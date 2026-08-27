import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/data/budget_suggestion.dart';

void main() {
  group('names that mean the same spending', () {
    test('the catalogue name and the lexicon name land together', () {
      expect(canonicalBudgetName('Car Fuel'), canonicalBudgetName('Fuel'));
      expect(canonicalBudgetName('Public Transport'),
          canonicalBudgetName('Transport'));
      expect(canonicalBudgetName('Miscellaneous'),
          canonicalBudgetName('Others'));
      expect(canonicalBudgetName('Airtime'),
          canonicalBudgetName('Mobile Phone'));
    });

    test('casing and stray spaces do not make a second category', () {
      expect(canonicalBudgetName('  CAR FUEL '), 'fuel');
    });

    test('a name of its own is left alone', () {
      expect(canonicalBudgetName('Family'), 'family');
      expect(canonicalBudgetName('Chowdeck Money'), 'chowdeck money');
    });

    test('different meals are not treated as the same money', () {
      // Deliberate: lending Takeout the whole food total would be inventing a
      // figure, not reporting one.
      expect(canonicalBudgetName('Takeout'),
          isNot(canonicalBudgetName('Food')));
      expect(canonicalBudgetName('Lunch'), isNot(canonicalBudgetName('Food')));
    });
  });

  group('pooling the history', () {
    test('two names for one spend add up, month by month', () {
      final pooled = poolHistoryByAlias(
        {
          'cat_fuel': const [
            MonthlySpend('2026-07', 5000),
            MonthlySpend('2026-06', 3000),
          ],
          'cat_car_fuel': const [
            MonthlySpend('2026-07', 1000),
            MonthlySpend('2026-05', 2000),
          ],
        },
        {'cat_fuel': 'Fuel', 'cat_car_fuel': 'Car Fuel'},
      );

      expect(pooled.keys, ['fuel']);
      final months = {for (final m in pooled['fuel']!) m.month: m.total};
      expect(months['2026-07'], 6000); // both halves
      expect(months['2026-06'], 3000);
      expect(months['2026-05'], 2000);
    });

    test('newest month first, as the sparkline expects', () {
      final pooled = poolHistoryByAlias(
        {
          'cat_fuel': const [
            MonthlySpend('2026-05', 1),
            MonthlySpend('2026-07', 2),
            MonthlySpend('2026-06', 3),
          ]
        },
        {'cat_fuel': 'Fuel'},
      );
      expect(pooled['fuel']!.map((m) => m.month),
          ['2026-07', '2026-06', '2026-05']);
    });

    test('unrelated categories stay in their own pots', () {
      final pooled = poolHistoryByAlias(
        {
          'cat_food': const [MonthlySpend('2026-07', 5000)],
          'cat_lunch': const [MonthlySpend('2026-07', 1000)],
        },
        {'cat_food': 'Food', 'cat_lunch': 'Lunch'},
      );
      expect(pooled.keys.toSet(), {'food', 'lunch'});
    });

    test('a category with no name is dropped, not pooled under nothing', () {
      final pooled = poolHistoryByAlias(
        {'cat_ghost': const [MonthlySpend('2026-07', 5000)]},
        const {},
      );
      expect(pooled, isEmpty);
    });
  });
}
