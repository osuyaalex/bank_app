// Dev utility: what a batch-tag screen would contain, from real history.
import 'dart:io';
import 'package:banking_app/parsing/bank_alert.dart';

void main(List<String> args) {
  final raw = File(args.first).readAsStringSync();
  final rows = ('\n$raw').split(RegExp(r'\nRow: \d+ '));
  final re = RegExp(r'address=(.*?), date=(\d+), body=(.*)$', dotAll: true);

  final alerts = <BankAlert>[];
  for (final r in rows) {
    final m = re.firstMatch(r);
    if (m == null) continue;
    final a = parseAlert(m.group(1)!, m.group(3)!);
    if (a != null) alerts.add(a);
  }

  final charges = alerts.where((a) => a.kind == AlertKind.charge);
  final chargeTotal = charges.fold<double>(0, (s, a) => s + (a.amount ?? 0));
  final debits = alerts.where((a) => a.isSpending).toList();
  final spendTotal = debits.fold<double>(0, (s, a) => s + (a.amount ?? 0));

  print('bank charges : ${charges.length} fees, NGN ${chargeTotal.toStringAsFixed(2)}');
  print('spending     : ${debits.length} debits, NGN ${spendTotal.toStringAsFixed(2)}');
  print('fees as % of spending: '
      '${(chargeTotal / spendTotal * 100).toStringAsFixed(2)}%\n');

  final count = <String, int>{}, value = <String, double>{};
  for (final a in debits) {
    final k = a.counterpartyKey;
    if (k == null) continue;
    count[k] = (count[k] ?? 0) + 1;
    value[k] = (value[k] ?? 0) + (a.amount ?? 0);
  }
  final top = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));

  print('distinct counterparties: ${count.length}');
  for (final n in [10, 20, 30]) {
    final covered = top.take(n).fold<int>(0, (s, k) => s + count[k]!);
    print('  tagging top $n covers ${(covered / debits.length * 100).toStringAsFixed(0)}%'
        ' of all transactions');
  }
  print('\ntop 12 by frequency:');
  for (final k in top.take(12)) {
    print('  ${count[k]!.toString().padLeft(3)}x  '
        'NGN ${value[k]!.toStringAsFixed(0).padLeft(9)}   $k');
  }
}
