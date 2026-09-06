/// Working out what a budget should be from what the user already spends.
///
/// The app arrives holding months of the user's real transactions, so asking
/// them to invent a figure for "Family" is asking for a number it could work
/// out itself. A tester put it plainly: he wanted to type in as few budgets as
/// possible.
library;

/// What one category cost in one month.
class MonthlySpend {
  const MonthlySpend(this.month, this.total);

  /// `2026-06`.
  final String month;
  final double total;
}

/// A budget the app is proposing, and the evidence behind it.
class BudgetSuggestion {
  const BudgetSuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.typical,
    required this.months,
    this.isTracked = true,
  });

  final String categoryId;
  final String categoryName;

  /// The figure to offer, rounded to something a person would actually write.
  final double amount;

  /// The unrounded middle month, kept so the screen can explain itself.
  final double typical;

  /// The complete months this was drawn from, newest first.
  final List<MonthlySpend> months;

  /// False when the user does not have this category yet.
  ///
  /// Accepting one of these does two things at once -- starts tracking the
  /// category and sets its budget -- which is the whole point, and also why
  /// the screen must not tick them by default. Adding rows to somebody's home
  /// screen is a bigger thing than changing a number on one.
  final bool isTracked;

  BudgetSuggestion copyWith({double? amount}) => BudgetSuggestion(
        categoryId: categoryId,
        categoryName: categoryName,
        amount: amount ?? this.amount,
        typical: typical,
        months: months,
        isTracked: isTracked,
      );

  int get monthsObserved => months.length;

  /// Three months is where a figure stops being one month's accident.
  bool get isConfident => months.length >= 3;

  double get highest =>
      months.isEmpty ? 0 : months.map((m) => m.total).reduce((a, b) => a > b ? a : b);

  /// Said in words, because a person setting a budget wants to know how much
  /// to trust the number, not how it was computed.
  String get basis => switch (months.length) {
        0 => 'No full month to go on yet',
        1 => 'Based on one full month',
        2 => 'Based on 2 months — still settling',
        _ => 'Based on your last ${months.length} months',
      };
}

/// Whether a proposal is worth putting in front of the user at all.
///
/// [currentBudget] is what they have set for it, or zero for nothing set.
///
/// The rule used to be a tenth either way, which made this screen argue with
/// the one before it: a user who set ten thousand for Internet and spends six
/// was told, immediately after typing it, that the app thought six. That is
/// not a correction, it is a disagreement about a decision the app was not
/// asked to make -- a budget above what someone spends is a ceiling they
/// chose, and the whole point of choosing it is that it is not last month.
///
/// What is worth saying is the other direction, and only by enough to matter.
bool suggestionWorthShowing(BudgetSuggestion s, double currentBudget) {
  if (!s.isTracked) return true; // money going somewhere untracked
  if (currentBudget <= 0) return true; // nothing set at all
  if (s.amount <= currentBudget) return false; // their ceiling, their call
  return (s.amount - currentBudget) / currentBudget > 0.25;
}

/// Categories that exist to absorb what has not been decided yet.
const _catchAll = {
  'others',
  'other',
  'miscellaneous',
  'misc',
  'uncategorised',
  'uncategorized',
  'unsorted',
  'general',
  'cash',
};

/// How much a budget of this size should move by when nudged once.
///
/// Proportional, so a tap does something meaningful at every scale: ₦100 at
/// the bottom would be twelve taps to shift a ₦46,000 budget by anything a
/// person would notice.
double budgetStep(double v) {
  if (v >= 500000) return 50000;
  if (v >= 100000) return 10000;
  if (v >= 50000) return 5000;
  if (v >= 10000) return 1000;
  if (v >= 2000) return 500;
  return 100;
}

/// Rounds to a figure someone would choose themselves.
///
/// Rounds up, not to nearest: a budget set fractionally below what the user
/// reliably spends is one they blow in week three, and the point of the
/// suggestion is to be livable.
double roundBudget(double v) {
  if (v <= 0) return 0;
  final step = budgetStep(v);
  return (v / step).ceil() * step;
}

/// The value [p] of the way through a sorted list, 0 to 1.
double percentile(List<double> xs, double p) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  if (s.length == 1) return s.first;
  final at = (s.length - 1) * p;
  final lo = at.floor();
  final hi = at.ceil();
  if (lo == hi) return s[lo];
  return s[lo] + (s[hi] - s[lo]) * (at - lo);
}

/// Three budgets to choose between, drawn from the user's own months.
///
/// Typing a figure is the slowest thing this app asks anybody to do, and the
/// figures worth typing are already implied by their history: a lean month, a
/// normal one, and a comfortable one. Three taps' worth of choice removes the
/// keyboard from the common path entirely.
///
/// Returns null when there is not enough history to say anything honest, in
/// which case the caller falls back to round numbers.
({double tight, double usual, double roomy})? budgetChoices(
    List<double> months) {
  final real = months.where((m) => m > 0).toList();
  if (real.length < 2) return null;

  var tight = roundBudget(percentile(months, 0.25));
  var usual = roundBudget(median(months));
  var roomy = roundBudget(percentile(months, 0.75));

  // Steady spending collapses all three onto the same figure, which reads as
  // a broken control rather than a stable habit. Spread them by one step so
  // there is still a choice to make.
  final step = budgetStep(usual);
  if (usual <= 0) return null;
  if (tight >= usual) tight = usual - step;
  if (roomy <= usual) roomy = usual + step;
  if (tight <= 0) tight = step;

  return (tight: tight, usual: usual, roomy: roomy);
}

/// Round figures to pick from, whatever the size of the budget.
///
/// A 1-2-5 progression, which is how people actually round money: nobody sets
/// a budget of ₦37,000, they set ₦20,000 or ₦50,000. It runs to two million
/// because rent, school fees and family support are all budgets somebody
/// genuinely needs to set, and a ladder that stopped at ₦50,000 quietly told
/// them this app was not for them.
///
/// Long, but shown in one row that scrolls, so its length costs no height.
const budgetLadder = <double>[
  1000, 2000, 5000, 10000, 20000, 50000,
  100000, 200000, 500000, 1000000, 2000000,
];

/// Money written short enough to sit on a chip.
///
/// ₦500,000 is eight characters and a chip that wide pushes everything else
/// off the row. `₦500k` is read the same way by anyone who would type it.
String compactMoney(double v, String currency) {
  String trim(double n) => n == n.roundToDouble()
      ? n.toStringAsFixed(0)
      : n.toStringAsFixed(1);
  if (v >= 1000000) return '$currency${trim(v / 1000000)}M';
  if (v >= 1000) return '$currency${trim(v / 1000)}k';
  return '$currency${v.toStringAsFixed(0)}';
}

/// The middle value, which is what "typical" has to mean here.
///
/// Not the mean. One ₦300,000 rent payment in an ordinary month of transfers
/// drags an average far above anything the user actually spends month to
/// month, and a budget built on it is useless in both directions.
double median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// Proposes a budget per category from historical monthly spend.
///
/// [byMonth] maps `2026-06` to category id to what was spent. [partialMonths]
/// and [currentMonth] are excluded: a month the inbox only half covers, or one
/// still in progress, reads as an unusually cheap month and would drag every
/// figure down.
///
/// A category is only averaged from the month it first appears. Counting the
/// months before the user ever paid that counterparty as zeroes would halve a
/// budget for a category they only started using recently.
List<BudgetSuggestion> suggestBudgets({
  required Map<String, Map<String, double>> byMonth,
  required Map<String, String> categoryNames,
  required String currentMonth,
  Set<String> partialMonths = const {},
  Set<String> trackedNames = const {},
  int lookback = 6,
}) {
  // Empty means "assume everything offered is already tracked", which is what
  // every caller wanted before untracked categories were proposed at all.
  final tracked = trackedNames.isEmpty
      ? null
      : trackedNames.map((n) => n.toLowerCase().trim()).toSet();
  bool isCatchAll(String name) =>
      _catchAll.contains(name.toLowerCase().trim());
  final usable = byMonth.keys
      .where((m) => m != currentMonth && !partialMonths.contains(m))
      .toList()
    ..sort((a, b) => b.compareTo(a)); // newest first

  if (usable.isEmpty) return const [];
  final window = usable.take(lookback).toList();

  final out = <BudgetSuggestion>[];
  for (final entry in categoryNames.entries) {
    final id = entry.key;
    // A catch-all is where things land when nobody has decided yet, so its
    // total is the size of the backlog, not of a spending habit. Proposing a
    // budget for it would be proposing a budget for "everything else".
    if (isCatchAll(entry.value)) continue;

    // Oldest month in the window in which this category appears at all.
    final seen = window.where((m) => (byMonth[m]?[id] ?? 0) > 0).toList();
    if (seen.isEmpty) continue;
    final firstSeen = seen.last;

    // From first appearance onward, a month with nothing in it is a real
    // zero -- the user genuinely spent nothing on this that month.
    final months = [
      for (final m in window)
        if (m.compareTo(firstSeen) >= 0) MonthlySpend(m, byMonth[m]?[id] ?? 0)
    ];
    if (months.isEmpty) continue;

    // A category the user spends on in only some months has no monthly
    // figure worth proposing -- the middle month is near zero and the
    // suggestion comes out as a number nobody would choose. Better to say
    // nothing and let them set it themselves.
    final active = months.where((m) => m.total > 0).length;
    if (active * 2 <= months.length) continue;

    final typical = median([for (final m in months) m.total]);
    final amount = roundBudget(typical);
    if (amount <= 0) continue;

    out.add(BudgetSuggestion(
      categoryId: id,
      categoryName: entry.value,
      amount: amount,
      typical: typical,
      months: months,
      isTracked:
          tracked == null || tracked.contains(entry.value.toLowerCase().trim()),
    ));
  }

  out.sort((a, b) {
    if (a.isTracked != b.isTracked) return a.isTracked ? -1 : 1;
    return b.amount.compareTo(a.amount);
  });
  return out;
}

/// The monthly figures behind a category, for a screen about to ask for its
/// budget. Empty when the app has nothing on it, which the picker handles by
/// falling back to round numbers.
List<double> historyFor(List<BudgetSuggestion> all, String categoryName) {
  final want = categoryName.toLowerCase().trim();
  for (final s in all) {
    if (s.categoryName.toLowerCase().trim() == want) {
      return [for (final m in s.months) m.total];
    }
  }
  return const [];
}

/// Every category's monthly figures, with none of the suggestion rules applied.
///
/// [suggestBudgets] decides what the app should *volunteer*, and rightly
/// ignores catch-alls and anything the user only spends on now and then. This
/// is the other question: the user has picked a category and is being asked
/// for its budget, so whatever months exist are worth showing them.
///
/// Same window as the proposals -- the month in progress and any half-covered
/// month are still excluded, because a partial month is misleading whoever is
/// looking at it.
Map<String, List<MonthlySpend>> categoryMonthlyHistory({
  required Map<String, Map<String, double>> byMonth,
  required Map<String, String> categoryNames,
  required String currentMonth,
  Set<String> partialMonths = const {},
  int lookback = 6,
}) {
  final usable = byMonth.keys
      .where((m) => m != currentMonth && !partialMonths.contains(m))
      .toList()
    ..sort((a, b) => b.compareTo(a));
  if (usable.isEmpty) return const {};
  final window = usable.take(lookback).toList();

  final out = <String, List<MonthlySpend>>{};
  for (final id in categoryNames.keys) {
    final seen = window.where((m) => (byMonth[m]?[id] ?? 0) > 0).toList();
    if (seen.isEmpty) continue;
    final firstSeen = seen.last;
    out[id] = [
      for (final m in window)
        if (m.compareTo(firstSeen) >= 0) MonthlySpend(m, byMonth[m]?[id] ?? 0)
    ];
  }
  return out;
}

/// Category names that mean the same spending.
///
/// The app can offer the same money under two names -- "Car Fuel" from the
/// shipped catalogue, "Fuel" from a ghost chip -- and whichever one the
/// matcher happened to pick is the only one that ends up holding any history.
/// Tapping the other then shows round numbers for money the app has records
/// of, which reads as the feature being broken.
///
/// Deliberately only genuine synonyms. Lunch, Dinner and Takeout are *not*
/// pooled into Food: they are different spending, and lending one the other's
/// total would be inventing a figure rather than reporting one.
const _aliasGroups = <List<String>>[
  ['fuel', 'car fuel', 'petrol', 'diesel', 'gas'],
  ['mobile phone', 'airtime', 'phone', 'recharge', 'data'],
  ['transport', 'public transport', 'transportation'],
  ['others', 'other', 'miscellaneous', 'misc', 'general', 'sundry'],
  ['groceries', 'grocery', 'supermarket'],
  ['utilities', 'bills', 'electricity', 'power'],
  ['healthcare', 'health', 'medical'],
  ['education', 'school', 'tuition'],
  ['clothing', 'clothes', 'fashion'],
  ['personal care', 'grooming'],
  ['subscriptions', 'subscription'],
  ['savings', 'saving'],
  ['investments', 'investment'],
  ['gifts', 'gift'],
  ['charity', 'donations', 'donation'],
  ['transfers', 'transfer'],
  ['friends', 'friend'],
  ['rent', 'housing'],
];

final Map<String, String> _aliasIndex = {
  for (final group in _aliasGroups)
    for (final name in group) name: group.first,
};

/// The name under which a category's history is pooled.
///
/// Its own name, lowercased, unless it shares meaning with another -- in which
/// case the group's first name stands for all of them.
String canonicalBudgetName(String name) {
  final k = name.toLowerCase().trim();
  return _aliasIndex[k] ?? k;
}

/// Merges the history of categories that mean the same thing.
///
/// Keyed by canonical name rather than category id, because the whole point is
/// that two ids -- `cat_fuel` and `cat_car_fuel` -- are one pot of money.
Map<String, List<MonthlySpend>> poolHistoryByAlias(
  Map<String, List<MonthlySpend>> byCategoryId,
  Map<String, String> categoryNames,
) {
  final totals = <String, Map<String, double>>{};

  byCategoryId.forEach((id, months) {
    final name = categoryNames[id];
    if (name == null) return;
    final key = canonicalBudgetName(name);
    final bucket = totals[key] ??= <String, double>{};
    for (final m in months) {
      bucket.update(m.month, (v) => v + m.total, ifAbsent: () => m.total);
    }
  });

  return {
    for (final e in totals.entries)
      e.key: (e.value.entries.map((m) => MonthlySpend(m.key, m.value)).toList()
        ..sort((a, b) => b.month.compareTo(a.month)))
  };
}
