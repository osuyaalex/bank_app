import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'category_picker.dart';

/// One thing waiting to be filed.
class BulkSortRow {
  const BulkSortRow({
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
}

/// Files several things at once, each somewhere different if need be.
///
/// The bulk action began as "put them all in one place", which is right when
/// the user genuinely does not care and wrong the moment they do -- and then
/// they are back to opening rows one at a time, which is the chore this
/// existed to remove.
///
/// So both, in one sheet. "Same for all" is one tap when everything belongs
/// together. Otherwise each row carries the categories inline, so filing
/// twenty things differently is twenty taps in one place rather than twenty
/// trips through a picker.
///
/// Returns row id to category id, or null if the user backed out. Rows left
/// untouched are absent, and the caller leaves them alone.
Future<Map<String, String>?> showBulkSortSheet(
  BuildContext context, {
  required List<BulkSortRow> rows,
  required List<Category> categories,
}) {
  final chosen = <String, String>{};

  return showModalBottomSheet<Map<String, String>>(
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sort ${rows.length}',
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'Tap a budget on each, or use Same for all.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),

                // The one-tap path, kept first because it is the common case.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Row(
                    children: [
                      Text('SAME FOR ALL',
                          style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 0.9,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => pickerChip(
                      label: categories[i].name,
                      selected: false,
                      onTap: () => setSheetState(() {
                        for (final r in rows) {
                          chosen[r.id] = categories[i].id;
                        }
                      }),
                    ),
                  ),
                ),

                const Divider(height: 26),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final pick = chosen[row.id];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(row.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (pick != null)
                                  const Icon(Icons.check_circle_rounded,
                                      size: 17, color: brandBlue),
                              ],
                            ),
                            if (row.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(row.subtitle!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500)),
                            ],
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final c in categories)
                                  pickerChip(
                                    label: c.name,
                                    selected: pick == c.id,
                                    onTap: () => setSheetState(() {
                                      // Tapping the current pick clears it,
                                      // so a mistake costs one tap not a
                                      // reopened sheet.
                                      if (chosen[row.id] == c.id) {
                                        chosen.remove(row.id);
                                      } else {
                                        chosen[row.id] = c.id;
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          chosen.isEmpty
                              ? 'Nothing chosen yet'
                              : '${chosen.length} of ${rows.length} chosen',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade700),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        onPressed: chosen.isEmpty
                            ? null
                            : () => Navigator.pop(
                                sheetContext, Map<String, String>.from(chosen)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Apply',
                            style: TextStyle(fontWeight: FontWeight.w600)),
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
