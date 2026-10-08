import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/polling.dart';

void main() {
  test('runs the task on every tick until stopped', () async {
    var runs = 0;
    final p = Poller(const Duration(milliseconds: 20), () async => runs++);
    p.start();
    expect(p.isActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 110));
    p.stop();
    final atStop = runs;
    expect(atStop, greaterThanOrEqualTo(3));
    expect(p.isActive, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, atStop, reason: 'no ticks after stop');
  });

  test('a slow tick is not stacked on top of itself', () async {
    var concurrent = 0, maxConcurrent = 0, runs = 0;
    final p = Poller(const Duration(milliseconds: 10), () async {
      concurrent++;
      runs++;
      if (concurrent > maxConcurrent) maxConcurrent = concurrent;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      concurrent--;
    });
    p.start();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    p.stop();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(maxConcurrent, 1);
    expect(runs, lessThan(5));
  });

  test('errors in the task are swallowed and the next tick still runs; poke runs immediately', () async {
    var runs = 0;
    final p = Poller(const Duration(hours: 1), () async {
      runs++;
      throw StateError('network down');
    });
    await p.poke();
    await p.poke();
    expect(runs, 2);
  });
}
