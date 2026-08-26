import 'package:flutter_test/flutter_test.dart';

/// The entry decision, written as `MigrationGate.initialRoute` writes it, so
/// the ordering is testable without Firestore.
///
/// The order is the point. Budgets have to exist before the scan runs,
/// because a transaction is filed by matching it to a category that already
/// exists -- a user reaching the batch screen with none gets nothing matched
/// and has to tag every row by hand.
String route({
  required bool introSeen,
  required bool hasCategories,
  required bool needsMigration,
  required bool dismissed,
  required int candidates,
}) {
  if (!hasCategories) return introSeen ? '/trackItems' : '/intro';
  if (needsMigration) return '/preparing';
  if (dismissed) return '/deeplink/summary';
  if (candidates > 0) return '/preparing';
  return '/deeplink/summary';
}

void main() {
  test('a brand new user is explained to before anything is asked', () {
    expect(
        route(introSeen: false, hasCategories: false, needsMigration: true,
            dismissed: false, candidates: 0),
        '/intro');
  });

  test('budgets are collected before the scan, not after', () {
    // Even with a migration pending, categories come first.
    expect(
        route(introSeen: true, hasCategories: false, needsMigration: true,
            dismissed: false, candidates: 0),
        '/trackItems');
  });

  test('the explainer is not repeated once read', () {
    expect(
        route(introSeen: true, hasCategories: false, needsMigration: false,
            dismissed: false, candidates: 0),
        '/trackItems');
  });

  test('with budgets set, the scan runs', () {
    expect(
        route(introSeen: true, hasCategories: true, needsMigration: true,
            dismissed: false, candidates: 0),
        '/preparing');
  });

  test('a dismissed batch screen is never offered again', () {
    expect(
        route(introSeen: true, hasCategories: true, needsMigration: false,
            dismissed: true, candidates: 40),
        '/deeplink/summary');
  });

  test('nothing to offer means no animation', () {
    // The scan screen is the way in to the batch screen, never shown on its
    // own account.
    expect(
        route(introSeen: true, hasCategories: true, needsMigration: false,
            dismissed: false, candidates: 0),
        '/deeplink/summary');
  });

  test('something to offer runs the scan first', () {
    expect(
        route(introSeen: true, hasCategories: true, needsMigration: false,
            dismissed: false, candidates: 20),
        '/preparing');
  });
}
