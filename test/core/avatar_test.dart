import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/avatar.dart';

void main() {
  group('cleanAvatarUrl', () {
    test('no photo: null, empty and blank values', () {
      expect(cleanAvatarUrl(null), isNull);
      expect(cleanAvatarUrl(''), isNull, reason: 'a removed photo can come back as an empty string');
      expect(cleanAvatarUrl('   '), isNull);
    });

    test('anything that is not an http(s) address is not a usable photo', () {
      expect(cleanAvatarUrl('avatars/x.jpg'), isNull);
      expect(cleanAvatarUrl('javascript:alert(1)'), isNull);
      expect(cleanAvatarUrl('file:///x.jpg'), isNull);
    });

    test('a real address is kept (trimmed)', () {
      expect(cleanAvatarUrl('https://api.hrtoffy.in/storage/v1/object/public/avatars/a.jpg'), 'https://api.hrtoffy.in/storage/v1/object/public/avatars/a.jpg');
      expect(cleanAvatarUrl('  http://x.test/a.png '), 'http://x.test/a.png');
    });
  });
}
