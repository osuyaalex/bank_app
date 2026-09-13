/// Reads what the big-payments feature needs, and remembers a summary for the
/// home screen.
library;

import 'dart:isolate';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'big_payments.dart';
import 'inbox_history.dart';
import 'migration.dart' show InboxMessage;
import 'migration_plan.dart' show monthKeyOf;
import 'models.dart';
import 'sms_inbox.dart';
import 'spend_repository.dart';

class BigPaymentStore {
  BigPaymentStore({FirebaseFirestore? db, String? uid})
    : db = db ?? FirebaseFirestore.instance,
      uid = uid ?? FirebaseAuth.instance.currentUser!.uid;

  final FirebaseFirestore db;
  final String uid;

  /// How far back to look.
  static const lookBack = Duration(days: 400);

  /// How many recent months of the user's own sorting decisions to lay over
  /// the inbox history.
  static const decisionMonths = 2;

  /// Every bank alert on the phone from the last [lookBack], as transactions.
  ///
  /// Read from the SMS inbox, not the database, which only ever holds about a
  /// month. Recent transactions then take the category and status saved in
  /// the database, so a payment the user re-sorted shows where they put it.
  Future<List<TransactionRecord>> history({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final inbox = await SmsInbox.readForMigration() ?? const <InboxMessage>[];
    final counterparties = await SpendRepository(
      db: db,
      uid: uid,
    ).loadCounterparties();
    final since = today.subtract(lookBack);

    // Off the main thread: thousands of messages would freeze the screen.
    final parsed = await Isolate.run(
      () => historyFromInbox(inbox, counterparties, since: since),
    );

    final saved = <String, ({TxnStatus status, String? categoryId})>{};
    final user = db.collection('Users').doc(uid);
    for (var i = 0; i < decisionMonths; i++) {
      final key = monthKeyOf(DateTime(today.year, today.month - i, 1));
      final snap = await user
          .collection('months')
          .doc(key)
          .collection('transactions')
          .get();
      for (final d in snap.docs) {
        final m = d.data();
        saved[d.id] = (
          status: TxnStatus.values.firstWhere(
            (v) => v.name == m['status'],
            orElse: () => TxnStatus.pending,
          ),
          categoryId: m['categoryId'] as String?,
        );
      }
    }
    return withSavedDecisions(parsed, saved);
  }

  // -------------------------------------------------------------------------
  // "Hide this"
  // -------------------------------------------------------------------------

  static const _hiddenKey = 'big_payments_hidden_v1';

  /// Payments the user said were not really theirs, by SMS id.
  static Future<Set<String>> hidden() async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(
                _hiddenKey,
              ) ??
              const [])
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> hide(String smsId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_hiddenKey) ?? const []).toSet()
        ..add(smsId);
      await prefs.setStringList(_hiddenKey, set.toList());
    } catch (_) {}
  }

  static Future<void> unhide(String smsId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_hiddenKey) ?? const []).toSet()
        ..remove(smsId);
      await prefs.setStringList(_hiddenKey, set.toList());
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // The latest big payment, remembered for the home screen.
  //
  // Parsing the whole inbox is too slow to do every time the home screen
  // opens, so the result is kept and worked out again at most every few hours.
  // -------------------------------------------------------------------------

  static const _summaryKey = 'big_payment_summary_v1';

  static Future<BigPaymentSummary?> cachedSummary() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getStringList(
        _summaryKey,
      );
      if (raw == null || raw.length != 8) return null;
      return BigPaymentSummary(
        found: raw[0] == '1',
        amount: double.parse(raw[1]),
        left: double.parse(raw[2]),
        from: raw[3],
        arrivedAt: DateTime.fromMillisecondsSinceEpoch(int.parse(raw[4])),
        goneOn: raw[5].isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(int.parse(raw[5])),
        currency: raw[6],
        computedAt: DateTime.fromMillisecondsSinceEpoch(int.parse(raw[7])),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSummary(
    List<BigPayment> payments, {
    required String currency,
  }) async {
    final now = DateTime.now();
    final latest = payments.isEmpty ? null : payments.first;
    try {
      await (await SharedPreferences.getInstance()).setStringList(_summaryKey, [
        latest == null ? '0' : '1',
        '${latest?.amount ?? 0}',
        '${latest?.left ?? 0}',
        latest?.from ?? '',
        '${(latest?.arrivedAt ?? now).millisecondsSinceEpoch}',
        latest?.goneOn == null
            ? ''
            : '${latest!.goneOn!.millisecondsSinceEpoch}',
        currency,
        '${now.millisecondsSinceEpoch}',
      ]);
    } catch (_) {}
  }

  /// Works everything out and remembers the latest payment.
  Future<BigPaymentSummary?> refreshSummary({
    required String currency,
    String? ownerName,
  }) async {
    final payments = whereBigPaymentsWent(
      await history(),
      ownerName: ownerName,
      hidden: await hidden(),
    );
    await saveSummary(payments, currency: currency);
    return cachedSummary();
  }
}

class BigPaymentSummary {
  const BigPaymentSummary({
    required this.found,
    required this.amount,
    required this.left,
    required this.from,
    required this.arrivedAt,
    required this.goneOn,
    required this.currency,
    required this.computedAt,
  });

  /// False when there is no big payment at all.
  final bool found;
  final double amount;
  final double left;
  final String from;
  final DateTime arrivedAt;
  final DateTime? goneOn;
  final String currency;
  final DateTime computedAt;
}
