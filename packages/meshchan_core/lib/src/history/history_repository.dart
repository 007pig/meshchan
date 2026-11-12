import '../errors.dart';
import '../models/diagnostic_run.dart';
import '../recording/run_store.dart';
import '../repositories.dart';
import '../storage/codec.dart';
import '../storage/storage.dart';
import '../values.dart';
import 'history_store.dart';

final class PersistentDiagnosticHistory implements DiagnosticHistory {
  PersistentDiagnosticHistory(this._storage, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final StorageHandle _storage;
  final DateTime Function() _clock;

  @override
  Future<DiagnosticRun> read(LocalId runId) =>
      _storage.useDatabase((db) => readRun(db, runId));

  @override
  Future<Page<DiagnosticRun, HistoryCursor>> query({
    HistoryQuery? filter,
    PageSize? size,
    HistoryCursor? after,
  }) => _storage.useDatabase(
    (db) => queryRuns(db, filter: filter, size: size, after: after),
  );

  @override
  Future<void> delete(LocalId runId) => _storage.useDatabase((db) async {
    await db.transaction(() async {
      final run = await readRun(db, runId);
      if (!eligibleHistory(run) || _storage.isRunPinned(runId)) {
        throw const CoreException(CoreErrorCode.conflict);
      }
      await deleteRun(db, runId);
      _storage.invalidateHistorySelection();
    });
    _storage.requestHistoryMaintenance();
  }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<DiagnosticSummaryPage> exportSummary({
    HistoryQuery? filter,
    PageSize? size,
    HistoryCursor? after,
  }) => _storage.useDatabase((db) async {
    final page = await queryRuns(db, filter: filter, size: size, after: after);
    // Generation is outside stored-row classification. A host clock or JSON
    // encoder failure is a read failure, never evidence of damaged storage.
    try {
      return DiagnosticSummaryPage(
        json: encodeDiagnosticExport(page.items, _clock().toUtc()),
        nextCursor: page.nextCursor,
      );
    } catch (_) {
      throw const CoreException(CoreErrorCode.storageReadFailed);
    }
  });

  @override
  Future<HistoryMaintenanceReport> maintain() =>
      _storage.useDatabase((_) => _storage.requestHistoryMaintenance());
  @override
  Future<HistoryMaintenanceReport> waitForMaintenance() =>
      _storage.useDatabase((_) => _storage.waitForHistoryMaintenance());
  @override
  HistoryMaintenanceReport? get latestMaintenance =>
      _storage.latestHistoryMaintenance;
  @override
  HistoryMaintenanceReport? get unacknowledgedFailure =>
      _storage.historyMaintenanceFailure;
  @override
  int get unacknowledgedFailureCount => _storage.historyMaintenanceFailureCount;
  @override
  void acknowledgeMaintenanceFailures() =>
      _storage.acknowledgeHistoryMaintenanceFailures();
}
