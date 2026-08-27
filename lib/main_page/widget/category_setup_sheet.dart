import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/budget_suggestion.dart';
import 'budget_picker.dart';

import 'category_picker.dart';

/// Formats a budget with thousand separators as it is typed, so the figure
/// stays readable at a glance instead of becoming a wall of digits.
/// What the user set up.
class CategorySetup {
  const CategorySetup({required this.name, required this.budget});

  final String name;

  /// Kept as the display string, e.g. `20,000`, which is the shape the rest
  /// of the app already stores budgets in.
  final String budget;
}

/// Asks for a category's name and monthly budget.
///
/// The budget is required, not optional. This app exists to budget: a
/// category without one cannot be measured against anything, and the details
/// screen renders it as "No budget set for this item" -- an unfinished state
/// the user never asked for.
///
/// Pass [fixedName] when the category already exists and only the budget is
/// missing, which happens when tagging into something not tracked this month.
///
/// [history] is what this category has cost per month, where the app knows.
/// Two or more real months and the budget is chosen from the user's own
/// spending instead of typed. [suggested] pre-fills the figure so the common
/// case is confirming rather than deciding.
Future<CategorySetup?> showCategorySetupSheet(
  BuildContext context, {
  required String currency,
  String? fixedName,
  List<double> history = const [],
  double suggested = 0,
}) {
  final nameField = TextEditingController(text: fixedName ?? '');
  final creating = fixedName == null;
  // Starts on the middle of the three choices where there is history, so the
  // sheet opens on an answer rather than on an empty field.
  var budget = suggested > 0
      ? suggested
      : (budgetChoices(history)?.usual ?? 0);

  return showModalBottomSheet<CategorySetup>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => Padding(
      // Lifts above the keyboard so the budget field is never hidden behind it.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final name = nameField.text.trim();
          final ready = name.isNotEmpty && budget > 0;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 22),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    creating ? 'New category' : 'Set a budget for $fixedName',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    creating
                        ? 'Give it a name and how much you plan to spend on it '
                            'this month.'
                        : "You're not tracking $fixedName yet. Set a monthly "
                            'budget and it will start showing on your home screen.',
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  if (creating) ...[
                    _label('CATEGORY NAME'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameField,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: _fieldDecoration(hint: 'Groceries'),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _label('MONTHLY BUDGET'),
                  const SizedBox(height: 10),
                  BudgetPicker(
                    initial: budget,
                    currency: currency,
                    history: history,
                    onChanged: (v) => setSheetState(() => budget = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          history.length >= 2
                              ? 'Worked out from what you have been spending. '
                                  'Nudge it if it looks wrong.'
                              : 'A budget is required. It is what your '
                                  'spending gets measured against.',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: ready
                              ? () => Navigator.pop(
                                    sheetContext,
                                    CategorySetup(
                                        name: name,
                                        budget: NumberFormat('#,###')
                                            .format(budget.round())),
                                  )
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade200,
                            disabledForegroundColor: Colors.grey.shade400,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            creating ? 'Add category' : 'Start tracking',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _label(String text) => Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: Colors.black38,
      ),
    );

InputDecoration _fieldDecoration({required String hint}) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade300),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: brandBlue, width: 1.6),
      ),
    );
