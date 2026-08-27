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

      final repo = SpendRepository(uid: uid);
      final tracked = await repo.trackedCategoryNames();

      // Budgets come first, and the order is not cosmetic. A transaction is
      // filed by matching it to a category that already exists, so a user who
      // reaches the scan with none gets nothing matched and has to tag every
      // row by hand.
      if (tracked.isEmpty) {
        // The explainer runs once, ahead of the first thing the app asks for.
        // Its absence is what had testers asking what a screen wanted from
        // them before they knew what the app was.
        if (data?['introSeen'] != true) return '/intro';

        // Read the messages before asking for a single category.
        //
        // The order used to be the other way round, and it was the root of
        // the confusion on the sorting screen rather than anything on that
        // screen itself. A new user was handed twenty-nine abstract nouns,
        // asked to choose some and invent a budget for each, and only then
        // shown their spending. They chose blind -- three or four -- and
        // arrived at twenty-two payments matching none of them.
        //
        // Scanning first means the categories can come from what they
        // already spend, with the figures worked out, and there is nothing
        // to invent.
        final migration = SchemaMigration(FirebaseFirestore.instance, uid);
        if (await migration.needsMigration()) return '/preparing';
        return '/trackItems';
      }

      // A new month. The categories and figures have been carried forward, so
      // the screen arrives filled in and confirming is one tap -- but it is
      // shown, because a budget nobody revisits stops being a plan.
      if (!await repo.budgetsConfirmedThisMonth()) return '/trackItems';

      final migration = SchemaMigration(FirebaseFirestore.instance, uid);
      if (await migration.needsMigration()) return '/preparing';

      // Closing the screen is permanent, by either button. Anyone who has
      // done so goes straight in, and the rescan happens quietly behind the
      // summary instead of behind an animation they did not ask to watch.
      if (data?['batchTagDismissed'] == true) return '/deeplink/summary';

      // Otherwise the offer stands -- but only bother if there is something
      // to offer. The scan screen is the way in to the batch screen and is
      // never shown on its own account: making the user watch it on every
      // launch only to land on the summary would be a delay dressed up as
      // work.
      if (await repo.pendingTagCount() > 0) return '/preparing';
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
  static const _repairVersion = 5;

  static Future<void> _repairOnce(String uid) async {
    final doc = FirebaseFirestore.instance.collection('Users').doc(uid);
    final done = (await doc.get()).data()?['repairVersion'] ?? 0;
    if (done >= _repairVersion) return;
    try {
      final repo = SpendRepository(uid: uid);
      print('REPAIR: ${await repo.repairOrphanedLabels()}');
      print('REPAIR: ${await repo.backfillMissingBudgets()}');
      // Releases transfers the user made to their own accounts, which a
      // faulty name guard had filed as spending on a relative.
      print('REPAIR: self-transfers released ${await repo.repairSelfTransfers()}');
      print('REPAIR: duplicate categories merged '
          '${await repo.mergeDuplicateCategories()}');
      // Money that left and came back was still counted as spent.
      print('REPAIR: reversals netted ${await repo.repairReversals()}');
      await doc.set({'repairVersion': _repairVersion}, SetOptions(merge: true));
    } catch (e) {
      // Leave the marker unset so it retries next launch.
      print('REPAIR failed: $e');
    }
  }

  /// True once the user has closed the batch-tag screen.
  static Future<bool> _batchTagSettled(String uid) async {
    final snap =
        await FirebaseFirestore.instance.collection('Users').doc(uid).get();
    return snap.data()?['batchTagDismissed'] == true;
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
        ownerName: await SpendRepository(uid: user.uid).ownerName(),
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
