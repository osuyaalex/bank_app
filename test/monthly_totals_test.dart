import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/data/migration_plan.dart';
import 'package:banking_app/data/models.dart';
import 'package:banking_app/parsing/bank_alert.dart';

BankAlert alert(
  String key,
  DateTime when, {
  double amount = 1000,
  AlertKind kind = AlertKind.debit,
  bool reversal = false,
}) =>
    BankAlert(
      bank: 'ZENITHBANK',
      kind: kind,
      channel: TxnChannel.transfer,
      narration: key,
      amount: amount,
      counterpartyKey: key,
      occurredAt: when,
      isReversal: reversal,
    );

Map<String, CounterpartyEntry> mapped(Map<String, String> keyToCategory) => {
      for (final e in keyToCategory.entries)
        e.key: CounterpartyEntry(
          key: e.key,
          categoryId: e.value,
          disposition: Disposition.tracked,
        ),
    };

final now = DateTime(2026, 8, 15);

void main() {
  group('monthly totals from the inbox', () {
    test('adds a category up within each month separately', () {
      final got = monthlyCategoryTotals(
        [
          alert('CHARLES OSUYA', DateTime(2026, 6, 3), amount: 20000),
          alert('CHARLES OSUYA', DateTime(2026, 6, 20), amount: 15000),
          alert('CHARLES OSUYA', DateTime(2026, 7, 8), amount: 40000),
        ],
        mapped({'CHARLES OSUYA': 'cat_family'}),
        {'Family'},
        now,
      );
      expect(got.byMonth['2026-06']!['cat_family'], 35000);
      expect(got.byMonth['2026-07']!['cat_family'], 40000);
    });

    test('money coming in is not spending', () {
      final got = monthlyCategoryTotals(
        [
          alert('CHARLES OSUYA', DateTime(2026, 6, 3), amount: 20000),
          alert('CHARLES OSUYA', DateTime(2026, 6, 4),
              amount: 500000, kind: AlertKind.credit),
        ],
        mapped({'CHARLES OSUYA': 'cat_family'}),
        {'Family'},
        now,
      );
      expect(got.byMonth['2026-06']!['cat_family'], 20000);
    });

    test('a reversed payment never counted, so it never inflates a budget', () {
      final got = monthlyCategoryTotals(
        [
          alert('PAYSTACK', DateTime(2026, 6, 3), amount: 5000),
          alert('PAYSTACK', DateTime(2026, 6, 4),
              amount: 300000, reversal: true),
        ],
        mapped({'PAYSTACK': 'cat_family'}),
        {'Family'},
        now,
      );
      expect(got.byMonth['2026-06']!['cat_family'], 5000);
    });

    test('transfers to the user themselves are left out', () {
      final got = monthlyCategoryTotals(
        [
          alert('ALEXANDER OSUYA', DateTime(2026, 6, 3), amount: 90000),
        ],
        {
          'ALEXANDER OSUYA': const CounterpartyEntry(
            key: 'ALEXANDER OSUYA',
            disposition: Disposition.notSpending,
          )
        },
        {'Family'},
        now,
      );
      expect(got.byMonth['2026-06'], isNull);
    });

    test('a counterparty with no category contributes nothing', () {
      final got = monthlyCategoryTotals(
        [alert('SOME RANDOM NAME', DateTime(2026, 6, 3), amount: 9000)],
        const {},
        {'Family'},
        now,
      );
      expect(got.byMonth, isEmpty);
    });

    test('the month in progress and the oldest month are marked partial', () {
      final got = monthlyCategoryTotals(
        [
          alert('CHARLES OSUYA', DateTime(2026, 4, 20), amount: 5000),
          alert('CHARLES OSUYA', DateTime(2026, 6, 3), amount: 20000),
          alert('CHARLES OSUYA', DateTime(2026, 8, 3), amount: 20000),
        ],
        mapped({'CHARLES OSUYA': 'cat_family'}),
        {'Family'},
        now,
      );
      expect(got.partialMonths, containsAll(['2026-08', '2026-04']));
      expect(got.partialMonths.contains('2026-06'), isFalse);
    });

    test('an alert with no date cannot be placed in a month', () {
      final got = monthlyCategoryTotals(
        [
          BankAlert(
            bank: 'ZENITHBANK',
            kind: AlertKind.debit,
            channel: TxnChannel.transfer,
            narration: 'CHARLES OSUYA',
            amount: 20000,
            counterpartyKey: 'CHARLES OSUYA',
          )
        ],
        mapped({'CHARLES OSUYA': 'cat_family'}),
        {'Family'},
        now,
      );
      expect(got.byMonth, isEmpty);
    });

    test('a tracked category wins over a wider name for the same money', () {
      // Airtime prefers a Mobile Phone category and settles for Internet. The
      // app, tracking only Internet, files it there -- so the history has to
      // say Internet too, even though Mobile Phone is the better name.
      final got = monthlyCategoryTotals(
        [alert('AIRTIME MTN', DateTime(2026, 6, 3), amount: 1000)],
        const {},
        {'Internet'},
        now,
        alsoConsider: {'Mobile Phone'},
      );
      expect(got.byMonth['2026-06']!.keys, ['cat_internet']);
    });

    test('the wider names are used only where tracking has nothing to say', () {
      final got = monthlyCategoryTotals(
        [alert('AIRTIME MTN', DateTime(2026, 6, 3), amount: 1000)],
        const {},
        {'Rent'},
        now,
        alsoConsider: {'Mobile Phone'},
      );
      expect(got.byMonth['2026-06']!.keys, ['cat_mobile_phone']);
    });
  });
}
