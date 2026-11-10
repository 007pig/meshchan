import '../session/meshcore_session.dart';

enum DiagnosticTaskReason {
  completed,
  startRejected,
  nonceGenerationFailed,
  initializationFailed,
  sendFailed,
  receptionFailed,
  sessionFailed,
  responseTimeout,
  taskTimeout,
  canceled,
  entryLimit,
}

enum DiagnosticTaskStage {
  startup,
  nonceGeneration,
  connecting,
  receiving,
  sending,
  waiting,
  settling,
}

enum DiagnosticListenStopReason { durationElapsed, responseLimit, entryLimit }

enum DiagnosticCleanupState {
  notStarted,
  notRequired,
  pending,
  succeeded,
  failed,
}

/// Local rejection with a private, explicitly inspectable original cause.
final class DiagnosticTaskStartError implements Exception {
  const DiagnosticTaskStartError(this.cause, this.stackTrace);
  final Object cause;
  final StackTrace stackTrace;
  @override
  String toString() => 'DiagnosticTaskStartError: Task start was rejected.';
}

/// The first primary failure. Default formatting never recursively prints input.
final class DiagnosticTaskFailure {
  const DiagnosticTaskFailure(this.stage, this.cause, this.stackTrace);
  final DiagnosticTaskStage stage;
  final Object cause;
  final StackTrace stackTrace;
  @override
  String toString() => 'DiagnosticTaskFailure(stage: ${stage.name})';
}

/// Nullable facts distinguish unattempted/unconfirmed work from frozen facts.
/// A local OK observed before a failed write is not confirmed acceptance.
final class DiagnosticSendFacts {
  const DiagnosticSendFacts({
    required this.attempted,
    required this.pendingAtTermination,
    required this.deviceAcceptanceConfirmed,
    this.dispatched,
    this.localWriteCompleted,
    this.localOkObserved,
    this.commandFailure,
  });
  final bool attempted;
  final bool pendingAtTermination;
  final bool? dispatched;
  final bool? localWriteCompleted;
  final bool? localOkObserved;
  final bool deviceAcceptanceConfirmed;
  final MeshCoreSessionCommandFailure? commandFailure;
  @override
  String toString() =>
      'DiagnosticSendFacts(attempted: $attempted, '
      'pendingAtTermination: $pendingAtTermination, dispatched: $dispatched, '
      'localWriteCompleted: $localWriteCompleted, localOkObserved: '
      '$localOkObserved, deviceAcceptanceConfirmed: $deviceAcceptanceConfirmed)';
}

final class DiagnosticCleanupResult {
  DiagnosticCleanupResult(this.state, Iterable<DiagnosticTaskFailure> failures)
    : failures = List.unmodifiable(failures);
  final DiagnosticCleanupState state;
  final List<DiagnosticTaskFailure> failures;
  @override
  String toString() =>
      'DiagnosticCleanupResult(${state.name}, failures: ${failures.length})';
}

sealed class DiagnosticTaskResult {
  const DiagnosticTaskResult({
    required this.reason,
    required this.stage,
    required this.send,
    required this.processedEntries,
    this.failure,
    this.sessionInfo,
    this.sessionFailure,
    this.reception,
  });
  final DiagnosticTaskReason reason;
  final DiagnosticTaskStage stage;
  final DiagnosticSendFacts send;
  final int processedEntries;
  final DiagnosticTaskFailure? failure;
  final MeshCoreSessionInfo? sessionInfo;
  final MeshCoreSessionFailure? sessionFailure;
  final MeshCoreReceptionResult? reception;
  int get publishedEntries => reception?.publishedEntries ?? 0;
  @override
  String toString() =>
      '$runtimeType(${reason.name}, stage: ${stage.name}, '
      'processedEntries: $processedEntries, publishedEntries: $publishedEntries)';
}

final class DiagnosticPingResult extends DiagnosticTaskResult {
  const DiagnosticPingResult({
    required super.reason,
    required super.stage,
    required super.send,
    required super.processedEntries,
    super.failure,
    super.sessionInfo,
    super.sessionFailure,
    super.reception,
    required this.firstMatchingPongElapsed,
    required this.matchingPongDuplicates,
  });
  final Duration? firstMatchingPongElapsed;
  final int matchingPongDuplicates;
  bool get matchingPongObserved => firstMatchingPongElapsed != null;
  bool get exactContentValidated => matchingPongObserved;
  bool get roundTripSucceeded => reason == DiagnosticTaskReason.completed;
  Duration? get applicationRtt =>
      roundTripSucceeded ? firstMatchingPongElapsed : null;
}

final class DiagnosticResponderResult extends DiagnosticTaskResult {
  const DiagnosticResponderResult({
    required super.reason,
    required super.stage,
    required super.send,
    required super.processedEntries,
    super.failure,
    super.sessionInfo,
    super.sessionFailure,
    super.reception,
    required this.listenStopReason,
    required this.responseAttempts,
    required this.localResponsesConfirmed,
    required this.duplicates,
    required this.conflicts,
    required this.cacheCapacityRejections,
    required this.returnCapacityRejections,
  });
  final DiagnosticListenStopReason? listenStopReason;
  final int responseAttempts;
  final int localResponsesConfirmed;
  final int duplicates;
  final int conflicts;
  final int cacheCapacityRejections;
  final int returnCapacityRejections;
}
