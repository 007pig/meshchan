import 'package:drift/drift.dart';

import '../models/diagnostic_codes.dart';
import '../models/diagnostic_run.dart';
import '../repositories/write_support.dart';
import '../storage/codec.dart';
import '../storage/database.dart';
import 'run_store.dart';
import 'validation.dart';

const recoveryBatchSize = 128;

/// Called exactly once during exclusive open, before a handle is published.
/// Each state has its own indexed, strict two-key cursor. Even unchanged settled
/// rows advance the cursor. Earlier batches survive a later batch failure.
Future<void> recoverRuns(
  CoreDatabase db, {
  DateTime Function()? clock,
}) => runWrite(() async {
  for (final state in [
    DiagnosticRecordState.prepared,
    DiagnosticRecordState.settled,
  ]) {
    StoredRun? cursor;
    while (true) {
      final rows = await db.transaction(() async {
        final query = db.select(db.storedRuns)
          ..where((t) => t.recordState.equals(state.code));
        if (cursor != null) {
          final last = cursor;
          query.where((t) => _BeforeRun(t, last));
        }
        query.orderBy([
          (t) => OrderingTerm.desc(t.preparedAtUs),
          (t) => OrderingTerm.desc(t.runId),
        ]);
        query.limit(recoveryBatchSize);
        final batch = await query.get();
        for (final row in batch) {
          final run = validateStoredRun(decodeRun(row));
          final unresolved =
              !terminalCleanup(run.cleanup.core.state) ||
              !terminalCleanup(run.cleanup.hostSubscriptions.state);
          if (state == DiagnosticRecordState.settled && !unresolved) continue;
          CleanupScopeSummary archive(CleanupScopeSummary s) =>
              terminalCleanup(s.state)
              ? s
              : CleanupScopeSummary(
                  state: CleanupState.unconfirmedAfterExit,
                  failures: s.failures,
                );
          final cleanup = combineCleanup(
            archive(run.cleanup.core),
            archive(run.cleanup.hostSubscriptions),
          );
          final now = writeDependency(() => (clock ?? DateTime.now)().toUtc());
          await (db.update(
            db.storedRuns,
          )..where((t) => t.runId.equals(run.runId.value))).write(
            StoredRunsCompanion(
              recordState: Value(DiagnosticRecordState.recoveredArchived.code),
              recoveredAtUs: Value(now.microsecondsSinceEpoch),
              recoveryReason: Value(
                (state == DiagnosticRecordState.prepared
                        ? RecoveryReason.interrupted
                        : RecoveryReason.cleanupUnconfirmed)
                    .code,
              ),
              cleanupJson: Value(encodeCleanupSummary(cleanup)),
            ),
          );
        }
        return batch;
      });
      if (rows.isEmpty) break;
      cursor = rows.last;
      if (rows.length < recoveryBatchSize) break;
    }
  }
});

final class _BeforeRun extends Expression<bool> {
  const _BeforeRun(this.table, this.row);
  final StoredRuns table;
  final StoredRun row;
  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('(');
    table.preparedAtUs.writeInto(context);
    context.buffer.write(', ');
    table.runId.writeInto(context);
    context.buffer.write(') < (');
    Variable<int>(row.preparedAtUs).writeInto(context);
    context.buffer.write(', ');
    Variable<String>(row.runId).writeInto(context);
    context.buffer.write(')');
  }
}
