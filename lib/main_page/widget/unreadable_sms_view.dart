import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'category_picker.dart' show brandBlue;

/// Shown when the app cannot read the user's bank alerts.
///
/// There are two ways to end up here and they need different words. Either
/// SMS access is off -- which the user can fix -- or it is on and their bank's
/// format is one this app has never seen, which they cannot fix and should not
/// be left guessing about.
///
/// The second case is the one that matters. Every screen behind this assumes
/// transactions exist; with none, the user would wander an empty app deciding
/// it was broken, or worse, that they had spent nothing. Saying plainly that
/// their bank is not supported yet is more use than any amount of empty state.
class UnreadableSmsView extends StatelessWidget {
  const UnreadableSmsView({
    super.key,
    required this.permissionGranted,
    required this.messagesSeen,
    this.onRetry,
  });

  /// Whether SMS access is on. Off is fixable; on is not, by the user.
  final bool permissionGranted;

  /// How many messages were read. Zero with permission granted means an empty
  /// inbox rather than an unreadable one.
  final int messagesSeen;

  final Future<void> Function()? onRetry;

  bool get _unsupportedBank => permissionGranted && messagesSeen > 0;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                28, 0, 28, 24 + MediaQuery.of(context).padding.bottom),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: const Color(0xffFFF4E5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.sms_failed_outlined,
                      size: 33, color: Color(0xff9A6412)),
                ),
                const SizedBox(height: 26),
                Text(
                  _unsupportedBank
                      ? "We can't read your bank's alerts yet"
                      : 'The app needs your bank alerts',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 23, height: 1.25, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Text(
                  _unsupportedBank
                      ? 'Your bank writes its messages in a format this app '
                          'does not understand yet. Nothing is wrong on your '
                          'side, and nothing you do here will help until we '
                          'add support for it.\n\n'
                          "We're working on it."
                      : 'This app works by reading the transaction messages '
                          'your bank already sends you. Without that it has '
                          'nothing to track.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5, height: 1.6, color: Colors.grey.shade600),
                ),
                if (_unsupportedBank) ...[
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mark_email_read_outlined,
                            size: 17, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$messagesSeen messages read, none recognised.',
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (!permissionGranted)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final status = await Permission.sms.request();
                        if (status.isPermanentlyDenied) {
                          await openAppSettings();
                        } else if (status.isGranted) {
                          await onRetry?.call();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Turn on SMS access',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                if (!permissionGranted) const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    // Nothing behind this screen works without transactions,
                    // so leaving is the only honest option on offer.
                    onPressed: () => SystemNavigator.pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Close the app',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
