import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../tool/diagnostic_fixture.dart';
import '../tool/device_scenario.dart' show deviceState;

void main() {
  test('rejected duplicate cannot clear an earlier Start admission latch', () async {
    final observer = ReceivePort();
    final control = Completer<SendPort>();
    final firstSeen = Completer<void>();
    final counts = <int>[];
    final subscription = observer.listen((message) {
      if (message is SendPort) control.complete(message);
      if (message is int) {
        counts.add(message);
        if (!firstSeen.isCompleted) firstSeen.complete();
      }
    });
    final runtime = RuntimeController(
      resolveDirectory: () async => '/unused-admission-fixture',
      entry: _delayedAdmission(observer.sendPort),
    );
    addTearDown(() async {
      await runtime.shutdown();
      await subscription.cancel();
      observer.close();
    });
    await runtime.start();
    final first = runtime.startRecordedDiagnostic(
      ' explicit fixture ',
      diagnosticRequest(),
    );
    final duplicate = runtime.startRecordedDiagnostic(
      ' explicit fixture ',
      diagnosticRequest(),
    );
    // Rejections are observed by the controller even if a caller attaches later.
    await Future<void>.delayed(Duration.zero);
    final busy = isA<RuntimeFault>().having(
      (e) => e.host,
      'admission still pending',
      CoordinationFault.deviceBusy,
    );
    await expectLater(duplicate.accepted, throwsA(busy));
    final third = runtime.startRecordedDiagnostic(
      ' explicit fixture ',
      diagnosticRequest(),
    );
    final thirdObserved = expectLater(third.accepted, throwsA(busy));
    expect(runtime.pendingCount, 1);
    await thirdObserved;
    // The bridge is still usable, although no occupied snapshot or ACK arrived.
    await runtime.request(const GetStatus());
    await firstSeen.future;
    expect(counts, [1]);
    (await control.future).send(true);
    await first.accepted;
    expect(runtime.pendingCount, 0);
    expect((await runtime.shutdown()).canExit, true);
  });
  test('typed product bridge records PING and finite zero-response Responder with fresh sessions', () async {
    final dir = Directory.systemTemp.createTempSync(
      'meshchan-typed-recording-',
    );
    final observer = ReceivePort();
    final runtime = RuntimeController(
      resolveDirectory: () async => dir.path,
      entry: diagnosticFixtureEntry(observer.sendPort),
    );
    final facts = <String>[];
    final subscription = observer.listen((e) {
      if (e is DiagnosticFact) facts.add(e.name);
    });
    await runtime.start();
    for (final respond in [false, true]) {
      final handle = runtime.startRecordedDiagnostic(
        ' explicit fixture ',
        diagnosticRequest(respond: respond),
      );
      await handle.accepted;
      await deviceState(
        runtime,
        (s) =>
            s.operation?.attemptId == handle.id &&
            s.operation!.done &&
            s.gate == DeviceGateState.free,
      );
      final op = runtime.snapshot.operation!;
      expect(op.runId, isNotNull);
      expect(op.resourcesReleased, true);
      expect(op.registration!.state, RecordingSaveState.committed);
      expect(op.logicalSave!.state, RecordingSaveState.committed);
      expect(op.cleanupSave!.state, RecordingSaveState.committed);
      expect(op.cleanupSave!.finalCleanup, true);
      expect(op.summary, respond ? isA<RespondSummary>() : isA<PingSummary>());
      if (respond) {
        final result = op.summary as RespondSummary;
        expect(result.reason, LogicalReason.completed);
        expect(result.responseAttempts, 0);
        expect(result.localResponsesConfirmed, 0);
        expect(result.listenStopReason, ListenStopReason.durationElapsed);
        expect(result.lastSend!.attempted, false);
        expect(result.lastSend!.deviceAcceptanceConfirmed, false);
      } else {
        final result = op.summary as PingSummary;
        expect(result.roundTripSucceeded, true);
        expect(result.applicationRttUs, isNotNull);
      }
      await runtime.cancelRecordedDiagnostic(handle); // Settled idempotence.
      await runtime
          .startDeviceCheck('metadata fixture', const DeviceCheckOptions())
          .accepted;
      await deviceState(
        runtime,
        (s) =>
            s.deviceCheck?.released == true && s.gate == DeviceGateState.free,
      );
    }
    expect(facts.where((s) => s == 'factory').length, 2);
    expect((await runtime.shutdown()).canExit, true);
    final storage = await CoreStorage.open(dataDirectory: dir);
    final runs = (await storage.history.query()).items;
    expect(runs.length, 2);
    expect(runs.map((r) => r.operation).toSet(), {
      DiagnosticOperation.ping,
      DiagnosticOperation.respond,
    });
    expect(runs.every((r) => r.appVersion == '0.1.0-dev.3+1'), true);
    await storage.close();
    await subscription.cancel();
    observer.close();
    dir.deleteSync(recursive: true);
  });
}

/// Deliberately withholds both the occupied snapshot and Start ACK, without
/// storage or hardware. Only test code can choose this worker entry.
void Function(WorkerBootstrap) _delayedAdmission(SendPort observer) => (b) {
  final commands = ReceivePort();
  final held = <RequestEnvelope>[];
  var starts = 0;
  void releaseStarts() {
    for (final message in held) {
      b.events.send(
        RequestReply(b.generation, message.id, value: const Accepted()),
      );
    }
    held.clear();
  }

  observer.send(commands.sendPort);
  b.events.send(WorkerHello(b.generation, commands.sendPort));
  b.events.send(
    SnapshotEvent(
      b.generation,
      RuntimeSnapshot(
        generation: b.generation,
        sequence: 1,
        phase: RuntimePhase.ready,
      ),
    ),
  );
  commands.listen((message) {
    if (message is ReleaseAcknowledged) {
      commands.close();
    } else if (message == true) {
      releaseStarts();
    } else if (message is RequestEnvelope) {
      if (message.request is StartRecordedDiagnostic) {
        held.add(message);
        observer.send(++starts);
      } else if (message.request is ShutdownRuntime) {
        releaseStarts();
        b.events.send(
          ReleaseReport(
            b.generation,
            message.id,
            RuntimeSnapshot(
              generation: b.generation,
              sequence: 2,
              phase: RuntimePhase.closed,
            ),
            true,
          ),
        );
      } else {
        b.events.send(
          RequestReply(b.generation, message.id, value: const Accepted()),
        );
      }
    }
  });
};
