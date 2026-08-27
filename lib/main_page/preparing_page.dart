import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/migration.dart';
import '../data/migration_gate.dart';
import '../data/sms_inbox.dart';
import '../firebase network/sms_service.dart';
import '../data/spend_repository.dart';
import 'widget/category_picker.dart';

/// Shown while the first migration runs.
///
/// The work takes the better part of a minute, and leaving the user on the
/// summary during it invites them to tap into screens whose data is being
/// rewritten underneath them. This holds the foreground until it is safe.
class PreparingPage extends StatefulWidget {
  const PreparingPage({super.key});

  @override
  State<PreparingPage> createState() => _PreparingPageState();
}

class _PreparingPageState extends State<PreparingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// Rotated on a timer rather than tied to real progress: the migration has
  /// no meaningful percentage, and a fake progress bar would be a lie.
  static const _stages = [
    'Reading your bank messages',
    'Working out who you pay most',
    'Sorting your spending',
    'Almost there',
  ];
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    _cycleStages();
    _run();
  }

  Future<void> _cycleStages() async {
    while (mounted && _stage < _stages.length - 1) {
      await Future.delayed(const Duration(seconds: 6));
      if (mounted) setState(() => _stage++);
    }
  }

  /// Asks for SMS access before anything tries to read the inbox.
  ///
  /// Nothing in the foreground used to ask. The only request lived in the
  /// two-hourly background scan, where an isolate cannot show a dialog, so a
  /// new user was never prompted: the migration read nothing, reported
  /// "awaiting inbox", and dropped them on an empty app with no explanation.
  ///
  /// Returns false when the user says no, which is a legitimate answer -- they
  /// can still budget by hand, and the batch screen says what they are missing.
  Future<bool> _ensureSmsAccess() async {
    try {
      if (await Permission.sms.isGranted) return true;
      final status = await Permission.sms.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _run() async {
    var candidates = 0;
    var needsSetup = false;
    try {
      // Before the migration, not after: it is what makes the inbox readable.
      await _ensureSmsAccess();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final repo = SpendRepository(uid: user.uid);
        final migration =
            SchemaMigration(FirebaseFirestore.instance, user.uid);

        if (await migration.needsMigration()) {
          final report = await migration.run(
            inbox: await SmsInbox.readForMigration(),
            ownerName: await repo.ownerName(),
          );
          // One line describing the outcome. Enough to explain a support
          // report, without narrating every step.
          // ignore: avoid_print
          print('MIGRATION: months=${report.legacyMonths} '
              'counterparties=${report.counterparties}'
              '${report.awaitingInbox ? " (awaiting inbox)" : ""}');
        } else {
          // Already migrated, so this screen is here to refresh rather than
          // rebuild: pick up the alerts that have arrived since the last
          // scan, which is what makes new counterparties worth offering.
          await SmsService().getSmsMessages();
        }

        // This path returns straight to the app without passing back through
        // the gate, so the same maintenance has to happen here.
        await MigrationGate.runMaintenance(user.uid);
        // Creates the month document the deleted track-items screen used to
        // write, carrying last month's budgets forward where there are any.
        await repo.ensureMonthInitialised();

        needsSetup = (await repo.trackedCategoryNames()).isEmpty;
        // Recomputed from the map as it stands now. Reading it off the
        // migration report only worked on the run that did the migrating;
        // every later entry reported zero and sent the user past the screen.
        candidates = await repo.pendingTagCount();
        // ignore: avoid_print
        print('SCAN: candidates=$candidates needsSetup=$needsSetup');
      }
    } catch (e) {
      // Never trap the user here: the app works exactly as before if this
      // fails, and the next launch retries.
      // ignore: avoid_print
      print('SCAN FAILED: $e');
    }

    if (!mounted) return;
    // Reached by `go` from the root, so there is nothing beneath to pop back
    // to. Hand straight to the batch screen, or to the summary when the scan
    // turned nothing up.
    if (candidates > 0 || needsSetup) {
      // Somebody with no categories has just had their inbox read so the
      // setup screen can propose some. Send them there, not to a sorting
      // screen with nothing to sort into.
      if ((await SpendRepository().trackedCategoryNames()).isEmpty) {
        if (!context.mounted) return;
        context.pushReplacement('/trackItems');
        return;
      }
      if (!context.mounted) return;
      context.pushReplacement('/batchTag');
    } else {
      context.go('/deeplink/summary');
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: brandBlue,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) {
                      final t = Curves.easeInOut.transform(_pulse.value);
                      return Container(
                        width: 108 + t * 16,
                        height: 108 + t * 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14 + t * 0.10),
                        ),
                        child: Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: Colors.white),
                            child: const Icon(Icons.auto_awesome,
                                color: brandBlue, size: 32),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'Getting your spending together',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _stages[_stage],
                      key: ValueKey(_stage),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  SizedBox(
                    width: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'This only happens once',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
