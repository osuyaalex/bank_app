import 'package:banking_app/data/inbox_history.dart';
import 'package:banking_app/data/migration.dart' show InboxMessage;
import 'package:banking_app/data/models.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

const _zenithDebit = '''
Acct:221****558
DT:23/08/2026 09:06:35 PM
NIP CR/MOB/ABUBAKAR  ALIYU/PAL
DR Amt:300.00
Bal:142.92''';

const _zenithCredit = '''
Acct:221****558
DT:25/08/2026 09:00:00 AM
NIP CR/MOB/BRIGHTPATH LTD/GTB
CR Amt:350,000.00
Bal:350,142.92''';

InboxMessage _m(String id, String body, {DateTime? at}) =>
    InboxMessage(id: id, sender: 'ZENITHBANK', body: body, receivedAt: at);

void main() {
  group('reading history from the inbox', () {
    test(
      'bank alerts become transactions, with amount, date and direction',
      () {
        final h = historyFromInbox([
          _m('1', _zenithDebit),
          _m('2', _zenithCredit),
        ], const {});
        expect(h, hasLength(2));
        expect(h.first.kind, AlertKind.debit);
        expect(h.first.amount, 300);
        expect(h.last.kind, AlertKind.credit);
        expect(h.last.amount, 350000);
      },
    );

    test('oldest first, whatever order the inbox gave them in', () {
      final h = historyFromInbox([
        _m('2', _zenithCredit),
        _m('1', _zenithDebit),
      ], const {});
      expect(h.map((t) => t.smsId), ['1', '2']);
    });

    test('messages that are not bank alerts are left out', () {
      final h = historyFromInbox([
        _m('otp', 'Your OTP is 482913. Do not share it.'),
        _m('1', _zenithDebit),
      ], const {});
      expect(h.map((t) => t.smsId), ['1']);
    });

    test('anything older than the cut-off is left out', () {
      final h = historyFromInbox(
        [_m('1', _zenithDebit), _m('2', _zenithCredit)],
        const {},
        since: DateTime(2026, 8, 24),
      );
      expect(h.map((t) => t.smsId), ['2']);
    });

    test('a counterparty already filed carries its category', () {
      // Same rules as when the app saves a transaction, so the history agrees
      // with the budgets on the home screen.
      final key = historyFromInbox([
        _m('1', _zenithDebit),
      ], const {}).single.counterpartyKey!;
      final h = historyFromInbox(
        [_m('1', _zenithDebit)],
        {
          key: CounterpartyEntry(
            key: key,
            disposition: Disposition.tracked,
            categoryId: 'family',
          ),
        },
      );
      expect(h.single.status, TxnStatus.labeled);
      expect(h.single.categoryId, 'family');
    });

    test('a transfer to the user\'s own account is not spending', () {
      final key = historyFromInbox([
        _m('1', _zenithDebit),
      ], const {}).single.counterpartyKey!;
      final h = historyFromInbox(
        [_m('1', _zenithDebit)],
        {
          key: CounterpartyEntry(
            key: key,
            disposition: Disposition.notSpending,
          ),
        },
      );
      expect(h.single.status, TxnStatus.excluded);
    });
  });

  group('laying the user\'s own decisions over it', () {
    test('a transaction the user re-sorted takes the saved category', () {
      final h = historyFromInbox([_m('1', _zenithDebit)], const {});
      final merged = withSavedDecisions(h, {
        '1': (status: TxnStatus.labeled, categoryId: 'food'),
      });
      expect(merged.single.categoryId, 'food');
      expect(merged.single.status, TxnStatus.labeled);
      // Everything the bank sent is kept as it was.
      expect(merged.single.amount, 300);
    });

    test('transactions the database never saw are left alone', () {
      final h = historyFromInbox([
        _m('1', _zenithDebit),
        _m('2', _zenithCredit),
      ], const {});
      final merged = withSavedDecisions(h, {
        '1': (status: TxnStatus.excluded, categoryId: null),
      });
      expect(merged.last.kind, AlertKind.credit);
      expect(merged.last.status, h.last.status);
    });
  });
}
