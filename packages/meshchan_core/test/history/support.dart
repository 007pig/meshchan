import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/recording/projection.dart';
import 'package:meshchan_core/src/recording/validation.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/storage.dart';

import '../recording/support.dart';
import '../repositories/draft_repository_test.dart' show Control;

export '../recording/support.dart';
export '../recording/run_store_test.dart' show logical;

final terminal = combineCleanup(
  CleanupScopeSummary(state: CleanupState.succeeded),
  CleanupScopeSummary(state: CleanupState.notRequired),
);
DiagnosticRun sample(
  int id, {
  DiagnosticOperation operation = DiagnosticOperation.send,
  DiagnosticRecordState state = DiagnosticRecordState.settled,
  DateTime? time,
  CleanupSummary? cleanup,
  LogicalSummary? result,
  LocalId? profileId,
}) {
  final archived = state == DiagnosticRecordState.recoveredArchived;
  final prepared = state == DiagnosticRecordState.prepared;
  final run = DiagnosticRun(
    runId: fixtureId(id),
    appVersion: 'host-1.2.3',
    configuration: projectConfiguration(input(operation)),
    preparedAt: time ?? instant,
    profileId: profileId,
    recordState: state,
    logicalEndedAt: prepared || archived
        ? null
        : instant.add(const Duration(days: 10)),
    result:
        result ??
        (prepared || archived
            ? null
            : switch (operation) {
                DiagnosticOperation.send => const SendSummary(
                  reason: LogicalReason.canceled,
                  stage: DiagnosticStage.sending,
                ),
                DiagnosticOperation.listen => const ListenSummary(
                  reason: LogicalReason.canceled,
                  stage: DiagnosticStage.receiving,
                ),
                DiagnosticOperation.ping => const PingSummary(
                  reason: LogicalReason.canceled,
                  stage: DiagnosticStage.sending,
                ),
                DiagnosticOperation.respond => const RespondSummary(
                  reason: LogicalReason.canceled,
                  stage: DiagnosticStage.receiving,
                ),
              }),
    cleanup: cleanup ?? terminal,
    recoveredAt: archived ? instant.add(const Duration(days: 20)) : null,
    recoveryReason: archived ? RecoveryReason.interrupted : null,
  );
  validateRun(run);
  return run;
}

class HistoryControl extends Control {
  HistoryControl() : super(readTable: 'stored_runs');
  bool capture = false;
  final selects = <(String, List<Object?>, List<String>)>[];
  int deletes = 0, commits = 0;
  int? failDelete, failCommit;
  void Function()? afterCommit;
  final hostZone = Zone.current;
  Future<void> Function(String, List<Object?>, List<Map<String, Object?>>)?
  selected;
  void Function(String, List<Object?>)? updated;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (capture &&
        statement.startsWith('SELECT') &&
        statement.contains('stored_runs')) {
      final plan = await executor.runSelect(
        'EXPLAIN QUERY PLAN $statement',
        args,
      );
      selects.add((
        statement,
        List.of(args),
        plan.map((r) => r['detail'] as String).toList(),
      ));
    }
    final rows = await super.runSelect(executor, statement, args);
    await selected?.call(statement, args, rows);
    return rows;
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final count = await super.runUpdate(executor, statement, args);
    updated?.call(statement, args);
    return count;
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final count = await super.runDelete(executor, statement, args);
    if (statement.contains('stored_runs') && ++deletes == failDelete) {
      throw StateError('PRIVATE DELETE');
    }
    return count;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    if (++commits == failCommit) throw StateError('PRIVATE COMMIT');
    await super.commitTransaction(inner);
    final action = afterCommit;
    afterCommit = null;
    if (action != null) hostZone.run(action);
  }
}

class Fixture {
  final directory = Directory.systemTemp.createTempSync('meshchan-history-');
  final handles = <StorageHandle>[];
  Future<StorageHandle> open({
    HistoryControl? control,
    DateTime Function()? clock,
    LocalId Function()? runId,
  }) async {
    final storage = await openStorage(
      directory,
      hooks: StorageHooks(
        executorFactory: control == null
            ? null
            : (file) => NativeDatabase(file).interceptWith(control),
        clock: clock,
        runId: runId,
      ),
    ) as StorageHandle;
    handles.add(storage);
    return storage;
  }

  Future<void> seed(StorageHandle s, Iterable<DiagnosticRun> runs) =>
      s.useDatabase(
        (db) => db.transaction(() async {
          for (final run in runs) {
            await db.into(db.storedRuns).insert(encodeRun(run));
          }
        }),
      );
  Future<List<LocalId>> ids(StorageHandle s) async =>
      (await s.history.query(size: PageSize(200))).items
          .map((r) => r.runId)
          .toList();
  Future<int> count(StorageHandle s) => s.useDatabase(
    (db) async =>
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM stored_runs')
                .getSingle())
            .read<int>('n'),
  );
  Future<void> close() async {
    for (final s in handles.reversed) {
      await s.close();
    }
    directory.deleteSync(recursive: true);
  }
}
