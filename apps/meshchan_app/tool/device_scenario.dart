import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'device_fixture.dart';
import 'profile_fixture.dart';

void require(bool value, String code) {
  if (!value) throw StateError(code);
}

Future<void> deviceState(
  RuntimeController runtime,
  bool Function(RuntimeSnapshot) match,
) async {
  if (match(runtime.snapshot)) return;
  await runtime.changes.firstWhere(match).timeout(const Duration(seconds: 10));
}

Future<void> rejects(Future<Object?> result) async {
  try {
    await result;
  } on RuntimeFault {
    return;
  }
  throw StateError('Expected controlled rejection');
}

/// Real isolate, public fake transport and real owned SQLite. No native serial.
Future<void> runDeviceScenario(
  String directory, {
  bool delayedAck = false,
  Future<void> Function()? whileHeld,
}) async {
  final observer = ReceivePort();
  final ready = observer.first.then((v) => v as DeviceFixtureReady);
  final runtime = RuntimeController(
    resolveDirectory: () async => directory,
    entry: deviceFixtureEntry(observer.sendPort, delayAck: delayedAck),
  );
  await runtime.start();
  final control = (await ready).commands;
  observer.close();
  require(runtime.snapshot.phase == RuntimePhase.ready, 'owner');
  final ports = await runtime.refreshDevicePorts(3);
  require(
    ports.generation == 3 &&
        ports.ports.length == 2 &&
        ports.ports[1].warning != null,
    'ports',
  );
  final handle = runtime.startDeviceCheck(
    ' fixture A ',
    const DeviceCheckOptions(),
  );
  if (delayedAck) {
    await deviceState(runtime, (s) => s.deviceCheck?.info != null);
    await runtime.cancelDeviceCheck(handle.id); // Before start reply delivery.
    await deviceState(runtime, (s) => s.deviceCheck?.cancelApplied == true);
  } else {
    await handle.accepted;
    await deviceState(runtime, (s) => s.deviceCheck?.info != null);
  }
  await deviceState(
    runtime,
    (s) => s.deviceCheck?.sessionCleanup == DeviceCleanup.pending,
  );
  require(
    runtime.pendingCount == (delayedAck ? 1 : 0),
    'only admission pending',
  );
  require(runtime.snapshot.gate == DeviceGateState.occupied, 'occupied');
  await rejects(
    runtime.request(const StartDeviceCheck(99, 'B', DeviceCheckOptions())),
  );
  await rejects(runtime.refreshDevicePorts(4));
  await runtime.listDrafts();
  final draft = await runtime.saveDraft(
    title: 'Device fixture',
    body: 'offline',
    session: 1,
  );
  for (final target in EditorTarget.values) {
    final decision = await runtime.beginDraftDecision(
      1,
      target: target,
      targetId: target == EditorTarget.draft ? draft.id : null,
    );
    if (target == EditorTarget.draft) {
      await runtime.saveDraft(
        id: draft.id,
        expectedRevision: draft.revision,
        title: 'Device fixture',
        body: 'final save',
        session: 1,
        decision: decision,
      );
    } else if (target == EditorTarget.profile) {
      await runtime.saveProfile(
        fixtureProfile(DiagnosticOperation.send),
        session: 1,
        decision: decision,
      );
    } else {
      await runtime.saveSettings(
        AppSettings(diagnosticHistoryLimit: 1234),
        decision: decision,
      );
    }
    await rejects(runtime.saveSettings(AppSettings(), decision: decision));
    await runtime.endDraftDecision(
      decision,
    ); // Continue offline with same check.
    require(
      runtime.snapshot.gate == DeviceGateState.occupied &&
          !runtime.snapshot.admissionPaused,
      'healthy occupied resume',
    );
  }
  await runtime.readSettings();
  await runtime.cancelDeviceCheck(handle.id);
  await runtime.cancelDeviceCheck(handle.id);
  await whileHeld?.call();
  if (delayedAck) {
    control.send(DeviceFixtureControl.release);
    await deviceState(
      runtime,
      (s) => s.deviceCheck?.settled == true && s.gate == DeviceGateState.free,
    );
    await handle.accepted;
    require(runtime.snapshot.deviceCheck!.settled, 'late ack cannot regress');
    final next = runtime.startDeviceCheck(
      'fixture B',
      const DeviceCheckOptions(),
    );
    await next.accepted;
    await rejects(runtime.cancelDeviceCheck(handle.id));
    await deviceState(
      runtime,
      (s) => s.deviceCheck?.id == next.id && s.deviceCheck!.settled,
    );
  }
  await runtime.stop();
  await rejects(runtime.resumeAdmission());
  await rejects(
    runtime.startDeviceCheck('B', const DeviceCheckOptions()).accepted,
  );
  var finished = false;
  final closing = runtime.shutdown().then((v) {
    finished = true;
    return v;
  });
  if (!delayedAck) {
    await runtime.request(const GetStatus());
    require(
      !finished && runtime.snapshot.owner == OwnerFact.held,
      'close barrier',
    );
    control.send(DeviceFixtureControl.release);
  }
  final outcome = await closing;
  require(
    outcome.canExit && runtime.pendingCount == 0 && runtime.openPortCount == 0,
    'actual release and exit',
  );
  require(runtime.snapshot.deviceCheck!.released, 'device released');
  if (!delayedAck) {
    require(
      runtime.snapshot.lastDeviceInfo?.port == ' fixture A ',
      'historical source',
    );
  }
  final storage = await CoreStorage.open(dataDirectory: Directory(directory));
  require(
    (await storage.drafts.list()).items.single.body == 'final save',
    'committed draft',
  );
  require(
    (await storage.settings.read()).diagnosticHistoryLimit == 1234,
    'committed settings',
  );
  require(
    (await storage.history.query()).items.isEmpty,
    'no diagnostic history',
  );
  await storage.close();
}
