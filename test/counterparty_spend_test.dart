import 'package:banking_app/data/migration_plan.dart';
import 'package:banking_app/data/models.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

BankAlert _alert(
  String key, {
  AlertKind kind = AlertKind.debit,
  double amt = 100,
}) => BankAlert(
  bank: 'WEMA',
  kind: kind,
  channel: TxnChannel.transfer,
  narration: key,
  amount: amt,
  counterpartyKey: key,
  occurredAt: DateTime(2026, 8, 1),
);

/// What the user has paid a counterparty, which the sorting screen asks them
/// to file and until now could not show them.
///
/// A row saying "7 transactions" is the one fact that does not help: seven
/// payments to a name could be airtime or it could be rent, and nobody can
/// say where it belongs without knowing which.
void main() {
  group('what a counterparty has cost', () {
    test('debits are added up', () {
      final map = seedCounterparties([
        _alert('EBEANO', amt: 12000),
        _alert('EBEANO', amt: 8500),
      ]);
      expect(map['EBEANO']!.totalDebited, 20500);
      expect(map['EBEANO']!.txCount, 2);
    });

    test('money coming back does not reduce what was spent', () {
      // Credits annotate an entry; they never create or discount one. A
      // refund is not the user spending less, and the map exists to measure
      // spending.
      final map = seedCounterparties([
        _alert('MUSA', amt: 30000),
        _alert('MUSA', kind: AlertKind.credit, amt: 30000),
      ]);
      expect(map['MUSA']!.totalDebited, 30000);
      expect(map['MUSA']!.creditCount, 1);
    });

    test('an alert with no amount does not corrupt the total', () {
      final map = seedCounterparties([
        BankAlert(
          bank: 'WEMA',
          kind: AlertKind.debit,
          channel: TxnChannel.transfer,
          narration: 'GTB',
          counterpartyKey: 'GTB',
          occurredAt: DateTime(2026, 8, 1),
        ),
        _alert('GTB', amt: 5000),
      ]);
      expect(map['GTB']!.totalDebited, 5000);
    });

    test('truncated spellings of one person carry one figure', () {
      // SMS truncation yields three spellings of the same name. Merging the
      // count without merging the money would show a person's whole year of
      // payments against a third of what they cost.
      final map = canonicaliseKeys(
        seedCounterparties([
          _alert('ALEXANDER ADENIYI OSUYA', amt: 10000),
          _alert('ALEXANDER ADENIYI O', amt: 5000),
          _alert('ALEXANDER ADENI', amt: 2500),
        ]),
      );
      expect(map.keys, ['ALEXANDER ADENIYI OSUYA']);
      expect(map['ALEXANDER ADENIYI OSUYA']!.totalDebited, 17500);
    });
  });

  group('what to ask about first', () {
    test('the biggest spend leads, not the busiest name', () {
      // Ranking by count put twelve airtime top-ups ahead of one rent
      // payment, so the question that shapes the month arrived last.
      final map = seedCounterparties([
        for (var i = 0; i < 12; i++) _alert('AIRTIME', amt: 100),
        _alert('LANDLORD', amt: 400000),
      ]);
      expect(batchTagCandidates(map).map((e) => e.key), [
        'LANDLORD',
        'AIRTIME',
      ]);
    });

    test('the count still breaks a tie', () {
      final map = {
        'A': const CounterpartyEntry(key: 'A', txCount: 1, totalDebited: 5000),
        'B': const CounterpartyEntry(key: 'B', txCount: 9, totalDebited: 5000),
      };
      expect(batchTagCandidates(map).map((e) => e.key), ['B', 'A']);
    });

    test(
      'entries recorded before spending was tracked keep their old order',
      () {
        // Those carry a total of zero. Falling back to the count leaves them
        // exactly as they were rather than shuffling them arbitrarily.
        final map = {
          'QUIET': const CounterpartyEntry(key: 'QUIET', txCount: 2),
          'BUSY': const CounterpartyEntry(key: 'BUSY', txCount: 8),
        };
        expect(batchTagCandidates(map).map((e) => e.key), ['BUSY', 'QUIET']);
      },
    );
  });

  group('persistence', () {
    test('the figure survives a write', () {
      const e = CounterpartyEntry(
        key: 'EBEANO',
        txCount: 3,
        totalDebited: 20500,
      );
      expect(e.toMap()['totalDebited'], 20500);
    });

    test('copyWith keeps it unless asked to change it', () {
      const e = CounterpartyEntry(key: 'X', totalDebited: 1200);
      expect(e.copyWith(txCount: 9).totalDebited, 1200);
      expect(e.copyWith(totalDebited: 50).totalDebited, 50);
    });
  });
}
