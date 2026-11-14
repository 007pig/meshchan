import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/drafts/editor.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../tool/device_fixture.dart';
import '../tool/device_scenario.dart';
import '../tool/profile_fixture.dart';

void main() {
  for (final target in EditorTarget.values) {
    for (final choice in LeaveChoice.values) {
      test('occupied check + dirty $target + quit $choice', () async {
        final dir = Directory.systemTemp.createTempSync(
          'meshchan-device-quit-',
        );
        final port = ReceivePort();
        final ready = port.first;
        final runtime = RuntimeController(
          resolveDirectory: () async => dir.path,
          entry: deviceFixtureEntry(port.sendPort),
        );
        await runtime.start();
        final commands = ((await ready) as DeviceFixtureReady).commands;
        port.close();
        final handle = runtime.startDeviceCheck(
          'A',
          const DeviceCheckOptions(),
        );
        await handle.accepted;
        await deviceState(runtime, (s) => s.deviceCheck?.info != null);
        final quit = DraftQuitCoordinator(runtime)
          ..auxiliaryActive = target != EditorTarget.draft;
        Future<LeaveChoice> discard({required bool unknown}) async =>
            LeaveChoice.discard;
        if (target == EditorTarget.draft) {
          await quit.editor.newDraft(discard);
          quit.editor.body.text = 'saved during check';
        } else if (target == EditorTarget.profile) {
          await quit.profiles.newProfile(discard);
          quit.profiles.form.load(
            fixtureProfile(DiagnosticOperation.send).parameters,
          );
          quit.profiles.name.text = 'saved during check';
        } else {
          await quit.profiles.openSettings(discard);
          quit.profiles.history.text = '1234';
        }
        final prompted = Completer<void>();
        var prompts = 0;
        quit.prompt = ({required unknown}) async {
          prompts++;
          if (!prompted.isCompleted) prompted.complete();
          return choice;
        };
        final a = quit.requestQuit(), b = quit.requestQuit();
        await prompted.future;
        if (choice == LeaveChoice.continueEditing) {
          expect(await a, false);
          expect(await b, false);
          expect(runtime.snapshot.gate, DeviceGateState.occupied);
          expect(runtime.snapshot.admissionPaused, false);
          await runtime.listDrafts();
          quit.prompt = discard;
          final finishing = quit.requestQuit();
          commands.send(DeviceFixtureControl.release);
          expect(await finishing, true);
        } else {
          await deviceState(runtime, (s) => s.stopReceived);
          expect(runtime.snapshot.owner, OwnerFact.held);
          expect(runtime.snapshot.deviceCheck!.released, false);
          commands.send(DeviceFixtureControl.release);
          expect(await a, true);
          expect(await b, true);
        }
        expect(prompts, 1);
        expect(runtime.pendingCount, 0);
        expect(runtime.openPortCount, 0);
        quit.disposeEditors();
        final storage = await CoreStorage.open(dataDirectory: dir);
        final saved = choice == LeaveChoice.save;
        if (target == EditorTarget.draft) {
          expect((await storage.drafts.list()).items.length, saved ? 1 : 0);
        }
        if (target == EditorTarget.profile) {
          expect((await storage.profiles.list()).items.length, saved ? 1 : 0);
        }
        if (target == EditorTarget.settings) {
          expect(
            (await storage.settings.read()).diagnosticHistoryLimit,
            saved ? 1234 : 1000,
          );
        }
        expect((await storage.history.query()).items, isEmpty);
        await storage.close();
        dir.deleteSync(recursive: true);
      });
    }
  }
  test('pending profile create A, edit B, occupied check and quit Save retain one ID', () async {
    final dir = Directory.systemTemp.createTempSync('meshchan-device-create-');
    final port = ReceivePort();
    final ready = Completer<DeviceFixtureReady>(),
        committed = Completer<void>();
    final subscription = port.listen((v) {
      if (v is DeviceFixtureReady) ready.complete(v);
      if (v is DeviceFixtureFact) committed.complete();
    });
    final runtime = RuntimeController(
      resolveDirectory: () async => dir.path,
      entry: deviceFixtureEntry(port.sendPort, holdProfileCreate: true),
    );
    await runtime.start();
    final commands = (await ready.future).commands;
    await runtime.startDeviceCheck('A', const DeviceCheckOptions()).accepted;
    await deviceState(runtime, (s) => s.deviceCheck?.info != null);
    final quit = DraftQuitCoordinator(runtime)..auxiliaryActive = true;
    await quit.profiles.newProfile(
      ({required unknown}) async => LeaveChoice.discard,
    );
    quit.profiles.form.load(
      fixtureProfile(DiagnosticOperation.send).parameters,
    );
    quit.profiles.name.text = 'A';
    final saving = quit.profiles.save();
    await committed.future;
    quit.profiles.name.text = 'B';
    quit.prompt = ({required unknown}) async => LeaveChoice.save;
    final exiting = quit.requestQuit();
    commands.send(DeviceFixtureControl.releaseProfileAck);
    expect(await saving, true);
    await deviceState(runtime, (s) => s.stopReceived);
    commands.send(DeviceFixtureControl.release);
    expect(await exiting, true);
    quit.disposeEditors();
    await subscription.cancel();
    port.close();
    final storage = await CoreStorage.open(dataDirectory: dir);
    final profiles = (await storage.profiles.list()).items;
    expect(profiles.length, 1);
    expect(profiles.single.name, 'B');
    await storage.close();
    dir.deleteSync(recursive: true);
  });
  test('lost start ack retains info/cleanup and terminal fault; late release closes normally', () async {
    final dir = Directory.systemTemp.createTempSync('meshchan-device-unknown-');
    final port = ReceivePort(), ready = Completer<DeviceFixtureReady>();
    final subscription = port.listen(
      (v) => ready.complete(v as DeviceFixtureReady),
    );
    final runtime = RuntimeController(
      resolveDirectory: () async => dir.path,
      entry: deviceFixtureEntry(port.sendPort, delayAck: true),
      deadline: const Duration(seconds: 2),
    );
    await runtime.start();
    final commands = (await ready.future).commands;
    final handle = runtime.startDeviceCheck('A', const DeviceCheckOptions());
    final rejected = expectLater(handle.accepted, throwsA(isA<RuntimeFault>()));
    await deviceState(runtime, (s) => s.deviceCheck?.info != null);
    final info = runtime.snapshot.lastDeviceInfo;
    await rejected;
    expect(runtime.snapshot.phase, RuntimePhase.fault);
    expect(runtime.snapshot.lastDeviceInfo!.observedAt, info!.observedAt);
    expect(runtime.snapshot.deviceCheck!.sessionCleanup, DeviceCleanup.pending);
    commands.send(DeviceFixtureControl.release);
    await deviceState(runtime, (s) => s.deviceCheck?.released == true);
    expect(runtime.snapshot.phase, RuntimePhase.fault);
    expect(runtime.snapshot.admissionPaused, true);
    expect(runtime.snapshot.lastDeviceInfo!.observedAt, info.observedAt);
    expect((await runtime.shutdown()).canExit, true);
    await subscription.cancel();
    port.close();
    dir.deleteSync(recursive: true);
  });
}
