import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/parsing/bank_alert.dart';
import 'package:banking_app/data/models.dart';
import 'package:banking_app/data/migration_plan.dart';

BankAlert _alert(String key, {AlertKind kind = AlertKind.debit, double amt = 100}) =>
    BankAlert(
      bank: 'WEMA',
      kind: kind,
      channel: TxnChannel.transfer,
      narration: key,
      amount: amt,
      counterpartyKey: key,
      occurredAt: DateTime(2026, 8, 1),
    );

void main() {
  group('legacy month keys', () {
    test('converts the old document id', () {
      expect(legacyMonthKey('August2026'), '2026-08');
      expect(legacyMonthKey('January2025'), '2025-01');
      expect(legacyMonthKey('December2024'), '2024-12');
    });
    test('rejects anything else rather than inventing a month', () {
      expect(legacyMonthKey('notamonth'), isNull);
      expect(legacyMonthKey('2026-08'), isNull);
    });
  });

  group('legacy carry-over', () {
    final items = [
      {'name': 'Food', 'image': 'food.svg', 'budgetSet': '20,000',
       'totalAmountSpent': 18500.0, 'dailySpend': 300.0},
      {'name': 'Others', 'budgetSet': 5000, 'totalAmountSpent': 1200.0},
    ];

    test('budgets stored as display strings are parsed', () {
      final l = ledgerFromLegacy('2026-08', items, closed: true);
      expect(l.budgets['cat_food'], 20000);
      expect(l.budgets['cat_others'], 5000);
    });

    test('totals are preserved verbatim, never recomputed', () {
      final l = ledgerFromLegacy('2026-08', items, closed: true);
      expect(l.spend['cat_food'], 18500.0);
      expect(l.spend['cat_others'], 1200.0);
      expect(l.closed, isTrue);
    });

    test('categories dedupe across months', () {
      final cats = categoriesFromLegacy([items, items]);
      expect(cats.length, 2);
      expect(cats.map((c) => c.id), containsAll(['cat_food', 'cat_others']));
    });
  });

  group('seeding', () {
    test('credits do not become spending counterparties', () {
      final map = seedCounterparties([
        _alert('CHOWDECK'),
        _alert('MUM SENDING MONEY', kind: AlertKind.credit),
      ]);
      expect(map.keys, ['CHOWDECK']);
    });

    test('everything starts at ask -- nothing is auto-categorised', () {
      final map = seedCounterparties([_alert('CHOWDECK')]);
      expect(map['CHOWDECK']!.disposition, Disposition.ask);
      expect(map['CHOWDECK']!.autoAssigns, isFalse);
    });

    test('the account holder is proposed as not-spending', () {
      final map = seedCounterparties([_alert('ALEXANDER ADENIYI O')],
          ownerName: 'ALEXANDER ADENIYI OSUYA');
      expect(map['ALEXANDER ADENIYI O']!.disposition, Disposition.notSpending);
    });
  });

  group('canonicalising truncated names', () {
    test('merges truncated spellings into the longest', () {
      final map = canonicaliseKeys(seedCounterparties([
        _alert('ALEXANDER ADENIYI OSUYA'),
        _alert('ALEXANDER ADENIYI O'),
        _alert('ALEXANDER ADENI'),
      ]));
      expect(map.length, 1);
      final e = map['ALEXANDER ADENIYI OSUYA']!;
      expect(e.txCount, 3);
      expect(e.aliases, hasLength(2));
    });

    test('keeps genuinely different names apart', () {
      final map = canonicaliseKeys(seedCounterparties([
        _alert('ABUBAKAR ALIYU'),
        _alert('ABUBAKAR ALH UMMARU'),
      ]));
      expect(map.length, 2);
    });

    test('a truncated spelling resolves through aliases', () {
      final map = canonicaliseKeys(seedCounterparties([
        _alert('ALEXANDER ADENIYI OSUYA'),
        _alert('ALEXANDER ADENI'),
      ]));
      expect(resolveKey(map, 'ALEXANDER ADENI')!.key, 'ALEXANDER ADENIYI OSUYA');
    });
  });

  group('institution keys', () {
    test('a truncated destination bank never identifies anyone', () {
      expect(isInstitutionOnlyKey('OPAY-'), isTrue);
      expect(isInstitutionOnlyKey('ZENITH BANK-'), isTrue);
      expect(isInstitutionOnlyKey('FBN-'), isTrue);
      expect(isInstitutionOnlyKey('PAYSTACK CHECKOUT'), isTrue);
    });

    test('a real name that merely starts similarly is not an institution', () {
      expect(isInstitutionOnlyKey('OPAYEMI ADEBAYO'), isFalse);
      expect(isInstitutionOnlyKey('MONIEPOINT-PERSONAL'), isFalse);
    });

    test('institution keys are kept off the batch screen', () {
      final map = canonicaliseKeys(seedCounterparties(
          [_alert('OPAY-'), _alert('OPAY-'), _alert('CHOWDECK')]));
      expect(batchTagCandidates(map).map((e) => e.key), ['CHOWDECK']);
    });
  });

  group('record building', () {
    test('a bank charge is excluded, never pending', () {
      final r = recordFor('1', _alert('FEE', kind: AlertKind.charge), {});
      expect(r.status, TxnStatus.excluded);
      expect(r.countsAsSpending, isFalse);
    });

    test('a self-transfer is stored but not counted', () {
      final map = seedCounterparties([_alert('ALEXANDER ADENIYI OSUYA')],
          ownerName: 'ALEXANDER ADENIYI OSUYA');
      final r = recordFor('1', _alert('ALEXANDER ADENIYI OSUYA'), map);
      expect(r.status, TxnStatus.excluded);
      expect(r.amount, 100);
    });

    test('a tracked counterparty labels outright', () {
      final map = {
        'CHOWDECK': const CounterpartyEntry(
            key: 'CHOWDECK',
            categoryId: 'cat_food',
            disposition: Disposition.tracked),
      };
      final r = recordFor('1', _alert('CHOWDECK'), map);
      expect(r.status, TxnStatus.labeled);
      expect(r.categoryId, 'cat_food');
      expect(r.countsAsSpending, isTrue);
    });

    test('repeated corrections stop the auto-assignment', () {
      final map = {
        'CHOWDECK': const CounterpartyEntry(
            key: 'CHOWDECK',
            categoryId: 'cat_food',
            disposition: Disposition.tracked,
            overrideCount: 3),
      };
      expect(recordFor('1', _alert('CHOWDECK'), map).status, TxnStatus.pending);
    });

    test('an unknown counterparty is pending, not guessed', () {
      expect(recordFor('1', _alert('NEW VENDOR'), {}).status, TxnStatus.pending);
    });

    test('a credit is stored for the balance chain but never pending', () {
      final r = recordFor('1', _alert('MUM', kind: AlertKind.credit), {});
      expect(r.status, TxnStatus.excluded);
    });
  });

  group('document ids', () {
    test('characters Firestore forbids are replaced', () {
      expect(counterpartyDocId('NIP CR/MOB/ABUBAKAR'), 'NIP CR_MOB_ABUBAKAR');
      expect(counterpartyDocId('A.B#C[D]'), 'A_B_C_D_');
    });
    test('ordinary keys are unchanged', () {
      expect(counterpartyDocId('CHOWDECK'), 'CHOWDECK');
    });
  });

  group('what gets persisted', () {
    test('one-off counterparties are not written', () {
      // A year of real data turned up ~184 counterparties, only ~69 seen more
      // than once. The singletons are created on demand instead.
      final map = canonicaliseKeys(seedCounterparties([
        _alert('CHOWDECK'), _alert('CHOWDECK'),
        _alert('SOMEONE ONCE'),
      ]));
      expect(worthPersisting(map).keys, ['CHOWDECK']);
    });

    test('a proposed self-transfer is kept even if seen once', () {
      final map = seedCounterparties([_alert('ALEXANDER ADENIYI OSUYA')],
          ownerName: 'ALEXANDER ADENIYI OSUYA');
      expect(worthPersisting(map).keys, ['ALEXANDER ADENIYI OSUYA']);
    });
  });
}
