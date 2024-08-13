import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/abusiveexperiencereport/v1.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';


//final clientId = ClientId("829190868345-f1t3n83v4nplhiqq3blluipne1qs8dnl.apps.googleusercontent.com");

class GoogleService{

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/gmail.readonly'],
  );

  Future<void> authenticateAndFetchEmails() async {
    try {
      // Sign in the user
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // Retrieve authentication credentials
      final GoogleSignInAuthentication googleAuth = await googleUser!.authentication;

      // Use the access token for authorization
      final accessToken = googleAuth.accessToken!;
      // Create authenticated client
      final client = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            'Bearer',
            accessToken,
            DateTime.now().toUtc().add(Duration(hours: 1)), // Example expiry
          ),
          null, // No refresh token provided
          ['https://www.googleapis.com/auth/gmail.readonly'],
        ),
      );

      final gmailApi = gmail.GmailApi(client);
      String? pageToken;
      int retryCount = 0;
      const int maxRetries = 5;

      final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

      do {
        try {
          final response = await gmailApi.users.messages.list('me', pageToken: pageToken);
          final messages = response.messages ?? [];

          for (var message in messages) {
            final msg = await gmailApi.users.messages.get('me', message.id!);
            final snippet = msg.snippet!;
            final internalDateMillis = msg.internalDate!;

            // Check if the snippet contains all three terms
            if (snippet.contains('Debit') &&
                snippet.contains('Account Name') &&
                snippet.contains('Description')) {
              final subject = msg.payload!.headers!.firstWhere((header) => header.name == 'Subject').value;
              print('Found email with all three terms: $subject');
            } else {
              print('Nooootttt seeeeeennnnnnnn');
            }
          }
          pageToken = response.nextPageToken; // Get the next page token
          retryCount = 0; // Reset retry count on successful request
        } catch (e) {
          if (e is ApiRequestError && e.message != null &&
              (e.message!.contains('Rate Limit Exceeded') ||
                  e.message!.contains('Quota Exceeded') ||
                  e.message!.contains('Too Many Requests'))) {
            // Rate limit error
            if (retryCount < maxRetries) {
              retryCount++;
              final delay = Duration(seconds: 2 * retryCount); // Exponential backoff
              print('Rate limit exceeded, retrying in ${delay.inSeconds} seconds...');
              await Future.delayed(delay);
            } else {
              print('Max retries reached. Exiting...');
              break;
            }
          } else {
            // Other errors
            print('Failed to fetch emails: $e');
            break;
          }
        }
      } while (pageToken != null);

    } catch (e) {
      print('Failed to authenticate or fetch emails: $e');
    }
  }


}