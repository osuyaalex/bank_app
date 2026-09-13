import 'package:banking_app/data/models.dart';
import 'package:banking_app/data/salary.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord _in(
  String id,
  String from,
  double amount,
  DateTime when, {
  String narration = '',
}) => TransactionRecord(
  smsId: id,
  bank: 'GTB',
  kind: AlertKind.credit,
  channel: TxnChannel.transfer,
  status: TxnStatus.excluded,
  amount: amount,
  occurredAt: when,
  counterpartyKey: from,
  narration: narration,
);

TransactionRecord _out(
  String id,
  double amount,
  DateTime when, {
  String? category,
  TxnStatus status = TxnStatus.labeled,
  AlertKind kind = AlertKind.debit,
}) => TransactionRecord(
  smsId: id,
  bank: 'GTB',
  kind: kind,
  channel: TxnChannel.transfer,
  status: status,
  amount: amount,
  occurredAt: when,
  categoryId: category,
  counterpartyKey: 'SOMEONE',
);

DateTime _d(int m, int d, [int h = 9]) => DateTime(2026, m, d, h);

void main() {
  group('recognising a salary', () {
    test('the same company, a month apart, the same amount', () {
      final s = detectSalary([
        _in('1', 'BRIGHTPATH LTD', 350000, _d(6, 25)),
        _in('2', 'BRIGHTPATH LTD', 350000, _d(7, 25)),
        _in('3', 'BRIGHTPATH LTD', 350000, _d(8, 25)),
      ], now: _d(9, 5));
      expect(s, isNotNull);
      expect(s!.payer, 'BRIGHTPATH LTD');
      expect(s.typical, 350000);
      expect(s.latest.smsId, '3');
    });

    test('without the word salary anywhere', () {
      // Most Nigerian salaries arrive as a plain transfer from the employer.
      final s = detectSalary([
        _in('1', 'BRIGHTPATH LTD', 350000, _d(7, 25)),
        _in('2', 'BRIGHTPATH LTD', 350000, _d(8, 25)),
      ], now: _d(9, 5));
      expect(s, isNotNull);
      expect(s!.namedSalary, isFalse);
    });

    test('paid by a person, which small businesses often do', () {
      final s = detectSalary([
        _in('1', 'SOLARINSODARA OLUWATOBI', 200000, _d(7, 28)),
        _in('2', 'SOLARINSODARA OLUWATOBI', 200000, _d(8, 28)),
      ], now: _d(9, 5));
      expect(s?.payer, 'SOLARINSODARA OLUWATOBI');
    });

    test('a payday moved by a weekend still counts', () {
      final s = detectSalary([
        _in('1', 'BRIGHTPATH LTD', 350000, _d(6, 25)),
        _in('2', 'BRIGHTPATH LTD', 350000, _d(7, 23)),
        _in('3', 'BRIGHTPATH LTD', 350000, _d(8, 27)),
      ], now: _d(9, 5));
      expect(s?.paydays.length, 3);
    });

    test('a month with overtime or deductions still counts', () {
      final s = detectSalary([
        _in('1', 'BRIGHTPATH LTD', 350000, _d(6, 25)),
        _in('2', 'BRIGHTPATH LTD', 395000, _d(7, 25)),
        _in('3', 'BRIGHTPATH LTD', 320000, _d(8, 25)),
      ], now: _d(9, 5));
      expect(s?.paydays.length, 3);
    });

    test('the name cut short on one alert is the same payer', () {
      final s = detectSalary([
        _in('1', 'BRIGHTPATH TECHNOLOGIES LTD', 350000, _d(7, 25)),
        _in('2', 'BRIGHTPATH TECHNOL', 350000, _d(8, 25)),
      ], now: _d(9, 5));
      expect(s?.payer, 'BRIGHTPATH TECHNOLOGIES LTD');
    });

    test('the word salary tips it over a monthly allowance', () {
      final s = detectSalary([
        _in('a', 'MUMMY ADEYEMI', 400000, _d(7, 1)),
        _in('b', 'MUMMY ADEYEMI', 400000, _d(8, 1)),
        _in(
          's1',
          'BRIGHTPATH LTD',
          300000,
          _d(7, 25),
          narration: 'JULY SALARY',
        ),
        _in('s2', 'BRIGHTPATH LTD', 300000, _d(8, 25), narration: 'AUG SALARY'),
      ], now: _d(9, 5));
      expect(s?.payer, 'BRIGHTPATH LTD');
    });
  });

  group('what is not a salary', () {
    test('one payment is not a pattern', () {
      expect(
        detectSalary([
          _in('1', 'BRIGHTPATH LTD', 350000, _d(8, 25)),
        ], now: _d(9, 5)),
        isNull,
      );
    });

    test('small monthly transfers are not wages', () {
      expect(
        detectSalary([
          _in('1', 'DANIEL JOSEPH', 10000, _d(7, 25)),
          _in('2', 'DANIEL JOSEPH', 10000, _d(8, 25)),
        ], now: _d(9, 5)),
        isNull,
      );
    });

    test('irregular payments are not a salary', () {
      expect(
        detectSalary([
          _in('1', 'CLIENT A', 200000, _d(6, 2)),
          _in('2', 'CLIENT A', 90000, _d(6, 20)),
          _in('3', 'CLIENT A', 400000, _d(8, 29)),
        ], now: _d(9, 5)),
        isNull,
      );
    });

    test('a salary that stopped months ago is not the current one', () {
      expect(
        detectSalary([
          _in('1', 'OLD EMPLOYER LTD', 300000, _d(2, 25)),
          _in('2', 'OLD EMPLOYER LTD', 300000, _d(3, 25)),
        ], now: _d(9, 5)),
        isNull,
      );
    });

    test('the user moving money from another account of their own', () {
      expect(
        detectSalary(
          [
            _in('1', 'ALEXANDER OSUYA', 300000, _d(7, 25)),
            _in('2', 'ALEXANDER OSUYA', 300000, _d(8, 25)),
          ],
          ownerName: 'Alexander Osuya',
          now: _d(9, 5),
        ),
        isNull,
      );
    });
  });

  group('where it went in one pay cycle', () {
    final start = _d(8, 25);

    test('sorted, unsorted and charges all count as gone', () {
      final c = payCycle(
        [
          _out('1', 100000, _d(8, 25, 12), category: 'rent'),
          _out('2', 20000, _d(8, 26), status: TxnStatus.pending),
          _out(
            '3',
            53.75,
            _d(8, 26),
            kind: AlertKind.charge,
            status: TxnStatus.excluded,
          ),
        ],
        start: start,
        end: _d(9, 5),
        salary: 350000,
      );
      expect(c.byCategory['rent'], 100000);
      expect(c.unsorted, 20000);
      expect(c.charges, 53.75);
      expect(c.spent, closeTo(120053.75, 0.01));
    });

    test('moving money to your own account is not spending', () {
      final c = payCycle(
        [_out('1', 160000, _d(8, 26), status: TxnStatus.excluded)],
        start: start,
        end: _d(9, 5),
        salary: 350000,
      );
      expect(c.spent, 0);
    });

    test('spending before payday or after the cycle is left out', () {
      final c = payCycle(
        [
          _out('before', 5000, _d(8, 24), category: 'food'),
          _out('after', 5000, _d(9, 6), category: 'food'),
          _out('in', 5000, _d(8, 30), category: 'food'),
        ],
        start: start,
        end: _d(9, 5),
        salary: 350000,
      );
      expect(c.spent, 5000);
    });

    test('the morning after payday is day two', () {
      final c = payCycle(
        [_out('1', 1000, _d(8, 26, 8), category: 'food')],
        start: _d(8, 25, 9),
        end: _d(9, 5),
        salary: 350000,
      );
      expect(c.dailyTotals[0], 0);
      expect(c.dailyTotals[1], 1000);
    });

    test('when half of it was gone', () {
      final c = payCycle(
        [
          _out('1', 100000, _d(8, 25, 12), category: 'rent'),
          _out('2', 80000, _d(8, 29), category: 'food'),
          _out('3', 50000, _d(9, 3), category: 'food'),
        ],
        start: start,
        end: _d(9, 5),
        salary: 350000,
      );
      // 100k on day 1, 180k by day 5 -- past 175k, half of 350k.
      expect(c.dayWhenGone(0.5), 5);
      expect(c.dayWhenGone(0.9), isNull);
      expect(c.shareGone, closeTo(230000 / 350000, 0.001));
    });
  });

  test('the next payday is expected on the usual gap', () {
    final s = detectSalary([
      _in('1', 'BRIGHTPATH LTD', 350000, _d(6, 25)),
      _in('2', 'BRIGHTPATH LTD', 350000, _d(7, 25)),
      _in('3', 'BRIGHTPATH LTD', 350000, _d(8, 25)),
    ], now: _d(9, 5))!;
    final next = s.nextExpected;
    expect(next.month, 9);
    expect(next.day, inInclusiveRange(23, 26));
  });
}
