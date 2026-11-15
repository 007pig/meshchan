import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'diagnostic_fixture.dart';
import 'device_scenario.dart' show require, rejects, deviceState;

/// Test-only owned fixture: exclusively public APIs, no product seed options.
Future<void> main(List<String> args) async {
  final mode = args[0], directory = Directory(args[1]);
  if (mode == 'inspect') {
    final storage = await CoreStorage.open(dataDirectory: directory);
    final page = await storage.history.query(size: PageSize(200));
    final json = (await storage.history.exportSummary(size: PageSize(200)))
        .json;
    require(
      page.items.every((r) => r.recordState != DiagnosticRecordState.prepared),
      'recovery completed',
    );
    await storage.close();
    stdout.writeln(
      jsonEncode({
        'passed': true,
        'runs': page.items.length,
        'summary': jsonDecode(json),
      }),
    );
    return;
  }
  if (mode == 'seed' || mode.startsWith('crash-')) {
    final storage = await CoreStorage.open(dataDirectory: directory);
    await storage.drafts.create(
      DraftContent(title: 'Unrelated draft', body: 'preserved'),
    );
    if (mode == 'seed') {
      final requests = <EffectiveParameterRequest>[
        SendParameterRequest(
          payload: const [83, 69, 67, 82, 69, 84],
          overrides: SendOverrides(
            budgets: const BudgetOverrides(taskTimeoutSeconds: 10),
            sendChannelIndex: 0,
            dataType: 1,
            route: RouteOverrides(routeDescriptor: 255),
          ),
        ),
        ListenParameterRequest(
          overrides: ListenOverrides(
            budgets: const BudgetOverrides(taskTimeoutSeconds: 10),
            receiveChannelIndex: 0,
            listenDurationSeconds: 1,
          ),
        ),
        diagnosticRequest(),
        diagnosticRequest(respond: true),
      ];
      for (final request in requests) {
        final op = storage.record(
          parameters: await storage.resolveParameters(request),
          appVersion: 'fixture',
          createTransport: () => throw StateError('canceled before factory'),
        );
        op.cancel().ignore();
        await op.done;
      }
      await storage.close();
      stdout.writeln(jsonEncode({'passed': true, 'runs': 4}));
      return;
    }
    final blocker = Completer<void>();
    final op = storage.record(
      parameters: await storage.resolveParameters(diagnosticRequest()),
      appVersion: 'fixture',
      createTransport: () => InterruptedHistoryTransport(
        blocker,
        prepared: mode == 'crash-prepared',
      ),
    );
    if (mode == 'crash-prepared') {
      await op.prepared;
    } else {
      await op.logicalSaved;
    }
    stdout.writeln(jsonEncode({'barrier': mode}));
    await stdout.flush();
    await blocker.future;
    return; // Parent terminates only this owned process.
  }
  final observer = ReceivePort();
  final ready = Completer<SendPort>();
  final subscription = observer.listen((e) {
    if (e is DiagnosticReady) ready.complete(e.port);
  });
  final runtime = RuntimeController(
    resolveDirectory: () async => directory.path,
    entry: diagnosticFixtureEntry(observer.sendPort, holdCleanup: true),
  );
  await runtime.start();
  final control = await ready.future;
  final first = (await runtime.historyRequest(
    const QueryHistory(HistorySelection(size: 2)),
  )) as HistoryPageValue;
  require(
    first.page.items.length == 2 && first.page.nextCursor != null,
    'bounded page',
  );
  final target = first.page.items.last.runId;
  await runtime.historyRequest(ReadHistory(target.value));
  final exported = (await runtime.historyRequest(
    ExportHistoryPage(HistorySelection(size: 2, after: first.page.nextCursor)),
  )) as HistoryExportValue;
  require(
    (jsonDecode(exported.page.json)['runs'] as List).length == 2 &&
        exported.page.nextCursor == null,
    'page input cursor and full terminal page',
  );
  await runtime.historyRequest(DeleteHistory(target.value));
  final continued = await runtime.historyRequest(
    QueryHistory(HistorySelection(size: 2, after: first.page.nextCursor)),
  ) as HistoryPageValue;
  require(
    continued.page.items.length == 2,
    'continuation survives deleted cursor row',
  );
  final instant = first.page.items.first.preparedAt;
  final bounded = await runtime.historyRequest(
    QueryHistory(
      HistorySelection(
        filter: HistoryQuery(
          preparedFromInclusive: instant,
          preparedUntilExclusive: instant.add(const Duration(microseconds: 1)),
        ),
      ),
    ),
  ) as HistoryPageValue;
  require(
    bounded.page.items.single.preparedAt == instant,
    'real half-open UTC boundary',
  );
  await rejects(runtime.historyRequest(ReadHistory(target.value)));
  final handle = runtime.startRecordedDiagnostic(
    ' explicit fixture ',
    diagnosticRequest(),
  );
  await handle.accepted;
  await deviceState(runtime, (s) => s.operation?.logical != null);
  require(runtime.snapshot.gate == DeviceGateState.occupied, 'held recording');
  final offline = await runtime.historyRequest(
    const QueryHistory(HistorySelection(size: 200)),
  ) as HistoryPageValue;
  require(offline.page.items.length == 4, 'offline during recording');
  await rejects(
    runtime.historyRequest(DeleteHistory(runtime.snapshot.operation!.runId!)),
  );
  final requests = <HistoryRequest>[
    const QueryHistory(HistorySelection()),
    ReadHistory(target.value),
    DeleteHistory(target.value),
    const ExportHistoryPage(HistorySelection()),
    const ReadMaintenanceStatus(),
    const StartMaintenance(1),
    AcknowledgeMaintenance(runtime.generation, 0, 0),
  ];
  await runtime.pauseAdmission();
  for (final q in requests) {
    await rejects(runtime.historyRequest(q));
  }
  await runtime.resumeAdmission();
  await runtime.historyRequest(const StartMaintenance(2));
  await runtime.request(const GetStatus());
  await runtime.cancelRecordedDiagnostic(handle);
  final closing = runtime.shutdown();
  await runtime.request(const GetStatus());
  for (final q in requests) {
    await rejects(runtime.historyRequest(q));
  }
  control.send(DiagnosticControl.releaseCleanup);
  require((await closing).canExit, 'drain recording/maintenance/owner/worker');
  await subscription.cancel();
  observer.close();
  final storage = await CoreStorage.open(dataDirectory: directory);
  require(
    (await storage.history.query(size: PageSize(200))).items.length == 4,
    'committed delete and recording',
  );
  require(
    (await storage.drafts.list()).items.single.title == 'Unrelated draft',
    'draft survives',
  );
  await storage.settings.save(AppSettings(diagnosticHistoryLimit: 1));
  final maintenance = await storage.history.waitForMaintenance();
  require(
    maintenance.state == HistoryMaintenanceState.completed,
    'real retention',
  );
  require((await storage.history.query()).items.length == 1, 'retention exact');
  await storage.close();
  stdout.writeln(jsonEncode({'passed': true, 'runs': 1, 'hardware': false}));
}

class InterruptedHistoryTransport extends DiagnosticFixtureTransport {
  InterruptedHistoryTransport(this.barrier, {required this.prepared})
    : super(closeBarrier: prepared ? null : barrier);
  final Completer<void> barrier;
  final bool prepared;
  @override
  Future<void> open() async {
    if (prepared) await barrier.future;
    await super.open();
  }
}
