import 'dart:async';

import 'package:meshchan_core/meshchan_core.dart';

import 'protocol.dart';

/// Observes public recording facts only. The final result repairs missed
/// broadcast events; cancel/logical are never treated as release barriers.
final class RecordingAdapter {
  RecordingAdapter(this.operation, this.generation, this.changed) {
    _subscriptions.add(
      operation.cleanupUpdates.listen(_cleanup, onError: _error),
    );
    _subscriptions.add(operation.saveUpdates.listen(_save, onError: _error));
    _observe(operation.prepared, (v) {
      registration = v;
      _notify();
    });
    _observe(operation.logical, (v) {
      logical = v?.reason;
      _notify();
    });
    _observe(operation.logicalSaved, (v) {
      logicalSave = v;
      _notify();
    });
    _observe(operation.cleanupDone, _cleanup);
    _observe(operation.cleanupSaved, (v) {
      cleanupSave = v;
      _notify();
    });
    _observe(operation.done, (v) {
      registration = v.registration;
      logical = v.logical?.reason;
      logicalSave = v.logicalSave;
      cleanupSave = v.cleanupSave;
      cleanup = v.cleanup;
      coordinationFailure = v.coordinationFailure != null;
      coordinationKind = v.coordinationFailure?.kind;
      unawaited(_finish());
    }, terminal: true);
  }
  final RecordedOperation operation;
  final int generation;
  final void Function(OperationSnapshot) changed;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _settled = Completer<OperationSnapshot>();
  Future<void>? _canceling;
  bool _finished = false,
      observationFailure = false,
      coordinationFailure = false;
  LogicalReason? logical;
  FailureKind? coordinationKind;
  RecordingSave? registration, logicalSave, cleanupSave;
  CleanupSummary? cleanup;
  Future<OperationSnapshot> get settled => _settled.future;
  OperationSnapshot get snapshot => OperationSnapshot(
    generation: generation,
    runId: registration?.snapshot?.runId.value,
    logical: logical,
    registration: registration == null
        ? null
        : SaveSnapshot.from(registration!),
    logicalSave: logicalSave == null ? null : SaveSnapshot.from(logicalSave!),
    cleanupSave: cleanupSave == null ? null : SaveSnapshot.from(cleanupSave!),
    coreCleanup: cleanup?.core.state,
    hostCleanup: cleanup?.hostSubscriptions.state,
    aggregate: cleanup?.aggregate,
    observationFailure: observationFailure,
    coordinationFailure: coordinationFailure,
    coordinationKind: coordinationKind,
    done: _finished,
  );

  void _observe<T>(
    Future<T> future,
    void Function(T) accept, {
    bool terminal = false,
  }) {
    unawaited(
      future.then<void>(
        (v) {
          if (!_finished) accept(v);
        },
        onError: (Object e, StackTrace s) {
          _error(e, s);
          if (terminal) unawaited(_finish());
        },
      ),
    );
  }

  void _error(Object _, [StackTrace? stack]) {
    observationFailure = true;
    _notify();
  }

  void _notify() {
    if (!_finished) changed(snapshot);
  }

  void _cleanup(CleanupSummary value) {
    cleanup = value;
    _notify();
  }

  void _save(RecordingSave value) {
    switch (value.phase) {
      case RecordingPhase.registration:
        registration = value;
      case RecordingPhase.logical:
        logicalSave = value;
      case RecordingPhase.cleanup:
        cleanupSave = value;
    }
    _notify();
  }

  void cancel() {
    // Observe the returned logical future immediately, once. It does not wait
    // for cleanup and never releases the lease.
    _canceling ??= Future.sync(operation.cancel).then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {
        _error(e, s);
      },
    );
  }

  Future<void> _finish() async {
    if (_finished || _settled.isCompleted) return;
    // Stop observers before publishing done. Subscription cancellation failures
    // are independent host failures and leave the device lease quarantined.
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {
        observationFailure = true;
      }
    }
    _subscriptions.clear();
    _finished = true;
    final value = snapshot;
    changed(value);
    _settled.complete(value);
  }
}
