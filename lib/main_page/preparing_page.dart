import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/migration.dart';
import '../data/sms_inbox.dart';
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

  Future<void> _run() async {
    var candidates = 0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final report =
            await SchemaMigration(FirebaseFirestore.instance, user.uid).run(
          inbox: await SmsInbox.readForMigration(),
          ownerName: user.displayName,
        );
        candidates = report.batchTagCandidates.length;
      }
    } catch (e) {
      // Never trap the user here: the app works exactly as before if this
      // fails, and the next launch retries.
      // ignore: avoid_print
      print('MIGRATION FAILED: $e');
    }

    if (!mounted) return;
    if (candidates > 0) {
      context.pushReplacement('/batchTag');
    } else {
      context.pop();
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
