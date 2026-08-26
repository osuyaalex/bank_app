import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'category_picker.dart';

/// What to do with a category being removed.
enum RemoveChoice { moveThenRemove, removeAndUnfile, removeAndDelete }

/// The outcome of the sheet.
class RemoveOutcome {
  const RemoveOutcome(this.choice, {this.moveTo, this.moveToName});
  final RemoveChoice choice;
  final String? moveTo;
  final String? moveToName;
}

/// Asks what should happen to the transactions inside a category.
///
/// Removing a tracker used to delete the row and stop, leaving its
/// transactions pointing at something the user could no longer see -- money
/// still counted in the month total with nowhere to correct it. The
/// transactions have to go somewhere, and only the user knows where.
Future<RemoveOutcome?> showRemoveCategorySheet(
  BuildContext context, {
  required String categoryName,
  required int transactionCount,
  required List<Category> otherCategories,
}) {
  return showModalBottomSheet<RemoveOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text('Remove $categoryName',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  transactionCount == 0
                      ? 'Nothing is filed here, so this just removes the '
                          'budget.'
                      : '$transactionCount transaction'
                          '${transactionCount == 1 ? " is" : "s are"} filed '
                          'here. Choose where '
                          '${transactionCount == 1 ? "it goes" : "they go"}.',
                  style: TextStyle(
                      fontSize: 13.5, height: 1.45, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),

                if (transactionCount > 0 && otherCategories.isNotEmpty) ...[
                  _label('MOVE THEM TO'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in otherCategories)
                        pickerChip(
                          label: c.name,
                          selected: false,
                          onTap: () => Navigator.pop(
                            sheetContext,
                            RemoveOutcome(RemoveChoice.moveThenRemove,
                                moveTo: c.id, moveToName: c.name),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                ],

                if (transactionCount > 0) ...[
                  _option(
                    context: sheetContext,
                    icon: Icons.inbox_outlined,
                    title: 'Send them back to sorting',
                    body: 'The budget goes, the transactions stay. They return '
                        'to the sorting list so you can file them elsewhere.',
                    onTap: () => Navigator.pop(sheetContext,
                        const RemoveOutcome(RemoveChoice.removeAndUnfile)),
                  ),
                  const SizedBox(height: 10),
                  _option(
                    context: sheetContext,
                    icon: Icons.delete_forever_outlined,
                    danger: true,
                    title: 'Delete them permanently',
                    // Said plainly, because it is true and nothing else in the
                    // app behaves this way.
                    body: '$transactionCount transaction'
                        '${transactionCount == 1 ? "" : "s"} will be erased. '
                        'This cannot be undone and the records cannot be '
                        'recovered.',
                    onTap: () => _confirmDelete(
                        sheetContext, categoryName, transactionCount),
                  ),
                ] else
                  _option(
                    context: sheetContext,
                    icon: Icons.delete_outline_rounded,
                    title: 'Remove the budget',
                    body: 'Nothing else changes.',
                    onTap: () => Navigator.pop(sheetContext,
                        const RemoveOutcome(RemoveChoice.removeAndUnfile)),
                  ),

                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A second, explicit confirmation.
///
/// One tap is not enough for something that cannot be undone, and the count
/// is repeated so the number is in front of the user at the moment they agree.
Future<void> _confirmDelete(
    BuildContext context, String categoryName, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Delete permanently?'),
      content: Text(
        'This erases $count transaction${count == 1 ? "" : "s"} from '
        '$categoryName. They cannot be brought back — not by re-scanning, '
        'not by re-installing.',
        style: const TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep them'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xffC0392B)),
          child: const Text('Delete forever'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    Navigator.pop(
        context, const RemoveOutcome(RemoveChoice.removeAndDelete));
  }
}

Widget _label(String text) => Text(text,
    style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: Colors.black38));

Widget _option({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String body,
  required VoidCallback onTap,
  bool danger = false,
}) {
  final colour = danger ? const Color(0xffC0392B) : brandBlue;
  return InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
        color: colour.withValues(alpha: 0.04),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colour),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: danger ? colour : Colors.black87)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
