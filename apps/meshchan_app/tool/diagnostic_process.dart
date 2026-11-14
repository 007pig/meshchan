import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'diagnostic_fixture.dart';
import 'device_scenario.dart' show deviceState, require, rejects;
import 'profile_fixture.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      ![
        'normal',
        'resolve',
        'stop',
        'prepared',
        'fault',
        'read',
      ].contains(args[0]) ||
      !args[1].startsWith('/')) {
    exitCode = 64;
    return;
  }
  final mode = args[0], directory = Directory(args[1]);
  if (mode == 'read') {
    final storage = await CoreStorage.open(dataDirectory: directory);
    final runs = (await storage.history.query()).items;
    for (final run in runs) {
      require(run.appVersion == '0.1.0-dev.3+1', 'app version');
      require(
        run.result is PingSummary || run.result is RespondSummary,
        'typed stored result',
      );
      require(
        run.cleanup.aggregate == CleanupState.succeeded ||
            run.cleanup.aggregate == CleanupState.notRequired,
        'stored actual cleanup',
      );
    }
    await storage.close();
    stdout.writeln(jsonEncode({'passed': true, 'runs': runs.length}));
    return;
  }
  final observer = ReceivePort();
  final facts = <String>[];
  final ready = Completer<SendPort>();
  final subscription = observer.listen((e) {
    if (e is DiagnosticReady) ready.complete(e.port);
    if (e is DiagnosticFact) facts.add(e.name);
  });
  final resolving = mode == 'resolve' || mode == 'stop';
  final runtime = RuntimeController(
    resolveDirectory: () async => directory.path,
    entry: diagnosticFixtureEntry(
      observer.sendPort,
      holdResolve: resolving,
      holdCleanup: mode == 'normal',
      failCleanup: mode == 'fault',
      cancelBeforePrepared: mode == 'prepared',
      delayAck: mode == 'normal',
    ),
  );
  await runtime.start();
  final control = await ready.future;
  final handle = runtime.startRecordedDiagnostic(
    ' explicit fixture ',
    diagnosticRequest(),
  );
  if (mode != 'normal') await handle.accepted;
  await deviceState(runtime, (s) => s.operation?.attemptId == handle.id);
  require(
    runtime.snapshot.operation!.runId == null || !resolving,
    'initial real run ID',
  );
  await rejects(runtime.refreshDevicePorts(1));
  await rejects(
    runtime.startDeviceCheck('other', const DeviceCheckOptions()).accepted,
  );
  if (resolving) {
    // Actual resolver entry, before record, with responsive control channel.
    while (!facts.contains('resolving')) {
      await Future<void>.delayed(Duration.zero);
    }
    await runtime.request(const GetStatus());
    await runtime.cancelRecordedDiagnostic(handle);
    require(runtime.snapshot.operation!.cancelRequested, 'scoped intent');
    final reading = runtime.readSettings();
    final d = await runtime.beginDraftDecision(
      3,
      target: EditorTarget.settings,
    );
    final saving = runtime.saveSettings(
      AppSettings(diagnosticHistoryLimit: 1234),
      decision: d,
    );
    await rejects(runtime.saveSettings(AppSettings(), decision: d));
    await runtime.request(const GetStatus());
    if (mode == 'stop') {
      await runtime.stop();
    }
    control.send(DiagnosticControl.releaseResolve);
    await reading;
    await saving;
    if (mode == 'stop') {
      await rejects(runtime.endDraftDecision(d));
    } else {
      await runtime.endDraftDecision(d);
    }
    control.send(DiagnosticControl.releaseResolve);
    await deviceState(
      runtime,
      (s) => s.operation?.done == true && s.gate == DeviceGateState.free,
    );
    require(
      !facts.contains('record') && !facts.contains('factory'),
      'cancel before record',
    );
    require(runtime.snapshot.operation!.runId == null, 'no fake registration');
    if (mode == 'stop') {
      await rejects(runtime.resumeAdmission());
      await rejects(
        runtime
            .startRecordedDiagnostic(' explicit fixture ', diagnosticRequest())
            .accepted,
      );
    } else {
      await runtime.listDrafts(); // No Resume required.
      final next = runtime.startRecordedDiagnostic(
        ' explicit fixture ',
        diagnosticRequest(),
      );
      await next.accepted;
      await rejects(runtime.cancelRecordedDiagnostic(handle));
      await deviceState(
        runtime,
        (s) => s.operation?.attemptId == next.id && s.operation!.done,
      );
      require(
        (runtime.snapshot.operation!.summary as PingSummary)
                .roundTripSucceeded ==
            true,
        'next explicit PING',
      );
    }
  } else {
    await deviceState(runtime, (s) => s.operation?.logical != null);
    if (mode == 'normal') {
      final a = runtime.snapshot.operation!;
      require(
        (a.summary as PingSummary).roundTripSucceeded == true &&
            (a.summary as PingSummary).applicationRttUs != null,
        'real recorded fake PONG',
      );
      require(
        !a.done && runtime.snapshot.gate == DeviceGateState.occupied,
        'logical is not release',
      );
      await runtime.cancelRecordedDiagnostic(
        handle,
      ); // Before delayed Accepted.
      await runtime.cancelRecordedDiagnostic(handle);
      await runtime.request(const GetStatus());
      require(
        runtime.pendingCount == 1,
        'only delayed admission remains pending',
      );
      for (final target in EditorTarget.values) {
        final decision = await runtime.beginDraftDecision(7, target: target);
        if (target == EditorTarget.draft) {
          await runtime.saveDraft(
            title: 'Diagnostic fixture',
            body: 'final save',
            session: 7,
            decision: decision,
          );
        } else if (target == EditorTarget.profile) {
          await runtime.saveProfile(
            fixtureProfile(DiagnosticOperation.respond),
            session: 7,
            decision: decision,
          );
        } else {
          await runtime.saveSettings(
            AppSettings(diagnosticHistoryLimit: 1234),
            decision: decision,
          );
        }
        await rejects(runtime.saveSettings(AppSettings(), decision: decision));
        await runtime.endDraftDecision(decision);
        require(
          runtime.snapshot.gate == DeviceGateState.occupied &&
              !runtime.snapshot.admissionPaused,
          'Continue while healthy cleanup pending',
        );
      }
      stdout.writeln(jsonEncode({'held': true}));
      await stdout.flush();
      await stdin.first;
      var finished = false;
      final closing = runtime.shutdown().then((v) {
        finished = true;
        return v;
      });
      await runtime.request(const GetStatus());
      require(!finished, 'shutdown waits cleanup');
      control.send(DiagnosticControl.releaseCleanup);
      await handle.accepted;
      require(runtime.stopIntent, 'late Accepted preserves stop');
      require((await closing).canExit, 'normal actual exit');
    } else {
      await deviceState(runtime, (s) => s.operation?.done == true);
      if (mode == 'prepared') {
        require(
          !facts.contains('factory'),
          'synchronous cancel precedes factory admission',
        );
        require(
          runtime.snapshot.operation!.runId != null &&
              runtime.snapshot.operation!.logical == LogicalReason.canceled,
          'cancel retains registration',
        );
      } else {
        await deviceState(runtime, (s) => s.phase == RuntimePhase.fault);
        require(
          runtime.snapshot.gate == DeviceGateState.quarantined,
          'failed cleanup quarantines',
        );
        require(
          (runtime.snapshot.operation!.summary as PingSummary)
                  .roundTripSucceeded ==
              true,
          'RTT survives cleanup failure',
        );
        await rejects(runtime.listDrafts());
        require(
          !(await runtime.shutdown()).canExit,
          'fault is not exit success',
        );
        stdout.writeln(
          jsonEncode({
            'passed': true,
            'normalClose': false,
            'resourcesReleased': false,
          }),
        );
        await stdout.flush();
        exit(0); // Isolated fault reclamation, no release claim.
      }
    }
  }
  if (mode != 'normal') {
    require((await runtime.shutdown()).canExit, 'release and worker exit');
  }
  await subscription.cancel();
  observer.close();
  final storage = await CoreStorage.open(dataDirectory: directory);
  final runs = (await storage.history.query()).items;
  require(runs.length == (mode == 'stop' ? 0 : 1), 'independent final records');
  if (runs.isNotEmpty) {
    require(
      runs.single.recordState == DiagnosticRecordState.settled,
      'settled history',
    );
    require(runs.single.appVersion == '0.1.0-dev.3+1', 'actual app version');
  }
  await storage.close();
  stdout.writeln(
    jsonEncode({
      'passed': true,
      'hardware': false,
      'released': true,
      'workerExited': true,
      'runs': runs.length,
    }),
  );
}
