import 'package:banking_app/data/models.dart';
import 'package:banking_app/data/money_owed.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord _out(String id, String who, double amount, DateTime when) =>
    TransactionRecord(
      smsId: id,
      bank: 'GTB',
      kind: AlertKind.debit,
      channel: TxnChannel.transfer,
      status: TxnStatus.pending,
      amount: amount,
      occurredAt: when,
      counterpartyKey: who,
    );

TransactionRecord _in(
  String id,
  String who,
  double amount,
  DateTime when, {
  bool reversal = false,
}) => TransactionRecord(
  smsId: id,
  bank: 'GTB',
  kind: AlertKind.credit,
  channel: TxnChannel.transfer,
  status: TxnStatus.excluded,
  amount: amount,
  occurredAt: when,
  counterpartyKey: who,
  isReversal: reversal,
);

DateTime _d(int month, int day) => DateTime(2026, month, day);

void main() {
  group('the same person, written two ways', () {
    test('exactly the same', () {
      expect(samePerson('PRECIOUS OKAFOR', 'PRECIOUS OKAFOR'), isTrue);
    });

    test('cut short on one side', () {
      expect(samePerson('PRECIOUS OKAFOR', 'PRECIOUS OKAF'), isTrue);
    });

    test('in a different order', () {
      expect(samePerson('OKAFOR PRECIOUS', 'PRECIOUS OKAFOR'), isTrue);
    });

    test('someone who only shares a surname is someone else', () {
      expect(samePerson('PRECIOUS OKAFOR', 'DANIEL OKAFOR'), isFalse);
    });

    test('someone who only shares a first name is someone else', () {
      expect(samePerson('PRECIOUS OKAFOR', 'PRECIOUS ADEYEMI'), isFalse);
    });
  });

  group('which transfers are worth asking about', () {
    test('a large transfer to a person is offered', () {
      final c = loanCandidates([
        _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
      ], decisions: const {});
      expect(c.map((x) => x.transfer.smsId), ['1']);
    });

    test('a small one is not', () {
      // Below the floor a payment to a person is lunch or a favour, and asking
      // about every one would bury the real loans.
      final c = loanCandidates([
        _out('1', 'PRECIOUS OKAFOR', 1500, _d(6, 3)),
      ], decisions: const {});
      expect(c, isEmpty);
    });

    test('a shop is not', () {
      final c = loanCandidates([
        _out('1', 'SHOPRITE LEKKI', 50000, _d(6, 3)),
      ], decisions: const {});
      expect(c, isEmpty);
    });

    test('the user moving their own money is not', () {
      final c = loanCandidates(
        [_out('1', 'ALEXANDER OSUYA', 50000, _d(6, 3))],
        decisions: const {},
        ownerName: 'Alexander Osuya',
      );
      expect(c, isEmpty);
    });

    test('anything already answered is never asked again', () {
      final c = loanCandidates(
        [
          _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
          _out('2', 'DANIEL JOSEPH', 20000, _d(6, 4)),
        ],
        decisions: const {'1': LoanDecision.notLoan, '2': LoanDecision.loan},
      );
      expect(c, isEmpty);
    });

    test('someone who has sent money back is offered first', () {
      final c = loanCandidates([
        _out('big', 'DANIEL JOSEPH', 90000, _d(6, 1)),
        _out('likely', 'PRECIOUS OKAFOR', 20000, _d(6, 2)),
        _in('back', 'PRECIOUS OKAF', 5000, _d(5, 1)),
      ], decisions: const {});
      expect(c.first.transfer.smsId, 'likely');
      expect(c.first.hasSentBack, isTrue);
    });
  });

  group('what is owed', () {
    test('only confirmed loans count', () {
      final owed = moneyOwed([
        _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
      ], decisions: const {});
      expect(owed, isEmpty);
    });

    test('a loan with nothing back is owed in full', () {
      final owed = moneyOwed(
        [_out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3))],
        decisions: const {'1': LoanDecision.loan},
      );
      expect(owed.single.outstanding, 50000);
      expect(owed.single.oldestOpen, _d(6, 3));
    });

    test('money back afterwards reduces it', () {
      final owed = moneyOwed(
        [
          _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
          _in('2', 'PRECIOUS OKAF', 20000, _d(7, 1)),
        ],
        decisions: const {'1': LoanDecision.loan},
      );
      expect(owed.single.repaid, 20000);
      expect(owed.single.outstanding, 30000);
    });

    test('money that arrived before the loan is not repayment', () {
      // It cannot be paying back something that had not happened yet.
      final owed = moneyOwed(
        [
          _in('0', 'PRECIOUS OKAFOR', 20000, _d(5, 1)),
          _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
        ],
        decisions: const {'1': LoanDecision.loan},
      );
      expect(owed.single.outstanding, 50000);
    });

    test('a bank reversal is not repayment', () {
      final owed = moneyOwed(
        [
          _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
          _in('2', 'PRECIOUS OKAFOR', 50000, _d(6, 4), reversal: true),
        ],
        decisions: const {'1': LoanDecision.loan},
      );
      expect(owed.single.outstanding, 50000);
    });

    test('paid back in full, nobody is listed', () {
      final owed = moneyOwed(
        [
          _out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3)),
          _in('2', 'PRECIOUS OKAFOR', 30000, _d(7, 1)),
          _in('3', 'PRECIOUS OKAFOR', 20000, _d(8, 1)),
        ],
        decisions: const {'1': LoanDecision.loan},
      );
      expect(owed, isEmpty);
    });

    test('several loans to one person, oldest settled first', () {
      final owed = moneyOwed(
        [
          _out('1', 'PRECIOUS OKAFOR', 10000, _d(6, 1)),
          _out('2', 'PRECIOUS OKAF', 40000, _d(6, 10)),
          _in('3', 'PRECIOUS OKAFOR', 15000, _d(7, 1)),
        ],
        decisions: const {'1': LoanDecision.loan, '2': LoanDecision.loan},
      );
      final p = owed.single;
      expect(p.loans.first.isOpen, isFalse);
      expect(p.loans.last.repaid, 5000);
      expect(p.outstanding, 35000);
      // Oldest still open is the second loan, since the first is cleared.
      expect(p.oldestOpen, _d(6, 10));
    });

    test('a loan marked settled is not owed', () {
      final owed = moneyOwed(
        [_out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3))],
        decisions: const {'1': LoanDecision.settled},
      );
      expect(owed, isEmpty);
    });

    test('two different people are kept apart, largest first', () {
      final owed = moneyOwed(
        [
          _out('1', 'PRECIOUS OKAFOR', 20000, _d(6, 1)),
          _out('2', 'DANIEL JOSEPH', 35000, _d(6, 2)),
        ],
        decisions: const {'1': LoanDecision.loan, '2': LoanDecision.loan},
      );
      expect(owed.map((p) => p.name), ['DANIEL JOSEPH', 'PRECIOUS OKAFOR']);
    });
  });

  test('the reminder uses their first name and the amount', () {
    final p = moneyOwed(
      [_out('1', 'PRECIOUS OKAFOR', 50000, _d(6, 3))],
      decisions: const {'1': LoanDecision.loan},
    ).single;
    final text = reminderText(p, currency: '₦');
    expect(text, contains('Precious'));
    expect(text, contains('₦50,000'));
  });
}
