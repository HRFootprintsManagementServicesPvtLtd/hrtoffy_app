import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/providers/role_provider.dart';
import 'package:hrms_app/repositories/disciplinary_repository.dart';
import 'package:hrms_app/screens/manager/manager_disciplinary_screen.dart';
import 'package:hrms_app/screens/manager/widgets/manager_state_views.dart';
import 'package:provider/provider.dart';

import '../helpers/test_auth.dart';

const _base = '/organizations/$testOrgId/disciplinary/cases';

Widget _screen(TestSession s) => ChangeNotifierProvider<RoleProvider>(
  create: (_) => RoleProvider(),
  child: MaterialApp(
    home: ManagerDisciplinaryScreen(
      userEmail: 'm@x.com',
      userData: const {
        'id': 'e1',
        'organization_id': testOrgId,
        'emp_role': 'manager',
      },
      fetchHrmsContext: () async => {},
      disciplinaryRepository: DisciplinaryRepository(auth: s.auth),
    ),
  ),
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final _cases = [
  {
    'id': 'c1',
    'case_number': 'DC-100',
    'employee_id': 'e1',
    'category': 'Attendance',
    'severity': 'minor',
    'status': 'issued',
    'incident_date': '2026-09-01T00:00:00.000Z',
    'incident_description': 'Late three times',
  },
  {
    'id': 'c2',
    'case_number': 'DC-200',
    'employee_id': 'e2',
    'category': 'Misconduct',
    'severity': 'major',
    'status': 'closed',
    'incident_date': '2026-08-01T00:00:00.000Z',
    'incident_description': 'Argument',
  },
];

Future<TestSession> _ok() => signedIn((req) async {
  switch (req.url.path) {
    case _base:
      return ok({'items': _cases, 'total': 2});
    case '/organizations/$testOrgId/employees/summaries':
      return ok([
        {'id': 'e1', 'fullName': 'Asha Rao'},
        {'id': 'e2', 'fullName': 'Ravi Kumar'},
      ]);
    case '$_base/c1':
      return ok(_cases[0]);
    case '$_base/c1/actions':
      return ok([
        {
          'action_type': 'written_warning',
          'action_date': '2026-09-05',
          'remarks': 'Keep time',
        },
      ]);
    case '$_base/c1/responses':
      return ok([
        {
          'response_text': 'Traffic was bad',
          'submitted_at': '2026-09-06T10:00:00Z',
        },
      ]);
  }
  return jsonResponse({'success': false}, 404);
});

void main() {
  testWidgets('lists cases with names, status and filters Open/Closed', (
    t,
  ) async {
    _tall(t);
    final s = await _ok();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text('DC-100'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Issued'), findsOneWidget);
    expect(find.text('DC-200'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, 'Closed'));
    await t.pump();
    expect(find.text('DC-100'), findsNothing);
    expect(find.text('DC-200'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, 'Open'));
    await t.pump();
    expect(find.text('DC-100'), findsOneWidget);
    expect(find.text('DC-200'), findsNothing);
  });

  testWidgets('detail shows fields, actions and responses; only GETs', (
    t,
  ) async {
    _tall(t);
    final s = await _ok();
    await t.pumpWidget(_screen(s));
    await _settle(t);
    await t.tap(find.text('DC-100'));
    await _settle(t);
    expect(find.text('Late three times'), findsOneWidget);
    expect(find.text('Written Warning'), findsOneWidget);
    expect(find.text('Keep time'), findsOneWidget);
    expect(find.text('Traffic was bad'), findsOneWidget);
    expect(s.apiCalls.every((r) => r.method == 'GET'), isTrue);
    expect(s.apiCalls.any((r) => r.path.endsWith('/actions')), isTrue);
  });

  testWidgets('empty list says so', (t) async {
    final s = await signedIn((req) async => ok({'items': [], 'total': 0}));
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text('No disciplinary cases'), findsOneWidget);
  });

  testWidgets('403 shows the friendly role message', (t) async {
    final s = await signedIn(
      (req) async => jsonResponse({
        'success': false,
        'message': 'secret server text',
      }, 403),
    );
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text(kDisciplinaryUnavailableMessage), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('an error shows a fixed message and Retry reloads', (t) async {
    _tall(t);
    var fail = true;
    final s = await signedIn((req) async {
      if (req.url.path == _base) {
        return fail
            ? jsonResponse({'success': false, 'message': 'db exploded'}, 500)
            : ok({'items': _cases, 'total': 2});
      }
      return ok([]);
    });
    await t.pumpWidget(_screen(s));
    await _settle(t);
    expect(find.text(kManagerLoadFailedMessage), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    fail = false;
    await t.tap(find.text('Retry'));
    await _settle(t);
    expect(find.text('DC-100'), findsOneWidget);
    expect(s.apiCalls.every((r) => r.method == 'GET'), isTrue);
  });
}
