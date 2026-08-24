import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/sms_inbox.dart';
import '../data/models.dart';
import '../data/pending_notifications.dart';
import '../data/spend_repository.dart';
import '../parsing/bank_alert.dart';

class SmsService{
  Future<dynamic>getSmsMessages() async {
    // Get the current date in the desired format
    String currentDate = DateFormat('yyyy/MM/dd').format(DateTime.now());
    final dateFormat = DateFormat('yyyy/MM/dd');
    bool? shouldBreak;

    // Request SMS permissions if not granted
    var status = await Permission.sms.status;

    if (!status.isGranted) {
      // Request permission
      status = await Permission.sms.request();

      // Check if permission was granted after request
      if (!status.isGranted) {
        // Permission denied, handle appropriately (e.g., show a message to the user)
        print('SMS permission denied.');
        return 'SMS permission denied.';
      }
    }
    // If permission is granted, continue
    if (status.isGranted) {
      print('Access to SMS granted.');

      // Retrieve all SMS messages
      // One repository per scan so the counterparty map is read once.
      final repo = SpendRepository();
      // Not getAllSms: since flutter_sms_inbox 1.0.5 that silently returns
      // only the 200 most recent messages across inbox, sent and drafts.
      // This scan only cares about today's incoming alerts.
      List<SmsMessage> messages = await SmsInbox.readRecent();
      messages.sort((a, b) => b.date!.compareTo(a.date!));
      // Flag to track whether we should break out of the loop
      shouldBreak = false;

      // Iterate over each message
      for (var message in messages) {
        final dateTime =message.date!;
        final formattedDateTime = dateFormat.format(dateTime);
        print(dateTime);
        print(currentDate);
        // Break the loop if the message date doesn't match today's date
        if (formattedDateTime != currentDate) {
          shouldBreak = true;
          break;
        }

        // Process the SMS body
        String? smsBody = message.body;
        if (smsBody != null) {
          switch (classifyAlert(smsBody)) {
            case AlertKind.debit:
              // Gemini is no longer in this path. It used to categorise the
              // message and increment the legacy totals directly, but those
              // fields are now derived from the transaction records and
              // overwritten moments later -- so its answer was discarded after
              // being rendered, which showed up as figures changing on screen.
              // The parser gets the amount and the counterparty map gets the
              // category; anything unrecognised becomes a prompt instead of a
              // guess.
              final parsed = parseAlert(message.sender ?? '', smsBody);
              final mirrored = await repo.mirrorLegacyWrite(
                smsId: message.id!.toString(),
                alert: parsed,
              );
              print('Debit alert from ${message.sender} at $dateTime');
              // Nothing else tells the user an unrecognised transaction is
              // waiting, so ask while they still remember what it was.
              if (mirrored != null && mirrored.status == TxnStatus.pending) {
                await PendingNotifications.show(
                  mirrored,
                  quickPicks: await repo.quickPickCategories(),
                  currencySymbol: await repo.currencySymbol(),
                );
              }
              break;
            case AlertKind.credit:
              // Money received is not spending. M3 will store these with a
              // direction so the running balance stays continuous.
              print('Skipping credit alert at $dateTime');
              break;
            case AlertKind.charge:
              print('Skipping bank charge at $dateTime');
              break;
            case AlertKind.other:
              print('Not a transaction alert. Received at: $dateTime');
              break;
          }
        } else {
          print('SMS body is empty.');
          print('Received at: $formattedDateTime');
        }

        // Break if the date does not match today's date
        if (shouldBreak!) {
          break;
        }
      }

      // Totals are derived from the records, so refresh them once the scan
      // has written whatever it found.
      try {
        await repo.rebuildCurrentMonthTotals();
      } catch (e) {
        print('Totals rebuild after scan failed: $e');
      }
    }

    return shouldBreak;
  }

}