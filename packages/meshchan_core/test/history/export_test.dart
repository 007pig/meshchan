import 'dart:convert';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/recording/projection.dart';
import 'package:meshchan_core/src/recording/validation.dart';
import 'package:test/test.dart';

import '../repositories/profile_fixtures.dart';
import 'support.dart';

void keys(Map<String, dynamic> value, String expected) =>
    expect(value.keys.toSet(), expected.split(' ').toSet());
void main() {
  late Fixture f;
  setUp(() {
    f = Fixture();
  });
  tearDown(() => f.close());

  test('parsed whitelist for four operations preserves partial/null/false/zero, failures, six-digit UTC and bounded continuation', () async {
    final exported = DateTime.utc(2026, 11, 12, 9, 30);
    final s = await f.open(clock: () => exported);
    final failed = CleanupScopeSummary(
      state: CleanupState.failed,
      failures: [
        const FailureSummary(
          domain: FailureDomain.host,
          kind: FailureKind.cleanup,
          hostCleanupStage: HostCleanupStage.signalSubscription,
        ),
      ],
    );
    final runs = <DiagnosticRun>[];
    for (var i = 0; i < 4; i++) {
      final privateRoute = ProfileRoute(routeDescriptor: 2, path: [0xab, 0xcd]);
      const privateEndpoints = ProfileTestEndpoints(
        localTestId: 4294967295,
        peerTestId: 3735928559,
      );
      final parameters = switch (i) {
        0 => sendParameters(route: privateRoute),
        1 => listenParameters(dataType: null),
        2 => pingParameters(route: privateRoute, endpoints: privateEndpoints),
        _ => respondParameters(
          route: privateRoute,
          endpoints: privateEndpoints,
        ),
      };
      final profile = await s.profiles.save(
        ProfileContent(
          name: 'PRIVATE PROFILE NAME',
          portHint: '/PRIVATE/serial-port',
          parameters: parameters,
        ),
      );
      final configuration = projectConfiguration(
        EffectiveParameters(
          profileId: profile.id,
          parameters: parameters,
          content: i == 0 || i == 2 ? utf8.encode('PRIVATE CONTENT') : null,
        ),
      );
      final result = switch (i) {
        0 => logical,
        1 => const ListenSummary(
          publishedEntries: 0,
          processedEntries: 0,
          matchingDatagrams: 0,
          filteredDatagrams: 0,
          ordinaryMessages: 0,
        ),
        2 => const PingSummary(
          reason: LogicalReason.sendFailed,
          stage: DiagnosticStage.sending,
          send: SendFacts(
            attempted: true,
            pendingAtTermination: false,
            deviceAcceptanceConfirmed: false,
            dispatched: true,
            localWriteCompleted: false,
            localOkObserved: false,
          ),
          matchingPongObserved: true,
          exactContentValidated: true,
          roundTripSucceeded: false,
          firstMatchingPongElapsedUs: 0,
          matchingPongDuplicates: 0,
        ),
        _ => const RespondSummary(
          responseAttempts: 0,
          localResponsesConfirmed: 0,
          duplicates: 0,
          conflicts: 0,
          cacheCapacityRejections: 0,
          returnCapacityRejections: 0,
        ),
      };
      final run = DiagnosticRun(
        runId: fixtureId(i + 1),
        appVersion: 'actual-app-1.0',
        configuration: configuration,
        profileId: profile.id,
        preparedAt: i.isEven
            ? DateTime.utc(2026, 11, 12, 9, 30)
            : DateTime.utc(2026, 11, 12, 9, 30, 0, 123, 456),
        logicalEndedAt: i == 0 || i == 2 ? instant : null,
        recordState: i == 3
            ? DiagnosticRecordState.recoveredArchived
            : i == 1
            ? DiagnosticRecordState.prepared
            : DiagnosticRecordState.settled,
        result: result,
        cleanup: i == 0
            ? combineCleanup(
                CleanupScopeSummary(state: CleanupState.succeeded),
                failed,
              )
            : i == 1
            ? combineCleanup(
                CleanupScopeSummary(state: CleanupState.pending),
                CleanupScopeSummary(state: CleanupState.unconfirmed),
              )
            : i == 3
            ? combineCleanup(
                CleanupScopeSummary(state: CleanupState.unconfirmedAfterExit),
                CleanupScopeSummary(state: CleanupState.notRequired),
              )
            : terminal,
        recoveredAt: i == 3 ? instant : null,
        recoveryReason: i == 3 ? RecoveryReason.interrupted : null,
      );
      validateRun(run);
      runs.add(run);
    }
    await f.seed(s, runs);
    final draft = await s.drafts.create(
      const DraftContent(body: 'PRIVATE CHAT BODY'),
    );
    final page = await s.history.exportSummary(size: PageSize(2));
    expect(page.nextCursor, isNotNull);
    final next = await s.history.exportSummary(
      size: PageSize(2),
      after: page.nextCursor,
    );
    expect(next.nextCursor, isNull);
    final all = <Map<String, dynamic>>[];
    for (final selection in [page, next]) {
      final root = jsonDecode(selection.json) as Map<String, dynamic>;
      keys(root, 'diagnosticSummaryFormatVersion exportedAt runs');
      expect(root['diagnosticSummaryFormatVersion'], 1);
      expect(root['exportedAt'], '2026-11-12T09:30:00.000000Z');
      expect(root['runs'], hasLength(2));
      all.addAll((root['runs'] as List).cast<Map<String, dynamic>>());
    }
    expect(all.map((r) => r['runId']), [
      fixtureId(4).value,
      fixtureId(2).value,
      fixtureId(3).value,
      fixtureId(1).value,
    ]);
    for (final run in all) {
      keys(
        run,
        'runId operation appVersion diagnosticSummaryFormatVersion configuration preparedAt logicalEndedAt recordState result cleanup recoveredAt recoveryReason',
      );
      expect(run['appVersion'], 'actual-app-1.0');
      for (final field in ['preparedAt', 'logicalEndedAt', 'recoveredAt']) {
        if (run[field] != null) {
          expect(
            run[field],
            matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$')),
          );
        }
      }
      final c = run['configuration'] as Map<String, dynamic>;
      final extra = switch (run['operation']) {
        'send' => 'sendChannelIndex dataType route payloadByteLength',
        'listen' => 'receiveChannelIndex dataType listenDurationSeconds maxEntries maxReadsPerBatch',
        'ping' => 'sendChannelIndex receiveChannelIndex route maxEntries maxReadsPerBatch diagnosticWireVersion diagnosticDataType responseTimeoutSeconds contentByteLength',
        _ => 'sendChannelIndex receiveChannelIndex route maxEntries maxReadsPerBatch diagnosticWireVersion diagnosticDataType listenDurationSeconds maxResponses cacheCapacity cacheTtlUs',
      };
      keys(c, 'operation budgets appTargetVersion maxQueuedCommands $extra');
      keys(
        c['budgets'] as Map<String, dynamic>,
        'requestTimeoutSeconds initializationTimeoutSeconds startupDelayMilliseconds taskTimeoutSeconds',
      );
      if (c['route'] case final Map<String, dynamic> route) {
        keys(route, 'routeDescriptor pathByteCount');
        expect(route, {'routeDescriptor': 2, 'pathByteCount': 2});
      }
      final cleanup = run['cleanup'] as Map<String, dynamic>;
      keys(cleanup, 'core hostSubscriptions aggregate');
      for (final scope in ['core', 'hostSubscriptions']) {
        keys(cleanup[scope] as Map<String, dynamic>, 'state failures');
        for (final failure in cleanup[scope]['failures'] as List) {
          keys(
            failure as Map<String, dynamic>,
            'domain kind stage hostCleanupStage session',
          );
        }
      }
      final result = run['result'] as Map<String, dynamic>;
      final fields = switch (run['operation']) {
        'send' => 'send',
        'listen' => 'reception receptionReason publishedEntries processedEntries matchingDatagrams filteredDatagrams ordinaryMessages',
        'ping' => 'send reception processedEntries matchingPongObserved exactContentValidated roundTripSucceeded firstMatchingPongElapsedUs applicationRttUs matchingPongDuplicates',
        _ => 'lastSend reception processedEntries listenStopReason responseAttempts localResponsesConfirmed duplicates conflicts cacheCapacityRejections returnCapacityRejections',
      };
      keys(result, 'operation reason stage failure $fields');
      if (result['send'] case final Map<String, dynamic> send) {
        keys(
          send,
          'attempted pendingAtTermination deviceAcceptanceConfirmed dispatched localWriteCompleted localOkObserved commandFailure',
        );
      }
    }
    final byOp = {for (final run in all) run['operation']: run};
    expect(byOp['send']!['result']['reason'], 'completed');
    expect(byOp['send']!['cleanup']['aggregate'], 'failed');
    expect(byOp['send']!['configuration']['payloadByteLength'], 15);
    expect(byOp['listen']!['configuration']['dataType'], isNull);
    expect(byOp['listen']!['result']['processedEntries'], 0);
    expect(byOp['listen']!['logicalEndedAt'], isNull);
    expect(byOp['listen']!['preparedAt'], '2026-11-12T09:30:00.123456Z');
    expect(byOp['ping']!['result']['matchingPongObserved'], isTrue);
    expect(byOp['ping']!['result']['send']['localWriteCompleted'], isFalse);
    expect(byOp['ping']!['result']['roundTripSucceeded'], isFalse);
    expect(byOp['ping']!['result']['firstMatchingPongElapsedUs'], 0);
    expect(byOp['ping']!['result']['applicationRttUs'], isNull);
    expect(
      byOp['respond']!['cleanup']['core']['state'],
      'unconfirmed_after_exit',
    );
    expect(byOp['respond']!['result']['reason'], isNull);
    expect(byOp['respond']!['recoveryReason'], 'interrupted');
    final leaves = <Object?>[];
    void walk(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          leaves.add(entry.key);
          walk(entry.value);
        }
      } else if (value is List) {
        for (final item in value) {
          walk(item);
        }
      } else {
        leaves.add(value);
      }
    }

    walk(all);
    for (final secret in [
      'PRIVATE PROFILE NAME',
      '/PRIVATE/serial-port',
      'PRIVATE CONTENT',
      'PRIVATE CHAT BODY',
      draft.id.value,
      ...runs.map((r) => r.profileId!.value),
      4294967295,
      3735928559,
      'profileId',
      'path',
      'localTestId',
      'peerTestId',
      'nonce',
      'argv',
      'stack',
    ]) {
      expect(leaves, isNot(contains(secret)));
    }
    expect(
      (await s.history.read(fixtureId(1))).profileId,
      runs.first.profileId,
    );
    final filtered = await s.history.exportSummary(
      filter: HistoryQuery(operation: DiagnosticOperation.ping),
    );
    expect(
      (jsonDecode(filtered.json)['runs'] as List).single['operation'],
      'ping',
    );
  });
}
