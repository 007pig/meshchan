import 'dart:async';

/// Keeps native termination resource-free until the engine has a rendered frame
/// and AppKit has acknowledged that resources may be created. Stop opens the
/// barrier without permission; callers must save their stop intent first.
final class HostResourceBootstrap {
  HostResourceBootstrap({required this.firstFrame, required this.authorize});

  final Future<void> Function() firstFrame;
  final Future<bool> Function() authorize;
  final _ready = Completer<void>();
  bool _started = false, _stopped = false;
  bool get stopped => _stopped;

  Future<void> prepare() {
    if (!_started) {
      _started = true;
      unawaited(_prepare());
    }
    return _ready.future;
  }

  void stop() {
    _stopped = true;
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> _prepare() async {
    try {
      if (_stopped) return;
      await firstFrame();
      if (_stopped) return;
      if (!await authorize()) {
        throw StateError('Native resource bootstrap was not authorized.');
      }
      if (!_ready.isCompleted) _ready.complete();
    } catch (error, stack) {
      if (!_ready.isCompleted) _ready.completeError(error, stack);
    }
  }
}
