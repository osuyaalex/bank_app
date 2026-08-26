import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'category_picker.dart' show brandBlue;

/// One instruction on a screen.
class GuideStep {
  const GuideStep(this.text);
  final String text;
}

/// A short "here is what to do on this screen" panel.
///
/// Testers kept asking what a screen wanted from them. The app knew the
/// answer on every screen and never said it, so this puts it where the
/// question gets asked -- at the top, before the first tap, in the user's
/// words rather than the app's.
///
/// Shown by default and dismissible, remembered per screen so it explains
/// itself once rather than nagging. [GuideButton] brings it back for anyone
/// who dismissed it and then wanted it.
class ScreenGuide extends StatefulWidget {
  const ScreenGuide({
    super.key,
    required this.id,
    required this.title,
    required this.steps,
    this.footnote,
  });

  /// Identifies this guide in storage. Stable, so dismissing it sticks.
  final String id;
  final String title;
  final List<GuideStep> steps;

  /// An extra reassurance below the steps, where one helps.
  final String? footnote;

  static String _key(String id) => 'guide_dismissed_$id';

  static Future<bool> isDismissed(String id) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(id)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismiss(String id) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(id), true);
    } catch (_) {/* a guide that will not stay dismissed is survivable */}
  }

  static Future<void> restore(String id) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key(id));
    } catch (_) {}
  }

  @override
  State<ScreenGuide> createState() => _ScreenGuideState();
}

class _ScreenGuideState extends State<ScreenGuide> {
  /// Null while unknown, so the panel never flashes in and out on load.
  bool? _dismissed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dismissed = await ScreenGuide.isDismissed(widget.id);
    if (mounted) setState(() => _dismissed = dismissed);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed != false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: guidePanel(
        title: widget.title,
        steps: widget.steps,
        footnote: widget.footnote,
        onDismiss: () async {
          await ScreenGuide.dismiss(widget.id);
          if (mounted) setState(() => _dismissed = true);
        },
      ),
    );
  }
}

/// The panel itself, also used by [showGuideSheet].
Widget guidePanel({
  required String title,
  required List<GuideStep> steps,
  String? footnote,
  VoidCallback? onDismiss,
}) =>
    Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      decoration: BoxDecoration(
        color: brandBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brandBlue.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 18, color: brandBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: Color(0xff1C1939))),
                ),
              ),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 17, color: Colors.black38),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: brandBlue, shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(steps[i].text,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: Colors.grey.shade800)),
                  ),
                ],
              ),
            ),
          if (footnote != null) ...[
            const SizedBox(height: 12),
            Text(footnote,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600)),
          ],
        ],
      ),
    );

/// Reopens a guide the user dismissed, from the "?" in an app bar.
Future<void> showGuideSheet(
  BuildContext context, {
  required String title,
  required List<GuideStep> steps,
  String? footnote,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              guidePanel(title: title, steps: steps, footnote: footnote),
            ],
          ),
        ),
      ),
    );

/// The "?" that reopens a screen's guide.
class GuideButton extends StatelessWidget {
  const GuideButton({
    super.key,
    required this.id,
    required this.title,
    required this.steps,
    this.footnote,
  });

  final String id;
  final String title;
  final List<GuideStep> steps;
  final String? footnote;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'How this works',
        icon: const Icon(Icons.help_outline_rounded,
            size: 21, color: Colors.black45),
        onPressed: () async {
          // Restored as well as shown, so someone who needed it back gets it
          // inline next time rather than having to find this button again.
          await ScreenGuide.restore(id);
          if (context.mounted) {
            await showGuideSheet(context,
                title: title, steps: steps, footnote: footnote);
          }
        },
      );
}
