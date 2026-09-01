// Checks a candidate against real traffic, with no answer key.
//
//   dart run agent/harness/corpus_probe.dart
//
// The evaluation cases have expected values, and a candidate that iterates
// against them learns those cases. This does something different: it runs the
// candidate over 2,419 real bank messages that nobody has labelled, and
// reports three things it can know without an answer key.
//
//   crashes        a rule that throws on real input is broken, full stop
//   newly read     messages the shipped parser could not read and this can
//   disagreements  messages the shipped parser DID read, where this candidate
//                  says something different. One of the two is wrong, and the
//                  shipped parser has been right for 2,367 of them.
//
// Disagreements are the useful signal. A careless regular expression written
// to catch one bank shows up here as fifty arguments with a parser that was
// already correct.
//
// Nothing personal is printed. Every example goes through the same
// anonymiser that produces the publishable cases, because these runs end up
// in a submitted trajectory.
import 'dart:io';

import 'package:banking_app/parsing/bank_alert.dart';

import '../lib/anonymise.dart';
import '../out/current/fallback.dart';

const _defaultDump = 'bank-sms-dump.txt';

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '.';
  final path = args.isNotEmpty ? args.first : '$home/$_defaultDump';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('No corpus at $path.');
    stderr.writeln('This check needs the private SMS dump. Skipping is fine;');
    stderr.writeln('the case files do not depend on it.');
    exit(0);
  }

  final rows = ('\n${file.readAsStringSync()}').split(RegExp(r'\nRow: \d+ '));
  final re = RegExp(r'address=(.*?), date=(\d+), body=(.*)$', dotAll: true);

  var messages = 0, crashes = 0, newlyRead = 0, agreed = 0, deferred = 0;
  var bothSilent = 0, disagreed = 0;
  final disagreements = <String>[];
  final crashExamples = <String>[];

  for (final r in rows) {
    final m = re.firstMatch(r);
    if (m == null) continue;
    final sender = m.group(1)!;
    final body = m.group(3)!.trim();
    if (body.isEmpty) continue;
    messages++;

    final shipped = parseAlert(sender, body);
    BankAlert? mine;
    try {
      mine = parseFallback(sender, body);
    } catch (e) {
      crashes++;
      if (crashExamples.length < 3) {
        crashExamples.add('${anonymise(body).split("\n").first}\n      threw $e');
      }
      continue;
    }

    if (shipped == null && mine != null) {
      newlyRead++;
      continue;
    }
    if (shipped != null && mine == null) {
      // Correct behaviour, not a miss: the candidate declined and left a
      // working format to the parser that already handles it.
      deferred++;
      continue;
    }
    if (shipped == null && mine == null) {
      bothSilent++;
      continue;
    }
    if (shipped == null || mine == null) continue; // handled above
    final a = shipped;
    final b = mine;

    final differs = a.kind != b.kind ||
        a.amount != b.amount ||
        a.counterpartyKey != b.counterpartyKey ||
        a.occurredAt != b.occurredAt;
    if (!differs) {
      agreed++;
      continue;
    }
    disagreed++;
    if (disagreements.length < 8) {
      final what = <String>[];
      if (a.kind != b.kind) what.add('kind ${a.kind.name} vs ${b.kind.name}');
      if (a.amount != b.amount) what.add('amount ${a.amount} vs ${b.amount}');
      if (a.counterpartyKey != b.counterpartyKey) {
        what.add('key "${a.counterpartyKey}" vs "${b.counterpartyKey}"');
      }
      if (a.occurredAt != b.occurredAt) {
        what.add('date ${a.occurredAt} vs ${b.occurredAt}');
      }
      disagreements.add('${anonymise(body).split("\n").first}\n      ${what.join(", ")}');
    }
  }

  final totalDisagreed = disagreed;
  stdout
    ..writeln('')
    ..writeln('  real messages      $messages   (unlabelled: there is no right answer here)')
    ..writeln('  not a transaction  $bothSilent   (both of you ignored it)')
    ..writeln('  crashes            $crashes')
    ..writeln('  newly read         $newlyRead   (shipped parser could not, you can)')
    ..writeln('  agreed             $agreed   (both read it, same answer)')
    ..writeln('  left alone         $deferred   (you declined, shipped parser handled it)')
    ..writeln('  disagreed          $totalDisagreed   <- every one of these is a bug in one of you')
    ..writeln('');

  if (crashes > 0) {
    stdout.writeln('  CRASHES -- fix these first, they are unambiguous bugs');
    for (final c in crashExamples) {
      stdout.writeln('    $c');
    }
    stdout.writeln('');
  }
  if (disagreements.isNotEmpty) {
    stdout.writeln('  DISAGREEMENTS with a parser that reads 2,367 of these correctly.');
    stdout.writeln('  Every one is a bug in one of you. Assume it is yours.');
    for (final d in disagreements) {
      stdout.writeln('    $d');
    }
    if (totalDisagreed > disagreements.length) {
      stdout.writeln('    ... and ${totalDisagreed - disagreements.length} more');
    }
    stdout.writeln('');
  }
  if (crashes == 0 && disagreements.isEmpty) {
    stdout.writeln('  No crashes and no disagreements on real traffic.');
    stdout.writeln('');
  }
}
