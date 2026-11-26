import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/device/model.dart';
import 'package:meshchan_app/diagnostics/model.dart';
import 'package:meshchan_app/profiles/preview.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart'
    show CompanionTransportKind, ConnectionTarget, TcpTarget, UsbSerialTarget;

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
      UsbSerialTarget(portPath: ' explicit fixture '),
      diagnosticRequest(),
    );
    final duplicate = runtime.startRecordedDiagnostic(
      UsbSerialTarget(portPath: ' explicit fixture '),
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
      TcpTarget(host: 'fixture.invalid', port: 5000),
      SendParameterRequest(),
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
    final invalid = runtime.startRecordedDiagnostic(
      TcpTarget(host: 'fixture.invalid', port: 5000),
      diagnosticRequest(),
    );
    await expectLater(
      invalid.accepted,
      throwsA(
        isA<RuntimeFault>().having(
          (e) => e.host,
          'unsupported product target',
          CoordinationFault.invalidState,
        ),
      ),
    );
    expect(runtime.pendingCount, 0);
    expect((await runtime.shutdown()).canExit, true);
  });
  test('UI sends exact Check, Ping and Responder worker targets', () async {
    const diagnosticPath = ' explicit\tfixture ';
    final dir = Directory.systemTemp.createTempSync(
      'meshchan-typed-recording-',
    );
    // Produce closed historical records through the public recorder, then let
    // the current App worker open the same schema-1 directory sequentially.
    final historical = await CoreStorage.open(dataDirectory: dir);
    final historicalIds = <LocalId, String>{};
    for (final version in ['0.1.0-beta.1+5', '0.1.0-dev.3']) {
      final operation = historical.record(
        parameters: await historical.resolveParameters(diagnosticRequest()),
        appVersion: version,
        createTransport: DiagnosticFixtureTransport.new,
      );
      final result = await operation.done;
      expect(result.fullySuccessful, true);
      historicalIds[result.registration.snapshot!.runId] = version;
    }
    final profiles = <bool, ConnectionProfile>{};
    for (final respond in [false, true]) {
      profiles[respond] = await historical.profiles.save(
        ProfileContent(
          name: respond ? 'Fixture Responder' : 'Fixture Ping',
          portHint: 'different profile port',
          parameters: (await historical.resolveParameters(
            diagnosticRequest(respond: respond),
          )).parameters,
        ),
      );
    }
    await historical.close();
    final observer = ReceivePort();
    final runtime = RuntimeController(
      resolveDirectory: () async => dir.path,
      entry: diagnosticFixtureEntry(
        observer.sendPort,
        expectedPortPath: diagnosticPath,
      ),
    );
    final facts = <String>[];
    final observedTargets = <ConnectionTarget>[];
    final factoriesObserved = Completer<void>();
    final subscription = observer.listen((e) {
      if (e is DiagnosticFact) facts.add(e.name);
      if (e is ConnectionTarget) {
        observedTargets.add(e);
        if (observedTargets.length == 4) factoriesObserved.complete();
      }
    });
    final device = DeviceModel(runtime);
    final diagnostics = DiagnosticsModel(runtime, device);
    addTearDown(() async {
      diagnostics.dispose();
      device.dispose();
      await runtime.shutdown();
      await subscription.cancel();
      observer.close();
      dir.deleteSync(recursive: true);
    });

    await runtime.start();
    await device.refresh();
    expect(device.selected, isNull);
    for (final respond in [false, true]) {
      final profile = profiles[respond]!;
      diagnostics.changeOperation(profile.parameters.operation);
      await diagnostics.select(profile.id.value);
      expect(diagnostics.inherited?.portHint, 'different profile port');
      if (!respond) {
        expect(diagnostics.canStart, false);
        diagnostics.mode = ContentMode.hex;
        diagnostics.content.text = '0080ff';
      }
      device.select(diagnosticPath);
      final starting = diagnostics.startDiagnostic();
      final handle = diagnostics.handle!;
      device.select(diagnosticFixtureCheckPath);
      await starting;
      expect(diagnostics.actionFailure, isNull);
      await deviceState(
        runtime,
        (s) =>
            s.operation?.attemptId == handle.id &&
            s.operation!.done &&
            s.gate == DeviceGateState.free,
      );
      expect(diagnostics.attemptPort, diagnosticPath);
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
      final checking = device.check();
      final checkId = device.handle!.id;
      device.select(diagnosticPath);
      await checking;
      expect(device.actionFailure, isNull);
      await deviceState(
        runtime,
        (s) =>
            s.deviceCheck?.id == checkId &&
            s.deviceCheck!.released &&
            s.gate == DeviceGateState.free,
      );
      expect(runtime.snapshot.deviceCheck!.port, diagnosticFixtureCheckPath);
      expect(runtime.snapshot.lastDeviceInfo!.port, diagnosticFixtureCheckPath);
    }
    await factoriesObserved.future;
    expect(observedTargets, everyElement(isA<UsbSerialTarget>()));
    expect(
      observedTargets.map((target) => target.kind),
      everyElement(CompanionTransportKind.usbSerial),
    );
    expect(observedTargets.cast<UsbSerialTarget>().map((t) => t.portPath), [
      diagnosticPath,
      diagnosticFixtureCheckPath,
      diagnosticPath,
      diagnosticFixtureCheckPath,
    ]);
    expect(facts.where((s) => s == 'factory').length, 2);
    expect((await runtime.shutdown()).canExit, true);
    final storage = await CoreStorage.open(dataDirectory: dir);
    final runs = (await storage.history.query()).items;
    expect(runs.length, 4);
    expect(runs.map((r) => r.operation).toSet(), {
      DiagnosticOperation.ping,
      DiagnosticOperation.respond,
    });
    expect(
      runs
          .where((r) => !historicalIds.containsKey(r.runId))
          .every((r) => r.appVersion == '0.1.0-rc.1+10'),
      true,
    );
    for (final entry in historicalIds.entries) {
      expect((await storage.history.read(entry.key)).appVersion, entry.value);
    }
    await storage.close();
    final reopened = await CoreStorage.open(dataDirectory: dir);
    for (final entry in historicalIds.entries) {
      expect((await reopened.history.read(entry.key)).appVersion, entry.value);
    }
    await reopened.close();
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
