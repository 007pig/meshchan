import 'package:drift/drift.dart';

import '../errors.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_run.dart';
import '../recording/run_store.dart';
import '../recording/validation.dart';
import '../repositories.dart';
import '../repositories/settings_repository.dart';
import '../storage/codec.dart';
import '../storage/database.dart';
import '../values.dart';

const historyMaintenanceBatchSize = 128;

// Call only after strict decoding and semantic validation. Pins are a separate
// deletion constraint: they do not change rank or the eligible population.
bool eligibleHistory(DiagnosticRun run) =>
    run.recordState == DiagnosticRecordState.recoveredArchived ||
    (run.recordState == DiagnosticRecordState.settled &&
        terminalCleanup(run.cleanup.core.state) &&
        terminalCleanup(run.cleanup.hostSubscriptions.state));

Future<List<DiagnosticRun>> selectRuns(
  CoreDatabase db, {
  HistoryQuery? filter,
  HistoryCursor? after,
  required int limit,
}) async {
  final conditions = <String>[];
  final variables = <Variable>[];
  if (filter?.operation case final operation?) {
    conditions.add('"operation" = ?');
    variables.add(Variable(operation.code));
  }
  if (filter?.recordState case final state?) {
    conditions.add('"record_state" = ?');
    variables.add(Variable(state.code));
  }
  if (filter?.preparedFromInclusive case final from?) {
    conditions.add('prepared_at_us >= ?');
    variables.add(Variable(from.microsecondsSinceEpoch));
  }
  if (filter?.preparedUntilExclusive case final until?) {
    conditions.add('prepared_at_us < ?');
    variables.add(Variable(until.microsecondsSinceEpoch));
  }
  if (after != null) {
    conditions.add('(prepared_at_us, run_id) < (?, ?)');
    variables.addAll([
      Variable(after.preparedAt.microsecondsSinceEpoch),
      Variable(after.runId.value),
    ]);
  }
  variables.add(Variable(limit));
  final where = conditions.isEmpty ? '' : ' WHERE ${conditions.join(' AND ')}';
  // Only fixed SQL fragments are composed. All values, including the bound,
  // are parameters. Map through the strict table reader before the codec.
  final rows = await db
      .customSelect(
        'SELECT * FROM stored_runs$where ORDER BY prepared_at_us DESC, run_id DESC LIMIT ?',
        variables: variables,
        readsFrom: {db.storedRuns},
      )
      .get();
  // Validate the probe too. A corrupt extra row cannot become a false success.
  return rows
      .map((r) => validateStoredRun(decodeRun(db.storedRuns.map(r.data))))
      .toList();
}

HistoryCursor cursorOf(DiagnosticRun run) =>
    HistoryCursor(preparedAt: run.preparedAt, runId: run.runId);

Future<Page<DiagnosticRun, HistoryCursor>> queryRuns(
  CoreDatabase db, {
  HistoryQuery? filter,
  PageSize? size,
  HistoryCursor? after,
}) async {
  final count = (size ?? PageSize()).value;
  final rows = await selectRuns(
    db,
    filter: filter,
    after: after,
    limit: count + 1,
  );
  return Page(
    items: rows.take(count),
    nextCursor: rows.length > count ? cursorOf(rows[count - 1]) : null,
  );
}

Future<void> deleteRun(CoreDatabase db, LocalId id) async {
  final count = await (db.delete(
    db.storedRuns,
  )..where((t) => t.runId.equals(id.value))).go();
  if (count != 1) throw const CoreException(CoreErrorCode.storageWriteFailed);
}

/// Bounded memory and short transactions, not bounded total search work: cleanup
/// eligibility lives in JSON. Every visited row is strictly validated. Known
/// worker deletions do not invalidate rank; external writes do, before commit.
Future<HistoryMaintenanceReport> pruneHistory(
  CoreDatabase db, {
  required bool Function(LocalId) isPinned,
  required int Function() revision,
}) async {
  var deleted = 0, retained = 0, deferred = 0;
  int? limit;
  var selection = -1;
  HistoryCursor? cursor;
  try {
    while (true) {
      final batch = await runWrite(
        () => db.transaction(() async {
          final currentLimit = (await readStoredSettings(db))
              .diagnosticHistoryLimit;
          if (selection != revision() || limit != currentLimit) {
            selection = revision();
            limit = currentLimit;
            cursor = null;
            retained = 0;
            deferred = 0;
          }
          final rows = await selectRuns(
            db,
            after: cursor,
            limit: historyMaintenanceBatchSize,
          );
          var removed = 0;
          for (final run in rows) {
            if (!eligibleHistory(run)) continue;
            retained++;
            if (retained <= currentLimit) continue;
            if (isPinned(run.runId)) {
              deferred++;
            } else {
              await deleteRun(db, run.runId);
              removed++;
            }
          }
          return (rows, removed);
        }),
      );
      deleted += batch.$2; // Only a successfully committed batch counts.
      final rows = batch.$1;
      if (rows.isNotEmpty) cursor = cursorOf(rows.last);
      if (selection != revision()) continue;
      if (rows.length < historyMaintenanceBatchSize) break;
    }
    return HistoryMaintenanceReport(
      state: deferred == 0
          ? HistoryMaintenanceState.completed
          : HistoryMaintenanceState.deferred,
      deletedCount: deleted,
      historyLimit: limit,
      deferredCount: deferred,
    );
  } on CoreException catch (error) {
    return HistoryMaintenanceReport(
      state: HistoryMaintenanceState.failed,
      deletedCount: deleted,
      historyLimit: limit,
      error: error,
    );
  }
}
