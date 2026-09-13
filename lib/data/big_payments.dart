/// What happened to one large payment, line by line.
///
/// Money is not labelled once it lands, so a rule decides which payment a
/// purchase came out of. The first version worked the rule out and showed
/// only the answer -- "all gone in 6 days" -- which nobody could check. Now
/// every payment it counts is listed, in order, with what was left after it,
/// so the user can read it and see where they disagree.
///
/// The rule, simple enough to say out loud:
///
///  1. Spending after a big payment comes out of it first, before any money
///     the user already had.
///  2. When several big payments overlap, they are used up in the order they
///     arrived.
///  3. Nothing is taken from a payment once it is used up, so it can never
///     show more gone than it was.
///
/// Any single payment of [bigPaymentFloor] or more is followed, whatever it
/// was for: the app cannot tell a salary from any other payment.
library;

import '../parsing/bank_alert.dart';
import 'models.dart';
import 'month_statement.dart';

/// The smallest amount treated as a big payment.
const bigPaymentFloor = 100000.0;

/// One spending counted against a big payment.
class PaymentUse {
  const PaymentUse({
    required this.spend,
    required this.taken,
    required this.leftAfter,
  });

  final TransactionRecord spend;

  /// How much of [spend] came out of this payment. Less than the whole
  /// amount when an earlier payment paid for part of it, or this one ran out
  /// part way.
  final double taken;

  final double leftAfter;

  bool get isPart => taken < (spend.amount ?? 0) - 0.005;
}

/// One big payment and everything counted against it.
class BigPayment {
  BigPayment(this.credit)
    : amount = credit.amount ?? 0,
      arrivedAt = credit.occurredAt!;

  final TransactionRecord credit;
  final double amount;
  final DateTime arrivedAt;

  String get from => credit.counterpartyKey ?? '';

  final List<PaymentUse> uses = [];

  double get used => uses.fold(0.0, (t, u) => t + u.taken);
  double get left => (amount - used).clamp(0, amount);
  bool get isGone => left < 0.5;

  /// When the last of it went, or null while some is left.
  DateTime? get goneOn =>
      isGone && uses.isNotEmpty ? uses.last.spend.occurredAt : null;

  /// Days from arrival until it was all gone, counting the day it arrived as
  /// day one. Null while some is left.
  int? get daysToGo {
    final gone = goneOn;
    if (gone == null) return null;
    DateTime date(DateTime d) => DateTime(d.year, d.month, d.day);
    return date(gone).difference(date(arrivedAt)).inDays + 1;
  }

  void _take(TransactionRecord spend, double take) {
    uses.add(PaymentUse(spend: spend, taken: take, leftAfter: left - take));
  }
}

/// Whether a transaction is money arriving that counts as a big payment.
bool isBigPayment(
  TransactionRecord t, {
  String? ownerName,
  Set<String> ownKeys = const {},
  double floor = bigPaymentFloor,
}) =>
    t.kind == AlertKind.credit &&
    !t.isReversal &&
    t.occurredAt != null &&
    (t.amount ?? 0) >= floor &&
    // Money moved in from the user's own other account is not new money.
    !isOwnTransfer(t, ownerName: ownerName, ownKeys: ownKeys);

/// Whether a transaction is money genuinely leaving the user.
bool _isSpending(TransactionRecord t, String? ownerName, Set<String> ownKeys) {
  if (t.occurredAt == null || (t.amount ?? 0) <= 0) return false;
  if (effectOf(t) >= 0) return false;
  // A bank taking back money it credited by mistake is not spending either.
  if (t.kind == AlertKind.debit && t.isReversal) return false;
  // Moving money to your own account is not spending it.
  return !isOwnTransfer(t, ownerName: ownerName, ownKeys: ownKeys);
}

/// Every big payment in [transactions] and what was counted against it,
/// newest first.
List<BigPayment> whereBigPaymentsWent(
  List<TransactionRecord> transactions, {
  String? ownerName,
  Set<String> ownKeys = const {},
  double floor = bigPaymentFloor,
}) {
  final payments =
      transactions
          .where(
            (t) => isBigPayment(
              t,
              ownerName: ownerName,
              ownKeys: ownKeys,
              floor: floor,
            ),
          )
          .map(BigPayment.new)
          .toList()
        ..sort((a, b) => compareTransactions(a.credit, b.credit));
  if (payments.isEmpty) return const [];

  final sorted = transactions.where((t) => t.occurredAt != null).toList()
    ..sort(compareTransactions);
  final declined = declinedDebits(sorted);
  final spending = sorted
      .where(
        (t) =>
            !declined.contains(t.smsId) && _isSpending(t, ownerName, ownKeys),
      )
      .toList();

  for (final spend in spending) {
    var owed = spend.amount!;
    // Oldest first, and only payments that had already arrived.
    for (final p in payments) {
      if (owed <= 0.005) break;
      if (p.arrivedAt.isAfter(spend.occurredAt!)) break;
      if (p.isGone) continue;
      final take = owed < p.left ? owed : p.left;
      p._take(spend, take);
      owed -= take;
    }
  }

  return payments.reversed.toList();
}
