/// Money the user has lent to people, and how much of it has come back.
///
/// Nigerians lend to friends and family all the time, and forget. The app sees
/// every transfer out and every transfer in, across every account on the phone,
/// with the other person's name on both. So it can notice ₦50,000 going to
/// Precious in June and nothing coming back from her since.
///
/// It cannot know that a transfer was a loan. A payment to a person could be a
/// gift, a debt being repaid, or dinner. So the app never decides: it offers
/// likely candidates and the user says which were loans. Only confirmed loans
/// are ever counted as owed.
library;

import '../parsing/bank_alert.dart';
import '../parsing/category_matcher.dart';
import '../parsing/merchant_dictionary.dart';
import 'models.dart';

/// What the user said about a transfer.
enum LoanDecision {
  /// A loan. Counted as owed until repaid or marked settled.
  loan,

  /// Not a loan. Never offered again.
  notLoan,

  /// A loan that has been settled outside what the app can see, in cash or
  /// by the other person paying for something. Owed nothing.
  settled,
}

/// The smallest transfer worth asking about.
///
/// Below this, a payment to a person is overwhelmingly food, transport or a
/// favour, and asking about each one would bury the few real loans.
const loanCandidateFloor = 5000.0;

/// How many candidates are offered at once. More than this is a chore.
const loanCandidateLimit = 8;

/// A transfer the user might want to mark as a loan.
class LoanCandidate {
  const LoanCandidate({required this.transfer, required this.hasSentBack});

  final TransactionRecord transfer;

  /// This person has sent the user money at some point. The strongest sign
  /// available that money moves both ways between them, which is what lending
  /// looks like.
  final bool hasSentBack;
}

/// One loan and what has been paid against it.
class LoanRow {
  const LoanRow({required this.transfer, required this.repaid});

  final TransactionRecord transfer;
  final double repaid;

  double get lent => transfer.amount ?? 0;
  double get outstanding => (lent - repaid).clamp(0, double.infinity);
  bool get isOpen => outstanding > 0.5;
}

/// Everything owed by one person.
class PersonOwing {
  const PersonOwing({
    required this.name,
    required this.loans,
    required this.repayments,
  });

  final String name;

  /// Oldest first.
  final List<LoanRow> loans;

  /// Money received from this person after their first loan, oldest first.
  final List<TransactionRecord> repayments;

  double get lent => loans.fold(0, (t, l) => t + l.lent);
  double get repaid => loans.fold(0, (t, l) => t + l.repaid);
  double get outstanding => loans.fold(0, (t, l) => t + l.outstanding);

  /// When the oldest loan still not fully repaid was made.
  DateTime? get oldestOpen => loans
      .where((l) => l.isOpen)
      .map((l) => l.transfer.occurredAt)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
}

/// Whether two counterparty keys are the same person.
///
/// The name on a transfer out and the name on a transfer in come from
/// different narrations, and banks truncate them differently: `PRECIOUS
/// OKAFOR` going out, `PRECIOUS OKAF` coming back. Exact equality would miss
/// most repayments.
bool samePerson(String a, String b) {
  String squash(String v) => v.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  final x = squash(a), y = squash(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  if (x.length >= 8 && y.length >= 8 && (x.startsWith(y) || y.startsWith(x))) {
    return true;
  }

  // Word by word, allowing either spelling to be cut short, and either order.
  List<String> words(String v) => v
      .toUpperCase()
      .split(RegExp(r'[^A-Z]+'))
      .where((w) => w.length >= 3)
      .toList();
  final wa = words(a), wb = words(b);
  if (wa.length < 2 || wb.length < 2) return false;
  bool match(String p, String q) =>
      p == q ||
      (p.length >= 3 && q.startsWith(p)) ||
      (q.length >= 3 && p.startsWith(q));
  final shorter = wa.length <= wb.length ? wa : wb;
  final longer = identical(shorter, wa) ? wb : wa;
  final matched = shorter.where((w) => longer.any((l) => match(w, l))).length;
  // Every word of the shorter name, and at least one of them a real name
  // rather than a three-letter stub.
  return matched == shorter.length && shorter.any((w) => w.length >= 4);
}

/// Whether a transfer out could plausibly be a loan to a person.
bool _isPersonTransfer(TransactionRecord t, String? ownerName) {
  if (t.kind != AlertKind.debit || t.isReversal) return false;
  final key = t.counterpartyKey;
  if (key == null || key.trim().isEmpty) return false;
  if (isInstitutionOnlyKey(key)) return false;
  if (looksLikeOwnAccount(key, ownerName)) return false;
  // A known business, even one whose name reads like a person's. Nobody lends
  // money to Shoprite.
  if (conceptsFor(key).isNotEmpty) return false;
  return looksLikePersonName(key);
}

/// Transfers worth asking the user about, most worth asking first.
///
/// A transfer is offered once. Anything already decided, either way, is left
/// alone.
List<LoanCandidate> loanCandidates(
  List<TransactionRecord> transactions, {
  required Map<String, LoanDecision> decisions,
  String? ownerName,
  int limit = loanCandidateLimit,
}) {
  final credits = transactions
      .where((t) => t.kind == AlertKind.credit && t.counterpartyKey != null)
      .toList();

  final out = <LoanCandidate>[];
  for (final t in transactions) {
    if (decisions.containsKey(t.smsId)) continue;
    if ((t.amount ?? 0) < loanCandidateFloor) continue;
    if (!_isPersonTransfer(t, ownerName)) continue;
    final sentBack = credits.any(
      (c) => samePerson(c.counterpartyKey!, t.counterpartyKey!),
    );
    out.add(LoanCandidate(transfer: t, hasSentBack: sentBack));
  }

  // People who have sent money back first, then the largest amounts, then the
  // most recent. A large round transfer to someone who once paid the user back
  // is the likeliest loan in the list.
  out.sort((a, b) {
    if (a.hasSentBack != b.hasSentBack) return a.hasSentBack ? -1 : 1;
    final byAmount = (b.transfer.amount ?? 0).compareTo(a.transfer.amount ?? 0);
    if (byAmount != 0) return byAmount;
    return (b.transfer.occurredAt ?? DateTime(0)).compareTo(
      a.transfer.occurredAt ?? DateTime(0),
    );
  });
  return out.take(limit).toList();
}

/// Who owes the user what, largest first.
///
/// Money received from a person after they were lent something is counted as
/// repayment, oldest loan first. Money received before the first loan is not:
/// it cannot be paying back something that had not happened yet.
List<PersonOwing> moneyOwed(
  List<TransactionRecord> transactions, {
  required Map<String, LoanDecision> decisions,
}) {
  final loans =
      transactions
          .where(
            (t) =>
                t.kind == AlertKind.debit &&
                t.counterpartyKey != null &&
                t.occurredAt != null &&
                decisions[t.smsId] == LoanDecision.loan,
          )
          .toList()
        ..sort((a, b) => a.occurredAt!.compareTo(b.occurredAt!));

  // Group loans by person, tolerating the name being written differently.
  final groups = <List<TransactionRecord>>[];
  for (final l in loans) {
    final group = groups.firstWhere(
      (g) => samePerson(g.first.counterpartyKey!, l.counterpartyKey!),
      orElse: () {
        final g = <TransactionRecord>[];
        groups.add(g);
        return g;
      },
    );
    group.add(l);
  }

  final credits =
      transactions
          .where(
            (t) =>
                t.kind == AlertKind.credit &&
                !t.isReversal &&
                t.counterpartyKey != null &&
                t.occurredAt != null,
          )
          .toList()
        ..sort((a, b) => a.occurredAt!.compareTo(b.occurredAt!));

  final out = <PersonOwing>[];
  for (final group in groups) {
    final first = group.first.occurredAt!;
    final repayments = credits
        .where(
          (c) =>
              samePerson(c.counterpartyKey!, group.first.counterpartyKey!) &&
              c.occurredAt!.isAfter(first),
        )
        .toList();

    // Settle oldest loans first, but only with money that arrived after each
    // loan was made.
    final remaining = [for (final r in repayments) r.amount ?? 0];
    final rows = <LoanRow>[];
    for (final loan in group) {
      var owed = loan.amount ?? 0;
      var paid = 0.0;
      for (var i = 0; i < repayments.length && owed > 0.5; i++) {
        if (!repayments[i].occurredAt!.isAfter(loan.occurredAt!)) continue;
        final take = remaining[i] < owed ? remaining[i] : owed;
        remaining[i] -= take;
        owed -= take;
        paid += take;
      }
      rows.add(LoanRow(transfer: loan, repaid: paid));
    }

    out.add(
      PersonOwing(
        name: _bestName(group.map((t) => t.counterpartyKey!)),
        loans: rows,
        repayments: repayments,
      ),
    );
  }

  out.removeWhere((p) => p.outstanding <= 0.5);
  out.sort((a, b) => b.outstanding.compareTo(a.outstanding));
  return out;
}

/// The fullest spelling of a name seen, since truncation only ever removes.
String _bestName(Iterable<String> keys) =>
    keys.reduce((a, b) => b.length > a.length ? b : a);

/// A short, friendly reminder the user can paste into a chat.
String reminderText(PersonOwing p, {required String currency}) {
  final first = p.name.split(RegExp(r'\s+')).first;
  final name = first.isEmpty
      ? ''
      : ' ${first[0]}${first.substring(1).toLowerCase()}';
  return 'Hi$name, just a gentle reminder about the '
      '$currency${_money(p.outstanding)} I sent you. '
      'Let me know when you can sort it. Thanks!';
}

String _money(double v) => v.round().toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
