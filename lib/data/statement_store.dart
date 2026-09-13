/// Reads what the monthly statement needs, and remembers a summary for the
/// home screen.
library;

import 'dart:isolate';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inbox_history.dart';
import 'migration.dart' show InboxMessage;
import 'migration_plan.dart' show monthKeyOf;
import 'models.dart';
import 'month_statement.dart';
import 'sms_inbox.dart';
import 'spend_repository.dart';

/// Everything the statement screen shows, read once.
class StatementData {
  const StatementData({
    required this.history,
    required this.ownerName,
    required this.ownKeys,
  });

  final List<TransactionRecord> history;
  final String? ownerName;
  final Set<String> ownKeys;
}

class StatementStore {
  StatementStore({FirebaseFirestore? db, String? uid})
    : db = db ?? FirebaseFirestore.instance,
      uid = uid ?? FirebaseAuth.instance.currentUser!.uid;

  final FirebaseFirestore db;
  final String uid;

  /// How many months the statement can show, this one included.
  static const months = 6;

  /// How many recent months of the user's own sorting decisions to lay over
  /// the inbox history.
  static const decisionMonths = 2;

  /// Every bank text on the phone from the months the statement can show,
  /// and the month before them for the first opening balance.
  ///
  /// Read from the SMS inbox, not the database, which only ever holds about a
  /// month. Recent transactions then take the category and status saved in
  /// the database, so a payment the user re-sorted shows where they put it.
  Future<StatementData> load({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final repo = SpendRepository(db: db, uid: uid);
    final inbox = await SmsInbox.readForMigration() ?? const <InboxMessage>[];
    final counterparties = await repo.loadCounterparties();
    final since = DateTime(today.year, today.month - months, 1);

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

    return StatementData(
      history: withSavedDecisions(parsed, saved),
      ownerName: await repo.ownerName(),
      ownKeys: {
        for (final e in counterparties.values)
          if (e.disposition == Disposition.notSpending) e.key,
      },
    );
  }

  // -------------------------------------------------------------------------
  // This month, remembered for the home screen.
  //
  // Parsing the whole inbox is too slow to do every time the home screen
  // opens, so the result is kept and worked out again at most every few hours.
  // -------------------------------------------------------------------------

  static const _summaryKey = 'statement_summary_v1';

  static Future<StatementSummary?> cachedSummary() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getStringList(
        _summaryKey,
      );
      if (raw == null || raw.length != 5) return null;
      return StatementSummary(
        month: DateTime.fromMillisecondsSinceEpoch(int.parse(raw[0])),
        moneyIn: double.parse(raw[1]),
        moneyOut: double.parse(raw[2]),
        currency: raw[3],
        computedAt: DateTime.fromMillisecondsSinceEpoch(int.parse(raw[4])),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSummary(
    MonthStatement statement, {
    required String currency,
  }) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_summaryKey, [
        '${statement.month.millisecondsSinceEpoch}',
        '${statement.moneyIn}',
        '${statement.moneyOut}',
        currency,
        '${DateTime.now().millisecondsSinceEpoch}',
      ]);
    } catch (_) {}
  }

  /// Works this month out and remembers it.
  Future<StatementSummary?> refreshSummary({required String currency}) async {
    final data = await load();
    final now = DateTime.now();
    await saveSummary(
      statementFor(
        data.history,
        DateTime(now.year, now.month, 1),
        now: now,
        ownerName: data.ownerName,
        ownKeys: data.ownKeys,
      ),
      currency: currency,
    );
    return cachedSummary();
  }
}

class StatementSummary {
  const StatementSummary({
    required this.month,
    required this.moneyIn,
    required this.moneyOut,
    required this.currency,
    required this.computedAt,
  });

  /// The first day of the month it describes.
  final DateTime month;
  final double moneyIn;
  final double moneyOut;
  final String currency;
  final DateTime computedAt;
}
