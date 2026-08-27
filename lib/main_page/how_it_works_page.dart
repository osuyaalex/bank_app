import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/spend_repository.dart';
import '../data/migration_gate.dart';

const _ink = Color(0xff1C1939);
const _brand = Color(0xff5AA5E2);

/// What the app does, before it asks the user for anything.
///
/// Testers kept asking what a screen wanted from them, and the first of those
/// screens arrived with no context at all: a stranger asking for a budget and
/// permission to read their bank messages. This explains the whole loop first,
/// so every later screen is a step in something already understood rather than
/// an isolated demand.
class HowItWorksPage extends StatefulWidget {
  const HowItWorksPage({super.key});

  @override
  State<HowItWorksPage> createState() => _HowItWorksPageState();
}

class _HowItWorksPageState extends State<HowItWorksPage>
    with SingleTickerProviderStateMixin {
  /// One controller driving every entrance, so the steps arrive in sequence
  /// instead of all at once. The page reads as something being explained
  /// rather than a wall of text appearing.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  bool _saving = false;

  static const _steps = <_Step>[
    _Step(
      icon: Icons.pie_chart_outline_rounded,
      accent: Color(0xff5AA5E2),
      title: 'Choose what to budget for',
      body: 'Pick the things you spend on and say how much you plan to spend '
          'on each this month.',
    ),
    _Step(
      icon: Icons.sms_outlined,
      accent: Color(0xff7C5CE6),
      title: 'We read your bank alerts',
      body: 'The app looks at the transaction messages your bank already '
          'sends you. Nothing else is read.',
    ),
    _Step(
      icon: Icons.auto_awesome_outlined,
      accent: Color(0xff17A398),
      title: 'Your spending sorts itself',
      body: 'Each payment is matched to one of your budgets automatically. '
          'Where the app is unsure, it says so.',
    ),
    _Step(
      icon: Icons.notifications_active_outlined,
      accent: Color(0xffE8933D),
      title: 'You know before you overspend',
      body: 'Watch each budget fill up through the month, and get told when '
          'one is running out.',
    ),
  ];

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// A fade-and-rise that starts at [begin] through the shared timeline.
  Widget _enter(int index, Widget child) {
    final start = (index * 0.12).clamp(0.0, 0.7);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, (start + 0.45).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xffF7F8FB),
        body: Column(
          children: [
            _hero(width),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    _enter(i + 1,
                        _timelineRow(_steps[i], i, i == _steps.length - 1)),
                  const SizedBox(height: 6),
                  _enter(_steps.length + 1, _privacyNote()),
                ],
              ),
            ),
            _enter(_steps.length + 2, _cta()),
          ],
        ),
      ),
    );
  }

  Widget _hero(double width) => ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
              26, MediaQuery.of(context).padding.top + 22, 26, 26),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_ink, Color(0xff2E3B6B), _brand],
              stops: [0, 0.55, 1],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _enter(
                0,
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: SvgPicture.asset('assets/money-svgrepo-com.svg',
                          height: 19,
                          width: 19,
                          placeholderBuilder: (_) => const SizedBox(width: 19)),
                    ),
                    const SizedBox(width: 11),
                    Text('BANKAL',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            letterSpacing: 2.4,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              SizedBox(height: width * 0.055),
              _enter(
                0,
                const Text(
                  'Know where\nyour money goes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4),
                ),
              ),
              const SizedBox(height: 10),
              _enter(
                0,
                Text(
                  'Four steps. The first takes a minute — '
                  'the rest happen on their own.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13.8,
                      height: 1.45),
                ),
              ),
            ],
          ),
        ),
      );

  /// A step, joined to the next by a line.
  ///
  /// The connector is what makes this read as a sequence rather than four
  /// unrelated features -- the user is being shown a loop they will be walked
  /// through, in order, starting on the next screen.
  Widget _timelineRow(_Step step, int index, bool last) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: step.accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                        color: step.accent.withValues(alpha: 0.28), width: 1.2),
                  ),
                  child: Icon(step.icon, color: step.accent, size: 21),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            step.accent.withValues(alpha: 0.35),
                            step.accent.withValues(alpha: 0.06),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STEP ${index + 1}',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w800,
                            color: step.accent)),
                    const SizedBox(height: 5),
                    Text(step.title,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                            height: 1.25)),
                    const SizedBox(height: 6),
                    Text(step.body,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.48,
                            color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// Said plainly and early, because the very next screens ask for a budget
  /// and for permission to read SMS. Someone deciding whether to grant that
  /// deserves the answer before the dialog, not after.
  Widget _privacyNote() => Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 17, color: Colors.grey.shade500),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Only bank alerts are read. Your messages are never sent '
                'anywhere.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );

  Widget _cta() => Container(
        padding: EdgeInsets.fromLTRB(
            22, 14, 22, 18 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: const Color(0xffF7F8FB),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, -4)),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                  colors: [_brand, Color(0xff3E7FBF)]),
              boxShadow: [
                BoxShadow(
                    color: _brand.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: ElevatedButton(
              onPressed: _saving ? null : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Set up my budgets',
                            style: TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
            ),
          ),
        ),
      );

  Future<void> _start() async {
    setState(() => _saving = true);
    try {
      // Recorded before navigating, so this cannot reappear on the next
      // launch and read as the app forgetting.
      await SpendRepository().markIntroSeen();
    } catch (_) {
      // Not worth blocking the user over. Worst case they see it once more.
    }
    if (!mounted) return;
    // Asks where to go rather than naming a screen.
    //
    // A hardcoded destination here is how the old order survived being
    // changed everywhere else: the explainer walked straight past the gate,
    // so a new user was still asked to invent categories before a single
    // message had been read.
    final next = await MigrationGate.initialRoute(
        FirebaseAuth.instance.currentUser?.uid ?? '');
    if (mounted) context.go(next);
  }
}

class _Step {
  const _Step({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
}
