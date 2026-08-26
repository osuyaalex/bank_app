import 'package:banking_app/data/budget_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BudgetStatus of(double spent, double budget) =>
      BudgetStatus.of(spent: spent, budget: budget);

  test('well within budget is ok', () {
    expect(of(2000, 20000).level, BudgetLevel.ok);
  });

  test('four fifths spent starts warning', () {
    expect(of(15999, 20000).level, BudgetLevel.ok);
    expect(of(16000, 20000).level, BudgetLevel.nearing);
  });

  test('exactly on budget is not over', () {
    // Spending your budget exactly is doing it right, not failing.
    final s = of(20000, 20000);
    expect(s.level, BudgetLevel.nearing);
    expect(s.isOver, isFalse);
  });

  test('a naira past is over', () {
    final s = of(20001, 20000);
    expect(s.level, BudgetLevel.over);
    expect(s.difference, 1);
  });

  test('no budget means nothing to warn about', () {
    // Warning someone against a budget they never set is noise.
    expect(of(50000, 0).level, BudgetLevel.ok);
    expect(of(50000, 0).difference, 0);
  });

  group('wording', () {
    test('over says how far over and against what', () {
      expect(of(24500, 20000).describe('₦'),
          '₦4,500 over your ₦20,000 budget');
    });

    test('nearing says what is left', () {
      expect(of(17000, 20000).describe('₦'), '₦3,000 left of ₦20,000');
    });

    test('an empty currency symbol does not print null', () {
      expect(of(24500, 20000).describe(''), '4,500 over your 20,000 budget');
    });
  });
}
