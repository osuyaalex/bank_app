import 'package:banking_app/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a correction should leave behind, as `correctTransaction` writes it.
///
/// Moving one payment used to change that row and nothing else: the app went
/// on believing the counterparty belonged to the old category, and the next
/// payment went straight back there. Moving a whole category, by contrast,
/// repointed everything -- so the same gesture at two scales behaved
/// differently.
({String? categoryId, Disposition disposition}) afterCorrection({
  required int previousOverrides,
  required String toCategoryId,
}) {
  final overrides = previousOverrides + 1;
  if (overrides >= CounterpartyEntry.overrideLimit) {
    return (categoryId: null, disposition: Disposition.ask);
  }
  return (categoryId: toCategoryId, disposition: Disposition.tracked);
}

void main() {
  test('a correction moves the counterparty with it', () {
    final r = afterCorrection(previousOverrides: 0, toCategoryId: 'cat_food');
    expect(r.categoryId, 'cat_food');
    expect(r.disposition, Disposition.tracked);
  });

  test('so does a second one', () {
    final r = afterCorrection(previousOverrides: 1, toCategoryId: 'cat_rent');
    expect(r.categoryId, 'cat_rent');
  });

  test('but someone who keeps changing their mind gets asked instead', () {
    // No stable answer exists for this counterparty, and guessing again would
    // just be wrong in a new way.
    final r = afterCorrection(
        previousOverrides: CounterpartyEntry.overrideLimit - 1,
        toCategoryId: 'cat_food');
    expect(r.disposition, Disposition.ask);
    expect(r.categoryId, isNull);
  });
}
