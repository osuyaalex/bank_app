// Dev utility: how much history does the counterparty map actually need?
import 'dart:io';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:banking_app/data/migration_plan.dart';
import 'package:banking_app/data/models.dart';

void main(List<String> args) {
  final raw = File(args.first).readAsStringSync();
  final rows = ('\n$raw').split(RegExp(r'\nRow: \d+ '));
  final re = RegExp(r'address=(.*?), date=(\d+), body=(.*)$', dotAll: true);

  final alerts = <BankAlert>[];
  for (final r in rows) {
    final m = re.firstMatch(r);
    if (m == null) continue;
    final a = parseAlert(m.group(1)!, m.group(3)!);
    if (a?.occurredAt != null) alerts.add(a!);
  }
  final newest = alerts.map((a) => a.occurredAt!).reduce((a, b) => a.isAfter(b) ? a : b);

  List<String> topOf(int months) {
    final cutoff = DateTime(newest.year, newest.month - months, newest.day);
    final win = alerts.where((a) => a.occurredAt!.isAfter(cutoff));
    final map = canonicaliseKeys(seedCounterparties(win));
    return batchTagCandidates(map, limit: 20).map((e) => e.key).toList();
  }

  final full = topOf(120);
  print('window   counterparties   worth-writing(2+)   top20 overlap with full');
  for (final months in [1, 2, 3, 6, 12]) {
    final cutoff = DateTime(newest.year, newest.month - months, newest.day);
    final win = alerts.where((a) => a.occurredAt!.isAfter(cutoff)).toList();
    final map = canonicaliseKeys(seedCounterparties(win));
    final repeat = map.values.where((e) => e.txCount >= 2).length;
    final top = topOf(months);
    final overlap = top.where(full.contains).length;
    print('${months.toString().padLeft(2)}mo'
        '   ${win.length.toString().padLeft(5)} alerts'
        '   ${map.length.toString().padLeft(4)}'
        '   ${repeat.toString().padLeft(4)}'
        '   ${overlap.toString().padLeft(4)}/20');
  }
  print('\nfull-history top 8: ${full.take(8).toList()}');
  print('1-month    top 8: ${topOf(1).take(8).toList()}');
}
