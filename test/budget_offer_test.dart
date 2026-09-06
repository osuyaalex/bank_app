import 'package:banking_app/data/budget_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

BudgetSuggestion _s(double amount, {bool tracked = true}) => BudgetSuggestion(
  categoryId: 'internet',
  categoryName: 'Internet',
  amount: amount,
  typical: amount,
  months: const [MonthlySpend('2026-07', 6000)],
  isTracked: tracked,
);

/// When the app should say anything about a budget the user has already set.
///
/// The sorting flow opens on this, immediately after the screen where the
/// user typed their budgets. Getting it wrong means the app contradicts, in
/// one screen, the figures it asked for in the last one.
void main() {
  group('a budget the user has already set', () {
    test('spending under it is their business, not a correction', () {
      // Ten thousand allowed for Internet and six thousand spent is a ceiling
      // working as intended. Proposing six is arguing with a decision.
      expect(suggestionWorthShowing(_s(6000), 10000), isFalse);
    });

    test('spending a little over it is not news either', () {
      // The old rule was a tenth, which reported eleven thousand against ten
      // as something the user needed to look at.
      expect(suggestionWorthShowing(_s(11000), 10000), isFalse);
    });

    test('spending well over it is worth raising', () {
      expect(suggestionWorthShowing(_s(16000), 10000), isTrue);
    });

    test('exactly on the figure says nothing', () {
      expect(suggestionWorthShowing(_s(10000), 10000), isFalse);
    });
  });

  group('everything else is still offered', () {
    test('a category with no budget set', () {
      expect(suggestionWorthShowing(_s(6000), 0), isTrue);
    });

    test('money going somewhere not tracked at all', () {
      // This is the case the user cannot discover on their own: spending
      // that appears on no budget because no budget exists for it.
      expect(suggestionWorthShowing(_s(6000, tracked: false), 0), isTrue);
    });

    test('an untracked category is offered even beside a large budget', () {
      expect(suggestionWorthShowing(_s(500, tracked: false), 90000), isTrue);
    });
  });
}
