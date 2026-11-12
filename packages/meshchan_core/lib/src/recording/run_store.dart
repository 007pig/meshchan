import 'dart:convert';

import 'package:drift/drift.dart';

import '../errors.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_configuration.dart';
import '../models/diagnostic_run.dart';
import '../repositories/write_support.dart';
import '../storage/codec.dart';
import '../storage/database.dart';
import '../storage/preflight.dart';
import '../values.dart';
import 'validation.dart';

Future<T> runWrite<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error) {
    if (error is TypeError || error is FormatException) {
      throw const CoreException(CoreErrorCode.databaseCorrupt);
    }
    throw classifyStorageError(error, CoreErrorCode.storageWriteFailed);
  }
}

Future<DiagnosticRun> readRun(CoreDatabase db, LocalId id) async {
  final row = await (db.select(
    db.storedRuns,
  )..where((t) => t.runId.equals(id.value))).getSingleOrNull();
  if (row == null) throw const CoreException(CoreErrorCode.notFound);
  return validateStoredRun(decodeRun(row));
}

/// One admitted run, multiple short transactions. A rejected write cannot poison
/// the tail. No call here acquires another storage admission.
final class RunStore {
  RunStore(
    this.db, {
    LocalId Function()? generateId,
    DateTime Function()? clock,
  }) : _generateId = generateId ?? randomLocalId,
       _clock = clock ?? DateTime.now;
  final CoreDatabase db;
  final LocalId Function() _generateId;
  final DateTime Function() _clock;
  Future<void> _tail = Future.value();
  DateTime observeTime() => writeDependency(() => _clock().toUtc());
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => runWrite(action));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<DiagnosticRun> register({
    required String appVersion,
    required DiagnosticConfiguration configuration,
    required LocalId? profileId,
    required bool hostRequired,
  }) => _enqueue(
    () => db.transaction(() async {
      final time = observeTime();
      for (var attempt = 0; attempt < 8; attempt++) {
        final run = DiagnosticRun(
          runId: writeDependency(_generateId),
          appVersion: appVersion,
          configuration: configuration,
          preparedAt: time,
          profileId: profileId,
          cleanup: combineCleanup(
            CleanupScopeSummary(),
            CleanupScopeSummary(
              state: hostRequired
                  ? CleanupState.unconfirmed
                  : CleanupState.notRequired,
            ),
          ),
        );
        validateRun(run);
        final row = await db
            .into(db.storedRuns)
            .insertReturningOrNull(
              encodeRun(run),
              onConflict: DoNothing(target: [db.storedRuns.runId]),
            );
        if (row != null) return validateStoredRun(decodeRun(row));
      }
      throw const CoreException(CoreErrorCode.storageWriteFailed);
    }),
  );

  Future<DiagnosticRun> saveLogical(
    LocalId id,
    LogicalSummary result,
    DateTime observedAt,
  ) => _enqueue(
    () => db.transaction(() async {
      final current = await readRun(db, id);
      if (current.recordState == DiagnosticRecordState.recoveredArchived) {
        throw const CoreException(CoreErrorCode.conflict);
      }
      validateLogical(result, current.configuration);
      if (result.reason == null || result.stage == null || !observedAt.isUtc) {
        throw const CoreException(CoreErrorCode.invalidInput);
      }
      if (current.recordState == DiagnosticRecordState.settled) {
        if (encodeLogicalSummary(current.result!) ==
            encodeLogicalSummary(result)) {
          return current;
        }
        throw const CoreException(CoreErrorCode.conflict);
      }
      if (current.result != null &&
          !_preserves(
            jsonDecode(encodeLogicalSummary(current.result!)),
            jsonDecode(encodeLogicalSummary(result)),
          )) {
        throw const CoreException(CoreErrorCode.conflict);
      }
      await (db.update(
        db.storedRuns,
      )..where((t) => t.runId.equals(id.value))).write(
        StoredRunsCompanion(
          resultJson: Value(encodeLogicalSummary(result)),
          logicalEndedAtUs: Value(observedAt.microsecondsSinceEpoch),
          recordState: Value(DiagnosticRecordState.settled.code),
        ),
      );
      return readRun(db, id);
    }),
  );

  Future<DiagnosticRun> saveCleanup(
    LocalId id, {
    CleanupScopeSummary? core,
    CleanupScopeSummary? host,
  }) => _enqueue(
    () => db.transaction(() async {
      final current = await readRun(db, id);
      if (current.recordState == DiagnosticRecordState.recoveredArchived) {
        throw const CoreException(CoreErrorCode.conflict);
      }
      final merged = combineCleanup(
        _merge(current.cleanup.core, core),
        _merge(current.cleanup.hostSubscriptions, host),
      );
      if (encodeCleanupSummary(merged) ==
          encodeCleanupSummary(current.cleanup)) {
        return current;
      }
      // Validate against the current logical fields; never write a stale full row.
      validateRun(
        DiagnosticRun(
          runId: current.runId,
          appVersion: current.appVersion,
          configuration: current.configuration,
          profileId: current.profileId,
          preparedAt: current.preparedAt,
          result: current.result,
          logicalEndedAt: current.logicalEndedAt,
          recordState: current.recordState,
          cleanup: merged,
        ),
      );
      await (db.update(
        db.storedRuns,
      )..where((t) => t.runId.equals(id.value))).write(
        StoredRunsCompanion(cleanupJson: Value(encodeCleanupSummary(merged))),
      );
      return readRun(db, id);
    }),
  );
}

String _scopeKey(CleanupScopeSummary s) => encodeCleanupSummary(
  combineCleanup(s, CleanupScopeSummary(state: CleanupState.notRequired)),
);
CleanupScopeSummary _merge(CleanupScopeSummary old, CleanupScopeSummary? next) {
  if (next == null || _scopeKey(old) == _scopeKey(next)) return old;
  if (terminalCleanup(old.state) ||
      old.state == CleanupState.unconfirmedAfterExit ||
      next.state == CleanupState.unconfirmedAfterExit ||
      (old.state == CleanupState.pending &&
          next.state == CleanupState.unconfirmed)) {
    throw const CoreException(CoreErrorCode.conflict);
  }
  // A source reports cumulative snapshots. Preserve the ordered prefix, including
  // two distinct failures of the same category, without appending it twice.
  if (next.failures.length < old.failures.length) {
    throw const CoreException(CoreErrorCode.conflict);
  }
  for (var i = 0; i < old.failures.length; i++) {
    final a = CleanupScopeSummary(
      state: CleanupState.pending,
      failures: [old.failures[i]],
    );
    final b = CleanupScopeSummary(
      state: CleanupState.pending,
      failures: [next.failures[i]],
    );
    if (_scopeKey(a) != _scopeKey(b)) {
      throw const CoreException(CoreErrorCode.conflict);
    }
  }
  return next;
}

bool _preserves(Object? before, Object? after, [String? field]) {
  if (before == null) return true;
  if (before is Map && after is Map) {
    return before.keys.every(
      (k) => _preserves(before[k], after[k], k as String),
    );
  }
  // Counts may increase; true observations and exact elapsed facts cannot vanish.
  // Partial false acceptance only means unconfirmed, and can become confirmed.
  if (before is bool && after is bool) return !before || after;
  if (before is int &&
      after is int &&
      const {
        'publishedEntries',
        'processedEntries',
        'dispatchedReads',
        'completedReads',
        'matchingDatagrams',
        'filteredDatagrams',
        'ordinaryMessages',
        'matchingPongDuplicates',
        'responseAttempts',
        'localResponsesConfirmed',
        'duplicates',
        'conflicts',
        'cacheCapacityRejections',
        'returnCapacityRejections',
      }.contains(field)) {
    return after >= before;
  }
  return before == after;
}
