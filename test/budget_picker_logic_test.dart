import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/data/budget_suggestion.dart';

void main() {
  group('nudging', () {
    test('a tap moves the figure by something a person would notice', () {
      expect(budgetStep(500), 100);
      expect(budgetStep(4000), 500);
      expect(budgetStep(46000), 1000);
      expect(budgetStep(60000), 5000);
      expect(budgetStep(120000), 10000);
      expect(budgetStep(750000), 50000);
    });

    test('crossing a decade never takes an unreasonable number of taps', () {
      // Anywhere on the ladder, one step is between 1% and 10% of the figure,
      // so nudging is always worth doing and never the fastest way to get
      // somewhere far away -- that is what the ladder is for.
      for (final v in [1500.0, 8000.0, 46000.0, 90000.0, 400000.0, 1500000.0]) {
        final ratio = budgetStep(v) / v;
        expect(ratio, greaterThan(0.005), reason: 'step too small at $v');
        expect(ratio, lessThan(0.12), reason: 'step too big at $v');
      }
    });

    test('the ladder reaches the budgets people actually have', () {
      expect(budgetLadder.last, 2000000);
      expect(budgetLadder, containsAll(<double>[200000, 500000, 1000000]));
    });

    test('big money still fits on a chip', () {
      expect(compactMoney(500, '#'), '#500');
      expect(compactMoney(20000, '#'), '#20k');
      expect(compactMoney(500000, '#'), '#500k');
      expect(compactMoney(1000000, '#'), '#1M');
      expect(compactMoney(1500000, '#'), '#1.5M');
      expect(compactMoney(46000, '#'), '#46k');
    });
  });

  group('three budgets from your own months', () {
    test('lean, normal and comfortable, all rounded', () {
      final c = budgetChoices([47000, 44000, 8000, 15000, 288100, 177000])!;
      expect(c.tight, lessThan(c.usual));
      expect(c.usual, lessThan(c.roomy));
      expect(c.usual, 46000); // the same figure the suggestion proposes
    });

    test('steady spending still leaves a choice to make', () {
      final c = budgetChoices([20000, 20000, 20000, 20000])!;
      expect(c.usual, 20000);
      expect(c.tight, 19000);
      expect(c.roomy, 21000);
    });

    test('one month is not enough to claim a range', () {
      expect(budgetChoices([20000]), isNull);
      expect(budgetChoices([]), isNull);
      expect(budgetChoices([0, 0, 20000]), isNull);
    });

    test('tight never goes to nothing', () {
      final c = budgetChoices([200, 300, 250])!;
      expect(c.tight, greaterThan(0));
    });
  });

  group('percentiles', () {
    test('reads the middle and the edges', () {
      expect(percentile([10, 20, 30, 40], 0.5), 25);
      expect(percentile([10, 20, 30, 40], 0), 10);
      expect(percentile([10, 20, 30, 40], 1), 40);
    });
    test('a single month is its own answer', () {
      expect(percentile([7], 0.25), 7);
    });
  });

  group('history lookup', () {
    final all = [
      const BudgetSuggestion(
        categoryId: 'cat_family',
        categoryName: 'Family',
        amount: 46000,
        typical: 45500,
        months: [MonthlySpend('2026-07', 47000), MonthlySpend('2026-06', 44000)],
      ),
    ];

    test('finds a category regardless of casing', () {
      expect(historyFor(all, 'family'), [47000, 44000]);
      expect(historyFor(all, '  Family '), [47000, 44000]);
    });
    test('an unknown category has no history, not a wrong one', () {
      expect(historyFor(all, 'Groceries'), isEmpty);
    });
  });

  group('untracked categories', () {
    test('are marked, and sorted after the ones you have', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-06': {'cat_family': 40000.0, 'cat_public_transport': 90000.0},
          '2026-07': {'cat_family': 40000.0, 'cat_public_transport': 90000.0},
        },
        categoryNames: {
          'cat_family': 'Family',
          'cat_public_transport': 'Public Transport',
        },
        currentMonth: '2026-08',
        trackedNames: {'Family'},
      );
      expect(got.map((s) => s.categoryName), ['Family', 'Public Transport']);
      expect(got.first.isTracked, isTrue);
      expect(got.last.isTracked, isFalse);
    });

    test('with no tracked list given, everything is treated as tracked', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-06': {'cat_family': 40000.0},
          '2026-07': {'cat_family': 40000.0},
        },
        categoryNames: {'cat_family': 'Family'},
        currentMonth: '2026-08',
      );
      expect(got.single.isTracked, isTrue);
    });
  });
}
