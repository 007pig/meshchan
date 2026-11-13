import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'support/recording_worker.dart';

void main() {
  for (final mode in [
    HarnessCommand.startImmediateCancel,
    HarnessCommand.startPreparedCancel,
    HarnessCommand.startActive,
  ]) {
    final active = mode == HarnessCommand.startActive;
    final recorded = mode != HarnessCommand.startImmediateCancel;
    test(
      'real isolate/core recording $mode keeps control responsive',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'meshchan-recording-worker-',
        );
        final events = ReceivePort(),
            exits = ReceivePort(),
            errors = ReceivePort();
        final stream = StreamController<Object?>.broadcast(sync: true);
        final seen = <Object?>[];
        final subscription = events.listen((e) {
          seen.add(e);
          stream.add(e);
        });
        final exited = Completer<void>();
        final exitSubscription = exits.listen((_) => exited.complete());
        final errorSubscription = errors.listen(
          (_) => fail('Unexpected worker error'),
        );
        Future<T> event<T>(bool Function(T) match) async {
          for (final e in seen.whereType<T>()) {
            if (match(e)) return e;
          }
          return await stream.stream.where((e) => e is T && match(e)).first
              as T;
        }

        await Isolate.spawn(
          recordingWorker,
          WorkerBootstrap(91, dir.path, events.sendPort),
          onError: errors.sendPort,
          onExit: exits.sendPort,
        );
        final hello = await event<WorkerHello>((_) => true);
        await event<SnapshotEvent>(
          (e) => e.snapshot.phase == RuntimePhase.ready,
        );
        final port = hello.commands;
        port.send(mode);
        if (active) {
          await event<HarnessFact>((e) => e.name == 'opened');
          port.send(const RequestEnvelope(91, 1, CancelOperation(1)));
          await event<RequestReply>((e) => e.id == 1);
          await event<SnapshotEvent>(
            (e) => e.snapshot.operation?.logical != null,
          );
          port.send(const RequestEnvelope(91, 2, GetStatus()));
          final status = await event<RequestReply>((e) => e.id == 2);
          expect(
            (status.value as StatusValue).snapshot.gate,
            DeviceGateState.occupied,
          );
          // Logical cancellation has completed; actual transport close is blocked.
          port.send(const RequestEnvelope(91, 3, ShutdownRuntime()));
          await event<HarnessFact>((e) => e.name == 'closing');
          expect(seen.whereType<ReleaseReport>(), isEmpty);
          port.send(const RequestEnvelope(91, 4, GetStatus()));
          await event<RequestReply>((e) => e.id == 4);
          port.send(HarnessCommand.releaseCleanup);
        } else {
          await event<SnapshotEvent>(
            (e) =>
                (recorded
                    ? e.snapshot.operation?.done == true
                    : e.snapshot.stopApplied) &&
                e.snapshot.gate == DeviceGateState.free,
          );
          port.send(const RequestEnvelope(91, 2, ShutdownRuntime()));
        }
        final release = await event<ReleaseReport>((_) => true);
        expect(release.resourcesReleased, true);
        if (recorded) {
          final operation = release.snapshot.operation!;
          expect(operation.registration!.state, RecordingSaveState.committed);
          expect(operation.logical, LogicalReason.canceled);
          expect(operation.logicalSave!.state, RecordingSaveState.committed);
          expect(operation.cleanupSave!.state, RecordingSaveState.committed);
          expect(operation.cleanupSave!.finalCleanup, true);
          expect(operation.resourcesReleased, true);
        }
        expect(
          seen
              .whereType<HarnessFact>()
              .where((e) => e.name == 'factory')
              .length,
          active ? 1 : 0,
        );
        port.send(const ReleaseAcknowledged(91));
        await exited.future;
        final storage = await CoreStorage.open(dataDirectory: dir);
        final history = await storage.history.query();
        expect(history.items.length, recorded ? 1 : 0);
        if (recorded) {
          expect(history.items.single.result!.reason, LogicalReason.canceled);
        }
        await storage.close();
        await subscription.cancel();
        await exitSubscription.cancel();
        await errorSubscription.cancel();
        events.close();
        exits.close();
        errors.close();
        await stream.close();
        dir.deleteSync(recursive: true);
      },
    );
  }
}
