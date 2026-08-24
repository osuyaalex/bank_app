// Dev utility: runs the migration plan over an SMS dump. Writes nothing.
// Usage: dart run tool/migration_dryrun.dart <dump> "<owner name>"
import 'dart:io';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:banking_app/data/migration_plan.dart';
import 'package:banking_app/data/models.dart';

void main(List<String> args) {
  final raw = File(args.first).readAsStringSync();
  final owner = args.length > 1 ? args[1] : null;
  final rows = ('\n$raw').split(RegExp(r'\nRow: \d+ '));
  final re = RegExp(r'address=(.*?), date=(\d+), body=(.*)$', dotAll: true);

  final alerts = <String, BankAlert>{};
  var i = 0;
  for (final r in rows) {
    final m = re.firstMatch(r);
    if (m == null) continue;
    final a = parseAlert(m.group(1)!, m.group(3)!);
    if (a != null) alerts['sms_${i++}'] = a;
  }

  final map = canonicaliseKeys(
      seedCounterparties(alerts.values, ownerName: owner));
  final inst = map.values.where((e) => isInstitutionOnlyKey(e.key)).length;
  final self = map.values
      .where((e) => e.disposition == Disposition.notSpending)
      .toList();

  print('parsed alerts        : ${alerts.length}');
  print('counterparties seeded: ${map.length}');
  print('  institution-only (locked to ask): $inst');
  print('  proposed as own account         : ${self.length}');
  for (final e in self) {
    print('      ${e.key}  (${e.txCount} txns)');
  }

  print('\nbatch-tag screen, top 20:');
  final cands = batchTagCandidates(map, limit: 20);
  var covered = 0;
  for (final e in cands) {
    covered += e.txCount;
    print('   ${e.txCount.toString().padLeft(3)}x  ${e.key}');
  }
  final spendable = map.values
      .where((e) => e.disposition != Disposition.notSpending)
      .fold<int>(0, (s, e) => s + e.txCount);
  print('   -> ${(covered / spendable * 100).toStringAsFixed(0)}% of remaining transactions');

  // Records for the most recent month present in the data.
  final months = alerts.values
      .where((a) => a.occurredAt != null)
      .map((a) => monthKeyOf(a.occurredAt!))
      .toSet()
      .toList()
    ..sort();
  final current = months.last;
  final records = <TransactionRecord>[];
  alerts.forEach((id, a) {
    if (a.occurredAt != null && monthKeyOf(a.occurredAt!) == current) {
      records.add(recordFor(id, a, map));
    }
  });
  final byStatus = <String, int>{};
  for (final r in records) {
    byStatus[r.status.name] = (byStatus[r.status.name] ?? 0) + 1;
  }
  print('\nbackfill for $current: ${records.length} records  $byStatus');
  print('legacy key check: August2026 -> ${legacyMonthKey("August2026")}, '
      'Jan 2025 -> ${legacyMonthKey("January2025")}');
}
