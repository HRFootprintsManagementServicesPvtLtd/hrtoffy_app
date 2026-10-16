import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression check: the Flutter app has no Supabase SDK. This file itself names the banned strings, so it
/// is excluded from the scan. The server-side `supabase/` directory is not part of the Flutter app and is
/// deliberately not scanned.
void main() {
  Iterable<File> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where(
        (f) => !f.path
            .replaceAll(r'\', '/')
            .endsWith('test/core/no_supabase_sdk_test.dart'),
      );

  test('no Dart file in lib/ or test/ imports or calls the Supabase SDK', () {
    final offenders = <String>[];
    for (final f in [...dartFiles('lib'), ...dartFiles('test')]) {
      final src = f.readAsStringSync();
      for (final banned in [
        'package:supabase',
        'SupabaseClient',
        'FlutterAuthClientOptions',
        'AuthChangeEvent',
        'PostgrestException',
        'FunctionException',
      ]) {
        if (src.contains(banned)) offenders.add('${f.path}: $banned');
      }
      if (RegExp(r'Supabase\.[a-z]').hasMatch(src))
        offenders.add('${f.path}: Supabase.<member>');
    }
    expect(offenders, isEmpty);
  });

  test(
    'the Supabase package is not a dependency, and the retired flag and helpers are gone',
    () {
      expect(
        File('pubspec.yaml').readAsStringSync().contains('supabase_flutter'),
        isFalse,
      );
      expect(
        File('pubspec.lock').readAsStringSync().contains('supabase'),
        isFalse,
      );
      expect(File('lib/core/feature_flags.dart').existsSync(), isFalse);
      for (final f in dartFiles('lib')) {
        final src = f.readAsStringSync();
        expect(src.contains('USE_AWS_AUTH'), isFalse, reason: f.path);
        expect(
          src.contains('initializeSupabaseForLegacyAuth'),
          isFalse,
          reason: f.path,
        );
        expect(src.contains('supabaseWriter'), isFalse, reason: f.path);
      }
    },
  );

  test('no hardcoded Supabase project URL remains in the Flutter app', () {
    for (final f in dartFiles('lib')) {
      expect(
        f.readAsStringSync().contains('.supabase.co'),
        isFalse,
        reason: f.path,
      );
    }
  });
}
