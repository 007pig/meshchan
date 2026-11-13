import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

import 'protocol.dart';
import 'recording_adapter.dart';

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
  }) : _openStorage =
           openStorage ??
           ((directory) => CoreStorage.open(dataDirectory: directory));
  final WorkerBootstrap bootstrap;
  final void Function(WorkerEvent) send;
  final void Function() finish;
  final Future<CoreStorage> Function(Directory) _openStorage;
  final gate = DeviceGate();
  CoreStorage? _storage;
  DiagnosticHistory? _history;
  RuntimePhase _phase = RuntimePhase.opening;
  OwnerFact _owner = OwnerFact.none;
  RuntimeFault? _error;
  MaintenanceSnapshot? _maintenance;
  OperationSnapshot? _operation;
  bool _stop = false, _stopApplied = false, _paused = false, _closing = false;
  bool _releaseReported = false;
  bool _bootstrapSettled = false;
  int _sequence = 0, _lastId = 0;
  DraftDecision? _decision;
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
    operation: _operation,
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
      case BeginDraftDecision():
        if (!_canAdmit || request.decision.generation <= _lastDecision) {
          _reply(
            id,
            error: const RuntimeFault(host: CoordinationFault.invalidState),
          );
        } else {
          _lastDecision = request.decision.generation;
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
            gate.state != DeviceGateState.free ||
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
            !_decisionSaveUsed &&
            _paused &&
            !_stop &&
            !_closing &&
            _phase == RuntimePhase.ready &&
            _storage?.state == StorageState.open &&
            gate.state == DeviceGateState.free;
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
          _stopNow();
          _reply(id, value: const Accepted());
        }
      case PauseAdmission():
        _paused = true;
        _emit();
        _reply(id, value: const Accepted());
      case ResumeAdmission():
        if (_closing ||
            _decision != null ||
            _phase == RuntimePhase.fault ||
            _storage?.state != StorageState.open ||
            gate.state != DeviceGateState.free) {
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

  void _stopNow() {
    _stop = true;
    _paused = true;
    if (!_closing) _phase = RuntimePhase.stopping;
    _adapter?.cancel();
    // Receipt is distinct from application at the next awaited checkpoint.
    _stopApplied =
        _adapter != null || (_bootstrapSettled && _deviceWork == null);
    _emit();
  }

  bool _matchesDecision(DraftDecision value) =>
      _decision?.generation == value.generation &&
      _decision?.documentGeneration == value.documentGeneration;

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

  /// Future product requests must call this boundary. Test-side worker entries
  /// exercise it with real core/fake transport, without a production start API.
  Future<void> startRecording({
    required Future<EffectiveParameters> Function(CoreStorage) resolve,
    required CompanionTransport Function() createTransport,
  }) {
    if (!_canAdmit) throw const RuntimeFault(host: CoordinationFault.stopped);
    final lease = gate.acquire(); // Before the first await, including resolve.
    _emit();
    final work = _record(lease, resolve, createTransport);
    _deviceWork = work;
    return work;
  }

  Future<void> _record(
    int lease,
    Future<EffectiveParameters> Function(CoreStorage) resolve,
    CompanionTransport Function() createTransport,
  ) async {
    bool constructed = false;
    try {
      await _checkpoint();
      if (_stop) return;
      final parameters = await resolve(_storage!);
      await _checkpoint();
      if (_stop) return;
      final operation = _storage!.record(
        parameters: parameters,
        appVersion: '0.1.0-dev.3',
        createTransport: () {
          // record's own cancel gate handles stops observed before prepared.
          constructed = true;
          return createTransport();
        },
      );
      final adapter = RecordingAdapter(operation, lease, (value) {
        if (value.generation != gate.generation) return;
        _operation = value;
        _emit();
      });
      _adapter = adapter;
      if (_stop) adapter.cancel();
      final result = await adapter.settled;
      gate.settle(lease, released: result.resourcesReleased);
      if (!result.resourcesReleased) {
        _error = const RuntimeFault(
          host: CoordinationFault.releaseUnconfirmed,
          cleanupUnconfirmed: true,
        );
        _phase = RuntimePhase.fault;
      }
    } catch (e) {
      _error = RuntimeFault.from(e);
      gate.settle(lease, released: !constructed && !_error!.cleanupUnconfirmed);
      if (gate.state == DeviceGateState.quarantined) {
        _phase = RuntimePhase.fault;
      }
    } finally {
      // Only a path which did not construct resources can release without a
      // recorded cleanup result. A settled ambiguous adapter remains occupied.
      if (gate.state == DeviceGateState.occupied && _adapter == null) {
        gate.settle(lease, released: !constructed);
      }
      if (_stop) _stopApplied = true;
      _adapter = null;
      _deviceWork = null;
      _captureMaintenance();
      _emit();
    }
  }

  void _captureMaintenance() {
    final h = _history;
    if (h == null) return;
    _maintenance = MaintenanceSnapshot(
      h.latestMaintenance?.state,
      h.unacknowledgedFailure?.error?.code,
      h.unacknowledgedFailureCount,
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
