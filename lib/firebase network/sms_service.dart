import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'google_service.dart';

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
      final smsQuery = SmsQuery();
      List<SmsMessage> messages = await smsQuery.getAllSms;
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

        // Process the SMS body and perform keyword filtering
        String? smsBody = message.body;
        if (smsBody != null) {
          // Convert SMS body to lowercase for case-insensitive comparison
          String decodedBody = smsBody.toLowerCase();

          // Check if the message contains the specified terms
          if ((decodedBody.contains('debit') || decodedBody.contains('dr')) &&
              (decodedBody.contains('acc') || decodedBody.contains('acct'))
              //&& decodedBody.contains('desc')
          ) {
            // Log message details
            await updateDailySpend(message.id!.toString(), decodedBody);
            print('Found SMS with specified terms:');
            print('Sender: ${message.sender}');
            print('Body: $decodedBody');
            print('Received at: $dateTime');

          } else {
            print('SMS does not contain the required terms.');
            print('Received at: $dateTime');
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
    }
    return shouldBreak;
  }

}