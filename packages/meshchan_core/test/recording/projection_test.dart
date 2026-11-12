import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/recording/projection.dart';
import 'package:meshchan_core/src/recording/validation.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshcore_link/meshcore_link.dart' as link;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  for (final operation in DiagnosticOperation.values) {
    test(
      '${operation.code} safe configuration uses only applicable fields and actual byte lengths',
      () {
        final execution = input(operation);
        final config = projectConfiguration(execution);
        validateConfiguration(config);
        final row = encodeRun(
          DiagnosticRun(
            runId: fixtureId(1),
            appVersion: 'host-7',
            configuration: config,
            preparedAt: instant,
          ),
        );
        final json = row.configurationJson.value;
        expect(config.operation, operation);
        expect(config.appTargetVersion, 3);
        expect(config.maxQueuedCommands, 8);
        expect(json, contains('"requestTimeoutSeconds":5'));
        expect(json, isNot(contains('localTestId')));
        expect(json, isNot(contains('path":')));
        if (config is SendConfiguration) {
          expect(config.payloadByteLength, 3);
          expect(config.dataType, 99);
        }
        if (config is ListenConfiguration) {
          expect(config.maxReadsPerBatch, 8);
          expect(config.dataType, isNull);
        }
        if (config is TaskConfiguration) {
          expect(config.diagnosticWireVersion, 1);
          expect(config.diagnosticDataType, 65535);
        }
        if (config is PingConfiguration) expect(config.contentByteLength, 3);
        if (config is RespondConfiguration) {
          expect(config.cacheCapacity, 128);
          expect(config.cacheTtlUs, 120000000);
        }
      },
    );
  }
  test('nonempty Direct route stores its real length, and explicit empty bytes stay zero', () {
    final execution = EffectiveParameters(
      profileId: fixtureId(9),
      parameters: SendProfileParameters(
        budgets: budgets,
        sendChannelIndex: 0,
        dataType: 65535,
        route: ProfileRoute(routeDescriptor: 0x60, path: List.filled(64, 0xab)),
      ),
      content: [],
    );
    final config = projectConfiguration(execution) as SendConfiguration;
    validateConfiguration(config);
    expect(config.route.pathByteCount, 64);
    expect(config.payloadByteLength, 0);
  });

  test('task with absent reception keeps null despite publishedEntries default getter', () {
    final result = link.DiagnosticPingResult(
      reason: link.DiagnosticTaskReason.canceled,
      stage: link.DiagnosticTaskStage.startup,
      send: const link.DiagnosticSendFacts(
        attempted: false,
        pendingAtTermination: false,
        deviceAcceptanceConfirmed: false,
      ),
      processedEntries: 0,
      firstMatchingPongElapsed: null,
      matchingPongDuplicates: 0,
    );
    expect(result.publishedEntries, 0);
    final summary = projectTask(result) as PingSummary;
    expect(summary.reception, isNull);
    expect(summary.send!.dispatched, isNull);
    expect(summary.matchingPongObserved, isFalse);
    expect(summary.processedEntries, 0);
  });

  test('every public task reason and stage has an explicit stable mapping', () {
    const reasons = [
      'completed',
      'startRejected',
      'nonceGenerationFailed',
      'initializationFailed',
      'sendFailed',
      'receptionFailed',
      'sessionFailed',
      'responseTimeout',
      'taskTimeout',
      'canceled',
      'entryLimit',
    ];
    const stages = [
      'startup',
      'nonceGeneration',
      'connecting',
      'receiving',
      'sending',
      'waiting',
      'settling',
    ];
    expect(
      link.DiagnosticTaskReason.values.map((v) => taskReason(v).code),
      reasons,
    );
    expect(
      link.DiagnosticTaskStage.values.map((v) => taskStage(v).code),
      stages,
    );
    expect(
      link.MeshCoreSessionFailureKind.values.map((v) => sessionKind(v).code),
      [
        'transport',
        'protocol',
        'deviceRejected',
        'requestTimeout',
        'initializationTimeout',
        'disconnected',
        'canceled',
        'cleanup',
      ],
    );
    expect(link.MeshCoreSessionState.values.map((v) => sessionStage(v).code), [
      'idle',
      'opening',
      'initializing',
      'ready',
      'closing',
      'closed',
      'failed',
    ]);
    expect(
      link.MeshCoreReceptionStopReason.values.map(
        (v) => receptionReason(v).code,
      ),
      [
        'startRejected',
        'stopped',
        'subscriptionCanceled',
        'durationElapsed',
        'entryLimit',
        'sessionClosed',
        'sessionFailed',
      ],
    );
  });

  test(
    'notStarted is unconfirmed, and actual task notRequired is distinct',
    () {
      expect(
        projectTaskCleanup(
          link.DiagnosticCleanupResult(
            link.DiagnosticCleanupState.notStarted,
            [],
          ),
        ).state,
        CleanupState.unconfirmed,
      );
      expect(
        projectTaskCleanup(
          link.DiagnosticCleanupResult(
            link.DiagnosticCleanupState.notRequired,
            [],
          ),
        ).state,
        CleanupState.notRequired,
      );
    },
  );

  test('aggregate gives pending precedence over failure, recovery changes only unresolved scopes', () {
    final failed = CleanupScopeSummary(
      state: CleanupState.failed,
      failures: [
        const FailureSummary(
          domain: FailureDomain.cleanup,
          kind: FailureKind.cleanup,
        ),
      ],
    );
    expect(
      combineCleanup(
        failed,
        CleanupScopeSummary(state: CleanupState.pending),
      ).aggregate,
      CleanupState.pending,
    );
    expect(
      combineCleanup(
        failed,
        CleanupScopeSummary(state: CleanupState.succeeded),
      ).aggregate,
      CleanupState.failed,
    );
    expect(
      combineCleanup(
        CleanupScopeSummary(state: CleanupState.notRequired),
        CleanupScopeSummary(state: CleanupState.notRequired),
      ).aggregate,
      CleanupState.notRequired,
    );
    expect(
      combineCleanup(
        failed,
        CleanupScopeSummary(state: CleanupState.unconfirmedAfterExit),
      ).aggregate,
      CleanupState.unconfirmedAfterExit,
    );
  });

  test('semantic validation rejects contradictions without imposing wall-clock ordering', () {
    final config = projectConfiguration(input(DiagnosticOperation.ping));
    for (final summary in <LogicalSummary>[
      const SendSummary(
        reason: LogicalReason.canceled,
        stage: DiagnosticStage.startup,
      ),
      const PingSummary(
        reason: LogicalReason.completed,
        stage: DiagnosticStage.sending,
        roundTripSucceeded: false,
      ),
      const PingSummary(
        reason: LogicalReason.sendFailed,
        stage: DiagnosticStage.sending,
        matchingPongObserved: false,
        firstMatchingPongElapsedUs: 1,
      ),
      const PingSummary(applicationRttUs: 1, roundTripSucceeded: false),
      const PingSummary(processedEntries: -1),
      const PingSummary(
        send: SendFacts(
          attempted: false,
          pendingAtTermination: false,
          deviceAcceptanceConfirmed: true,
        ),
      ),
    ]) {
      expect(
        () => validateLogical(summary, config),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
    validateRun(
      DiagnosticRun(
        runId: fixtureId(1),
        appVersion: 'v',
        configuration: config,
        preparedAt: instant,
        logicalEndedAt: instant.subtract(const Duration(days: 1)),
        recordState: DiagnosticRecordState.settled,
        result: const PingSummary(
          reason: LogicalReason.canceled,
          stage: DiagnosticStage.startup,
        ),
      ),
    );
  });

  test('RTT conversion preserves communication microseconds and PONG evidence through failure', () {
    final result = link.DiagnosticPingResult(
      reason: link.DiagnosticTaskReason.sendFailed,
      stage: link.DiagnosticTaskStage.sending,
      send: const link.DiagnosticSendFacts(
        attempted: true,
        pendingAtTermination: true,
        deviceAcceptanceConfirmed: false,
      ),
      processedEntries: 1,
      firstMatchingPongElapsed: const Duration(microseconds: 1234567),
      matchingPongDuplicates: 2,
    );
    final summary = projectTask(result) as PingSummary;
    expect(summary.firstMatchingPongElapsedUs, 1234567);
    expect(summary.applicationRttUs, isNull);
    expect(summary.matchingPongDuplicates, 2);
    expect(summary.matchingPongObserved, isTrue);
  });

  test('entry limit keeps its controlled reason without inventing unexpected failure', () {
    final r = link.DiagnosticPingResult(
      reason: link.DiagnosticTaskReason.entryLimit,
      stage: link.DiagnosticTaskStage.receiving,
      send: const link.DiagnosticSendFacts(
        attempted: false,
        pendingAtTermination: false,
        deviceAcceptanceConfirmed: false,
      ),
      processedEntries: 1,
      firstMatchingPongElapsed: null,
      matchingPongDuplicates: 0,
    );
    final s = projectTask(r);
    expect(s.reason, LogicalReason.entryLimit);
    expect(s.failure!.domain, FailureDomain.task);
    expect(s.failure!.kind, isNull);
  });

  test('zero-response responder completion is not an observed round trip', () {
    final r = link.DiagnosticResponderResult(
      reason: link.DiagnosticTaskReason.completed,
      stage: link.DiagnosticTaskStage.receiving,
      send: const link.DiagnosticSendFacts(
        attempted: false,
        pendingAtTermination: false,
        deviceAcceptanceConfirmed: false,
      ),
      processedEntries: 0,
      listenStopReason: link.DiagnosticListenStopReason.durationElapsed,
      responseAttempts: 0,
      localResponsesConfirmed: 0,
      duplicates: 0,
      conflicts: 0,
      cacheCapacityRejections: 0,
      returnCapacityRejections: 0,
    );
    final summary = projectTask(r) as RespondSummary;
    validateLogical(
      summary,
      projectConfiguration(input(DiagnosticOperation.respond)),
    );
    expect(summary.responseAttempts, 0);
    expect(summary.lastSend!.attempted, isFalse);
    expect(summary.reception, isNull);
  });
}
