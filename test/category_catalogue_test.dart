import 'package:banking_app/data/category_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const all = [
    CatalogueEntry(name: 'Groceries', image: 'a.svg'),
    CatalogueEntry(name: 'Rent', image: 'b.svg'),
    CatalogueEntry(name: 'Car Fuel', image: 'c.svg'),
  ];

  group('CategoryCatalogue.unseen', () {
    test('drops what the user already has', () {
      final left = CategoryCatalogue.unseen(all, ['Rent']);
      expect(left.map((e) => e.name), ['Groceries', 'Car Fuel']);
    });

    test('matches regardless of case or padding', () {
      // A hand-typed "groceries" and the catalogue's "Groceries" are the same
      // category; suggesting it again would let the user create a duplicate.
      final left = CategoryCatalogue.unseen(all, ['  groceries ', 'RENT']);
      expect(left.map((e) => e.name), ['Car Fuel']);
    });

    test('returns everything when the user tracks nothing', () {
      expect(CategoryCatalogue.unseen(all, const []).length, 3);
    });
  });
}
