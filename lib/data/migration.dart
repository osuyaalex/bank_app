import 'package:cloud_firestore/cloud_firestore.dart';

import '../parsing/bank_alert.dart';
import '../parsing/merchant_dictionary.dart';
import 'migration_plan.dart';
import 'models.dart';

/// One SMS handed to the migration. Keeps this file independent of the SMS
/// plugin so it can be driven from a test.
class InboxMessage {
  const InboxMessage({required this.id, required this.sender, required this.body});
  final String id;
  final String sender;
  final String body;
}

/// Moves a user from `track_items` to the per-user schema.
///
/// Three properties matter more than speed here:
///
/// * **Idempotent** -- re-running changes nothing, so a user who updates on
///   two devices is safe.
/// * **Resumable** -- a user backgrounding the app mid-run is a normal event,
///   not a corruption. Each step records its own completion.
/// * **Non-destructive** -- `track_items` is read and never written. It stays
///   the rollback path for as long as it is wanted.
class SchemaMigration {
  SchemaMigration(this.db, this.uid);

  final FirebaseFirestore db;
  final String uid;

  /// History:
  ///  * 2 -> 3: version 2 could mark itself complete while the SMS-derived
  ///    steps had been skipped, leaving users flagged as migrated with an
  ///    empty counterparty map.
  ///  * 3 -> 4: version 3 seeded from `getAllSms`, which since
  ///    flutter_sms_inbox 1.0.5 returns only the 200 most recent messages, so
  ///    the map covered a fortnight instead of a year.
  ///  * 4 -> 5: version 4 persisted every counterparty it saw, including the
  ///    two thirds seen only once, and predates the untracked-category
  ///    prompt.
  ///  * 5 -> 6: bank routing language was leaking into counterparty keys
  ///    (`ALAT TRANSFER FROM <you> TO <them>`, `POS Trf on <date> ...`),
  ///    splitting single people across several machine-looking entries.
  ///  * 6 -> 7: transactions recorded the raw truncated counterparty key
  ///    rather than the canonical one, so tagging could never find them and
  ///    they stayed pending forever.
  ///  * 7 -> 8: merchant keys carried the terminal reference the bank appends
  ///    per purchase, so one merchant arrived under dozens of keys and a tag
  ///    never matched the next transaction.
  ///  * 8 -> 9: no schema change. Deleting the collections for a clean test
  ///    leaves this field behind, and without a bump the migration would
  ///    consider itself done and skip rebuilding them.
  ///
  /// Re-running is safe: every step is idempotent, `track_items` is never
  /// written, and decisions the user has already made are preserved.
  static const currentVersion = 9;

  /// How far back to look for legacy month documents.
  ///
  /// The old ids (`August2026`) sit under a `track_items` parent that may not
  /// exist as a document, and Firestore will not list documents that were
  /// never written. Probing a bounded range of known-format ids is more
  /// reliable than trying to enumerate them.
  static const monthsToProbe = 36;

  /// The existing profile document, reused as the parent of the new tree.
  ///
  /// Note the capital U: the app already stores profiles in `Users`, and
  /// adding a lowercase `users` alongside it would leave two collections
  /// separated only by case, which Firestore treats as entirely distinct.
  DocumentReference<Map<String, dynamic>> get _user =>
      db.collection('Users').doc(uid);

  static const _legacyMonthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  List<String> _legacyIds(DateTime now) {
    final ids = <String>[];
    for (var i = 0; i < monthsToProbe; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      ids.add('${_legacyMonthNames[d.month - 1]}${d.year}');
    }
    return ids;
  }

  /// Completed steps, scoped to the schema version that recorded them.
  ///
  /// Without the version scope, bumping [currentVersion] would re-run the
  /// migration but still skip every step the previous version had marked done,
  /// which is exactly the state that needs repairing.
  Future<Set<String>> _done() async {
    final data = (await _user.get()).data();
    if (data == null) return {};
    if ((data['migrationStepsVersion'] ?? 0) != currentVersion) return {};
    return Set<String>.from(data['migrationSteps'] ?? const []);
  }

  Future<void> _markDone(String step) => _user.set({
        'migrationStepsVersion': currentVersion,
        'migrationSteps': FieldValue.arrayUnion([step]),
      }, SetOptions(merge: true));

  /// Whether [run] has real work to do.
  ///
  /// A cheap single read, so the caller can decide whether to put a progress
  /// screen in front of the user before committing to a half-minute of work.
  Future<bool> needsMigration() async {
    final snap = await _user.get();
    if (((snap.data()?['schemaVersion'] ?? 0) as int) < currentVersion) {
      return true;
    }

    // The version says migrated, but the data it describes may be gone --
    // collections deleted for a clean test, or an account restored from
    // nothing. Without this the app trusts the flag, skips the migration and
    // shows empty screens.
    //
    // Probed on counterparties rather than months: `rebuildCurrentMonthTotals`
    // writes a month document on every run, so that collection is recreated by
    // the app itself moments after being deleted and can never look missing.
    final seeded = await _user.collection('counterparties').limit(1).get();
    return seeded.docs.isEmpty;
  }

  /// Runs any steps that have not completed yet.
  ///
  /// [inbox] is the device's SMS, used to backfill transactions and seed the
  /// counterparty map. Pass **null** when the inbox could not be read -- for
  /// instance when the SMS permission has not been granted yet. That is a
  /// recoverable condition, not a finished migration: the SMS-derived steps
  /// are left undone and the schema version is not advanced, so the next
  /// launch retries. An empty list, by contrast, means the inbox really is
  /// empty and the migration is complete.
  ///
  /// [ownerName] drives the self-transfer proposal.
  Future<MigrationReport> run({
    required List<InboxMessage>? inbox,
    String? ownerName,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();

    // Deliberately the same question [needsMigration] answers. Checking the
    // version here instead meant the two disagreed whenever the data had been
    // deleted: the router sent the user to the progress screen because the
    // data was gone, and this returned "already migrated" because the flag
    // said so -- so nothing was rebuilt, and the screen it returned to asked
    // again, round and round.
    if (!await needsMigration()) {
      return const MigrationReport(alreadyMigrated: true);
    }

    var done = await _done();

    // A step marked complete whose output is missing has to run again.
    // Otherwise a write that was recorded but never landed -- Firestore
    // briefly unavailable, or the collection deleted afterwards -- leaves the
    // step permanently ticked off and the data permanently absent, and every
    // later run skips the very work that would fix it.
    final seeded = await _user.collection('counterparties').limit(1).get();
    if (seeded.docs.isEmpty) {
      // Every step, not a chosen few. An empty counterparties collection means
      // the migration's output is gone -- deleted, or written while Firestore
      // was unavailable -- so no step marker can be trusted. Un-ticking only
      // some of them left categories permanently unwritten, which emptied the
      // category picker.
      done = <String>{};
      // ignore: avoid_print
      print('MIGRATION: output missing, re-running every step');
    }

    final legacy = await _readLegacy(today);

    if (!done.contains('categories')) {
      await _writeCategories(legacy);
      await _markDone('categories');
    }
    if (!done.contains('months')) {
      await _writeMonths(legacy, today);
      await _markDone('months');
    }

    if (inbox == null) {
      // Categories and months are done; the SMS-derived steps are not, and
      // the version stays put so this runs again once the inbox is readable.
      return MigrationReport(
        legacyMonths: legacy.length,
        awaitingInbox: true,
      );
    }

    final alerts = _parseInbox(inbox);
    final map = canonicaliseKeys(
        seedCounterparties(alerts.values, ownerName: ownerName));

    if (!done.contains('counterparties')) {
      final persist = worthPersisting(map);
      // ignore: avoid_print
      print('MIGRATION: seeded=${map.length} persisting=${persist.length}');
      await _writeCounterparties(persist);
      final check = await _user.collection('counterparties').limit(5).get();
      // ignore: avoid_print
      print('MIGRATION: counterparties readback=${check.docs.length}');
      await _markDone('counterparties');
    }
    if (!done.contains('backfill')) {
      await _backfillCurrentMonth(alerts, map, today);
      await _markDone('backfill');
    }

    // Only now is the migration genuinely finished.
    //
    // `batchTagSeen` is cleared deliberately: a fresh migration has just
    // rebuilt the counterparty map, which is exactly when the batch-tag
    // screen is worth offering again -- including to someone who dismissed it
    // under an older schema.
    await _user.set({
      'schemaVersion': currentVersion,
      'batchTagSeen': false,
    }, SetOptions(merge: true));

    return MigrationReport(
      legacyMonths: legacy.length,
      counterparties: map.length,
      batchTagCandidates: batchTagCandidates(map),
    );
  }

  Future<Map<String, List<dynamic>>> _readLegacy(DateTime now) async {
    final out = <String, List<dynamic>>{};
    for (final id in _legacyIds(now)) {
      final doc = await db
          .collection('track_items')
          .doc(id)
          .collection('monthUsers')
          .doc(uid)
          .get();
      final items = doc.data()?['listItems'];
      if (items is List && items.isNotEmpty) out[id] = items;
    }
    return out;
  }

  Future<void> _writeCategories(Map<String, List<dynamic>> legacy) async {
    final cats = categoriesFromLegacy(legacy.values);
    final batch = db.batch();
    for (final c in cats) {
      // merge: a re-run must not clobber a rename the user has since made.
      batch.set(_user.collection('categories').doc(c.id), c.toMap(),
          SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _writeMonths(
      Map<String, List<dynamic>> legacy, DateTime now) async {
    final currentKey = monthKeyOf(now);
    final batch = db.batch();
    legacy.forEach((legacyId, items) {
      final key = legacyMonthKey(legacyId);
      if (key == null) return;
      final ledger =
          ledgerFromLegacy(key, items, closed: key != currentKey);
      batch.set(_user.collection('months').doc(key), ledger.toMap(),
          SetOptions(merge: true));
    });
    await batch.commit();
  }

  Map<String, BankAlert> _parseInbox(List<InboxMessage> inbox) {
    final out = <String, BankAlert>{};
    for (final m in inbox) {
      final a = parseAlert(m.sender, m.body);
      if (a != null) out[m.id] = a;
    }
    return out;
  }

  /// Writes the seeded counterparties without disturbing existing decisions.
  ///
  /// A re-run must never reset a counterparty the user has already tagged back
  /// to [Disposition.ask] -- silently undoing their work would be worse than
  /// not re-running at all. For entries that already exist, only the
  /// observational fields are refreshed.
  Future<void> _writeCounterparties(Map<String, CounterpartyEntry> map) async {
    final existing = await _user.collection('counterparties').get();
    final known = {for (final d in existing.docs) d.id};

    await _commitChunked(map.values, (batch, e) {
      final ref =
          _user.collection('counterparties').doc(counterpartyDocId(e.key));
      if (known.contains(ref.id)) {
        batch.set(
            ref,
            {
              'txCount': e.txCount,
              'aliases': e.aliases,
              'lastSeen': e.lastSeen?.toIso8601String(),
            },
            SetOptions(merge: true));
      } else {
        batch.set(ref, e.toMap(), SetOptions(merge: true));
      }
    });
  }

  /// Backfills the current month only.
  ///
  /// Closed months keep the totals the user has already seen; re-deriving them
  /// would silently change history. The current month is rebuilt so the switch
  /// feature has real transactions to operate on from day one.
  Future<void> _backfillCurrentMonth(
    Map<String, BankAlert> alerts,
    Map<String, CounterpartyEntry> map,
    DateTime now,
  ) async {
    final key = monthKeyOf(now);
    final month = _user.collection('months').doc(key);

    // Recognised merchants file themselves here too. Without this the
    // dictionary would only ever apply to transactions arriving after the
    // migration, leaving everything already backfilled sitting in the sorting
    // list even when the merchant is one anybody would recognise.
    final tracked = await _trackedCategoryNames();
    final entries = alerts.entries.where((e) =>
        e.value.occurredAt != null && monthKeyOf(e.value.occurredAt!) == key);

    await _commitChunked(entries, (batch, e) {
      final suggestion = e.value.counterpartyKey == null
          ? null
          : suggestCategoryName(e.value.counterpartyKey!, tracked);
      final record = recordFor(
        e.key,
        e.value,
        map,
        suggestedCategoryId:
            suggestion == null ? null : slugifyCategory(suggestion),
      );
      batch.set(month.collection('transactions').doc(e.key), record.toMap(),
          SetOptions(merge: true));
    });
  }

  /// Category names tracked in the current month, read from the legacy
  /// document since that is where the category screens still write.
  Future<Set<String>> _trackedCategoryNames() async {
    final legacyId =
        '${_legacyMonthNames[DateTime.now().month - 1]}${DateTime.now().year}';
    final doc = await db
        .collection('track_items')
        .doc(legacyId)
        .collection('monthUsers')
        .doc(uid)
        .get();
    final items = doc.data()?['listItems'];
    if (items is! List) return {};
    return {
      for (final item in items)
        if (item is Map && item['name'] != null) item['name'].toString(),
    };
  }

  /// Firestore caps a batch at 500 writes.
  Future<void> _commitChunked<T>(
    Iterable<T> items,
    void Function(WriteBatch, T) write,
  ) async {
    var batch = db.batch();
    var n = 0;
    for (final item in items) {
      write(batch, item);
      if (++n == 400) {
        await batch.commit();
        batch = db.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }
}

class MigrationReport {
  const MigrationReport({
    this.alreadyMigrated = false,
    this.awaitingInbox = false,
    this.legacyMonths = 0,
    this.counterparties = 0,
    this.batchTagCandidates = const [],
  });

  final bool alreadyMigrated;

  /// True when the migration stopped short because the SMS inbox could not be
  /// read. It will resume on a later launch.
  final bool awaitingInbox;
  final int legacyMonths;
  final int counterparties;
  final List<CounterpartyEntry> batchTagCandidates;
}
