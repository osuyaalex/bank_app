// Scores the shipped parser WITH a generated fallback behind it.
//
//   dart run agent/harness/run_with_fallback.dart agent/cases/*.json
//
// Identical to agent/evaluate.dart except for which parse function it uses,
// so a difference in the score is a difference in the parsing and nothing
// else.
import 'dart:io';

import 'package:banking_app/parsing/bank_alert.dart';

import '../lib/case_model.dart';
import '../lib/score.dart';
import '../out/current/fallback.dart';

/// The fallback is asked first and wins when it answers.
///
/// This is deliberate. If the fallback could only speak where the shipped
/// parser stayed silent, it could never correct a message that parses but
/// parses wrongly -- and it could never break anything either, which would
/// make the regression cases decoration. Giving it precedence puts all 29
/// working formats genuinely at risk, so the seen cases have to be earned
/// every run.
BankAlert? _fallbackThenShipped(String sender, String body) =>
    parseFallback(sender, body) ?? parseAlert(sender, body);

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run agent/harness/run_with_fallback.dart <case-file>...');
    exit(64);
  }
  final cases = <EvalCase>[];
  for (final p in args) {
    cases.addAll(loadCases(p));
  }
  final report = runEval(cases, parse: _fallbackThenShipped);

  stdout.writeln('');
  stdout.writeln('  cases            ${report.total}');
  stdout.writeln('  fully correct    ${report.passed}'
      '   (${(report.rate * 100).toStringAsFixed(1)}%)');
  if (report.holdouts.isNotEmpty) {
    stdout.writeln('  held-out banks   ${report.holdoutPassed}'
        '/${report.holdouts.length}   <- the number that matters');
  }
  stdout.writeln('');

  final failed = report.results.where((r) => !r.ok).toList();
  for (final r in failed) {
    stdout.writeln('  ${r.evalCase.id}  ${r.evalCase.bank}'
        '${r.evalCase.holdout ? "  [held out]" : ""}');
    for (final f in r.failures) {
      stdout.writeln('      ${f.name.padRight(13)} want ${f.expected}   got ${f.actual}');
    }
  }
  if (failed.isEmpty) stdout.writeln('  nothing failed.');
  stdout.writeln('');
  stdout.writeln('  ${failed.length} of ${report.total} cases failed.');
  if (failed.isNotEmpty) exitCode = 1;
}
