import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../firebase_options.dart';
import 'models.dart';
import 'spend_repository.dart';

/// Prompts the user to say what an unrecognised transaction was.
///
/// Android allows three notification actions, so the three likeliest
/// categories are offered as buttons answerable straight from the lock screen.
/// Anything else needs the app, which is what the notification body opens.
class PendingNotifications {
  PendingNotifications._();

  static const channelId = 'pending_transactions';
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Marks a payload as ours. The app's existing handler decodes payloads as
  /// FCM messages, so it needs to be able to tell these apart.
  static const _marker = 'sortTx';

  /// Set when the user taps the body or "More". The app routes to the pending
  /// list on its next frame; a notification tap cannot navigate on its own,
  /// because the UI may not exist yet.
  static bool openPendingList = false;

  static Future<void> show(
    TransactionRecord txn, {
    required List<Category> quickPicks,
    required String currencySymbol,
  }) async {
    final amount = NumberFormat('#,##0.00').format(txn.amount ?? 0);
    final who = txn.counterpartyKey ?? txn.bank;

    final actions = <AndroidNotificationAction>[
      for (final c in quickPicks.take(3))
        AndroidNotificationAction(
          'cat|${c.id}|${c.name}',
          c.name,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      const AndroidNotificationAction('more', 'More',
          showsUserInterface: true, cancelNotification: true),
    ];

    await _plugin.show(
      txn.smsId.hashCode,
      '$currencySymbol$amount to $who',
      'What was this?',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Transactions to sort',
          channelDescription:
              'Asks what a new transaction was, so it can be tracked',
          importance: Importance.high,
          priority: Priority.high,
          actions: actions,
        ),
      ),
      payload: jsonEncode({
        'type': _marker,
        'smsId': txn.smsId,
        'key': txn.counterpartyKey,
      }),
    );
  }

  static bool ownsPayload(String? payload) {
    if (payload == null) return false;
    try {
      return jsonDecode(payload)['type'] == _marker;
    } catch (_) {
      return false;
    }
  }

  /// Applies a tap. Safe to call from either isolate.
  static Future<void> handle(NotificationResponse response) async {
    if (!ownsPayload(response.payload)) return;
    final data = jsonDecode(response.payload!) as Map<String, dynamic>;
    final action = response.actionId;

    if (action == null || action == 'more') {
      openPendingList = true;
      return;
    }
    if (!action.startsWith('cat|')) return;

    final parts = action.split('|');
    if (parts.length < 3) return;

    await SpendRepository().labelTransaction(
      smsId: data['smsId'],
      categoryId: parts[1],
      categoryName: parts.sublist(2).join('|'),
      counterpartyKey: data['key'],
    );
  }

  /// Entry point for a button pressed while the app is not running.
  ///
  /// Runs in its own isolate with nothing initialised, so Firebase has to be
  /// started from scratch before anything can be written.
  @pragma('vm:entry-point')
  static Future<void> handleBackground(NotificationResponse response) async {
    if (!ownsPayload(response.payload)) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
      if (FirebaseAuth.instance.currentUser == null) {
        // Nothing can be written without a signed-in user; the transaction
        // stays pending and the in-app list still has it.
        return;
      }
      await handle(response);
    } catch (e) {
      // ignore: avoid_print
      print('Pending-notification action failed: $e');
    }
  }
}
