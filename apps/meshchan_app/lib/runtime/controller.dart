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
  Future<OfflineSnapshot> refresh({int pageSize = 20, DraftCursor? after});
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after});
  Future<DraftSnapshot> readDraft(String id);
  Future<DraftSnapshot> saveDraft({
    required String title,
    required String body,
    String? id,
    int? expectedRevision,
    DraftDecision? decision,
  });
  Future<String> deleteDraft(String id, {required int expectedRevision});
  Future<DraftDecision> beginDraftDecision(int documentGeneration);
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
  int _decisionGeneration = 0;
  DraftDecision? _decision;
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
        if (!_terminalFault) _project(event.snapshot);
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

  void _project(RuntimeSnapshot value, {bool force = false, bool? exited}) {
    if (!force && value.sequence < _snapshot.sequence) return;
    _snapshot = RuntimeSnapshot(
      generation: generation,
      sequence: value.sequence,
      phase: value.phase,
      owner: value.owner,
      storage: value.storage,
      gate: value.gate,
      stopReceived: value.stopReceived,
      stopApplied: value.stopApplied,
      admissionPaused: value.admissionPaused,
      workerExited: exited ?? _workerExited,
      error: value.error,
      maintenance: value.maintenance,
      operation: value.operation,
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
    if (_decision != null &&
        (request is ReadOffline ||
            request is ListDrafts ||
            request is ReadDraft ||
            request is DeleteDraft ||
            request is CreateFixtureDraft ||
            (request is WriteDraft && request.decision != _decision))) {
      return Future.error(const RuntimeFault(host: CoordinationFault.stopped));
    }
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
    DraftDecision? decision,
  }) async => (await request(
    WriteDraft(
      title: title,
      body: body,
      id: id,
      expectedRevision: expectedRevision,
      decision: decision,
    ),
  ) as DraftValue).draft;
  @override
  Future<String> deleteDraft(
    String id, {
    required int expectedRevision,
  }) async =>
      (await request(DeleteDraft(id, expectedRevision)) as DeletedDraft).id;
  @override
  Future<DraftDecision> beginDraftDecision(int documentGeneration) async {
    if (_decision != null) {
      throw const RuntimeFault(host: CoordinationFault.invalidState);
    }
    final decision = DraftDecision(++_decisionGeneration, documentGeneration);
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
  Future<ReplyValue> pauseAdmission() => request(const PauseAdmission());
  Future<ReplyValue> resumeAdmission() => request(const ResumeAdmission());

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
