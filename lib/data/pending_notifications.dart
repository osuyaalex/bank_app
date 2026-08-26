import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';

import '../firebase_options.dart';
import 'budget_status.dart';
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

  /// The daily digest: where the month stands, and what still needs an answer.
  ///
  /// Deliberately specific. The reminder this replaced said "This is your
  /// scheduled notification", which told the user nothing and trained them to
  /// swipe it away.
  /// Schedules the digest for [time], replacing any previous schedule.
  ///
  /// A workmanager task rather than a scheduled notification: the text has to
  /// be computed when it fires, and a scheduled notification fixes its content
  /// at the moment it is set.
  static Future<void> scheduleDigest(TimeOfDay time) async {
    await Workmanager().cancelByUniqueName(_digestTask);

    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));

    await Workmanager().registerPeriodicTask(
      _digestTask,
      'dailyDigestTask',
      frequency: const Duration(hours: 24),
      initialDelay: first.difference(now),
    );
  }

  static Future<void> cancelDigest() =>
      Workmanager().cancelByUniqueName(_digestTask);

  static const _digestTask = 'daily_digest';

  /// Initialises the plugin if it has not been already.
  ///
  /// The digest is raised from a background isolate, where nothing the app
  /// normally sets up has run. Calling this twice is harmless.
  static Future<void> ensureInitialized() async {
    const android = AndroidInitializationSettings('@drawable/bankal');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings,
        onDidReceiveBackgroundNotificationResponse: handleBackground);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          'Transactions to sort',
          description:
              'Asks what a new transaction was, so it can be tracked',
          importance: Importance.high,
        ));
  }

  static Future<void> showDigest({
    required double spent,
    required double budget,
    required int pending,
    required double unsorted,
    required String currency,
  }) async {
    final money = NumberFormat('#,##0');
    final title = '$currency${money.format(spent)} spent this month';

    final String body;
    if (pending > 0) {
      body = '$pending transaction${pending == 1 ? '' : 's'} still to sort '
          '($currency${money.format(unsorted)}). Tap to sort them.';
    } else if (budget <= 0) {
      body = 'No budget set yet. Tap to see where it went.';
    } else if (spent > budget) {
      body = "That's $currency${money.format(spent - budget)} over your "
          '$currency${money.format(budget)} budget.';
    } else {
      body = '$currency${money.format(budget - spent)} left of your '
          '$currency${money.format(budget)} budget.';
    }

    await _plugin.show(
      _digestId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Transactions to sort',
          channelDescription:
              'Asks what a new transaction was, so it can be tracked',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: jsonEncode({'type': _marker, 'digest': true}),
    );
  }

  /// Fixed id so a new digest replaces yesterday's rather than stacking.
  static const _digestId = 900001;

  /// Tells the user a category has gone past its budget.
  ///
  /// Sent once per category per month, decided by the caller. Repeating it on
  /// every later transaction would train the user to swipe budget warnings
  /// away, which is the opposite of what this is for.
  ///
  /// The body carries the figures rather than just the fact: "you have gone
  /// over" prompts a question, "₦4,500 over your ₦20,000 budget" answers it.
  static Future<void> showOverBudget({
    required String categoryId,
    required String categoryName,
    required double spent,
    required double budget,
    required String currency,
  }) async {
    await ensureInitialized();
    final status = BudgetStatus.of(spent: spent, budget: budget);
    final body = '$categoryName is ${status.describe(currency)}.';

    await _plugin.show(
      // Derived from the category, so a second warning for the same category
      // replaces the first instead of stacking.
      _overBudgetBaseId + (categoryId.hashCode & 0xffff),
      'Over budget',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Transactions to sort',
          channelDescription:
              'Asks what a new transaction was, so it can be tracked',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: jsonEncode({'type': _marker, 'overBudget': categoryId}),
    );
  }

  static const _overBudgetBaseId = 910000;

  /// One line for everything a scan could not ask about individually.
  ///
  /// Replaces a stack of per-transaction alerts, which is what a backfill
  /// produced before the scan learned to tell news from history.
  static Future<void> showBacklog(int count) async {
    if (count <= 0) return;
    await ensureInitialized();
    final body = '$count more transaction${count == 1 ? "" : "s"} to sort '
        'when you have a moment.';
    await _plugin.show(
      _backlogId,
      'Some spending needs sorting',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Transactions to sort',
          channelDescription:
              'Asks what a new transaction was, so it can be tracked',
          importance: Importance.low,
          priority: Priority.low,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: jsonEncode({'type': _marker, 'backlog': true}),
    );
  }

  /// Fixed, so a later backlog replaces the earlier one.
  static const _backlogId = 920001;

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

    if (data['digest'] == true) {
      openPendingList = true;
      return;
    }
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
