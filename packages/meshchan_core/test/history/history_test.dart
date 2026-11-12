import 'dart:convert';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Fixture f;
  setUp(() {
    f = Fixture();
  });
  tearDown(() => f.close());

  test(
    'stable no-I/O getter, public read/filter, real reopen and close rejection',
    () async {
      final c = HistoryControl();
      final s = await f.open(control: c);
      await f.seed(s, [sample(1)]);
      c.capture = true;
      expect(identical(s.history, s.history), isTrue);
      expect(c.selects, isEmpty);
      expect((await s.history.read(fixtureId(1))).runId, fixtureId(1));
      await expectLater(
        s.history.read(fixtureId(2)),
        throwsA(coreError(CoreErrorCode.notFound)),
      );
      await s.close();
      for (final call in [
        s.history.read(fixtureId(1)),
        s.history.query(),
        s.history.exportSummary(),
        s.history.maintain(),
        s.history.waitForMaintenance(),
      ]) {
        await expectLater(
          call,
          throwsA(coreError(CoreErrorCode.storageReadFailed)),
        );
      }
      await expectLater(
        s.history.delete(fixtureId(1)),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      final reopened = await CoreStorage.open(dataDirectory: f.directory);
      try {
        expect(
          (await reopened.history.query()).items.single.runId,
          fixtureId(1),
        );
      } finally {
        await reopened.close();
      }
    },
  );

  for (final operation in [null, DiagnosticOperation.ping]) {
    for (final state in [null, DiagnosticRecordState.prepared]) {
      test(
        'actual index shape operation=$operation state=$state; row-value seek and time predicates',
        () async {
          final c = HistoryControl();
          final s = await f.open(control: c);
          await f.seed(s, [
            for (var i = 1; i <= 12; i++)
              sample(
                i,
                operation: i.isEven
                    ? DiagnosticOperation.ping
                    : DiagnosticOperation.send,
                state: i % 3 == 0
                    ? DiagnosticRecordState.prepared
                    : DiagnosticRecordState.settled,
              ),
          ]);
          c.capture = true;
          final filter = HistoryQuery(operation: operation, recordState: state);
          final first = await s.history.query(
            filter: filter,
            size: PageSize(1),
          );
          expect(first.nextCursor, isNotNull);
          final second = await s.history.query(
            filter: filter,
            size: PageSize(1),
            after: first.nextCursor,
          );
          expect(
            second.items.single.runId.value.compareTo(
              first.items.single.runId.value,
            ),
            lessThan(0),
          );
          final index = operation == null
              ? (state == null ? 'runs_prepared' : 'runs_state')
              : (state == null ? 'runs_operation' : 'runs_operation_state');
          for (final sql in c.selects) {
            expect(sql.$3.join(' '), contains(index));
            expect(sql.$3.join(' '), isNot(contains('TEMP B-TREE')));
            expect(sql.$1, isNot(contains('OFFSET')));
            expect(sql.$2.last, 2);
            expect(sql.$1.contains('operation" = ?'), operation != null);
            expect(sql.$1.contains('record_state" = ?'), state != null);
          }
          final seek = c.selects.last;
          expect(seek.$3.join(' '), contains('SEARCH'));
          expect(seek.$3.join(' '), contains('(prepared_at_us,run_id)<(?,?)'));
          expect(seek.$1, contains(') < (?, ?)'));
          final timed = await s.history.query(
            filter: HistoryQuery(
              operation: operation,
              recordState: state,
              preparedFromInclusive: instant,
              preparedUntilExclusive: instant.add(
                const Duration(microseconds: 1),
              ),
            ),
          );
          expect(timed.items, isNotEmpty);
          expect(c.selects.last.$2, contains(instant.microsecondsSinceEpoch));
          expect(c.selects.last.$1, contains('>= ?'));
          expect(c.selects.last.$1, contains('< ?'));
        },
      );
    }
  }

  test('UTC half-open prepared range, not logical/recovery time, with typed input validation', () async {
    final s = await f.open();
    await f.seed(s, [
      sample(1, time: instant.subtract(const Duration(microseconds: 1))),
      sample(2),
      sample(
        3,
        time: instant.add(const Duration(microseconds: 1)),
        state: DiagnosticRecordState.recoveredArchived,
      ),
    ]);
    expect(
      (await s.history.query(
        filter: HistoryQuery(
          preparedFromInclusive: instant,
          preparedUntilExclusive: instant.add(const Duration(microseconds: 1)),
        ),
      )).items.single.runId,
      fixtureId(2),
    );
    expect(
      (await s.history.query(
        filter: HistoryQuery(
          preparedFromInclusive: instant.add(const Duration(microseconds: 1)),
        ),
      )).items.single.runId,
      fixtureId(3),
    );
    expect(
      (await s.history.query(
        filter: HistoryQuery(preparedUntilExclusive: instant),
      )).items.single.runId,
      fixtureId(1),
    );
    for (final until in [
      instant,
      instant.subtract(const Duration(microseconds: 1)),
    ]) {
      expect(
        () => HistoryQuery(
          preparedFromInclusive: instant,
          preparedUntilExclusive: until,
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
    expect(
      () => HistoryQuery(preparedFromInclusive: DateTime(2026)),
      throwsA(coreError(CoreErrorCode.invalidInput)),
    );
    expect(
      () => HistoryCursor(preparedAt: DateTime(2026), runId: fixtureId(1)),
      throwsA(coreError(CoreErrorCode.invalidInput)),
    );
    for (final size in [0, 201]) {
      expect(
        () => PageSize(size),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
    expect(
      () => LocalId('invalid'),
      throwsA(coreError(CoreErrorCode.invalidInput)),
    );
  });

  test('default 50, max 200, ties, empty/end pages and deleted cursor continuation', () async {
    final s = await f.open();
    await f.seed(s, [for (var i = 1; i <= 205; i++) sample(i)]);
    final first = await s.history.query();
    expect(first.items, hasLength(50));
    expect(first.nextCursor!.runId, fixtureId(156));
    await s.history.delete(first.nextCursor!.runId);
    await s.history.waitForMaintenance();
    final next = await s.history.query(
      after: first.nextCursor,
      size: PageSize(200),
    );
    expect(next.items, hasLength(155));
    expect(next.items.first.runId, fixtureId(155));
    expect(next.nextCursor, isNull);
    final full = await s.history.query(size: PageSize(200));
    expect(full.items, hasLength(200));
    expect(full.nextCursor, isNotNull);
    final last = await s.history.query(after: full.nextCursor);
    expect(last.items, hasLength(4));
    expect(last.nextCursor, isNull);
    final empty = await s.history.query(
      after: HistoryCursor(preparedAt: instant, runId: fixtureId(1)),
    );
    expect(empty.items, isEmpty);
    expect(empty.nextCursor, isNull);
  });

  for (final state in DiagnosticRecordState.values) {
    for (final cleanupState in [
      CleanupState.succeeded,
      CleanupState.failed,
      CleanupState.pending,
      CleanupState.unconfirmed,
    ]) {
      test(
        'delete qualification $state $cleanupState validates both scopes and preserves neighbors',
        () async {
          final s = await f.open();
          final scope = CleanupScopeSummary(
            state: cleanupState,
            failures: cleanupState == CleanupState.failed
                ? [
                    const FailureSummary(
                      domain: FailureDomain.cleanup,
                      kind: FailureKind.cleanup,
                    ),
                  ]
                : [],
          );
          await f.seed(s, [
            sample(
              1,
              state: state,
              cleanup: state == DiagnosticRecordState.recoveredArchived
                  ? CleanupSummary(
                      core: CleanupScopeSummary(
                        state: CleanupState.unconfirmedAfterExit,
                      ),
                      hostSubscriptions: CleanupScopeSummary(
                        state: CleanupState.notRequired,
                      ),
                      aggregate: CleanupState.unconfirmedAfterExit,
                    )
                  : CleanupSummary(
                      core: scope,
                      hostSubscriptions: CleanupScopeSummary(
                        state: CleanupState.notRequired,
                      ),
                      aggregate: cleanupState == CleanupState.unconfirmed
                          ? CleanupState.unconfirmed
                          : cleanupState,
                    ),
            ),
            sample(2),
          ]);
          final draft = await s.drafts.create(
            const DraftContent(body: 'PRIVATE DRAFT'),
          );
          final eligible =
              state == DiagnosticRecordState.recoveredArchived ||
              (state == DiagnosticRecordState.settled &&
                  [
                    CleanupState.succeeded,
                    CleanupState.failed,
                  ].contains(cleanupState));
          if (eligible) {
            await s.history.delete(fixtureId(1));
            await expectLater(
              s.history.delete(fixtureId(1)),
              throwsA(coreError(CoreErrorCode.notFound)),
            );
          } else {
            await expectLater(
              s.history.delete(fixtureId(1)),
              throwsA(coreError(CoreErrorCode.conflict)),
            );
            expect((await s.history.read(fixtureId(1))).recordState, state);
          }
          expect((await s.history.read(fixtureId(2))).runId, fixtureId(2));
          expect((await s.drafts.read(draft.id)).body, 'PRIVATE DRAFT');
        },
      );
    }
  }

  for (final damage in ['json', 'semantic', 'type', 'newer']) {
    test(
      'strict corrupt probe/read/export/delete/maintenance: $damage',
      () async {
        final s = await f.open();
        await f.seed(s, [sample(1), sample(2)]);
        await s.useDatabase((db) async {
          await db.customStatement('PRAGMA ignore_check_constraints = ON');
          final (column, value) = switch (damage) {
            'json' => ('cleanup_json', '{}'),
            'semantic' => ('record_state', 'prepared'),
            'type' => ('prepared_at_us', instant.microsecondsSinceEpoch + 0.5),
            _ => ('summary_format_version', 2),
          };
          await db.customStatement(
            'UPDATE stored_runs SET $column = ? WHERE run_id = ?',
            [value, fixtureId(1).value],
          );
        });
        final code = damage == 'newer'
            ? CoreErrorCode.storageReadFailed
            : CoreErrorCode.databaseCorrupt;
        for (final call in [
          s.history.read(fixtureId(1)),
          s.history.query(size: PageSize(1)),
          s.history.exportSummary(size: PageSize(1)),
          s.history.delete(fixtureId(1)),
        ]) {
          await expectLater(call, throwsA(coreError(code)));
        }
        final report = await s.history.maintain();
        expect(report.state, HistoryMaintenanceState.failed);
        expect(report.error, coreError(code));
        expect(await f.count(s), 2);
      },
    );
  }

  test('query IO is read failure, mutation SELECT IO is write failure; delete/commit rollback on same handle', () async {
    final c = HistoryControl();
    final s = await f.open(control: c);
    await f.seed(s, [sample(1), sample(2)]);
    c.readFailure = StateError('PRIVATE');
    await expectLater(
      s.history.query(),
      throwsA(coreError(CoreErrorCode.storageReadFailed)),
    );
    c.readFailure = StateError('PRIVATE');
    await expectLater(
      s.history.delete(fixtureId(1)),
      throwsA(coreError(CoreErrorCode.storageWriteFailed)),
    );
    c.failDelete = c.deletes + 1;
    await expectLater(
      s.history.delete(fixtureId(1)),
      throwsA(coreError(CoreErrorCode.storageWriteFailed)),
    );
    expect((await s.history.read(fixtureId(1))).runId, fixtureId(1));
    c.failCommit = c.commits + 1;
    await expectLater(
      s.history.delete(fixtureId(1)),
      throwsA(coreError(CoreErrorCode.storageWriteFailed)),
    );
    expect((await s.history.read(fixtureId(1))).runId, fixtureId(1));
    expect(c.rollbacks, 3);
    await s.history.delete(fixtureId(1));
    expect(await f.count(s), 1);
  });

  test('export generation TypeError/FormatException are safe read failures, and empty JSON is valid', () async {
    var clockCalls = 0;
    var fail = false;
    final s = await f.open(
      clock: () {
        clockCalls++;
        if (fail) throw const FormatException('PRIVATE');
        return DateTime.utc(2026);
      },
    );
    final before = clockCalls;
    final page = await s.history.exportSummary();
    expect(jsonDecode(page.json), {
      'diagnosticSummaryFormatVersion': 1,
      'exportedAt': '2026-01-01T00:00:00.000000Z',
      'runs': [],
    });
    expect(clockCalls, before + 1);
    fail = true;
    await expectLater(
      s.history.exportSummary(),
      throwsA(coreError(CoreErrorCode.storageReadFailed)),
    );
  });
}
