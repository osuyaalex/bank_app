import 'package:intl/intl.dart';

/// How a category is doing against its budget.
enum BudgetLevel {
  /// Comfortably within budget.
  ok,

  /// Most of the budget is gone. Worth a quiet warning, not an alarm.
  nearing,

  /// Spent more than the budget allows.
  over,
}

/// A category's standing against its budget, and how to say it.
///
/// Pure, so the home screen's colouring and the notification's wording come
/// from one rule rather than two that can drift apart.
class BudgetStatus {
  const BudgetStatus({
    required this.level,
    required this.spent,
    required this.budget,
    required this.difference,
  });

  final BudgetLevel level;
  final double spent;
  final double budget;

  /// How far over, or how much is left. Always positive; [level] says which.
  final double difference;

  bool get isOver => level == BudgetLevel.over;

  /// The fraction of the budget used, capped for display purposes only.
  double get fraction => budget <= 0 ? 0 : spent / budget;

  /// Where the warning starts. Four fifths spent is late enough to be worth
  /// saying and early enough to still be able to act on.
  static const nearingThreshold = 0.8;

  factory BudgetStatus.of({required double spent, required double budget}) {
    if (budget <= 0) {
      // No budget means nothing to measure against, so nothing to warn about.
      return BudgetStatus(
        level: BudgetLevel.ok,
        spent: spent,
        budget: budget,
        difference: 0,
      );
    }
    if (spent > budget) {
      return BudgetStatus(
        level: BudgetLevel.over,
        spent: spent,
        budget: budget,
        difference: spent - budget,
      );
    }
    return BudgetStatus(
      level: spent / budget >= nearingThreshold
          ? BudgetLevel.nearing
          : BudgetLevel.ok,
      spent: spent,
      budget: budget,
      difference: budget - spent,
    );
  }

  /// A sentence the user can act on.
  ///
  /// Says the figure and what it is measured against, because "over budget"
  /// on its own tells someone they have a problem without telling them how
  /// big it is.
  String describe(String currency) {
    final money = NumberFormat('#,##0');
    final c = currency.isEmpty ? '' : currency;
    switch (level) {
      case BudgetLevel.over:
        return '$c${money.format(difference)} over your '
            '$c${money.format(budget)} budget';
      case BudgetLevel.nearing:
        return '$c${money.format(difference)} left of '
            '$c${money.format(budget)}';
      case BudgetLevel.ok:
        return budget <= 0
            ? 'No budget set'
            : '$c${money.format(difference)} left of '
                '$c${money.format(budget)}';
    }
  }
}
