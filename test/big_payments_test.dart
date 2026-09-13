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
      // Only what was left of it came out of the second spending.
      expect(p.uses.last.taken, 50000);
      expect(p.uses.last.isPart, isTrue);
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

    test('bank charges count', () {
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
      expect(p.uses.single.spend.kind, AlertKind.charge);
      expect(p.used, 53.75);
    });

    test('every spending is listed in order, with what was left after it', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24)),
        _out('3', 150000, _d(8, 25, 9), to: 'RICHARD OSUYA'),
        _out('2', 20000, _d(8, 25, 8), category: 'food'),
        _out('4', 28000, _d(8, 26), to: 'PAYSTACK CHECKOUT'),
      ]).single;
      expect(p.uses.map((u) => u.spend.smsId), ['2', '3', '4']);
      expect(p.uses.map((u) => u.leftAfter), [330000, 180000, 152000]);
      expect(p.uses.every((u) => !u.isPart), isTrue);
    });

    test('a declined card payment is not spending', () {
      // Wema texts a declined payment with the balance untouched.
      TransactionRecord withBalance(TransactionRecord t, double bal) =>
          TransactionRecord(
            smsId: t.smsId,
            bank: 'WEMA',
            kind: t.kind,
            channel: t.channel,
            status: t.status,
            amount: t.amount,
            balanceAfter: bal,
            occurredAt: t.occurredAt,
            account: '0253****25',
            counterpartyKey: t.counterpartyKey,
          );
      final p = whereBigPaymentsWent([
        withBalance(_in('1', 'A', 150000, _d(8, 4)), 150086.43),
        withBalance(_out('2', 150000, _d(8, 4, 13)), 86.43),
        withBalance(_out('4', 13100, _d(8, 5)), 86.43),
      ]).single;
      expect(p.used, 150000);
      expect(p.uses.map((u) => u.spend.smsId), ['2']);
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
      expect(a.uses.single.taken, 100000);
      expect(b.uses.single.taken, 30000);
      expect(b.uses.single.isPart, isTrue);
    });

    test('nothing more is taken once every payment is used up', () {
      final p = whereBigPaymentsWent([
        _in('a', 'A', 100000, _d(8, 17)),
        _in('b', 'B', 100000, _d(8, 18)),
        _out('1', 250000, _d(8, 19)),
        _out('2', 5000, _d(8, 20)),
      ]);
      expect(p.every((x) => x.isGone), isTrue);
      expect(p.every((x) => x.uses.length == 1), isTrue);
    });
  });

  group('what was left', () {
    test('it only goes down, and never below zero', () {
      final p = whereBigPaymentsWent([
        _in('1', 'A', 350000, _d(8, 24, 9)),
        _out('2', 100000, _d(8, 24, 18)),
        _out('3', 400000, _d(8, 27)),
      ]).single;
      final left = p.uses.map((u) => u.leftAfter).toList();
      expect(left, [250000, 0]);
      expect(p.daysToGo, 4);
    });
  });
}
