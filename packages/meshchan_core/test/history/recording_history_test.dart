import 'dart:async';
import 'dart:convert';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Future<void> sendOk(FakeCompanionTransport t) async {
  await until(() => t.sent.isNotEmpty);
  t.receive(deviceInfo());
  await until(() => t.sent.length == 2);
  t.receive(selfInfo());
  await until(() => t.sent.length == 3);
  t.receive([0]);
}

void main() {
  late Fixture f;
  setUp(() {
    f = Fixture();
  });
  tearDown(() => f.close());

  test('real intermediate terminal snapshot pins delete/prune until final cleanup save; unpin retries without sacrificing newer retained row', () async {
    final c = HistoryControl();
    final s = await f.open(
      control: c,
      clock: () => instant,
      runId: () => fixtureId(1),
    );
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await f.seed(s, [sample(2, time: instant.add(const Duration(days: 1)))]);
    final finalRead = Completer<void>(), release = Completer<void>();
    Future<void>? deletion;
    Future<HistoryMaintenanceReport>? pruning;
    var armed = false, terminalReads = 0;
    c.updated = (statement, args) {
      if (!armed &&
          statement.contains('stored_runs') &&
          args.any(
            (a) => a is String && a.contains('"aggregate":"succeeded"'),
          )) {
        armed = true;
        c.afterCommit = () {
          deletion = s.history.delete(fixtureId(1));
          // Attach error observation immediately while final saving is queued.
          deletion!.ignore();
          pruning = s.history.maintain();
        };
      }
    };
    c.selected = (statement, args, rows) async {
      if (statement.startsWith('SELECT') &&
          args.contains(fixtureId(1).value) &&
          rows.isNotEmpty &&
          rows.first['cleanup_json'] is String &&
          jsonDecode(rows.first['cleanup_json'] as String)['aggregate'] ==
              'succeeded') {
        terminalReads++;
        if (terminalReads == 3) {
          finalRead.complete();
          await release.future;
        }
      }
    };
    final t = FakeCompanionTransport();
    final op = s.record(
      parameters: input(DiagnosticOperation.send),
      appVersion: 'host',
      createTransport: () => t,
    );
    await op.prepared;
    await sendOk(t);
    try {
      await finalRead.future;
      expect(deletion, isNotNull);
      expect(pruning, isNotNull);
      await expectLater(deletion!, throwsA(coreError(CoreErrorCode.conflict)));
      final report = await pruning!;
      expect(report.state, HistoryMaintenanceState.deferred);
      expect(report.deferredCount, 1);
      expect(report.deletedCount, 0);
      expect(t.sent, hasLength(3));
    } finally {
      release.complete();
    }
    final result = await op.done;
    expect(result.fullySuccessful, isTrue);
    expect(result.cleanupSave.state, RecordingSaveState.committed);
    expect(result.cleanupSave.finalCleanup, isTrue);
    expect(
      (await s.history.waitForMaintenance()).state,
      HistoryMaintenanceState.completed,
    );
    expect(await f.ids(s), [fixtureId(2)]);
    expect(t.sent, hasLength(3));
  });

  test('recording commit stays successful when postcommit prune fails; no resends and sticky report survives unpin retry', () async {
    final c = HistoryControl();
    final s = await f.open(
      control: c,
      clock: () => instant,
      runId: () => fixtureId(2),
    );
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await f.seed(s, [
      sample(1, time: instant.subtract(const Duration(days: 1))),
    ]);
    c.failDelete = c.deletes + 1;
    final t = FakeCompanionTransport();
    final op = s.record(
      parameters: input(DiagnosticOperation.send),
      appVersion: 'host',
      createTransport: () => t,
    );
    await op.prepared;
    await sendOk(t);
    final result = await op.done;
    await s.history.waitForMaintenance();
    expect(result.fullySuccessful, isTrue);
    expect(
      result.saves.every((save) => save.state == RecordingSaveState.committed),
      isTrue,
    );
    expect(
      s.history.unacknowledgedFailure!.error,
      coreError(CoreErrorCode.storageWriteFailed),
    );
    expect(s.history.unacknowledgedFailureCount, greaterThanOrEqualTo(1));
    expect(t.sent, hasLength(3));
    expect(
      (await s.history.maintain()).state,
      HistoryMaintenanceState.completed,
    );
    expect(await f.ids(s), [fixtureId(2)]);
  });

  test('admitted recording and automatic maintenance survive close; owner stays until final prune commits', () async {
    final c = HistoryControl();
    final s = await f.open(
      control: c,
      clock: () => instant,
      runId: () => fixtureId(2),
    );
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await f.seed(s, [
      sample(1, time: instant.subtract(const Duration(days: 1))),
    ]);
    final native = Completer<void>(),
        entered = Completer<void>(),
        release = Completer<void>();
    final t = FakeCompanionTransport()..closing = () => native.future;
    final op = s.record(
      parameters: input(DiagnosticOperation.send),
      appVersion: 'host',
      createTransport: () => t,
    );
    await op.prepared;
    await sendOk(t);
    await op.logicalSaved;
    var closed = false;
    final closing = s.close().then((_) {
      closed = true;
    });
    c.afterWrite = (_) async {
      entered.complete();
      await release.future;
    };
    native.complete();
    await entered.future;
    await turns();
    expect(closed, isFalse);
    await expectLater(
      CoreStorage.open(dataDirectory: f.directory),
      throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
    );
    release.complete();
    await op.done;
    await closing;
    expect(s.state, StorageState.closed);
    final reopened = await f.open();
    expect(await f.ids(reopened), [fixtureId(2)]);
  });

  test('postregistration construction failure unpins and maintenance may delete old row', () async {
    final s = await f.open(clock: () => instant, runId: () => fixtureId(1));
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await f.seed(s, [sample(2, time: instant.add(const Duration(days: 1)))]);
    final op = s.record(
      parameters: input(DiagnosticOperation.send),
      appVersion: 'host',
      createTransport: () => throw StateError('PRIVATE CONSTRUCTION'),
    );
    final result = await op.done;
    expect(result.cleanupSave.state, RecordingSaveState.committed);
    await s.history.waitForMaintenance();
    expect(await f.ids(s), [fixtureId(2)]);
  });
}
