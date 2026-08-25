import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'category_picker.dart';

/// Shown while the app reads new bank messages, before the home screen
/// renders.
///
/// The scan changes the figures on screen, so running it behind an already
/// drawn page meant the numbers jumped a second or two after arriving. Holding
/// the foreground until it finishes trades a short wait for a screen that is
/// correct the moment it appears.
class ScanningView extends StatefulWidget {
  const ScanningView({super.key});

  @override
  State<ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<ScanningView>
    with TickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  /// Rotated on a timer rather than tied to progress. The scan has no
  /// meaningful percentage, and a progress bar that does not track anything
  /// is a lie told to fill space.
  static const _stages = [
    'Reading your bank messages',
    'Matching them to your tracks',
    'Adding up this month',
  ];
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    _cycle();
  }

  Future<void> _cycle() async {
    while (mounted && _stage < _stages.length - 1) {
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) setState(() => _stage++);
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBlue,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 160,
                width: 160,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_ripple, _spin]),
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      // Three ripples, offset in phase so one is always
                      // leaving as another arrives.
                      for (var i = 0; i < 3; i++)
                        _rippleCircle((_ripple.value + i / 3) % 1.0),
                      Transform.rotate(
                        angle: _spin.value * 2 * math.pi,
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: -_spin.value * 2 * math.pi,
                            child: const Icon(Icons.receipt_long_rounded,
                                color: brandBlue, size: 34),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 38),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, 0.25), end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  _stages[_stage],
                  key: ValueKey(_stage),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Just a moment',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rippleCircle(double t) {
    final eased = Curves.easeOut.transform(t);
    return Opacity(
      opacity: (1 - eased).clamp(0.0, 1.0) * 0.5,
      child: Container(
        width: 78 + eased * 82,
        height: 78 + eased * 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.75),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}
