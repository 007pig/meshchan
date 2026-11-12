import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart' as link;

import '../errors.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_configuration.dart';
import '../models/diagnostic_run.dart';
import '../validation.dart';

bool terminalCleanup(CleanupState state) =>
    state == CleanupState.succeeded ||
    state == CleanupState.failed ||
    state == CleanupState.notRequired;

CleanupState aggregateCleanup(
  CleanupScopeSummary core,
  CleanupScopeSummary host,
) {
  final states = [core.state, host.state];
  if (states.contains(CleanupState.unconfirmedAfterExit)) {
    return CleanupState.unconfirmedAfterExit;
  }
  if (!states.every(terminalCleanup)) {
    return states.every(
          (s) => s == CleanupState.unconfirmed || s == CleanupState.notRequired,
        )
        ? CleanupState.unconfirmed
        : CleanupState.pending;
  }
  if (states.contains(CleanupState.failed)) return CleanupState.failed;
  if (states.every((s) => s == CleanupState.notRequired)) {
    return CleanupState.notRequired;
  }
  return CleanupState.succeeded;
}

CleanupSummary combineCleanup(
  CleanupScopeSummary core,
  CleanupScopeSummary host,
) => CleanupSummary(
  core: core,
  hostSubscriptions: host,
  aggregate: aggregateCleanup(core, host),
);

void _range(int value, int min, int max) =>
    requireValid(value >= min && value <= max);
void _count(int? n) {
  if (n != null) requireValid(n >= 0);
}

void _seconds(int n) => _range(n, 1, 86400);

// A route summary exposes only a descriptor and length. Link's pure helper
// checks those two facts using a length witness; no path is reconstructed.
int _capacity(DiagnosticRoute route, bool diagnostic) {
  _range(route.pathByteCount, 0, 255);
  try {
    return diagnostic
        ? link.maxDiagnosticContentLengthForRoute(
            routeDescriptor: route.routeDescriptor,
            path: Uint8List(route.pathByteCount),
          )
        : link.maxChannelDataPayloadLengthForRoute(
            routeDescriptor: route.routeDescriptor,
            path: Uint8List(route.pathByteCount),
          );
  } on ArgumentError {
    throw const CoreException(CoreErrorCode.invalidInput);
  }
}

void validateConfiguration(DiagnosticConfiguration c) {
  final b = c.budgets;
  _seconds(b.requestTimeoutSeconds);
  _seconds(b.initializationTimeoutSeconds);
  _seconds(b.taskTimeoutSeconds);
  _range(b.startupDelayMilliseconds, 0, 86399999);
  requireValid(
    b.startupDelayMilliseconds < b.initializationTimeoutSeconds * 1000,
  );
  switch (c) {
    case SendConfiguration():
      _range(c.sendChannelIndex, 0, 255);
      _range(c.dataType, 1, 65535);
      _range(c.payloadByteLength, 0, _capacity(c.route, false));
    case ListenConfiguration():
      _range(c.receiveChannelIndex, 0, 255);
      if (c.dataType != null) _range(c.dataType!, 0, 65535);
      _seconds(c.listenDurationSeconds);
      _range(c.maxEntries, 1, 4096);
    case TaskConfiguration():
      _range(c.sendChannelIndex, 0, 255);
      _range(c.receiveChannelIndex, 0, 255);
      _range(c.maxEntries, 1, 4096);
      final capacity = _capacity(c.route, true);
      switch (c) {
        case PingConfiguration():
          _seconds(c.responseTimeoutSeconds);
          _range(c.contentByteLength, 0, capacity);
        case RespondConfiguration():
          _seconds(c.listenDurationSeconds);
          _range(c.maxResponses, 1, 4096);
      }
  }
}

void _session(SessionFailureSummary? s) {
  if (s == null) return;
  requireValid(
    const {
      FailureKind.transport,
      FailureKind.protocol,
      FailureKind.deviceRejected,
      FailureKind.requestTimeout,
      FailureKind.initializationTimeout,
      FailureKind.disconnected,
      FailureKind.canceled,
      FailureKind.cleanup,
    }.contains(s.kind),
  );
  for (final opcode in [
    s.commandOpcode,
    s.expectedResponseOpcode,
    s.deviceErrorCode,
  ]) {
    if (opcode != null) _range(opcode, 0, 255);
  }
}

void _failure(FailureSummary? f) {
  if (f != null) _session(f.session);
}

void _send(SendFacts? s) {
  if (s == null) return;
  requireValid(!s.pendingAtTermination || s.attempted);
  requireValid(
    !s.deviceAcceptanceConfirmed ||
        (s.attempted &&
            s.dispatched == true &&
            s.localWriteCompleted == true &&
            s.localOkObserved == true &&
            s.commandFailure == null),
  );
  requireValid(
    s.attempted ||
        (s.dispatched == null &&
            s.localWriteCompleted == null &&
            s.localOkObserved == null &&
            s.commandFailure == null &&
            !s.deviceAcceptanceConfirmed),
  );
  requireValid(s.localWriteCompleted != true || s.dispatched == true);
  requireValid(s.localOkObserved != true || s.dispatched == true);
  final f = s.commandFailure;
  if (f != null) {
    _range(f.commandOpcode, 0, 255);
    _session(f.sessionFailure);
    requireValid(
      s.attempted &&
          !s.deviceAcceptanceConfirmed &&
          s.dispatched == f.dispatched &&
          s.localWriteCompleted == f.localWriteCompleted &&
          s.localOkObserved == f.matchingResponseObserved,
    );
    requireValid(
      f.dispatched || (!f.localWriteCompleted && !f.matchingResponseObserved),
    );
  }
}

void _reception(ReceptionSummary? r, int? processed, int? max) {
  _count(processed);
  if (r == null) return;
  _count(r.publishedEntries);
  _count(r.dispatchedReads);
  _count(r.completedReads);
  requireValid(r.completedReads <= r.dispatchedReads);
  if (max != null) requireValid(r.publishedEntries <= max);
  if (processed != null) requireValid(processed <= r.publishedEntries);
}

void validateLogical(LogicalSummary s, DiagnosticConfiguration c) {
  requireValid(s.operation == c.operation);
  requireValid((s.reason == null) == (s.stage == null));
  _failure(s.failure);
  if (s.reason == LogicalReason.completed) requireValid(s.failure == null);
  switch (s) {
    case SendSummary():
      _send(s.send);
      if (s.reason == LogicalReason.completed) {
        requireValid(s.send?.deviceAcceptanceConfirmed == true);
      }
    case ListenSummary():
      _reception(
        s.reception,
        s.processedEntries,
        (c as ListenConfiguration).maxEntries,
      );
      for (final n in [
        s.publishedEntries,
        s.matchingDatagrams,
        s.filteredDatagrams,
        s.ordinaryMessages,
      ]) {
        _count(n);
      }
      if (s.reception != null) {
        requireValid(s.receptionReason == s.reception!.reason);
        requireValid(s.publishedEntries == s.reception!.publishedEntries);
      }
      if (s.processedEntries != null) {
        if (s.publishedEntries != null) {
          requireValid(s.processedEntries! <= s.publishedEntries!);
        }
        for (final n in [
          s.matchingDatagrams,
          s.filteredDatagrams,
          s.ordinaryMessages,
        ]) {
          if (n != null) requireValid(n <= s.processedEntries!);
        }
      }
      if (s.reason == LogicalReason.completed) {
        requireValid(
          s.reception != null &&
              s.publishedEntries != null &&
              s.processedEntries != null &&
              s.matchingDatagrams != null &&
              s.filteredDatagrams != null &&
              s.ordinaryMessages != null &&
              (s.receptionReason == ReceptionReason.durationElapsed ||
                  s.receptionReason == ReceptionReason.entryLimit),
        );
      }
    case PingSummary():
      _send(s.send);
      _reception(
        s.reception,
        s.processedEntries,
        (c as PingConfiguration).maxEntries,
      );
      for (final n in [
        s.firstMatchingPongElapsedUs,
        s.applicationRttUs,
        s.matchingPongDuplicates,
      ]) {
        _count(n);
      }
      if (s.matchingPongObserved == true) {
        requireValid(
          s.firstMatchingPongElapsedUs != null &&
              s.exactContentValidated == true,
        );
      }
      if (s.matchingPongObserved == false) {
        requireValid(s.firstMatchingPongElapsedUs == null);
      }
      if (s.exactContentValidated == true) {
        requireValid(s.matchingPongObserved == true);
      }
      if (s.roundTripSucceeded == true) {
        requireValid(
          s.reason == LogicalReason.completed &&
              s.matchingPongObserved == true &&
              s.send?.deviceAcceptanceConfirmed == true &&
              s.applicationRttUs == s.firstMatchingPongElapsedUs,
        );
      }
      if (s.roundTripSucceeded == false) {
        requireValid(s.applicationRttUs == null);
      }
      if (s.firstMatchingPongElapsedUs != null) {
        requireValid(s.matchingPongObserved == true);
      }
      if (s.applicationRttUs != null) {
        requireValid(s.roundTripSucceeded == true);
      }
      if (s.reason == LogicalReason.completed) {
        requireValid(s.roundTripSucceeded == true);
      }
    case RespondSummary():
      _send(s.lastSend);
      _reception(
        s.reception,
        s.processedEntries,
        (c as RespondConfiguration).maxEntries,
      );
      for (final n in [
        s.responseAttempts,
        s.localResponsesConfirmed,
        s.duplicates,
        s.conflicts,
        s.cacheCapacityRejections,
        s.returnCapacityRejections,
      ]) {
        _count(n);
      }
      if (s.responseAttempts != null) {
        requireValid(s.responseAttempts! <= c.maxResponses);
        if (s.localResponsesConfirmed != null) {
          requireValid(s.localResponsesConfirmed! <= s.responseAttempts!);
        }
        if (s.responseAttempts == 0) {
          requireValid(s.lastSend?.attempted != true);
        }
      }
      if (s.reason == LogicalReason.completed) {
        requireValid(
          s.listenStopReason != null &&
              s.responseAttempts != null &&
              s.localResponsesConfirmed != null &&
              s.duplicates != null &&
              s.conflicts != null &&
              s.cacheCapacityRejections != null &&
              s.returnCapacityRejections != null,
        );
      }
  }
}

void validateRun(DiagnosticRun run) {
  requireValid(run.appVersion.trim().isNotEmpty);
  validateUnicode(run.appVersion);
  validateConfiguration(run.configuration);
  final result = run.result;
  if (result != null) validateLogical(result, run.configuration);
  final finalResult = result?.reason != null && result?.stage != null;
  switch (run.recordState) {
    case DiagnosticRecordState.prepared:
      requireValid(
        run.logicalEndedAt == null &&
            !finalResult &&
            run.recoveredAt == null &&
            run.recoveryReason == null,
      );
    case DiagnosticRecordState.settled:
      requireValid(
        finalResult &&
            run.logicalEndedAt != null &&
            run.recoveredAt == null &&
            run.recoveryReason == null,
      );
    case DiagnosticRecordState.recoveredArchived:
      requireValid(run.recoveredAt != null && run.recoveryReason != null);
      if (run.recoveryReason == RecoveryReason.interrupted) {
        requireValid(!finalResult && run.logicalEndedAt == null);
      }
      if (run.recoveryReason == RecoveryReason.cleanupUnconfirmed) {
        requireValid(
          finalResult &&
              run.logicalEndedAt != null &&
              run.cleanup.aggregate == CleanupState.unconfirmedAfterExit,
        );
      }
  }
  for (final scope in [run.cleanup.core, run.cleanup.hostSubscriptions]) {
    if (run.recordState != DiagnosticRecordState.recoveredArchived) {
      requireValid(scope.state != CleanupState.unconfirmedAfterExit);
    }
    if (scope.state == CleanupState.succeeded ||
        scope.state == CleanupState.notRequired) {
      requireValid(scope.failures.isEmpty);
    }
    if (scope.state == CleanupState.failed) {
      requireValid(scope.failures.isNotEmpty);
    }
    for (final f in scope.failures) {
      _failure(f);
    }
  }
  requireValid(
    run.cleanup.aggregate ==
        aggregateCleanup(run.cleanup.core, run.cleanup.hostSubscriptions),
  );
}

DiagnosticRun validateStoredRun(DiagnosticRun run) {
  try {
    validateRun(run);
    return run;
  } on CoreException {
    throw const CoreException(CoreErrorCode.databaseCorrupt);
  }
}
