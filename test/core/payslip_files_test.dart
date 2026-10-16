import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/payslip_files.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('payslip_files_test_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  PayslipFiles files({
    Duration lifetime = const Duration(minutes: 10),
    Duration stale = const Duration(minutes: 15),
    DateTime Function()? now,
  }) => PayslipFiles(
    baseDirectory: () async => base,
    openedFileLifetime: lifetime,
    staleAfter: stale,
    now: now,
  );

  group('safePayslipFileName', () {
    test('keeps a base name of safe characters and always ends in .pdf', () {
      expect(
        safePayslipFileName('Payslip_GC-001_September_2026.pdf'),
        'Payslip_GC-001_September_2026.pdf',
      );
      expect(safePayslipFileName('../a:b*c.pdf'), 'a_b_c.pdf');
      expect(safePayslipFileName(r'..\..\x'), 'x.pdf');
      expect(safePayslipFileName(''), 'Payslip.pdf');
      expect(safePayslipFileName('.hidden'), 'hidden.pdf');
      expect(safePayslipFileName('${'a' * 200}.pdf').length, 84);
    });
  });

  group('save', () {
    test(
      'writes the bytes under <base>/payslips with a sanitized name, creating the folder',
      () async {
        final path = await files().save([37, 80, 68, 70], '../evil name.pdf');
        expect(
          path.startsWith('${base.path}${Platform.pathSeparator}payslips'),
          isTrue,
        );
        expect(path.endsWith('.pdf'), isTrue);
        expect(path.contains('..'), isFalse);
        expect(await File(path).readAsBytes(), [37, 80, 68, 70]);
        expect(
          Directory(path).parent.path,
          '${base.path}${Platform.pathSeparator}payslips',
        );
      },
    );
  });

  group('scheduleDelete', () {
    test(
      'the file is NOT deleted straight away: it is still there while the delay runs, and a timer is pending',
      () async {
        final f = files(lifetime: const Duration(minutes: 5));
        final path = await f.save([1], 'a.pdf');
        f.scheduleDelete(path);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(await File(path).exists(), isTrue);
        expect(f.pendingDeletes, 1);
        await f.deleteAll();
        expect(f.pendingDeletes, 0);
      },
    );

    test('the file is deleted once the delay has passed', () async {
      final f = files(lifetime: const Duration(milliseconds: 30));
      final path = await f.save([1], 'a.pdf');
      f.scheduleDelete(path);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await File(path).exists(), isFalse);
      expect(f.pendingDeletes, 0);
    });

    test('scheduling the same file again replaces the earlier timer', () async {
      final f = files(lifetime: const Duration(minutes: 5));
      final path = await f.save([1], 'a.pdf');
      f.scheduleDelete(path);
      f.scheduleDelete(path);
      expect(f.pendingDeletes, 1);
      await f.deleteAll();
    });

    test('a file that is already gone does not make the timer fail', () async {
      final f = files(lifetime: const Duration(milliseconds: 20));
      final path = await f.save([1], 'a.pdf');
      f.scheduleDelete(path);
      await File(path).delete();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(f.pendingDeletes, 0);
    });
  });

  group('deleteStale', () {
    test('removes files older than the limit and keeps recent ones', () async {
      final now = DateTime(2026, 10, 9, 12, 0);
      final f = files(stale: const Duration(minutes: 15), now: () => now);
      final old = await f.save([1], 'old.pdf');
      final recent = await f.save([2], 'recent.pdf');
      await File(old).setLastModified(now.subtract(const Duration(hours: 2)));
      await File(
        recent,
      ).setLastModified(now.subtract(const Duration(minutes: 2)));

      expect(await f.deleteStale(), 1);
      expect(await File(old).exists(), isFalse);
      expect(await File(recent).exists(), isTrue);
    });

    test(
      'does nothing, and does not throw, when the folder does not exist',
      () async {
        expect(await files().deleteStale(), 0);
      },
    );

    test('leaves sub-folders alone', () async {
      final f = files(
        stale: Duration.zero,
        now: () => DateTime.now().add(const Duration(days: 1)),
      );
      final path = await f.save([1], 'a.pdf');
      final sub = Directory(
        '${File(path).parent.path}${Platform.pathSeparator}keep',
      )..createSync();
      expect(await f.deleteStale(), 1);
      expect(await sub.exists(), isTrue);
    });
  });

  group('deleteAll', () {
    test(
      'removes every payslip file regardless of age and cancels pending timers',
      () async {
        final f = files(lifetime: const Duration(minutes: 5));
        final a = await f.save([1], 'a.pdf');
        final b = await f.save([2], 'b.pdf');
        f.scheduleDelete(a);
        expect(await f.deleteAll(), 2);
        expect(await File(a).exists(), isFalse);
        expect(await File(b).exists(), isFalse);
        expect(f.pendingDeletes, 0);
      },
    );

    test('does not throw when there is nothing to delete', () async {
      expect(await files().deleteAll(), 0);
    });

    test('never touches files outside the payslips folder', () async {
      final f = files();
      await f.save([1], 'a.pdf');
      final other = File('${base.path}${Platform.pathSeparator}other.txt')
        ..writeAsStringSync('x');
      await f.deleteAll();
      expect(await other.exists(), isTrue);
    });
  });

  group('Android cleartext traffic (manifest files)', () {
    String read(String p) => File(p).readAsStringSync();

    test(
      'the main manifest, used by release builds, does not allow cleartext traffic',
      () {
        expect(
          read(
            'android/app/src/main/AndroidManifest.xml',
          ).contains('usesCleartextTraffic'),
          isFalse,
        );
      },
    );

    test('the profile manifest does not allow it either', () {
      expect(
        read(
          'android/app/src/profile/AndroidManifest.xml',
        ).contains('usesCleartextTraffic'),
        isFalse,
      );
    });

    test(
      'only the debug manifest allows it, and no network security config re-enables it',
      () {
        expect(
          read(
            'android/app/src/debug/AndroidManifest.xml',
          ).contains('android:usesCleartextTraffic="true"'),
          isTrue,
        );
        expect(
          read(
            'android/app/src/main/AndroidManifest.xml',
          ).contains('networkSecurityConfig'),
          isFalse,
        );
      },
    );

    test(
      'the default API address is HTTPS and no source file uses a plain http:// API address',
      () {
        final client = read('lib/core/api/api_client.dart');
        expect(
          client.contains("defaultValue: 'https://api.hrtoffy.in'"),
          isTrue,
        );
      },
    );
  });
}
