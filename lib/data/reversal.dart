import '../parsing/bank_alert.dart';
import 'models.dart';

/// One stored transaction, reduced to what deciding a reversal needs.
class ReversalCandidate {
  const ReversalCandidate({
    required this.id,
    required this.kind,
    required this.status,
    this.counterpartyKey,
    this.occurredAt,
    this.alreadyReversed = false,
  });

  final String id;
  final String kind;
  final String status;
  final String? counterpartyKey;
  final DateTime? occurredAt;
  final bool alreadyReversed;
}

/// Which stored transaction a reversal undoes, or null when none qualifies.
///
/// Callers have already narrowed [candidates] to an exact amount match, which
/// is the strongest signal available: a bank reverses the figure it took. What
/// is left is to reject the ones that cannot be it.
///
///  * Money has to have gone out. A reversal never undoes a credit.
///  * It has to have gone out *first*. A later transaction of the same value
///    is a different transaction.
///  * It cannot already be reversed, or a redelivered alert would take the
///    money off twice.
///  * Where both halves name a counterparty, they have to agree. Not every
///    format prints one on the reversal, and requiring it there would leave
///    the common case unmatched.
///
/// Where several survive, the nearest one before the reversal wins.
ReversalCandidate? pickReversed(
  List<ReversalCandidate> candidates, {
  required DateTime when,
  String? counterpartyKey,
}) {
  final viable = candidates.where((c) {
    if (c.alreadyReversed) return false;
    if (c.kind != AlertKind.debit.name && c.kind != AlertKind.charge.name) {
      return false;
    }
    if (c.occurredAt != null && c.occurredAt!.isAfter(when)) return false;
    if (c.counterpartyKey != null && counterpartyKey != null) {
      return c.counterpartyKey == counterpartyKey;
    }
    return true;
  }).toList();

  if (viable.isEmpty) return null;

  viable.sort((a, b) {
    final x = a.occurredAt ?? DateTime(1970);
    final y = b.occurredAt ?? DateTime(1970);
    return y.compareTo(x);
  });
  return viable.first;
}

/// How much a reversal takes back off a total, and from where.
///
/// A reversed spend comes off its category. A reversed bank charge comes off
/// the charges line. Anything else was never in a total to begin with.
({String? categoryId, bool isCharge, double amount}) reversalEffect({
  required String kind,
  required String status,
  required String? categoryId,
  required double amount,
}) {
  if (status == TxnStatus.labeled.name && categoryId != null) {
    return (categoryId: categoryId, isCharge: false, amount: amount);
  }
  if (kind == AlertKind.charge.name) {
    return (categoryId: null, isCharge: true, amount: amount);
  }
  return (categoryId: null, isCharge: false, amount: 0);
}
