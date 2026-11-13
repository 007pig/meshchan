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
