import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/api/json_case.dart';

void main() {
  test('snakeKeys converts camelCase keys recursively and leaves snake_case alone', () {
    final out = snakeKeys({
      'fullName': 'A',
      'employee_id': 'x',
      'orgInfo': {'logoUrl': 'u', 'listItems': [{'someKey': 1}]},
    });
    expect(out, {
      'full_name': 'A',
      'employee_id': 'x',
      'org_info': {'logo_url': 'u', 'list_items': [{'some_key': 1}]},
    });
  });

  test('asMapList accepts bare list, {items}, {data} and null', () {
    final row = {'a': 1};
    expect(asMapList([row]), [row]);
    expect(asMapList({'items': [row], 'total': 1}), [row]);
    expect(asMapList({'data': [row]}), [row]);
    expect(asMapList(null), isEmpty);
  });

  test('numeric helpers handle Decimal strings', () {
    expect(asNum('2.50'), 2.5);
    expect(asDouble('7'), 7.0);
    expect(asInt('3.9'), 3);
    expect(asDouble(null, 1.5), 1.5);
    expect(asDouble('abc'), 0);
  });

  test('date helpers', () {
    expect(asDateOnly('2026-10-07T00:00:00.000Z'), '2026-10-07');
    expect(asDateOnly('2026-10-07'), '2026-10-07');
    expect(asDateOnly(null), isNull);
    expect(asDate('2026-10-07T10:00:00Z')?.toUtc().hour, 10);
  });
}
