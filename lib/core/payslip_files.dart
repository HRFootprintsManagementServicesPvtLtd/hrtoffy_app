import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A file name that is safe to create: base name only, letters, digits, `.`, `_`, `-`, no leading dot, always `.pdf`.
String safePayslipFileName(String name) {
  var base = name
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceFirst(RegExp(r'^\.+'), '');
  if (base.toLowerCase().endsWith('.pdf')) {
    base = base.substring(0, base.length - 4);
  }
  if (base.length > 80) base = base.substring(0, 80);
  return '${base.isEmpty ? 'Payslip' : base}.pdf';
}

/// Where downloaded payslip PDFs live, and when they are removed.
///
/// Files are written, UNENCRYPTED, to `<app temporary directory>/payslips` (private to the app). Removal is best effort:
///  * after a payslip is opened it is deleted once [openedFileLifetime] has passed, by a timer that only runs while the app
///    process is alive;
///  * files older than [staleAfter] are deleted when the app starts;
///  * every payslip file is deleted when the user signs out or the session ends.
///
/// A file is NOT deleted right after it is opened: `OpenFilex.open` only starts the viewer (an Android intent with a
/// content URI, an iOS document preview) and returns at once, with no signal for when the viewer has read or closed
/// the file. Deleting immediately could leave the viewer with an empty or missing document. Limitations: if the app is
/// killed before the timer fires, the file stays until the next start; the operating system may also clear the cache
/// earlier; a viewer that still has a file open when it is deleted at sign-out may lose it; there is no secure wipe.
class PayslipFiles {
  PayslipFiles({
    Future<Directory> Function()? baseDirectory,
    this.openedFileLifetime = const Duration(minutes: 10),
    this.staleAfter = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _baseDirectory = baseDirectory ?? getTemporaryDirectory,
       _now = now ?? DateTime.now;

  static final PayslipFiles instance = PayslipFiles();

  final Future<Directory> Function() _baseDirectory;
  final DateTime Function() _now;

  /// How long an opened payslip is left for the viewer before the app deletes it.
  final Duration openedFileLifetime;

  /// Files older than this are removed by [deleteStale].
  final Duration staleAfter;

  final Map<String, Timer> _timers = {};

  Future<Directory> folder() async {
    final base = await _baseDirectory();
    return Directory('${base.path}${Platform.pathSeparator}payslips');
  }

  /// Writes [bytes] under a sanitized version of [fileName] and returns the path.
  Future<String> save(List<int> bytes, String fileName) async {
    final dir = await folder();
    await dir.create(recursive: true);
    final path =
        '${dir.path}${Platform.pathSeparator}${safePayslipFileName(fileName)}';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Deletes [path] after [openedFileLifetime] (replacing any earlier timer for the same file).
  void scheduleDelete(String path) {
    _timers.remove(path)?.cancel();
    _timers[path] = Timer(openedFileLifetime, () {
      _timers.remove(path);
      unawaited(_deleteFile(path));
    });
  }

  /// Number of pending delayed deletions (tests).
  @visibleForTesting
  int get pendingDeletes => _timers.length;

  /// Deletes payslip files last modified more than [staleAfter] ago. Never throws; returns how many were removed.
  Future<int> deleteStale() async {
    try {
      final dir = await folder();
      if (!await dir.exists()) return 0;
      final limit = _now().subtract(staleAfter);
      var removed = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          if ((await entity.lastModified()).isBefore(limit)) {
            await entity.delete();
            removed++;
          }
        } catch (_) {
          // a file that cannot be read or removed is left for the next sweep
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes every payslip file and cancels pending timers (sign-out, session end). Never throws; returns how many were removed.
  Future<int> deleteAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    try {
      final dir = await folder();
      if (!await dir.exists()) return 0;
      var removed = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          await entity.delete();
          removed++;
        } catch (_) {}
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
