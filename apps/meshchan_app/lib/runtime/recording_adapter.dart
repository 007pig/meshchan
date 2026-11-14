import 'dart:async';

import 'package:meshchan_core/meshchan_core.dart';

import 'protocol.dart';

/// Observes public recording facts only. The final result repairs missed
/// broadcast events; cancel/logical are never treated as release barriers.
final class RecordingAdapter {
  RecordingAdapter(
    this.operation,
    this.generation,
    this.changed, {
    this.attemptId,
    this.isCancelRequested,
  }) {
    // One broken observer must not prevent installing the others.
    try {
      _subscriptions.add(
        operation.cleanupUpdates.listen(_cleanup, onError: _error),
      );
    } catch (e, s) {
      _error(e, s);
    }
    try {
      _subscriptions.add(operation.saveUpdates.listen(_save, onError: _error));
    } catch (e, s) {
      _error(e, s);
    }
    _observe(operation.prepared, (v) {
      _preparedObserved = true;
      registration = v;
      _notify();
    });
    _observe(operation.logical, (v) {
      summary = v;
      logical = v?.reason;
      _notify();
    });
    _observe(operation.logicalSaved, (v) {
      _logicalSavedObserved = true;
      logicalSave = v;
      _notify();
    });
    _observe(operation.cleanupDone, (v) {
      cleanupDoneObserved = true;
      cleanup = v;
      _cleanupFinal = true;
      _notify();
    });
    _observe(operation.cleanupSaved, (v) {
      _cleanupSavedObserved = true;
      cleanupSave = v;
      _notify();
    });
    _observe(operation.done, (v) {
      coreDoneObserved = true;
      cleanupDoneObserved = true;
      summary = v.logical;
      saves = v.saves.map(SaveSnapshot.from).toList(growable: false);
      coordination = v.coordinationFailure;
      fullySuccessful = v.fullySuccessful;
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
  final int? attemptId;
  final bool Function()? isCancelRequested;
  LogicalSummary? summary;
  FailureSummary? coordination;
  List<SaveSnapshot> saves = const [];
  bool coreDoneObserved = false, cleanupDoneObserved = false;
  bool? fullySuccessful;
  bool _finishing = false;
  bool _preparedObserved = false,
      _logicalSavedObserved = false,
      _cleanupSavedObserved = false;
  int _observerCleanupFailures = 0;
  final void Function(OperationSnapshot) changed;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _observations = <Future<void>>[];
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
    attemptId: attemptId,
    preparation: _finished
        ? DiagnosticPreparation.settled
        : DiagnosticPreparation.recording,
    cancelRequested: isCancelRequested?.call() ?? _canceling != null,
    summary: summary,
    cleanup: cleanup,
    saves: List.unmodifiable(saves),
    coordination: coordination,
    coreDoneObserved: coreDoneObserved,
    cleanupDoneObserved: cleanupDoneObserved,
    observerCleanupComplete: _finished,
    observerCleanup: !_finished
        ? CleanupState.pending
        : _observerCleanupFailures == 0
        ? CleanupState.succeeded
        : CleanupState.failed,
    observerCleanupFailureCount: _observerCleanupFailures,
    fullySuccessful: fullySuccessful,
    runId: registration?.state == RecordingSaveState.committed
        ? registration?.snapshot?.runId.value
        : null,
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
    final observation = future.then<void>(
      (v) {
        if (!_finished && !coreDoneObserved) accept(v);
      },
      onError: (Object e, StackTrace s) {
        _error(e, s);
        if (terminal) unawaited(_finish());
      },
    );
    if (!terminal) _observations.add(observation);
    unawaited(observation);
  }

  void _error(Object _, [StackTrace? stack]) {
    observationFailure = true;
    _notify();
  }

  void _notify() {
    if (!_finished) changed(snapshot);
  }

  bool _cleanupFinal = false;
  void _cleanup(CleanupSummary value) {
    if (coreDoneObserved || _cleanupFinal) return;
    cleanup = value;
    _notify();
  }

  void _save(RecordingSave value) {
    if (coreDoneObserved) return;
    if (value.phase == RecordingPhase.cleanup &&
        cleanupSave?.finalCleanup == true &&
        !value.finalCleanup) {
      return;
    }
    saves = List.unmodifiable([...saves, SaveSnapshot.from(value)]);
    switch (value.phase) {
      case RecordingPhase.registration:
        if (_preparedObserved) return;
        registration = value;
      case RecordingPhase.logical:
        if (_logicalSavedObserved) return;
        logicalSave = value;
      case RecordingPhase.cleanup:
        if (_cleanupSavedObserved) return;
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
    if (_finished || _finishing || _settled.isCompleted) return;
    _finishing = true;
    await Future.wait(_observations);
    await _canceling;
    // Stop observers before publishing done. Subscription cancellation failures
    // are independent host failures and leave the device lease quarantined.
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {
        _observerCleanupFailures++;
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
