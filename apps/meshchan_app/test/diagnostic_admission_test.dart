import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

import '../../../packages/meshchan_core/test/history/support.dart'
    show Fixture, HistoryControl;
import '../tool/device_fixture.dart';
import '../tool/diagnostic_fixture.dart';
import 'recording_adapter_test.dart' show ControlledRecording, finishedResult;

final class ControlledStorage implements CoreStorage {
  ControlledStorage(this.inner, [this.operation]);
  final CoreStorage inner;
  final ControlledRecording? operation;
  Future<void> Function()? beforeResolve;
  void Function()? beforeRecord, afterRecord;
  RecordingSubscription? subscription;
  int resolves = 0, records = 0;
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
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest r,
  ) async {
    resolves++;
    await beforeResolve?.call();
    return inner.resolveParameters(r);
  }

  @override
  RecordedOperation record({
    required EffectiveParameters parameters,
    required String appVersion,
    required CompanionTransport Function() createTransport,
    List<RecordingSubscription> subscriptions = const [],
  }) {
    records++;
    beforeRecord?.call();
    final result =
        operation ??
        inner.record(
          parameters: parameters,
          appVersion: appVersion,
          createTransport: createTransport,
          subscriptions: [...subscriptions, ?subscription],
        );
    afterRecord?.call();
    return result;
  }

  @override
  Future<void> close() => inner.close();
}

final class _AdmissionDispatcher {
  _AdmissionDispatcher(
    ControlledStorage storage,
    String path, {
    required List<SerialPortDescription> Function() enumeratePorts,
    required CompanionTransportFactory createCheckTransport,
    required CompanionTransportFactory createDiagnosticTransport,
  }) {
    worker = WorkerDispatcher(
      WorkerBootstrap(1, path, _port.sendPort),
      send: (event) {
        if (event is SnapshotEvent) _snapshots.add(event.snapshot);
        if (event is RequestReply) _reply = event;
        if (event is ReleaseReport) _release.complete(event);
      },
      finish: () {},
      openStorage: (_) async => storage,
      enumeratePorts: enumeratePorts,
      createCheckTransport: createCheckTransport,
      createDiagnosticTransport: createDiagnosticTransport,
    );
    addTearDown(() async {
      await _snapshots.close();
      _port.close();
    });
  }

  final _port = ReceivePort();
  final _snapshots = StreamController<RuntimeSnapshot>.broadcast();
  final _release = Completer<ReleaseReport>();
  late final WorkerDispatcher worker;
  RequestReply? _reply;
  int _lastId = 0;

  RequestReply send(RuntimeRequest request, {int generation = 1, int? id}) {
    _reply = null;
    worker.receive(RequestEnvelope(generation, id ?? ++_lastId, request));
    return _reply!;
  }

  Future<RuntimeSnapshot> when(bool Function(RuntimeSnapshot) predicate) async {
    final current = worker.snapshot;
    return predicate(current)
        ? current
        : _snapshots.stream.firstWhere(predicate);
  }

  Future<void> start() async {
    worker.start();
    await when((snapshot) => snapshot.phase == RuntimePhase.ready);
  }

  Future<void> shutdown() async {
    worker.receive(RequestEnvelope(1, ++_lastId, const ShutdownRuntime()));
    expect((await _release.future).resourcesReleased, isTrue);
  }
}

void main() {
  test('raw requests reject unsupported targets before taking a lease', () async {
    final fixture = Fixture();
    addTearDown(fixture.close);
    final inner = await fixture.open();
    final storage = ControlledStorage(inner);
    var enumerations = 0, checks = 0, diagnostics = 0;
    final dispatcher = _AdmissionDispatcher(
      storage,
      fixture.directory.path,
      enumeratePorts: () {
        enumerations++;
        return [];
      },
      createCheckTransport: (_) {
        checks++;
        return DeviceFixtureTransport();
      },
      createDiagnosticTransport: (_) {
        diagnostics++;
        return DiagnosticFixtureTransport();
      },
    );
    final gate = dispatcher.worker.gate;
    await dispatcher.start();
    const options = DeviceCheckOptions();
    final usb = UsbSerialTarget(portPath: ' serial\tpath ');
    final tcp = TcpTarget(host: 'relay.example', port: 5000);
    final ble = BleTarget(selectionId: 'test-selection');
    final parameters = diagnosticRequest();
    final check = StartDeviceCheck(1, usb, options);
    final diagnostic = StartRecordedDiagnostic(1, usb, parameters);

    void rejects(RuntimeRequest request, CoordinationFault fault) {
      expect(dispatcher.send(request).error?.host, fault);
    }

    for (final target in [tcp, ble]) {
      rejects(
        StartDeviceCheck(1, target, options),
        CoordinationFault.invalidState,
      );
      final rejected = dispatcher.send(
        StartRecordedDiagnostic(1, target, parameters),
      );
      expect(rejected.error?.host, CoordinationFault.invalidState);
      expect(
        dispatcher.send(diagnostic, id: rejected.id).error?.host,
        CoordinationFault.staleRequest,
      );
      expect(gate.state, DeviceGateState.free);
      expect(gate.generation, 0);
    }
    rejects(
      StartRecordedDiagnostic(1, usb, const ListenParameterRequest()),
      CoordinationFault.invalidState,
    );
    final paused = dispatcher.send(const PauseAdmission());
    expect(
      dispatcher.send(check, generation: 2, id: 999).error?.host,
      CoordinationFault.staleRequest,
    );
    expect(
      dispatcher.send(diagnostic, id: paused.id).error?.host,
      CoordinationFault.staleRequest,
    );
    rejects(StartDeviceCheck(1, tcp, options), CoordinationFault.stopped);
    rejects(
      StartRecordedDiagnostic(1, ble, parameters),
      CoordinationFault.invalidState,
    );
    rejects(diagnostic, CoordinationFault.stopped);
    expect(dispatcher.send(const ResumeAdmission()).value, isA<Accepted>());
    expect(
      (enumerations, checks, diagnostics, storage.resolves, storage.records),
      (0, 0, 0, 0, 0),
    );
    expect(gate.state, DeviceGateState.free);
    expect(gate.generation, 0);
    expect(dispatcher.worker.snapshot.operation, isNull);
    expect(dispatcher.worker.snapshot.deviceCheck, isNull);
    expect(await fixture.count(inner), 0);

    // Reuse unadmitted command IDs with fresh envelope IDs. An invalid request
    // still wins over the busy gate while admission is open.
    expect(dispatcher.send(check).value, isA<Accepted>());
    rejects(StartDeviceCheck(2, ble, options), CoordinationFault.invalidState);
    rejects(StartDeviceCheck(2, usb, options), CoordinationFault.deviceBusy);
    rejects(
      StartRecordedDiagnostic(1, tcp, parameters),
      CoordinationFault.invalidState,
    );
    rejects(diagnostic, CoordinationFault.deviceBusy);
    expect(gate.generation, 1);
    expect(dispatcher.send(const CancelDeviceCheck(1)).value, isA<Accepted>());
    await dispatcher.when(
      (s) => s.deviceCheck!.settled && s.gate == DeviceGateState.free,
    );
    expect(dispatcher.send(diagnostic).value, isA<Accepted>());
    expect(gate.generation, 2);
    expect(
      dispatcher.send(const CancelRecordedDiagnostic(1, 1)).value,
      isA<Accepted>(),
    );
    await dispatcher.when(
      (s) => s.operation!.done && s.gate == DeviceGateState.free,
    );
    expect(
      (enumerations, checks, diagnostics, storage.resolves, storage.records),
      (0, 0, 0, 0, 0),
    );
    expect(await fixture.count(inner), 0);
    await dispatcher.shutdown();
  });

  test('each recorded factory starts after registration commits', () async {
    final fixture = Fixture();
    addTearDown(fixture.close);
    final control = HistoryControl();
    final inner = await fixture.open(control: control);
    var registrationCommitted = false;
    final storage = ControlledStorage(inner)
      ..beforeRecord = () {
        registrationCommitted = false;
        control.afterCommit = () => registrationCommitted = true;
      };
    final transports = <DiagnosticFixtureTransport>[];
    final entries = <(ConnectionTarget, bool, int)>[];
    final dispatcher = _AdmissionDispatcher(
      storage,
      fixture.directory.path,
      enumeratePorts: () => throw StateError('Unexpected enumeration'),
      createCheckTransport: (_) => throw StateError('Unexpected Check'),
      createDiagnosticTransport: (target) {
        final transport = DiagnosticFixtureTransport();
        transports.add(transport);
        entries.add((target, registrationCommitted, transport.opens));
        return transport;
      },
    );
    await dispatcher.start();
    const path = ' exact\tfixture ';
    for (final respond in [false, true]) {
      await inner.history.waitForMaintenance();
      final id = respond ? 2 : 1;
      final target = UsbSerialTarget(portPath: path);
      final request = StartRecordedDiagnostic(
        id,
        target,
        diagnosticRequest(respond: respond),
      );
      expect(dispatcher.send(request).value, isA<Accepted>());
      expect(entries, hasLength(id - 1));
      if (respond) {
        expect(
          dispatcher.send(const CancelRecordedDiagnostic(1, 1)).error?.host,
          CoordinationFault.staleRequest,
        );
      }
      final snapshot = await dispatcher.when(
        (s) =>
            s.operation?.attemptId == id &&
            s.operation!.done &&
            s.gate == DeviceGateState.free,
      );
      expect(
        snapshot.operation!.registration!.state,
        RecordingSaveState.committed,
      );
      expect(snapshot.operation!.fullySuccessful, isTrue);
      expect(entries, hasLength(id));
      expect(entries.last, (target, true, 0));
      expect(transports.last.opens, 1);
      expect(transports.last.closes, 1);
    }
    expect(transports[0], isNot(same(transports[1])));
    expect(storage.resolves, 2);
    expect(storage.records, 2);
    await dispatcher.shutdown();
    final reopened = await fixture.open();
    final rows = (await reopened.history.query()).items;
    expect(
      rows.map((r) => r.operation),
      unorderedEquals([DiagnosticOperation.ping, DiagnosticOperation.respond]),
    );
  });

  for (final mode in [
    'resolve failure',
    'cancel during resolve',
    'registration failure',
    'cancel during commit',
    'cancel before record returns',
  ]) {
    test(
      '$mode does not execute transport or subscription factories',
      () async {
        final fixture = Fixture();
        addTearDown(fixture.close);
        final control = HistoryControl();
        final storage = ControlledStorage(await fixture.open(control: control));
        var factories = 0, subscriptions = 0;
        storage.subscription = RecordingSubscription(
          stage: HostCleanupStage.signalSubscription,
          subscribe: (_) {
            subscriptions++;
            return const Stream<Object?>.empty().listen((_) {});
          },
        );
        final dispatcher = _AdmissionDispatcher(
          storage,
          fixture.directory.path,
          enumeratePorts: () => throw StateError('Unexpected enumeration'),
          createCheckTransport: (_) => throw StateError('Unexpected Check'),
          createDiagnosticTransport: (_) {
            factories++;
            return DiagnosticFixtureTransport();
          },
        );
        void cancel() {
          expect(
            dispatcher.send(const CancelRecordedDiagnostic(1, 1)).value,
            isA<Accepted>(),
          );
          expect(dispatcher.worker.gate.state, DeviceGateState.occupied);
        }

        final entered = Completer<void>(), resume = Completer<void>();
        Future<void> hold() async {
          entered.complete();
          await resume.future;
        }

        switch (mode) {
          case 'resolve failure':
            storage.beforeResolve = () async =>
                throw StateError('private resolve');
          case 'cancel during resolve':
            storage.beforeResolve = hold;
          case 'registration failure':
            storage.beforeRecord = () {
              control.beforeCommit = () async =>
                  throw StateError('private commit');
            };
          case 'cancel during commit':
            storage.beforeRecord = () => control.beforeCommit = hold;
          case 'cancel before record returns':
            storage.afterRecord = cancel;
        }
        await dispatcher.start();
        expect(
          dispatcher
              .send(
                StartRecordedDiagnostic(
                  1,
                  UsbSerialTarget(portPath: ' fixture '),
                  diagnosticRequest(),
                ),
              )
              .value,
          isA<Accepted>(),
        );
        if (mode == 'cancel during resolve' || mode == 'cancel during commit') {
          await entered.future;
          cancel();
          expect((factories, subscriptions), (0, 0));
          resume.complete();
        }
        final settled = await dispatcher.when(
          (s) => s.operation!.done && s.gate == DeviceGateState.free,
        );
        final operation = settled.operation!;
        expect((factories, subscriptions), (0, 0));
        expect(storage.resolves, 1);
        switch (mode) {
          case 'resolve failure':
          case 'cancel during resolve':
            expect(storage.records, 0);
            expect(operation.registration, isNull);
          case 'registration failure':
            expect(storage.records, 1);
            expect(operation.registration!.state, RecordingSaveState.failed);
            expect(
              operation.logicalSave!.state,
              RecordingSaveState.notAttempted,
            );
            expect(
              operation.cleanupSave!.state,
              RecordingSaveState.notAttempted,
            );
          case 'cancel during commit':
          case 'cancel before record returns':
            expect(storage.records, 1);
            expect(operation.registration!.state, RecordingSaveState.committed);
            expect(operation.logical, LogicalReason.canceled);
            expect(operation.resourcesReleased, isTrue);
        }
        await dispatcher.shutdown();
      },
    );
  }

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
        StartRecordedDiagnostic(
          7,
          UsbSerialTarget(portPath: ' explicit fixture '),
          diagnosticRequest(),
        ),
      );
      expect(events.whereType<RequestReply>().last.value, isA<Accepted>());
      expect(dispatcher.snapshot.operation!.attemptId, 7);
      expect(dispatcher.snapshot.operation!.runId, null);
      expect(dispatcher.snapshot.operation!.logical, null);
      send(
        StartRecordedDiagnostic(
          8,
          UsbSerialTarget(portPath: 'other'),
          diagnosticRequest(),
        ),
      );
      expect(events.whereType<RequestReply>().last.error, isNotNull);
      await until(() => storage.records == 1);
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
