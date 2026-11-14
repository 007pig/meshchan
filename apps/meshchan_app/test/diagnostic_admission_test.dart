import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart' show CompanionTransport;

import '../tool/diagnostic_fixture.dart';
import 'recording_adapter_test.dart' show ControlledRecording, finishedResult;

final class ControlledStorage implements CoreStorage {
  ControlledStorage(this.inner, this.operation);
  final CoreStorage inner;
  final ControlledRecording operation;
  bool recorded = false;
  @override
  StorageState get state => inner.state;
  @override
  DiagnosticHistory get history => inner.history;
  @override
  DraftRepository get drafts => inner.drafts;
  @override
  ProfileRepository get profiles => inner.profiles;
  @override
  SettingsRepository get settings => inner.settings;
  @override
  Future<EffectiveParameters> resolveParameters(EffectiveParameterRequest r) =>
      inner.resolveParameters(r);
  @override
  RecordedOperation record({
    required EffectiveParameters parameters,
    required String appVersion,
    required CompanionTransport Function() createTransport,
    List<RecordingSubscription> subscriptions = const [],
  }) {
    recorded = true;
    return operation;
  }

  @override
  Future<void> close() => inner.close();
}

void main() {
  for (final mode in [
    'initial',
    'unconfirmed',
    'pending',
    'scopeFailure',
    'saveFailure',
    'cleanupUnconfirmed',
    'observerFailure',
  ]) {
    test('tracked preparation/cleanup offline capability: $mode', () async {
      final dir = Directory.systemTemp.createTempSync(
        'meshchan-diagnostic-admission-',
      );
      final op = ControlledRecording();
      final inner = await CoreStorage.open(dataDirectory: dir);
      final storage = ControlledStorage(inner, op);
      final port = ReceivePort();
      final events = <WorkerEvent>[];
      final dispatcher = WorkerDispatcher(
        WorkerBootstrap(1, dir.path, port.sendPort),
        send: events.add,
        finish: () {},
        openStorage: (_) async => storage,
      );
      Future<void> until(bool Function() predicate) async {
        while (!predicate()) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      dispatcher.start();
      await until(() => dispatcher.snapshot.phase == RuntimePhase.ready);
      var id = 0;
      void send(RuntimeRequest request) =>
          dispatcher.receive(RequestEnvelope(1, ++id, request));
      send(
        StartRecordedDiagnostic(7, ' explicit fixture ', diagnosticRequest()),
      );
      expect(events.whereType<RequestReply>().last.value, isA<Accepted>());
      expect(dispatcher.snapshot.operation!.attemptId, 7);
      expect(dispatcher.snapshot.operation!.runId, null);
      expect(dispatcher.snapshot.operation!.logical, null);
      send(StartRecordedDiagnostic(8, 'other', diagnosticRequest()));
      expect(events.whereType<RequestReply>().last.error, isNotNull);
      await until(() => storage.recorded);
      if (mode != 'initial') {
        op.cleanups.add(
          CleanupSummary(
            core: CleanupScopeSummary(
              state: mode == 'unconfirmed'
                  ? CleanupState.unconfirmed
                  : CleanupState.pending,
            ),
            hostSubscriptions: CleanupScopeSummary(
              state: CleanupState.pending,
              failures: mode == 'scopeFailure'
                  ? const [
                      FailureSummary(
                        domain: FailureDomain.host,
                        kind: FailureKind.cleanup,
                      ),
                    ]
                  : const [],
            ),
            aggregate: CleanupState.pending,
          ),
        );
      }
      if (mode == 'saveFailure' || mode == 'cleanupUnconfirmed') {
        op.logicalSaveValue.complete(
          RecordingSave(
            RecordingPhase.logical,
            RecordingSaveState.failed,
            error: CoreException(
              CoreErrorCode.storageWriteFailed,
              cleanupUnconfirmed: mode == 'cleanupUnconfirmed',
            ),
          ),
        );
      }
      if (mode == 'observerFailure') {
        op.cleanups.addError(StateError('PRIVATE sentinel port route content'));
      }
      await Future<void>.delayed(Duration.zero);
      const decision = DraftDecision(1, 3, target: EditorTarget.settings);
      send(const BeginDraftDecision(decision));
      final healthy = ![
        'scopeFailure',
        'cleanupUnconfirmed',
        'observerFailure',
      ].contains(mode);
      expect(events.whereType<RequestReply>().last.error == null, healthy);
      if (healthy) {
        send(
          WriteSettings(
            AppSettings(diagnosticHistoryLimit: 1234),
            decision: decision,
          ),
        );
        final saveId = id;
        await until(
          () => events.whereType<RequestReply>().any((e) => e.id == saveId),
        );
        expect(events.whereType<RequestReply>().last.error, null);
        send(WriteSettings(AppSettings(), decision: decision));
        expect(events.whereType<RequestReply>().last.error, isNotNull);
        send(const EndDraftDecision(decision));
        expect(events.whereType<RequestReply>().last.error, null);
      }
      // Scoped cancel ACK never waits for the still-pending fake logical signal.
      send(const CancelRecordedDiagnostic(1, 7));
      expect(events.whereType<RequestReply>().last.value, isA<Accepted>());
      op.result.complete(
        finishedResult(
          cleanup: healthy ? CleanupState.succeeded : CleanupState.failed,
        ),
      );
      await until(
        () =>
            dispatcher.snapshot.operation!.done &&
            dispatcher.snapshot.gate != DeviceGateState.occupied,
      );
      expect(
        dispatcher.snapshot.gate,
        healthy ? DeviceGateState.free : DeviceGateState.quarantined,
      );
      send(const ShutdownRuntime());
      await until(() => events.whereType<ReleaseReport>().isNotEmpty);
      expect(events.whereType<ReleaseReport>().last.resourcesReleased, healthy);
      // Explicit test reclamation of a fake ambiguous handle, never a product
      // release assertion. Product shutdown retained its owner above.
      if (!healthy) await inner.close();
      await op.streamsClose();
      port.close();
      dir.deleteSync(recursive: true);
    });
  }
}
