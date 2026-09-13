/// What happened to each large amount of money the user received.
///
/// This started as "where your salary went", and a real account showed why
/// that was the wrong question. The app recognised a salary by its pattern --
/// the same payer, about a month apart -- and picked up a YouTube payment that
/// happened to match a job that had ended months earlier. It cannot tell a
/// salary from any other regular payment, and many people are paid by gigs,
/// contracts and platforms that follow no pattern at all.
///
/// So there is no guessing here. Any single payment of [bigPaymentFloor] or
/// more is followed, whatever it was for.
///
/// Money is not labelled once it lands, so a rule decides which payment a
/// purchase came out of, and the rule is simple enough to say out loud:
///
///  1. Spending after a big payment comes out of that payment first, before
///     any money the user already had.
///  2. When several big payments overlap, they are used up in the order they
///     arrived.
///  3. Spending after every big payment is used up comes from "other money",
///     and is shown on its own, never added to a payment.
///
/// So no payment can ever show more gone than it was.
library;

import '../parsing/bank_alert.dart';
import 'models.dart';

/// The smallest amount treated as a big payment.
const bigPaymentFloor = 100000.0;

/// One big payment and everything that came out of it.
class BigPayment {
  BigPayment(this.credit)
    : amount = credit.amount ?? 0,
      arrivedAt = credit.occurredAt!;

  final TransactionRecord credit;
  final double amount;
  final DateTime arrivedAt;

  String get from => credit.counterpartyKey ?? '';

  double _used = 0;
  double get used => _used;
  double get left => (amount - _used).clamp(0, amount);
  bool get isGone => left < 0.5;

  /// When the last of it went, or null while some is left.
  DateTime? goneOn;

  /// Category id to amount, for spending that was sorted.
  final Map<String, double> byCategory = {};

  /// Who received unsorted spending, and how much.
  final Map<String, double> unsortedByPayee = {};

  double charges = 0;

  /// Spending after this payment was used up and before the next big payment
  /// arrived, that no big payment covered.
  double fromOtherMoney = 0;

  /// Amount taken from this payment on each calendar day since it arrived,
  /// keyed by days since arrival.
  final Map<int, double> _usedOnDay = {};

  /// How much of it was left at the end of each day, from the day it arrived
  /// to [until], never below zero.
  List<double> leftByDay(DateTime until) {
    final days = _dateOf(until).difference(_dateOf(arrivedAt)).inDays + 1;
    var left = amount;
    return [
      for (var d = 0; d < (days < 1 ? 1 : days); d++)
        left = (left - (_usedOnDay[d] ?? 0)).clamp(0, amount),
    ];
  }

  /// Days from arrival until it was all gone, counting the day it arrived as
  /// day one. Null while some is left.
  int? get daysToGo => goneOn == null
      ? null
      : _dateOf(goneOn!).difference(_dateOf(arrivedAt)).inDays + 1;

  void _take(TransactionRecord spend, double take) {
    _used += take;
    final day = _dateOf(
      spend.occurredAt!,
    ).difference(_dateOf(arrivedAt)).inDays;
    _usedOnDay[day] = (_usedOnDay[day] ?? 0) + take;
    if (spend.kind == AlertKind.charge) {
      charges += take;
    } else if (spend.status == TxnStatus.labeled && spend.categoryId != null) {
      byCategory[spend.categoryId!] =
          (byCategory[spend.categoryId!] ?? 0) + take;
    } else {
      final who =
          (spend.counterpartyKey == null || spend.counterpartyKey!.isEmpty)
          ? 'Unknown'
          : spend.counterpartyKey!;
      unsortedByPayee[who] = (unsortedByPayee[who] ?? 0) + take;
    }
    if (isGone && goneOn == null) goneOn = spend.occurredAt;
  }
}

DateTime _dateOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whether a transaction is money arriving that counts as a big payment.
bool isBigPayment(
  TransactionRecord t, {
  String? ownerName,
  double floor = bigPaymentFloor,
  Set<String> hidden = const {},
}) =>
    t.kind == AlertKind.credit &&
    !t.isReversal &&
    t.occurredAt != null &&
    (t.amount ?? 0) >= floor &&
    !hidden.contains(t.smsId) &&
    // Money moved in from the user's own other account is not new money.
    !(t.counterpartyKey != null &&
        looksLikeOwnAccount(t.counterpartyKey!, ownerName));

/// Whether a transaction is money genuinely leaving the user.
bool _isSpending(TransactionRecord t, String? ownerName) {
  if (t.occurredAt == null || t.isReversal || (t.amount ?? 0) <= 0) {
    return false;
  }
  if (t.kind == AlertKind.charge) return true;
  if (t.kind != AlertKind.debit) return false;
  // Excluded debits are transfers to the user's own accounts.
  if (t.status == TxnStatus.excluded) return false;
  // As is one nothing has sorted yet. Moving money is not spending it.
  if (t.counterpartyKey != null &&
      looksLikeOwnAccount(t.counterpartyKey!, ownerName)) {
    return false;
  }
  return true;
}

/// Every big payment in [transactions] and what came out of it, newest first.
List<BigPayment> whereBigPaymentsWent(
  List<TransactionRecord> transactions, {
  String? ownerName,
  double floor = bigPaymentFloor,
  Set<String> hidden = const {},
}) {
  final payments =
      transactions
          .where(
            (t) => isBigPayment(
              t,
              ownerName: ownerName,
              floor: floor,
              hidden: hidden,
            ),
          )
          .map(BigPayment.new)
          .toList()
        ..sort((a, b) => a.arrivedAt.compareTo(b.arrivedAt));
  if (payments.isEmpty) return const [];

  final spending = transactions.where((t) => _isSpending(t, ownerName)).toList()
    ..sort((a, b) => a.occurredAt!.compareTo(b.occurredAt!));

  for (final spend in spending) {
    final when = spend.occurredAt!;
    // Only payments that had already arrived can pay for this.
    final arrived = payments.where((p) => !p.arrivedAt.isAfter(when)).toList();
    if (arrived.isEmpty) continue; // before the first big payment

    var owed = spend.amount!;
    // Oldest first.
    for (final p in arrived) {
      if (owed <= 0) break;
      if (p.isGone) continue;
      final take = owed < p.left ? owed : p.left;
      p._take(spend, take);
      owed -= take;
    }
    // Nothing big left to cover it: other money, credited to the latest
    // payment so it can say what happened after it ran out.
    if (owed > 0.005) arrived.last.fromOtherMoney += owed;
  }

  return payments.reversed.toList();
}
