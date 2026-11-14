import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';

import 'device_fixture.dart';

import 'device_scenario.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !['normal', 'delayed', 'fault'].contains(args[0]) ||
      !args[1].startsWith('/')) {
    exitCode = 64;
    return;
  }
  if (args[0] == 'fault') {
    final observer = ReceivePort();
    final ready = observer.first;
    final runtime = RuntimeController(
      resolveDirectory: () async => args[1],
      entry: deviceFixtureEntry(observer.sendPort, failClose: true),
    );
    await runtime.start();
    final commands = ((await ready) as DeviceFixtureReady).commands;
    observer.close();
    await runtime.startDeviceCheck('A', const DeviceCheckOptions()).accepted;
    await deviceState(runtime, (s) => s.deviceCheck?.info != null);
    commands.send(DeviceFixtureControl.release);
    await deviceState(runtime, (s) => s.phase == RuntimePhase.fault);
    require(
      runtime.snapshot.lastDeviceInfo != null &&
          runtime.snapshot.deviceCheck!.cleanupFailure != null,
      'info plus cleanup fault',
    );
    require(runtime.snapshot.gate == DeviceGateState.quarantined, 'quarantine');
    await rejects(runtime.listDrafts());
    await rejects(runtime.resumeAdmission());
    final outcome = await runtime.shutdown();
    require(
      !outcome.canExit &&
          !outcome.resourcesReleased &&
          runtime.snapshot.owner == OwnerFact.held,
      'owner retained',
    );
    stdout.writeln(
      jsonEncode({
        'passed': true,
        'normalClose': false,
        'resourcesReleased': false,
        'reclamation': 'fault child process exit',
      }),
    );
    await stdout.flush();
    exit(0); // Explicit isolation reclamation, never a normal-close assertion.
  }
  await runDeviceScenario(
    args[1],
    delayedAck: args[0] == 'delayed',
    whileHeld: () async {
      stdout.writeln(jsonEncode({'held': true}));
      await stdout.flush();
      await stdin.first;
    },
  );
  stdout.writeln(
    jsonEncode({
      'passed': true,
      'fixtureWrites': false,
      'hardware': false,
      'released': true,
      'workerExited': true,
    }),
  );
}
