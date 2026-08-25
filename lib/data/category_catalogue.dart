import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A category the app suggests, with the icon it ships with.
class CatalogueEntry {
  const CatalogueEntry({required this.name, required this.image});

  final String name;
  final String image;
}

/// The curated categories offered to someone who is not tracking anything yet.
///
/// These used to live only on the track-items screen, which every new user had
/// to walk through before seeing a single transaction. That screen is gone --
/// the batch screen asks the same question against real spending instead -- so
/// the list moved here, where both the picker and the batch screen's empty
/// state can offer it.
class CategoryCatalogue {
  CategoryCatalogue._();

  static const _asset = 'assets/models/track_items.json';

  static List<CatalogueEntry>? _cache;

  /// Read once per launch. The file ships with the app, so it cannot change
  /// underneath us and re-reading it per picker would be wasted work.
  static Future<List<CatalogueEntry>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = jsonDecode(await rootBundle.loadString(_asset)) as List;
      return _cache = [
        for (final e in raw)
          if (e is Map && e['name'] != null)
            CatalogueEntry(
              name: e['name'].toString(),
              image: (e['image'] ?? '').toString(),
            ),
      ];
    } catch (_) {
      // A missing or malformed asset must not take the screen down with it;
      // the user can still type a category name by hand.
      return _cache = const [];
    }
  }

  /// The suggestions worth showing: everything the user has not already got a
  /// category for. Matching is case-insensitive because a hand-typed
  /// "groceries" and the catalogue's "Groceries" are the same category.
  static List<CatalogueEntry> unseen(
    List<CatalogueEntry> all,
    Iterable<String> existingNames,
  ) {
    final taken = existingNames.map((n) => n.toLowerCase().trim()).toSet();
    return all.where((e) => !taken.contains(e.name.toLowerCase())).toList();
  }
}
