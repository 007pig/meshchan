import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';

class HistoryControl implements DiagnosticHistory {
  HistoryControl(this.inner);
  final DiagnosticHistory inner;
  final execution = Completer<HistoryMaintenanceReport>();
  HistoryMaintenanceReport? failure;
  int count = 0, acks = 0;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
  @override
  HistoryMaintenanceReport? get latestMaintenance => inner.latestMaintenance;
  @override
  HistoryMaintenanceReport? get unacknowledgedFailure => failure;
  @override
  int get unacknowledgedFailureCount => count;
  @override
  void acknowledgeMaintenanceFailures() {
    acks++;
    failure = null;
    count = 0;
  }

  @override
  Future<HistoryMaintenanceReport> maintain() => execution.future;
  @override
  Future<HistoryMaintenanceReport> waitForMaintenance() =>
      inner.waitForMaintenance();
}

class StorageControl implements CoreStorage {
  StorageControl(this.inner) : history = HistoryControl(inner.history);
  final CoreStorage inner;
  @override
  final HistoryControl history;
  @override
  StorageState get state => inner.state;
  @override
  Future<void> close() => inner.close();
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

Future<void> until(bool Function() condition) async {
  while (!condition()) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('long maintenance fast ACK, status/Stop responsive, close drains action; revision protects unseen failures', () async {
    final dir = await Directory.systemTemp.createTemp(
      'meshchan-history-worker-',
    );
    final storage = StorageControl(await CoreStorage.open(dataDirectory: dir));
    final port = ReceivePort(), events = <WorkerEvent>[];
    final worker = WorkerDispatcher(
      WorkerBootstrap(7, dir.path, port.sendPort),
      send: events.add,
      finish: () {},
      openStorage: (_) async => storage,
      enumeratePorts: () => throw StateError('must stay offline'),
      createDiagnosticTransport: (_) => throw StateError('must stay offline'),
    );
    worker.start();
    await until(() => worker.snapshot.phase == RuntimePhase.ready);
    var id = 0;
    Future<RequestReply> send(RuntimeRequest q) async {
      final current = ++id;
      worker.receive(RequestEnvelope(7, current, q));
      await until(
        () => events.whereType<RequestReply>().any((r) => r.id == current),
      );
      return events.whereType<RequestReply>().firstWhere(
        (r) => r.id == current,
      );
    }

    void fail() {
      storage.history.failure = const HistoryMaintenanceReport(
        state: HistoryMaintenanceState.failed,
        deletedCount: 128,
        historyLimit: null,
        error: CoreException(CoreErrorCode.storageReadFailed),
      );
      storage.history.count++;
    }

    fail();
    await send(const ReadMaintenanceStatus());
    final seen = worker.snapshot.maintenance!;
    fail();
    final stale = await send(
      AcknowledgeMaintenance(7, seen.revision, seen.failureCount),
    );
    expect(stale.error!.host, CoordinationFault.staleRequest);
    expect(storage.history.acks, 0);
    final current = worker.snapshot.maintenance!;
    await send(
      AcknowledgeMaintenance(7, current.revision, current.failureCount),
    );
    expect(storage.history.acks, 1);
    // Same count and error after clear is a new failure identity/revision.
    fail();
    await send(const ReadMaintenanceStatus());
    expect(
      worker.snapshot.maintenance!.revision,
      greaterThan(current.revision),
    );
    expect(
      (await send(
        AcknowledgeMaintenance(6, worker.snapshot.maintenance!.revision, 1),
      )).error!.host,
      CoordinationFault.staleRequest,
    );
    expect((await send(const StartMaintenance(1))).value, isA<Accepted>());
    expect(worker.snapshot.maintenanceAction!.done, false);
    expect((await send(const GetStatus())).value, isA<StatusValue>());
    await send(const PauseAdmission());
    for (final q in <HistoryRequest>[
      const QueryHistory(HistorySelection()),
      ReadHistory('0' * 32),
      DeleteHistory('0' * 32),
      const ExportHistoryPage(HistorySelection()),
      const ReadMaintenanceStatus(),
      const StartMaintenance(2),
      const AcknowledgeMaintenance(7, 1, 1),
    ]) {
      expect((await send(q)).error!.host, CoordinationFault.stopped);
    }
    await send(const StopRuntime());
    worker.receive(RequestEnvelope(7, ++id, const ShutdownRuntime()));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<ReleaseReport>(), isEmpty);
    storage.history.execution.complete(
      const HistoryMaintenanceReport(
        state: HistoryMaintenanceState.failed,
        deletedCount: 128,
        historyLimit: null,
        error: CoreException(CoreErrorCode.storageReadFailed),
      ),
    );
    await until(() => events.whereType<ReleaseReport>().isNotEmpty);
    expect(events.whereType<ReleaseReport>().last.resourcesReleased, true);
    expect(worker.snapshot.maintenanceAction!.report!.deletedCount, 128);
    expect(worker.snapshot.maintenanceAction!.done, true);
    expect(worker.snapshot.maintenance!.failureCount, 1);
    port.close();
    await dir.delete(recursive: true);
  });
}
