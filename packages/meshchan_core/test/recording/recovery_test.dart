import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/recording/projection.dart';
import 'package:meshchan_core/src/recording/recovery.dart';
import 'package:meshchan_core/src/recording/run_store.dart';
import 'package:meshchan_core/src/recording/validation.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/ownership.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../repositories/draft_repository_test.dart' show Control;
import '../storage/process_support.dart';
import 'support.dart';

final good = CleanupScopeSummary(state: CleanupState.succeeded);
final noWork = CleanupScopeSummary(state: CleanupState.notRequired);
final failed = CleanupScopeSummary(
  state: CleanupState.failed,
  failures: [
    const FailureSummary(
      domain: FailureDomain.cleanup,
      kind: FailureKind.cleanup,
    ),
  ],
);
DiagnosticRun residual(
  int id, {
  bool settled = false,
  CleanupSummary? cleanup,
  LogicalSummary? partial,
  DateTime? preparedAt,
}) => DiagnosticRun(
  runId: fixtureId(id),
  appVersion: 'real-host-version',
  configuration: projectConfiguration(input(DiagnosticOperation.ping)),
  preparedAt: preparedAt ?? instant,
  recordState: settled
      ? DiagnosticRecordState.settled
      : DiagnosticRecordState.prepared,
  logicalEndedAt: settled ? instant : null,
  result: settled
      ? const PingSummary(
          reason: LogicalReason.sendFailed,
          stage: DiagnosticStage.sending,
          matchingPongObserved: true,
          exactContentValidated: true,
          roundTripSucceeded: false,
          firstMatchingPongElapsedUs: 987,
          applicationRttUs: null,
        )
      : partial,
  cleanup: cleanup,
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

  Future<void> seed(List<DiagnosticRun> runs) async {
    final s = await open();
    await s.useDatabase((db) async {
      for (final run in runs) {
        await db.into(db.storedRuns).insert(encodeRun(run));
      }
    });
    await s.close();
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meshchan-recovery-');
  });
  tearDown(() async {
    for (final s in handles.reversed) {
      await s.close();
    }
    handles.clear();
    directory.deleteSync(recursive: true);
  });

  test('recovery matrix preserves terminal cleanup, partial facts, first times and meaningful nulls', () async {
    final before = [
      residual(1),
      residual(2, cleanup: combineCleanup(good, noWork)),
      residual(
        3,
        settled: true,
        cleanup: combineCleanup(
          failed,
          CleanupScopeSummary(state: CleanupState.pending),
        ),
      ),
      residual(4, settled: true, cleanup: combineCleanup(good, failed)),
      residual(
        5,
        partial: const PingSummary(
          matchingPongObserved: true,
          exactContentValidated: true,
          firstMatchingPongElapsedUs: 456,
        ),
      ),
    ];
    await seed(before);
    var clockReads = 0;
    final s = await open(
      hooks: StorageHooks(
        clock: () {
          clockReads++;
          return instant.add(const Duration(days: 1));
        },
      ),
    );
    final rows = await s.useDatabase(
      (db) async => [for (final run in before) await readRun(db, run.runId)],
    );
    expect(clockReads, 4);
    for (final row in rows) {
      validateRun(row);
    }
    expect(rows[0].recordState, DiagnosticRecordState.recoveredArchived);
    expect(rows[0].recoveryReason, RecoveryReason.interrupted);
    expect(rows[0].logicalEndedAt, isNull);
    expect(rows[0].result, isNull);
    expect(rows[0].cleanup.aggregate, CleanupState.unconfirmedAfterExit);
    expect(rows[1].cleanup.aggregate, CleanupState.succeeded);
    expect(rows[1].cleanup.core.state, CleanupState.succeeded);
    expect(rows[1].logicalEndedAt, isNull);
    expect(rows[1].result, isNull);
    expect(rows[2].recoveryReason, RecoveryReason.cleanupUnconfirmed);
    expect(rows[2].cleanup.core.state, CleanupState.failed);
    expect(rows[2].cleanup.core.failureCount, 1);
    expect(
      rows[2].cleanup.hostSubscriptions.state,
      CleanupState.unconfirmedAfterExit,
    );
    expect(
      encodeLogicalSummary(rows[2].result!),
      encodeLogicalSummary(before[2].result!),
    );
    expect(rows[2].logicalEndedAt, instant);
    expect(rows[3].recordState, DiagnosticRecordState.settled);
    expect(rows[3].recoveredAt, isNull);
    expect(rows[3].cleanup.aggregate, CleanupState.failed);
    final partial = rows[4].result as PingSummary;
    expect(partial.reason, isNull);
    expect(partial.roundTripSucceeded, isNull);
    expect(partial.matchingPongObserved, isTrue);
    expect(partial.firstMatchingPongElapsedUs, 456);
    expect(partial.processedEntries, isNull);
    expect(partial.reception, isNull);
    final representations = rows
        .map((v) => representation(encodeRun(v)))
        .toList();
    await s.close();
    final reopened = await open(
      hooks: StorageHooks(
        clock: () => throw StateError('No second recovery clock'),
      ),
    );
    await reopened.useDatabase((db) async {
      final all = [for (final row in rows) await readRun(db, row.runId)];
      expect(all.map((v) => representation(encodeRun(v))), representations);
    });
  });

  test('bounded indexed traversal crosses unchanged settled batches, ties and updated states', () async {
    final before = <DiagnosticRun>[];
    for (var n = 1; n <= recoveryBatchSize * 3 + 17; n++) {
      before.add(
        residual(
          n,
          settled: n.isEven,
          cleanup: n % 6 == 0 ? combineCleanup(good, noWork) : null,
          preparedAt: instant.add(Duration(microseconds: n % 3)),
        ),
      );
    }
    await seed(before);
    final s = await open();
    await s.useDatabase((db) async {
      for (final old in before) {
        final row = await readRun(db, old.runId);
        final terminal =
            old.recordState == DiagnosticRecordState.settled &&
            old.cleanup.aggregate == CleanupState.succeeded;
        expect(
          row.recordState,
          terminal
              ? DiagnosticRecordState.settled
              : DiagnosticRecordState.recoveredArchived,
        );
      }
      final plans = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM stored_runs WHERE record_state = ? AND (prepared_at_us, run_id) < (?, ?) ORDER BY prepared_at_us DESC, run_id DESC LIMIT 128',
            variables: [
              const Variable<String>('settled'),
              Variable<int>(instant.microsecondsSinceEpoch),
              const Variable<String>('ffffffffffffffffffffffffffffffff'),
            ],
          )
          .get();
      expect(
        plans.map((r) => r.read<String>('detail')).join(' '),
        contains('runs_state'),
      );
    });
  });

  test(
    'complete settled batches advance cursor to a later unresolved row',
    () async {
      await seed([
        for (var n = 1; n <= recoveryBatchSize * 2; n++)
          residual(n, settled: true, cleanup: combineCleanup(good, noWork)),
        residual(
          recoveryBatchSize * 2 + 1,
          settled: true,
          preparedAt: instant.subtract(const Duration(days: 1)),
        ),
      ]);
      final s = await open();
      expect(
        (await stored(s, fixtureId(recoveryBatchSize * 2 + 1))).recordState,
        DiagnosticRecordState.recoveredArchived,
      );
    },
  );

  test('later batch commit rejection rolls back only that batch, open releases owner and next open continues', () async {
    await seed([for (var n = 1; n <= recoveryBatchSize + 5; n++) residual(n)]);
    var commits = 0;
    final control = RecoveryControl(
      onCommit: () {
        if (++commits == 2) throw StateError('PRIVATE COMMIT');
      },
    );
    await expectLater(
      open(
        hooks: StorageHooks(
          executorFactory: (file) =>
              NativeDatabase(file).interceptWith(control),
        ),
      ),
      throwsA(coreError(CoreErrorCode.storageWriteFailed)),
    );
    final raw = sqlite3.open('${directory.path}/$databaseFileName');
    try {
      expect(
        raw
            .select(
              "SELECT count(*) AS n FROM stored_runs WHERE record_state='recovered_archived'",
            )
            .single['n'],
        recoveryBatchSize,
      );
      expect(
        raw
            .select(
              "SELECT count(*) AS n FROM stored_runs WHERE record_state='prepared'",
            )
            .single['n'],
        5,
      );
    } finally {
      raw.close();
    }
    final s = await open();
    await s.useDatabase((db) async {
      final rows = await db.select(db.storedRuns).get();
      expect(rows.every((r) => r.recordState == 'recovered_archived'), isTrue);
    });
  });

  for (final damage in [
    'semantic',
    'json',
    'format',
    'write',
    'clock',
    'select',
  ]) {
    test(
      'recovery $damage failure retains category and never returns a half-recovered handle',
      () async {
        await seed([residual(1)]);
        final control = Control(readTable: 'stored_runs');
        if (damage == 'semantic' || damage == 'json' || damage == 'format') {
          final raw = sqlite3.open('${directory.path}/$databaseFileName');
          try {
            if (damage == 'semantic') {
              raw.execute("UPDATE stored_runs SET record_state='settled'");
            }
            if (damage == 'json') {
              raw.execute("UPDATE stored_runs SET configuration_json='{}'");
            }
            if (damage == 'format') {
              raw.execute('UPDATE stored_runs SET summary_format_version=2');
            }
          } finally {
            raw.close();
          }
        }
        if (damage == 'write') {
          control.afterWrite = (_) async {
            throw StateError('PRIVATE');
          };
        }
        if (damage == 'select') control.readFailure = StateError('PRIVATE');
        final code = damage == 'semantic' || damage == 'json'
            ? CoreErrorCode.databaseCorrupt
            : damage == 'format'
            ? CoreErrorCode.storageReadFailed
            : CoreErrorCode.storageWriteFailed;
        await expectLater(
          open(
            hooks: StorageHooks(
              executorFactory: (file) =>
                  NativeDatabase(file).interceptWith(control),
              clock: damage == 'clock'
                  ? () => throw const FormatException('PRIVATE CLOCK')
                  : null,
            ),
          ),
          throwsA(coreError(code)),
        );
        // No failed-open owner remains. Restore the injected damage and reopen.
        final raw = sqlite3.open('${directory.path}/$databaseFileName');
        try {
          raw.execute('DELETE FROM stored_runs');
        } finally {
          raw.close();
        }
        final s = await open();
        expect(s.state, StorageState.open);
      },
    );
  }

  for (final window in ['prepared', 'logical']) {
    test(
      'independent process exits after $window commit; new owner archives without replay',
      () async {
        final peer = await Peer.start('record-$window', directory);
        try {
          expect(await peer.line(), 'ready');
          peer.send('crash');
          await peer.finish(23);
          final s = await open();
          await s.useDatabase((db) async {
            final row = validateStoredRun(
              decodeRun(await db.select(db.storedRuns).getSingle()),
            );
            expect(row.recordState, DiagnosticRecordState.recoveredArchived);
            expect(
              row.recoveryReason,
              window == 'prepared'
                  ? RecoveryReason.interrupted
                  : RecoveryReason.cleanupUnconfirmed,
            );
            if (window == 'prepared') {
              expect(row.result, isNull);
              expect(row.logicalEndedAt, isNull);
            } else {
              expect(row.result!.reason, LogicalReason.completed);
              expect(row.logicalEndedAt, isNotNull);
            }
          });
        } finally {
          await peer.dispose();
        }
      },
    );
  }
}

class RecoveryControl extends QueryInterceptor {
  RecoveryControl({required this.onCommit});
  final void Function() onCommit;
  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    onCommit();
    await inner.send();
  }
}
