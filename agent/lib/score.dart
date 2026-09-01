// Scores a parser against the evaluation cases.
//
// The primary metric is deliberately strict: a case counts only when every
// field a user would notice is right. A parser that finds the amount but
// files the payment under the wrong name has not helped anybody, and a
// field-level average would hide that.
import 'package:banking_app/parsing/bank_alert.dart';

import 'case_model.dart';

class FieldResult {
  const FieldResult(this.name, this.ok, this.expected, this.actual);
  final String name;
  final bool ok;
  final String expected;
  final String actual;
}

class CaseResult {
  CaseResult(this.evalCase, this.fields);
  final EvalCase evalCase;
  final List<FieldResult> fields;

  bool get ok => fields.every((f) => f.ok);
  Iterable<FieldResult> get failures => fields.where((f) => !f.ok);
}

String _s(Object? v) => v == null ? '-' : '$v';

/// Money is compared to the kobo. Anything looser lets a parser that reads
/// 1,200.00 as 1.2 pass.
bool _sameMoney(double? a, double? b) {
  if (a == null || b == null) return a == b;
  return (a - b).abs() < 0.005;
}

/// Dates are compared to the minute. Banks write seconds inconsistently and
/// nothing in the app depends on them.
bool _sameInstant(DateTime? a, String? bIso) {
  if (bIso == null) return a == null;
  if (a == null) return false;
  final b = DateTime.parse(bIso);
  return a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;
}

/// How a candidate reads a message. The shipped parser is one of these; so is
/// the shipped parser with a generated fallback behind it.
typedef ParseFn = BankAlert? Function(String sender, String body);

CaseResult scoreCase(EvalCase c, {ParseFn parse = parseAlert}) {
  final alert = parse(c.sender, c.body);
  final e = c.expected;
  final fields = <FieldResult>[];

  // 1. Did we recognise it as a bank alert at all?
  final detected = alert != null;
  fields.add(FieldResult(
      'detected', detected == e.isBankAlert, '${e.isBankAlert}', '$detected'));

  // A message that should have been ignored and was ignored is fully correct;
  // there is nothing else to check.
  if (!e.isBankAlert) return CaseResult(c, fields);

  // A missed bank alert fails every remaining field rather than skipping them,
  // so the headline number reflects what the user actually lost.
  if (alert == null) {
    fields.add(FieldResult('kind', false, _s(e.kind), 'not parsed'));
    fields.add(FieldResult('amount', false, _s(e.amount), 'not parsed'));
    if (e.occurredAtIso != null) {
      fields.add(FieldResult('date', false, _s(e.occurredAtIso), 'not parsed'));
    }
    if (e.counterpartyKey != null) {
      fields.add(
          FieldResult('counterparty', false, _s(e.counterpartyKey), 'not parsed'));
    }
    return CaseResult(c, fields);
  }

  final kind = alert.kind.name;
  fields.add(FieldResult('kind', kind == e.kind, _s(e.kind), kind));
  fields.add(FieldResult('amount', _sameMoney(alert.amount, e.amount),
      _s(e.amount), _s(alert.amount)));

  if (e.occurredAtIso != null) {
    fields.add(FieldResult(
        'date',
        _sameInstant(alert.occurredAt, e.occurredAtIso),
        _s(e.occurredAtIso),
        _s(alert.occurredAt?.toIso8601String())));
  }
  if (e.counterpartyKey != null) {
    fields.add(FieldResult('counterparty',
        alert.counterpartyKey == e.counterpartyKey,
        _s(e.counterpartyKey), _s(alert.counterpartyKey)));
  }
  if (e.balanceAfter != null) {
    fields.add(FieldResult('balance',
        _sameMoney(alert.balanceAfter, e.balanceAfter),
        _s(e.balanceAfter), _s(alert.balanceAfter)));
  }
  return CaseResult(c, fields);
}

class Report {
  Report(this.results);
  final List<CaseResult> results;

  int get total => results.length;
  int get passed => results.where((r) => r.ok).length;
  double get rate => total == 0 ? 0 : passed / total;

  List<CaseResult> get holdouts =>
      results.where((r) => r.evalCase.holdout).toList();
  int get holdoutPassed => holdouts.where((r) => r.ok).length;
}

Report runEval(List<EvalCase> cases, {ParseFn parse = parseAlert}) =>
    Report(cases.map((c) => scoreCase(c, parse: parse)).toList(growable: false));
