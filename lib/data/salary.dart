/// Where the user's salary went.
///
/// Most Nigerian salaries do not say "salary". They arrive as an ordinary
/// transfer from the employer -- `TRF FROM BRIGHTPATH LTD` -- and for people who
/// work for a small business, often from the owner's personal account. So a
/// salary is recognised by its pattern, not its wording: money from the same
/// payer, about a month apart, for roughly the same amount. The word, when it
/// is there, only adds confidence.
library;

import '../parsing/bank_alert.dart';
import 'models.dart';

/// The smallest amount treated as a possible salary. Below this, a monthly
/// transfer from the same person is far more likely to be allowance or a
/// contribution than wages.
const salaryFloor = 30000.0;

/// The gap between two paydays, in days. Wide enough for a salary that lands
/// a few days early or late around weekends and public holidays.
const _minGap = 24, _maxGap = 38;

/// How far a month's pay may differ from the typical figure and still count as
/// the same salary. Allows for overtime, deductions and the odd bonus.
const _amountTolerance = 0.25;

final _salaryWord = RegExp(
  r'\b(salary|sal|payroll|wages?|stipend|pay\s*slip)\b',
  caseSensitive: false,
);

/// A salary the app has recognised.
class SalaryPattern {
  const SalaryPattern({
    required this.payer,
    required this.paydays,
    required this.typical,
    required this.namedSalary,
  });

  /// Who pays it, as written on the alerts.
  final String payer;

  /// Every recognised payday, oldest first.
  final List<TransactionRecord> paydays;

  /// The middle amount, so one bonus month does not distort it.
  final double typical;

  /// At least one payment said "salary" or similar.
  final bool namedSalary;

  TransactionRecord get latest => paydays.last;

  /// When the next one is expected, from the average gap so far.
  DateTime get nextExpected {
    final dates = paydays.map((p) => p.occurredAt!).toList();
    if (dates.length < 2) return dates.last.add(const Duration(days: 30));
    final totalDays = dates.last.difference(dates.first).inDays;
    final gap = (totalDays / (dates.length - 1)).round();
    return dates.last.add(Duration(days: gap));
  }
}

/// Whether two payer names are the same payer, allowing for truncation.
bool samePayer(String a, String b) {
  String squash(String v) =>
      v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final x = squash(a), y = squash(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  return x.length >= 6 && y.length >= 6 && (x.startsWith(y) || y.startsWith(x));
}

/// The user's salary, or null when there is no clear one.
///
/// Null is the common, correct answer for anybody without a regular income,
/// and the feature simply does not appear for them.
SalaryPattern? detectSalary(
  List<TransactionRecord> transactions, {
  String? ownerName,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final credits =
      transactions
          .where(
            (t) =>
                t.kind == AlertKind.credit &&
                !t.isReversal &&
                t.occurredAt != null &&
                (t.amount ?? 0) >= salaryFloor &&
                t.counterpartyKey != null &&
                t.counterpartyKey!.trim().isNotEmpty &&
                // Moving your own money between accounts is not being paid.
                !looksLikeOwnAccount(t.counterpartyKey!, ownerName),
          )
          .toList()
        ..sort((a, b) => a.occurredAt!.compareTo(b.occurredAt!));

  // Group by payer.
  final groups = <List<TransactionRecord>>[];
  for (final c in credits) {
    final g = groups.firstWhere(
      (g) => samePayer(g.first.counterpartyKey!, c.counterpartyKey!),
      orElse: () {
        final n = <TransactionRecord>[];
        groups.add(n);
        return n;
      },
    );
    g.add(c);
  }

  SalaryPattern? best;
  var bestScore = 0.0;
  for (final g in groups) {
    final run = _longestMonthlyRun(g);
    if (run.length < 2) continue;

    // A salary that stopped months ago is not the one being spent now.
    final sinceLast = today.difference(run.last.occurredAt!).inDays;
    if (sinceLast > _maxGap + 10) continue;

    final named = run.any((t) => _salaryWord.hasMatch(t.narration));
    final typical = _median(run.map((t) => t.amount!).toList());
    // More paydays, a named salary and a larger amount all make it likelier
    // to be the salary rather than, say, a monthly allowance from a parent.
    final score = run.length * 10 + (named ? 25 : 0) + typical / 100000;
    if (score > bestScore) {
      bestScore = score;
      best = SalaryPattern(
        payer: _longestName(run),
        paydays: run,
        typical: typical,
        namedSalary: named,
      );
    }
  }
  return best;
}

/// The longest run of payments about a month apart and about the same size,
/// ending with the most recent one that fits.
List<TransactionRecord> _longestMonthlyRun(List<TransactionRecord> payments) {
  var best = <TransactionRecord>[];
  for (var start = 0; start < payments.length; start++) {
    final run = [payments[start]];
    for (var i = start + 1; i < payments.length; i++) {
      final gap = payments[i].occurredAt!
          .difference(run.last.occurredAt!)
          .inDays;
      if (gap < _minGap) continue; // a second payment in the same month
      if (gap > _maxGap) break;
      final typical = _median(run.map((t) => t.amount!).toList());
      final amount = payments[i].amount!;
      if ((amount - typical).abs() / typical > _amountTolerance) continue;
      run.add(payments[i]);
    }
    if (run.length > best.length ||
        (run.length == best.length &&
            best.isNotEmpty &&
            run.last.occurredAt!.isAfter(best.last.occurredAt!))) {
      best = run;
    }
  }
  return best;
}

double _median(List<double> values) {
  final v = [...values]..sort();
  final mid = v.length ~/ 2;
  return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

String _longestName(List<TransactionRecord> run) => run
    .map((t) => t.counterpartyKey!)
    .reduce((a, b) => b.length > a.length ? b : a);

// ---------------------------------------------------------------------------
// One pay cycle: from a payday to the next one, or to today.
// ---------------------------------------------------------------------------

/// Money that left in one pay cycle, and what it went on.
class PayCycle {
  const PayCycle({
    required this.start,
    required this.end,
    required this.salary,
    required this.spent,
    required this.byCategory,
    required this.unsorted,
    required this.unsortedByPayee,
    required this.charges,
    required this.dailyTotals,
  });

  final DateTime start;

  /// The next payday, or today if it has not arrived yet.
  final DateTime end;

  final double salary;

  /// Everything that left, excluding money moved between the user's own
  /// accounts, which is not spending.
  final double spent;

  /// Category id to amount, for sorted spending.
  final Map<String, double> byCategory;

  /// Spending not yet given a category.
  final double unsorted;

  /// The same money by who received it, largest first. A single "not sorted"
  /// line hides that most of it went to two or three people, which is the
  /// thing the user actually wants to know.
  final Map<String, double> unsortedByPayee;

  /// Bank fees.
  final double charges;

  /// Money out on each day of the cycle, day 1 first.
  final List<double> dailyTotals;

  double get shareGone => salary <= 0 ? 0 : spent / salary;
  int get daysIn => dailyTotals.length;

  /// The day of the cycle by which [share] of the salary had gone, or null if
  /// it never did.
  int? dayWhenGone(double share) {
    var running = 0.0;
    for (var i = 0; i < dailyTotals.length; i++) {
      running += dailyTotals[i];
      if (running >= salary * share) return i + 1;
    }
    return null;
  }
}

/// Money out between [start] and [end].
PayCycle payCycle(
  List<TransactionRecord> transactions, {
  required DateTime start,
  required DateTime end,
  required double salary,
  String? ownerName,
}) {
  // By calendar date, not by hours since the payment landed: money spent at
  // 8am the morning after a 9am payday is day two, not day one.
  DateTime dateOf(DateTime d) => DateTime(d.year, d.month, d.day);
  final days = dateOf(end).difference(dateOf(start)).inDays + 1;
  final daily = List<double>.filled(days < 1 ? 1 : days, 0);
  final byCategory = <String, double>{};
  final byPayee = <String, double>{};
  var unsorted = 0.0, charges = 0.0, spent = 0.0;

  for (final t in transactions) {
    final when = t.occurredAt;
    if (when == null || when.isBefore(start) || when.isAfter(end)) continue;
    if (t.isReversal) continue;
    final amount = t.amount ?? 0;
    if (amount <= 0) continue;

    if (t.kind == AlertKind.charge) {
      charges += amount;
    } else if (t.kind == AlertKind.debit) {
      // Excluded debits are the user moving money to their own account.
      if (t.status == TxnStatus.excluded) continue;
      // So is one the map has not caught yet. Counting it would say money is
      // gone when it has only moved to another of the user's own accounts.
      if (t.counterpartyKey != null &&
          looksLikeOwnAccount(t.counterpartyKey!, ownerName)) {
        continue;
      }
      if (t.status == TxnStatus.labeled && t.categoryId != null) {
        byCategory[t.categoryId!] = (byCategory[t.categoryId!] ?? 0) + amount;
      } else {
        unsorted += amount;
        final who = (t.counterpartyKey == null || t.counterpartyKey!.isEmpty)
            ? 'Unknown'
            : t.counterpartyKey!;
        byPayee[who] = (byPayee[who] ?? 0) + amount;
      }
    } else {
      continue;
    }
    spent += amount;
    final day = dateOf(when).difference(dateOf(start)).inDays;
    if (day >= 0 && day < daily.length) daily[day] += amount;
  }

  return PayCycle(
    start: start,
    end: end,
    salary: salary,
    spent: spent,
    byCategory: byCategory,
    unsorted: unsorted,
    unsortedByPayee: Map.fromEntries(
      byPayee.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    ),
    charges: charges,
    dailyTotals: daily,
  );
}
