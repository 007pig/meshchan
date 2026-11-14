import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'profile_fixture.dart';

void check(bool condition) {
  if (!condition) throw StateError('Profile process assertion failed');
}

void lostProfileReply(WorkerBootstrap b) {
  final commands = ReceivePort();
  var lost = false;
  final dispatcher = WorkerDispatcher(
    b,
    send: (event) {
      if (!lost && event is RequestReply && event.value is ProfileValue) {
        lost = true;
        return;
      }
      b.events.send(event);
    },
    finish: commands.close,
  );
  commands.listen(dispatcher.receive);
  b.events.send(WorkerHello(b.generation, commands.sendPort));
  dispatcher.start();
}

void delayedProfileReply(WorkerBootstrap b) {
  final commands = ReceivePort();
  var delayed = false;
  final dispatcher = WorkerDispatcher(
    b,
    send: (event) {
      if (!delayed && event is RequestReply && event.value is ProfileValue) {
        delayed = true;
        Timer(const Duration(milliseconds: 300), () => b.events.send(event));
      } else {
        b.events.send(event);
      }
    },
    finish: commands.close,
  );
  commands.listen(dispatcher.receive);
  b.events.send(WorkerHello(b.generation, commands.sendPort));
  dispatcher.start();
}

Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !args[1].startsWith('/') ||
      !{
        'write',
        'read',
        'contend',
        'unknown',
        'unknown-read',
        'delayed',
      }.contains(args[0])) {
    exitCode = 64;
    return;
  }
  final mode = args[0], directory = args[1];
  final r = RuntimeController(
    resolveDirectory: () async => directory,
    entry: mode == 'unknown'
        ? lostProfileReply
        : mode == 'delayed'
        ? delayedProfileReply
        : runtimeWorkerEntry,
    deadline: Duration(seconds: mode == 'unknown' ? 2 : 30),
  );
  await r.start();
  if (mode == 'contend') {
    check(r.snapshot.phase == RuntimePhase.busy);
    check((await r.shutdown()).canExit);
    stdout.writeln(jsonEncode({'passed': true}));
    return;
  }
  check(r.snapshot.phase == RuntimePhase.ready && !r.fixtureWrites);
  final receipt = File('$directory/profile-receipt.json');
  if (mode == 'delayed') {
    final creating = r.saveProfile(
      fixtureProfile(DiagnosticOperation.send),
      session: 71,
    );
    final permit = await r.beginDraftDecision(71, target: EditorTarget.profile);
    final created = await creating;
    final saved = await r.saveProfile(
      fixtureProfile(DiagnosticOperation.send, name: 'B'),
      id: created.id.value,
      session: 71,
      decision: permit,
    );
    check(saved.id == created.id && saved.name == 'B');
    await r.endDraftDecision(permit);
    check((await r.listProfiles()).items.length == 1);
  } else if (mode == 'write') {
    check((await r.listProfiles()).items.isEmpty);
    final ids = <String, String>{};
    for (final op in DiagnosticOperation.values) {
      final p = await r.saveProfile(fixtureProfile(op), session: op.index + 1);
      ids[op.name] = p.id.value;
      final noOp = await r.saveProfile(
        fixtureProfile(op),
        id: p.id.value,
        session: op.index + 1,
      );
      check(noOp.updatedAt == p.updatedAt);
      check((await r.readProfile(p.id.value)).name == '  中文🙂\n');
    }
    final first = await r.listProfiles(size: 2);
    check(first.items.length == 2 && first.nextCursor != null);
    final second = await r.listProfiles(size: 2, after: first.nextCursor);
    check(
      second.items.length == 2 &&
          second.nextCursor == null &&
          {
                ...first.items.map((p) => p.id.value),
                ...second.items.map((p) => p.id.value),
              }.length ==
              4,
    );
    final replacement = await r.saveProfile(
      fixtureProfile(DiagnosticOperation.listen),
      id: ids['send'],
      session: 9,
    );
    check(replacement.operation == DiagnosticOperation.listen);
    await r.saveProfile(
      fixtureProfile(DiagnosticOperation.send),
      id: ids['send'],
      session: 9,
    );
    await r.saveSettings(
      AppSettings(
        defaultProfileId: LocalId(ids['send']!),
        diagnosticHistoryLimit: 1,
      ),
    );
    for (final op in DiagnosticOperation.values) {
      final request = switch (op) {
        DiagnosticOperation.send => SendParameterRequest(
          profileId: LocalId(ids[op.name]!),
          payload: [],
        ),
        DiagnosticOperation.listen => ListenParameterRequest(
          profileId: LocalId(ids[op.name]!),
          overrides: const ListenOverrides(dataType: DataTypeOverride(null)),
        ),
        DiagnosticOperation.ping => PingParameterRequest(
          profileId: LocalId(ids[op.name]!),
          content: [],
        ),
        DiagnosticOperation.respond => RespondParameterRequest(
          profileId: LocalId(ids[op.name]!),
        ),
      };
      final result = await r.resolveParameters(request);
      check(result.profileId?.value == ids[op.name] && result.operation == op);
    }
    final inherited = await r.resolveParameters(
      SendParameterRequest(
        payload: [],
        overrides: const SendOverrides(sendChannelIndex: 0),
      ),
    );
    check(
      inherited.profileId?.value == ids['send'] && inherited.content!.isEmpty,
    );
    try {
      await r.resolveParameters(
        SendParameterRequest(
          payload: [],
          overrides: SendOverrides(route: RouteOverrides(routeDescriptor: 255)),
        ),
      );
      check(false);
    } on RuntimeFault catch (e) {
      check(e.code == 'invalid_input');
    }
    final flood = await r.resolveParameters(
      SendParameterRequest(
        payload: [],
        overrides: SendOverrides(
          route: RouteOverrides(routeDescriptor: 255, path: []),
        ),
      ),
    );
    check((flood.parameters as SendProfileParameters).route.path.isEmpty);
    await r.deleteProfile(ids['send']!);
    final settings = await r.readSettings();
    check(
      settings.defaultProfileId == null && settings.diagnosticHistoryLimit == 1,
    );
    await r.saveSettings(
      AppSettings(
        defaultProfileId: LocalId(ids['listen']!),
        diagnosticHistoryLimit: 100000,
      ),
    );
    final restored = await r.restoreSettings();
    check(
      restored.defaultProfileId == null &&
          restored.diagnosticHistoryLimit == 1000,
    );
    receipt.writeAsStringSync(jsonEncode(ids));
    stdout.writeln(jsonEncode({'ready': true, 'fixtureWrites': false}));
    await stdout.flush();
    await stdin.first;
  } else if (mode == 'read') {
    final ids = jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
    check((await r.listProfiles()).items.length == 3);
    for (final op in DiagnosticOperation.values.skip(1)) {
      final p = await r.readProfile(ids[op.name] as String);
      check(
        p.operation == op &&
            p.portHint == 'fixture hint\n' &&
            p.parameters.budgets.taskTimeoutSeconds == 7,
      );
    }
    final s = await r.readSettings();
    check(s.defaultProfileId == null && s.diagnosticHistoryLimit == 1000);
  } else if (mode == 'unknown') {
    final creating = r.saveProfile(
      fixtureProfile(DiagnosticOperation.send),
      session: 1,
    );
    final permit = await r.beginDraftDecision(1, target: EditorTarget.profile);
    try {
      await creating;
      check(false);
    } on RuntimeFault catch (e) {
      check(e.host == CoordinationFault.requestUnknown);
    }
    try {
      await r.saveProfile(
        fixtureProfile(DiagnosticOperation.send),
        session: 1,
        decision: permit,
      );
      check(false);
    } on RuntimeFault catch (e) {
      check(e.host == CoordinationFault.requestUnknown);
    }
  } else {
    check((await r.listProfiles()).items.length == 1);
  }
  final close = await r.shutdown();
  check(close.canExit && r.pendingCount == 0 && r.openPortCount == 0);
  stdout.writeln(
    jsonEncode({
      'passed': true,
      'mode': mode,
      'released': close.resourcesReleased,
      'workerExited': close.workerExited,
      'pending': r.pendingCount,
      'ports': r.openPortCount,
    }),
  );
}
