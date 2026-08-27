import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/data/migration_plan.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:banking_app/story/demo_inbox.dart';

void main() {
  final now = DateTime(2026, 8, 27, 20);
  final inbox = DemoInbox.build(now);

  test('the made-up inbox reads as real bank alerts', () {
    final parsed = [
      for (final m in inbox)
        if (parseAlert(m.sender, m.body) != null) m
    ];
    // If the app cannot read its own demo data the screenshots are worthless.
    expect(parsed.length, inbox.length,
        reason: 'every demo message must parse');
    expect(inbox.length, greaterThan(200));
  });

  test('it covers enough months for a budget to be worked out', () {
    final months = <String>{};
    for (final m in inbox) {
      final a = parseAlert(m.sender, m.body)!;
      months.add(monthKeyOf(a.occurredAt ?? m.receivedAt!));
    }
    expect(months.length, greaterThanOrEqualTo(7));
  });

  test('nothing after today, so the current month reads as part-way through',
      () {
    for (final m in inbox) {
      final a = parseAlert(m.sender, m.body)!;
      // Wema prints no date, and the migration dates those from the message
      // that carried them. Same rule here.
      final at = a.occurredAt ?? m.receivedAt!;
      expect(at.isAfter(now), isFalse);
    }
  });

  test('money moves in both directions, and fees are charges', () {
    final kinds = <AlertKind, int>{};
    for (final m in inbox) {
      final a = parseAlert(m.sender, m.body)!;
      kinds.update(a.kind, (v) => v + 1, ifAbsent: () => 1);
    }
    expect(kinds[AlertKind.debit], greaterThan(100));
    expect(kinds[AlertKind.credit], greaterThan(5));
    expect(kinds[AlertKind.charge], greaterThan(20));
  });

  test('no real person appears in it', () {
    final joined = inbox.map((m) => m.body).join('\n').toUpperCase();
    for (final real in ['OSUYA', 'ALEXANDER', 'JESUTOFUNMI', 'CHARLES',
                        'ADEYEMI HENRY', 'ABUBAKAR', 'TIMOTHY OYEYEMI']) {
      expect(joined.contains(real), isFalse, reason: '$real must not appear');
    }
  });
}
