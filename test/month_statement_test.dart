import 'package:banking_app/data/models.dart';
import 'package:banking_app/data/month_statement.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _d(int m, int d, [int h = 12, int min = 0]) =>
    DateTime(2026, m, d, h, min);

var _id = 1000;

TransactionRecord _t(
  AlertKind kind,
  double amount,
  DateTime when, {
  double? bal,
  String bank = 'ZENITH',
  String? account = '221****558',
  String? who = 'SOMEONE',
  String? category,
  TxnStatus? status,
  bool reversal = false,
  String? id,
}) => TransactionRecord(
  smsId: id ?? '${_id++}',
  bank: bank,
  kind: kind,
  channel: TxnChannel.transfer,
  status:
      status ??
      (kind == AlertKind.credit || kind == AlertKind.charge
          ? TxnStatus.excluded
          : category == null
          ? TxnStatus.pending
          : TxnStatus.labeled),
  amount: amount,
  balanceAfter: bal,
  occurredAt: when,
  account: account,
  counterpartyKey: kind == AlertKind.charge ? null : who,
  categoryId: category,
  isReversal: reversal,
);

TransactionRecord _in(
  double a,
  DateTime w, {
  double? bal,
  String? who,
  String bank = 'ZENITH',
  String? account = '221****558',
  bool reversal = false,
  String? id,
}) => _t(
  AlertKind.credit,
  a,
  w,
  bal: bal,
  who: who ?? 'CHARLES OSUYA',
  bank: bank,
  account: account,
  reversal: reversal,
  id: id,
);

TransactionRecord _out(
  double a,
  DateTime w, {
  double? bal,
  String? who,
  String? category,
  TxnStatus? status,
  String bank = 'ZENITH',
  String? account = '221****558',
  String? id,
}) => _t(
  AlertKind.debit,
  a,
  w,
  bal: bal,
  who: who ?? 'SOMEONE',
  category: category,
  status: status,
  bank: bank,
  account: account,
  id: id,
);

TransactionRecord _charge(
  double a,
  DateTime w, {
  double? bal,
  bool reversal = false,
  String? id,
}) => _t(AlertKind.charge, a, w, bal: bal, reversal: reversal, id: id);

final _now = _d(9, 14, 9);

void main() {
  group('how a text moves a balance', () {
    test('credits add, debits and charges take away', () {
      expect(effectOf(_in(500, _d(9, 1))), 500);
      expect(effectOf(_out(500, _d(9, 1))), -500);
      expect(effectOf(_charge(26.88, _d(9, 1))), -26.88);
    });

    test('a reversed charge gives the money back', () {
      expect(effectOf(_charge(53.75, _d(9, 1), reversal: true)), 53.75);
    });

    test('one account, however the bank masks its number', () {
      expect(
        accountKeyOf(_in(1, _d(9, 1), account: '221****558')),
        accountKeyOf(_in(1, _d(9, 1), account: '221**558')),
      );
      expect(
        accountKeyOf(_in(1, _d(9, 1), account: '221****558')),
        isNot(accountKeyOf(_in(1, _d(9, 1), bank: 'WEMA'))),
      );
    });
  });

  group('the closing balance', () {
    test('a transfer texted before the charge that came off first', () {
      // Real Zenith texts, 24 Aug: the transfer arrived first, but its
      // balance already had the charge taken.
      final at = _d(8, 24, 19, 5);
      final texts = [
        _in(350000, _d(8, 24, 18), bal: 351021.42, id: '5351'),
        _out(150000, at, bal: 200967.67, id: '5352'),
        _charge(53.75, at, bal: 350967.67, id: '5353'),
      ]..sort(compareTransactions);
      expect(closingBalance(texts), 200967.67);
    });

    test('a charge texted before its transfer', () {
      final at = _d(8, 21, 11, 30);
      final texts = [
        _in(14150, _d(8, 21, 11), bal: 36557.43, id: '5323'),
        _charge(26.88, at, bal: 36530.55, id: '5324'),
        _out(28300, at, bal: 8230.55, id: '5325'),
      ]..sort(compareTransactions);
      expect(closingBalance(texts), 8230.55);
    });

    test('none when no text shows a balance', () {
      expect(closingBalance([_in(500, _d(9, 1))]), isNull);
    });
  });

  group('a month that adds up', () {
    final history = [
      _in(1000, _d(8, 30), bal: 5000),
      _in(20000, _d(9, 2), bal: 25000, who: 'CHARLES OSUYA'),
      _out(7000, _d(9, 3), bal: 18000, who: 'ORIKI CITY HOTEL'),
      _charge(26.88, _d(9, 3, 13), bal: 17973.12),
      _out(3000, _d(9, 5), bal: 14973.12, category: 'food', who: 'CHOWDECK'),
    ];
    final s = statementFor(history, _d(9, 1), now: _now);

    test('starts from the last balance before the month', () {
      expect(s.openingTotal, 5000);
    });

    test('money in and out', () {
      expect(s.moneyIn, 20000);
      expect(s.moneyOut, closeTo(10026.88, 0.001));
      expect(s.charges, 26.88);
      expect(s.spentByCategory['food'], 3000);
      expect(s.unsortedByPayee['ORIKI CITY HOTEL'], 7000);
    });

    test('nothing unexplained, and it ends on the bank\'s balance', () {
      expect(s.leftWithoutText, 0);
      expect(s.arrivedWithoutText, 0);
      expect(s.closingTotal, closeTo(14973.12, 0.001));
      expect(
        s.openingTotal + s.checkedIn - s.checkedOut,
        closeTo(s.closingTotal, 0.001),
      );
    });

    test('the balance each day, carried over quiet days', () {
      expect(s.dailyBalance.length, 14);
      expect(s.dailyBalance[0], 5000); // 1 Sep, nothing yet
      expect(s.dailyBalance[1], 25000); // 2 Sep
      expect(s.dailyBalance[2], closeTo(17973.12, 0.001)); // 3 Sep
      expect(s.dailyBalance[3], closeTo(17973.12, 0.001)); // quiet
      expect(s.dailyBalance.last, closeTo(14973.12, 0.001));
      expect(s.dailyIn[1], 20000);
      expect(s.dailyOut[2], closeTo(7026.88, 0.001));
    });

    test('the month before is not in it', () {
      expect(s.received.map((l) => l.amount), [20000]);
    });
  });

  group('what the texts do not explain', () {
    test('money that left with no text is shown, not hidden', () {
      // The real 1 Sep: a ₦7,000 text, and the balance fell ₦29,522.
      final s = statementFor(
        [
          _out(3000, _d(8, 31), bal: 180613.74),
          _out(7000, _d(9, 1, 22), bal: 151091.72),
        ],
        _d(9, 1),
        now: _now,
      );
      expect(s.moneyOut, 7000);
      expect(s.leftWithoutText, closeTo(22522.02, 0.001));
      expect(
        s.openingTotal + s.checkedIn - s.checkedOut - s.leftWithoutText,
        closeTo(s.closingTotal, 0.001),
      );
      expect(s.accounts.single.unexplained, closeTo(-22522.02, 0.001));
    });

    test('the levy on an incoming transfer is small unexplained money', () {
      final s = statementFor(
        [
          _in(1000, _d(8, 31), bal: 22457.43),
          _in(14150, _d(9, 2), bal: 36557.43),
        ],
        _d(9, 1),
        now: _now,
      );
      expect(s.leftWithoutText, closeTo(50, 0.001));
    });

    test('a few kobo is rounding, not missing money', () {
      final s = statementFor(
        [_in(1000, _d(8, 31), bal: 1000), _out(500, _d(9, 2), bal: 499.6)],
        _d(9, 1),
        now: _now,
      );
      expect(s.leftWithoutText, 0);
    });
  });

  group('declined payments', () {
    // Wema, 4 and 5 Aug: a card payment texted with the balance untouched.
    final history = [
      _in(
        1190.32,
        _d(7, 31),
        bal: 1190.32,
        bank: 'WEMA',
        account: '0253****25',
      ),
      _out(
        1103.89,
        _d(8, 4, 4),
        bal: 86.43,
        bank: 'WEMA',
        account: '0253****25',
        who: 'SUBSCRIPTION BE',
      ),
      _out(
        13100,
        _d(8, 5, 3),
        bal: 86.43,
        bank: 'WEMA',
        account: '0253****25',
        who: 'CHOWDECK',
      ),
    ];

    test('are found', () {
      final sorted = [...history]..sort(compareTransactions);
      expect(declinedDebits(sorted), {history[2].smsId});
    });

    test('are not counted, and the month still adds up', () {
      final s = statementFor(history, _d(8, 1), now: _now);
      expect(s.moneyOut, closeTo(1103.89, 0.001));
      expect(s.declined.map((t) => t.smsId), [history[2].smsId]);
      expect(s.leftWithoutText, 0);
      expect(s.arrivedWithoutText, 0);
    });

    test('a payment that fits in the balance is never called declined', () {
      final sorted = [
        _in(5000, _d(8, 1), bal: 5000),
        _out(0.5, _d(8, 2), bal: 5000),
      ];
      expect(declinedDebits(sorted), isEmpty);
    });
  });

  group('your own money moving', () {
    final history = [
      _in(0, _d(8, 31), bal: 50000),
      _out(20000, _d(9, 2), bal: 30000, who: 'ALEXANDER ADENIYI OSUYA'),
      _in(
        20000,
        _d(9, 2, 12, 1),
        bal: 20000,
        bank: 'WEMA',
        account: '0253****25',
        who: 'ALEXANDER ADENIYI OSUYA',
      ),
      _out(
        5000,
        _d(9, 3),
        bal: 25000,
        status: TxnStatus.excluded,
        who: 'OPAY ME',
      ),
    ];
    final s = statementFor(
      history,
      _d(9, 1),
      now: _now,
      ownerName: 'Alexander Osuya',
    );

    test('is neither money in nor money out', () {
      expect(s.moneyIn, 0);
      expect(s.moneyOut, 0);
      expect(s.movedIn, 20000);
      expect(s.movedOut, 25000);
    });

    test('between two accounts it can see, it cancels out', () {
      // Wema's opening is worked back from its first text: 0.
      expect(s.openingTotal, 50000);
      expect(s.closingTotal, 45000);
      // ₦5,000 went to an account with no texts.
      expect(s.checkedMovedNet, -5000);
      expect(s.leftWithoutText, 0);
    });

    test('a known own account counts by its key', () {
      expect(
        isOwnTransfer(
          _out(1, _d(9, 1), who: 'MY SAVINGS'),
          ownKeys: {'MY SAVINGS'},
        ),
        isTrue,
      );
    });
  });

  group('refunds', () {
    test('money coming back is its own line, not a payment received', () {
      final s = statementFor(
        [
          _in(100, _d(8, 31), bal: 1000),
          _in(300000, _d(9, 2), bal: 301000, reversal: true, who: 'ZENITH'),
          _charge(53.75, _d(9, 2, 13), bal: 301053.75, reversal: true),
        ],
        _d(9, 1),
        now: _now,
      );
      expect(s.received, isEmpty);
      expect(s.refunds, closeTo(300053.75, 0.001));
      expect(s.leftWithoutText, 0);
    });
  });

  group('accounts', () {
    test('one whose texts show no balance is outside the sum', () {
      final s = statementFor(
        [
          _in(100, _d(8, 31), bal: 1000),
          _in(
            5000,
            _d(9, 2),
            bank: 'OPAY',
            account: null,
            who: 'CHARLES OSUYA',
          ),
        ],
        _d(9, 1),
        now: _now,
      );
      expect(s.moneyIn, 5000);
      expect(s.uncheckedAccounts.single.bank, 'OPAY');
      expect(s.checkedIn, 0);
      expect(s.closingTotal, 1000);
    });

    test('a quiet account still holding money is listed', () {
      final s = statementFor(
        [_in(11645.76, _d(8, 29), bal: 11645.76, bank: 'WEMA')],
        _d(9, 1),
        now: _now,
      );
      expect(s.accounts.single.closing, 11645.76);
      expect(s.closingTotal, 11645.76);
    });

    test('one the bank stopped texting about long ago is not', () {
      final s = statementFor(
        [
          _in(2117.70, DateTime(2025, 2, 2), bal: 2117.70, bank: 'WEMA'),
          _in(500, _d(9, 2), bal: 500),
        ],
        _d(9, 1),
        now: _now,
      );
      expect(s.accounts.map((a) => a.bank), ['ZENITH']);
    });

    test('with no text before the month, it works back from the first', () {
      final s = statementFor(
        [_out(7000, _d(9, 1, 22), bal: 151091.72)],
        _d(9, 1),
        now: _now,
      );
      expect(s.openingTotal, closeTo(158091.72, 0.001));
      expect(s.leftWithoutText, 0);
    });
  });

  group('which months', () {
    test('newest first, back to the oldest text, at most six', () {
      final months = statementMonths([
        _in(1, _d(7, 20)),
        _in(1, _d(9, 2)),
      ], now: _now);
      expect(months, [_d(9, 1, 0), _d(8, 1, 0), _d(7, 1, 0)]);
      expect(
        statementMonths([_in(1, DateTime(2025, 1, 1))], now: _now).length,
        6,
      );
    });

    test('a past month runs to its last day', () {
      final s = statementFor(
        [_in(100, _d(8, 31, 23), bal: 100)],
        _d(8, 1),
        now: _now,
      );
      expect(s.dailyBalance.length, 31);
      expect(s.until, DateTime(2026, 9, 1));
    });
  });
}
