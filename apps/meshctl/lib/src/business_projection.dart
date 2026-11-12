import 'package:meshchan_core/meshchan_core.dart';

import 'business_input.dart';
import 'business_storage.dart';

Map<String, Object?> draftFields(Draft d, {bool body = true}) => {
  'id': d.id.value,
  'title': d.title,
  if (body) 'body': d.body,
  'bodyUtf8ByteLength': d.bodyUtf8ByteLength,
  'revision': d.revision,
  'createdAt': utcOutput(d.createdAt),
  'updatedAt': utcOutput(d.updatedAt),
};
Map<String, Object?> budgetFields(ProfileBudgets b) => {
  'requestTimeoutSeconds': b.requestTimeoutSeconds,
  'initializationTimeoutSeconds': b.initializationTimeoutSeconds,
  'startupDelayMilliseconds': b.startupDelayMilliseconds,
  'taskTimeoutSeconds': b.taskTimeoutSeconds,
};
Map<String, Object?> profileFields(ConnectionProfile p, {bool full = true}) => {
  'id': p.id.value,
  'name': p.name,
  'operation': p.operation.code,
  'updatedAt': utcOutput(p.updatedAt),
  if (full) ...{
    'portHint': p.portHint,
    'parameters': profileParameterFields(p.parameters),
  },
};
Map<String, Object?> profileParameterFields(ProfileParameters p) {
  Map<String, Object?> route(ProfileRoute r) => {
    'routeDescriptor': r.routeDescriptor,
    'pathHex': r.path.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  };
  Map<String, Object?> endpoints(ProfileTestEndpoints e) => {
    'localTestId': e.localTestId,
    'peerTestId': e.peerTestId,
  };
  return {
    'budgets': budgetFields(p.budgets),
    ...switch (p) {
      SendProfileParameters() => {
        'sendChannelIndex': p.sendChannelIndex,
        'dataType': p.dataType,
        'route': route(p.route),
      },
      ListenProfileParameters() => {
        'receiveChannelIndex': p.receiveChannelIndex,
        'dataType': p.dataType,
        'listenDurationSeconds': p.listenDurationSeconds,
        'maxEntries': p.maxEntries,
      },
      PingProfileParameters() => {
        'sendChannelIndex': p.sendChannelIndex,
        'receiveChannelIndex': p.receiveChannelIndex,
        'route': route(p.route),
        'endpoints': endpoints(p.endpoints),
        'responseTimeoutSeconds': p.responseTimeoutSeconds,
        'maxEntries': p.maxEntries,
      },
      RespondProfileParameters() => {
        'sendChannelIndex': p.sendChannelIndex,
        'receiveChannelIndex': p.receiveChannelIndex,
        'route': route(p.route),
        'endpoints': endpoints(p.endpoints),
        'listenDurationSeconds': p.listenDurationSeconds,
        'maxEntries': p.maxEntries,
        'maxResponses': p.maxResponses,
      },
    },
  };
}

Map<String, Object?> settingsFields(AppSettings s) => {
  'defaultProfileId': s.defaultProfileId?.value,
  'diagnosticHistoryLimit': s.diagnosticHistoryLimit,
};

Map<String, Object?>? failureSummaryFields(FailureSummary? f) => f == null
    ? null
    : {
        'domain': f.domain.code,
        'kind': f.kind?.code,
        'stage': f.stage?.code,
        'hostCleanupStage': f.hostCleanupStage?.code,
        'session': sessionSummaryFields(f.session),
      };
Map<String, Object?>? sessionSummaryFields(SessionFailureSummary? f) =>
    f == null
    ? null
    : {
        'kind': f.kind.code,
        'stage': f.stage.code,
        'commandOpcode': f.commandOpcode,
        'expectedResponseOpcode': f.expectedResponseOpcode,
        'deviceErrorCode': f.deviceErrorCode,
        'deviceErrorName': f.deviceErrorName?.code,
      };
Map<String, Object?>? sendFactsFields(SendFacts? s) => s == null
    ? null
    : {
        'attempted': s.attempted,
        'pendingAtTermination': s.pendingAtTermination,
        'dispatched': s.dispatched,
        'localWriteCompleted': s.localWriteCompleted,
        'localOkObserved': s.localOkObserved,
        'deviceAcceptanceConfirmed': s.deviceAcceptanceConfirmed,
        'commandFailure': s.commandFailure == null
            ? null
            : {
                'commandOpcode': s.commandFailure!.commandOpcode,
                'dispatched': s.commandFailure!.dispatched,
                'localWriteCompleted': s.commandFailure!.localWriteCompleted,
                'matchingResponseObserved':
                    s.commandFailure!.matchingResponseObserved,
                'sessionFailure': sessionSummaryFields(
                  s.commandFailure!.sessionFailure,
                ),
              },
      };
Map<String, Object?>? receptionFields(ReceptionSummary? r) => r == null
    ? null
    : {
        'reason': r.reason.code,
        'publishedEntries': r.publishedEntries,
        'dispatchedReads': r.dispatchedReads,
        'completedReads': r.completedReads,
      };
Map<String, Object?>? logicalFields(LogicalSummary? r) => r == null
    ? null
    : {
        'reason': r.reason?.code,
        'stage': r.stage?.code,
        'failure': failureSummaryFields(r.failure),
        ...switch (r) {
          SendSummary() => {'send': sendFactsFields(r.send)},
          ListenSummary() => {
            'reception': receptionFields(r.reception),
            'receptionReason': r.receptionReason?.code,
            'publishedEntries': r.publishedEntries,
            'processedEntries': r.processedEntries,
            'matchingDatagrams': r.matchingDatagrams,
            'filteredDatagrams': r.filteredDatagrams,
            'ordinaryMessages': r.ordinaryMessages,
          },
          PingSummary() => {
            'send': sendFactsFields(r.send),
            'reception': receptionFields(r.reception),
            'processedEntries': r.processedEntries,
            'matchingPongObserved': r.matchingPongObserved,
            'exactContentValidated': r.exactContentValidated,
            'roundTripSucceeded': r.roundTripSucceeded,
            'firstMatchingPongElapsedUs': r.firstMatchingPongElapsedUs,
            'applicationRttUs': r.applicationRttUs,
            'matchingPongDuplicates': r.matchingPongDuplicates,
          },
          RespondSummary() => {
            'lastSend': sendFactsFields(r.lastSend),
            'reception': receptionFields(r.reception),
            'processedEntries': r.processedEntries,
            'listenStopReason': r.listenStopReason?.code,
            'responseAttempts': r.responseAttempts,
            'localResponsesConfirmed': r.localResponsesConfirmed,
            'duplicates': r.duplicates,
            'conflicts': r.conflicts,
            'cacheCapacityRejections': r.cacheCapacityRejections,
            'returnCapacityRejections': r.returnCapacityRejections,
          },
        },
      };
Map<String, Object?> scopeFields(CleanupScopeSummary s) => {
  'state': s.state.code,
  'failureCount': s.failureCount,
  'failures': s.failures.map(failureSummaryFields).toList(),
};
Map<String, Object?> cleanupFields(CleanupSummary c) => {
  'aggregate': c.aggregate.code,
  'core': scopeFields(c.core),
  'hostSubscriptions': scopeFields(c.hostSubscriptions),
};
Map<String, Object?> saveFields(RecordingSave s) => {
  'phase': s.phase.name,
  'state': s.state.name,
  'error': s.error == null
      ? null
      : coreErrorFields(s.error!, 'recording_${s.phase.name}'),
  'finalCleanup': s.finalCleanup,
};

Map<String, Object?> configurationFields(DiagnosticConfiguration c) {
  Map<String, Object?> route(DiagnosticRoute r) => {
    'routeDescriptor': r.routeDescriptor,
    'pathByteCount': r.pathByteCount,
  };
  return {
    'budgets': budgetFields(c.budgets),
    'appTargetVersion': c.appTargetVersion,
    'maxQueuedCommands': c.maxQueuedCommands,
    ...switch (c) {
      SendConfiguration() => {
        'sendChannelIndex': c.sendChannelIndex,
        'dataType': c.dataType,
        'route': route(c.route),
        'payloadByteLength': c.payloadByteLength,
      },
      ListenConfiguration() => {
        'receiveChannelIndex': c.receiveChannelIndex,
        'dataType': c.dataType,
        'listenDurationSeconds': c.listenDurationSeconds,
        'maxEntries': c.maxEntries,
        'maxReadsPerBatch': c.maxReadsPerBatch,
      },
      PingConfiguration() => {
        'sendChannelIndex': c.sendChannelIndex,
        'receiveChannelIndex': c.receiveChannelIndex,
        'route': route(c.route),
        'maxEntries': c.maxEntries,
        'responseTimeoutSeconds': c.responseTimeoutSeconds,
        'contentByteLength': c.contentByteLength,
        'diagnosticWireVersion': c.diagnosticWireVersion,
        'diagnosticDataType': c.diagnosticDataType,
        'maxReadsPerBatch': c.maxReadsPerBatch,
      },
      RespondConfiguration() => {
        'sendChannelIndex': c.sendChannelIndex,
        'receiveChannelIndex': c.receiveChannelIndex,
        'route': route(c.route),
        'maxEntries': c.maxEntries,
        'listenDurationSeconds': c.listenDurationSeconds,
        'maxResponses': c.maxResponses,
        'diagnosticWireVersion': c.diagnosticWireVersion,
        'diagnosticDataType': c.diagnosticDataType,
        'maxReadsPerBatch': c.maxReadsPerBatch,
        'cacheCapacity': c.cacheCapacity,
        'cacheTtlUs': c.cacheTtlUs,
      },
    },
  };
}

Map<String, Object?> historyFields(DiagnosticRun r, {bool full = true}) => {
  'runId': r.runId.value,
  'operation': r.operation.code,
  'appVersion': r.appVersion,
  'diagnosticSummaryFormatVersion': r.diagnosticSummaryFormatVersion,
  'preparedAt': utcOutput(r.preparedAt),
  'logicalEndedAt': r.logicalEndedAt == null
      ? null
      : utcOutput(r.logicalEndedAt!),
  'recordState': r.recordState.code,
  'result': logicalFields(r.result),
  'cleanup': cleanupFields(r.cleanup),
  'recoveredAt': r.recoveredAt == null ? null : utcOutput(r.recoveredAt!),
  'recoveryReason': r.recoveryReason?.code,
  if (full) 'configuration': configurationFields(r.configuration),
};
