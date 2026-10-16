import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms_app/models/work_site.dart';
import 'package:hrms_app/repositories/attendance_repository.dart';
import 'package:hrms_app/services/attendance_service.dart';
import 'package:hrms_app/services/geo_tracker_service.dart';
import 'package:http/http.dart' as http;

import '../helpers/test_auth.dart';

const _statusPath =
    '/organizations/$testOrgId/employees/$testEmployeeId/punch-status';
const _punchPath = '/organizations/$testOrgId/attendance/punch';

final _employee = <String, dynamic>{
  'id': testEmployeeId,
  'organization_id': testOrgId,
  'branch_id': 'b1',
  'entity_id': 'e1',
};

Position _pos({
  double lat = 12.9716,
  double lng = 77.5946,
  double accuracy = 8.5,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 8),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Map<String, dynamic> _status({Map<String, dynamic>? attendance}) => {
  'latestPunch': null,
  'attendance': attendance,
  'punchLogs': <dynamic>[],
  'today': '2026-10-08',
};

Map<String, dynamic> _punchOk({String type = 'punch_in'}) => {
  'success': true,
  'punch_log_id': 'log-1',
  'attendance_id': 'att-1',
  'punch_time': '2026-10-08T04:30:00.000Z',
  'punch_type': type,
  'in_fence': true,
  'distance_m': 0,
  'site_id': null,
  'is_suspicious': false,
  'suspicion_reasons': <String>[],
};

class _Run {
  final errors = <String>[];
  final loading = <bool>[];
  int successes = 0;
  int confirms = 0;
}

Future<TestSession> _setup(
  Future<http.Response> Function(http.Request req) handler, {
  Position? position,
}) async {
  final s = await signedIn(handler);
  AttendanceService.debugOverride(
    repository: AttendanceRepository(auth: s.auth),
    location: () async => position ?? _pos(),
    address: (lat, lng) async => 'Test address',
  );
  return s;
}

Future<_Run> _punchIn(
  Map<String, dynamic> employee, {
  String workType = 'on-duty',
  bool geoEnabled = false,
  String geoMode = 'strict',
  bool geoTrackOnly = false,
  List<WorkSite> sites = const [],
  bool confirmOutside = true,
}) async {
  final run = _Run();
  await AttendanceService.punchIn(
    employee: employee,
    selectedWorkType: workType,
    geoEnabled: geoEnabled,
    geoMode: geoMode,
    geoTrackOnly: geoTrackOnly,
    workSites: sites,
    onShowGeoConfirm: (n, d, a) async {
      run.confirms++;
      return confirmOutside;
    },
    onSuccess: () async => run.successes++,
    onError: run.errors.add,
    onLoading: run.loading.add,
  );
  return run;
}

Future<_Run> _punchOut(
  Map<String, dynamic> employee, {
  String workType = 'on-duty',
}) async {
  final run = _Run();
  await AttendanceService.punchOut(
    employee: employee,
    selectedWorkType: workType,
    geoEnabled: false,
    geoMode: 'strict',
    geoTrackOnly: false,
    workSites: const [],
    onShowGeoConfirm: (n, d, a) async => true,
    onSuccess: () => run.successes++,
    onError: run.errors.add,
    onLoading: run.loading.add,
  );
  return run;
}

List<Recorded> _punches(TestSession s) =>
    s.apiCalls.where((r) => r.path == _punchPath).toList();

void main() {
  tearDown(() {
    AttendanceService.debugReset();
    GeoTrackerService.trackWriter = null;
    GeoTrackerService.isTracking = false;
  });

  group('Punch In', () {
    test(
      'sends the AWS request, no site values when none was evaluated, and calls onSuccess exactly once',
      () async {
        final s = await _setup((req) async {
          if (req.url.path == _statusPath) return ok(_status());
          if (req.url.path == _punchPath) return ok(_punchOk());
          return jsonResponse({'success': false}, 404);
        });
        final run = await _punchIn(_employee);

        expect(run.errors, isEmpty);
        expect(run.successes, 1, reason: 'onSuccess must run exactly once');
        expect(run.loading, [true, false]);

        final call = _punches(s).single;
        expect(call.headers['Authorization'], 'Bearer acc');
        expect(call.json, {
          'employeeId': testEmployeeId,
          'punchType': 'punch_in',
          'workType': 'on-duty',
          'punchSource': 'mobile',
          'latitude': 12.9716,
          'longitude': 77.5946,
          'accuracy': 8.5,
          'address': 'Test address',
          'siteId': null,
          'inFence': null,
          'distanceM': null,
          'clientSignals': null,
        });
      },
    );

    test(
      'with an evaluated work site the site, fence result and distance are sent',
      () async {
        final site = WorkSite(
          id: 'site-1',
          name: 'HQ',
          latitude: 12.9716,
          longitude: 77.5946,
          radiusMeters: 100,
        );
        final s = await _setup((req) async {
          if (req.url.path == _statusPath) return ok(_status());
          return ok(_punchOk());
        });
        final run = await _punchIn(
          _employee,
          geoEnabled: true,
          geoTrackOnly: true,
          sites: [site],
        );
        expect(run.errors, isEmpty);
        final body = _punches(s).single.json as Map;
        expect(body['siteId'], 'site-1');
        expect(body['inFence'], true);
        expect(body['distanceM'], isA<num>());
      },
    );

    test(
      'strict geofence outside the radius blocks the punch with the same message and sends nothing',
      () async {
        final far = WorkSite(
          id: 'site-1',
          name: 'HQ',
          latitude: 13.5,
          longitude: 78.5,
          radiusMeters: 100,
        );
        final s = await _setup((req) async => ok(_status()));
        final run = await _punchIn(
          _employee,
          geoEnabled: true,
          geoMode: 'strict',
          sites: [far],
        );
        expect(
          run.errors.single,
          startsWith('You are outside allowed office radius'),
        );
        expect(run.successes, 0);
        expect(_punches(s), isEmpty);
        expect(run.loading.last, false);
      },
    );

    test(
      'lenient geofence asks for confirmation; declining sends nothing, confirming sends in_fence=false',
      () async {
        final far = WorkSite(
          id: 'site-1',
          name: 'HQ',
          latitude: 13.5,
          longitude: 78.5,
          radiusMeters: 100,
        );
        final s1 = await _setup((req) async => ok(_status()));
        final declined = await _punchIn(
          _employee,
          geoEnabled: true,
          geoMode: 'lenient',
          sites: [far],
          confirmOutside: false,
        );
        expect(declined.confirms, 1);
        expect(declined.successes, 0);
        expect(_punches(s1), isEmpty);

        final s2 = await _setup((req) async {
          if (req.url.path == _statusPath) return ok(_status());
          return ok(_punchOk());
        });
        final confirmed = await _punchIn(
          _employee,
          geoEnabled: true,
          geoMode: 'lenient',
          sites: [far],
        );
        expect(confirmed.successes, 1);
        expect((_punches(s2).single.json as Map)['inFence'], false);
      },
    );

    test(
      'success:false in a 200 is a failure: onError with the reason, no onSuccess',
      () async {
        await _setup((req) async {
          if (req.url.path == _statusPath) return ok(_status());
          return ok({'success': false, 'error': 'Already punched in'});
        });
        final run = await _punchIn(_employee);
        expect(run.errors.single, 'Already punched in');
        expect(run.successes, 0);
        expect(run.loading, [true, false]);
      },
    );

    test(
      'a server error shows a safe message, never the database text',
      () async {
        await _setup((req) async {
          if (req.url.path == _statusPath) return ok(_status());
          return jsonResponse({
            'success': false,
            'error': {
              'code': 'INTERNAL_SERVER_ERROR',
              'message':
                  'permission denied for function get_current_employee_ids',
            },
          }, 500);
        });
        final run = await _punchIn(_employee);
        expect(run.successes, 0);
        expect(run.errors.single, isNot(contains('permission denied')));
        expect(run.errors.single, isNot(contains('get_current_employee_ids')));
        expect(run.errors.single, contains('try again'));
      },
    );

    test('location failures keep their message', () async {
      final s = await signedIn((req) async => ok(_status()));
      AttendanceService.debugOverride(
        repository: AttendanceRepository(auth: s.auth),
        location: () async => throw Exception('Location services disabled'),
        address: (a, b) async => 'x',
      );
      final run = await _punchIn(_employee);
      expect(run.errors.single, contains('Location services disabled'));
      expect(_punches(s), isEmpty);
    });

    test('invalid employee data is rejected before any call', () async {
      final s = await _setup((req) async => ok(_status()));
      final run = await _punchIn({'id': null, 'organization_id': testOrgId});
      expect(run.errors.single, contains('Invalid employee data'));
      expect(s.apiCalls, isEmpty);
    });
  });

  group('Punch Out', () {
    test(
      'sends punch_out with the work type and calls onSuccess exactly once',
      () async {
        final s = await _setup((req) async {
          if (req.url.path == _statusPath)
            return ok(
              _status(attendance: {'id': 'att-1', 'work_type': 'on-duty'}),
            );
          return ok(_punchOk(type: 'punch_out'));
        });
        final run = await _punchOut(_employee);
        expect(run.errors, isEmpty);
        expect(run.successes, 1);
        final body = _punches(s).single.json as Map;
        expect(body['punchType'], 'punch_out');
        expect(body['workType'], 'on-duty');
        expect(body['punchSource'], 'mobile');
        expect(body['siteId'], isNull);
        expect(body['inFence'], isNull);
        expect(body['distanceM'], isNull);
      },
    );

    test(
      'work-type mismatch is refused using the server\'s attendance row, nothing is sent',
      () async {
        final s = await _setup(
          (req) async =>
              ok(_status(attendance: {'id': 'att-1', 'work_type': 'on-site'})),
        );
        final run = await _punchOut(_employee, workType: 'on-duty');
        expect(
          run.errors.single,
          "Work type mismatch. Please select 'on-site' to punch out.",
        );
        expect(run.successes, 0);
        expect(_punches(s), isEmpty);
      },
    );
  });

  group('Tracking', () {
    test(
      'no AWS tracking endpoint: tracking stays disabled after a punch-in and nothing is written anywhere',
      () async {
        final s = await _setup((req) async {
          if (req.url.path == _statusPath) return ok(_status());
          return ok(_punchOk());
        });
        expect(GeoTrackerService.isEnabled, isFalse);
        final run = await _punchIn(_employee);
        expect(run.successes, 1);
        expect(GeoTrackerService.isTracking, isFalse);
        expect(GeoTrackerService.timer, isNull);
        // the only API calls are the status read and the punch: no tracking write
        expect(s.apiCalls.map((r) => '${r.method} ${r.path}'), [
          'GET $_statusPath',
          'POST $_punchPath',
        ]);
      },
    );
  });

  group('Reads through the API', () {
    test(
      'getTodayPunchLogs: no attendance today -> empty (no further call)',
      () async {
        final s = await _setup((req) async => ok(_status()));
        expect(
          await AttendanceService.getTodayPunchLogs(employeeId: testEmployeeId),
          isEmpty,
        );
        expect(s.apiCalls, hasLength(1));
      },
    );

    test(
      'getTodayPunchLogs: full rows from day-punch-logs for the server\'s day; falls back to the status logs',
      () async {
        var failDetail = false;
        await _setup((req) async {
          if (req.url.path == _statusPath) {
            return ok({
              'latestPunch': null,
              'attendance': {'id': 'att-1', 'work_type': 'on-duty'},
              'punchLogs': [
                {
                  'punch_time': 't',
                  'punch_type': 'punch_in',
                  'work_type': 'on-duty',
                  'punch_source': 'mobile',
                },
              ],
              'today': '2026-10-08',
            });
          }
          if (failDetail)
            return jsonResponse({
              'success': false,
              'error': {'code': 'X', 'message': 'boom'},
            }, 500);
          expect(req.url.queryParameters, {
            'date': '2026-10-08',
            'attendanceId': 'att-1',
          });
          return ok([
            {
              'id': 'l1',
              'punch_type': 'punch_in',
              'punch_lat': '12.97',
              'punch_lng': '77.59',
              'punch_address': 'A',
            },
          ]);
        });
        final full = await AttendanceService.getTodayPunchLogs(
          employeeId: testEmployeeId,
        );
        expect(full.single['punch_lat'], 12.97);
        expect(full.single['punch_address'], 'A');

        failDetail = true;
        final basic = await AttendanceService.getTodayPunchLogs(
          employeeId: testEmployeeId,
        );
        expect(basic.single['punch_type'], 'punch_in');
      },
    );

    test('getPunchLogs returns [] instead of throwing', () async {
      await _setup(
        (req) async => jsonResponse({
          'success': false,
          'error': {'code': 'X', 'message': 'boom'},
        }, 500),
      );
      expect(
        await AttendanceService.getPunchLogs(
          employeeId: testEmployeeId,
          date: '2026-10-08',
        ),
        isEmpty,
      );
    });

    test(
      'getGeoFencePolicy and isGeoTrackOnly work on the adapted keys',
      () async {
        await _setup(
          (req) async => ok({
            'enabled': true,
            'defaultRadiusMeters': 100,
            'mode': 'lenient',
            'onlyForOffice': true,
            'trackAllPunches': true,
          }),
        );
        final p = (await AttendanceService.getGeoFencePolicy(testOrgId))!;
        expect(p['geo_fencing_enabled'], true);
        expect(p['geo_fencing_mode'], 'lenient');
        expect(
          AttendanceService.isGeoTrackOnly(
            policy: p,
            selectedWorkType: 'work-from-home',
          ),
          true,
        );
        expect(
          AttendanceService.isGeoTrackOnly(
            policy: p,
            selectedWorkType: 'on-duty',
          ),
          false,
        );
      },
    );

    group('getResolvedWorkSites priority', () {
      Map<String, dynamic> site(
        String id, {
        String? branch,
        String? entity,
        bool active = true,
      }) => {
        'id': id,
        'name': id,
        'latitude': 1.0,
        'longitude': 2.0,
        'radiusMeters': 50,
        'isActive': active,
        'branchId': branch,
        'entityId': entity,
      };

      Future<List<String>> resolve(
        List<Map<String, dynamic>> sites,
        List<String> assignedIds,
      ) async {
        await _setup((req) async {
          if (req.url.path.endsWith('/work-site-assignments')) {
            return ok([
              for (final id in assignedIds)
                {'id': 'a-$id', 'workSiteId': id, 'employeeId': testEmployeeId},
            ]);
          }
          return ok(sites);
        });
        return (await AttendanceService.getResolvedWorkSites(
          _employee,
        )).map((w) => w.id).toList();
      }

      test('assigned sites win', () async {
        expect(await resolve([site('a'), site('b', branch: 'b1')], ['a']), [
          'a',
        ]);
      });
      test('then the branch', () async {
        expect(
          await resolve([
            site('a'),
            site('b', branch: 'b1'),
            site('c', entity: 'e1'),
          ], []),
          ['b'],
        );
      });
      test('then the entity', () async {
        expect(await resolve([site('a'), site('c', entity: 'e1')], []), ['c']);
      });
      test('then the organization\'s active sites', () async {
        expect(await resolve([site('a'), site('z', active: false)], []), ['a']);
      });
      test('values are read from the camelCase API (radiusMeters)', () async {
        await _setup((req) async {
          if (req.url.path.endsWith('/work-site-assignments')) return ok([]);
          return ok([site('a')]);
        });
        final w = (await AttendanceService.getResolvedWorkSites(
          _employee,
        )).single;
        expect(w.radiusMeters, 50);
      });
      test('an API failure gives no sites, not an exception', () async {
        await _setup(
          (req) async => jsonResponse({
            'success': false,
            'error': {'code': 'X', 'message': 'no'},
          }, 403),
        );
        expect(
          await AttendanceService.getResolvedWorkSites(_employee),
          isEmpty,
        );
      });
    });
  });
}
