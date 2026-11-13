import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/launch_configuration.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';

void main() {
  test('actual future schema and corrupt fixtures fail safely without replacing bytes', () async {
    for (final future in [true, false]) {
      final dir = Directory.systemTemp.createTempSync(
        'meshchan-runtime-invalid-',
      );
      final file = File('${dir.path}/meshchan.sqlite');
      if (future) {
        final storage = await CoreStorage.open(dataDirectory: dir);
        await storage.close();
        final bytes = file.readAsBytesSync();
        bytes[60] = 0;
        bytes[61] = 0;
        bytes[62] = 0;
        bytes[63] = 2;
        file.writeAsBytesSync(bytes, flush: true);
      } else {
        file.writeAsStringSync('Controlled corrupt SQLite fixture');
      }
      final before = file.readAsBytesSync();
      final runtime = RuntimeController(resolveDirectory: () async => dir.path);
      await runtime.start();
      expect(
        runtime.snapshot.error!.core,
        future
            ? CoreErrorCode.unsupportedDatabaseVersion
            : CoreErrorCode.databaseCorrupt,
      );
      expect(runtime.snapshot.owner, OwnerFact.none);
      expect((await runtime.shutdown()).canExit, true);
      expect(file.readAsBytesSync(), before);
      dir.deleteSync(recursive: true);
    }
  });
  test('stale snapshots, reversed reads and duplicate replies preserve newest facts', () async {
    final runtime = RuntimeController(
      resolveDirectory: () async => '/unused',
      entry: orderedEntry,
    );
    await runtime.start();
    final reads = await Future.wait([runtime.refresh(), runtime.refresh()]);
    expect(reads.map((r) => r.historyLimit), [11, 22]);
    expect(runtime.offline!.historyLimit, 22);
    expect(runtime.snapshot.phase, RuntimePhase.stopping);
    expect(runtime.snapshot.sequence, 5);
    expect(runtime.pendingCount, 0);
    expect((await runtime.shutdown()).canExit, true);
    expect(runtime.openPortCount, 0);
  });
  test('synchronous admission holds a lease through resolution and old cancel cannot reach a newer lease', () async {
    final s = FakeStorage();
    final events = <WorkerEvent>[];
    final d = WorkerDispatcher(
      WorkerBootstrap(3, '/unused', unusedPort()),
      send: events.add,
      finish: () {},
      openStorage: (_) async => s,
    );
    d.start();
    await until(() => d.snapshot.phase == RuntimePhase.ready);
    final resolve = Completer<EffectiveParameters>();
    var factories = 0, resolves = 0;
    final work = d.startRecording(
      resolve: (_) {
        resolves++;
        return resolve.future;
      },
      createTransport: () {
        factories++;
        throw StateError('Must never construct');
      },
    );
    expect(d.snapshot.gate, DeviceGateState.occupied);
    expect(
      () => d.startRecording(
        resolve: (_) async {
          throw StateError('Not admitted');
        },
        createTransport: () {
          throw StateError('Not admitted');
        },
      ),
      throwsA(isA<RuntimeFault>()),
    );
    await until(() => resolves == 1);
    d.receive(const RequestEnvelope(3, 1, GetStatus()));
    d.receive(const RequestEnvelope(3, 2, CancelOperation(1)));
    expect(events.whereType<RequestReply>().length, 2);
    resolve.complete(
      EffectiveParameters(
        profileId: null,
        parameters: ListenProfileParameters(
          budgets: const ProfileBudgets(taskTimeoutSeconds: 5),
          receiveChannelIndex: 0,
          listenDurationSeconds: 1,
          maxEntries: 1,
        ),
      ),
    );
    await work;
    expect(factories, 0);
    expect(d.snapshot.stopApplied, true);
    d.receive(const RequestEnvelope(3, 3, ResumeAdmission()));
    final secondResolve = Completer<EffectiveParameters>();
    final second = d.startRecording(
      resolve: (_) => secondResolve.future,
      createTransport: () => throw StateError('No device'),
    );
    d.receive(const RequestEnvelope(3, 4, CancelOperation(1)));
    expect(
      events.whereType<RequestReply>().last.error!.host,
      CoordinationFault.staleRequest,
    );
    expect(d.snapshot.stopReceived, false);
    d.receive(const RequestEnvelope(3, 5, StopRuntime()));
    secondResolve.completeError(
      const CoreException(CoreErrorCode.storageReadFailed),
    );
    // Stop is checked before resolve; keep the independent future observed too.
    unawaited(
      secondResolve.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace s) {},
      ),
    );
    await second;
    d.receive(const RequestEnvelope(3, 6, ShutdownRuntime()));
    await until(() => events.whereType<ReleaseReport>().isNotEmpty);
  });
  test('late sticky maintenance failure survives actual close and does not claim native connection', () async {
    final s = FakeStorage();
    final events = <WorkerEvent>[];
    s.history.unacknowledgedFailureCount = 2;
    s.history.unacknowledgedFailure = HistoryMaintenanceReport(
      state: HistoryMaintenanceState.failed,
      deletedCount: 0,
      historyLimit: null,
      error: const CoreException(CoreErrorCode.storageWriteFailed),
    );
    s.history.latestMaintenance = HistoryMaintenanceReport(
      state: HistoryMaintenanceState.completed,
      deletedCount: 0,
      historyLimit: 1000,
    );
    final d = WorkerDispatcher(
      WorkerBootstrap(1, '/unused', unusedPort()),
      send: events.add,
      finish: () {},
      openStorage: (_) async => s,
    );
    d.start();
    await until(() => d.snapshot.phase == RuntimePhase.ready);
    d.receive(const RequestEnvelope(1, 1, ShutdownRuntime()));
    await until(() => events.whereType<ReleaseReport>().isNotEmpty);
    expect(d.snapshot.owner, OwnerFact.released);
    expect(d.snapshot.maintenance!.failureCount, 2);
    expect(d.snapshot.maintenance!.latest, HistoryMaintenanceState.completed);
    expect(d.snapshot.maintenance!.failure, CoreErrorCode.storageWriteFailed);
  });
  test('pure startup validation preserves modes and rejects ambiguity', () {
    expect(LaunchConfiguration.parse([]).mode, LaunchMode.normal);
    expect(
      LaunchConfiguration.parse(['--data-dir=/private/tmp/owned']).directory,
      '/private/tmp/owned',
    );
    expect(
      LaunchConfiguration.parse([
        '--meshchan-native-test',
      ], nativeTestHost: true).mode,
      LaunchMode.nativeTest,
    );
    for (final args in [
      <String>[],
      ['--data-dir=/private/tmp/owned'],
    ]) {
      expect(
        () => LaunchConfiguration.parse(args, nativeTestHost: true),
        throwsFormatException,
      );
    }
    for (final args in [
      ['--data-dir='],
      ['--data-dir=relative'],
      ['--data-dir=/a\u0000b'],
      ['--data-dir=/a/../b'],
      ['--data-dir=/a', '--data-dir=/b'],
      ['--runtime-exit'],
      ['--fixture=/a'],
      ['--enumerate-serial'],
      ['--meshchan-native-test'],
      ['--unknown'],
      [
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '-NSDocumentRevisionsDebugMode',
        'NO',
      ],
      ['--meshchan-runtime=read', '--data-dir=/private/tmp/not-a-fixture'],
      [
        '--meshchan-probe=read',
        '--fixture=/private/tmp/meshchan-1d2-test',
        '--data-dir=/a',
      ],
      [
        '--meshchan-runtime=write',
        '--data-dir=/private/tmp/meshchan-1d3-test',
        '--probe-exit',
      ],
    ]) {
      expect(
        () => LaunchConfiguration.parse(args),
        throwsFormatException,
        reason: '$args',
      );
    }
  });

  test('one actual isolate serves correlated reads and commit, then releases all client ports', () async {
    final dir = Directory.systemTemp.createTempSync('meshchan-runtime-');
    final runtime = RuntimeController(
      resolveDirectory: () async => dir.path,
      fixtureWrites: true,
    );
    final firstStart = runtime.start();
    expect(identical(firstStart, runtime.start()), true);
    await firstStart;
    expect(runtime.snapshot.owner, OwnerFact.held);
    final created =
        await runtime.request(const CreateFixtureDraft()) as DraftValue;
    expect(created.draft.body, runtimeFixtureBody);
    final pages = await Future.wait([runtime.refresh(), runtime.refresh()]);
    expect(pages.every((p) => p.drafts.single.id == created.draft.id), true);
    expect(() => pages.first.drafts.clear(), throwsUnsupportedError);
    await expectLater(
      CoreStorage.open(dataDirectory: dir),
      throwsA(
        isA<CoreException>().having(
          (e) => e.code,
          'busy',
          CoreErrorCode.dataDirectoryBusy,
        ),
      ),
    );
    final close = runtime.shutdown();
    expect(identical(close, runtime.shutdown()), true);
    expect((await close).canExit, true);
    expect(runtime.snapshot.workerExited, true);
    expect(runtime.pendingCount, 0);
    expect(runtime.openPortCount, 0);
    final reopened = await CoreStorage.open(dataDirectory: dir);
    final draft = await reopened.drafts.read(LocalId(created.draft.id));
    expect(draft.body, runtimeFixtureBody);
    expect(draft.revision, 1);
    await reopened.close();
    dir.deleteSync(recursive: true);
  });

  test('stop before directory resolution prevents any worker/open and drains queued controls', () async {
    final directory = Completer<String>();
    final runtime = RuntimeController(
      resolveDirectory: () => directory.future,
      entry: _mustNotSpawn,
    );
    final starting = runtime.start();
    final stop = runtime.stop();
    final observedStop = stop.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    final closing = runtime.shutdown();
    directory.complete('/never-opened');
    await starting;
    final result = await closing;
    expect(result.canExit, true);
    expect(result.workerWasSpawned, false);
    expect(result.workerExited, false);
    await observedStop;
    expect(runtime.snapshot.stopApplied, true);
    expect(runtime.pendingCount, 0);
  });

  test('worker fatal and unexpected exit terminate accepted pending requests without replacement', () async {
    for (final entry in [_fatalEntry, _exitEntry]) {
      final runtime = RuntimeController(
        resolveDirectory: () async => '/unused',
        entry: entry,
      );
      final request = runtime.request(const ReadOffline());
      final observed = expectLater(request, throwsA(isA<RuntimeFault>()));
      await runtime.start();
      await observed;
      expect(runtime.snapshot.phase, RuntimePhase.fault);
      expect(runtime.snapshot.owner, OwnerFact.unknown);
      expect(runtime.pendingCount, 0);
      expect((await runtime.shutdown()).canExit, false);
      // Fatal fixtures have no native resources; ports may be closed by the
      // test process, but production never interprets onExit as native release.
    }
  });

  test(
    'lost response is unknown and late values cannot resurrect a request',
    () async {
      final runtime = RuntimeController(
        resolveDirectory: () async => '/unused',
        entry: _lostEntry,
        deadline: const Duration(milliseconds: 100),
      );
      await runtime.start();
      await expectLater(
        runtime.request(const ReadOffline()),
        throwsA(
          isA<RuntimeFault>().having(
            (e) => e.host,
            'unknown',
            CoordinationFault.requestUnknown,
          ),
        ),
      );
      expect(runtime.pendingCount, 0);
      expect(runtime.snapshot.owner, OwnerFact.unknown);
      expect((await runtime.shutdown()).canExit, false);
    },
  );

  test(
    'dispatcher controls bypass an outstanding open and honor early stop',
    () async {
      final storage = FakeStorage();
      final open = Completer<CoreStorage>();
      final events = <WorkerEvent>[];
      final d = WorkerDispatcher(
        WorkerBootstrap(5, '/unused', unusedPort()),
        send: events.add,
        finish: () {},
        openStorage: (_) => open.future,
      );
      d.start();
      await eventTurn();
      d.receive(const RequestEnvelope(5, 1, StopRuntime()));
      d.receive(const RequestEnvelope(5, 2, GetStatus()));
      expect(events.whereType<RequestReply>().length, 2);
      expect(d.snapshot.stopReceived, true);
      expect(d.snapshot.stopApplied, false);
      open.complete(storage);
      await until(() => d.snapshot.stopApplied);
      expect(d.snapshot.owner, OwnerFact.held);
      d.receive(const RequestEnvelope(5, 3, ShutdownRuntime()));
      await until(() => events.whereType<ReleaseReport>().isNotEmpty);
      expect(storage.closes, 1);
    },
  );

  test('initial query failure keeps the single open owner; accepted DB work drains before one close', () async {
    final storage = FakeStorage();
    final read = Completer<AppSettings>();
    storage.settings.result = read.future;
    final events = <WorkerEvent>[];
    var opens = 0;
    final d = WorkerDispatcher(
      WorkerBootstrap(1, '/unused', unusedPort()),
      send: events.add,
      finish: () {},
      openStorage: (_) async {
        opens++;
        return storage;
      },
    );
    d.start();
    await until(() => d.snapshot.phase == RuntimePhase.ready);
    d.receive(const RequestEnvelope(1, 1, ReadOffline()));
    await eventTurn();
    d.receive(const RequestEnvelope(1, 2, GetStatus()));
    expect(events.whereType<RequestReply>().single.id, 2);
    d.receive(const RequestEnvelope(1, 3, ShutdownRuntime()));
    d.receive(const RequestEnvelope(1, 4, ResumeAdmission()));
    expect(storage.closes, 0);
    read.completeError(const CoreException(CoreErrorCode.storageReadFailed));
    await until(() => events.whereType<ReleaseReport>().isNotEmpty);
    expect(opens, 1);
    expect(storage.closes, 1);
    expect(
      events.whereType<RequestReply>().firstWhere((e) => e.id == 1).error!.core,
      CoreErrorCode.storageReadFailed,
    );
    expect(events.whereType<ReleaseReport>().single.resourcesReleased, true);
  });

  test('duplicate/stale requests do not execute, pause can resume only before close', () async {
    final s = FakeStorage();
    final events = <WorkerEvent>[];
    final d = WorkerDispatcher(
      WorkerBootstrap(2, '/unused', unusedPort()),
      send: events.add,
      finish: () {},
      openStorage: (_) async => s,
    );
    d.start();
    await until(() => d.snapshot.phase == RuntimePhase.ready);
    d.receive(const RequestEnvelope(2, 1, PauseAdmission()));
    expect(d.snapshot.admissionPaused, true);
    d.receive(const RequestEnvelope(2, 2, ResumeAdmission()));
    expect(d.snapshot.admissionPaused, false);
    d.receive(const RequestEnvelope(2, 2, ReadOffline()));
    d.receive(const RequestEnvelope(1, 3, ReadOffline()));
    expect(
      events.whereType<RequestReply>().where((e) => e.error != null).length,
      2,
    );
    expect(s.settings.reads, 0);
    d.receive(const RequestEnvelope(2, 3, ShutdownRuntime()));
    await until(() => events.whereType<ReleaseReport>().isNotEmpty);
  });

  test(
    'open cleanup ambiguity and closeUnconfirmed remain quarantined',
    () async {
      for (final failOpen in [true, false]) {
        final s = FakeStorage()..unconfirmed = true;
        final events = <WorkerEvent>[];
        final d = WorkerDispatcher(
          WorkerBootstrap(1, '/unused', unusedPort()),
          send: events.add,
          finish: () => fail('Quarantine must retain control port'),
          openStorage: (_) async {
            if (failOpen) {
              throw const CoreException(
                CoreErrorCode.storageOpenFailed,
                cleanupUnconfirmed: true,
              );
            }
            return s;
          },
        );
        d.start();
        await until(() => d.snapshot.phase != RuntimePhase.opening);
        d.receive(const RequestEnvelope(1, 1, ShutdownRuntime()));
        await until(() => events.whereType<ReleaseReport>().isNotEmpty);
        expect(
          events.whereType<ReleaseReport>().single.resourcesReleased,
          false,
        );
        expect(d.snapshot.owner, OwnerFact.unknown);
        expect(s.closes, failOpen ? 0 : 1);
      }
    },
  );
}

void orderedEntry(WorkerBootstrap b) {
  final p = ReceivePort();
  final reads = <RequestEnvelope>[];
  b.events.send(WorkerHello(b.generation, p.sendPort));
  b.events.send(
    SnapshotEvent(
      b.generation,
      RuntimeSnapshot(
        generation: b.generation,
        sequence: 3,
        phase: RuntimePhase.ready,
        owner: OwnerFact.held,
      ),
    ),
  );
  p.listen((message) {
    if (message is ReleaseAcknowledged) {
      p.close();
      return;
    }
    if (message is! RequestEnvelope) return;
    if (message.request is ReadOffline) {
      reads.add(message);
      if (reads.length == 2) {
        b.events.send(
          SnapshotEvent(
            b.generation,
            RuntimeSnapshot(
              generation: b.generation,
              sequence: 5,
              phase: RuntimePhase.stopping,
              owner: OwnerFact.held,
            ),
          ),
        );
        b.events.send(
          SnapshotEvent(
            b.generation,
            RuntimeSnapshot(
              generation: b.generation,
              sequence: 4,
              phase: RuntimePhase.ready,
              owner: OwnerFact.held,
            ),
          ),
        );
        b.events.send(
          SnapshotEvent(
            b.generation - 1,
            RuntimeSnapshot(
              generation: b.generation - 1,
              sequence: 100,
              phase: RuntimePhase.fault,
            ),
          ),
        );
        for (final i in [1, 0, 0]) {
          b.events.send(
            RequestReply(
              b.generation,
              reads[i].id,
              value: OfflineSnapshot(null, (i + 1) * 11, [], null),
            ),
          );
        }
      }
    } else if (message.request is ShutdownRuntime) {
      b.events.send(
        ReleaseReport(
          b.generation,
          message.id,
          RuntimeSnapshot(
            generation: b.generation,
            sequence: 6,
            phase: RuntimePhase.closed,
            owner: OwnerFact.released,
          ),
          true,
        ),
      );
    } else {
      b.events.send(
        RequestReply(b.generation, message.id, value: const Accepted()),
      );
    }
  });
}

void _mustNotSpawn(WorkerBootstrap b) => throw StateError('Unexpected spawn');
void _fatalEntry(WorkerBootstrap b) => throw StateError('PRIVATE native error');
void _exitEntry(WorkerBootstrap b) {
  Isolate.exit();
}

void _lostEntry(WorkerBootstrap b) {
  final p = ReceivePort();
  b.events.send(WorkerHello(b.generation, p.sendPort));
  b.events.send(
    SnapshotEvent(
      b.generation,
      RuntimeSnapshot(
        generation: b.generation,
        phase: RuntimePhase.ready,
        owner: OwnerFact.held,
        sequence: 1,
      ),
    ),
  );
  p.listen((_) {
    p.close();
  }); // Exit without response or release proof.
  // Keep alive past the client deadline, then exit without claiming release.
  Timer(const Duration(milliseconds: 300), () {});
}

Future<void> eventTurn() => Future<void>.delayed(Duration.zero);
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 10000 && !ready(); i++) {
    await eventTurn();
  }
  expect(ready(), true, reason: 'Controlled boundary did not settle');
}

class FakeStorage implements CoreStorage {
  @override
  StorageState state = StorageState.open;
  @override
  final FakeSettings settings = FakeSettings();
  @override
  final FakeHistory history = FakeHistory();
  int closes = 0;
  bool unconfirmed = false;
  @override
  Future<void> close() async {
    closes++;
    state = unconfirmed ? StorageState.closeUnconfirmed : StorageState.closed;
    if (unconfirmed) {
      throw const CoreException(
        CoreErrorCode.storageWriteFailed,
        cleanupUnconfirmed: true,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class FakeSettings implements SettingsRepository {
  Future<AppSettings>? result;
  int reads = 0;
  @override
  Future<AppSettings> read() {
    reads++;
    return result ?? Future.value(AppSettings());
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class FakeHistory implements DiagnosticHistory {
  @override
  HistoryMaintenanceReport? latestMaintenance;
  @override
  HistoryMaintenanceReport? unacknowledgedFailure;
  @override
  int unacknowledgedFailureCount = 0;
  @override
  Future<HistoryMaintenanceReport> waitForMaintenance() async =>
      latestMaintenance ??
      HistoryMaintenanceReport(
        state: HistoryMaintenanceState.completed,
        deletedCount: 0,
        historyLimit: 1000,
      );
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

SendPort unusedPort() {
  final port = ReceivePort();
  final send = port.sendPort;
  port.close();
  return send;
}
