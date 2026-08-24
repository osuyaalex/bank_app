import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../parsing/bank_alert.dart';
import 'migration_plan.dart';
import 'models.dart';

/// Reads and writes the per-user schema under `Users/{uid}`.
class SpendRepository {
  SpendRepository({FirebaseFirestore? db, String? uid})
      : db = db ?? FirebaseFirestore.instance,
        uid = uid ?? FirebaseAuth.instance.currentUser!.uid;

  final FirebaseFirestore db;
  final String uid;

  Map<String, CounterpartyEntry>? _map;

  /// The counterparty map, loaded once per repository instance.
  ///
  /// A scan processes many messages, and re-reading the map for each one would
  /// turn one read into dozens.
  Future<Map<String, CounterpartyEntry>> counterparties() async =>
      _map ??= await loadCounterparties();

  DocumentReference<Map<String, dynamic>> get _user =>
      db.collection('Users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _counterparties =>
      _user.collection('counterparties');

  DocumentReference<Map<String, dynamic>> monthRef(String monthKey) =>
      _user.collection('months').doc(monthKey);

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Future<List<Category>> loadCategories() async {
    final snap = await _user.collection('categories').get();
    return snap.docs
        .map((d) => Category(
              id: d.data()['id'] ?? d.id,
              name: d.data()['name'] ?? d.id,
              image: d.data()['image'],
              active: d.data()['active'] ?? true,
            ))
        .toList();
  }

  Future<Map<String, CounterpartyEntry>> loadCounterparties() async {
    final snap = await _counterparties.get();
    final out = <String, CounterpartyEntry>{};
    for (final d in snap.docs) {
      final m = d.data();
      final key = (m['key'] ?? d.id).toString();
      out[key] = CounterpartyEntry(
        key: key,
        categoryId: m['categoryId'],
        disposition: Disposition.values.firstWhere(
          (v) => v.name == m['disposition'],
          orElse: () => Disposition.ask,
        ),
        overrideCount: (m['overrideCount'] ?? 0) as int,
        txCount: (m['txCount'] ?? 0) as int,
        aliases: List<String>.from(m['aliases'] ?? const []),
      );
    }
    return out;
  }

  /// The legacy month document, which is still what the app displays.
  DocumentReference<Map<String, dynamic>> get _legacyMonth {
    final key = DateFormat('MMMM yyyy').format(DateTime.now()).replaceAll(' ', '');
    return db
        .collection('track_items')
        .doc(key)
        .collection('monthUsers')
        .doc(uid);
  }

  /// Names of the categories being tracked *this month*.
  ///
  /// Read from the legacy document rather than the new schema: the category
  /// screens still write only to `track_items`, so it is the one place
  /// guaranteed to be current.
  Future<Set<String>> trackedCategoryNames() async {
    final items = (await _legacyMonth.get()).data()?['listItems'];
    if (items is! List) return {};
    return {
      for (final raw in items)
        if (raw is Map && raw['name'] != null) raw['name'].toString(),
    };
  }

  /// Starts tracking [name] for the current month.
  ///
  /// Writes to both schemas: the legacy list the app renders from, and the
  /// new categories plus this month's budget. Without the legacy write the
  /// category would be invisible until the cutover.
  Future<Category> startTracking({
    required String name,
    String budget = '0',
    String image = '',
  }) async {
    final category = Category.fromName(name, image: image);

    await _legacyMonth.set({
      'listItems': FieldValue.arrayUnion([
        {
          'image': image,
          'name': name,
          'description': '',
          'dailySpend': 0.0,
          'budgetSet': budget,
          'totalAmountSpent': 0.0,
          'currentMonth': DateFormat.MMMM().format(DateTime.now()),
          'previousDailySpends': <dynamic>[],
          'lastResetTime': Timestamp.now(),
        }
      ]),
    }, SetOptions(merge: true));

    await _user
        .collection('categories')
        .doc(category.id)
        .set(category.toMap(), SetOptions(merge: true));

    await monthRef(monthKeyOf(DateTime.now())).set({
      'budgets': {
        category.id: double.tryParse(budget.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0
      }
    }, SetOptions(merge: true));

    return category;
  }

  /// The currency symbol the user's month was set up with.
  Future<String> currencySymbol() async =>
      (await _legacyMonth.get()).data()?['currency']?.toString() ?? '';

  /// Transactions in [monthKey] still waiting for the user to say what they
  /// were, newest first.
  Future<List<TransactionRecord>> pendingTransactions({String? monthKey}) async {
    final snap = await monthRef(monthKey ?? monthKeyOf(DateTime.now()))
        .collection('transactions')
        .where('status', isEqualTo: TxnStatus.pending.name)
        .get();

    final rows = snap.docs.map((d) {
      final m = d.data();
      return TransactionRecord(
        smsId: d.id,
        bank: m['bank'] ?? '',
        kind: AlertKind.debit,
        channel: TxnChannel.values.firstWhere(
            (v) => v.name == m['channel'], orElse: () => TxnChannel.unknown),
        status: TxnStatus.pending,
        amount: (m['amount'] as num?)?.toDouble(),
        occurredAt: DateTime.tryParse(m['occurredAt'] ?? ''),
        narration: m['narration'] ?? '',
        counterpartyKey: m['counterpartyKey'],
      );
    }).toList();

    rows.sort((a, b) => (b.occurredAt ?? DateTime(0))
        .compareTo(a.occurredAt ?? DateTime(0)));
    return rows;
  }

  Future<int> pendingCount({String? monthKey}) async =>
      (await pendingTransactions(monthKey: monthKey)).length;

  /// The categories to offer as one-tap answers on a notification.
  ///
  /// Android allows three action buttons, so this returns the three the user
  /// spends most through -- the likeliest answers, and they adapt as habits
  /// change. Only categories actually tracked this month are offered: a button
  /// that files money somewhere invisible would be worse than no button.
  Future<List<Category>> quickPickCategories({int limit = 3}) async {
    final items = (await _legacyMonth.get()).data()?['listItems'];
    if (items is! List) return const [];

    final ranked = <MapEntry<String, double>>[];
    for (final raw in items) {
      if (raw is! Map || raw['name'] == null) continue;
      final spent = (raw['totalAmountSpent'] as num?)?.toDouble() ?? 0;
      final daily = (raw['dailySpend'] as num?)?.toDouble() ?? 0;
      ranked.add(MapEntry(raw['name'].toString(), spent + daily));
    }
    ranked.sort((a, b) => b.value.compareTo(a.value));

    return [
      for (final e in ranked.take(limit)) Category.fromName(e.key),
    ];
  }

  /// Files a single transaction, moving both schemas.
  ///
  /// [alsoRemember] upserts the counterparty so the next transaction from them
  /// files itself. Answering from a notification always remembers; correcting
  /// a one-off might not.
  Future<void> labelTransaction({
    required String smsId,
    required String categoryId,
    required String categoryName,
    String? counterpartyKey,
    bool alsoRemember = true,
    String? monthKey,
  }) async {
    final key = monthKey ?? monthKeyOf(DateTime.now());
    final month = monthRef(key);
    final txRef = month.collection('transactions').doc(smsId);

    final amount = await db.runTransaction<double>((tx) async {
      final snap = await tx.get(txRef);
      if (!snap.exists) return 0;
      if (snap.data()?['status'] != TxnStatus.pending.name) return 0;
      final value = (snap.data()?['amount'] as num?)?.toDouble() ?? 0;
      tx.update(txRef, {
        'status': TxnStatus.labeled.name,
        'categoryId': categoryId,
        'source': LabelSource.user.name,
      });
      tx.set(month, {'spend': {categoryId: FieldValue.increment(value)}},
          SetOptions(merge: true));
      return value;
    });

    if (amount == 0) return; // already answered elsewhere

    await _addToLegacyDailySpend(categoryName, amount);

    if (alsoRemember && counterpartyKey != null) {
      await _counterparties.doc(counterpartyDocId(counterpartyKey)).set({
        'key': counterpartyKey,
        'categoryId': categoryId,
        'disposition': Disposition.tracked.name,
      }, SetOptions(merge: true));
      _map = null;
    }
  }

  /// Mirrors a label into the legacy list the app still renders from.
  ///
  /// Without this the user answers a prompt and nothing on screen changes,
  /// which reads as the feature being broken. Matched on category *name*,
  /// since that is all the old schema records.
  Future<void> _addToLegacyDailySpend(String categoryName, double amount) async {
    await db.runTransaction((tx) async {
      final snap = await tx.get(_legacyMonth);
      final items = List<dynamic>.from(snap.data()?['listItems'] ?? const []);
      var touched = false;
      for (final item in items) {
        if (item is Map &&
            item['name'].toString().toLowerCase() ==
                categoryName.toLowerCase()) {
          item['dailySpend'] =
              ((item['dailySpend'] as num?)?.toDouble() ?? 0) + amount;
          touched = true;
          break;
        }
      }
      // Not tracked this month: the tag is still remembered, but there is
      // nowhere on screen for the money to go.
      if (touched) tx.update(_legacyMonth, {'listItems': items});
    });
  }

  /// How many counterparties are still worth putting in front of the user.
  Future<int> pendingTagCount({int limit = 20}) async =>
      batchTagCandidates(await loadCounterparties(), limit: limit).length;

  /// Records that the user has saved or skipped the batch-tag screen, so it
  /// is not shown again on every launch.
  Future<void> markBatchTagSeen() =>
      _user.set({'batchTagSeen': true}, SetOptions(merge: true));

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// Records one parsed alert and moves the month's totals.
  ///
  /// Idempotent by construction: the transaction document is keyed by the SMS
  /// id, and the totals are only advanced when that document did not already
  /// exist. Re-scanning the inbox therefore cannot double-count, which matters
  /// because the periodic task re-reads the same messages every two hours.
  /// Returns the record written, or null if this SMS was already counted.
  Future<TransactionRecord?> recordTransaction({
    required String smsId,
    required BankAlert alert,
    required Map<String, CounterpartyEntry> map,
  }) async {
    final record = recordFor(smsId, alert, map, source: LabelSource.map);
    final month = monthRef(monthKeyOf(alert.occurredAt ?? DateTime.now()));
    final txRef = month.collection('transactions').doc(smsId);
    final amount = record.amount ?? 0;

    final written = await db.runTransaction<bool>((tx) async {
      final existing = await tx.get(txRef);
      if (existing.exists) return false; // already counted
      tx.set(txRef, record.toMap());

      if (record.countsAsSpending && record.categoryId != null) {
        tx.set(
            month,
            {
              'spend': {record.categoryId!: FieldValue.increment(amount)}
            },
            SetOptions(merge: true));
      } else if (alert.kind == AlertKind.charge) {
        // Visible to the user, deliberately outside every budget.
        tx.set(month, {'charges': FieldValue.increment(amount)},
            SetOptions(merge: true));
      } else if (alert.kind == AlertKind.debit &&
          record.status == TxnStatus.excluded) {
        // Money moved between the user's own accounts.
        tx.set(month, {'excluded': FieldValue.increment(amount)},
            SetOptions(merge: true));
      }
      return true;
    });

    return written ? record : null;
  }

  /// Applies a decision about a counterparty and settles the transactions
  /// already waiting on it.
  ///
  /// Used by the batch-tag screen and, later, by the per-transaction prompt.
  Future<int> tagCounterparty({
    required String key,
    required Disposition disposition,
    String? categoryId,
    String? monthKey,
  }) async {
    await _counterparties.doc(counterpartyDocId(key)).set({
      'key': key,
      'categoryId': categoryId,
      'disposition': disposition.name,
      'lastSeen': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    _map = null; // later writes must see this decision
    return _settlePending(
      key: key,
      disposition: disposition,
      categoryId: categoryId,
      monthKey: monthKey ?? monthKeyOf(DateTime.now()),
    );
  }

  /// Labels the pending transactions for [key] in one month.
  ///
  /// Queried on `counterpartyKey` alone and filtered in memory: a second
  /// equality clause on `status` would require a composite index, which is a
  /// console step this does not need.
  Future<int> _settlePending({
    required String key,
    required Disposition disposition,
    required String? categoryId,
    required String monthKey,
  }) async {
    final month = monthRef(monthKey);

    // Records written before keys were canonicalised carry a truncated
    // spelling, so match the aliases as well or those stay pending forever.
    final entry = (await counterparties())[key];
    final keys = <String>{key, ...?entry?.aliases}.take(30).toList();

    final snap = await month
        .collection('transactions')
        .where('counterpartyKey', whereIn: keys)
        .get();

    final pending = snap.docs
        .where((d) => d.data()['status'] == TxnStatus.pending.name)
        .toList();
    if (pending.isEmpty) return 0;

    final batch = db.batch();
    final increments = <String, double>{};
    var excluded = 0.0;

    for (final d in pending) {
      final amount = (d.data()['amount'] as num?)?.toDouble() ?? 0;
      if (disposition == Disposition.tracked && categoryId != null) {
        batch.update(d.reference, {
          'status': TxnStatus.labeled.name,
          'categoryId': categoryId,
          'source': LabelSource.user.name,
        });
        increments[categoryId] = (increments[categoryId] ?? 0) + amount;
      } else if (disposition == Disposition.notSpending) {
        batch.update(d.reference, {'status': TxnStatus.excluded.name});
        excluded += amount;
      }
    }

    if (increments.isNotEmpty || excluded > 0) {
      batch.set(
          month,
          {
            if (increments.isNotEmpty)
              'spend': increments
                  .map((k, v) => MapEntry(k, FieldValue.increment(v))),
            if (excluded > 0) 'excluded': FieldValue.increment(excluded),
          },
          SetOptions(merge: true));
    }

    await batch.commit();

    // Mirror into the legacy list the app renders from, or the user answers
    // and sees nothing change.
    if (increments.isNotEmpty) {
      final names = {for (final c in await loadCategories()) c.id: c.name};
      for (final e in increments.entries) {
        final name = names[e.key];
        if (name != null) await _addToLegacyDailySpend(name, e.value);
      }
    }

    return pending.length;
  }

  /// Mirrors a legacy write into the new schema.
  ///
  /// Called alongside the existing `track_items` write for one release, so the
  /// old collection stays correct and current and remains a working rollback
  /// path while the new schema is proven in production.
  Future<TransactionRecord?> mirrorLegacyWrite({
    required String smsId,
    required BankAlert? alert,
  }) async {
    if (alert == null) return null;
    try {
      return await recordTransaction(
          smsId: smsId, alert: alert, map: await counterparties());
    } catch (e) {
      // The legacy write is still the source of truth this release, so a
      // failure here must never break the user's tracking.
      // ignore: avoid_print
      print('mirror write failed for $smsId: $e');
      return null;
    }
  }
}
