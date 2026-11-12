import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/recording/projection.dart';
import 'package:meshchan_core/src/recording/run_store.dart';
import 'package:meshchan_core/src/recording/validation.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:test/test.dart';

import '../repositories/draft_repository_test.dart' show Control;
import 'support.dart';

const logical = SendSummary(
  reason: LogicalReason.completed,
  stage: DiagnosticStage.sending,
  send: SendFacts(
    attempted: true,
    pendingAtTermination: false,
    deviceAcceptanceConfirmed: true,
    dispatched: true,
    localWriteCompleted: true,
    localOkObserved: true,
  ),
);
final noWork = CleanupScopeSummary(state: CleanupState.notRequired);
final succeeded = CleanupScopeSummary(state: CleanupState.succeeded);
const failedItem = FailureSummary(
  domain: FailureDomain.host,
  kind: FailureKind.cleanup,
  hostCleanupStage: HostCleanupStage.signalSubscription,
);
void main() {
  late Directory directory;
  final handles = <CoreStorage>[];
  Future<StorageHandle> open({
    StorageHooks hooks = const StorageHooks(),
  }) async {
    final s = await openStorage(directory, hooks: hooks) as StorageHandle;
    handles.add(s);
    return s;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meshchan-run-write-');
  });
  tearDown(() async {
    for (final s in handles.reversed) {
      await s.close();
    }
    handles.clear();
    directory.deleteSync(recursive: true);
  });

  test('canonical final facts no-op keeps first time; conflicting facts and absent run fail safely', () async {
    final s = await open();
    await s.useDatabase((db) async {
      final store = RunStore(db, clock: () => instant);
      final prepared = await store.register(
        appVersion: 'v',
        configuration: projectConfiguration(input(DiagnosticOperation.send)),
        profileId: null,
        hostRequired: false,
      );
      final first = await store.saveLogical(prepared.runId, logical, instant);
      final second = await store.saveLogical(
        prepared.runId,
        const SendSummary(
          reason: LogicalReason.completed,
          stage: DiagnosticStage.sending,
          send: SendFacts(
            attempted: true,
            pendingAtTermination: false,
            deviceAcceptanceConfirmed: true,
            dispatched: true,
            localWriteCompleted: true,
            localOkObserved: true,
          ),
        ),
        instant.add(const Duration(days: 1)),
      );
      expect(second.logicalEndedAt, first.logicalEndedAt);
      await expectLater(
        store.saveLogical(
          prepared.runId,
          const SendSummary(
            reason: LogicalReason.canceled,
            stage: DiagnosticStage.sending,
          ),
          instant,
        ),
        throwsA(coreError(CoreErrorCode.conflict)),
      );
      await expectLater(
        store.saveCleanup(fixtureId(999), core: succeeded),
        throwsA(coreError(CoreErrorCode.notFound)),
      );
      final saved = await store.saveCleanup(prepared.runId, core: succeeded);
      expect(saved.result!.reason, LogicalReason.completed);
      expect(saved.cleanup.aggregate, CleanupState.succeeded);
      final again = await store.saveLogical(
        prepared.runId,
        logical,
        instant.subtract(const Duration(days: 1)),
      );
      expect(again.cleanup.aggregate, CleanupState.succeeded);
    });
  });

  test('cumulative cleanup snapshots preserve duplicate source failures and forbid terminal regression', () async {
    final s = await open();
    await s.useDatabase((db) async {
      final store = RunStore(db, clock: () => instant);
      final p = await store.register(
        appVersion: 'v',
        configuration: projectConfiguration(input(DiagnosticOperation.send)),
        profileId: null,
        hostRequired: true,
      );
      final pending = CleanupScopeSummary(
        state: CleanupState.pending,
        failures: [failedItem, failedItem],
      );
      final a = await store.saveCleanup(
        p.runId,
        core: succeeded,
        host: pending,
      );
      expect(a.recordState, DiagnosticRecordState.prepared);
      expect(a.cleanup.aggregate, CleanupState.pending);
      final b = await store.saveCleanup(
        p.runId,
        host: CleanupScopeSummary(
          state: CleanupState.pending,
          failures: [failedItem, failedItem],
        ),
      );
      expect(b.cleanup.hostSubscriptions.failureCount, 2);
      await store.saveLogical(p.runId, logical, instant);
      final finalHost = CleanupScopeSummary(
        state: CleanupState.failed,
        failures: [failedItem, failedItem],
      );
      await store.saveCleanup(p.runId, host: finalHost);
      final c = await store.saveCleanup(
        p.runId,
        host: CleanupScopeSummary(
          state: CleanupState.failed,
          failures: [failedItem, failedItem],
        ),
      );
      expect(c.cleanup.aggregate, CleanupState.failed);
      expect(c.cleanup.hostSubscriptions.failureCount, 2);
      for (final next in [
        pending,
        succeeded,
        noWork,
        CleanupScopeSummary(state: CleanupState.failed, failures: [failedItem]),
      ]) {
        await expectLater(
          store.saveCleanup(p.runId, host: next),
          throwsA(coreError(CoreErrorCode.conflict)),
        );
      }
    });
  });

  test('run ID collision retries only run_id, at most eight, without touching protocol nonce', () async {
    final s = await open();
    await s.useDatabase((db) async {
      var ids = 0;
      final store = RunStore(
        db,
        generateId: () {
          ids++;
          return fixtureId(1);
        },
        clock: () => instant,
      );
      await store.register(
        appVersion: 'v',
        configuration: projectConfiguration(input(DiagnosticOperation.send)),
        profileId: null,
        hostRequired: false,
      );
      await expectLater(
        store.register(
          appVersion: 'v',
          configuration: projectConfiguration(input(DiagnosticOperation.send)),
          profileId: null,
          hostRequired: false,
        ),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      expect(ids, 9);
      expect(await db.select(db.storedRuns).get(), hasLength(1));
      var tries = 0;
      final retry = RunStore(
        db,
        generateId: () => fixtureId(++tries == 1 ? 1 : 2),
        clock: () => instant,
      );
      final p = await retry.register(
        appVersion: 'v',
        configuration: projectConfiguration(input(DiagnosticOperation.send)),
        profileId: null,
        hostRequired: false,
      );
      expect(tries, 2);
      expect(p.runId, fixtureId(2));
    });
  });

  for (final phase in ['logical', 'cleanup']) {
    for (final fault in ['write', 'commit', 'select']) {
      test(
        '$phase $fault failure rolls back immediately; queue accepts the next safe write',
        () async {
          final control = Control(readTable: 'stored_runs');
          final s = await open(
            hooks: StorageHooks(
              executorFactory: (file) =>
                  NativeDatabase(file).interceptWith(control),
            ),
          );
          await s.useDatabase((db) async {
            final store = RunStore(db, clock: () => instant);
            final p = await store.register(
              appVersion: 'v',
              configuration: projectConfiguration(
                input(DiagnosticOperation.send),
              ),
              profileId: null,
              hostRequired: true,
            );
            if (fault == 'write') {
              control.afterWrite = (_) async {
                throw StateError('PRIVATE');
              };
            }
            if (fault == 'commit') {
              control.beforeCommit = () async {
                throw StateError('PRIVATE');
              };
            }
            if (fault == 'select') control.readFailure = StateError('PRIVATE');
            await expectLater(
              phase == 'logical'
                  ? store.saveLogical(p.runId, logical, instant)
                  : store.saveCleanup(p.runId, core: succeeded, host: noWork),
              throwsA(coreError(CoreErrorCode.storageWriteFailed)),
            );
            final unchanged = await readRun(db, p.runId);
            expect(unchanged.recordState, DiagnosticRecordState.prepared);
            expect(unchanged.cleanup.aggregate, CleanupState.unconfirmed);
            await store.saveLogical(p.runId, logical, instant);
            final next = await store.saveCleanup(
              p.runId,
              core: succeeded,
              host: noWork,
            );
            expect(next.cleanup.aggregate, CleanupState.succeeded);
            expect(next.recordState, DiagnosticRecordState.settled);
          });
        },
      );
    }
  }

  test('non-run-id constraints fail once without retrying entropy or overwriting a row', () async {
    final s = await open();
    await s.useDatabase((db) async {
      await db.customStatement(
        'CREATE UNIQUE INDEX test_app_version_unique ON stored_runs(app_version)',
      );
      var generated = 0;
      final store = RunStore(
        db,
        generateId: () => fixtureId(++generated),
        clock: () => instant,
      );
      final config = projectConfiguration(input(DiagnosticOperation.send));
      await store.register(
        appVersion: 'same',
        configuration: config,
        profileId: null,
        hostRequired: false,
      );
      await expectLater(
        store.register(
          appVersion: 'same',
          configuration: config,
          profileId: null,
          hostRequired: false,
        ),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      expect(generated, 2);
      expect(await db.select(db.storedRuns).get(), hasLength(1));
      await db.customStatement('DROP INDEX test_app_version_unique');
    });
  });

  test('saved partial PONG evidence is preserved and archived run rejects every late save', () async {
    final s = await open();
    final config = projectConfiguration(input(DiagnosticOperation.ping));
    await s.useDatabase((db) async {
      final partial = DiagnosticRun(
        runId: fixtureId(99),
        appVersion: 'v',
        configuration: config,
        preparedAt: instant,
        result: const PingSummary(
          matchingPongObserved: true,
          exactContentValidated: true,
          firstMatchingPongElapsedUs: 123,
        ),
      );
      await db.into(db.storedRuns).insert(encodeRun(partial));
      final store = RunStore(db);
      await expectLater(
        store.saveLogical(
          partial.runId,
          const PingSummary(
            reason: LogicalReason.sendFailed,
            stage: DiagnosticStage.sending,
            matchingPongObserved: false,
            exactContentValidated: false,
            roundTripSucceeded: false,
          ),
          instant,
        ),
        throwsA(coreError(CoreErrorCode.conflict)),
      );
      await store.saveLogical(
        partial.runId,
        const PingSummary(
          reason: LogicalReason.sendFailed,
          stage: DiagnosticStage.sending,
          matchingPongObserved: true,
          exactContentValidated: true,
          firstMatchingPongElapsedUs: 123,
          roundTripSucceeded: false,
        ),
        instant,
      );
    });
    await s.close();
    final reopened = await open();
    await reopened.useDatabase((db) async {
      final store = RunStore(db);
      expect(
        (await readRun(db, fixtureId(99))).recordState,
        DiagnosticRecordState.recoveredArchived,
      );
      await expectLater(
        store.saveCleanup(fixtureId(99), core: succeeded),
        throwsA(coreError(CoreErrorCode.conflict)),
      );
      await expectLater(
        store.saveLogical(
          fixtureId(99),
          const PingSummary(
            reason: LogicalReason.canceled,
            stage: DiagnosticStage.startup,
          ),
          instant,
        ),
        throwsA(coreError(CoreErrorCode.conflict)),
      );
    });
  });

  test('observation clock runs before a blocked database queue, and cleanup does not wait for that queue', () async {
    var reads = 0;
    final s = await open(
      hooks: StorageHooks(
        clock: () {
          reads++;
          return instant.add(Duration(microseconds: reads));
        },
      ),
    );
    final t = FakeCompanionTransport();
    final op = s.record(
      parameters: input(DiagnosticOperation.send),
      appVersion: 'v',
      createTransport: () => t,
    );
    await op.prepared;
    await until(() => t.sent.isNotEmpty);
    t.receive(deviceInfo());
    await until(() => t.sent.length == 2);
    t.receive(selfInfo());
    await until(() => t.sent.length == 3);
    final entered = Completer<void>(), release = Completer<void>();
    final blocking = s.useDatabase(
      (db) => db.transaction(() async {
        entered.complete();
        await release.future;
      }),
    );
    await entered.future;
    t.receive([0]);
    final summary = await op.logical;
    try {
      expect(summary!.reason, LogicalReason.completed);
      expect(reads, 2);
      await until(() => t.closeCount == 1);
      expect((await op.cleanupDone).aggregate, CleanupState.succeeded);
    } finally {
      release.complete();
    }
    await blocking;
    final r = await op.done;
    expect(
      r.logicalSave.snapshot!.logicalEndedAt,
      instant.add(const Duration(microseconds: 2)),
    );
  });

  test('semantic damage is corrupt while mutation query I/O retains write category', () async {
    final s = await open();
    await s.useDatabase((db) async {
      final bad = DiagnosticRun(
        runId: fixtureId(1),
        appVersion: 'v',
        configuration: projectConfiguration(input(DiagnosticOperation.send)),
        preparedAt: instant,
        recordState: DiagnosticRecordState.settled,
      );
      await db.into(db.storedRuns).insert(encodeRun(bad));
      await expectLater(
        RunStore(db).saveCleanup(bad.runId, core: succeeded),
        throwsA(coreError(CoreErrorCode.databaseCorrupt)),
      );
      expect(
        () => validateRun(bad),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    });
  });
}
