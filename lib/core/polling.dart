import 'dart:async';

/// Runs [task] every [interval] while started. Replaces Supabase Realtime
/// subscriptions: the AWS backend has no push channel to the app, so screens
/// that used a realtime INSERT feed (notifications, chat) poll instead.
///
/// A tick is skipped while the previous one is still running, so a slow
/// network never stacks up requests. Errors from [task] are swallowed (the
/// next tick retries).
class Poller {
  Poller(this.interval, this.task);

  final Duration interval;
  final Future<void> Function() task;

  Timer? _timer;
  bool _running = false;

  bool get isActive => _timer?.isActive ?? false;

  void start() {
    stop();
    _timer = Timer.periodic(interval, (_) => poke());
  }

  /// Run [task] now (e.g. when the app returns to the foreground).
  Future<void> poke() async {
    if (_running) return;
    _running = true;
    try {
      await task();
    } catch (_) {
      // transient failure: the next tick retries
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
