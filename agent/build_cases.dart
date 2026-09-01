// Turns a private SMS dump into a publishable evaluation set.
//
//   dart run agent/build_cases.dart <dump-file>
//
// The dump itself never leaves the machine. What comes out is a small, hand-
// checkable set of cases with every real name, account number and phone
// number replaced. Replacement is consistent: one real person always becomes
// the same invented person, so counterparty grouping still means something.
//
// Two sets come out of this:
//
//   seen.json      formats the parser already handles. Expected values are
//                  taken from the current parser, which makes this a
//                  REGRESSION set, not a test of correctness. Its job is to
//                  catch an agent that fixes one bank by breaking another.
//   negative.json  real adverts, OTPs and telco balance texts. These carry
//                  amounts and the word "balance" and must be ignored.
import 'dart:convert';
import 'dart:io';

import 'lib/anonymise.dart';

import 'package:banking_app/parsing/bank_alert.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run agent/build_cases.dart <dump-file>');
    exit(64);
  }
  final raw = File(args.first).readAsStringSync();
  final rows = ('\n$raw').split(RegExp(r'\nRow: \d+ '));
  final re = RegExp(r'address=(.*?), date=(\d+), body=(.*)$', dotAll: true);

  final seen = <Map<String, dynamic>>[];
  final negative = <Map<String, dynamic>>[];
  final shapesTaken = <String>{};
  final perBucket = <String, int>{};
  final negTaken = <String>{};

  for (final r in rows) {
    final m = re.firstMatch(r);
    if (m == null) continue;
    final sender = m.group(1)!;
    final body = m.group(3)!.trim();
    if (body.isEmpty) continue;

    final alert = parseAlert(sender, body);
    if (alert != null && alert.amount != null) {
      // One case per distinct format shape, not per message. Fifty copies of
      // the same layout tell a judge nothing and make the file unreadable.
      // A judge has to be able to read this file. Four examples of each
      // bank/kind/channel combination is enough to catch a regression and
      // few enough that someone will actually look at them.
      final bucket = '${alert.bank}|${alert.kind.name}|${alert.channel.name}';
      final n = perBucket.update(bucket, (v) => v + 1, ifAbsent: () => 1);
      if (n > 4) continue;
      final shape = '$bucket|'
          '${body.replaceAll(RegExp(r'[\d,.]+'), '#').substring(0, body.length.clamp(0, 40))}';
      if (!shapesTaken.add(shape)) continue;
      final clean = anonymise(body);
      final reparsed = parseAlert(sender, clean);
      // If anonymising changed what the parser sees, the case would be a lie.
      if (reparsed == null ||
          reparsed.kind != alert.kind ||
          reparsed.amount != alert.amount) {
        continue;
      }
      seen.add({
        'id': 'seen-${seen.length.toString().padLeft(3, '0')}',
        'bank': reparsed.bank,
        'sender': sender,
        'body': clean,
        'holdout': false,
        'note': 'Format the parser already handles. Regression guard.',
        'expected': {
          'isBankAlert': true,
          'kind': reparsed.kind.name,
          'amount': reparsed.amount,
          'occurredAt': reparsed.occurredAt?.toIso8601String(),
          'counterpartyKey': reparsed.counterpartyKey,
          'balanceAfter': reparsed.balanceAfter,
        },
      });
    } else if (alert == null) {
      // Negative cases only matter when they look like money.
      final looksMonetary = RegExp(r'(NGN|N|₦)\s?[\d,]+').hasMatch(body) &&
          RegExp(r'\b(bal|balance|debit|credit|expires|bonus)\b', caseSensitive: false)
              .hasMatch(body);
      if (!looksMonetary) continue;
      final key = sender + body.substring(0, body.length.clamp(0, 40));
      if (!negTaken.add(key)) continue;
      if (negative.length >= 12) continue;
      negative.add({
        'id': 'neg-${negative.length.toString().padLeft(3, '0')}',
        'bank': 'none',
        'sender': sender,
        'body': anonymise(body),
        'holdout': false,
        'note': 'Carries an amount but is not a transaction. Must be ignored.',
        'expected': {'isBankAlert': false},
      });
    }
  }

  final enc = const JsonEncoder.withIndent('  ');
  File('agent/cases/seen.json').writeAsStringSync(enc.convert(seen));
  File('agent/cases/negative.json').writeAsStringSync(enc.convert(negative));
  stdout.writeln('seen formats : ${seen.length}  -> agent/cases/seen.json');
  stdout.writeln('negative     : ${negative.length}  -> agent/cases/negative.json');
  stdout.writeln('names mapped : ${nameMap.length}');
}
