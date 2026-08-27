import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/data/budget_suggestion.dart';

const names = {'cat_family': 'Family', 'cat_food': 'Food'};

void main() {
  group('rounding to a figure a person would write', () {
    test('rounds up so the budget is livable', () {
      expect(roundBudget(47382), 48000);
      expect(roundBudget(1240), 1300);
      expect(roundBudget(2100), 2500);
      expect(roundBudget(93400), 95000);
    });
    test('an exact step is left alone', () {
      expect(roundBudget(20000), 20000);
    });
    test('nothing spent suggests nothing', () {
      expect(roundBudget(0), 0);
    });
  });

  group('typical month', () {
    test('one large payment does not drag the figure up', () {
      // Four ordinary months and one rent payment.
      expect(median([20000, 22000, 19000, 300000]), 21000);
    });
    test('the mean would have said 90,250', () {
      final mean = [20000, 22000, 19000, 300000].reduce((a, b) => a + b) / 4;
      expect(mean, greaterThan(90000));
    });
  });

  group('suggesting budgets', () {
    final byMonth = {
      '2026-04': {'cat_family': 40000.0, 'cat_food': 12000.0},
      '2026-05': {'cat_family': 95000.0, 'cat_food': 14000.0},
      '2026-06': {'cat_family': 90000.0, 'cat_food': 13000.0},
      '2026-07': {'cat_family': 100000.0, 'cat_food': 15000.0},
      '2026-08': {'cat_family': 8000.0, 'cat_food': 1000.0},
    };

    test('the month in progress is never counted', () {
      final got = suggestBudgets(
        byMonth: byMonth,
        categoryNames: names,
        currentMonth: '2026-08',
      );
      final family = got.firstWhere((s) => s.categoryId == 'cat_family');
      expect(family.months.any((m) => m.month == '2026-08'), isFalse);
      expect(family.monthsObserved, 4);
    });

    test('a half-covered month is dropped too', () {
      final got = suggestBudgets(
        byMonth: byMonth,
        categoryNames: names,
        currentMonth: '2026-08',
        partialMonths: {'2026-04'},
      );
      final family = got.firstWhere((s) => s.categoryId == 'cat_family');
      expect(family.monthsObserved, 3);
      expect(family.amount, 95000); // median of 95k, 90k, 100k
    });

    test('suggests a figure the user can live with', () {
      final got = suggestBudgets(
        byMonth: byMonth,
        categoryNames: names,
        currentMonth: '2026-08',
      );
      final food = got.firstWhere((s) => s.categoryId == 'cat_food');
      expect(food.amount, 14000);
      expect(food.isConfident, isTrue);
      expect(food.basis, 'Based on your last 4 months');
    });

    test('largest first, since that is what needs a decision', () {
      final got = suggestBudgets(
        byMonth: byMonth,
        categoryNames: names,
        currentMonth: '2026-08',
      );
      expect(got.first.categoryId, 'cat_family');
    });

    test('a category only started recently is not averaged against zeroes', () {
      final late = {
        '2026-04': {'cat_family': 40000.0},
        '2026-05': {'cat_family': 40000.0},
        '2026-06': {'cat_family': 40000.0, 'cat_food': 30000.0},
        '2026-07': {'cat_family': 40000.0, 'cat_food': 30000.0},
        '2026-08': <String, double>{},
      };
      final got = suggestBudgets(
        byMonth: late,
        categoryNames: names,
        currentMonth: '2026-08',
      );
      final food = got.firstWhere((s) => s.categoryId == 'cat_food');
      expect(food.monthsObserved, 2);
      expect(food.amount, 30000);
    });

    test('a genuine zero month still counts once the category exists', () {
      final gap = {
        '2026-05': {'cat_food': 20000.0},
        '2026-06': <String, double>{},
        '2026-07': {'cat_food': 20000.0},
        '2026-08': <String, double>{},
      };
      final got = suggestBudgets(
        byMonth: gap,
        categoryNames: names,
        currentMonth: '2026-08',
      );
      final food = got.firstWhere((s) => s.categoryId == 'cat_food');
      expect(food.monthsObserved, 3); // May, June, July
      expect(food.amount, 20000); // median of 20k, 0, 20k
    });

    test('nothing to go on yields nothing rather than a guess', () {
      final got = suggestBudgets(
        byMonth: {'2026-08': {'cat_family': 50000.0}},
        categoryNames: names,
        currentMonth: '2026-08',
      );
      expect(got, isEmpty);
    });

    test('one month is offered, but says so', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-07': {'cat_family': 50000.0},
          '2026-08': {'cat_family': 3000.0},
        },
        categoryNames: names,
        currentMonth: '2026-08',
      );
      expect(got.single.isConfident, isFalse);
      expect(got.single.basis, 'Based on one full month');
    });

    test('a catch-all bucket is never given a budget', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-06': {'cat_others': 200000.0, 'cat_family': 40000.0},
          '2026-07': {'cat_others': 250000.0, 'cat_family': 40000.0},
        },
        categoryNames: {
          'cat_others': 'Others',
          'cat_family': 'Family',
          'cat_misc': 'Miscellaneous',
        },
        currentMonth: '2026-08',
      );
      expect(got.map((s) => s.categoryName), ['Family']);
    });

    test('a category quiet in half its months is left to the user', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-04': {'cat_food': 1600.0},
          '2026-05': {'cat_food': 23300.0},
          '2026-06': <String, double>{},
          '2026-07': <String, double>{},
        },
        categoryNames: names,
        currentMonth: '2026-08',
      );
      expect(got, isEmpty);
    });

    test('but a category active in most months still gets one', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-04': {'cat_food': 4200.0},
          '2026-05': {'cat_food': 4600.0},
          '2026-06': {'cat_food': 2000.0},
          '2026-07': <String, double>{},
        },
        categoryNames: names,
        currentMonth: '2026-08',
      );
      expect(got.single.amount, 3500); // median of 0, 2000, 4200, 4600 = 3100
    });

    test('a category the user does not track is not suggested', () {
      final got = suggestBudgets(
        byMonth: {
          '2026-06': {'cat_transport': 9000.0},
          '2026-07': {'cat_transport': 9000.0},
        },
        categoryNames: names,
        currentMonth: '2026-08',
      );
      expect(got, isEmpty);
    });
  });

  group('history kept for the picker', () {
    final byMonth = {
      '2026-04': {'cat_lunch': 1600.0, 'cat_others': 90000.0},
      '2026-05': {'cat_lunch': 23300.0, 'cat_others': 90000.0},
      '2026-06': <String, double>{},
      '2026-07': <String, double>{},
    };
    const all = {
      'cat_lunch': 'Lunch',
      'cat_others': 'Others',
      'cat_family': 'Family',
    };

    test('a category too sparse to suggest still has months to show', () {
      // suggestBudgets deliberately refuses this one.
      expect(
        suggestBudgets(
            byMonth: byMonth,
            categoryNames: all,
            currentMonth: '2026-08').where((s) => s.categoryName == 'Lunch'),
        isEmpty,
      );
      // The picker still gets the figures, because the user asked for them.
      final h = categoryMonthlyHistory(
          byMonth: byMonth, categoryNames: all, currentMonth: '2026-08');
      expect(h['cat_lunch']!.map((m) => m.total), [0, 0, 23300, 1600]);
    });

    test('a catch-all keeps its history even though it gets no budget', () {
      final h = categoryMonthlyHistory(
          byMonth: byMonth, categoryNames: all, currentMonth: '2026-08');
      expect(h.containsKey('cat_others'), isTrue);
    });

    test('a category never spent on has no history invented for it', () {
      final h = categoryMonthlyHistory(
          byMonth: byMonth, categoryNames: all, currentMonth: '2026-08');
      expect(h.containsKey('cat_family'), isFalse);
    });

    test('the month in progress stays out of the picker too', () {
      final h = categoryMonthlyHistory(
        byMonth: {
          '2026-07': {'cat_lunch': 5000.0},
          '2026-08': {'cat_lunch': 200.0},
        },
        categoryNames: all,
        currentMonth: '2026-08',
      );
      expect(h['cat_lunch']!.map((m) => m.month), ['2026-07']);
    });
  });
}
