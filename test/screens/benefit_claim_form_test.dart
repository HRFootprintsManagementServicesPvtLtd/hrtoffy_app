import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/screens/benefits_screen.dart';

Future<List<Map<String, String>>> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final submitted = <Map<String, String>>[];
  await tester.pumpWidget(MaterialApp(
    home: SubmitClaimPage(
      benefits: const [
        {'id': 'b1', 'benefit_name': 'Meal Vouchers'},
      ],
      gradeLimitData: null,
      claimedTotal: 0,
      onSubmit: ({required benefitId, required claimAmount, required description}) async {
        submitted.add({'benefitId': benefitId, 'amount': '$claimAmount', 'description': description});
        return true;
      },
    ),
  ));
  await tester.pump();
  return submitted;
}

Future<void> _fill(WidgetTester tester, String description) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Meal Vouchers').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Claim Amount (₹)'), '100');
  await tester.enterText(find.widgetWithText(TextFormField, 'Description'), description);
  await tester.pump();
  final submit = find.widgetWithText(ElevatedButton, 'Submit Claim');
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

void main() {
  // The "+" button is switched off (kBenefitClaimSubmissionEnabled) until the backend stores the payroll fields of a
  // claim; this form is only reachable then. Its rules already follow the website so enabling it needs no change here.
  testWidgets('a description shorter than 5 characters is refused before anything is sent', (tester) async {
    final submitted = await _pump(tester);
    await _fill(tester, 'abc');
    expect(find.text('Enter at least 5 characters'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('spaces do not count toward the 5 characters', (tester) async {
    final submitted = await _pump(tester);
    await _fill(tester, 'ab      ');
    expect(find.text('Enter at least 5 characters'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('an empty description says it is required', (tester) async {
    final submitted = await _pump(tester);
    await _fill(tester, '');
    expect(find.text('Description required'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('more than 1000 characters is refused', (tester) async {
    final submitted = await _pump(tester);
    await _fill(tester, 'a' * 1001);
    expect(find.text('Description is too long (max 1000 characters)'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('a valid description is submitted with the chosen benefit and amount', (tester) async {
    final submitted = await _pump(tester);
    await _fill(tester, 'Lunch for client visit');
    expect(submitted, hasLength(1));
    expect(submitted.single['benefitId'], 'b1');
    expect(submitted.single['amount'], '100.0');
    expect(submitted.single['description'], 'Lunch for client visit');
  });
}
