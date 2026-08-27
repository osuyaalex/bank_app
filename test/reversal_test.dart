import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/data/models.dart';
import 'package:banking_app/data/reversal.dart';
import 'package:banking_app/parsing/bank_alert.dart';

ReversalCandidate cand(
  String id, {
  String kind = 'debit',
  String status = 'labeled',
  String? key,
  DateTime? at,
  bool reversed = false,
}) =>
    ReversalCandidate(
      id: id,
      kind: kind,
      status: status,
      counterpartyKey: key,
      occurredAt: at,
      alreadyReversed: reversed,
    );

void main() {
  group('detecting a reversal', () {
    test('a negative debit amount is money coming back', () {
      const body = 'Acct:221****558\n'
          'DT:26/08/2026 07:46:40 PM\n'
          '***RSVL NIP CR/MOB/PAYSTACK CHECKOUT/T\n'
          'DR Amt:-300,000.00\n'
          'Bal:278,581.02';
      expect(isReversalAlert(body), isTrue);
      expect(classifyAlert(body), AlertKind.credit);
      expect(parseAlert('ZENITHBANK', body)!.isReversal, isTrue);
    });

    test('the word alone is enough when the amount is positive', () {
      const body = 'Acct:221****558\n'
          'REVERSAL OF NIP TRANSFER\n'
          'CR Amt:15,000.00\n'
          'Bal:100.00';
      expect(isReversalAlert(body), isTrue);
    });

    test('an ordinary debit is not a reversal', () {
      const body = 'Acct:221****558\n'
          'NIP CR/MOB/CHARLES  OSUYA/ABN\n'
          'DR Amt:3,000.00\n'
          'Bal:279,261.77';
      expect(isReversalAlert(body), isFalse);
      expect(parseAlert('ZENITHBANK', body)!.isReversal, isFalse);
    });

    test('a reversed bank charge is still a charge', () {
      const body = 'Acct:221****558\n'
          '***RSVL NIP CHARGE + VAT\n'
          'DR Amt:-10.75\n'
          'Bal:279,251.02';
      expect(isReversalAlert(body), isTrue);
      expect(classifyAlert(body), AlertKind.charge);
      expect(parseAlert('ZENITHBANK', body)!.isReversal, isTrue);
    });
  });

  group('picking what a reversal undoes', () {
    final when = DateTime(2026, 8, 26, 19, 46);

    test('takes the nearest debit before it', () {
      final got = pickReversed([
        cand('old', at: DateTime(2026, 8, 1)),
        cand('near', at: DateTime(2026, 8, 25)),
      ], when: when);
      expect(got!.id, 'near');
    });

    test('never undoes a transaction that came after it', () {
      final got = pickReversed([
        cand('later', at: DateTime(2026, 8, 27)),
      ], when: when);
      expect(got, isNull);
    });

    test('never undoes a credit', () {
      final got = pickReversed([
        cand('in', kind: 'credit', status: 'excluded', at: DateTime(2026, 8, 20)),
      ], when: when);
      expect(got, isNull);
    });

    test('will not take the same money off twice', () {
      final got = pickReversed([
        cand('done', at: DateTime(2026, 8, 20), reversed: true),
      ], when: when);
      expect(got, isNull);
    });

    test('counterparties must agree when both carry one', () {
      final got = pickReversed([
        cand('other', key: 'CHARLES OSUYA', at: DateTime(2026, 8, 20)),
        cand('same', key: 'PAYSTACK CHECKOUT', at: DateTime(2026, 8, 19)),
      ], when: when, counterpartyKey: 'PAYSTACK CHECKOUT');
      expect(got!.id, 'same');
    });

    test('an unnamed reversal still matches on amount and time', () {
      final got = pickReversed([
        cand('named', key: 'CHARLES OSUYA', at: DateTime(2026, 8, 20)),
      ], when: when);
      expect(got!.id, 'named');
    });

    test('a reversed charge is eligible even though charges sit excluded', () {
      final got = pickReversed([
        cand('fee', kind: 'charge', status: 'excluded', at: DateTime(2026, 8, 26)),
      ], when: when);
      expect(got!.id, 'fee');
    });
  });

  group('what a reversal takes back', () {
    test('a labelled spend comes off its category', () {
      final e = reversalEffect(
          kind: 'debit',
          status: TxnStatus.labeled.name,
          categoryId: 'cat_family',
          amount: 300000);
      expect(e.categoryId, 'cat_family');
      expect(e.amount, 300000);
      expect(e.isCharge, isFalse);
    });

    test('a bank charge comes off the charges line', () {
      final e = reversalEffect(
          kind: 'charge',
          status: TxnStatus.excluded.name,
          categoryId: null,
          amount: 10.75);
      expect(e.isCharge, isTrue);
      expect(e.amount, 10.75);
    });

    test('an unsorted debit was never in a total, so nothing moves', () {
      final e = reversalEffect(
          kind: 'debit',
          status: TxnStatus.pending.name,
          categoryId: null,
          amount: 5000);
      expect(e.categoryId, isNull);
      expect(e.isCharge, isFalse);
      expect(e.amount, 0);
    });
  });
}
