import 'package:meshcore_link/meshcore_link.dart' as link;

import '../models/connection_profile.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_configuration.dart';
import '../models/diagnostic_run.dart';
import '../models/effective_parameters.dart';

DiagnosticRoute _route(ProfileRoute route) => DiagnosticRoute(
  routeDescriptor: route.routeDescriptor,
  pathByteCount: route.path.length,
);

DiagnosticConfiguration projectConfiguration(EffectiveParameters value) {
  final p = value.parameters;
  return switch (p) {
    SendProfileParameters() => SendConfiguration(
      budgets: p.budgets,
      sendChannelIndex: p.sendChannelIndex,
      dataType: p.dataType,
      route: _route(p.route),
      payloadByteLength: value.content!.length,
    ),
    ListenProfileParameters() => ListenConfiguration(
      budgets: p.budgets,
      receiveChannelIndex: p.receiveChannelIndex,
      dataType: p.dataType,
      listenDurationSeconds: p.listenDurationSeconds,
      maxEntries: p.maxEntries,
    ),
    PingProfileParameters() => PingConfiguration(
      budgets: p.budgets,
      sendChannelIndex: p.sendChannelIndex,
      receiveChannelIndex: p.receiveChannelIndex,
      route: _route(p.route),
      maxEntries: p.maxEntries,
      responseTimeoutSeconds: p.responseTimeoutSeconds,
      contentByteLength: value.content!.length,
    ),
    RespondProfileParameters() => RespondConfiguration(
      budgets: p.budgets,
      sendChannelIndex: p.sendChannelIndex,
      receiveChannelIndex: p.receiveChannelIndex,
      route: _route(p.route),
      maxEntries: p.maxEntries,
      listenDurationSeconds: p.listenDurationSeconds,
      maxResponses: p.maxResponses,
    ),
  };
}

// Read direct typed evidence only. In particular, never inspect cause chains.
link.MeshCoreSessionFailure? sessionEvidence(Object? value) => switch (value) {
  link.MeshCoreSessionFailure() => value,
  link.MeshCoreSessionCommandFailure() => value.sessionFailure,
  _ => null,
};

SessionFailureSummary projectSession(link.MeshCoreSessionFailure value) =>
    SessionFailureSummary(
      kind: sessionKind(value.kind),
      stage: sessionStage(value.stage),
      commandOpcode: value.commandOpcode,
      expectedResponseOpcode: value.expectedResponseOpcode,
      deviceErrorCode: value.deviceErrorCode,
      deviceErrorName: switch (value.deviceErrorName) {
        'unsupported command' => DeviceErrorName.unsupportedCommand,
        'not found' => DeviceErrorName.notFound,
        'table full' => DeviceErrorName.tableFull,
        'bad state' => DeviceErrorName.badState,
        'file I/O error' => DeviceErrorName.fileIoError,
        'illegal argument' => DeviceErrorName.illegalArgument,
        _ => null,
      },
    );

FailureSummary projectFailure(
  Object? evidence, {
  required FailureDomain domain,
  FailureKind? kind,
  DiagnosticStage? stage,
  HostCleanupStage? hostStage,
}) {
  final session = sessionEvidence(evidence);
  return FailureSummary(
    domain: domain,
    kind:
        kind ??
        (session == null
            ? FailureKind.unexpectedFailure
            : sessionKind(session.kind)),
    stage: stage,
    hostCleanupStage: hostStage,
    session: session == null ? null : projectSession(session),
  );
}

CommandFailureFacts projectCommand(link.MeshCoreSessionCommandFailure value) =>
    CommandFailureFacts(
      commandOpcode: value.commandOpcode,
      dispatched: value.dispatched,
      localWriteCompleted: value.localWriteCompleted,
      matchingResponseObserved: value.matchingResponseObserved,
      sessionFailure: projectSession(value.sessionFailure),
    );

SendFacts projectSend(link.DiagnosticSendFacts value) => SendFacts(
  attempted: value.attempted,
  pendingAtTermination: value.pendingAtTermination,
  dispatched: value.dispatched,
  localWriteCompleted: value.localWriteCompleted,
  localOkObserved: value.localOkObserved,
  deviceAcceptanceConfirmed: value.deviceAcceptanceConfirmed,
  commandFailure: value.commandFailure == null
      ? null
      : projectCommand(value.commandFailure!),
);

ReceptionSummary? projectReception(link.MeshCoreReceptionResult? value) =>
    value == null
    ? null
    : ReceptionSummary(
        reason: receptionReason(value.reason),
        publishedEntries: value.publishedEntries,
        dispatchedReads: value.dispatchedReads,
        completedReads: value.completedReads,
      );

LogicalSummary projectTask(link.DiagnosticTaskResult value) {
  final reason = taskReason(value.reason);
  final stage = taskStage(value.stage);
  final evidence =
      value.sessionFailure ??
      value.send.commandFailure?.sessionFailure ??
      value.reception?.sessionFailure ??
      value.reception?.commandFailure?.sessionFailure ??
      sessionEvidence(value.failure?.cause);
  final failure = value.reason == link.DiagnosticTaskReason.completed
      ? null
      : FailureSummary(
          domain: FailureDomain.task,
          kind: taskFailureKind(value.reason),
          stage: stage,
          session: evidence == null ? null : projectSession(evidence),
        );
  return switch (value) {
    link.DiagnosticPingResult() => PingSummary(
      reason: reason,
      stage: stage,
      failure: failure,
      send: projectSend(value.send),
      reception: projectReception(value.reception),
      processedEntries: value.processedEntries,
      matchingPongObserved: value.matchingPongObserved,
      exactContentValidated: value.exactContentValidated,
      roundTripSucceeded: value.roundTripSucceeded,
      firstMatchingPongElapsedUs:
          value.firstMatchingPongElapsed?.inMicroseconds,
      applicationRttUs: value.applicationRtt?.inMicroseconds,
      matchingPongDuplicates: value.matchingPongDuplicates,
    ),
    link.DiagnosticResponderResult() => RespondSummary(
      reason: reason,
      stage: stage,
      failure: failure,
      lastSend: projectSend(value.send),
      reception: projectReception(value.reception),
      processedEntries: value.processedEntries,
      listenStopReason: switch (value.listenStopReason) {
        null => null,
        link.DiagnosticListenStopReason.durationElapsed =>
          ListenStopReason.durationElapsed,
        link.DiagnosticListenStopReason.responseLimit =>
          ListenStopReason.responseLimit,
        link.DiagnosticListenStopReason.entryLimit =>
          ListenStopReason.entryLimit,
      },
      responseAttempts: value.responseAttempts,
      localResponsesConfirmed: value.localResponsesConfirmed,
      duplicates: value.duplicates,
      conflicts: value.conflicts,
      cacheCapacityRejections: value.cacheCapacityRejections,
      returnCapacityRejections: value.returnCapacityRejections,
    ),
  };
}

CleanupScopeSummary projectTaskCleanup(link.DiagnosticCleanupResult value) =>
    CleanupScopeSummary(
      state: switch (value.state) {
        link.DiagnosticCleanupState.notStarted => CleanupState.unconfirmed,
        link.DiagnosticCleanupState.notRequired => CleanupState.notRequired,
        link.DiagnosticCleanupState.pending => CleanupState.pending,
        link.DiagnosticCleanupState.succeeded => CleanupState.succeeded,
        link.DiagnosticCleanupState.failed => CleanupState.failed,
      },
      failures: value.failures.map(
        (f) => projectFailure(
          f.cause,
          domain: FailureDomain.cleanup,
          kind: FailureKind.cleanup,
          stage: taskStage(f.stage),
        ),
      ),
    );

LogicalReason taskReason(link.DiagnosticTaskReason value) => switch (value) {
  link.DiagnosticTaskReason.completed => LogicalReason.completed,
  link.DiagnosticTaskReason.startRejected => LogicalReason.startRejected,
  link.DiagnosticTaskReason.nonceGenerationFailed =>
    LogicalReason.nonceGenerationFailed,
  link.DiagnosticTaskReason.initializationFailed =>
    LogicalReason.initializationFailed,
  link.DiagnosticTaskReason.sendFailed => LogicalReason.sendFailed,
  link.DiagnosticTaskReason.receptionFailed => LogicalReason.receptionFailed,
  link.DiagnosticTaskReason.sessionFailed => LogicalReason.sessionFailed,
  link.DiagnosticTaskReason.responseTimeout => LogicalReason.responseTimeout,
  link.DiagnosticTaskReason.taskTimeout => LogicalReason.taskTimeout,
  link.DiagnosticTaskReason.canceled => LogicalReason.canceled,
  link.DiagnosticTaskReason.entryLimit => LogicalReason.entryLimit,
};

DiagnosticStage taskStage(link.DiagnosticTaskStage value) => switch (value) {
  link.DiagnosticTaskStage.startup => DiagnosticStage.startup,
  link.DiagnosticTaskStage.nonceGeneration => DiagnosticStage.nonceGeneration,
  link.DiagnosticTaskStage.connecting => DiagnosticStage.connecting,
  link.DiagnosticTaskStage.receiving => DiagnosticStage.receiving,
  link.DiagnosticTaskStage.sending => DiagnosticStage.sending,
  link.DiagnosticTaskStage.waiting => DiagnosticStage.waiting,
  link.DiagnosticTaskStage.settling => DiagnosticStage.settling,
};

FailureKind sessionKind(
  link.MeshCoreSessionFailureKind value,
) => switch (value) {
  link.MeshCoreSessionFailureKind.transport => FailureKind.transport,
  link.MeshCoreSessionFailureKind.protocol => FailureKind.protocol,
  link.MeshCoreSessionFailureKind.deviceRejected => FailureKind.deviceRejected,
  link.MeshCoreSessionFailureKind.requestTimeout => FailureKind.requestTimeout,
  link.MeshCoreSessionFailureKind.initializationTimeout =>
    FailureKind.initializationTimeout,
  link.MeshCoreSessionFailureKind.disconnected => FailureKind.disconnected,
  link.MeshCoreSessionFailureKind.canceled => FailureKind.canceled,
  link.MeshCoreSessionFailureKind.cleanup => FailureKind.cleanup,
};

SessionStage sessionStage(link.MeshCoreSessionState value) => switch (value) {
  link.MeshCoreSessionState.idle => SessionStage.idle,
  link.MeshCoreSessionState.opening => SessionStage.opening,
  link.MeshCoreSessionState.initializing => SessionStage.initializing,
  link.MeshCoreSessionState.ready => SessionStage.ready,
  link.MeshCoreSessionState.closing => SessionStage.closing,
  link.MeshCoreSessionState.closed => SessionStage.closed,
  link.MeshCoreSessionState.failed => SessionStage.failed,
};

ReceptionReason receptionReason(link.MeshCoreReceptionStopReason value) =>
    switch (value) {
      link.MeshCoreReceptionStopReason.startRejected =>
        ReceptionReason.startRejected,
      link.MeshCoreReceptionStopReason.stopped => ReceptionReason.stopped,
      link.MeshCoreReceptionStopReason.subscriptionCanceled =>
        ReceptionReason.subscriptionCanceled,
      link.MeshCoreReceptionStopReason.durationElapsed =>
        ReceptionReason.durationElapsed,
      link.MeshCoreReceptionStopReason.entryLimit => ReceptionReason.entryLimit,
      link.MeshCoreReceptionStopReason.sessionClosed =>
        ReceptionReason.sessionClosed,
      link.MeshCoreReceptionStopReason.sessionFailed =>
        ReceptionReason.sessionFailed,
    };

FailureKind? taskFailureKind(link.DiagnosticTaskReason value) =>
    switch (value) {
      link.DiagnosticTaskReason.completed => null,
      link.DiagnosticTaskReason.startRejected => FailureKind.startRejected,
      link.DiagnosticTaskReason.nonceGenerationFailed =>
        FailureKind.nonceGenerationFailed,
      link.DiagnosticTaskReason.initializationFailed =>
        FailureKind.initializationFailed,
      link.DiagnosticTaskReason.sendFailed => FailureKind.sendFailed,
      link.DiagnosticTaskReason.receptionFailed => FailureKind.receptionFailed,
      link.DiagnosticTaskReason.sessionFailed => FailureKind.sessionFailed,
      link.DiagnosticTaskReason.responseTimeout => FailureKind.responseTimeout,
      link.DiagnosticTaskReason.taskTimeout => FailureKind.taskTimeout,
      link.DiagnosticTaskReason.canceled => FailureKind.canceled,
      link.DiagnosticTaskReason.entryLimit => null,
    };
