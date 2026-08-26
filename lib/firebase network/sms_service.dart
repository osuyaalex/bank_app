import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sms_inbox.dart';
import '../data/models.dart';
import '../data/pending_notifications.dart';
import '../data/spend_repository.dart';
import '../parsing/bank_alert.dart';

class SmsService{
  /// The one result the caller acts on.
  static const permissionDenied = 'SMS permission denied.';

  /// Scans recent messages, returning an error to show or null on success.
  ///
  /// Typed, and deliberately. It was `dynamic`, returned a String on the
  /// permission path and a bool at the end, and the home screen assigned the
  /// result to a `String?` -- so every *successful* scan threw
  /// `type 'bool' is not a subtype of type 'String?'`. The failure was
  /// invisible because it landed in a catch that only printed.
  Future<String?> getSmsMessages() async {
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
      if (!status.isGranted) {
        // ignore: avoid_print
        print('SMS permission denied.');
        return permissionDenied;
      }
    }

    final repo = SpendRepository();
    final marker = await _lastScanAt();
    final since = marker.since;

    // Not getAllSms: since flutter_sms_inbox 1.0.5 that silently returns only
    // the 200 most recent messages across inbox, sent and drafts.
    final messages = await SmsInbox.readRecent();
    messages.sort((a, b) => b.date!.compareTo(a.date!));

    DateTime? newest;
    var seen = 0;
    var pending = 0;
    var alerted = 0;

    for (final message in messages) {
      final when = message.date;
      if (when == null) continue;
      // Everything since the last scan, not merely today.
      //
      // This used to stop at the first message that was not from today, on
      // the assumption that the app is opened daily. It is not: a transaction
      // arriving on an evening the user never reopened the app was skipped
      // that night and skipped forever after, because the next scan only
      // looked at its own today. A real ₦7,500 data purchase was missing from
      // the records entirely, and nothing anywhere said so.
      if (!when.isAfter(since)) break;

      newest ??= when;
      seen++;

      final smsBody = message.body;
      if (smsBody == null || smsBody.isEmpty) continue;

      switch (classifyAlert(smsBody)) {
        case AlertKind.debit:
        case AlertKind.credit:
        case AlertKind.charge:
          final parsed = parseAlert(message.sender ?? '', smsBody);
          if (parsed == null) break;
          // Dated from the message where the bank printed none, so an alert
          // without its own timestamp still lands in the right month.
          final alert =
              parsed.occurredAt == null ? parsed.copyWith(occurredAt: when) : parsed;
          final mirrored = await repo.mirrorLegacyWrite(
            smsId: message.id!.toString(),
            alert: alert,
          );
          if (mirrored != null && mirrored.status == TxnStatus.pending) {
            pending++;
            // Nothing else tells the user an unrecognised transaction is
            // waiting, so ask -- but only about something that just happened,
            // and only a few times.
            //
            // A first run is a backfill, not news: the user has not been away
            // from the app, they have just arrived at it, and the batch screen
            // is where that history gets sorted. Notifying there buried a new
            // user under one alert per transaction while they were still
            // onboarding.
            final isNews = DateTime.now().difference(when) < _newsWindow;
            if (!marker.firstRun && isNews && alerted < _maxAlertsPerScan) {
              alerted++;
              await PendingNotifications.show(
                mirrored,
                currencySymbol: await repo.currencySymbol(),
                quickPicks: await repo.pickerCategories(),
              );
            }
          }
        case AlertKind.other:
          break;
      }
    }

    // Anything beyond the first few becomes one line instead of a stack.
    if (pending > alerted && alerted > 0) {
      await PendingNotifications.showBacklog(pending - alerted);
    }

    // Only after a clean pass. Advancing the marker on a scan that threw
    // half way would skip whatever it had not reached yet.
    if (newest != null) await _setLastScanAt(newest);
    // ignore: avoid_print
    print('SCAN: $seen new, $pending pending, $alerted alerted '
        '(firstRun=${marker.firstRun})');

    {
      // Totals are derived from the records, so refresh them once the scan
      // has written whatever it found.
      try {
        await repo.rebuildCurrentMonthTotals();
      } catch (e) {
        // ignore: avoid_print
        print('Totals rebuild after scan failed: $e');
      }
    }

    return null;
  }

  static const _lastScanKey = 'lastSmsScanAt';

  /// When the inbox was last read to the end.
  ///
  /// A first run has no marker, and reaching back through the whole inbox
  /// would re-do the migration's work. Thirty days is enough to cover an app
  /// that has been uninstalled for a while without turning every fresh
  /// install into a full history import.
  Future<({DateTime since, bool firstRun})> _lastScanAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_lastScanKey);
      if (millis != null) {
        return (
          since: DateTime.fromMillisecondsSinceEpoch(millis),
          firstRun: false
        );
      }
    } catch (_) {/* fall through to the default window */}
    return (
      since: DateTime.now().subtract(const Duration(days: 30)),
      firstRun: true
    );
  }

  /// At most this many "what was this?" notifications from one scan.
  ///
  /// Anything beyond it becomes a single summary. A notification per pending
  /// transaction is right for one arriving now and catastrophic for a
  /// backfill: reaching back thirty days on a first run produced one per
  /// transaction across a month, which is what a new user actually saw.
  static const _maxAlertsPerScan = 3;

  /// A message older than this is history, not news.
  ///
  /// Asking "what was this?" about a payment from last week is a question the
  /// user cannot answer from memory, and it arrives with no context.
  static const _newsWindow = Duration(hours: 12);

  Future<void> _setLastScanAt(DateTime when) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastScanKey, when.millisecondsSinceEpoch);
    } catch (_) {
      // A marker that will not persist means the next scan re-reads a little
      // more than it needed to. Writes are keyed by SMS id, so that is wasted
      // work rather than double counting.
    }
  }
}