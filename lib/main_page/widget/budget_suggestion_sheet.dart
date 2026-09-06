import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/budget_suggestion.dart';

const _brand = Color(0xff2E5BFF);
const _ink = Color(0xff1C1939);

/// Offers budgets worked out from what the user has actually been spending.
///
/// A tester said he wanted to type in as few budgets as possible, and he was
/// right to: by the time this screen appears the app is holding months of his
/// real transactions, so asking him to invent a figure for Family is asking
/// for a number it already knows.
///
/// Every row is opt-in and every row shows its working. A budget the user did
/// not choose and cannot explain is one they will not trust when it turns red.
///
/// Returns the suggestions the user accepted, or null if they backed out.
Future<List<BudgetSuggestion>?> showBudgetSuggestionSheet(
  BuildContext context, {
  required List<BudgetSuggestion> suggestions,
  required Map<String, double> currentBudgets,
  required String currency,
}) {
  // Categories the user already has start accepted: they came here to be
  // given figures, and making them tick each one is the work this removes.
  //
  // Ones they do not track start unticked. Accepting those adds rows to their
  // home screen, which is a larger thing than changing a number, and taking it
  // by default would be deciding on their behalf.
  final accepted = {
    for (final s in suggestions)
      if (s.isTracked) s.categoryId
  };

  final tracked = suggestions.where((s) => s.isTracked).toList();
  final untracked = suggestions.where((s) => !s.isTracked).toList();

  String money(double v) => '$currency${NumberFormat('#,###').format(v)}';

  return showModalBottomSheet<List<BudgetSuggestion>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final height = MediaQuery.of(sheetContext).size.height;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.86),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Budgets from your own spending',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: _ink)),
                      const SizedBox(height: 4),
                      Text(
                        'Worked out from your past months. Change anything '
                        'that looks wrong, or leave it out.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    children: [
                      for (final s in tracked) ...[
                        _SuggestionRow(
                          suggestion: s,
                          accepted: accepted.contains(s.categoryId),
                          currentBudget: currentBudgets[s.categoryName] ?? 0,
                          money: money,
                          onToggle: () => setSheetState(() {
                            accepted.contains(s.categoryId)
                                ? accepted.remove(s.categoryId)
                                : accepted.add(s.categoryId);
                          }),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (untracked.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                          child: Text(
                            "YOU DON'T TRACK THESE YET",
                            style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 0.9,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade500),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                          child: Text(
                            'Money has been going here every month. Tick one '
                            'and it starts being tracked at this budget.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                        for (final s in untracked) ...[
                          _SuggestionRow(
                            suggestion: s,
                            accepted: accepted.contains(s.categoryId),
                            currentBudget: 0,
                            money: money,
                            onToggle: () => setSheetState(() {
                              accepted.contains(s.categoryId)
                                  ? accepted.remove(s.categoryId)
                                  : accepted.add(s.categoryId);
                            }),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text('Not now',
                            style: TextStyle(color: Colors.grey.shade700)),
                      ),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: accepted.isEmpty
                            ? null
                            : () => Navigator.pop(
                                  sheetContext,
                                  suggestions
                                      .where((s) =>
                                          accepted.contains(s.categoryId))
                                      .toList(),
                                ),
                        child: Text(
                          accepted.length == suggestions.length
                              ? 'Use these ${accepted.length}'
                              : 'Use ${accepted.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.accepted,
    required this.currentBudget,
    required this.money,
    required this.onToggle,
  });

  final BudgetSuggestion suggestion;
  final bool accepted;
  final double currentBudget;
  final String Function(double) money;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    // Worth saying out loud when the figure the user set is nowhere near what
    // they spend. That gap is the whole reason this screen is useful.
    final farOff = currentBudget > 0 && s.amount > currentBudget * 1.5;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: accepted ? const Color(0xffF4F7FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accepted ? _brand.withValues(alpha: 0.45)
                            : Colors.grey.shade300,
            width: accepted ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(s.categoryName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _ink)),
                      ),
                      if (!s.isTracked) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xffEFF3FF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text('NEW',
                              style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w700,
                                  color: _brand)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(money(s.amount),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _brand)),
                      const SizedBox(width: 6),
                      Text('a month',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    s.basis,
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  if (currentBudget > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      farOff
                          ? 'You have ${money(currentBudget)} set — you have '
                              'been going well past it'
                          : 'Currently ${money(currentBudget)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: farOff
                            ? const Color(0xffB3261E)
                            : Colors.grey.shade600,
                        fontWeight:
                            farOff ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                  if (s.months.length > 1) ...[
                    const SizedBox(height: 8),
                    BudgetSparkline(months: s.months, money: money),
                  ],
                ],
              ),
            ),
            Icon(
              accepted ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: accepted ? _brand : Colors.grey.shade400,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// The months behind the figure, oldest to newest.
///
/// Small, unlabelled and deliberately so -- it is not a chart to be read off,
/// it is evidence that the number came from somewhere.
class BudgetSparkline extends StatelessWidget {
  const BudgetSparkline({super.key, required this.months, required this.money});

  final List<MonthlySpend> months;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final ordered = [...months]..sort((a, b) => a.month.compareTo(b.month));
    final peak = ordered.map((m) => m.total).fold<double>(0, (a, b) => a > b ? a : b);
    if (peak <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final m in ordered)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: '${_label(m.month)}  ${money(m.total)}',
                child: Container(
                  width: 16,
                  height: (m.total / peak * 26).clamp(2.0, 26.0),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _label(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final n = int.tryParse(parts[1]);
    if (n == null || n < 1 || n > 12) return monthKey;
    return DateFormat.MMM().format(DateTime(2000, n));
  }
}
