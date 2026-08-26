import 'package:banking_app/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// What each of the two moves leaves behind.
///
/// The breakdown offers both over the same money, sliced two ways, and until
/// now both quietly changed where future payments went. One of them should
/// not: moving a single ₦50,000 payment to somebody you usually buy lunch
/// from says that payment was rent, and says nothing about the next one.
({String? categoryId, Disposition? disposition, int overrides}) afterMove({
  required bool isRule,
  required int previousOverrides,
  required String toCategoryId,
}) {
  if (isRule) {
    // "Move all", from the counterparty view. A deliberate decision, so the
    // correction counter starts again.
    return (
      categoryId: toCategoryId,
      disposition: Disposition.tracked,
      overrides: 0
    );
  }

  // "Just this one". The rule is untouched.
  final overrides = previousOverrides + 1;
  if (overrides >= CounterpartyEntry.overrideLimit) {
    return (categoryId: null, disposition: Disposition.ask, overrides: overrides);
  }
  return (categoryId: null, disposition: null, overrides: overrides);
}

void main() {
  group('Move all sets the rule', () {
    test('future payments follow', () {
      final r = afterMove(
          isRule: true, previousOverrides: 0, toCategoryId: 'cat_snacks');
      expect(r.categoryId, 'cat_snacks');
      expect(r.disposition, Disposition.tracked);
    });

    test('and the correction count starts again', () {
      // A deliberate switch is a fresh decision, not another complaint.
      final r = afterMove(
          isRule: true, previousOverrides: 2, toCategoryId: 'cat_snacks');
      expect(r.overrides, 0);
    });
  });

  group('Just this one changes nothing else', () {
    test('the rule is left alone', () {
      final r = afterMove(
          isRule: false, previousOverrides: 0, toCategoryId: 'cat_rent');
      expect(r.categoryId, isNull);
      expect(r.disposition, isNull);
    });

    test('but it is still counted', () {
      final r = afterMove(
          isRule: false, previousOverrides: 0, toCategoryId: 'cat_rent');
      expect(r.overrides, 1);
    });

    test('a third exception means the rule does not fit', () {
      // Told three times that the automatic answer is wrong, the app stops
      // giving one rather than insisting.
      final r = afterMove(
          isRule: false,
          previousOverrides: CounterpartyEntry.overrideLimit - 1,
          toCategoryId: 'cat_rent');
      expect(r.disposition, Disposition.ask);
      expect(r.categoryId, isNull);
    });
  });
}
