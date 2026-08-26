import 'package:flutter/material.dart';

import '../../data/category_catalogue.dart';
import '../../data/models.dart';
import 'ghost_chip.dart';

const brandBlue = Color(0xff5AA5E2);

/// What the user picked: a category, or "this is my own account".
class CategoryChoice {
  const CategoryChoice.category(this.categoryId) : notSpending = false;
  const CategoryChoice.notSpending()
      : categoryId = null,
        notSpending = true;

  final String? categoryId;
  final bool notSpending;
}

Widget pickerChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? brandBlue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );

/// The category picker, shared by the batch screen and the pending list.
///
/// Categories are split into what is tracked this month and what is not,
/// because a tag pointing at an untracked category is remembered but its money
/// will not appear anywhere the user can see it.
Future<CategoryChoice?> showCategoryPicker(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<Category> categories,
  required Set<String> tracked,
  CategoryChoice? current,
  Future<Category?> Function()? onCreate,
  List<CatalogueEntry> suggestions = const [],
  Future<Category?> Function(CatalogueEntry)? onAdopt,
  List<String> ghostOptions = const [],
  String? ghostReason,
  Future<Category?> Function(String)? onAcceptGhost,
}) {
  Widget group(BuildContext sheetContext, String heading, Iterable<Category> items) {
    final list = items.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(heading.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: Colors.black38)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in list)
              pickerChip(
                label: c.name,
                selected: current?.categoryId == c.id,
                onTap: () =>
                    Navigator.pop(sheetContext, CategoryChoice.category(c.id)),
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  return showModalBottomSheet<CategoryChoice>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(subtitle,
                style: const TextStyle(color: Colors.black45, fontSize: 13)),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    group(sheetContext, 'Tracking this month',
                        categories.where((c) => tracked.contains(c.name))),
                    // Straight after what the user tracks, because that is
                    // where they look first and where the app's own answer
                    // belongs -- not buried under two other headings.
                    if (ghostOptions.isNotEmpty && onAcceptGhost != null) ...[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('THE APP SUGGESTS',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                                color: Colors.black38)),
                      ),
                      if (ghostReason != null) ...[
                        GhostHint(text: ghostReason),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in ghostOptions)
                            GhostChip(
                              label: name,
                              onTap: () async {
                                final created = await onAcceptGhost(name);
                                if (created == null) return;
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext,
                                      CategoryChoice.category(created.id));
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    group(sheetContext, 'Not tracked this month',
                        categories.where((c) => !tracked.contains(c.name))),
                    if (suggestions.isNotEmpty && onAdopt != null) ...[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, top: 4),
                        child: Text('SUGGESTED',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                                color: Colors.black38)),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in suggestions)
                            pickerChip(
                              label: s.name,
                              selected: false,
                              onTap: () async {
                                final created = await onAdopt(s);
                                if (created == null) return;
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext,
                                      CategoryChoice.category(created.id));
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        pickerChip(
                          label: 'My own account',
                          selected: current?.notSpending ?? false,
                          onTap: () => Navigator.pop(
                              sheetContext, const CategoryChoice.notSpending()),
                        ),
                        if (onCreate != null)
                          pickerChip(
                            label: '+ New category',
                            selected: false,
                            onTap: () async {
                              final created = await onCreate();
                              if (created == null) return;
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext,
                                    CategoryChoice.category(created.id));
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
