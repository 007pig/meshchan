import 'package:meshchan_core/meshchan_core.dart';

final instant = DateTime.utc(2026, 11, 11, 12, 3, 4, 567, 891);
LocalId fixtureId(int n) => LocalId(n.toRadixString(16).padLeft(32, '0'));
const budgets = ProfileBudgets(
  taskTimeoutSeconds: 19,
  startupDelayMilliseconds: 7,
);
final route = ProfileRoute(routeDescriptor: 0x12, path: [0xab, 0xcd]);
const safeRoute = DiagnosticRoute(routeDescriptor: 0x12, pathByteCount: 2);
const endpoints = ProfileTestEndpoints(localTestId: 0xffffffff, peerTestId: 42);
final draft = Draft(
  id: fixtureId(1),
  content: const DraftContent(
    title: '  中文 🚀\r\n ',
    body: '\n 原样 😀\r\n\rbody\t ',
  ),
  createdAt: instant,
  updatedAt: instant.subtract(const Duration(microseconds: 3)),
  revision: 7,
);
final profiles = <ConnectionProfile>[
  for (final parameters in <ProfileParameters>[
    SendProfileParameters(
      budgets: budgets,
      sendChannelIndex: 3,
      route: route,
      dataType: 99,
    ),
    const ListenProfileParameters(
      budgets: budgets,
      receiveChannelIndex: 4,
      listenDurationSeconds: 8,
    ),
    PingProfileParameters(
      budgets: budgets,
      sendChannelIndex: 3,
      receiveChannelIndex: 4,
      route: route,
      endpoints: endpoints,
      responseTimeoutSeconds: 2,
    ),
    RespondProfileParameters(
      budgets: budgets,
      sendChannelIndex: 3,
      receiveChannelIndex: 4,
      route: route,
      endpoints: endpoints,
      listenDurationSeconds: 8,
      maxResponses: 2,
    ),
  ])
    ConnectionProfile(
      id: fixtureId(10 + parameters.operation.index),
      content: ProfileContent(
        name: ' same name ',
        portHint: '/private/local-port',
        parameters: parameters,
      ),
      updatedAt: instant,
    ),
];
const sessionFailure = SessionFailureSummary(
  kind: FailureKind.protocol,
  stage: SessionStage.ready,
  commandOpcode: 55,
  expectedResponseOpcode: 0,
  deviceErrorCode: 6,
  deviceErrorName: DeviceErrorName.illegalArgument,
);
const failure = FailureSummary(
  domain: FailureDomain.host,
  kind: FailureKind.cleanup,
  stage: DiagnosticStage.settling,
  hostCleanupStage: HostCleanupStage.signalSubscription,
  session: sessionFailure,
);
const sendFacts = SendFacts(
  attempted: true,
  pendingAtTermination: false,
  deviceAcceptanceConfirmed: false,
  dispatched: true,
  localWriteCompleted: false,
  localOkObserved: null,
  commandFailure: CommandFailureFacts(
    commandOpcode: 55,
    dispatched: true,
    localWriteCompleted: false,
    matchingResponseObserved: true,
    sessionFailure: sessionFailure,
  ),
);
const reception = ReceptionSummary(
  reason: ReceptionReason.stopped,
  publishedEntries: 3,
  dispatchedReads: 5,
  completedReads: 4,
);
final cleanup = CleanupSummary(
  core: CleanupScopeSummary(state: CleanupState.succeeded),
  hostSubscriptions: CleanupScopeSummary(
    state: CleanupState.failed,
    failures: [failure],
  ),
  aggregate: CleanupState.failed,
);
final runs = <DiagnosticRun>[
  DiagnosticRun(
    runId: fixtureId(20),
    appVersion: '0.1.0-dev.2',
    profileId: profiles.first.id,
    configuration: const SendConfiguration(
      budgets: budgets,
      sendChannelIndex: 3,
      dataType: 99,
      route: safeRoute,
      payloadByteLength: 300,
    ),
    preparedAt: instant,
    cleanup: cleanup,
  ),
  DiagnosticRun(
    runId: fixtureId(21),
    appVersion: '0.1.0-dev.2',
    configuration: const ListenConfiguration(
      budgets: budgets,
      receiveChannelIndex: 4,
      listenDurationSeconds: 8,
      maxEntries: 128,
    ),
    preparedAt: instant,
    result: const ListenSummary(
      reception: reception,
      processedEntries: 2,
      matchingDatagrams: 0,
      ordinaryMessages: null,
    ),
  ),
  DiagnosticRun(
    runId: fixtureId(22),
    appVersion: '0.1.0-dev.2',
    configuration: const PingConfiguration(
      budgets: budgets,
      sendChannelIndex: 3,
      receiveChannelIndex: 4,
      route: safeRoute,
      maxEntries: 128,
      responseTimeoutSeconds: 2,
      contentByteLength: 13,
    ),
    preparedAt: instant,
    logicalEndedAt: instant.add(const Duration(microseconds: 7)),
    recordState: DiagnosticRecordState.settled,
    result: const PingSummary(
      reason: LogicalReason.completed,
      stage: DiagnosticStage.settling,
      send: sendFacts,
      reception: reception,
      matchingPongObserved: true,
      exactContentValidated: true,
      roundTripSucceeded: true,
      firstMatchingPongElapsedUs: 9007199254740993,
      applicationRttUs: 1234567,
      matchingPongDuplicates: null,
    ),
    cleanup: cleanup,
  ),
  DiagnosticRun(
    runId: fixtureId(23),
    appVersion: '0.1.0-dev.2',
    configuration: const RespondConfiguration(
      budgets: budgets,
      sendChannelIndex: 3,
      receiveChannelIndex: 4,
      route: safeRoute,
      maxEntries: 128,
      listenDurationSeconds: 8,
      maxResponses: 2,
    ),
    preparedAt: instant,
    recordState: DiagnosticRecordState.recoveredArchived,
    result: const RespondSummary(
      lastSend: sendFacts,
      responseAttempts: 1,
      localResponsesConfirmed: 0,
      duplicates: 0,
      conflicts: null,
      listenStopReason: ListenStopReason.responseLimit,
      failure: failure,
    ),
    recoveredAt: instant.add(const Duration(microseconds: 19)),
    recoveryReason: RecoveryReason.cleanupUnconfirmed,
  ),
];

// Lifecycle-valid fixtures for business reopen/isolation tests. The structural
// codec fixtures above intentionally cover values outside the recording contract.
const legalRoute = DiagnosticRoute(routeDescriptor: 0x02, pathByteCount: 2);
final legalProfile = ConnectionProfile(
  id: profiles.first.id,
  content: ProfileContent(
    name: profiles.first.name,
    portHint: profiles.first.portHint,
    parameters: SendProfileParameters(
      budgets: budgets,
      sendChannelIndex: 3,
      dataType: 99,
      route: ProfileRoute(routeDescriptor: 0x02, path: [0xab, 0xcd]),
    ),
  ),
  updatedAt: instant,
);
final legalRuns = <DiagnosticRun>[
  for (final (index, configuration, result)
      in <(int, DiagnosticConfiguration, LogicalSummary)>[
        (
          0,
          const SendConfiguration(
            budgets: budgets,
            sendChannelIndex: 3,
            dataType: 99,
            route: legalRoute,
            payloadByteLength: 3,
          ),
          const SendSummary(
            reason: LogicalReason.canceled,
            stage: DiagnosticStage.sending,
          ),
        ),
        (
          1,
          const ListenConfiguration(
            budgets: budgets,
            receiveChannelIndex: 4,
            listenDurationSeconds: 8,
            maxEntries: 128,
          ),
          const ListenSummary(
            reason: LogicalReason.canceled,
            stage: DiagnosticStage.receiving,
          ),
        ),
        (
          2,
          const PingConfiguration(
            budgets: budgets,
            sendChannelIndex: 3,
            receiveChannelIndex: 4,
            route: legalRoute,
            maxEntries: 128,
            responseTimeoutSeconds: 2,
            contentByteLength: 3,
          ),
          const PingSummary(
            reason: LogicalReason.canceled,
            stage: DiagnosticStage.connecting,
          ),
        ),
        (
          3,
          const RespondConfiguration(
            budgets: budgets,
            sendChannelIndex: 3,
            receiveChannelIndex: 4,
            route: legalRoute,
            maxEntries: 128,
            listenDurationSeconds: 8,
            maxResponses: 2,
          ),
          const RespondSummary(
            reason: LogicalReason.canceled,
            stage: DiagnosticStage.receiving,
          ),
        ),
      ])
    DiagnosticRun(
      runId: fixtureId(80 + index),
      appVersion: 'fixture',
      profileId: profiles.first.id,
      configuration: configuration,
      preparedAt: instant,
      recordState: DiagnosticRecordState.settled,
      logicalEndedAt: instant,
      result: result,
      cleanup: cleanup,
    ),
];
