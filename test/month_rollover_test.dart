import 'package:flutter_test/flutter_test.dart';

/// The entry decision as `MigrationGate.initialRoute` writes it, so the
/// month-turn behaviour is testable without Firestore.
String route({
  required bool introSeen,
  required bool hasCategories,
  required bool budgetsConfirmedThisMonth,
  required bool needsMigration,
  required bool dismissed,
  required int candidates,
}) {
  if (!hasCategories) return introSeen ? '/trackItems' : '/intro';
  if (!budgetsConfirmedThisMonth) return '/trackItems';
  if (needsMigration) return '/preparing';
  if (dismissed) return '/deeplink/summary';
  if (candidates > 0) return '/preparing';
  return '/deeplink/summary';
}

void main() {
  test('a new month asks the user to look at their budgets', () {
    // Carrying August's plan into September silently means nobody ever
    // revisits it, and a budget nobody revisits stops being a plan.
    expect(
        route(
            introSeen: true,
            hasCategories: true,
            budgetsConfirmedThisMonth: false,
            needsMigration: false,
            dismissed: true,
            candidates: 0),
        '/trackItems');
  });

  test('it is asked once, not on every launch', () {
    expect(
        route(
            introSeen: true,
            hasCategories: true,
            budgetsConfirmedThisMonth: true,
            needsMigration: false,
            dismissed: true,
            candidates: 0),
        '/deeplink/summary');
  });

  test('a brand new user still gets the explainer first', () {
    expect(
        route(
            introSeen: false,
            hasCategories: false,
            budgetsConfirmedThisMonth: false,
            needsMigration: true,
            dismissed: false,
            candidates: 0),
        '/intro');
  });

  test('the month check does not override a pending migration for a new user',
      () {
    // Budgets first either way: a transaction is filed by matching it to a
    // category that already exists.
    expect(
        route(
            introSeen: true,
            hasCategories: false,
            budgetsConfirmedThisMonth: false,
            needsMigration: true,
            dismissed: false,
            candidates: 0),
        '/trackItems');
  });
}
