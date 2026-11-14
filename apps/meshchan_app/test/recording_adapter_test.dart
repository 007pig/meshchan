import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/recording_adapter.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';

void main() {
  test('logical/cancel do not release; final done repairs missed streams and saves fail independently', () async {
    final op = ControlledRecording();
    final values = <OperationSnapshot>[];
    final adapter = RecordingAdapter(op, 7, values.add);
    final gate = DeviceGate();
    final lease = gate.acquire();
    adapter.cancel();
    adapter.cancel();
    op.logicalValue.complete(
      PingSummary(
        reason: LogicalReason.canceled,
        stage: DiagnosticStage.startup,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(values.last.logical, LogicalReason.canceled);
    expect(values.last.done, false);
    expect(gate.state, DeviceGateState.occupied);
    expect(op.cancels, 1);
    final result = finishedResult(saveFailed: true);
    // No broadcast replay is supplied; done is authoritative.
    op.result.complete(result);
    final finalValue = await adapter.settled;
    gate.settle(lease, released: finalValue.resourcesReleased);
    expect(finalValue.resourcesReleased, true);
    expect(finalValue.cleanupSave!.state, RecordingSaveState.failed);
    expect(finalValue.cleanupSave!.finalCleanup, true);
    expect(finalValue.logical, LogicalReason.canceled);
    expect(gate.state, DeviceGateState.free);
    await op.streamsClose();
  });
  test(
    'done with unknown or failed cleanup keeps the lease quarantined',
    () async {
      for (final state in [
        CleanupState.pending,
        CleanupState.unconfirmed,
        CleanupState.unconfirmedAfterExit,
        CleanupState.failed,
      ]) {
        final op = ControlledRecording();
        final adapter = RecordingAdapter(op, 1, (_) {});
        op.result.complete(finishedResult(cleanup: state));
        final value = await adapter.settled;
        final gate = DeviceGate();
        final lease = gate.acquire();
        gate.settle(lease, released: value.resourcesReleased);
        expect(gate.state, DeviceGateState.quarantined);
        expect(() => gate.acquire(), throwsA(isA<RuntimeFault>()));
        await op.streamsClose();
      }
    },
  );
  test(
    'registration failure retains null logical and notAttempted saves',
    () async {
      final op = ControlledRecording();
      final adapter = RecordingAdapter(op, 1, (_) {});
      op.result.complete(
        RecordedResult(
          logical: null,
          cleanup: releasedCleanup(),
          registration: const RecordingSave(
            RecordingPhase.registration,
            RecordingSaveState.failed,
            error: CoreException(CoreErrorCode.storageWriteFailed),
          ),
          logicalSave: const RecordingSave(
            RecordingPhase.logical,
            RecordingSaveState.notAttempted,
          ),
          cleanupSave: const RecordingSave(
            RecordingPhase.cleanup,
            RecordingSaveState.notAttempted,
          ),
          saves: [],
        ),
      );
      final value = await adapter.settled;
      expect(value.logical, null);
      expect(value.logicalSave!.state, RecordingSaveState.notAttempted);
      expect(value.resourcesReleased, true);
      await op.streamsClose();
    },
  );
  test('every named Future and stream rejection is observed and done rejection cannot release', () async {
    final op = ControlledRecording();
    final adapter = RecordingAdapter(op, 1, (_) {});
    op.preparedValue.completeError(StateError('PRIVATE'));
    op.logicalValue.completeError(StateError('PRIVATE'));
    op.logicalSaveValue.completeError(StateError('PRIVATE'));
    op.cleanupValue.completeError(StateError('PRIVATE'));
    op.cleanupSaveValue.completeError(StateError('PRIVATE'));
    op.cleanups.addError(StateError('PRIVATE'));
    op.saves.addError(StateError('PRIVATE'));
    op.result.completeError(StateError('PRIVATE'));
    final value = await adapter.settled;
    expect(value.observationFailure, true);
    expect(value.resourcesReleased, false);
    await op.streamsClose();
  });
  test('final summary repairs missed broadcasts and rejects late pending regressions', () async {
    final op = ControlledRecording();
    final adapter = RecordingAdapter(op, 2, (_) {});
    final finalCleanup = releasedCleanup(CleanupState.succeeded);
    op.cleanupValue.complete(finalCleanup);
    await Future<void>.delayed(Duration.zero);
    op.cleanups.add(releasedCleanup(CleanupState.pending));
    final result = finishedResult(saveFailed: true);
    op.result.complete(result);
    final value = await adapter.settled;
    expect(value.coreCleanup, CleanupState.succeeded);
    expect(value.saves.length, result.saves.length);
    expect(value.coreDoneObserved, true);
    await op.streamsClose();
  });
  test(
    'known scope failures block health even while aggregate is pending',
    () async {
      final op = ControlledRecording();
      final adapter = RecordingAdapter(op, 3, (_) {});
      op.cleanups.add(
        CleanupSummary(
          core: CleanupScopeSummary(state: CleanupState.pending),
          hostSubscriptions: CleanupScopeSummary(
            state: CleanupState.pending,
            failures: const [
              FailureSummary(
                domain: FailureDomain.host,
                kind: FailureKind.cleanup,
              ),
            ],
          ),
          aggregate: CleanupState.pending,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.resourceUncertainty, true);
      expect(adapter.snapshot.cleanup!.hostSubscriptions.failureCount, 1);
      op.cleanups.add(adapter.snapshot.cleanup!);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.cleanup!.hostSubscriptions.failureCount, 1);
      op.result.complete(finishedResult());
      await adapter.settled;
      await op.streamsClose();
    },
  );
  for (final ping in [
    const PingSummary(
      reason: LogicalReason.sendFailed,
      matchingPongObserved: true,
      exactContentValidated: true,
      firstMatchingPongElapsedUs: 50,
      roundTripSucceeded: false,
    ),
    const PingSummary(
      reason: LogicalReason.completed,
      matchingPongObserved: true,
      exactContentValidated: true,
      firstMatchingPongElapsedUs: 70,
      applicationRttUs: 70,
      roundTripSucceeded: true,
    ),
  ]) {
    test(
      'frozen PONG facts survive independent cleanup/save failure: ${ping.reason}',
      () async {
        final op = ControlledRecording();
        final adapter = RecordingAdapter(op, 4, (_) {});
        final base = finishedResult(
          saveFailed: true,
          cleanup: CleanupState.failed,
        );
        op.result.complete(
          RecordedResult(
            logical: ping,
            cleanup: base.cleanup,
            registration: base.registration,
            logicalSave: base.logicalSave,
            cleanupSave: base.cleanupSave,
            saves: base.saves,
          ),
        );
        final value = await adapter.settled;
        expect(identical(value.summary, ping), true);
        expect(
          (value.summary as PingSummary).applicationRttUs,
          ping.applicationRttUs,
        );
        expect(value.resourcesReleased, false);
        await op.streamsClose();
      },
    );
  }
  test(
    'zero responder counters and missing last send remain distinct',
    () async {
      final op = ControlledRecording();
      final adapter = RecordingAdapter(op, 5, (_) {});
      final base = finishedResult();
      const response = RespondSummary(
        reason: LogicalReason.completed,
        listenStopReason: ListenStopReason.durationElapsed,
        responseAttempts: 0,
        localResponsesConfirmed: 0,
        processedEntries: 0,
      );
      op.result.complete(
        RecordedResult(
          logical: response,
          cleanup: base.cleanup,
          registration: base.registration,
          logicalSave: base.logicalSave,
          cleanupSave: base.cleanupSave,
          saves: base.saves,
        ),
      );
      final value = await adapter.settled;
      final summary = value.summary as RespondSummary;
      expect(summary.responseAttempts, 0);
      expect(summary.lastSend, null);
      expect(summary.reception, null);
      await op.streamsClose();
    },
  );
  test(
    'all app subscriptions cancel independently; failed cancel quarantines',
    () async {
      final op = FailingCancellationRecording();
      final adapter = RecordingAdapter(op, 6, (_) {});
      op.result.complete(finishedResult());
      final value = await adapter.settled;
      expect(op.cancellations, 2);
      expect(value.observerCleanupFailureCount, 1);
      expect(value.observerCleanup, CleanupState.failed);
      expect(value.resourcesReleased, false);
      await op.streamsClose();
    },
  );
  test(
    'named final cleanup save cannot regress even without finalCleanup',
    () async {
      final op = ControlledRecording();
      final adapter = RecordingAdapter(op, 8, (_) {});
      const failure = RecordingSave(
        RecordingPhase.cleanup,
        RecordingSaveState.failed,
        error: CoreException(CoreErrorCode.storageWriteFailed),
      );
      op.cleanupSaveValue.complete(failure);
      await Future<void>.delayed(Duration.zero);
      op.saves.add(
        const RecordingSave(
          RecordingPhase.cleanup,
          RecordingSaveState.committed,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.snapshot.cleanupSave!.state, RecordingSaveState.failed);
      final base = finishedResult();
      op.result.complete(
        RecordedResult(
          logical: base.logical,
          cleanup: base.cleanup,
          registration: base.registration,
          logicalSave: base.logicalSave,
          cleanupSave: failure,
          saves: const [failure],
        ),
      );
      expect(
        (await adapter.settled).cleanupSave!.state,
        RecordingSaveState.failed,
      );
      await op.streamsClose();
    },
  );
}

CleanupSummary releasedCleanup([
  CleanupState state = CleanupState.notRequired,
]) => CleanupSummary(
  core: CleanupScopeSummary(state: state),
  hostSubscriptions: CleanupScopeSummary(state: CleanupState.notRequired),
  aggregate: state,
);
RecordedResult finishedResult({
  bool saveFailed = false,
  CleanupState cleanup = CleanupState.succeeded,
}) => RecordedResult(
  logical: PingSummary(
    reason: LogicalReason.canceled,
    stage: DiagnosticStage.startup,
  ),
  cleanup: releasedCleanup(cleanup),
  registration: const RecordingSave(
    RecordingPhase.registration,
    RecordingSaveState.committed,
  ),
  logicalSave: const RecordingSave(
    RecordingPhase.logical,
    RecordingSaveState.committed,
  ),
  cleanupSave: RecordingSave(
    RecordingPhase.cleanup,
    saveFailed ? RecordingSaveState.failed : RecordingSaveState.committed,
    finalCleanup: true,
  ),
  saves: [],
);

class ControlledRecording implements RecordedOperation {
  ControlledRecording() {
    // A conforming operation settles its named signals before done. Individual
    // tests may complete them earlier to control observation order.
    result.future.then<void>((v) {
      if (!preparedValue.isCompleted) preparedValue.complete(v.registration);
      if (!logicalValue.isCompleted) logicalValue.complete(v.logical);
      if (!logicalSaveValue.isCompleted) {
        logicalSaveValue.complete(v.logicalSave);
      }
      if (!cleanupValue.isCompleted) cleanupValue.complete(v.cleanup);
      if (!cleanupSaveValue.isCompleted) {
        cleanupSaveValue.complete(v.cleanupSave);
      }
    }, onError: (Object _, StackTrace _) {});
  }
  final preparedValue = Completer<RecordingSave>();
  final logicalValue = Completer<LogicalSummary?>();
  final logicalSaveValue = Completer<RecordingSave>();
  final cleanupValue = Completer<CleanupSummary>();
  final cleanupSaveValue = Completer<RecordingSave>();
  final result = Completer<RecordedResult>();
  final cleanups = StreamController<CleanupSummary>.broadcast();
  final saves = StreamController<RecordingSave>.broadcast();
  int cancels = 0;
  @override
  Future<RecordingSave> get prepared => preparedValue.future;
  @override
  Future<LogicalSummary?> get logical => logicalValue.future;
  @override
  Future<RecordingSave> get logicalSaved => logicalSaveValue.future;
  @override
  Future<CleanupSummary> get cleanupDone => cleanupValue.future;
  @override
  Future<RecordingSave> get cleanupSaved => cleanupSaveValue.future;
  @override
  Future<RecordedResult> get done => result.future;
  @override
  Stream<CleanupSummary> get cleanupUpdates => cleanups.stream;
  @override
  Stream<RecordingSave> get saveUpdates => saves.stream;
  @override
  Future<LogicalSummary?> cancel() {
    cancels++;
    return logical;
  }

  Future<void> streamsClose() async {
    await cleanups.close();
    await saves.close();
  }
}

class FailingCancellationRecording extends ControlledRecording {
  int cancellations = 0;
  late final first = StreamController<CleanupSummary>(
    onCancel: () async {
      cancellations++;
      throw StateError('PRIVATE /dev/path route content');
    },
  );
  late final second = StreamController<RecordingSave>(
    onCancel: () async {
      cancellations++;
    },
  );
  @override
  Stream<CleanupSummary> get cleanupUpdates => first.stream;
  @override
  Stream<RecordingSave> get saveUpdates => second.stream;
}
