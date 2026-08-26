import 'package:banking_app/data/migration_plan.dart';
import 'package:banking_app/data/models.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:banking_app/parsing/category_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

BankAlert alert(String key, AlertKind kind, double amount) => BankAlert(
      bank: 'WEMA',
      kind: kind,
      channel: TxnChannel.transfer,
      narration: key,
      amount: amount,
      counterpartyKey: key,
      occurredAt: DateTime(2026, 8, 1),
    );

void main() {
  group('money moving both ways', () {
    test('a credit annotates an existing counterparty', () {
      final map = seedCounterparties([
        alert('JOY ADAMS', AlertKind.debit, 5000),
        alert('JOY ADAMS', AlertKind.credit, 3000),
      ]);
      expect(map['JOY ADAMS']!.txCount, 1);
      expect(map['JOY ADAMS']!.creditCount, 1);
      expect(map['JOY ADAMS']!.isTwoWay, isTrue);
    });

    test('a credit never creates one', () {
      // Otherwise the batch screen fills with people who pay the user, which
      // is not spending and not something to categorise.
      final map = seedCounterparties([
        alert('EMPLOYER LTD', AlertKind.credit, 400000),
      ]);
      expect(map, isEmpty);
    });

    test('a shop stays one-way', () {
      final map = seedCounterparties([
        alert('CHOWDECK', AlertKind.debit, 4500),
        alert('CHOWDECK', AlertKind.debit, 3200),
      ]);
      expect(map['CHOWDECK']!.isTwoWay, isFalse);
    });

    test('the signal survives truncated spellings being merged', () {
      final merged = canonicaliseKeys(seedCounterparties([
        alert('ALEXANDER ADENIYI OSU', AlertKind.debit, 5000),
        alert('ALEXANDER ADENIYI OSUYA', AlertKind.debit, 5000),
        alert('ALEXANDER ADENIYI OSUYA', AlertKind.credit, 5000),
      ]));
      final entry = merged.values.first;
      expect(entry.txCount, 2);
      expect(entry.creditCount, 1);
    });
  });

  group('what it changes for a bare name', () {
    test('two-way money beats a neutral bucket', () {
      final g = guessCategory('JOY ADAMS', ['Others', 'Friends'],
          twoWayMoney: true)!;
      expect(g.categoryName, 'Friends');
      expect(g.reason, contains('both ways'));
    });

    test('one-way money lands in the neutral bucket', () {
      final g = guessCategory('JOY ADAMS', ['Others', 'Friends'])!;
      expect(g.categoryName, 'Others');
    });

    test('two-way money offers people buckets when none are tracked', () {
      final g =
          guessCategory('JOY ADAMS', ['Food'], twoWayMoney: true)!;
      expect(g.suggestedOptions, ['Friends', 'Family', 'Others']);
    });
  });

  group('round amounts', () {
    test('round figures are counted', () {
      final map = seedCounterparties([
        alert('JOY ADAMS', AlertKind.debit, 5000),
        alert('JOY ADAMS', AlertKind.debit, 20000),
        alert('JOY ADAMS', AlertKind.debit, 2847.50),
      ]);
      expect(map['JOY ADAMS']!.roundAmounts, 2);
      expect(map['JOY ADAMS']!.mostlyRound, isFalse);
    });

    test('a shop charging odd amounts is not round', () {
      final map = seedCounterparties([
        alert('CHOWDECK', AlertKind.debit, 4350.75),
        alert('CHOWDECK', AlertKind.debit, 3299),
      ]);
      expect(map['CHOWDECK']!.roundAmounts, 0);
    });
  });
}
