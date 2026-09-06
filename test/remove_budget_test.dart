import 'package:banking_app/main_page/select_track_items.dart';
import 'package:flutter_test/flutter_test.dart';

/// The budget setup screen shows two kinds of row that look identical, and
/// removing them does not mean the same thing.
///
/// Before this, it had no removal at all. `_toggle` carried an un-picking
/// branch, but the grid that called it was built from the categories *not*
/// chosen, so the branch could never run; a category tapped by mistake could
/// only be given a budget, and during onboarding the back gesture is closed,
/// so there was no way out of the screen without it.
void main() {
  group('which kind of removal a row needs', () {
    test('a category picked on this screen is simply un-picked', () {
      // Nothing has been written and nothing has been filed against it.
      expect(removalFor({'Food'}, 'Transport'), Removal.unpick);
    });

    test('one that was already tracked has to be asked about', () {
      // It may have weeks of transactions behind it. Dropping it silently is
      // what left money counted in the month total with nowhere to correct it.
      expect(removalFor({'Food'}, 'Food'), Removal.askWhereTheMoneyGoes);
    });

    test('nothing tracked yet means nothing can be destructive', () {
      // First setup: every row on the screen was picked a moment ago.
      expect(removalFor(const {}, 'Food'), Removal.unpick);
    });

    test('the name is matched as the screen stores it', () {
      // `_chosen` and `_tracked` are both keyed by display name, so a
      // near-miss must not be mistaken for a tracked category and quietly
      // routed through a delete.
      expect(removalFor({'Food'}, 'food'), Removal.unpick);
      expect(removalFor({'Food'}, 'Food & Drink'), Removal.unpick);
    });
  });

  group('what counts as a budget', () {
    test('a figure with separators is read', () {
      expect(isRealBudget('20,000'), isTrue);
    });

    test('zero is not a budget', () {
      // A carried-forward category whose figure was never set arrives as
      // exactly this, and a month could be confirmed measuring against it.
      expect(isRealBudget('0'), isFalse);
      expect(isRealBudget('0.00'), isFalse);
    });

    test('an empty or non-numeric field is not a budget', () {
      expect(isRealBudget(''), isFalse);
      expect(isRealBudget('N'), isFalse);
    });
  });

  group('the running total', () {
    test('adds the figures as they are stored', () {
      expect(budgetTotal(['20,000', '5,500', '1,000']), 26500);
    });

    test(
      'an unset budget contributes nothing rather than breaking the sum',
      () {
        expect(budgetTotal(['20,000', '', '0']), 20000);
      },
    );

    test('nothing chosen is zero, not a crash', () {
      expect(budgetTotal(const []), 0);
    });
  });
}
