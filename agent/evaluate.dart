// Runs the parser over one or more case files and prints a scorecard.
//
//   dart run agent/evaluate.dart agent/cases/*.json
//
// Same command, same cases, for the baseline and for the agent's output.
// That is what makes the comparison fair.
import 'dart:io';

import 'lib/case_model.dart';
import 'lib/score.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run agent/evaluate.dart <case-file>...');
    exit(64);
  }
  final cases = <EvalCase>[];
  for (final path in args) {
    cases.addAll(loadCases(path));
  }
  final report = runEval(cases);

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
  if (failed.isEmpty) {
    stdout.writeln('  nothing failed.');
    return;
  }
  stdout.writeln('  FAILURES');
  for (final r in failed) {
    stdout.writeln('  ${r.evalCase.id}  ${r.evalCase.bank}'
        '${r.evalCase.holdout ? "  [held out]" : ""}');
    for (final f in r.failures) {
      stdout.writeln('      ${f.name.padRight(13)} want ${f.expected}'
          '   got ${f.actual}');
    }
  }
  stdout.writeln('');
  stdout.writeln('  ${failed.length} of ${report.total} cases failed.');
  exitCode = 1;
}
