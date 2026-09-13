/// Reads what the salary feature needs, and remembers a summary for the home
/// screen.
library;

import 'dart:isolate';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/bank_alert.dart';
import 'inbox_history.dart';
import 'migration.dart' show InboxMessage;
import 'migration_plan.dart' show monthKeyOf;
import 'models.dart';
import 'salary.dart';
import 'sms_inbox.dart';
import 'spend_repository.dart';

class SalaryStore {
  SalaryStore({FirebaseFirestore? db, String? uid})
    : db = db ?? FirebaseFirestore.instance,
      uid = uid ?? FirebaseAuth.instance.currentUser!.uid;

  final FirebaseFirestore db;
  final String uid;

  /// How far back to look. A little over a year, so the same history serves
  /// features that compare with this time last year, not only the salary.
  static const lookBack = Duration(days: 400);

  /// How many recent months of the user's own sorting decisions to lay over
  /// the inbox history. The current pay cycle always falls inside these.
  static const decisionMonths = 2;

  /// Every bank alert on the phone from the last [lookBack], as transactions.
  ///
  /// Read from the SMS inbox rather than the database, which only ever holds
  /// about a month -- nowhere near enough to see two paydays. Recent
  /// transactions then take the category and status saved in the database,
  /// so a payment the user re-sorted shows where they put it.
  Future<List<TransactionRecord>> recentTransactions({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final inbox = await SmsInbox.readForMigration() ?? const <InboxMessage>[];
    final counterparties = await SpendRepository(
      db: db,
      uid: uid,
    ).loadCounterparties();
    final since = today.subtract(lookBack);

    // Off the main thread: thousands of messages would freeze the screen.
    final history = await Isolate.run(
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
    return withSavedDecisions(history, saved);
  }

  // -------------------------------------------------------------------------
  // "Not my salary"
  // -------------------------------------------------------------------------

  static const _ignoredKey = 'salary_ignored_payers_v1';

  /// Payers the user has said are not their salary.
  static Future<Set<String>> ignoredPayers() async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(
                _ignoredKey,
              ) ??
              const [])
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> ignorePayer(String payer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_ignoredKey) ?? const []).toSet()
        ..add(payer);
      await prefs.setStringList(_ignoredKey, set.toList());
    } catch (_) {}
  }

  static Future<void> clearIgnored() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_ignoredKey);
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // A summary the home screen can show without reading five months of data.
  // -------------------------------------------------------------------------

  static const _summaryKey = 'salary_summary_v1';

  static Future<SalarySummary?> cachedSummary() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getStringList(
        _summaryKey,
      );
      if (raw == null || raw.length != 6) return null;
      return SalarySummary(
        salary: double.parse(raw[0]),
        spent: double.parse(raw[1]),
        paidOn: DateTime.fromMillisecondsSinceEpoch(int.parse(raw[2])),
        currency: raw[3],
        computedAt: DateTime.fromMillisecondsSinceEpoch(int.parse(raw[4])),
        found: raw[5] == '1',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSummary(SalarySummary s) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_summaryKey, [
        '${s.salary}',
        '${s.spent}',
        '${s.paidOn.millisecondsSinceEpoch}',
        s.currency,
        '${s.computedAt.millisecondsSinceEpoch}',
        s.found ? '1' : '0',
      ]);
    } catch (_) {}
  }

  /// Works the whole thing out and remembers the result.
  ///
  /// Returns null when there is no recognisable salary, and remembers that too,
  /// so the home screen stops looking.
  Future<SalarySummary?> refreshSummary({
    required String currency,
    String? ownerName,
  }) async {
    final txns = await recentTransactions();
    final ignored = await ignoredPayers();
    final salary = detectSalary(
      txns
          .where(
            (t) =>
                t.kind != AlertKind.credit ||
                t.counterpartyKey == null ||
                !ignored.any((p) => samePayer(p, t.counterpartyKey!)),
          )
          .toList(),
      ownerName: ownerName,
    );
    final now = DateTime.now();
    if (salary == null) {
      await saveSummary(
        SalarySummary(
          salary: 0,
          spent: 0,
          paidOn: now,
          currency: currency,
          computedAt: now,
          found: false,
        ),
      );
      return null;
    }
    final cycle = payCycle(
      txns,
      start: salary.latest.occurredAt!,
      end: now,
      salary: salary.latest.amount ?? salary.typical,
      ownerName: ownerName,
    );
    final summary = SalarySummary(
      salary: salary.latest.amount ?? salary.typical,
      spent: cycle.spent,
      paidOn: salary.latest.occurredAt!,
      currency: currency,
      computedAt: now,
      found: true,
    );
    await saveSummary(summary);
    return summary;
  }
}

class SalarySummary {
  const SalarySummary({
    required this.salary,
    required this.spent,
    required this.paidOn,
    required this.currency,
    required this.computedAt,
    required this.found,
  });

  final double salary;
  final double spent;
  final DateTime paidOn;
  final String currency;
  final DateTime computedAt;

  /// False when the last check found no salary at all.
  final bool found;
}
