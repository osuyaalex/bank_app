import 'package:banking_app/data/big_payments.dart';
import 'package:banking_app/data/models.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _d(int m, int d, [int h = 12]) => DateTime(2026, m, d, h);

TransactionRecord _in(
  String id,
  String from,
  double amount,
  DateTime when, {
  bool reversal = false,
}) => TransactionRecord(
  smsId: id,
  bank: 'ZENITH',
  kind: AlertKind.credit,
  channel: TxnChannel.transfer,
  status: TxnStatus.excluded,
  amount: amount,
  occurredAt: when,
  counterpartyKey: from,
  isReversal: reversal,
);

TransactionRecord _out(
  String id,
  double amount,
  DateTime when, {
  String to = 'SOMEONE',
  String? category,
  TxnStatus? status,
  AlertKind kind = AlertKind.debit,
  bool reversal = false,
}) => TransactionRecord(
  smsId: id,
  bank: 'ZENITH',
  kind: kind,
  channel: TxnChannel.transfer,
  status: status ?? (category == null ? TxnStatus.pending : TxnStatus.labeled),
  amount: amount,
  occurredAt: when,
  counterpartyKey: to,
  categoryId: category,
  isReversal: reversal,
);

void main() {
  group('which payments are followed', () {
    test('a single payment of N100,000 or more', () {
      final p = whereBigPaymentsWent([_in('1', 'YOUTUBE', 350000, _d(8, 24))]);
      expect(p.single.amount, 350000);
      expect(p.single.from, 'YOUTUBE');
    });

    test('anything smaller is not', () {
      expect(whereBigPaymentsWent([_in('1', 'A', 99999, _d(8, 24))]), isEmpty);
    });

    test('money moved in from your own account is not new money', () {
      expect(
        whereBigPaymentsWent([
          _in('1', 'ALEXANDER OSUYA', 300000, _d(8, 24)),
        ], ownerName: 'Alexander Osuya'),
        isEmpty,
      );
    });

    test('a bank reversal is not', () {
      expect(
        whereBigPaymentsWent([
          _in('1', 'ZENITH', 200000, _d(8, 24), reversal: true),
        ]),
        isEmpty,
      );
    });

    test('a payment the user hid is not', () {
      expect(
        whereBigPaymentsWent([_in('1', 'A', 200000, _d(8, 24))], hidden: {'1'}),
        isEmpty,
      );
    });

    test('newest first', () {
      final p = whereBigPaymentsWent([
        _in('old', 'A', 200000, _d(8, 17)),
        _in('new', 'B', 350000, _d(8, 24)),
      ]);
      expect(p.map((x) => x.credit.smsId), ['new', 'old']);
    });
  });

  group('what came out of one payment', () {
    test('spending afterwards is taken from it', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out('2', 100000, _d(8, 25), category: 'rent'),
        _out('3', 20000, _d(8, 26)),
      ]).single;
      expect(p.used, 120000);
      expect(p.left, 230000);
      expect(p.isGone, isFalse);
      expect(p.goneOn, isNull);
    });

    test('spending before it arrived is not', () {
      final p = whereBigPaymentsWent([
        _out('0', 50000, _d(8, 20)),
        _in('1', 'A', 350000, _d(8, 24)),
      ]).single;
      expect(p.used, 0);
    });

    test('it can never show more gone than it was', () {
      // The real case: N595,845 spent after a N350,000 payment.
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out('2', 300000, _d(8, 25)),
        _out('3', 295845, _d(8, 29)),
      ]).single;
      expect(p.used, 350000);
      expect(p.left, 0);
      expect(p.isGone, isTrue);
      expect(p.goneOn, _d(8, 29));
      expect(p.fromOtherMoney, 245845);
    });

    test('moving money to your own account is not spending', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out('2', 8000, _d(8, 29), to: 'ALEXANDER ADENIYI OSUYA'),
        _out('3', 150000, _d(8, 25), status: TxnStatus.excluded),
      ], ownerName: 'Alexander Osuya').single;
      expect(p.used, 0);
    });

    test('a reversed debit is not spending', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out('2', 50000, _d(8, 25), reversal: true),
      ]).single;
      expect(p.used, 0);
    });

    test('bank charges count, and are kept apart', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out(
          '2',
          53.75,
          _d(8, 25),
          kind: AlertKind.charge,
          status: TxnStatus.excluded,
        ),
      ]).single;
      expect(p.charges, 53.75);
      expect(p.used, 53.75);
    });

    test('sorted spending by budget, unsorted by who received it', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out('2', 20000, _d(8, 25), category: 'food'),
        _out('3', 150000, _d(8, 25), to: 'RICHARD OSUYA'),
        _out('4', 28000, _d(8, 26), to: 'PAYSTACK CHECKOUT'),
        _out('5', 21400, _d(8, 27), to: 'PAYSTACK CHECKOUT'),
      ]).single;
      expect(p.byCategory['food'], 20000);
      expect(p.unsortedByPayee['RICHARD OSUYA'], 150000);
      expect(p.unsortedByPayee['PAYSTACK CHECKOUT'], 49400);
    });
  });

  group('several payments overlapping', () {
    test('they are used up in the order they arrived', () {
      // The real August: N200,000 on the 17th, N350,000 on the 24th.
      final p = whereBigPaymentsWent([
        _in('a', 'JESUTOFUNMI ALO', 200000, _d(8, 17)),
        _in('b', 'CHARLES OSUYA', 350000, _d(8, 24)),
        _out('1', 150000, _d(8, 20)),
        _out('2', 100000, _d(8, 25)),
      ]);
      final first = p.firstWhere((x) => x.credit.smsId == 'a');
      final second = p.firstWhere((x) => x.credit.smsId == 'b');
      // The 20th only had the first payment to draw on.
      expect(first.used, 200000);
      expect(first.goneOn, _d(8, 25));
      // The rest of the 25th's spending came out of the second.
      expect(second.used, 50000);
    });

    test('one purchase can be split across two payments', () {
      final p = whereBigPaymentsWent([
        _in('a', 'A', 100000, _d(8, 17)),
        _in('b', 'B', 200000, _d(8, 18)),
        _out('1', 130000, _d(8, 19), category: 'rent'),
      ]);
      final a = p.firstWhere((x) => x.credit.smsId == 'a');
      final b = p.firstWhere((x) => x.credit.smsId == 'b');
      expect(a.byCategory['rent'], 100000);
      expect(b.byCategory['rent'], 30000);
    });

    test('other money is only counted once everything big is used up', () {
      final p = whereBigPaymentsWent([
        _in('a', 'A', 100000, _d(8, 17)),
        _in('b', 'B', 100000, _d(8, 18)),
        _out('1', 250000, _d(8, 19)),
      ]);
      expect(p.every((x) => x.isGone), isTrue);
      expect(p.firstWhere((x) => x.credit.smsId == 'b').fromOtherMoney, 50000);
      expect(p.firstWhere((x) => x.credit.smsId == 'a').fromOtherMoney, 0);
    });
  });

  group('how much was left each day', () {
    test('it only goes down, and never below zero', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24, 9)),
        _out('2', 100000, _d(8, 24, 18)),
        _out('3', 400000, _d(8, 27)),
      ]).single;
      final left = p.leftByDay(_d(8, 29));
      expect(left.first, 250000);
      expect(left[3], 0);
      expect(left.last, 0);
      for (var i = 1; i < left.length; i++) {
        expect(left[i], lessThanOrEqualTo(left[i - 1]));
      }
      expect(p.daysToGo, 4);
    });
  });
}
