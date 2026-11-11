import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../errors.dart';
import '../models/app_settings.dart';
import '../models/connection_profile.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_configuration.dart';
import '../models/diagnostic_run.dart';
import '../models/draft.dart';
import '../values.dart';
import 'database.dart' as db;

// This is a private storage representation, not an export format or a mapper
// from communication results. Every nested object has an exact field allowlist.
T _stored<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    throw const CoreException(CoreErrorCode.databaseCorrupt);
  }
}

DateTime _utc(int value) =>
    DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
int _us(DateTime value) => value.microsecondsSinceEpoch;
T _code<T>(String value, Iterable<T> values, String Function(T) code) =>
    values.singleWhere((v) => code(v) == value);
DiagnosticOperation _operation(String code) =>
    _code(code, DiagnosticOperation.values, (v) => v.code);

final class _Object {
  _Object(Object? input, String fields) {
    if (input is! Map<String, dynamic>) throw const FormatException();
    final expected = fields.split(' ').toSet();
    if (input.length != expected.length ||
        !input.keys.every(expected.contains)) {
      throw const FormatException();
    }
    data = input;
  }
  late final Map<String, dynamic> data;
  int i(String key) => data[key] as int;
  int? ni(String key) => data[key] as int?;
  String s(String key) => data[key] as String;
  String? ns(String key) => data[key] as String?;
  bool b(String key) => data[key] as bool;
  bool? nb(String key) => data[key] as bool?;
  Object? operator [](String key) => data[key];
}

Map<String, Object?> _budgets(ProfileBudgets v) => {
  'requestTimeoutSeconds': v.requestTimeoutSeconds,
  'initializationTimeoutSeconds': v.initializationTimeoutSeconds,
  'startupDelayMilliseconds': v.startupDelayMilliseconds,
  'taskTimeoutSeconds': v.taskTimeoutSeconds,
};
ProfileBudgets _readBudgets(Object? value) {
  final o = _Object(
    value,
    'requestTimeoutSeconds initializationTimeoutSeconds startupDelayMilliseconds taskTimeoutSeconds',
  );
  return ProfileBudgets(
    requestTimeoutSeconds: o.i('requestTimeoutSeconds'),
    initializationTimeoutSeconds: o.i('initializationTimeoutSeconds'),
    startupDelayMilliseconds: o.i('startupDelayMilliseconds'),
    taskTimeoutSeconds: o.i('taskTimeoutSeconds'),
  );
}

Map<String, Object?> _profileRoute(ProfileRoute v) => {
  'routeDescriptor': v.routeDescriptor,
  'path': v.path,
};
ProfileRoute _readProfileRoute(Object? value) {
  final o = _Object(value, 'routeDescriptor path');
  return ProfileRoute(
    routeDescriptor: o.i('routeDescriptor'),
    path: (o['path'] as List).cast<int>(),
  );
}

Map<String, Object?> _endpoints(ProfileTestEndpoints v) => {
  'localTestId': v.localTestId,
  'peerTestId': v.peerTestId,
};
ProfileTestEndpoints _readEndpoints(Object? value) {
  final o = _Object(value, 'localTestId peerTestId');
  return ProfileTestEndpoints(
    localTestId: o.i('localTestId'),
    peerTestId: o.i('peerTestId'),
  );
}

Map<String, Object?> _route(DiagnosticRoute v) => {
  'routeDescriptor': v.routeDescriptor,
  'pathByteCount': v.pathByteCount,
};
DiagnosticRoute _readRoute(Object? value) {
  final o = _Object(value, 'routeDescriptor pathByteCount');
  return DiagnosticRoute(
    routeDescriptor: o.i('routeDescriptor'),
    pathByteCount: o.i('pathByteCount'),
  );
}

Map<String, Object?> _parameters(ProfileParameters v) => {
  'operation': v.operation.code,
  'budgets': _budgets(v.budgets),
  ...switch (v) {
    SendProfileParameters() => {
      'sendChannelIndex': v.sendChannelIndex,
      'route': _profileRoute(v.route),
      'dataType': v.dataType,
    },
    ListenProfileParameters() => {
      'receiveChannelIndex': v.receiveChannelIndex,
      'dataType': v.dataType,
      'listenDurationSeconds': v.listenDurationSeconds,
      'maxEntries': v.maxEntries,
    },
    PingProfileParameters() => {
      'sendChannelIndex': v.sendChannelIndex,
      'receiveChannelIndex': v.receiveChannelIndex,
      'route': _profileRoute(v.route),
      'endpoints': _endpoints(v.endpoints),
      'responseTimeoutSeconds': v.responseTimeoutSeconds,
      'maxEntries': v.maxEntries,
    },
    RespondProfileParameters() => {
      'sendChannelIndex': v.sendChannelIndex,
      'receiveChannelIndex': v.receiveChannelIndex,
      'route': _profileRoute(v.route),
      'endpoints': _endpoints(v.endpoints),
      'listenDurationSeconds': v.listenDurationSeconds,
      'maxEntries': v.maxEntries,
      'maxResponses': v.maxResponses,
    },
  },
};
ProfileParameters _readParameters(
  Object? value,
  DiagnosticOperation operation,
) {
  final fields = switch (operation) {
    DiagnosticOperation.send => 'sendChannelIndex route dataType',
    DiagnosticOperation.listen =>
      'receiveChannelIndex dataType listenDurationSeconds maxEntries',
    DiagnosticOperation.ping => 'sendChannelIndex receiveChannelIndex route endpoints responseTimeoutSeconds maxEntries',
    DiagnosticOperation.respond => 'sendChannelIndex receiveChannelIndex route endpoints listenDurationSeconds maxEntries maxResponses',
  };
  final o = _Object(value, 'operation budgets $fields');
  if (_operation(o.s('operation')) != operation) throw const FormatException();
  final budgets = _readBudgets(o['budgets']);
  return switch (operation) {
    DiagnosticOperation.send => SendProfileParameters(
      budgets: budgets,
      sendChannelIndex: o.i('sendChannelIndex'),
      route: _readProfileRoute(o['route']),
      dataType: o.i('dataType'),
    ),
    DiagnosticOperation.listen => ListenProfileParameters(
      budgets: budgets,
      receiveChannelIndex: o.i('receiveChannelIndex'),
      dataType: o.ni('dataType'),
      listenDurationSeconds: o.i('listenDurationSeconds'),
      maxEntries: o.i('maxEntries'),
    ),
    DiagnosticOperation.ping => PingProfileParameters(
      budgets: budgets,
      sendChannelIndex: o.i('sendChannelIndex'),
      receiveChannelIndex: o.i('receiveChannelIndex'),
      route: _readProfileRoute(o['route']),
      endpoints: _readEndpoints(o['endpoints']),
      responseTimeoutSeconds: o.i('responseTimeoutSeconds'),
      maxEntries: o.i('maxEntries'),
    ),
    DiagnosticOperation.respond => RespondProfileParameters(
      budgets: budgets,
      sendChannelIndex: o.i('sendChannelIndex'),
      receiveChannelIndex: o.i('receiveChannelIndex'),
      route: _readProfileRoute(o['route']),
      endpoints: _readEndpoints(o['endpoints']),
      listenDurationSeconds: o.i('listenDurationSeconds'),
      maxEntries: o.i('maxEntries'),
      maxResponses: o.i('maxResponses'),
    ),
  };
}

Map<String, Object?> _configuration(DiagnosticConfiguration v) => {
  'operation': v.operation.code,
  'budgets': _budgets(v.budgets),
  'appTargetVersion': v.appTargetVersion,
  'maxQueuedCommands': v.maxQueuedCommands,
  ...switch (v) {
    SendConfiguration() => {
      'sendChannelIndex': v.sendChannelIndex,
      'dataType': v.dataType,
      'route': _route(v.route),
      'payloadByteLength': v.payloadByteLength,
    },
    ListenConfiguration() => {
      'receiveChannelIndex': v.receiveChannelIndex,
      'dataType': v.dataType,
      'listenDurationSeconds': v.listenDurationSeconds,
      'maxEntries': v.maxEntries,
      'maxReadsPerBatch': v.maxReadsPerBatch,
    },
    PingConfiguration() => {
      'sendChannelIndex': v.sendChannelIndex,
      'receiveChannelIndex': v.receiveChannelIndex,
      'route': _route(v.route),
      'maxEntries': v.maxEntries,
      'maxReadsPerBatch': v.maxReadsPerBatch,
      'diagnosticWireVersion': v.diagnosticWireVersion,
      'diagnosticDataType': v.diagnosticDataType,
      'responseTimeoutSeconds': v.responseTimeoutSeconds,
      'contentByteLength': v.contentByteLength,
    },
    RespondConfiguration() => {
      'sendChannelIndex': v.sendChannelIndex,
      'receiveChannelIndex': v.receiveChannelIndex,
      'route': _route(v.route),
      'maxEntries': v.maxEntries,
      'maxReadsPerBatch': v.maxReadsPerBatch,
      'diagnosticWireVersion': v.diagnosticWireVersion,
      'diagnosticDataType': v.diagnosticDataType,
      'listenDurationSeconds': v.listenDurationSeconds,
      'maxResponses': v.maxResponses,
      'cacheCapacity': v.cacheCapacity,
      'cacheTtlUs': v.cacheTtlUs,
    },
  },
};
DiagnosticConfiguration _readConfiguration(
  Object? value,
  DiagnosticOperation operation,
) {
  const taskFields =
      'sendChannelIndex receiveChannelIndex route maxEntries maxReadsPerBatch diagnosticWireVersion diagnosticDataType';
  final fields = switch (operation) {
    DiagnosticOperation.send =>
      'sendChannelIndex dataType route payloadByteLength',
    DiagnosticOperation.listen => 'receiveChannelIndex dataType listenDurationSeconds maxEntries maxReadsPerBatch',
    DiagnosticOperation.ping =>
      '$taskFields responseTimeoutSeconds contentByteLength',
    DiagnosticOperation.respond =>
      '$taskFields listenDurationSeconds maxResponses cacheCapacity cacheTtlUs',
  };
  final o = _Object(
    value,
    'operation budgets appTargetVersion maxQueuedCommands $fields',
  );
  if (_operation(o.s('operation')) != operation ||
      o.i('appTargetVersion') != 3 ||
      o.i('maxQueuedCommands') != 8) {
    throw const FormatException();
  }
  if (operation != DiagnosticOperation.send && o.i('maxReadsPerBatch') != 8) {
    throw const FormatException();
  }
  if (operation == DiagnosticOperation.ping ||
      operation == DiagnosticOperation.respond) {
    if (o.i('diagnosticWireVersion') != 1 ||
        o.i('diagnosticDataType') != 65535) {
      throw const FormatException();
    }
  }
  if (operation == DiagnosticOperation.respond &&
      (o.i('cacheCapacity') != 128 || o.i('cacheTtlUs') != 120000000)) {
    throw const FormatException();
  }
  final budgets = _readBudgets(o['budgets']);
  return switch (operation) {
    DiagnosticOperation.send => SendConfiguration(
      budgets: budgets,
      sendChannelIndex: o.i('sendChannelIndex'),
      dataType: o.i('dataType'),
      route: _readRoute(o['route']),
      payloadByteLength: o.i('payloadByteLength'),
    ),
    DiagnosticOperation.listen => ListenConfiguration(
      budgets: budgets,
      receiveChannelIndex: o.i('receiveChannelIndex'),
      dataType: o.ni('dataType'),
      listenDurationSeconds: o.i('listenDurationSeconds'),
      maxEntries: o.i('maxEntries'),
    ),
    DiagnosticOperation.ping => PingConfiguration(
      budgets: budgets,
      sendChannelIndex: o.i('sendChannelIndex'),
      receiveChannelIndex: o.i('receiveChannelIndex'),
      route: _readRoute(o['route']),
      maxEntries: o.i('maxEntries'),
      responseTimeoutSeconds: o.i('responseTimeoutSeconds'),
      contentByteLength: o.i('contentByteLength'),
    ),
    DiagnosticOperation.respond => RespondConfiguration(
      budgets: budgets,
      sendChannelIndex: o.i('sendChannelIndex'),
      receiveChannelIndex: o.i('receiveChannelIndex'),
      route: _readRoute(o['route']),
      maxEntries: o.i('maxEntries'),
      listenDurationSeconds: o.i('listenDurationSeconds'),
      maxResponses: o.i('maxResponses'),
    ),
  };
}

// Row conversions stay internal. They perform no repository operations.
db.StoredDraftsCompanion encodeDraft(Draft v) =>
    db.StoredDraftsCompanion.insert(
      id: v.id.value,
      title: v.title,
      body: v.body,
      createdAtUs: _us(v.createdAt),
      updatedAtUs: _us(v.updatedAt),
      revision: v.revision,
    );
Draft decodeDraft(db.StoredDraft v) => _stored(
  () => Draft(
    id: LocalId(v.id),
    content: DraftContent(title: v.title, body: v.body),
    createdAt: _utc(v.createdAtUs),
    updatedAt: _utc(v.updatedAtUs),
    revision: v.revision,
  ),
);
db.StoredProfilesCompanion encodeProfile(ConnectionProfile v) =>
    db.StoredProfilesCompanion.insert(
      id: v.id.value,
      name: v.name,
      portHint: Value(v.portHint),
      operation: v.operation.code,
      parametersJson: jsonEncode(_parameters(v.parameters)),
      updatedAtUs: _us(v.updatedAt),
    );
ConnectionProfile decodeProfile(db.StoredProfile v) => _stored(
  () => ConnectionProfile(
    id: LocalId(v.id),
    content: ProfileContent(
      name: v.name,
      portHint: v.portHint,
      parameters: _readParameters(
        jsonDecode(v.parametersJson),
        _operation(v.operation),
      ),
    ),
    updatedAt: _utc(v.updatedAtUs),
  ),
);
db.StoredSettingsCompanion encodeSettings(AppSettings v) =>
    db.StoredSettingsCompanion.insert(
      singleton: const Value(1),
      defaultProfileId: Value(v.defaultProfileId?.value),
      diagnosticHistoryLimit: v.diagnosticHistoryLimit,
    );
AppSettings decodeSettings(db.StoredSetting v) => _stored(() {
  if (v.singleton != 1) throw const FormatException();
  return AppSettings(
    defaultProfileId: v.defaultProfileId == null
        ? null
        : LocalId(v.defaultProfileId!),
    diagnosticHistoryLimit: v.diagnosticHistoryLimit,
  );
});
db.StoredRunsCompanion encodeRun(DiagnosticRun v) {
  if (v.diagnosticSummaryFormatVersion != diagnosticSummaryFormatVersion) {
    throw const CoreException(CoreErrorCode.invalidInput);
  }
  return db.StoredRunsCompanion.insert(
    runId: v.runId.value,
    operation: v.operation.code,
    appVersion: v.appVersion,
    profileId: Value(v.profileId?.value),
    configurationJson: jsonEncode(_configuration(v.configuration)),
    preparedAtUs: _us(v.preparedAt),
    logicalEndedAtUs: Value(
      v.logicalEndedAt == null ? null : _us(v.logicalEndedAt!),
    ),
    recordState: v.recordState.code,
    resultJson: Value(
      v.result == null ? null : jsonEncode(_logical(v.result!)),
    ),
    cleanupJson: jsonEncode(_cleanup(v.cleanup)),
    recoveredAtUs: Value(v.recoveredAt == null ? null : _us(v.recoveredAt!)),
    recoveryReason: Value(v.recoveryReason?.code),
    summaryFormatVersion: v.diagnosticSummaryFormatVersion,
  );
}

DiagnosticRun decodeRun(db.StoredRun v) {
  // A supported database can contain a newer summary vocabulary. Refuse this
  // row as unreadable, without pretending its database structure is newer.
  if (v.summaryFormatVersion > diagnosticSummaryFormatVersion) {
    throw const CoreException(CoreErrorCode.storageReadFailed);
  }
  return _stored(() {
    if (v.summaryFormatVersion != 1) throw const FormatException();
    final operation = _operation(v.operation);
    return DiagnosticRun(
      runId: LocalId(v.runId),
      appVersion: v.appVersion,
      profileId: v.profileId == null ? null : LocalId(v.profileId!),
      configuration: _readConfiguration(
        jsonDecode(v.configurationJson),
        operation,
      ),
      preparedAt: _utc(v.preparedAtUs),
      logicalEndedAt: v.logicalEndedAtUs == null
          ? null
          : _utc(v.logicalEndedAtUs!),
      recordState: _code<DiagnosticRecordState>(
        v.recordState,
        DiagnosticRecordState.values,
        (v) => v.code,
      ),
      result: v.resultJson == null
          ? null
          : _readLogical(jsonDecode(v.resultJson!), operation),
      cleanup: _readCleanup(jsonDecode(v.cleanupJson)),
      recoveredAt: v.recoveredAtUs == null ? null : _utc(v.recoveredAtUs!),
      recoveryReason: v.recoveryReason == null
          ? null
          : _code<RecoveryReason>(
              v.recoveryReason!,
              RecoveryReason.values,
              (v) => v.code,
            ),
      diagnosticSummaryFormatVersion: v.summaryFormatVersion,
    );
  });
}

Map<String, Object?> _session(SessionFailureSummary v) => {
  'kind': v.kind.code,
  'stage': v.stage.code,
  'commandOpcode': v.commandOpcode,
  'expectedResponseOpcode': v.expectedResponseOpcode,
  'deviceErrorCode': v.deviceErrorCode,
  'deviceErrorName': v.deviceErrorName?.code,
};
SessionFailureSummary _readSession(Object? value) {
  final o = _Object(
    value,
    'kind stage commandOpcode expectedResponseOpcode deviceErrorCode deviceErrorName',
  );
  return SessionFailureSummary(
    kind: _code<FailureKind>(o.s('kind'), FailureKind.values, (v) => v.code),
    stage: _code<SessionStage>(
      o.s('stage'),
      SessionStage.values,
      (v) => v.code,
    ),
    commandOpcode: o.ni('commandOpcode'),
    expectedResponseOpcode: o.ni('expectedResponseOpcode'),
    deviceErrorCode: o.ni('deviceErrorCode'),
    deviceErrorName: o['deviceErrorName'] == null
        ? null
        : _code<DeviceErrorName>(
            o.s('deviceErrorName'),
            DeviceErrorName.values,
            (v) => v.code,
          ),
  );
}

Map<String, Object?> _failure(FailureSummary v) => {
  'domain': v.domain.code,
  'kind': v.kind?.code,
  'stage': v.stage?.code,
  'hostCleanupStage': v.hostCleanupStage?.code,
  'session': v.session == null ? null : _session(v.session!),
};
FailureSummary _readFailure(Object? value) {
  final o = _Object(value, 'domain kind stage hostCleanupStage session');
  return FailureSummary(
    domain: _code<FailureDomain>(
      o.s('domain'),
      FailureDomain.values,
      (v) => v.code,
    ),
    kind: o['kind'] == null
        ? null
        : _code<FailureKind>(o.s('kind'), FailureKind.values, (v) => v.code),
    stage: o['stage'] == null
        ? null
        : _code<DiagnosticStage>(
            o.s('stage'),
            DiagnosticStage.values,
            (v) => v.code,
          ),
    hostCleanupStage: o['hostCleanupStage'] == null
        ? null
        : _code<HostCleanupStage>(
            o.s('hostCleanupStage'),
            HostCleanupStage.values,
            (v) => v.code,
          ),
    session: o['session'] == null ? null : _readSession(o['session']),
  );
}

Map<String, Object?> _commandFailure(CommandFailureFacts v) => {
  'commandOpcode': v.commandOpcode,
  'dispatched': v.dispatched,
  'localWriteCompleted': v.localWriteCompleted,
  'matchingResponseObserved': v.matchingResponseObserved,
  'sessionFailure': _session(v.sessionFailure),
};
CommandFailureFacts _readCommandFailure(Object? value) {
  final o = _Object(
    value,
    'commandOpcode dispatched localWriteCompleted matchingResponseObserved sessionFailure',
  );
  return CommandFailureFacts(
    commandOpcode: o.i('commandOpcode'),
    dispatched: o.b('dispatched'),
    localWriteCompleted: o.b('localWriteCompleted'),
    matchingResponseObserved: o.b('matchingResponseObserved'),
    sessionFailure: _readSession(o['sessionFailure']),
  );
}

Map<String, Object?> _send(SendFacts v) => {
  'attempted': v.attempted,
  'pendingAtTermination': v.pendingAtTermination,
  'deviceAcceptanceConfirmed': v.deviceAcceptanceConfirmed,
  'dispatched': v.dispatched,
  'localWriteCompleted': v.localWriteCompleted,
  'localOkObserved': v.localOkObserved,
  'commandFailure': v.commandFailure == null
      ? null
      : _commandFailure(v.commandFailure!),
};
SendFacts _readSend(Object? value) {
  final o = _Object(
    value,
    'attempted pendingAtTermination deviceAcceptanceConfirmed dispatched localWriteCompleted localOkObserved commandFailure',
  );
  return SendFacts(
    attempted: o.b('attempted'),
    pendingAtTermination: o.b('pendingAtTermination'),
    deviceAcceptanceConfirmed: o.b('deviceAcceptanceConfirmed'),
    dispatched: o.nb('dispatched'),
    localWriteCompleted: o.nb('localWriteCompleted'),
    localOkObserved: o.nb('localOkObserved'),
    commandFailure: o['commandFailure'] == null
        ? null
        : _readCommandFailure(o['commandFailure']),
  );
}

Map<String, Object?> _reception(ReceptionSummary v) => {
  'reason': v.reason.code,
  'publishedEntries': v.publishedEntries,
  'dispatchedReads': v.dispatchedReads,
  'completedReads': v.completedReads,
};
ReceptionSummary _readReception(Object? value) {
  final o = _Object(
    value,
    'reason publishedEntries dispatchedReads completedReads',
  );
  return ReceptionSummary(
    reason: _code<ReceptionReason>(
      o.s('reason'),
      ReceptionReason.values,
      (v) => v.code,
    ),
    publishedEntries: o.i('publishedEntries'),
    dispatchedReads: o.i('dispatchedReads'),
    completedReads: o.i('completedReads'),
  );
}

Map<String, Object?> _scope(CleanupScopeSummary v) => {
  'state': v.state.code,
  'failures': v.failures.map(_failure).toList(),
};
CleanupScopeSummary _readScope(Object? value) {
  final o = _Object(value, 'state failures');
  return CleanupScopeSummary(
    state: _code<CleanupState>(
      o.s('state'),
      CleanupState.values,
      (v) => v.code,
    ),
    failures: (o['failures'] as List).map(_readFailure).toList(),
  );
}

Map<String, Object?> _cleanup(CleanupSummary v) => {
  'core': _scope(v.core),
  'hostSubscriptions': _scope(v.hostSubscriptions),
  'aggregate': v.aggregate.code,
};
CleanupSummary _readCleanup(Object? value) {
  final o = _Object(value, 'core hostSubscriptions aggregate');
  return CleanupSummary(
    core: _readScope(o['core']),
    hostSubscriptions: _readScope(o['hostSubscriptions']),
    aggregate: _code<CleanupState>(
      o.s('aggregate'),
      CleanupState.values,
      (v) => v.code,
    ),
  );
}

Map<String, Object?> _logical(LogicalSummary v) => {
  'operation': v.operation.code,
  'reason': v.reason?.code,
  'stage': v.stage?.code,
  'failure': v.failure == null ? null : _failure(v.failure!),
  ...switch (v) {
    SendSummary() => {'send': v.send == null ? null : _send(v.send!)},
    ListenSummary() => {
      'reception': v.reception == null ? null : _reception(v.reception!),
      'receptionReason': v.receptionReason?.code,
      'publishedEntries': v.publishedEntries,
      'processedEntries': v.processedEntries,
      'matchingDatagrams': v.matchingDatagrams,
      'filteredDatagrams': v.filteredDatagrams,
      'ordinaryMessages': v.ordinaryMessages,
    },
    PingSummary() => {
      'send': v.send == null ? null : _send(v.send!),
      'reception': v.reception == null ? null : _reception(v.reception!),
      'processedEntries': v.processedEntries,
      'matchingPongObserved': v.matchingPongObserved,
      'exactContentValidated': v.exactContentValidated,
      'roundTripSucceeded': v.roundTripSucceeded,
      'firstMatchingPongElapsedUs': v.firstMatchingPongElapsedUs,
      'applicationRttUs': v.applicationRttUs,
      'matchingPongDuplicates': v.matchingPongDuplicates,
    },
    RespondSummary() => {
      'lastSend': v.lastSend == null ? null : _send(v.lastSend!),
      'reception': v.reception == null ? null : _reception(v.reception!),
      'processedEntries': v.processedEntries,
      'listenStopReason': v.listenStopReason?.code,
      'responseAttempts': v.responseAttempts,
      'localResponsesConfirmed': v.localResponsesConfirmed,
      'duplicates': v.duplicates,
      'conflicts': v.conflicts,
      'cacheCapacityRejections': v.cacheCapacityRejections,
      'returnCapacityRejections': v.returnCapacityRejections,
    },
  },
};
LogicalSummary _readLogical(Object? value, DiagnosticOperation operation) {
  final fields = switch (operation) {
    DiagnosticOperation.send => 'send',
    DiagnosticOperation.listen => 'reception receptionReason publishedEntries processedEntries matchingDatagrams filteredDatagrams ordinaryMessages',
    DiagnosticOperation.ping => 'send reception processedEntries matchingPongObserved exactContentValidated roundTripSucceeded firstMatchingPongElapsedUs applicationRttUs matchingPongDuplicates',
    DiagnosticOperation.respond => 'lastSend reception processedEntries listenStopReason responseAttempts localResponsesConfirmed duplicates conflicts cacheCapacityRejections returnCapacityRejections',
  };
  final o = _Object(value, 'operation reason stage failure $fields');
  if (_operation(o.s('operation')) != operation) throw const FormatException();
  return switch (operation) {
    DiagnosticOperation.send => SendSummary(
      reason: o['reason'] == null
          ? null
          : _code<LogicalReason>(
              o.s('reason'),
              LogicalReason.values,
              (v) => v.code,
            ),
      stage: o['stage'] == null
          ? null
          : _code<DiagnosticStage>(
              o.s('stage'),
              DiagnosticStage.values,
              (v) => v.code,
            ),
      failure: o['failure'] == null ? null : _readFailure(o['failure']),
      send: o['send'] == null ? null : _readSend(o['send']),
    ),
    DiagnosticOperation.listen => ListenSummary(
      reason: o['reason'] == null
          ? null
          : _code<LogicalReason>(
              o.s('reason'),
              LogicalReason.values,
              (v) => v.code,
            ),
      stage: o['stage'] == null
          ? null
          : _code<DiagnosticStage>(
              o.s('stage'),
              DiagnosticStage.values,
              (v) => v.code,
            ),
      failure: o['failure'] == null ? null : _readFailure(o['failure']),
      reception: o['reception'] == null ? null : _readReception(o['reception']),
      receptionReason: o['receptionReason'] == null
          ? null
          : _code<ReceptionReason>(
              o.s('receptionReason'),
              ReceptionReason.values,
              (v) => v.code,
            ),
      publishedEntries: o.ni('publishedEntries'),
      processedEntries: o.ni('processedEntries'),
      matchingDatagrams: o.ni('matchingDatagrams'),
      filteredDatagrams: o.ni('filteredDatagrams'),
      ordinaryMessages: o.ni('ordinaryMessages'),
    ),
    DiagnosticOperation.ping => PingSummary(
      reason: o['reason'] == null
          ? null
          : _code<LogicalReason>(
              o.s('reason'),
              LogicalReason.values,
              (v) => v.code,
            ),
      stage: o['stage'] == null
          ? null
          : _code<DiagnosticStage>(
              o.s('stage'),
              DiagnosticStage.values,
              (v) => v.code,
            ),
      failure: o['failure'] == null ? null : _readFailure(o['failure']),
      send: o['send'] == null ? null : _readSend(o['send']),
      reception: o['reception'] == null ? null : _readReception(o['reception']),
      processedEntries: o.ni('processedEntries'),
      matchingPongObserved: o.nb('matchingPongObserved'),
      exactContentValidated: o.nb('exactContentValidated'),
      roundTripSucceeded: o.nb('roundTripSucceeded'),
      firstMatchingPongElapsedUs: o.ni('firstMatchingPongElapsedUs'),
      applicationRttUs: o.ni('applicationRttUs'),
      matchingPongDuplicates: o.ni('matchingPongDuplicates'),
    ),
    DiagnosticOperation.respond => RespondSummary(
      reason: o['reason'] == null
          ? null
          : _code<LogicalReason>(
              o.s('reason'),
              LogicalReason.values,
              (v) => v.code,
            ),
      stage: o['stage'] == null
          ? null
          : _code<DiagnosticStage>(
              o.s('stage'),
              DiagnosticStage.values,
              (v) => v.code,
            ),
      failure: o['failure'] == null ? null : _readFailure(o['failure']),
      lastSend: o['lastSend'] == null ? null : _readSend(o['lastSend']),
      reception: o['reception'] == null ? null : _readReception(o['reception']),
      processedEntries: o.ni('processedEntries'),
      listenStopReason: o['listenStopReason'] == null
          ? null
          : _code<ListenStopReason>(
              o.s('listenStopReason'),
              ListenStopReason.values,
              (v) => v.code,
            ),
      responseAttempts: o.ni('responseAttempts'),
      localResponsesConfirmed: o.ni('localResponsesConfirmed'),
      duplicates: o.ni('duplicates'),
      conflicts: o.ni('conflicts'),
      cacheCapacityRejections: o.ni('cacheCapacityRejections'),
      returnCapacityRejections: o.ni('returnCapacityRejections'),
    ),
  };
}
