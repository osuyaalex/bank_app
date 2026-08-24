import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'category_picker.dart';

/// Formats a budget with thousand separators as it is typed, so the figure
/// stays readable at a glance instead of becoming a wall of digits.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = NumberFormat('#,###').format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

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
Future<CategorySetup?> showCategorySetupSheet(
  BuildContext context, {
  required String currency,
  String? fixedName,
}) {
  final nameField = TextEditingController(text: fixedName ?? '');
  final budgetField = TextEditingController();
  final creating = fixedName == null;

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
          final budgetDigits =
              budgetField.text.replaceAll(RegExp(r'[^0-9]'), '');
          final budget = int.tryParse(budgetDigits) ?? 0;
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: budgetField,
                    autofocus: !creating,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandsFormatter()],
                    onChanged: (_) => setSheetState(() {}),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700),
                    decoration: _fieldDecoration(hint: '0').copyWith(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 6, 0),
                        child: Text(
                          currency.isEmpty ? '' : currency,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'A budget is required. It is what your spending gets '
                          'measured against.',
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
                                            .format(budget)),
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
