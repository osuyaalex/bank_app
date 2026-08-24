// Dev utility: runs the parsers over an adb SMS dump and reports coverage.
// Usage: dart run tool/parse_corpus.dart <dump-file>
// The dump contains personal data and is never committed.
import 'dart:io';
import 'package:banking_app/parsing/bank_alert.dart';

void main(List<String> args) {
  final raw = File(args.first).readAsStringSync();
  final rows = ('\n$raw').split(RegExp(r'\nRow: \d+ '));
  final re = RegExp(r'address=(.*?), date=(\d+), body=(.*)$', dotAll: true);

  final byBank = <String, List<BankAlert>>{};
  var seen = 0, parsed = 0;
  final noAmount = <BankAlert>[], noKey = <BankAlert>[];

  for (final r in rows) {
    final m = re.firstMatch(r);
    if (m == null) continue;
    final sender = m.group(1)!;
    if (!sender.toUpperCase().contains('ZENITH') &&
        !sender.toUpperCase().contains('WEMA')) continue;
    seen++;
    final a = parseAlert(sender, m.group(3)!);
    if (a == null) continue;
    parsed++;
    byBank.putIfAbsent(a.bank, () => []).add(a);
    if (a.amount == null) noAmount.add(a);
    if (a.isSpending && a.counterpartyKey == null) noKey.add(a);
  }

  print('bank messages: $seen   parsed: $parsed   skipped (non-txn): ${seen - parsed}\n');

  for (final e in byBank.entries) {
    final all = e.value;
    final debits = all.where((a) => a.isSpending).toList();
    final withDate = all.where((a) => a.occurredAt != null).length;
    final withBal = all.where((a) => a.balanceAfter != null).length;
    final keys = debits.map((a) => a.counterpartyKey).whereType<String>().toSet();
    print('${e.key}: ${all.length} alerts, ${debits.length} debits');
    print('   amount parsed : ${all.where((a) => a.amount != null).length}/${all.length}');
    print('   date parsed   : $withDate/${all.length}');
    print('   balance parsed: $withBal/${all.length}');
    print('   counterparty  : ${debits.where((a) => a.counterpartyKey != null).length}/${debits.length}'
        '  (${keys.length} distinct)');
    final ch = <String, int>{};
    for (final a in debits) {
      ch[a.channel.name] = (ch[a.channel.name] ?? 0) + 1;
    }
    print('   channels      : $ch');
    print('   sample keys   : ${keys.take(6).toList()}');
    print('');
  }

  if (noAmount.isNotEmpty) {
    print('!! ${noAmount.length} alerts with no amount, e.g. ${noAmount.first.narration}');
  }
  if (noKey.isNotEmpty) {
    print('!! ${noKey.length} debits with no counterparty, e.g.:');
    for (final a in noKey.take(5)) {
      print('     ${a.bank}  ${a.narration}');
    }
  }
}
