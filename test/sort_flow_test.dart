import 'package:banking_app/data/models.dart';
import 'package:banking_app/main_page/sort_flow.dart';
import 'package:flutter_test/flutter_test.dart';

CounterpartyEntry _cp(String key, {int count = 1, double spent = 0}) =>
    CounterpartyEntry(key: key, txCount: count, totalDebited: spent);

void main() {
  group('what to ask next', () {
    final rows = [_cp('EBEANO', spent: 48000), _cp('ALIYU', spent: 20000)];

    test('it opens on the first question', () {
      // Nothing precedes it. The flow briefly began with a card offering
      // budgets worked out from history, which was a duplicate -- the setup
      // screen asks for exactly those, with the same picker and figures from
      // the same months, one screen earlier.
      final step = nextStep(rows: rows, answered: const {});
      expect((step as AskStep).entry.key, 'EBEANO');
    });

    test('answered rows are skipped', () {
      final step = nextStep(rows: rows, answered: const {'EBEANO'});
      expect((step as AskStep).entry.key, 'ALIYU');
    });

    test('a row passed over is not put back straight away', () {
      final step = nextStep(
        rows: rows,
        answered: const {},
        skipped: const {'EBEANO'},
      );
      expect((step as AskStep).entry.key, 'ALIYU');
    });

    test('the review list is the end, not a question', () {
      final step = nextStep(rows: rows, answered: const {'EBEANO', 'ALIYU'});
      expect(step, isA<ReviewStep>());
    });

    test('a skipped row still ends at the review list', () {
      // It stays unanswered and turns up there, which is the whole difference
      // between skipping something and answering it.
      final step = nextStep(
        rows: rows,
        answered: const {'ALIYU'},
        skipped: const {'EBEANO'},
      );
      expect(step, isA<ReviewStep>());
    });

    test('a cascade jumps the queue', () {
      // It is the consequence of the answer just given. Held back until after
      // the next question, it would explain the wrong thing.
      final cascade = CascadeStep(
        trigger: 'ALIYU',
        categoryName: 'Family',
        covered: [_cp('FATIMA')],
      );
      final step = nextStep(rows: rows, answered: const {}, cascade: cascade);
      expect(step, same(cascade));
    });
  });

  group('what one answer settled', () {
    final rows = [_cp('ALIYU'), _cp('FATIMA'), _cp('MUSA'), _cp('EBEANO')];

    test('the rows that changed hands without being asked about', () {
      final covered = cascadedBy(
        trigger: 'ALIYU',
        before: const {},
        after: const {'ALIYU', 'FATIMA', 'MUSA'},
        rows: rows,
      );
      expect(covered.map((e) => e.key), ['FATIMA', 'MUSA']);
    });

    test('the row the user answered is not reported back to them', () {
      final covered = cascadedBy(
        trigger: 'ALIYU',
        before: const {},
        after: const {'ALIYU'},
        rows: rows,
      );
      expect(covered, isEmpty);
    });

    test('work already done is never re-announced', () {
      // The matcher re-runs after every category is created. Without this,
      // each run would claim credit for everything it had ever filed.
      final covered = cascadedBy(
        trigger: 'MUSA',
        before: const {'FATIMA'},
        after: const {'FATIMA', 'MUSA', 'EBEANO'},
        rows: rows,
      );
      expect(covered.map((e) => e.key), ['EBEANO']);
    });
  });

  group('progress', () {
    test('counts rows and money separately, because they differ', () {
      final rows = [
        _cp('RENT', spent: 400000),
        _cp('AIRTIME', spent: 1000),
        _cp('SNACKS', spent: 1500),
        _cp('BUS', spent: 2500),
      ];
      final p = SortProgress.of(rows, {'RENT'});
      expect(p.answered, 1);
      expect(p.remaining, 3);
      // One answer of four rows, and almost the whole month.
      expect(p.shareOfMoney, closeTo(0.987, 0.001));
    });

    test('unknown amounts do not become a false percentage', () {
      // Counterparties recorded before spending was tracked per name carry a
      // total of zero. Reporting "0% of your money sorted" would be a claim
      // the app cannot support.
      final rows = [_cp('A'), _cp('B')];
      expect(SortProgress.of(rows, {'A'}).shareOfMoney, 0);
    });

    test('an early exit is offered once most of the money is settled', () {
      final rows = [
        _cp('RENT', spent: 400000),
        _cp('FOOD', spent: 60000),
        _cp('FUEL', spent: 40000),
        for (var i = 0; i < 6; i++) _cp('SMALL$i', spent: 500),
      ];
      final p = SortProgress.of(rows, {'RENT', 'FOOD', 'FUEL'});
      expect(p.worthOfferingAnExit, isTrue);
    });

    test('it is not offered three taps from the end', () {
      // Talking someone out of finishing work they have nearly finished is
      // not a kindness.
      final rows = [
        _cp('RENT', spent: 400000),
        _cp('FOOD', spent: 60000),
        _cp('FUEL', spent: 40000),
        _cp('SMALL', spent: 500),
      ];
      final p = SortProgress.of(rows, {'RENT', 'FOOD', 'FUEL'});
      expect(p.worthOfferingAnExit, isFalse);
    });

    test('it is not offered before enough has actually been answered', () {
      final rows = [
        _cp('RENT', spent: 400000),
        for (var i = 0; i < 6; i++) _cp('SMALL$i', spent: 500),
      ];
      final p = SortProgress.of(rows, {'RENT'});
      expect(p.shareOfMoney, greaterThan(0.9));
      expect(p.worthOfferingAnExit, isFalse);
    });
  });
}
