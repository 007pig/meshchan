import 'dart:async';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Fixture f;
  setUp(() {
    f = Fixture();
  });
  tearDown(() => f.close());

  test('global eligible rank, cross-batch ties and noneligible rows; same-clock and reversed insertion', () async {
    final c = HistoryControl();
    final s = await f.open(control: c);
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 129));
    await s.history.waitForMaintenance();
    final rows = [
      for (var i = 1; i <= 310; i++)
        sample(
          i,
          operation: DiagnosticOperation.values[i % 4],
          time: i <= 10 ? instant.add(const Duration(days: 1)) : instant,
        ),
      for (var i = 311; i <= 600; i++)
        sample(i, state: DiagnosticRecordState.prepared),
      sample(
        601,
        cleanup: CleanupSummary(
          core: CleanupScopeSummary(state: CleanupState.pending),
          hostSubscriptions: CleanupScopeSummary(
            state: CleanupState.notRequired,
          ),
          aggregate: CleanupState.pending,
        ),
      ),
    ];
    await f.seed(s, rows.reversed);
    c.capture = true;
    final report = await s.history.maintain();
    expect(report.state, HistoryMaintenanceState.completed);
    expect(report.historyLimit, 129);
    expect(report.deletedCount, 181);
    expect(await f.count(s), 420);
    final remaining = <LocalId>[];
    HistoryCursor? cursor;
    do {
      final page = await s.history.query(size: PageSize(200), after: cursor);
      remaining.addAll(page.items.map((r) => r.runId));
      cursor = page.nextCursor;
    } while (cursor != null);
    expect(remaining.toSet(), {
      for (var i = 1; i <= 10; i++) fixtureId(i),
      for (var i = 192; i <= 601; i++) fixtureId(i),
    });
    final scans = c.selects
        .where((q) => q.$2.isNotEmpty && q.$2.last == 128)
        .toList();
    expect(scans.length, greaterThanOrEqualTo(5));
    expect(scans.skip(1).every((q) => q.$1.contains(') < (?, ?)')), isTrue);
    expect((await s.history.maintain()).deletedCount, 0);
  });

  test('open recovery followed by default 1000 retention; startup result remains available', () async {
    final s = await f.open();
    await f.seed(s, [
      for (var i = 1; i <= 1003; i++)
        sample(i, state: DiagnosticRecordState.prepared),
    ]);
    await s.close();
    final reopened = await f.open();
    final report = reopened.history.latestMaintenance!;
    expect(report.state, HistoryMaintenanceState.completed);
    expect(report.historyLimit, 1000);
    expect(report.deletedCount, 3);
    expect(await f.count(reopened), 1000);
    final run = await reopened.history.read(fixtureId(1003));
    expect(run.recordState, DiagnosticRecordState.recoveredArchived);
    expect(run.recoveryReason, RecoveryReason.interrupted);
    expect(
      identical(await reopened.history.waitForMaintenance(), report),
      isTrue,
    );
  });

  test('settings save and restoreDefaults really prune without changing their return semantics', () async {
    final s = await f.open();
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 100000));
    await s.history.waitForMaintenance();
    await f.seed(s, [for (var i = 1; i <= 1003; i++) sample(i)]);
    expect((await s.settings.restoreDefaults()).diagnosticHistoryLimit, 1000);
    expect((await s.history.waitForMaintenance()).deletedCount, 3);
    expect(await f.count(s), 1000);
    expect(
      (await s.settings.save(AppSettings(diagnosticHistoryLimit: 1)))
          .diagnosticHistoryLimit,
      1,
    );
    expect((await s.history.waitForMaintenance()).deletedCount, 999);
    expect(await f.ids(s), [fixtureId(1003)]);
  });

  for (final mutation in [
    'increase',
    'decrease',
    'delete-retained',
    'new-eligible',
  ]) {
    test('cross-batch $mutation invalidates rank before next delete', () async {
      final c = HistoryControl();
      final s = await f.open(control: c);
      await s.settings.save(AppSettings(diagnosticHistoryLimit: 128));
      await s.history.waitForMaintenance();
      await f.seed(s, [
        for (var i = 1; i <= 260; i++) sample(i),
        if (mutation == 'new-eligible')
          sample(261, state: DiagnosticRecordState.prepared),
      ]);
      Future<Object?>? change;
      c.afterCommit = () {
        change = switch (mutation) {
          'increase' => s.settings.save(
            AppSettings(diagnosticHistoryLimit: 250),
          ),
          'decrease' => s.settings.save(AppSettings(diagnosticHistoryLimit: 1)),
          'delete-retained' => s.history.delete(fixtureId(260)),
          _ =>
            s
                .useDatabase(
                  (db) => db.transaction(() async {
                    // Exercise the same precommit invalidation used by RunStore. Real
                    // recording pin release is covered by the separate recording test.
                    await db.customStatement(
                      'UPDATE stored_runs SET record_state = ?, logical_ended_at_us = ?, result_json = (SELECT result_json FROM stored_runs WHERE run_id = ?) WHERE run_id = ?',
                      [
                        'settled',
                        instant.microsecondsSinceEpoch,
                        fixtureId(260).value,
                        fixtureId(261).value,
                      ],
                    );
                    s.invalidateHistorySelection();
                  }),
                )
                .then((_) => s.requestHistoryMaintenance()),
        };
      };
      final report = await s.history.maintain();
      await change;
      await s.history.waitForMaintenance();
      expect(report.state, HistoryMaintenanceState.completed);
      final expected = switch (mutation) {
        'increase' => [for (var i = 260; i >= 11; i--) fixtureId(i)],
        'decrease' => [fixtureId(260)],
        'delete-retained' => [for (var i = 259; i >= 132; i--) fixtureId(i)],
        _ => [for (var i = 261; i >= 134; i--) fixtureId(i)],
      };
      final actual = <LocalId>[];
      HistoryCursor? cursor;
      do {
        final page = await s.history.query(size: PageSize(200), after: cursor);
        actual.addAll(page.items.map((r) => r.runId));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(actual, expected);
    });
  }

  for (final fault in ['delete', 'commit']) {
    test(
      'later batch $fault failure keeps committed earlier deletes, rolls back this batch and retries',
      () async {
        final c = HistoryControl();
        final s = await f.open(control: c);
        await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
        await s.history.waitForMaintenance();
        await f.seed(s, [for (var i = 1; i <= 270; i++) sample(i)]);
        if (fault == 'delete') {
          c.failDelete = c.deletes + 130;
        } else {
          c.failCommit = c.commits + 2;
        }
        final report = await s.history.maintain();
        expect(report.state, HistoryMaintenanceState.failed);
        expect(report.error, coreError(CoreErrorCode.storageWriteFailed));
        expect(report.deletedCount, 127);
        expect(c.rollbacks, 1);
        expect(await f.count(s), 143);
        expect((await s.history.read(fixtureId(142))).runId, fixtureId(142));
        await expectLater(
          s.history.read(fixtureId(143)),
          throwsA(coreError(CoreErrorCode.notFound)),
        );
        expect(s.history.unacknowledgedFailureCount, 1);
        final next = await s.history.maintain();
        expect(next.state, HistoryMaintenanceState.completed);
        expect(next.deletedCount, 142);
        expect(await f.ids(s), [fixtureId(270)]);
        expect(s.history.unacknowledgedFailure, same(report));
        s.history.acknowledgeMaintenanceFailures();
        expect(s.history.unacknowledgedFailure, isNull);
        expect(s.history.unacknowledgedFailureCount, 0);
      },
    );
  }

  test('all rows in a corrupt batch validate before any delete and newer summary is not blind-pruned', () async {
    final s = await f.open();
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await f.seed(s, [for (var i = 1; i <= 140; i++) sample(i)]);
    await s.useDatabase(
      (db) => db.customStatement(
        'UPDATE stored_runs SET summary_format_version = 2 WHERE run_id = ?',
        [fixtureId(139).value],
      ),
    );
    final failed = await s.history.maintain();
    expect(failed.state, HistoryMaintenanceState.failed);
    expect(failed.error, coreError(CoreErrorCode.storageReadFailed));
    expect(failed.deletedCount, 0);
    expect(await f.count(s), 140);
  });

  for (final restore in [false, true]) {
    test(
      'committed settings restore=$restore survives first prune failure and later success preserves unobserved failure',
      () async {
        final c = HistoryControl();
        final s = await f.open(control: c);
        await s.settings.save(AppSettings(diagnosticHistoryLimit: 100000));
        await s.history.waitForMaintenance();
        await f.seed(s, [for (var i = 1; i <= 1002; i++) sample(i)]);
        c.failDelete = c.deletes + 1;
        final saved = restore
            ? await s.settings.restoreDefaults()
            : await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
        final report = await s.history.waitForMaintenance();
        expect(saved.diagnosticHistoryLimit, restore ? 1000 : 1);
        expect(report.state, HistoryMaintenanceState.failed);
        expect(report.deletedCount, 0);
        expect(
          (await s.settings.read()).diagnosticHistoryLimit,
          saved.diagnosticHistoryLimit,
        );
        expect(await f.count(s), 1002);
        await s.settings.save(saved);
        expect(
          (await s.history.waitForMaintenance()).state,
          HistoryMaintenanceState.completed,
        );
        expect(s.history.unacknowledgedFailure, same(report));
        expect(s.history.unacknowledgedFailureCount, 1);
      },
    );
  }

  test('startup retention failure returns usable owner and sticky report, not failed open', () async {
    final s = await f.open();
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await f.seed(s, [sample(1), sample(2)]);
    await s.close();
    final c = HistoryControl()..failDelete = 1;
    final reopened = await f.open(control: c);
    expect(reopened.state, StorageState.open);
    expect(
      reopened.history.latestMaintenance!.state,
      HistoryMaintenanceState.failed,
    );
    expect(reopened.history.unacknowledgedFailureCount, 1);
    expect(await f.count(reopened), 2);
    await reopened.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    expect(
      (await reopened.history.waitForMaintenance()).state,
      HistoryMaintenanceState.completed,
    );
    expect(reopened.history.unacknowledgedFailure, isNotNull);
    expect(await f.ids(reopened), [fixtureId(2)]);
  });

  test('dangling default does not block history-only maintenance; corrupt setting is never clamped', () async {
    final s = await f.open();
    await f.seed(s, [sample(1), sample(2)]);
    await s.useDatabase((db) async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement('INSERT INTO stored_settings VALUES(1, ?, 1)', [
        fixtureId(999).value,
      ]);
    });
    await expectLater(
      s.settings.read(),
      throwsA(coreError(CoreErrorCode.notFound)),
    );
    expect((await s.history.maintain()).deletedCount, 1);
    await s.useDatabase((db) async {
      await db.customStatement('PRAGMA ignore_check_constraints = ON');
      await db.customStatement(
        'UPDATE stored_settings SET diagnostic_history_limit = 0',
      );
    });
    final report = await s.history.maintain();
    expect(report.state, HistoryMaintenanceState.failed);
    expect(report.error, coreError(CoreErrorCode.databaseCorrupt));
    expect(await f.count(s), 1);
  });

  for (final failure in [false, true]) {
    test(
      'coalesced admitted maintenance holds close/owner, releases after failure=$failure',
      () async {
        final c = HistoryControl();
        final s = await f.open(control: c);
        await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
        await s.history.waitForMaintenance();
        await f.seed(s, [sample(1), sample(2)]);
        final entered = Completer<void>(), release = Completer<void>();
        c.afterRead = () async {
          entered.complete();
          await release.future;
          if (failure) throw StateError('PRIVATE');
        };
        final first = s.history.maintain();
        await entered.future;
        final second = s.history.maintain();
        var closed = false;
        final closing = s.close().then((_) {
          closed = true;
        });
        await turns();
        expect(closed, isFalse);
        await expectLater(
          CoreStorage.open(dataDirectory: f.directory),
          throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
        );
        await expectLater(
          s.history.query(),
          throwsA(coreError(CoreErrorCode.storageReadFailed)),
        );
        release.complete();
        final results = await Future.wait([first, second]);
        expect(results[0], same(results[1]));
        expect(
          results[0].state,
          failure
              ? HistoryMaintenanceState.failed
              : HistoryMaintenanceState.completed,
        );
        await closing;
        expect(s.state, StorageState.closed);
        final next = await f.open();
        expect(next.state, StorageState.open);
      },
    );
  }
}
