// One evaluation case: a bank alert as it arrives, and what a correct parse
// of it looks like.
//
// Cases are the contract between the baseline, the agent and the judge. They
// are deliberately plain data so that a reader can check a case by eye without
// running anything.
import 'dart:convert';
import 'dart:io';

class ExpectedParse {
  const ExpectedParse({
    required this.isBankAlert,
    this.kind,
    this.amount,
    this.occurredAtIso,
    this.counterpartyKey,
    this.balanceAfter,
  });

  /// False for the negative cases: adverts, OTPs, scam texts. A parser that
  /// reads those as spending is worse than one that misses a real payment,
  /// so they are scored the same as everything else.
  final bool isBankAlert;

  /// 'debit', 'credit' or 'charge'.
  final String? kind;
  final double? amount;
  final String? occurredAtIso;
  final String? counterpartyKey;
  final double? balanceAfter;

  static ExpectedParse fromJson(Map<String, dynamic> j) => ExpectedParse(
        isBankAlert: j['isBankAlert'] as bool,
        kind: j['kind'] as String?,
        amount: (j['amount'] as num?)?.toDouble(),
        occurredAtIso: j['occurredAt'] as String?,
        counterpartyKey: j['counterpartyKey'] as String?,
        balanceAfter: (j['balanceAfter'] as num?)?.toDouble(),
      );
}

class EvalCase {
  const EvalCase({
    required this.id,
    required this.bank,
    required this.sender,
    required this.body,
    required this.expected,
    this.note,
    this.holdout = false,
  });

  final String id;
  final String bank;
  final String sender;
  final String body;
  final ExpectedParse expected;

  /// Why this case is here. Written for a judge reading the file cold.
  final String? note;

  /// Held-out cases are the ones the parser has never been taught. They are
  /// the whole point of the exercise: the agent has to earn these.
  final bool holdout;

  static EvalCase fromJson(Map<String, dynamic> j) => EvalCase(
        id: j['id'] as String,
        bank: j['bank'] as String,
        sender: j['sender'] as String,
        body: j['body'] as String,
        expected: ExpectedParse.fromJson(j['expected'] as Map<String, dynamic>),
        note: j['note'] as String?,
        holdout: (j['holdout'] as bool?) ?? false,
      );
}

List<EvalCase> loadCases(String path) {
  final raw = File(path).readAsStringSync();
  final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  return list.map(EvalCase.fromJson).toList();
}
