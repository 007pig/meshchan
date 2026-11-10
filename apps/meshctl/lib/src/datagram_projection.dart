import 'package:meshcore_link/meshcore_link.dart';

import 'cli_display.dart';

Map<String, Object?> diagnosticFailure(
  String domain,
  String? kind,
  String? stage, [
  MeshCoreSessionFailure? session,
]) => {
  'domain': domain,
  'kind': kind,
  'stage': stage,
  'session': session == null ? null : failureFields(session),
};

// Only direct, explicitly typed evidence; never walk cause/stack object graphs.
MeshCoreSessionFailure? sessionEvidence(Object? value) => switch (value) {
  MeshCoreSessionFailure() => value,
  MeshCoreSessionCommandFailure() => value.sessionFailure,
  _ => null,
};

Map<String, Object?> sendProjection(DiagnosticSendFacts send) => {
  'attempted': send.attempted,
  'pendingAtTermination': send.pendingAtTermination,
  'dispatched': send.dispatched,
  'localWriteCompleted': send.localWriteCompleted,
  'localOkObserved': send.localOkObserved,
  'deviceAcceptanceConfirmed': send.deviceAcceptanceConfirmed,
};

Map<String, Object?>? receptionProjection(MeshCoreReceptionResult? result) =>
    result == null
    ? null
    : {
        'reason': result.reason.name,
        'publishedEntries': result.publishedEntries,
        'dispatchedReads': result.dispatchedReads,
        'completedReads': result.completedReads,
      };

Map<String, Object?> taskFailureProjection(DiagnosticTaskResult result) =>
    diagnosticFailure(
      'task',
      result.reason.name,
      result.stage.name,
      result.sessionFailure ??
          result.send.commandFailure?.sessionFailure ??
          result.reception?.sessionFailure ??
          result.reception?.commandFailure?.sessionFailure ??
          sessionEvidence(result.failure?.cause),
    );

Map<String, Object?> taskProjection(DiagnosticTaskResult result) => {
  'reason': result.reason.name,
  'stage': result.stage.name,
  if (result is DiagnosticPingResult) ...{
    'send': sendProjection(result.send),
    'matchingPongObserved': result.matchingPongObserved,
    'exactContentValidated': result.exactContentValidated,
    'roundTripSucceeded': result.roundTripSucceeded,
    'firstMatchingPongElapsedUs':
        result.firstMatchingPongElapsed?.inMicroseconds,
    'applicationRttUs': result.applicationRtt?.inMicroseconds,
    'matchingPongDuplicates': result.matchingPongDuplicates,
  },
  if (result is DiagnosticResponderResult) ...{
    'listenStopReason': result.listenStopReason?.name,
    'lastSend': sendProjection(result.send),
    'responseAttempts': result.responseAttempts,
    'localResponsesConfirmed': result.localResponsesConfirmed,
    'duplicates': result.duplicates,
    'conflicts': result.conflicts,
    'cacheCapacityRejections': result.cacheCapacityRejections,
    'returnCapacityRejections': result.returnCapacityRejections,
  },
  'publishedEntries': result.publishedEntries,
  'processedEntries': result.processedEntries,
  'reception': receptionProjection(result.reception),
};
