import '../validation.dart';
import '../values.dart';
import 'diagnostic_codes.dart';
import 'diagnostic_configuration.dart';

/// Independent from databaseSchemaVersion and cliOutputSchemaVersion. The real
/// database version is introduced with the production database in 1C.3.
const diagnosticSummaryFormatVersion = 1;

final class SessionFailureSummary {
  const SessionFailureSummary({
    required this.kind,
    required this.stage,
    this.commandOpcode,
    this.expectedResponseOpcode,
    this.deviceErrorCode,
    this.deviceErrorName,
  });
  final FailureKind kind;
  final SessionStage stage;
  final int? commandOpcode;
  final int? expectedResponseOpcode;
  final int? deviceErrorCode;
  final DeviceErrorName? deviceErrorName;
}

/// Safe classified evidence; no raw cause, stack, or exception message.
final class FailureSummary {
  const FailureSummary({
    required this.domain,
    this.kind,
    this.stage,
    this.hostCleanupStage,
    this.session,
  });
  final FailureDomain domain;
  final FailureKind? kind;
  final DiagnosticStage? stage;
  final HostCleanupStage? hostCleanupStage;
  final SessionFailureSummary? session;
}

/// This command's facts remain separate from the root session failure, which
/// may have originated in a different queued command.
final class CommandFailureFacts {
  const CommandFailureFacts({
    required this.commandOpcode,
    required this.dispatched,
    required this.localWriteCompleted,
    required this.matchingResponseObserved,
    required this.sessionFailure,
  });
  final int commandOpcode;
  final bool dispatched;
  final bool localWriteCompleted;
  final bool matchingResponseObserved;
  final SessionFailureSummary sessionFailure;
}

/// Frozen send facts. Missing send facts are represented by a null summary.
/// False acceptance means unconfirmed acceptance, not proof of no RF emission.
final class SendFacts {
  const SendFacts({
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
  final bool deviceAcceptanceConfirmed;
  final bool? dispatched;
  final bool? localWriteCompleted;
  final bool? localOkObserved;
  final CommandFailureFacts? commandFailure;
}

final class ReceptionSummary {
  const ReceptionSummary({
    required this.reason,
    required this.publishedEntries,
    required this.dispatchedReads,
    required this.completedReads,
  });
  final ReceptionReason reason;
  final int publishedEntries;
  final int dispatchedReads;

  /// Includes both successful and failed reads.
  final int completedReads;
}

/// Reason/stage are absent for partial facts before logical settlement.
sealed class LogicalSummary {
  const LogicalSummary({this.reason, this.stage, this.failure});
  final LogicalReason? reason;
  final DiagnosticStage? stage;
  final FailureSummary? failure;
  DiagnosticOperation get operation;
}

final class SendSummary extends LogicalSummary {
  const SendSummary({super.reason, super.stage, super.failure, this.send});
  final SendFacts? send;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.send;
}

final class ListenSummary extends LogicalSummary {
  const ListenSummary({
    super.reason,
    super.stage,
    super.failure,
    this.reception,
    this.receptionReason,
    this.publishedEntries,
    this.processedEntries,
    this.matchingDatagrams,
    this.filteredDatagrams,
    this.ordinaryMessages,
  });
  final ReceptionSummary? reception;
  final ReceptionReason? receptionReason;
  final int? publishedEntries;
  final int? processedEntries;
  final int? matchingDatagrams;
  final int? filteredDatagrams;
  final int? ordinaryMessages;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.listen;
}

final class PingSummary extends LogicalSummary {
  const PingSummary({
    super.reason,
    super.stage,
    super.failure,
    this.send,
    this.reception,
    this.processedEntries,
    this.matchingPongObserved,
    this.exactContentValidated,
    this.roundTripSucceeded,
    this.firstMatchingPongElapsedUs,
    this.applicationRttUs,
    this.matchingPongDuplicates,
  });
  final SendFacts? send;
  final ReceptionSummary? reception;
  final int? processedEntries;
  final bool? matchingPongObserved;
  final bool? exactContentValidated;
  final bool? roundTripSucceeded;
  final int? firstMatchingPongElapsedUs;
  final int? applicationRttUs;
  final int? matchingPongDuplicates;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.ping;
}

final class RespondSummary extends LogicalSummary {
  const RespondSummary({
    super.reason,
    super.stage,
    super.failure,
    this.lastSend,
    this.reception,
    this.processedEntries,
    this.listenStopReason,
    this.responseAttempts,
    this.localResponsesConfirmed,
    this.duplicates,
    this.conflicts,
    this.cacheCapacityRejections,
    this.returnCapacityRejections,
  });
  final SendFacts? lastSend;
  final ReceptionSummary? reception;
  final int? processedEntries;
  final ListenStopReason? listenStopReason;
  final int? responseAttempts;
  final int? localResponsesConfirmed;
  final int? duplicates;
  final int? conflicts;
  final int? cacheCapacityRejections;
  final int? returnCapacityRejections;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.respond;
}

final class CleanupScopeSummary {
  CleanupScopeSummary({
    this.state = CleanupState.unconfirmed,
    Iterable<FailureSummary> failures = const [],
  }) : failures = List.unmodifiable(failures);
  final CleanupState state;
  final List<FailureSummary> failures;
  int get failureCount => failures.length;
}

/// Independent facts supplied by the recording coordinator. This value performs no
/// cleanup aggregation, ownership inference, or lifecycle transitions.
final class CleanupSummary {
  CleanupSummary({
    CleanupScopeSummary? core,
    CleanupScopeSummary? hostSubscriptions,
    this.aggregate = CleanupState.unconfirmed,
  }) : core = core ?? CleanupScopeSummary(),
       hostSubscriptions = hostSubscriptions ?? CleanupScopeSummary();
  final CleanupScopeSummary core;
  final CleanupScopeSummary hostSubscriptions;
  final CleanupState aggregate;
}

/// Read-only lifecycle snapshot. Only the recording coordinator writes
/// facts; constructing this object does not admit or start a device operation.
final class DiagnosticRun {
  DiagnosticRun({
    required this.runId,
    required this.appVersion,
    required this.configuration,
    required DateTime preparedAt,
    this.profileId,
    DateTime? logicalEndedAt,
    this.recordState = DiagnosticRecordState.prepared,
    this.result,
    CleanupSummary? cleanup,
    DateTime? recoveredAt,
    this.recoveryReason,
    this.diagnosticSummaryFormatVersion = 1,
  }) : preparedAt = requireUtc(preparedAt),
       logicalEndedAt = logicalEndedAt == null
           ? null
           : requireUtc(logicalEndedAt),
       cleanup = cleanup ?? CleanupSummary(),
       recoveredAt = recoveredAt == null ? null : requireUtc(recoveredAt) {
    requireValid(diagnosticSummaryFormatVersion >= 1);
    requireValid(result == null || result!.operation == operation);
  }
  final LocalId runId;
  final String appVersion;
  final LocalId? profileId;
  final DiagnosticConfiguration configuration;
  final DateTime preparedAt;
  final DateTime? logicalEndedAt;
  final DiagnosticRecordState recordState;
  final LogicalSummary? result;
  final CleanupSummary cleanup;
  final DateTime? recoveredAt;
  final RecoveryReason? recoveryReason;
  final int diagnosticSummaryFormatVersion;
  DiagnosticOperation get operation => configuration.operation;
}
