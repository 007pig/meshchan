import 'package:meshchan_core/meshchan_core.dart';

import 'dart:async';
import 'dart:isolate';

import 'protocol.dart';
import 'worker.dart';

final class ShutdownOutcome {
  const ShutdownOutcome(
    this.resourcesReleased,
    this.workerExited, {
    this.workerWasSpawned = true,
  });
  final bool resourcesReleased, workerExited, workerWasSpawned;
  bool get canExit => resourcesReleased && (!workerWasSpawned || workerExited);
}

/// Application owner, independent of Widget lifetime. It never holds core or
/// native resources. Deadlines conclude uncertainty; they never kill/reopen.
abstract interface class AppRuntime {
  RuntimeSnapshot get snapshot;
  Stream<RuntimeSnapshot> get changes;
  Stream<OfflineSnapshot> get offlineChanges;
  OfflineSnapshot? get offline;
  Future<void> start();
  Future<DevicePortsValue> refreshDevicePorts(int generation);
  DeviceCheckHandle startDeviceCheck(String port, DeviceCheckOptions options);
  Future<void> cancelDeviceCheck(int id);
  Future<OfflineSnapshot> refresh({int pageSize = 20, DraftCursor? after});
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after});
  Future<DraftSnapshot> readDraft(String id);
  Future<DraftSnapshot> saveDraft({
    required String title,
    required String body,
    String? id,
    int? expectedRevision,
    int? session,
    DraftDecision? decision,
  });
  Future<String> deleteDraft(String id, {required int expectedRevision});
  Future<DraftDecision> beginDraftDecision(
    int documentGeneration, {
    EditorTarget target = EditorTarget.draft,
    String? targetId,
  });
  Future<ProfilePage> listProfiles({int size = 20, UpdatedCursor? after});
  Future<ConnectionProfile> readProfile(String id);
  Future<ConnectionProfile> saveProfile(
    ProfileContent content, {
    String? id,
    required int session,
    DraftDecision? decision,
  });
  Future<void> deleteProfile(String id);
  Future<AppSettings> readSettings();
  Future<AppSettings> saveSettings(
    AppSettings settings, {
    DraftDecision? decision,
  });
  Future<AppSettings> restoreSettings();
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest request,
  );
  Future<void> endDraftDecision(DraftDecision decision);
  Future<ShutdownOutcome> shutdown();
}

final class RuntimeController implements AppRuntime {
  RuntimeController({
    required this.resolveDirectory,
    this.prepareForResources,
    this.fixtureWrites = false,
    this.entry = runtimeWorkerEntry,
    this.deadline = const Duration(seconds: 30),
  }) : generation = ++_nextGeneration;
  static int _nextGeneration = 0;
  final int generation;
  final Future<String> Function() resolveDirectory;
  final Future<void> Function()? prepareForResources;
  final bool fixtureWrites;
  final void Function(WorkerBootstrap) entry;
  final Duration deadline;
  final _changes = StreamController<RuntimeSnapshot>.broadcast(sync: true);
  final _offlineChanges = StreamController<OfflineSnapshot>.broadcast(
    sync: true,
  );
  final _pending = <int, _Pending>{};
  final _queued = <RequestEnvelope>[];
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _ports = <ReceivePort>[];
  final _boot = Completer<void>();
  final _exit = Completer<void>();
  Completer<bool>? _shutdownRelease;
  Future<void>? _starting;
  Future<ShutdownOutcome>? _shutdown;
  Future<void>? _disposing;
  bool _shutdownSettled = false, _shutdownVerified = false;
  SendPort? _commands;
  late RuntimeSnapshot _snapshot = RuntimeSnapshot(generation: generation);
  @override
  RuntimeSnapshot get snapshot => _snapshot;
  @override
  Stream<RuntimeSnapshot> get changes => _changes.stream;
  @override
  Stream<OfflineSnapshot> get offlineChanges => _offlineChanges.stream;
  @override
  OfflineSnapshot? offline;
  bool _stopIntent = false,
      _terminalFault = false,
      _released = false,
      _workerExited = false,
      _disposed = false,
      _spawnPending = false;
  bool _workerSpawned = false;
  bool get _workerMayOwnResources => _spawnPending || _workerSpawned;
  int _nextId = 0, _offlineVersion = 0;
  int _nextCheck = 0;
  bool _checkStarting = false;
  int _decisionGeneration = 0;
  DraftDecision? _decision;
  bool _hostSaveUsed = false, _hostPaused = false;
  String? _decisionCreatedProfileId, _decisionCreatedDraftId;
  int? _shutdownId;
  bool _shutdownSent = false;
  int get pendingCount => _pending.length;
  int get openPortCount => _ports.length;
  bool get stopIntent => _stopIntent;
  void reportHostFailure() => _fail(CoordinationFault.observationFailed);
  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    // Listeners exist before directory resolution/spawn, including fast errors.
    final events = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    _ports.addAll([events, errors, exits]);
    _subscriptions.addAll([
      events.listen(_event),
      errors.listen((_) => _fail(CoordinationFault.workerFailed)),
      exits.listen((_) {
        _workerExited = true;
        if (!_exit.isCompleted) _exit.complete();
        if (!_released) {
          _fail(CoordinationFault.workerExited);
        }
        // A prior timeout may already have made _fail a no-op. onExit is still
        // a new worker fact, independently of whether release is known yet.
        if (!_snapshot.workerExited) {
          _project(_snapshot, exited: true);
        }
        _completeShutdownObservation();
        _reconcileShutdown();
      }),
    ]);
    Timer? startupTimer;
    try {
      startupTimer = Timer(
        deadline,
        () => _fail(CoordinationFault.requestUnknown),
      );
      await prepareForResources?.call().timeout(deadline);
      final directory = !_stopIntent && !_terminalFault
          ? await resolveDirectory().timeout(deadline)
          : null;
      // Exit during directory resolution needs no worker or storage at all.
      if (_stopIntent) {
        _released = true;
        _workerExited = false; // No worker existed; this is not an onExit fact.
        if (!_exit.isCompleted) _exit.complete();
        _snapshot = RuntimeSnapshot(
          generation: generation,
          phase: RuntimePhase.closed,
          owner: OwnerFact.none,
          stopReceived: true,
          stopApplied: true,
          workerExited: false,
          admissionPaused: true,
        );
        _changes.add(_snapshot);
        _boot.complete();
      } else if (!_terminalFault) {
        _spawnPending = true;
        try {
          await Isolate.spawn(
            entry,
            WorkerBootstrap(
              generation,
              directory!,
              events.sendPort,
              fixtureWrites: fixtureWrites,
            ),
            onError: errors.sendPort,
            onExit: exits.sendPort,
            errorsAreFatal: true,
            debugName: 'meshchan-runtime-$generation',
          );
          _workerSpawned = true;
        } catch (_) {
          // Rejected creation cannot have opened storage. This is distinct from
          // onError/onExit after successful creation, which proves no release.
          _spawnPending = false;
          _fail(CoordinationFault.spawnFailed, creationRejected: true);
          await _disposePorts();
          return;
        } finally {
          _spawnPending = false;
        }
      }
      await _boot.future;
    } catch (_) {
      _fail(CoordinationFault.spawnFailed);
    } finally {
      startupTimer?.cancel();
    }
  }

  void _event(Object? event) {
    if (event is! WorkerEvent || event.generation != generation || _disposed) {
      return;
    }
    switch (event) {
      case WorkerHello():
        if (_commands != null) {
          _fail(CoordinationFault.workerFailed);
          return;
        }
        _commands = event.commands;
        // These envelopes keep original order and ID. Stop intent never needs
        // the UI or directory resolver to rediscover it after the handshake.
        for (final request in _queued) {
          _commands!.send(request);
        }
        _queued.clear();
        _sendShutdownIfPossible();
      case SnapshotEvent():
        _project(event.snapshot, retainFault: _terminalFault);
        if (event.snapshot.phase != RuntimePhase.opening &&
            !_boot.isCompleted) {
          _boot.complete();
        }
      case RequestReply():
        final pending = _pending.remove(event.id);
        if (pending == null) {
          return; // Duplicate/late reply cannot complete twice.
        }
        pending.timer.cancel();
        if (event.error != null) {
          pending.completer.completeError(event.error!);
        } else if (event.value != null) {
          pending.completer.complete(event.value!);
        } else {
          pending.completer.completeError(
            const RuntimeFault(host: CoordinationFault.requestUnknown),
          );
        }
      case ReleaseReport():
        if (event.requestId != _shutdownId || _released) return;
        // A release is an authoritative resource fact even after a lost reply.
        // It does not retroactively turn unknown requests into committed saves.
        _released = event.resourcesReleased;
        if (event.resourcesReleased) {
          _project(event.snapshot, force: true, exited: _workerExited);
          _commands?.send(ReleaseAcknowledged(generation));
        } else if (!_terminalFault) {
          _project(event.snapshot);
        }
        _completeShutdownObservation();
        _reconcileShutdown();
    }
  }

  void _project(
    RuntimeSnapshot value, {
    bool force = false,
    bool? exited,
    bool retainFault = false,
  }) {
    if (!force && value.sequence < _snapshot.sequence) return;
    _snapshot = RuntimeSnapshot(
      generation: generation,
      sequence: value.sequence,
      phase: retainFault ? RuntimePhase.fault : value.phase,
      owner: retainFault ? _snapshot.owner : value.owner,
      storage: value.storage,
      gate: value.gate,
      stopReceived: value.stopReceived,
      stopApplied: value.stopApplied,
      admissionPaused: retainFault || value.admissionPaused,
      workerExited: exited ?? _workerExited,
      error: _terminalFault ? _snapshot.error : value.error,
      maintenance: value.maintenance,
      operation: value.operation,
      deviceCheck: value.deviceCheck,
      lastDeviceInfo: value.lastDeviceInfo,
    );
    _changes.add(_snapshot);
  }

  void _fail(CoordinationFault fault, {bool creationRejected = false}) {
    if (_disposed || (_terminalFault && !creationRejected)) return;
    assert(!creationRejected || !_workerMayOwnResources);
    _terminalFault = true;
    if (!_workerMayOwnResources) {
      _released = true;
      if (!_exit.isCompleted) _exit.complete();
    }
    final error = RuntimeFault(
      host: fault,
      cleanupUnconfirmed: _workerMayOwnResources && !_released,
    );
    _snapshot = RuntimeSnapshot(
      generation: generation,
      sequence: _snapshot.sequence,
      phase: RuntimePhase.fault,
      owner: !_workerMayOwnResources
          ? OwnerFact.none
          : _released
          ? _snapshot.owner
          : OwnerFact.unknown,
      storage: _snapshot.storage,
      gate: _snapshot.gate,
      stopReceived: _snapshot.stopReceived,
      stopApplied: _snapshot.stopApplied,
      admissionPaused: true,
      workerExited: _workerExited,
      error: error,
      maintenance: _snapshot.maintenance,
      operation: _snapshot.operation,
      deviceCheck: _snapshot.deviceCheck,
      lastDeviceInfo: _snapshot.lastDeviceInfo,
    );
    _changes.add(_snapshot);
    for (final pending in _pending.values) {
      pending.timer.cancel();
      pending.completer.completeError(error);
    }
    _pending.clear();
    _queued.clear();
    if (!_boot.isCompleted) _boot.complete();
    _completeShutdownObservation();
    _reconcileShutdown();
  }

  Future<ReplyValue> request(RuntimeRequest request) {
    if (_disposed || _terminalFault || _workerExited) {
      return Future.error(
        _snapshot.error ??
            const RuntimeFault(host: CoordinationFault.invalidState),
      );
    }
    if (request is StopRuntime || request is ShutdownRuntime) {
      _stopIntent = true;
    }
    if (request is ResumeAdmission && _stopIntent) {
      return Future.error(const RuntimeFault(host: CoordinationFault.stopped));
    }
    if ((request is RefreshDevicePorts || request is StartDeviceCheck) &&
        (_snapshot.gate != DeviceGateState.free || _checkStarting)) {
      return Future.error(
        const RuntimeFault(host: CoordinationFault.deviceBusy),
      );
    }
    final ordinary =
        request is RefreshDevicePorts ||
        request is StartDeviceCheck ||
        request is ReadOffline ||
        request is ListDrafts ||
        request is ReadDraft ||
        request is DeleteDraft ||
        request is CreateFixtureDraft ||
        request is ListProfiles ||
        request is ReadProfile ||
        request is DeleteProfile ||
        request is ReadSettings ||
        request is RestoreSettings ||
        request is ResolveParameters ||
        (request is WriteDraft && request.decision == null) ||
        (request is WriteProfile && request.decision == null) ||
        (request is WriteSettings && request.decision == null);
    if (ordinary && (_stopIntent || _hostPaused || _snapshot.admissionPaused)) {
      return Future.error(const RuntimeFault(host: CoordinationFault.stopped));
    }
    if (_decision != null &&
        (request is ListProfiles ||
            request is ReadProfile ||
            request is DeleteProfile ||
            request is ReadSettings ||
            request is RestoreSettings ||
            request is ResolveParameters ||
            (request is WriteProfile && request.decision != _decision) ||
            (request is WriteSettings && request.decision != _decision) ||
            request is ReadOffline ||
            request is ListDrafts ||
            request is ReadDraft ||
            request is DeleteDraft ||
            request is CreateFixtureDraft ||
            (request is WriteDraft && request.decision != _decision))) {
      return Future.error(const RuntimeFault(host: CoordinationFault.stopped));
    }
    final permit = switch (request) {
      WriteProfile() => request.decision,
      WriteSettings() => request.decision,
      WriteDraft() => request.decision,
      _ => null,
    };
    if (permit != null &&
        (permit != _decision ||
            _hostSaveUsed ||
            _stopIntent ||
            (request is WriteProfile &&
                (permit.target != EditorTarget.profile ||
                    permit.documentGeneration != request.session ||
                    (request.id == null && _decisionCreatedProfileId != null) ||
                    (permit.targetId != request.id &&
                        !(permit.targetId == null &&
                            request.id == _decisionCreatedProfileId)))) ||
            (request is WriteSettings &&
                permit.target != EditorTarget.settings) ||
            (request is WriteDraft &&
                (permit.target != EditorTarget.draft ||
                    permit.documentGeneration != request.session ||
                    (permit.targetId != request.id &&
                        !(permit.targetId == null &&
                            request.id == _decisionCreatedDraftId)))))) {
      return Future.error(
        const RuntimeFault(host: CoordinationFault.staleRequest),
      );
    }
    if (permit != null) _hostSaveUsed = true;
    final id = ++_nextId;
    final completion = Completer<ReplyValue>();
    final timer = Timer(
      deadline,
      () => _fail(CoordinationFault.requestUnknown),
    );
    _pending[id] = _Pending(completion, timer);
    final message = RequestEnvelope(generation, id, request);
    if (_commands case final commands?) {
      commands.send(message);
    } else {
      _queued.add(message);
    }
    return completion.future;
  }

  @override
  Future<DevicePortsValue> refreshDevicePorts(int generation) async =>
      await request(RefreshDevicePorts(generation)) as DevicePortsValue;

  @override
  DeviceCheckHandle startDeviceCheck(String port, DeviceCheckOptions options) {
    final id = ++_nextCheck;
    if (_checkStarting) {
      final rejected = Future<void>.error(
        const RuntimeFault(host: CoordinationFault.deviceBusy),
      );
      unawaited(
        rejected.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return DeviceCheckHandle(id, rejected);
    }
    final reply = request(StartDeviceCheck(id, port, options));
    _checkStarting = true;
    final accepted = reply
        .then<void>((_) {})
        .whenComplete(() => _checkStarting = false);
    // Observe immediately even if the caller attaches after requesting cancel.
    unawaited(
      accepted.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return DeviceCheckHandle(id, accepted);
  }

  @override
  Future<void> cancelDeviceCheck(int id) async {
    await request(CancelDeviceCheck(id));
  }

  @override
  Future<OfflineSnapshot> refresh({
    int pageSize = 20,
    DraftCursor? after,
  }) async {
    final version = ++_offlineVersion;
    final result = await request(
      ReadOffline(pageSize: pageSize, after: after),
    ) as OfflineSnapshot;
    if (version == _offlineVersion && !_disposed && !_terminalFault) {
      offline = result;
      _offlineChanges.add(result);
    }
    return result;
  }

  @override
  Future<ProfilePage> listProfiles({
    int size = 20,
    UpdatedCursor? after,
  }) async =>
      await request(ListProfiles(size: size, after: after)) as ProfilePage;
  @override
  Future<ConnectionProfile> readProfile(String id) async =>
      (await request(ReadProfile(id)) as ProfileValue).profile;
  @override
  Future<ConnectionProfile> saveProfile(
    ProfileContent content, {
    String? id,
    required int session,
    DraftDecision? decision,
  }) async {
    final saved = (await request(
      WriteProfile(content, id: id, session: session, decision: decision),
    ) as ProfileValue).profile;
    if (id == null &&
        _decision?.target == EditorTarget.profile &&
        _decision?.documentGeneration == session &&
        _decision?.targetId == null) {
      _decisionCreatedProfileId = saved.id.value;
    }
    return saved;
  }

  @override
  Future<void> deleteProfile(String id) async {
    await request(DeleteProfile(id));
  }

  @override
  Future<AppSettings> readSettings() async =>
      (await request(const ReadSettings()) as SettingsValue).settings;
  @override
  Future<AppSettings> saveSettings(
    AppSettings settings, {
    DraftDecision? decision,
  }) async => (await request(
    WriteSettings(settings, decision: decision),
  ) as SettingsValue).settings;
  @override
  Future<AppSettings> restoreSettings() async =>
      (await request(const RestoreSettings()) as SettingsValue).settings;
  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest value,
  ) async =>
      (await request(ResolveParameters(value)) as ParametersValue).parameters;

  Future<void> stop() async {
    _stopIntent = true;
    if (_workerExited || _terminalFault) return;
    await request(const StopRuntime());
  }

  @override
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after}) async =>
      await request(ListDrafts(size: size, after: after)) as DraftPage;
  @override
  Future<DraftSnapshot> readDraft(String id) async =>
      (await request(ReadDraft(id)) as DraftValue).draft;
  @override
  Future<DraftSnapshot> saveDraft({
    required String title,
    required String body,
    String? id,
    int? expectedRevision,
    int? session,
    DraftDecision? decision,
  }) async {
    final saved = (await request(
      WriteDraft(
        title: title,
        body: body,
        id: id,
        expectedRevision: expectedRevision,
        session: session,
        decision: decision,
      ),
    ) as DraftValue).draft;
    if (id == null &&
        _decision?.target == EditorTarget.draft &&
        _decision?.documentGeneration == session &&
        _decision?.targetId == null) {
      _decisionCreatedDraftId = saved.id;
    }
    return saved;
  }

  @override
  Future<String> deleteDraft(
    String id, {
    required int expectedRevision,
  }) async =>
      (await request(DeleteDraft(id, expectedRevision)) as DeletedDraft).id;
  @override
  Future<DraftDecision> beginDraftDecision(
    int documentGeneration, {
    EditorTarget target = EditorTarget.draft,
    String? targetId,
  }) async {
    if (_decision != null) {
      throw const RuntimeFault(host: CoordinationFault.invalidState);
    }
    final decision = DraftDecision(
      ++_decisionGeneration,
      documentGeneration,
      target: target,
      targetId: targetId,
    );
    _hostSaveUsed = false;
    _decisionCreatedProfileId = _decisionCreatedDraftId = null;
    _decision =
        decision; // Freeze ordinary host requests before the first await.
    await request(BeginDraftDecision(decision));
    return decision;
  }

  @override
  Future<void> endDraftDecision(DraftDecision decision) async {
    if (!identical(decision, _decision)) return;
    await request(EndDraftDecision(decision));
    _decision = null; // Only confirmed healthy resume reopens host admission.
  }

  // An explicit pre-close decision boundary for 1D.9. Cancellation already sent
  // to an operation stays factual; resuming never undoes it.
  Future<ReplyValue> pauseAdmission() {
    _hostPaused = true;
    return request(const PauseAdmission());
  }

  Future<ReplyValue> resumeAdmission() async {
    final reply = await request(const ResumeAdmission());
    _hostPaused = false;
    return reply;
  }

  @override
  Future<ShutdownOutcome> shutdown() {
    _reconcileShutdown();
    return _shutdown ??= _close();
  }

  ShutdownOutcome get _shutdownFacts => ShutdownOutcome(
    _released,
    _workerExited,
    workerWasSpawned: _workerSpawned,
  );

  void _completeShutdownObservation() {
    final release = _shutdownRelease;
    if (release != null && !release.isCompleted) release.complete(_released);
  }

  void _sendShutdownIfPossible() {
    final id = _shutdownId, commands = _commands;
    if (id == null ||
        commands == null ||
        _shutdownSent ||
        _workerExited ||
        _disposed) {
      return;
    }
    _shutdownSent = true;
    commands.send(RequestEnvelope(generation, id, const ShutdownRuntime()));
  }

  void _reconcileShutdown() {
    if (!_shutdownSettled || _shutdownVerified || !_shutdownFacts.canExit) {
      return;
    }
    // Keep earlier unknown outcomes immutable, but let subsequent quit requests
    // observe late authoritative facts. This only finishes client disposal; the
    // original stop/close request is never repeated and admission stays frozen.
    _shutdownVerified = true;
    _shutdown = _disposePorts().then((_) => _shutdownFacts);
  }

  Future<ShutdownOutcome> _close() async {
    _stopIntent = true;
    // Attach observation immediately; it may be queued before the handshake.
    if (_starting != null && !_workerExited && !_terminalFault) {
      unawaited(
        stop().then<void>((_) {}, onError: (Object _, StackTrace s) {}),
      );
    }
    await start();
    // An earlier startup/business fault must not settle this later, first close
    // exchange. Ordinary admission stays faulted; shutdown still needs proof.
    final release = _shutdownRelease ??= Completer<bool>();
    if (_released || _workerExited || !_workerSpawned) {
      _completeShutdownObservation();
    } else {
      _shutdownId = ++_nextId;
      // Keep the intent and ID even when a timed-out handshake has not supplied
      // its port yet. WorkerHello can send this one envelope after the deadline.
      _sendShutdownIfPossible();
    }
    final timer = Timer(deadline, () {
      _fail(CoordinationFault.requestUnknown);
      // _fail may already have recorded a prior fault. This observation must
      // still terminate without inferring release or canceling the intent.
      _completeShutdownObservation();
    });
    await release.future;
    if (_released) {
      await _exit.future.timeout(deadline, onTimeout: () {});
    }
    timer.cancel();
    final result = _shutdownFacts;
    if (result.canExit) {
      await _disposePorts();
      _shutdownVerified = true;
    }
    _shutdownSettled = true;
    return result;
  }

  Future<void> _disposePorts() => _disposing ??= _disposeClientPorts();

  Future<void> _disposeClientPorts() async {
    _disposed = true;
    for (final p in _pending.values) {
      p.timer.cancel();
      p.completer.completeError(
        const RuntimeFault(host: CoordinationFault.workerExited),
      );
    }
    _pending.clear();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final port in _ports) {
      port.close();
    }
    _ports.clear();
    await _changes.close();
    await _offlineChanges.close();
  }
}

final class _Pending {
  const _Pending(this.completer, this.timer);
  final Completer<ReplyValue> completer;
  final Timer timer;
}
