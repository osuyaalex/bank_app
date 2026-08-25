import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'migration.dart';
import 'sms_inbox.dart';
import 'spend_repository.dart';

/// Runs the schema migration once, then offers the batch-tag screen.
///
/// Called after the user is signed in and the first screen has rendered, so
/// nothing here sits on the critical path of a cold start.
class MigrationGate {
  MigrationGate._();

  static bool _started = false;

  /// At most once per app session.
  ///
  /// [SchemaMigration] is itself idempotent, so a second run would be
  /// harmless -- this guard exists to avoid re-reading the whole SMS inbox.
  /// Where to send the user on launch, decided before anything is drawn.
  ///
  /// One document read covers both questions. Deciding this after the summary
  /// has rendered -- which is what the summary's post-frame gate did -- means
  /// the user watches it flash past on the way somewhere else.
  static Future<String> initialRoute(String uid) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      final data = snap.data();

      final migration = SchemaMigration(FirebaseFirestore.instance, uid);
      if (await migration.needsMigration()) return '/preparing';
      // Data present and current, but the flag says nothing about whether the
      // batch screen was ever dealt with.
      if (data?['batchTagSeen'] != true) return '/batchTag';
      return '/deeplink/summary';
    } catch (_) {
      // Never strand the user on a blank screen because a read failed.
      return '/deeplink/summary';
    }
  }

  /// One-off repairs plus a totals refresh.
  ///
  /// Safe to call on every launch and from either entry point: the repairs are
  /// version-guarded and the rebuild is a sum, so repeating it changes nothing.
  static Future<void> runMaintenance(String uid) async {
    await _repairOnce(uid);
    try {
      final total =
          await SpendRepository(uid: uid).rebuildCurrentMonthTotals();
      print('TOTALS: rebuilt, month total=$total');
    } catch (e) {
      print('TOTALS rebuild failed: $e');
    }
  }

  /// Version of the orphaned-label repair that has already run.
  static const _repairVersion = 2;

  static Future<void> _repairOnce(String uid) async {
    final doc = FirebaseFirestore.instance.collection('Users').doc(uid);
    final done = (await doc.get()).data()?['repairVersion'] ?? 0;
    if (done >= _repairVersion) return;
    try {
      final repo = SpendRepository(uid: uid);
      print('REPAIR: ${await repo.repairOrphanedLabels()}');
      print('REPAIR: ${await repo.backfillMissingBudgets()}');
      await doc.set({'repairVersion': _repairVersion}, SetOptions(merge: true));
    } catch (e) {
      // Leave the marker unset so it retries next launch.
      print('REPAIR failed: $e');
    }
  }

  /// True once the user has saved or skipped the batch-tag screen.
  static Future<bool> _batchTagSettled(String uid) async {
    final snap =
        await FirebaseFirestore.instance.collection('Users').doc(uid).get();
    return snap.data()?['batchTagSeen'] == true;
  }

  static Future<void> maybeRun(BuildContext context) async {
    if (_started) return;
    _started = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // A first migration takes the better part of a minute. Rather than doing
      // it behind the summary -- where the user can tap into screens whose
      // data is being rewritten -- hand over to a screen that holds the
      // foreground and runs it there.
      final migration =
          SchemaMigration(FirebaseFirestore.instance, user.uid);
      if (await migration.needsMigration()) {
        if (!context.mounted) return;
        await context.push('/preparing');
        return;
      }

      final inbox = await SmsInbox.readForMigration();
      final report =
          await SchemaMigration(FirebaseFirestore.instance, user.uid).run(
        inbox: inbox,
        ownerName: user.displayName,
      );

      // The screen is offered until the user deals with it once. Gating on a
      // fresh migration alone would mean anyone who tapped Skip -- or who
      // migrated before the screen existed -- never saw it again.
      // Maintenance first. These have nothing to do with the batch screen,
      // so they must not sit behind its early returns -- a user who has
      // dismissed it would never get repaired data or refreshed totals.
      await runMaintenance(user.uid);

      if (await _batchTagSettled(user.uid)) return;
      final candidates = report.alreadyMigrated
          ? await SpendRepository(uid: user.uid).pendingTagCount()
          : report.batchTagCandidates.length;
      // One-time repair for transactions labelled into a category the user
      // never finished setting up. Runs once per device, then never again.
      if (candidates == 0) return;
      if (!context.mounted) return;

      // Awaited: the caller refreshes its counts once this returns, and
      // without the await it would read them while the screen is still open
      // and show the pre-tagging figure.
      await GoRouter.of(context).push('/batchTag');
    } catch (e) {
      // A migration failure must never stop the user reaching their data.
      // track_items is untouched and still authoritative, so the app works
      // exactly as before; the next launch will retry from where it stopped.
      // ignore: avoid_print
      print('MIGRATION FAILED: $e');
    }
  }

  /// Reads the inbox for backfill.
  ///
  /// Deliberately does not *request* the SMS permission. The app asks for it
  /// in its own flow, and hijacking that with a prompt the user cannot place
  /// would be worse than migrating without history: categories and past totals
  /// still move across, only the counterparty seeding is skipped.
}
