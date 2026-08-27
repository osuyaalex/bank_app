import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/parsing/category_matcher.dart';

const meals = ['Breakfast', 'Lunch', 'Dinner'];
const foodOnly = ['Food'];

String? at(String key, int hour, List<String> tracked) =>
    guessCategory(key, tracked, hourOfDay: hour)?.categoryName;

void main() {
  group('splitting food by the time it was bought', () {
    test('morning, afternoon and evening each land where they should', () {
      expect(at('MAMA PUT KITCHEN', 8, meals), 'Breakfast');
      expect(at('MAMA PUT KITCHEN', 13, meals), 'Lunch');
      expect(at('MAMA PUT KITCHEN', 20, meals), 'Dinner');
    });

    test('eating late at night is dinner, not breakfast', () {
      // A window ending at eight would have filed most evening meals wrong.
      expect(at('MAMA PUT KITCHEN', 22, meals), 'Dinner');
      expect(at('MAMA PUT KITCHEN', 1, meals), 'Dinner');
      expect(at('MAMA PUT KITCHEN', 3, meals), 'Dinner');
      expect(at('MAMA PUT KITCHEN', 5, meals), 'Breakfast');
    });

    test('it says why, in words a person can check', () {
      final g = guessCategory('CHOWDECK', meals, hourOfDay: 20);
      expect(g!.categoryName, 'Dinner');
      expect(g.reason, contains('8pm'));
    });
  });

  group('when the split must not fire', () {
    test('somebody budgeting one Food category never sees it', () {
      expect(at('MAMA PUT KITCHEN', 8, foodOnly), 'Food');
      expect(at('MAMA PUT KITCHEN', 20, foodOnly), 'Food');
    });

    test('a meal the user does not track falls back to Food', () {
      const lunchAndFood = ['Lunch', 'Food'];
      expect(at('MAMA PUT KITCHEN', 13, lunchAndFood), 'Lunch');
      expect(at('MAMA PUT KITCHEN', 20, lunchAndFood), 'Food');
    });

    test('a supermarket run in the evening is not dinner', () {
      const withGroceries = ['Breakfast', 'Lunch', 'Dinner', 'Groceries'];
      expect(at('SHOPRITE LEKKI', 20, withGroceries), 'Groceries');
    });

    test('snacks and coffee keep their own categories', () {
      const wide = ['Breakfast', 'Lunch', 'Dinner', 'Snacks', 'Coffee'];
      expect(at('JULIANA CONFECTIONARIES', 20, wide), 'Snacks');
    });

    test('a name that already says the meal beats the clock', () {
      // "Lunch" in the name is better evidence than an eight o'clock payment.
      expect(at('THE LUNCH BOX', 20, meals), 'Lunch');
    });

    test('no timestamp means no guess from the clock', () {
      expect(guessCategory('MAMA PUT KITCHEN', foodOnly)?.categoryName, 'Food');
    });

    test('a nonsense hour is ignored rather than trusted', () {
      expect(at('MAMA PUT KITCHEN', 99, meals), isNot('Dinner'));
    });

    test('non-food spending is untouched by the time of day', () {
      const wide = ['Breakfast', 'Lunch', 'Dinner', 'Fuel', 'Rent'];
      expect(at('PETROCAM FILLING STATION', 8, wide), 'Fuel');
    });
  });
}
