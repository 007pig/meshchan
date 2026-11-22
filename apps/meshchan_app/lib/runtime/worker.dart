import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

import 'build_version.dart';
import 'protocol.dart';
import 'recording_adapter.dart';
import 'device_check.dart';

/// Production entry deliberately captures no host resources or closures.
void runtimeWorkerEntry(WorkerBootstrap bootstrap) {
  final commands = ReceivePort();
  final dispatcher = WorkerDispatcher(
    bootstrap,
    send: bootstrap.events.send,
    finish: commands.close,
  );
  commands.listen(dispatcher.receive);
  bootstrap.events.send(WorkerHello(bootstrap.generation, commands.sendPort));
  dispatcher.start();
}

/// Synchronous lease acquisition precedes resolution, repository I/O and factory
/// construction. Unknown release is retained rather than cleared in finally.
final class DeviceGate {
  DeviceGateState state = DeviceGateState.free;
  int generation = 0;
  int acquire() {
    if (state != DeviceGateState.free) {
      throw const RuntimeFault(host: CoordinationFault.deviceBusy);
    }
    state = DeviceGateState.occupied;
    return ++generation;
  }

  void settle(int lease, {required bool released}) {
    if (lease != generation || state != DeviceGateState.occupied) return;
    state = released ? DeviceGateState.free : DeviceGateState.quarantined;
  }
}

/// Shared by production and test-side workers. Injected dependencies are built
/// inside their worker entry; none travel in WorkerBootstrap or messages.
final class WorkerDispatcher {
  WorkerDispatcher(
    this.bootstrap, {
    required this.send,
    required this.finish,
    Future<CoreStorage> Function(Directory)? openStorage,
    List<SerialPortDescription> Function()? enumeratePorts,
    CompanionTransport Function(String)? createCheckTransport,
    CompanionTransport Function(String)? createDiagnosticTransport,
  }) : _createDiagnosticTransport =
           createDiagnosticTransport ?? createUsbCompanionTransport,
       _enumeratePorts = enumeratePorts ?? SerialPorts().listPorts,
       _createCheckTransport =
           createCheckTransport ?? createUsbCompanionTransport,
       _openStorage =
           openStorage ??
           ((directory) => CoreStorage.open(dataDirectory: directory));
  final WorkerBootstrap bootstrap;
  final void Function(WorkerEvent) send;
  final void Function() finish;
  final Future<CoreStorage> Function(Directory) _openStorage;
  final List<SerialPortDescription> Function() _enumeratePorts;
  final CompanionTransport Function(String) _createCheckTransport;
  final CompanionTransport Function(String) _createDiagnosticTransport;
  _RecordingAttempt? _attempt;
  int _lastAttemptId = 0;
  FiniteDeviceCheck? _check;
  DeviceCheckSnapshot? _checkSnapshot;
  DeviceInformation? _lastDeviceInfo;
  int _lastCheckId = 0;
  bool _permanentStop = false;
  final gate = DeviceGate();
  CoreStorage? _storage;
  DiagnosticHistory? _history;
  RuntimePhase _phase = RuntimePhase.opening;
  OwnerFact _owner = OwnerFact.none;
  RuntimeFault? _error;
  MaintenanceSnapshot? _maintenance;
  MaintenanceActionSnapshot? _maintenanceAction;
  int _lastMaintenanceId = 0, _maintenanceRevision = 1;
  HistoryMaintenanceReport? _seenFailure;
  int _seenFailureCount = 0;
  final _maintenanceWork = <Future<void>>{};
  OperationSnapshot? _operation;
  bool _stop = false, _stopApplied = false, _paused = false, _closing = false;
  bool _releaseReported = false;
  bool _bootstrapSettled = false;
  int _sequence = 0, _lastId = 0;
  DraftDecision? _decision;
  final _createdProfileIds = <int, String>{};
  final _createdDraftIds = <int, String>{};
  String? _decisionCreatedDraftId;
  int _lastDecision = 0;
  bool _decisionSaveUsed = false;
  Future<void>? _opening, _shutdown;
  Future<void> _databaseQueue = Future.value();
  Future<void>? _deviceWork;
  RecordingAdapter? _adapter;
  RuntimeSnapshot get snapshot => RuntimeSnapshot(
    generation: bootstrap.generation,
    sequence: _sequence,
    phase: _phase,
    owner: _owner,
    storage: _storage?.state,
    gate: gate.state,
    stopReceived: _stop,
    stopApplied: _stopApplied,
    admissionPaused: _paused,
    error: _error,
    maintenance: _maintenance,
    maintenanceAction: _maintenanceAction,
    operation: _operation,
    deviceCheck: _checkSnapshot,
    lastDeviceInfo: _lastDeviceInfo,
  );
  void _emit() {
    _sequence++;
    send(SnapshotEvent(bootstrap.generation, snapshot));
  }

  void start() {
    _opening ??= _open();
  }

  Future<void> _checkpoint() => Future<void>.delayed(Duration.zero);
  Future<void> _open() async {
    _emit();
    // A real event-loop turn permits early control messages to be received.
    await _checkpoint();
    if (_stop) {
      _bootstrapSettled = true;
      _stopApplied = true;
      _phase = RuntimePhase.stopping;
      _emit();
      return;
    }
    try {
      _storage = await _openStorage(Directory(bootstrap.directory));
      _owner = OwnerFact.held;
      _history = _storage!.history;
      _captureMaintenance();
      await _checkpoint();
      _stopApplied = _stop;
      _phase = _stop ? RuntimePhase.stopping : RuntimePhase.ready;
    } catch (e) {
      _error = RuntimeFault.from(e);
      _owner = _error!.cleanupUnconfirmed ? OwnerFact.unknown : OwnerFact.none;
      _phase = _error!.core == CoreErrorCode.dataDirectoryBusy
          ? RuntimePhase.busy
          : RuntimePhase.fault;
    }
    _bootstrapSettled = true;
    _emit();
  }

  void _reply(int id, {ReplyValue? value, Object? error}) => send(
    RequestReply(
      bootstrap.generation,
      id,
      value: value,
      error: error == null ? null : RuntimeFault.from(error),
    ),
  );
  bool get _canAdmit =>
      !_paused &&
      !_stop &&
      !_closing &&
      _phase == RuntimePhase.ready &&
      _offlineGateHealthy &&
      _owner == OwnerFact.held &&
      _storage?.state == StorageState.open &&
      gate.state != DeviceGateState.quarantined;

  void receive(Object? message) {
    if (message is ReleaseAcknowledged) {
      if (message.generation == bootstrap.generation && _releaseReported) {
        finish();
      }
      return;
    }
    if (message is! RequestEnvelope) return;
    final id = message.id;
    if (message.generation != bootstrap.generation || id <= _lastId) {
      _reply(
        id,
        error: const RuntimeFault(host: CoordinationFault.staleRequest),
      );
      return;
    }
    _lastId = id;
    final request = message.request;
    switch (request) {
      case QueryHistory():
        _enqueue(
          id,
          () async => HistoryPageValue(
            await _history!.query(
              filter: request.selection.filter,
              size: PageSize(request.selection.size),
              after: request.selection.after,
            ),
          ),
        );
      case ReadHistory():
        _enqueue(
          id,
          () async =>
              HistoryRunValue(await _history!.read(LocalId(request.id))),
        );
      case DeleteHistory():
        _enqueue(id, () async {
          await _history!.delete(LocalId(request.id));
          _captureMaintenance();
          _observeMaintenance();
          _emit();
          return const Accepted();
        });
      case ExportHistoryPage():
        _enqueue(
          id,
          () async => HistoryExportValue(
            await _history!.exportSummary(
              filter: request.selection.filter,
              size: PageSize(request.selection.size),
              after: request.selection.after,
            ),
          ),
        );
      case ReadMaintenanceStatus():
        _enqueue(id, () async {
          _captureMaintenance();
          _emit();
          return MaintenanceValue(_maintenance!, _maintenanceAction);
        });
      case AcknowledgeMaintenance():
        _enqueue(id, () async {
          // No await between current-fact capture, revision check and ack.
          _captureMaintenance();
          if (request.generation != bootstrap.generation ||
              request.revision != _maintenanceRevision ||
              request.count != _seenFailureCount) {
            _emit();
            throw const RuntimeFault(host: CoordinationFault.staleRequest);
          }
          _history!.acknowledgeMaintenanceFailures();
          _captureMaintenance();
          _emit();
          return MaintenanceValue(_maintenance!, _maintenanceAction);
        });
      case StartMaintenance():
        _enqueue(id, () async {
          if (request.id <= _lastMaintenanceId ||
              _maintenanceAction?.done == false) {
            throw const RuntimeFault(host: CoordinationFault.staleRequest);
          }
          _lastMaintenanceId = request.id;
          _maintenanceAction = MaintenanceActionSnapshot(request.id);
          // Install the whole observation before returning the fast ACK. The
          // ordinary DB queue does not wait for the maintenance execution.
          final completion = Completer<void>();
          _trackMaintenance(completion.future);
          unawaited(
            _runMaintenance(request.id).whenComplete(completion.complete),
          );
          _emit();
          return const Accepted();
        });
      case StartRecordedDiagnostic():
        try {
          if (request.id <= _lastAttemptId ||
              request.port.trim().isEmpty ||
              (request.parameters is! PingParameterRequest &&
                  request.parameters is! RespondParameterRequest)) {
            throw const RuntimeFault(host: CoordinationFault.invalidState);
          }
          _beginRecording(
            request.id,
            (storage) => storage.resolveParameters(request.parameters),
            () => _createDiagnosticTransport(request.port),
          );
          _lastAttemptId = request.id;
          _reply(id, value: const Accepted());
        } catch (e) {
          _reply(id, error: e);
        }
      case CancelRecordedDiagnostic():
        final attempt = _attempt;
        if (request.generation != bootstrap.generation ||
            attempt == null ||
            attempt.id != request.id ||
            attempt.lease != gate.generation) {
          // Idempotent completion of the most recently settled attempt.
          if (request.generation == bootstrap.generation &&
              _operation?.attemptId == request.id &&
              _operation?.done == true) {
            _reply(id, value: const Accepted());
          } else {
            _reply(
              id,
              error: const RuntimeFault(host: CoordinationFault.staleRequest),
            );
          }
        } else {
          attempt.canceled = true;
          _adapter?.cancel();
          _operation = _adapter?.snapshot ?? _attemptSnapshot(attempt);
          _emit();
          _reply(id, value: const Accepted());
        }
      case RefreshDevicePorts():
        if (!_canAdmit) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.stopped),
          );
          return;
        }
        int lease;
        try {
          lease = gate.acquire();
        } catch (e) {
          _reply(id, error: e);
          return;
        }
        _emit();
        DevicePortsValue result;
        try {
          result = DevicePortsValue(request.generation, _enumeratePorts());
        } catch (_) {
          result = DevicePortsValue(
            request.generation,
            [],
            failure: const DeviceFailure('enumerationFailed'),
          );
        }
        // Metadata APIs do not open ports. Ordinary metadata errors are not
        // evidence of an unknown device connection or an owner fault.
        gate.settle(lease, released: true);
        _emit();
        _reply(id, value: result);
      case StartDeviceCheck():
        if (!_canAdmit) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.stopped),
          );
          return;
        }
        if (request.id <= _lastCheckId ||
            request.port.trim().isEmpty ||
            !request.options.valid) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.invalidState),
          );
          return;
        }
        int lease;
        try {
          lease = gate.acquire();
        } catch (e) {
          _reply(id, error: e);
          return;
        }
        _lastCheckId = request.id;
        final check = _check = FiniteDeviceCheck(
          request.id,
          request.port,
          request.options,
          createTransport: _createCheckTransport,
          publish: (value) {
            if (gate.generation != lease) return;
            _checkSnapshot = value;
            if (value.info != null) _lastDeviceInfo = value.info;
            _emit();
          },
        );
        _checkSnapshot = check.snapshot;
        // Install the WHOLE barrier before scheduling resource creation.
        final completion = Completer<void>();
        _deviceWork = completion.future;
        _emit();
        unawaited(
          _runCheck(check, lease).then<void>(
            (_) {
              if (gate.generation == lease && identical(_check, check)) {
                _deviceWork = null;
              }
              completion.complete();
            },
            onError: (Object _, StackTrace _) {
              gate.settle(lease, released: false);
              _phase = RuntimePhase.fault;
              _error = const RuntimeFault(
                host: CoordinationFault.observationFailed,
                cleanupUnconfirmed: true,
              );
              _emit();
              completion.complete();
            },
          ),
        );
        _reply(id, value: const Accepted());
      case CancelDeviceCheck():
        if (_check?.id != request.id) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.staleRequest),
          );
        } else {
          _check!.cancel();
          _reply(id, value: const Accepted());
        }

      case BeginDraftDecision():
        if (!_canAdmit || request.decision.generation <= _lastDecision) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.invalidState),
          );
        } else {
          _lastDecision = request.decision.generation;
          _decisionCreatedDraftId =
              _createdDraftIds[request.decision.documentGeneration];
          _decision = request.decision;
          _decisionSaveUsed = false;
          _paused = true;
          _emit();
          _reply(id, value: request.decision);
        }
      case EndDraftDecision():
        if (!_matchesDecision(request.decision) ||
            _stop ||
            _closing ||
            _storage?.state != StorageState.open ||
            !_offlineGateHealthy ||
            _phase == RuntimePhase.fault) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.invalidState),
          );
        } else {
          _decision = null;
          _paused = false;
          _emit();
          _reply(id, value: const Accepted());
        }
      case ListProfiles():
        _enqueue(id, () async {
          if (request.size < 1 || request.size > 50) {
            throw const CoreException(CoreErrorCode.invalidInput);
          }
          final page = await _storage!.profiles.list(
            size: PageSize(request.size),
            after: request.after,
          );
          return ProfilePage(page.items, page.nextCursor);
        });
      case ReadProfile():
        _enqueue(
          id,
          () async =>
              ProfileValue(await _storage!.profiles.read(LocalId(request.id))),
        );
      case WriteProfile():
        final permitted = _permit(
          request.decision,
          EditorTarget.profile,
          request.id,
          session: request.session,
        );
        if (request.decision != null && !permitted) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.staleRequest),
          );
          return;
        }
        if (permitted) _decisionSaveUsed = true;
        _enqueue(id, () async {
          final saved = await _storage!.profiles.save(
            request.content,
            id: request.id == null ? null : LocalId(request.id!),
          );
          if (request.id == null) {
            _createdProfileIds.clear();
            _createdProfileIds[request.session] = saved.id.value;
          }
          return ProfileValue(saved);
        }, decisionSave: permitted);
      case DeleteProfile():
        _enqueue(id, () async {
          await _storage!.profiles.delete(LocalId(request.id));
          return const Accepted();
        });
      case ReadSettings():
        _enqueue(
          id,
          () async => SettingsValue(await _storage!.settings.read()),
        );
      case WriteSettings():
        final permitted = _permit(
          request.decision,
          EditorTarget.settings,
          null,
        );
        if (request.decision != null && !permitted) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.staleRequest),
          );
          return;
        }
        if (permitted) _decisionSaveUsed = true;
        _enqueue(id, () async {
          final saved = await _storage!.settings.save(request.settings);
          _observeMaintenance();
          return SettingsValue(saved);
        }, decisionSave: permitted);
      case RestoreSettings():
        _enqueue(id, () async {
          final saved = await _storage!.settings.restoreDefaults();
          _observeMaintenance();
          return SettingsValue(saved);
        });
      case ResolveParameters():
        _enqueue(
          id,
          () async => ParametersValue(
            await _storage!.resolveParameters(request.request),
          ),
        );
      case ListDrafts():
        _enqueue(id, () => _listDrafts(request.size, request.after));
      case ReadDraft():
        _enqueue(
          id,
          () async => DraftValue(
            DraftSnapshot.from(
              await _storage!.drafts.read(LocalId(request.id)),
            ),
          ),
        );
      case WriteDraft():
        final permitted =
            request.decision != null &&
            _matchesDecision(request.decision!) &&
            request.decision!.target == EditorTarget.draft &&
            request.decision!.documentGeneration == request.session &&
            (request.decision!.targetId == request.id ||
                (request.decision!.targetId == null &&
                    request.id == _decisionCreatedDraftId)) &&
            !_decisionSaveUsed &&
            _paused &&
            !_stop &&
            !_closing &&
            _phase == RuntimePhase.ready &&
            _storage?.state == StorageState.open &&
            _offlineGateHealthy;
        if (request.decision != null && !permitted) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.staleRequest),
          );
          return;
        }
        if (permitted) _decisionSaveUsed = true;
        _enqueue(id, () async {
          if ((request.id == null) != (request.expectedRevision == null)) {
            throw const CoreException(CoreErrorCode.invalidInput);
          }
          final content = DraftContent(
            title: request.title,
            body: request.body,
          );
          final draft = request.id == null
              ? await _storage!.drafts.create(content)
              : await _storage!.drafts.update(
                  LocalId(request.id!),
                  content,
                  expectedRevision: request.expectedRevision!,
                );
          if (request.id == null && request.session != null) {
            _createdDraftIds.clear();
            _createdDraftIds[request.session!] = draft.id.value;
            if (_decision?.target == EditorTarget.draft &&
                _decision?.documentGeneration == request.session &&
                _decision?.targetId == null) {
              _decisionCreatedDraftId = draft.id.value;
            }
          }
          return DraftValue(DraftSnapshot.from(draft));
        }, decisionSave: permitted);
      case DeleteDraft():
        _enqueue(id, () async {
          await _storage!.drafts.delete(
            LocalId(request.id),
            expectedRevision: request.expectedRevision,
          );
          return DeletedDraft(request.id);
        });
      case GetStatus():
        _reply(id, value: StatusValue(snapshot));
      case StopRuntime():
        _stopNow();
        _reply(id, value: const Accepted());
      case CancelOperation():
        if (request.operationGeneration != gate.generation ||
            _deviceWork == null) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.staleRequest),
          );
        } else {
          _stopNow(permanent: false);
          _reply(id, value: const Accepted());
        }
      case PauseAdmission():
        _paused = true;
        _emit();
        _reply(id, value: const Accepted());
      case ResumeAdmission():
        if (_permanentStop ||
            _closing ||
            _decision != null ||
            _phase == RuntimePhase.fault ||
            _storage?.state != StorageState.open ||
            !(_offlineGateHealthy ||
                (gate.state == DeviceGateState.free &&
                    _owner == OwnerFact.held))) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.invalidState),
          );
        } else {
          _paused = false;
          _stop = false;
          _stopApplied = false;
          _phase = RuntimePhase.ready;
          _emit();
          _reply(id, value: const Accepted());
        }
      case ShutdownRuntime():
        _stopNow();
        if (_shutdown != null) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.invalidState),
          );
        } else {
          _shutdown = _close(id);
        }
      case ReadOffline():
        _enqueue(id, () => _read(request));
      case CreateFixtureDraft():
        _enqueue(id, () async {
          if (!bootstrap.fixtureWrites) {
            throw const RuntimeFault(host: CoordinationFault.invalidState);
          }
          final d = await _storage!.drafts.create(
            DraftContent(title: runtimeFixtureTitle, body: runtimeFixtureBody),
          );
          return DraftValue(DraftSnapshot.from(d));
        });
    }
  }

  void _stopNow({bool permanent = true}) {
    if (permanent) _permanentStop = true;
    _stop = true;
    _paused = true;
    if (!_closing) _phase = RuntimePhase.stopping;
    _attempt?.canceled = true;
    _adapter?.cancel();
    _check?.cancel();
    // Receipt is distinct from application at the next awaited checkpoint.
    _stopApplied =
        _adapter != null || (_bootstrapSettled && _deviceWork == null);
    _emit();
  }

  bool get _offlineGateHealthy {
    if (_phase != RuntimePhase.ready ||
        _owner != OwnerFact.held ||
        _storage?.state != StorageState.open ||
        _stop ||
        _closing) {
      return false;
    }
    if (gate.state == DeviceGateState.free) return true;
    if (gate.state != DeviceGateState.occupied || _deviceWork == null) {
      return false;
    }
    final attempt = _attempt;
    if (attempt != null && attempt.lease == gate.generation) {
      return _operation?.attemptId == attempt.id &&
          !(_operation?.resourceUncertainty ?? false);
    }
    return _check != null &&
        _checkSnapshot?.settled == false &&
        _checkSnapshot?.observerFailure == null &&
        _checkSnapshot?.sessionCleanup != DeviceCleanup.failed;
  }

  Future<void> _runCheck(FiniteDeviceCheck check, int lease) async {
    await check.run();
    gate.settle(lease, released: check.snapshot.released);
    if (!check.snapshot.released) {
      _phase = RuntimePhase.fault;
      _error = const RuntimeFault(
        host: CoordinationFault.releaseUnconfirmed,
        cleanupUnconfirmed: true,
      );
    }
    if (_stop) _stopApplied = true;
    _emit();
  }

  bool _matchesDecision(DraftDecision value) =>
      _decision?.generation == value.generation &&
      _decision?.documentGeneration == value.documentGeneration &&
      _decision?.target == value.target &&
      _decision?.targetId == value.targetId;

  bool _permit(
    DraftDecision? value,
    EditorTarget target,
    String? id, {
    int? session,
  }) =>
      value != null &&
      _matchesDecision(value) &&
      value.target == target &&
      (session == null || value.documentGeneration == session) &&
      (value.targetId == id &&
              !(target == EditorTarget.profile &&
                  id == null &&
                  _createdProfileIds.containsKey(value.documentGeneration)) ||
          (target == EditorTarget.profile &&
              value.targetId == null &&
              id != null &&
              _createdProfileIds[value.documentGeneration] == id)) &&
      !_decisionSaveUsed &&
      _paused &&
      !_stop &&
      !_closing &&
      _phase == RuntimePhase.ready &&
      _storage?.state == StorageState.open &&
      _offlineGateHealthy;

  void _observeMaintenance() {
    _trackMaintenance(
      _history!.waitForMaintenance().then(
        (_) {
          _captureMaintenance();
          _emit();
        },
        onError: (Object _, StackTrace s) {
          _captureMaintenance();
          _emit();
        },
      ),
    );
  }

  void _trackMaintenance(Future<void> work) {
    _maintenanceWork.add(work);
    unawaited(work.then<void>((_) => _maintenanceWork.remove(work)));
  }

  Future<void> _runMaintenance(int id) async {
    try {
      final report = await _history!.maintain();
      _maintenanceAction = MaintenanceActionSnapshot(
        id,
        done: true,
        report: MaintenanceReportSnapshot(report),
      );
    } catch (e) {
      _maintenanceAction = MaintenanceActionSnapshot(
        id,
        done: true,
        error: RuntimeFault.from(e),
      );
    }
    _captureMaintenance();
    _emit();
  }

  void _enqueue(
    int id,
    Future<ReplyValue> Function() action, {
    bool decisionSave = false,
  }) {
    if (!_canAdmit && !decisionSave) {
      _reply(id, error: const RuntimeFault(host: CoordinationFault.stopped));
      return;
    }
    // Admission happens now. Already accepted work drains even after stop.
    _databaseQueue = _databaseQueue.then((_) async {
      try {
        _reply(id, value: await action());
      } catch (e) {
        _error = RuntimeFault.from(e);
        _emit();
        _reply(id, error: e);
      }
    });
  }

  Future<DraftPage> _listDrafts(int size, DraftCursor? after) async {
    if (size < 1 || size > 50) {
      throw const CoreException(CoreErrorCode.invalidInput);
    }
    final page = await _storage!.drafts.list(
      size: PageSize(size),
      after: after == null
          ? null
          : UpdatedCursor(updatedAt: after.updatedAt, id: LocalId(after.id)),
    );
    return DraftPage(
      page.items.map(DraftSnapshot.from),
      page.nextCursor == null
          ? null
          : DraftCursor(page.nextCursor!.updatedAt, page.nextCursor!.id.value),
    );
  }

  Future<OfflineSnapshot> _read(ReadOffline request) async {
    if (request.pageSize < 1 || request.pageSize > 50) {
      throw const CoreException(CoreErrorCode.invalidInput);
    }
    final settings = await _storage!.settings.read();
    final page = await _storage!.drafts.list(
      size: PageSize(request.pageSize),
      after: request.after == null
          ? null
          : UpdatedCursor(
              updatedAt: request.after!.updatedAt,
              id: LocalId(request.after!.id),
            ),
    );
    _captureMaintenance();
    _emit();
    return OfflineSnapshot(
      settings.defaultProfileId?.value,
      settings.diagnosticHistoryLimit,
      page.items.map(DraftSnapshot.from),
      page.nextCursor == null
          ? null
          : DraftCursor(page.nextCursor!.updatedAt, page.nextCursor!.id.value),
    );
  }

  /// Internal fixture seam shares the exact admission and settlement path.
  Future<void> startRecording({
    required Future<EffectiveParameters> Function(CoreStorage) resolve,
    required CompanionTransport Function() createTransport,
  }) => _beginRecording(++_lastAttemptId, resolve, createTransport);

  OperationSnapshot _attemptSnapshot(
    _RecordingAttempt attempt, {
    bool done = false,
    RuntimeFault? error,
  }) => OperationSnapshot(
    generation: attempt.lease,
    attemptId: attempt.id,
    preparation: done
        ? DiagnosticPreparation.settled
        : DiagnosticPreparation.resolving,
    cancelRequested: attempt.canceled,
    error: error,
    noResourcesAcquired: done && !(error?.cleanupUnconfirmed ?? false),
    done: done,
  );

  Future<void> _beginRecording(
    int id,
    Future<EffectiveParameters> Function(CoreStorage) resolve,
    CompanionTransport Function() createTransport,
  ) {
    if (!_canAdmit) throw const RuntimeFault(host: CoordinationFault.stopped);
    final lease = gate.acquire();
    final attempt = _attempt = _RecordingAttempt(id, lease);
    _adapter = null;
    final completion = Completer<void>();
    _deviceWork = completion.future;
    _operation = _attemptSnapshot(attempt);
    _emit();
    unawaited(
      _record(attempt, resolve, createTransport).then<void>(
        (_) {
          if (identical(_attempt, attempt)) {
            _attempt = null;
            _adapter = null;
            _deviceWork = null;
          }
          completion.complete();
        },
        onError: (Object _, StackTrace _) {
          gate.settle(lease, released: false);
          _phase = RuntimePhase.fault;
          _error = const RuntimeFault(
            host: CoordinationFault.observationFailed,
            cleanupUnconfirmed: true,
          );
          _emit();
          completion.complete();
        },
      ),
    );
    return completion.future;
  }

  Future<void> _record(
    _RecordingAttempt attempt,
    Future<EffectiveParameters> Function(CoreStorage) resolve,
    CompanionTransport Function() createTransport,
  ) async {
    bool obtainedOperation = false;
    try {
      // Only resolution joins the DB queue. Previously accepted CRUD retains
      // order; the hardware lifecycle never blocks database control requests.
      final resolved = Completer<EffectiveParameters?>();
      _databaseQueue = _databaseQueue.then((_) async {
        try {
          await _checkpoint();
          if (attempt.canceled || _stop) {
            resolved.complete(null);
            return;
          }
          resolved.complete(await resolve(_storage!));
        } catch (e, stack) {
          resolved.completeError(e, stack);
        }
      });
      final parameters = await resolved.future;
      if (parameters == null || attempt.canceled || _stop) return;
      final operation = _storage!.record(
        parameters: parameters,
        appVersion: appVersion,
        createTransport: createTransport,
      );
      obtainedOperation = true;
      final adapter = _adapter = RecordingAdapter(
        operation,
        attempt.lease,
        (value) {
          if (!identical(_attempt, attempt) ||
              attempt.lease != gate.generation) {
            return;
          }
          _operation = value;
          if (value.observationFailure) {
            _phase = RuntimePhase.fault;
            _error = const RuntimeFault(
              host: CoordinationFault.observationFailed,
              cleanupUnconfirmed: true,
            );
          }
          _emit();
        },
        attemptId: attempt.id,
        isCancelRequested: () => attempt.canceled,
      );
      _operation = adapter.snapshot;
      _emit();
      if (attempt.canceled || _stop) adapter.cancel();
      final result = await adapter.settled;
      gate.settle(attempt.lease, released: result.resourcesReleased);
      if (!result.resourcesReleased) {
        _error = const RuntimeFault(
          host: CoordinationFault.releaseUnconfirmed,
          cleanupUnconfirmed: true,
        );
        _phase = RuntimePhase.fault;
      }
    } catch (e) {
      _error = RuntimeFault.from(e);
      if (!obtainedOperation) {
        _operation = _attemptSnapshot(attempt, done: true, error: _error);
      }
      gate.settle(
        attempt.lease,
        released: !obtainedOperation && !_error!.cleanupUnconfirmed,
      );
      if (gate.state == DeviceGateState.quarantined) {
        _phase = RuntimePhase.fault;
      }
    } finally {
      if (!obtainedOperation &&
          gate.state == DeviceGateState.occupied &&
          identical(_attempt, attempt)) {
        _operation = _attemptSnapshot(attempt, done: true);
        gate.settle(attempt.lease, released: true);
      }
      if (_stop) _stopApplied = true;
      _captureMaintenance();
      _observeMaintenance();
      _emit();
    }
  }

  void _captureMaintenance() {
    final h = _history;
    if (h == null) return;
    final failure = h.unacknowledgedFailure;
    final count = h.unacknowledgedFailureCount;
    if (!identical(failure, _seenFailure) || count != _seenFailureCount) {
      _maintenanceRevision++;
      _seenFailure = failure;
      _seenFailureCount = count;
    }
    _maintenance = MaintenanceSnapshot(
      h.latestMaintenance?.state,
      h.unacknowledgedFailure?.error?.code,
      h.unacknowledgedFailureCount,
      revision: _maintenanceRevision,
      latestReport: h.latestMaintenance == null
          ? null
          : MaintenanceReportSnapshot(h.latestMaintenance!),
      unacknowledgedReport: h.unacknowledgedFailure == null
          ? null
          : MaintenanceReportSnapshot(h.unacknowledgedFailure!),
    );
  }

  Future<void> _close(int id) async {
    _closing = true;
    await _opening;
    _stopApplied = true;
    await _databaseQueue;
    await _deviceWork;
    while (_maintenanceWork.isNotEmpty) {
      await Future.wait(_maintenanceWork.toList());
    }
    if (gate.state != DeviceGateState.free || _owner == OwnerFact.unknown) {
      _phase = RuntimePhase.fault;
      _error ??= const RuntimeFault(
        host: CoordinationFault.releaseUnconfirmed,
        cleanupUnconfirmed: true,
      );
      _emit();
      send(ReleaseReport(bootstrap.generation, id, snapshot, false));
      return; // Preserve owner and control port in quarantine.
    }
    _phase = RuntimePhase.closing;
    _emit();
    final storage = _storage;
    if (storage != null) {
      try {
        await _history!.waitForMaintenance();
      } catch (e) {
        _error = RuntimeFault.from(e);
      }
      try {
        await storage.close();
        if (storage.state != StorageState.closed) {
          throw const RuntimeFault(
            host: CoordinationFault.releaseUnconfirmed,
            cleanupUnconfirmed: true,
          );
        }
        _owner = OwnerFact.released;
      } catch (e) {
        _error = RuntimeFault.from(e);
        _owner = OwnerFact.unknown;
      }
      // These getters are retained in-memory reports, never repository queries.
      _captureMaintenance();
    }
    final released = _owner == OwnerFact.released || _owner == OwnerFact.none;
    _phase = released ? RuntimePhase.closed : RuntimePhase.fault;
    _emit();
    _releaseReported = released;
    send(ReleaseReport(bootstrap.generation, id, snapshot, released));
    // Only an explicit main acknowledgement closes the receive port. onExit on
    // another port can therefore never outrun the trusted release report.
  }
}

final class _RecordingAttempt {
  _RecordingAttempt(this.id, this.lease);
  final int id, lease;
  bool canceled = false;
}
