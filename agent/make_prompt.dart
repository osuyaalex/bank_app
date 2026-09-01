// Builds the task prompt from the cases the shipped parser fails.
//
//   dart run agent/make_prompt.dart agent/cases/holdout.json
//
// The baseline and the agent are given the same prompt from the same command.
// The only difference between them is what they are allowed to do with it:
// the baseline answers in one turn with no tools, the agent may read the repo
// and run the evaluator until it passes.
import 'dart:io';

import 'lib/case_model.dart';
import 'lib/score.dart';

void main(List<String> args) {
  final cases = <EvalCase>[];
  for (final p in args) {
    cases.addAll(loadCases(p));
  }
  // Every case the shipped parser gets wrong, not only the ones it fails to
  // detect. A message that parses with the wrong counterparty is just as
  // broken from the user's side.
  final failing = cases.where((c) => !scoreCase(c).ok).toList();

  final b = StringBuffer()
    ..writeln('The app below reads Nigerian bank SMS alerts with a hand-written parser.')
    ..writeln('Banks it has never been taught are not being read at all.')
    ..writeln()
    ..writeln(File('agent/harness/contract.md').readAsStringSync())
    ..writeln()
    ..writeln('# The messages it cannot read')
    ..writeln()
    ..writeln('${failing.length} of ${cases.length} cases. For each, the message as it')
    ..writeln('arrives and what a correct parse looks like.')
    ..writeln();

  for (final c in failing) {
    final e = c.expected;
    b
      ..writeln('## ${c.id}  (${c.bank})')
      ..writeln('sender: ${c.sender}')
      ..writeln('body:')
      ..writeln('```')
      ..writeln(c.body)
      ..writeln('```')
      ..writeln('expected: kind=${e.kind} amount=${e.amount} '
          'date=${e.occurredAtIso ?? "-"} counterparty=${e.counterpartyKey ?? "-"} '
          'balance=${e.balanceAfter ?? "-"}')
      ..writeln();
  }

  b
    ..writeln('# Answer with')
    ..writeln()
    ..writeln('The complete contents of agent/out/current/fallback.dart in a single')
    ..writeln('```dart fenced block. No prose outside the block.');

  stdout.write(b);
}
