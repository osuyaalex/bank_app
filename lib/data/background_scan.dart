import 'dart:async';

import '../firebase network/sms_service.dart';

/// Reads the inbox once per app session, without anything waiting on it.
///
/// The scan used to live inside the home screen's setup, which meant it only
/// ran if the user happened to land on the home screen. On an account that
/// opens to the summary it never ran at all -- a real ₦7,500 purchase sat
/// unrecorded because the one screen that scans was never visited.
///
/// It is deliberately **not** run on an isolate. The obvious idea is that a
/// background isolate keeps the app responsive, but the work here is waiting
/// on the SMS provider and on Firestore, not computing -- and awaiting I/O
/// already leaves the UI thread free. Against that, `flutter_sms_inbox` talks
/// over a method channel, which a spawned isolate has no messenger for
/// without handing it a root isolate token, and Firebase would need
/// initialising inside it too. That is real machinery bought for a problem
/// that is not there.
///
/// What actually mattered was that nothing *awaits* it. The screens render
/// from Firestore listeners, so when this finishes writing, the figures
/// update themselves -- no notifier, no refresh, no waiting.
class BackgroundScan {
  BackgroundScan._();

  static bool _started = false;
  static String? _lastResult;

  /// The result of the last scan, for a screen that wants to explain itself.
  static String? get lastResult => _lastResult;

  /// Starts the scan if it has not run yet this session.
  ///
  /// Returns immediately. Failure is swallowed on purpose: a scan that cannot
  /// run must not stop the user reaching their own data.
  static void startOnce() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  static Future<void> _run() async {
    try {
      _lastResult = await SmsService().getSmsMessages();
    } catch (e) {
      // ignore: avoid_print
      print('Background scan failed: $e');
    }
  }

  /// Allows a fresh scan, after a sign-out or a granted permission.
  static void reset() {
    _started = false;
    _lastResult = null;
  }
}
