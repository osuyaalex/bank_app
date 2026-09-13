/// One month of money, the way a bank statement shows it: what came in, what
/// went out, and proof that it adds up.
///
/// This replaced "where your big payments went", which tried to say which
/// naira paid for what. Money is not labelled once it lands, so any answer to
/// that is a convention, and a figure the user cannot check is a figure they
/// do not trust. Everything here can be checked against the bank.
///
/// Most bank texts end with the balance. So for every account the month has a
/// starting balance and a closing balance the bank itself reported, and the
/// money in and out in between should explain the difference exactly. When it
/// does not, the difference is shown, not hidden: it is money that moved with
/// no text the app could read. On a real account that turned out to be card
/// payments the bank never texted about, and the ₦50 levy on incoming
/// transfers, which no bank sends a text for.
library;

import '../parsing/bank_alert.dart';
import 'models.dart';

/// How a transaction changes the balance of its account.
///
/// A bank charge normally takes money, but a reversed charge
/// (`***RSVL NIP CHARGE + VAT`) gives it back.
double effectOf(TransactionRecord t) {
  final amount = t.amount ?? 0;
  return switch (t.kind) {
    AlertKind.credit => amount,
    AlertKind.debit => -amount,
    AlertKind.charge => t.isReversal ? amount : -amount,
    AlertKind.other => 0,
  };
}

/// Which account a transaction belongs to.
///
/// Banks mask the number differently from one text to the next
/// (`221****558`, `221**558`), so the mask is reduced to a single mark.
String accountKeyOf(TransactionRecord t) =>
    '${t.bank}|${(t.account ?? '').replaceAll(RegExp(r'[^0-9]+'), '*')}';

int _smsOrder(String a, String b) {
  final x = int.tryParse(a), y = int.tryParse(b);
  if (x != null && y != null) return x.compareTo(y);
  return a.compareTo(b);
}

/// Oldest first; texts stamped with the same time in the order they arrived.
int compareTransactions(TransactionRecord a, TransactionRecord b) {
  final c = a.occurredAt!.compareTo(b.occurredAt!);
  return c != 0 ? c : _smsOrder(a.smsId, b.smsId);
}

/// The balance an account was left with after [sorted], one account's
/// transactions oldest first, or null when none of them showed a balance.
///
/// Banks send a transfer and its charge as two texts stamped with the same
/// second, and not always in the order the money moved: Zenith often sends
/// the transfer first although the charge came off first. So among texts that
/// share a time, the last one is the one no other text follows on from, the
/// one whose balance nothing else in the group was worked out from.
double? closingBalance(List<TransactionRecord> sorted) {
  final withBalance = sorted.lastWhereOrNull((t) => t.balanceAfter != null);
  if (withBalance == null) return null;
  final group = [
    for (final t in sorted)
      if (t.balanceAfter != null && t.occurredAt == withBalance.occurredAt) t,
  ];
  if (group.length == 1) return group.single.balanceAfter;

  bool follows(TransactionRecord next, TransactionRecord prev) =>
      (next.balanceAfter! - (prev.balanceAfter! + effectOf(next))).abs() < 0.05;
  final last = group.where(
    (c) => !group.any((o) => !identical(o, c) && follows(o, c)),
  );
  return (last.length == 1 ? last.single : group.last).balanceAfter;
}

extension _LastWhere<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}

/// Debit texts for money that never left: the SMS ids of every one in
/// [sorted], all transactions oldest first.
///
/// Wema texts a card payment even when it is declined, with the balance
/// untouched. On one real account that was twenty-seven texts in two years,
/// most of them a food app retrying a saved card at three in the morning,
/// and ₦231,000 that looked spent and never was. A declined payment is one
/// that asked for more than the account held and left the balance exactly
/// where the account's previous text had it.
Set<String> declinedDebits(List<TransactionRecord> sorted) {
  final previous = <String, double>{};
  final declined = <String>{};
  for (final t in sorted) {
    final key = accountKeyOf(t);
    final before = previous[key];
    final after = t.balanceAfter;
    if (t.kind == AlertKind.debit &&
        !t.isReversal &&
        before != null &&
        after != null &&
        (after - before).abs() < 0.01 &&
        (t.amount ?? 0) > after + 0.01) {
      declined.add(t.smsId);
    }
    if (after != null) previous[key] = after;
  }
  return declined;
}

/// One account over the month.
class AccountMonth {
  AccountMonth({
    required this.key,
    required this.bank,
    required this.account,
    required this.opening,
    required this.closing,
    required this.moneyIn,
    required this.moneyOut,
    required this.movedIn,
    required this.movedOut,
    required this.lastText,
  });

  final String key;
  final String bank;
  final String? account;

  /// The balance when the month began, or null when no text ever showed one.
  final double? opening;

  /// The balance in the bank's last text of the month.
  final double? closing;

  /// Everything that came in and went out, own transfers included, since
  /// those move the balance too.
  final double moneyIn;
  final double moneyOut;

  /// The part of [moneyIn] and [moneyOut] that was the user's own money
  /// moving between their accounts.
  final double movedIn;
  final double movedOut;

  /// When the bank last texted about this account, up to the end of the month.
  final DateTime? lastText;

  /// Whether the month can be checked against the bank's own figures.
  bool get checked => opening != null && closing != null;

  /// What the balance did that the texts do not explain. Negative when money
  /// left with no text, positive when it arrived with none.
  double get unexplained =>
      checked ? closing! - (opening! + moneyIn - moneyOut) : 0;

  /// The last three digits of the account number, as banks mask it.
  String get lastDigits {
    final digits = (account ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= 3 ? digits : digits.substring(digits.length - 3);
  }
}

/// A single line of a statement: who or what, and how much.
typedef StatementLine = ({
  String name,
  double amount,
  String smsId,
  DateTime when,
});

class MonthStatement {
  MonthStatement({
    required this.month,
    required this.until,
    required this.accounts,
    required this.received,
    required this.refunds,
    required this.spentByCategory,
    required this.unsortedByPayee,
    required this.charges,
    required this.movedIn,
    required this.movedOut,
    required this.dailyBalance,
    required this.dailyIn,
    required this.dailyOut,
    required this.declined,
  });

  /// The first day of the month.
  final DateTime month;

  /// The end of the month, or now if the month is not over.
  final DateTime until;

  final List<AccountMonth> accounts;

  /// Every payment received from someone else, one line each, largest first.
  final List<StatementLine> received;

  /// Reversals and refunds: money that came back.
  final double refunds;

  /// Category id to amount spent.
  final Map<String, double> spentByCategory;

  /// Who was paid, for spending not sorted into a budget.
  final Map<String, double> unsortedByPayee;

  /// Bank charges the bank sent a text for.
  final double charges;

  /// Money moved between the user's own accounts. Not income, not spending.
  final double movedIn;
  final double movedOut;

  /// The total balance of every checked account at the end of each day, day
  /// one first, up to [until].
  final List<double> dailyBalance;

  /// Money in and out each day, own transfers left out.
  final List<double> dailyIn;
  final List<double> dailyOut;

  /// Payments the bank texted about that were declined, so never counted.
  final List<TransactionRecord> declined;

  double get moneyIn => received.fold(0.0, (t, l) => t + l.amount) + refunds;

  double get moneyOut =>
      spentByCategory.values.fold(0.0, (t, v) => t + v) +
      unsortedByPayee.values.fold(0.0, (t, v) => t + v) +
      charges;

  List<AccountMonth> get checkedAccounts =>
      accounts.where((a) => a.checked).toList();

  List<AccountMonth> get uncheckedAccounts =>
      accounts.where((a) => !a.checked).toList();

  double get openingTotal =>
      checkedAccounts.fold(0.0, (t, a) => t + a.opening!);

  double get closingTotal =>
      checkedAccounts.fold(0.0, (t, a) => t + a.closing!);

  /// Money in and out of the checked accounts, own transfers left out.
  double get checkedIn =>
      checkedAccounts.fold(0.0, (t, a) => t + a.moneyIn - a.movedIn);
  double get checkedOut =>
      checkedAccounts.fold(0.0, (t, a) => t + a.moneyOut - a.movedOut);

  /// Own transfers into checked accounts less those out of them. Zero when
  /// money only moved between accounts the app can see.
  double get checkedMovedNet =>
      checkedAccounts.fold(0.0, (t, a) => t + a.movedIn - a.movedOut);

  /// Money that left checked accounts with no text, as a positive figure.
  double get leftWithoutText => checkedAccounts
      .where((a) => a.unexplained < -unexplainedTolerance)
      .fold(0.0, (t, a) => t - a.unexplained);

  /// Money that arrived in checked accounts with no text.
  double get arrivedWithoutText => checkedAccounts
      .where((a) => a.unexplained > unexplainedTolerance)
      .fold(0.0, (t, a) => t + a.unexplained);

  bool get isEmpty => accounts.isEmpty;
}

/// Anything smaller than this that the texts do not explain is left out as
/// rounding, not reported as missing money.
const unexplainedTolerance = 1.0;

/// How long an account can go without a text before a month with no activity
/// on it stops listing it.
const staleAccount = Duration(days: 90);

/// Whether [t] moved money between the user's own accounts.
bool isOwnTransfer(
  TransactionRecord t, {
  String? ownerName,
  Set<String> ownKeys = const {},
}) {
  if (t.kind != AlertKind.debit && t.kind != AlertKind.credit) return false;
  if (t.isReversal) return false;
  final key = t.counterpartyKey;
  if (key != null &&
      (ownKeys.contains(key) || looksLikeOwnAccount(key, ownerName))) {
    return true;
  }
  // A debit set aside without a category is one the user said was their own.
  return t.kind == AlertKind.debit && t.status == TxnStatus.excluded;
}

/// The month beginning at [month] from [history], every transaction the app
/// could read, in any order.
///
/// [history] should reach back before the month, so each account's opening
/// balance comes from the bank's last text before it began.
MonthStatement statementFor(
  List<TransactionRecord> history,
  DateTime month, {
  DateTime? now,
  String? ownerName,
  Set<String> ownKeys = const {},
}) {
  final start = DateTime(month.year, month.month, 1);
  final monthEnd = DateTime(month.year, month.month + 1, 1);
  final today = now ?? DateTime.now();
  final until = today.isBefore(monthEnd) ? today : monthEnd;

  final sorted =
      history
          .where((t) => t.occurredAt != null && t.kind != AlertKind.other)
          .toList()
        ..sort(compareTransactions);
  final declined = declinedDebits(sorted);
  double effect(TransactionRecord t) =>
      declined.contains(t.smsId) ? 0 : effectOf(t);
  bool inMonth(TransactionRecord t) =>
      !t.occurredAt!.isBefore(start) && t.occurredAt!.isBefore(until);

  // Accounts.
  final byAccount = <String, List<TransactionRecord>>{};
  for (final t in sorted) {
    if (!t.occurredAt!.isBefore(until)) continue;
    byAccount.putIfAbsent(accountKeyOf(t), () => []).add(t);
  }

  final accounts = <AccountMonth>[];
  final balanceOn = <String, List<double?>>{};
  final days = _dayCount(start, until);

  byAccount.forEach((key, txns) {
    final before = txns.where((t) => t.occurredAt!.isBefore(start)).toList();
    final during = txns.where(inMonth).toList();
    // An account with nothing this month is only shown if it still holds
    // money and the bank texted about it lately; an account closed long ago
    // would otherwise sit in every statement.
    if (during.isEmpty &&
        ((closingBalance(before) ?? 0).abs() < 0.5 ||
            start.difference(txns.last.occurredAt!) > staleAccount)) {
      return;
    }

    var opening = closingBalance(before);
    if (opening == null) {
      // No balance before the month: work back from the first one in it.
      final i = during.indexWhere((t) => t.balanceAfter != null);
      if (i >= 0) {
        opening =
            during[i].balanceAfter! -
            during.take(i + 1).fold(0.0, (s, t) => s + effect(t));
      }
    }

    var inSum = 0.0, outSum = 0.0, ownIn = 0.0, ownOut = 0.0;
    for (final t in during) {
      final e = effect(t);
      final own = isOwnTransfer(t, ownerName: ownerName, ownKeys: ownKeys);
      if (e >= 0) {
        inSum += e;
        if (own) ownIn += e;
      } else {
        outSum -= e;
        if (own) ownOut -= e;
      }
    }
    // When the month's last texts carried no balance, carry the bank's last
    // one forward by what they did.
    var closing = closingBalance(txns);
    if (closing != null) {
      final lastWithBalance = txns.lastIndexWhere(
        (t) => t.balanceAfter != null,
      );
      closing += txns
          .skip(lastWithBalance + 1)
          .fold(0.0, (s, t) => s + effect(t));
    }

    final account = AccountMonth(
      key: key,
      bank: txns.last.bank,
      account: txns.lastWhereOrNull((t) => t.account != null)?.account,
      opening: opening,
      closing: closing,
      moneyIn: inSum,
      moneyOut: outSum,
      movedIn: ownIn,
      movedOut: ownOut,
      lastText: txns.last.occurredAt,
    );
    accounts.add(account);

    if (account.checked) {
      balanceOn[key] = [
        for (var d = 0; d < days; d++)
          _balanceAtEndOfDay(txns, start, d, opening!, effect),
      ];
    }
  });
  accounts.sort((a, b) => a.bank.compareTo(b.bank));

  // Lines.
  final received = <StatementLine>[];
  var refunds = 0.0, charges = 0.0, movedIn = 0.0, movedOut = 0.0;
  final byCategory = <String, double>{};
  final byPayee = <String, double>{};
  final dailyIn = List.filled(days, 0.0);
  final dailyOut = List.filled(days, 0.0);
  final declinedLines = <TransactionRecord>[];

  for (final t in sorted.where(inMonth)) {
    final amount = t.amount ?? 0;
    if (amount <= 0) continue;
    if (declined.contains(t.smsId)) {
      declinedLines.add(t);
      continue;
    }
    final day = _dayIndex(start, t.occurredAt!).clamp(0, days - 1);

    if (isOwnTransfer(t, ownerName: ownerName, ownKeys: ownKeys)) {
      if (t.kind == AlertKind.credit) {
        movedIn += amount;
      } else {
        movedOut += amount;
      }
      continue;
    }

    if (effectOf(t) > 0) {
      dailyIn[day] += amount;
      if (t.isReversal) {
        refunds += amount;
      } else {
        received.add((
          name: _nameOf(t),
          amount: amount,
          smsId: t.smsId,
          when: t.occurredAt!,
        ));
      }
      continue;
    }

    dailyOut[day] += amount;
    if (t.kind == AlertKind.charge) {
      charges += amount;
    } else if (t.status == TxnStatus.labeled && t.categoryId != null) {
      byCategory[t.categoryId!] = (byCategory[t.categoryId!] ?? 0) + amount;
    } else {
      final who = _nameOf(t);
      byPayee[who] = (byPayee[who] ?? 0) + amount;
    }
  }
  received.sort((a, b) => b.amount.compareTo(a.amount));

  return MonthStatement(
    month: start,
    until: until,
    accounts: accounts,
    received: received,
    refunds: refunds,
    spentByCategory: byCategory,
    unsortedByPayee: byPayee,
    charges: charges,
    movedIn: movedIn,
    movedOut: movedOut,
    dailyBalance: [
      for (var d = 0; d < days; d++)
        balanceOn.values.fold(0.0, (s, b) => s + b[d]!),
    ],
    dailyIn: dailyIn,
    dailyOut: dailyOut,
    declined: declinedLines,
  );
}

String _nameOf(TransactionRecord t) =>
    (t.counterpartyKey == null || t.counterpartyKey!.trim().isEmpty)
    ? 'Unknown'
    : t.counterpartyKey!;

DateTime _dateOf(DateTime d) => DateTime(d.year, d.month, d.day);

int _dayIndex(DateTime start, DateTime when) =>
    _dateOf(when).difference(_dateOf(start)).inDays;

int _dayCount(DateTime start, DateTime until) {
  final last = until.subtract(const Duration(microseconds: 1));
  final n = _dayIndex(start, last) + 1;
  return n < 1 ? 1 : n;
}

double _balanceAtEndOfDay(
  List<TransactionRecord> sorted,
  DateTime start,
  int day,
  double opening,
  double Function(TransactionRecord) effect,
) {
  final end = DateTime(start.year, start.month, start.day + day + 1);
  final upTo = [
    for (final t in sorted)
      if (t.occurredAt!.isBefore(end)) t,
  ];
  final inMonth = upTo.where((t) => !t.occurredAt!.isBefore(start)).toList();
  if (inMonth.isEmpty) return opening;
  final i = upTo.lastIndexWhere((t) => t.balanceAfter != null);
  if (i < 0 || upTo[i].occurredAt!.isBefore(start)) {
    // Nothing this month showed a balance yet: opening plus what moved.
    return opening + inMonth.fold(0.0, (s, t) => s + effect(t));
  }
  return closingBalance(upTo)! +
      upTo.skip(i + 1).fold(0.0, (s, t) => s + effect(t));
}

/// The months a statement can be shown for, newest first: every month from
/// the oldest transaction in [history] to [now], at most [limit].
List<DateTime> statementMonths(
  List<TransactionRecord> history, {
  DateTime? now,
  int limit = 6,
}) {
  final today = now ?? DateTime.now();
  final dates = history.map((t) => t.occurredAt).whereType<DateTime>().toList();
  final current = DateTime(today.year, today.month, 1);
  if (dates.isEmpty) return [current];
  final oldest = dates.reduce((a, b) => a.isBefore(b) ? a : b);
  final first = DateTime(oldest.year, oldest.month, 1);
  return [
    for (var i = 0; i < limit; i++)
      if (!DateTime(today.year, today.month - i, 1).isBefore(first))
        DateTime(today.year, today.month - i, 1),
  ];
}
