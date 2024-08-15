import 'dart:convert';

import 'package:banking_app/firebase%20network/gemini_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/abusiveexperiencereport/v1.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
class GoogleService{

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/gmail.readonly'],
  );

  firebaseData(String actualMonth,String messageId)async{
    try{
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .doc(actualMonth)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();
      if (documentSnapshot.exists){
        Map<String, dynamic> data = documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> messageIds = data['messageId'];
        if(!messageIds.contains(messageId)){

        }
      }
    }catch(e){}
  }

  Future<GoogleSignInAccount?> signInUser() async {
    return await _googleSignIn.signIn();
  }

  Future<AccessCredentials> getAccessCredentials(GoogleSignInAccount googleUser) async {
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken!;
    return AccessCredentials(
      AccessToken(
        'Bearer',
        accessToken,
        DateTime.now().toUtc().add(Duration(hours: 1)), // Example expiry
      ),
      null, // No refresh token provided
      ['https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/cloud-vision',
      ],
    );
  }

  http.Client createAuthenticatedClient(AccessCredentials credentials) {
    return authenticatedClient(
      http.Client(),
      credentials,
    );
  }

  Future<void> fetchEmailsForToday(gmail.GmailApi gmailApi) async {
    String currentDate = DateFormat('yyyy/MM/dd').format(DateTime.now());
    final dateFormat = DateFormat('yyyy/MM/dd');
    String? pageToken;
    int retryCount = 0;
    const int maxRetries = 5;

    do {
      try {
        final response = await gmailApi.users.messages.list('me',
            pageToken: pageToken
        );
        final messages = response.messages ?? [];

        if (messages.isEmpty) {
          print('No new emails for today.');
          break; // Exit loop if there are no new emails
        }
        bool shouldBreak = false; // Flag to determine if the loop should break
        for (var message in messages) {
          final msg = await gmailApi.users.messages.get('me', message.id!);
          final internalDateMillis = msg.internalDate!;
          final dateTime = DateTime.fromMillisecondsSinceEpoch(int.parse(internalDateMillis));
          final formattedDateTime = dateFormat.format(dateTime);

          if (formattedDateTime != currentDate) {
            shouldBreak = true;
            break; // Exit the for loop if the date doesn't match
          }

          // Retrieve and process email body
          String? emailBody;
          if (msg.payload != null) {
            final mimeType = msg.payload!.mimeType;
            if (mimeType == 'text/plain' || mimeType == 'text/html') {
              emailBody = msg.payload!.body!.data;
            } else if (msg.payload!.parts != null) {
              for (var part in msg.payload!.parts!) {
                if (part.mimeType == 'text/plain' || part.mimeType == 'text/html') {
                  emailBody = part.body!.data;
                  break;
                }
              }
            }
          }
          if (emailBody != null) {
            final decodedBody = utf8.decode(base64.decode(emailBody));
            if (decodedBody.contains('Debit') && decodedBody.contains('Account Name') && decodedBody.contains('Description')) {
              final subject = msg.payload!.headers!.firstWhere((header) => header.name == 'Subject').value;
              final document = html_parser.parse(decodedBody);
              final plainText = document.body?.text;
              final messageId = message.id;
              print('Found email with all three terms: $subject');
              print('message id is $messageId');
              AiUse().useGeminiAi(plainText!);
              print('Received at: $dateTime');

            } else {
              print('Nooootttt seeeeeennnnnnnn');
              print('Received at: $dateTime');
            }
          } else {
            print('Email body is empty or not found.');
            print('Received at: $formattedDateTime');
          }
        }
        if (shouldBreak) {
          break; // Exit the do-while loop if the date didn't match
        }

        pageToken = response.nextPageToken; // Get the next page token
        retryCount = 0; // Reset retry count on successful request
      } catch (e) {
        if (await handleRateLimit(e, retryCount, maxRetries)) {
          retryCount++;
        } else {
          print('Failed to fetch emails: $e');
          break;
        }
      }
    } while (pageToken != null);
  }

  Future<bool> handleRateLimit(dynamic e, int retryCount, int maxRetries) async {
    if (e is ApiRequestError && e.message != null &&
        (e.message!.contains('Rate Limit Exceeded') ||
            e.message!.contains('Quota Exceeded') ||
            e.message!.contains('Too Many Requests'))) {
      if (retryCount < maxRetries) {
        final delay = Duration(seconds: 2 * retryCount); // Exponential backoff
        print('Rate limit exceeded, retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
        return true;
      } else {
        print('Max retries reached. Exiting...');
        return false;
      }
    }
    return false;
  }

  Future<void> authenticateAndFetchEmails(String actualMonth) async {
    try {
      final googleUser = await signInUser();
      if (googleUser == null) {
        print('User sign-in failed.');
        return;
      }

      final credentials = await getAccessCredentials(googleUser);
      final client = createAuthenticatedClient(credentials);
      final gmailApi = gmail.GmailApi(client);

      await fetchEmailsForToday(gmailApi);
    } catch (e) {
      print('Failed to authenticate or fetch emails: $e');
    }
  }


}


//AIzaSyCEzlGzqgSeFyELQaMrOp8ZtSQtgIPAsRs