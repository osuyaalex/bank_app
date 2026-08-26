import 'package:flutter/material.dart';

import 'category_picker.dart' show brandBlue;

/// A category the app thinks fits but the user does not track yet.
///
/// Drawn as an outline rather than a solid chip, so it reads as *offered*
/// rather than *chosen*: the same shape as a real category, visibly not one
/// yet. Tapping it asks only for a budget -- the app already knows the name,
/// and making the user find "Add more", type "Family" and then set an amount
/// is three steps to reach something it could have proposed.
///
/// It breathes slowly instead of flashing. A blink pulls the eye away from
/// whatever the user is reading; a slow fade is noticed on the way past and
/// ignorable if they are busy.
class GhostChip extends StatefulWidget {
  const GhostChip({
    super.key,
    required this.label,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Tighter, for use inside a transaction row rather than a picker.
  final bool dense;

  @override
  State<GhostChip> createState() => _GhostChipState();
}

class _GhostChipState extends State<GhostChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.dense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          final t = 0.35 + (_breath.value * 0.45);
          return Container(
            padding: pad,
            decoration: BoxDecoration(
              color: brandBlue.withValues(alpha: 0.05 + _breath.value * 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: brandBlue.withValues(alpha: t),
                width: 1.3,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded,
                size: widget.dense ? 14 : 16, color: brandBlue),
            SizedBox(width: widget.dense ? 5 : 7),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.dense ? 12.5 : 14,
                color: brandBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains what a ghost chip is, once, where one first appears.
class GhostHint extends StatelessWidget {
  const GhostHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Colors.grey.shade600)),
          ),
        ],
      );
}
