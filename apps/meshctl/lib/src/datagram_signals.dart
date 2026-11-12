import 'dart:async';

import 'session_command.dart';

/// One invocation owns the real source from before storage admission until after
/// database close. A runner owns only its real forwarding subscription; removing
/// that observer never releases the invocation's process-signal watches.
final class DatagramSignals {
  DatagramSignals(this._source);
  final Stream<CliStopRequest>? _source;
  final _events = StreamController<CliStopRequest>(
    sync: true,
    onCancel: () => Future<void>.value(),
  );
  StreamSubscription<CliStopRequest>? _subscription;
  CliStopRequest? firstStop;
  String? firstReason;
  Object? _error;
  StackTrace? _stack;
  Object? cancellationError;
  String cleanupState = 'notRequired';
  Future<void>? _finishing;
  void Function(CliStopRequest)? onIdleStop;
  void Function(Object, StackTrace)? onIdleError;
  bool get stopped => firstReason != null || _error != null;
  void outputFailed() => firstReason ??= 'output_failure';

  void start() {
    try {
      _subscription = _source?.listen(
        (request) {
          firstStop ??= request;
          firstReason ??= request.name;
          if (_events.hasListener) {
            _events.add(request);
          } else {
            onIdleStop?.call(request);
          }
        },
        onError: (Object error, StackTrace stack) {
          _error ??= error;
          _stack ??= stack;
          if (_events.hasListener) {
            _events.addError(error, stack);
          } else {
            onIdleError?.call(error, stack);
          }
        },
      );
    } catch (error, stack) {
      _error ??= error;
      _stack ??= stack;
    }
  }

  StreamSubscription<CliStopRequest>? listen(
    void Function(CliStopRequest) onStop,
    void Function(Object, StackTrace) onError,
  ) {
    if (_source == null) return null;
    final subscription = _events.stream.listen(onStop, onError: onError);
    replay(onStop, onError);
    return subscription;
  }

  /// Reconcile events latched before a runner or after its observer was removed.
  /// Final typed task/session evidence still decides the runner's precedence.
  void replay(
    void Function(CliStopRequest) onStop,
    void Function(Object, StackTrace) onError,
  ) {
    if (firstStop case final request?) onStop(request);
    if (_error case final error?) onError(error, _stack!);
  }

  Future<void> finish() => _finishing ??= _finish();
  Future<void> _finish() async {
    try {
      if (_subscription != null) {
        await _subscription!.cancel();
        cleanupState = 'succeeded';
      }
    } catch (error) {
      cancellationError = error;
      cleanupState = 'failed';
    } finally {
      // The runner already awaited its forwarding subscription's cancellation.
      // A never-listened controller has no resource and its close Future need
      // not complete; observe it without turning early cancellation into a wait.
      _events.close().ignore();
    }
  }

  Map<String, Object?>? get failure => cancellationError == null
      ? null
      : {
          'domain': 'host',
          'source': 'signalSubscription',
          'code': 'cleanup_failure',
        };
  Map<String, Object?> get fields => {'state': cleanupState, 'error': failure};

  void rethrowError() {
    if (_error case final error?) Error.throwWithStackTrace(error, _stack!);
  }
}
