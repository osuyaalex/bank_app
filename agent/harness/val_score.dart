// The validation signal: a count, and nothing else.
//
//   dart run agent/harness/val_score.dart
//
// Deliberately says less than the main evaluator. It reports how many
// validation cases pass and never which ones, never which field, never what
// was expected. A candidate can tell whether it is generalising; it cannot
// tune against the answers, because it is not given any.
import 'dart:io';

import 'package:banking_app/parsing/bank_alert.dart';

import '../lib/case_model.dart';
import '../lib/score.dart';
import '../out/current/fallback.dart';

BankAlert? _fallbackThenShipped(String sender, String body) =>
    parseFallback(sender, body) ?? parseAlert(sender, body);

void main() {
  final cases = loadCases('agent/cases/.val_sealed.json');
  final report = runEval(cases, parse: _fallbackThenShipped);
  stdout.writeln('validation: ${report.passed}/${report.total} passing');
  if (report.passed < report.total) {
    stdout.writeln('(which ones, and why, is deliberately not shown)');
  }
}
