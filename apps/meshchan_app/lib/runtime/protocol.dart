import 'dart:isolate';

import 'package:meshchan_core/meshchan_core.dart';

enum RuntimePhase {
  starting,
  opening,
  ready,
  busy,
  stopping,
  closing,
  closed,
  fault,
}

enum OwnerFact { none, held, released, unknown }

enum DeviceGateState { free, occupied, quarantined }

enum CoordinationFault {
  invalidState,
  staleRequest,
  deviceBusy,
  stopped,
  requestUnknown,
  spawnFailed,
  workerFailed,
  workerExited,
  releaseUnconfirmed,
  observationFailed,
}

/// Only controlled categories cross the bridge; never native exceptions/stacks.
final class RuntimeFault implements Exception {
  const RuntimeFault({this.core, this.host, this.cleanupUnconfirmed = false});
  factory RuntimeFault.from(Object error) => error is CoreException
      ? RuntimeFault(
          core: error.code,
          cleanupUnconfirmed: error.cleanupUnconfirmed,
        )
      : error is RuntimeFault
      ? error
      : const RuntimeFault(host: CoordinationFault.observationFailed);
  final CoreErrorCode? core;
  final CoordinationFault? host;
  final bool cleanupUnconfirmed;
  String get code => core?.code ?? host!.name;
  @override
  String toString() => 'RuntimeFault($code)';
}

final class MaintenanceSnapshot {
  const MaintenanceSnapshot(
    this.latest,
    this.failure,
    this.failureCount, {
    this.latestReport,
    this.unacknowledgedReport,
  });
  final HistoryMaintenanceState? latest;
  final CoreErrorCode? failure;
  final int failureCount;
  final MaintenanceReportSnapshot? latestReport, unacknowledgedReport;
}

final class MaintenanceReportSnapshot {
  MaintenanceReportSnapshot(HistoryMaintenanceReport report)
    : state = report.state,
      deletedCount = report.deletedCount,
      deferredCount = report.deferredCount,
      historyLimit = report.historyLimit,
      error = report.error?.code;
  final HistoryMaintenanceState state;
  final int deletedCount, deferredCount;
  final int? historyLimit;
  final CoreErrorCode? error;
}

final class SaveSnapshot {
  const SaveSnapshot(
    this.state,
    this.finalCleanup,
    this.error, {
    this.cleanupUnconfirmed = false,
  });
  factory SaveSnapshot.from(RecordingSave save) => SaveSnapshot(
    save.state,
    save.finalCleanup,
    save.error?.code,
    cleanupUnconfirmed: save.error?.cleanupUnconfirmed ?? false,
  );
  final RecordingSaveState state;
  final bool finalCleanup;
  final CoreErrorCode? error;
  final bool cleanupUnconfirmed;
}

final class OperationSnapshot {
  const OperationSnapshot({
    required this.generation,
    this.runId,
    this.logical,
    this.registration,
    this.logicalSave,
    this.cleanupSave,
    this.coreCleanup,
    this.hostCleanup,
    this.aggregate,
    this.coordinationFailure = false,
    this.coordinationKind,
    this.observationFailure = false,
    this.done = false,
  });
  final int generation;
  final String? runId;
  final LogicalReason? logical;
  final SaveSnapshot? registration, logicalSave, cleanupSave;
  final CleanupState? coreCleanup, hostCleanup, aggregate;
  final bool coordinationFailure, observationFailure, done;
  final FailureKind? coordinationKind;
  bool get resourcesReleased =>
      done &&
      !observationFailure &&
      _released(coreCleanup) &&
      _released(hostCleanup) &&
      _released(aggregate);
  static bool _released(CleanupState? state) =>
      state == CleanupState.succeeded || state == CleanupState.notRequired;
}

final class RuntimeSnapshot {
  const RuntimeSnapshot({
    required this.generation,
    this.sequence = 0,
    this.phase = RuntimePhase.starting,
    this.owner = OwnerFact.none,
    this.storage,
    this.gate = DeviceGateState.free,
    this.stopReceived = false,
    this.stopApplied = false,
    this.admissionPaused = false,
    this.workerExited = false,
    this.error,
    this.maintenance,
    this.operation,
  });
  final int generation, sequence;
  final RuntimePhase phase;
  final OwnerFact owner;
  final StorageState? storage;
  final DeviceGateState gate;
  final bool stopReceived, stopApplied, admissionPaused, workerExited;
  final RuntimeFault? error;
  final MaintenanceSnapshot? maintenance;
  final OperationSnapshot? operation;
}

final class DraftSnapshot {
  const DraftSnapshot(
    this.id,
    this.revision,
    this.title,
    this.body,
    this.createdAt,
    this.updatedAt,
    this.bodyUtf8Bytes,
  );
  factory DraftSnapshot.from(Draft d) => DraftSnapshot(
    d.id.value,
    d.revision,
    d.title,
    d.body,
    d.createdAt,
    d.updatedAt,
    d.bodyUtf8ByteLength,
  );
  final String id, title, body;
  final int revision, bodyUtf8Bytes;
  final DateTime createdAt, updatedAt;
}

final class DraftCursor {
  const DraftCursor(this.updatedAt, this.id);
  final DateTime updatedAt;
  final String id;
}

final class DraftPage extends ReplyValue {
  DraftPage(Iterable<DraftSnapshot> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<DraftSnapshot> items;
  final DraftCursor? nextCursor;
}

final class DeletedDraft extends ReplyValue {
  const DeletedDraft(this.id);
  final String id;
}

/// One decision, one document session, at most one final save. Not a general
/// admission bypass. Human decision time never occupies a pending worker RPC.
final class DraftDecision extends ReplyValue {
  const DraftDecision(this.generation, this.documentGeneration);
  final int generation, documentGeneration;
}

sealed class ReplyValue {
  const ReplyValue();
}

final class OfflineSnapshot extends ReplyValue {
  OfflineSnapshot(
    this.defaultProfileId,
    this.historyLimit,
    Iterable<DraftSnapshot> drafts,
    this.nextCursor,
  ) : drafts = List.unmodifiable(drafts);
  final String? defaultProfileId;
  final int historyLimit;
  final List<DraftSnapshot> drafts;
  final DraftCursor? nextCursor;
}

final class Accepted extends ReplyValue {
  const Accepted();
}

final class StatusValue extends ReplyValue {
  const StatusValue(this.snapshot);
  final RuntimeSnapshot snapshot;
}

final class DraftValue extends ReplyValue {
  const DraftValue(this.draft);
  final DraftSnapshot draft;
}

/// Explicit bootstrap values only. Production constructs dependencies in worker.
final class WorkerBootstrap {
  const WorkerBootstrap(
    this.generation,
    this.directory,
    this.events, {
    this.fixtureWrites = false,
  });
  final int generation;
  final String directory;
  final SendPort events;
  final bool fixtureWrites;
}

sealed class RuntimeRequest {
  const RuntimeRequest();
}

final class ListDrafts extends RuntimeRequest {
  const ListDrafts({this.size = 20, this.after});
  final int size;
  final DraftCursor? after;
}

final class ReadDraft extends RuntimeRequest {
  const ReadDraft(this.id);
  final String id;
}

final class WriteDraft extends RuntimeRequest {
  const WriteDraft({
    required this.title,
    required this.body,
    this.id,
    this.expectedRevision,
    this.decision,
  });
  final String title, body;
  final String? id;
  final int? expectedRevision;
  final DraftDecision? decision;
}

final class DeleteDraft extends RuntimeRequest {
  const DeleteDraft(this.id, this.expectedRevision);
  final String id;
  final int expectedRevision;
}

final class BeginDraftDecision extends RuntimeRequest {
  const BeginDraftDecision(this.decision);
  final DraftDecision decision;
}

final class EndDraftDecision extends RuntimeRequest {
  const EndDraftDecision(this.decision);
  final DraftDecision decision;
}

final class ReadOffline extends RuntimeRequest {
  const ReadOffline({this.pageSize = 20, this.after});
  final int pageSize; // App bound 1..50; core's independent bound is 1..200.
  final DraftCursor? after;
}

final class GetStatus extends RuntimeRequest {
  const GetStatus();
}

final class StopRuntime extends RuntimeRequest {
  const StopRuntime();
}

final class CancelOperation extends RuntimeRequest {
  const CancelOperation(this.operationGeneration);
  final int operationGeneration;
}

final class PauseAdmission extends RuntimeRequest {
  const PauseAdmission();
}

final class ResumeAdmission extends RuntimeRequest {
  const ResumeAdmission();
}

final class ShutdownRuntime extends RuntimeRequest {
  const ShutdownRuntime();
}

/// Fixed verification write, enabled only by explicit fixture bootstrap.
final class CreateFixtureDraft extends RuntimeRequest {
  const CreateFixtureDraft();
}

const runtimeFixtureTitle = 'Runtime 中文 🛰️';
const runtimeFixtureBody = 'First\r\n第二行 🙂\nLast\rEnd';

final class RequestEnvelope {
  const RequestEnvelope(this.generation, this.id, this.request);
  final int generation, id;
  final RuntimeRequest request;
}

final class ReleaseAcknowledged {
  const ReleaseAcknowledged(this.generation);
  final int generation;
}

sealed class WorkerEvent {
  const WorkerEvent(this.generation);
  final int generation;
}

final class WorkerHello extends WorkerEvent {
  const WorkerHello(super.generation, this.commands);
  final SendPort commands;
}

final class SnapshotEvent extends WorkerEvent {
  const SnapshotEvent(super.generation, this.snapshot);
  final RuntimeSnapshot snapshot;
}

final class RequestReply extends WorkerEvent {
  const RequestReply(super.generation, this.id, {this.value, this.error});
  final int id;
  final ReplyValue? value;
  final RuntimeFault? error;
}

final class ReleaseReport extends WorkerEvent {
  const ReleaseReport(
    super.generation,
    this.requestId,
    this.snapshot,
    this.resourcesReleased,
  );
  final int requestId;
  final RuntimeSnapshot snapshot;
  final bool resourcesReleased;
}
