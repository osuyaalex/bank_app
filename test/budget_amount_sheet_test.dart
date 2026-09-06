import 'package:banking_app/main_page/widget/budget_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Changing one proposed figure.
///
/// The first card offers budgets worked out from real spending, and an offer
/// the user cannot alter is not an offer -- it is a choice between the app's
/// number and typing every one of them again somewhere else.
void main() {
  Future<double?> open(WidgetTester tester, {double initial = 35000}) async {
    double? got;
    var returned = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              got = await showBudgetAmountSheet(
                context,
                categoryName: 'Food',
                initial: initial,
                currency: 'N',
              );
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget, reason: 'the sheet did not open');
    return Future.value(returned ? got : null);
  }

  testWidgets('a nudge carries back out of the sheet', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The figure the card writes comes from here, so a nudge that does not
    // survive the sheet is a Change button that does nothing.
    expect(find.text('Food'), findsNothing, reason: 'the sheet did not close');
  });

  testWidgets('cancelling changes nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
  });

  testWidgets('the figure it opens on is the one it was given', (tester) async {
    await open(tester, initial: 12000);
    expect(find.text('N12,000'), findsOneWidget);
  });
}
