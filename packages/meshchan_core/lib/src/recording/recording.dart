import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart' as link;

import '../errors.dart';
import '../models/connection_profile.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_run.dart';
import '../models/effective_parameters.dart';
import '../storage/database.dart';
import '../values.dart';
import 'projection.dart';
import 'raw_operation.dart';
import 'run_store.dart';
import 'validation.dart';

enum RecordingPhase { registration, logical, cleanup }

enum RecordingSaveState { notAttempted, committed, failed }

/// A completed persistence attempt. Committed means the transaction committed;
/// a pending cleanup snapshot is explicitly not the final cleanup save.
final class RecordingSave {
  const RecordingSave(
    this.phase,
    this.state, {
    this.snapshot,
    this.error,
    this.finalCleanup = false,
  });
  final RecordingPhase phase;
  final RecordingSaveState state;
  final DiagnosticRun? snapshot;
  final CoreException? error;
  final bool finalCleanup;
}

/// Fixed before registration. Subscribe only after prepared commits. Return the
/// actual subscription immediately; do not acquire an unreturned resource and
/// then throw. Core invokes every returned subscription's cancel independently.
/// Calling cancelOperation synchronously is supported: operation cancellation
/// stays immediate, and subscription cleanup waits for registration to finish.
/// Task-owned subscriptions are already in core cleanup and must not be listed.
final class RecordingSubscription {
  const RecordingSubscription({required this.stage, required this.subscribe});
  final HostCleanupStage stage;
  final StreamSubscription<Object?> Function(void Function() cancelOperation)
  subscribe;
}

final class RecordedResult {
  RecordedResult({
    required this.logical,
    required this.cleanup,
    required this.registration,
    required this.logicalSave,
    required this.cleanupSave,
    required Iterable<RecordingSave> saves,
    this.coordinationFailure,
  }) : saves = List.unmodifiable(saves);
  final LogicalSummary? logical;
  final CleanupSummary cleanup;
  final RecordingSave registration;
  final RecordingSave logicalSave;
  final RecordingSave cleanupSave;
  final List<RecordingSave> saves;

  /// Controlled host/construction failure, independent of frozen task facts.
  final FailureSummary? coordinationFailure;
  bool get fullySuccessful =>
      coordinationFailure == null &&
      logical?.reason == LogicalReason.completed &&
      (cleanup.aggregate == CleanupState.succeeded ||
          cleanup.aggregate == CleanupState.notRequired) &&
      registration.state == RecordingSaveState.committed &&
      logicalSave.state == RecordingSaveState.committed &&
      cleanupSave.state == RecordingSaveState.committed &&
      cleanupSave.finalCleanup;
}

/// One already admitted finite recording. Observe logical and logicalSaved
/// without waiting for native release. Await done before finally closing storage.
/// Cancel uses the existing task/session gate; it never retracts or retries RF.
abstract interface class RecordedOperation {
  Future<RecordingSave> get prepared;
  Future<LogicalSummary?> get logical;
  Future<RecordingSave> get logicalSaved;
  Future<CleanupSummary> get cleanupDone;
  Future<RecordingSave> get cleanupSaved;
  Future<RecordedResult> get done;
  Stream<CleanupSummary> get cleanupUpdates;
  Stream<RecordingSave> get saveUpdates;
  Future<LogicalSummary?> cancel();
}

/// Internal implementation; the only constructor used by StorageHandle.
final class Recording implements RecordedOperation {
  Recording({
    required this.input,
    required this.appVersion,
    required this.createTransport,
    required List<RecordingSubscription> subscriptions,
    this.generateId,
    this.clock,
    this.onRegistered,
    this.onChanged,
    this.onCommitted,
  }) : plans = List.unmodifiable(subscriptions) {
    final p = input.parameters;
    _rawSlots = p is ListenProfileParameters
        ? 2
        : p is SendProfileParameters
        ? 1
        : 0;
    _slots = [
      if (_rawSlots > 0)
        _SubscriptionSlot(HostCleanupStage.sessionSubscription),
      if (_rawSlots > 1)
        _SubscriptionSlot(HostCleanupStage.entriesSubscription),
      for (final plan in plans) _SubscriptionSlot(plan.stage),
    ];
    _host = _slots.isEmpty
        ? CleanupScopeSummary(state: CleanupState.notRequired)
        : CleanupScopeSummary();
  }
  final EffectiveParameters input;
  final String appVersion;
  final link.CompanionTransport Function() createTransport;
  final List<RecordingSubscription> plans;
  final LocalId Function()? generateId;
  final DateTime Function()? clock;
  final void Function(LocalId)? onRegistered;
  final void Function()? onChanged;
  final void Function(DiagnosticRun)? onCommitted;
  LocalId? get runId => _id;
  late final int _rawSlots;
  late final List<_SubscriptionSlot> _slots;
  final _prepared = Completer<RecordingSave>();
  final _logical = Completer<LogicalSummary?>();
  final _logicalSaved = Completer<RecordingSave>();
  final _cleanupDone = Completer<CleanupSummary>();
  final _cleanupSaved = Completer<RecordingSave>();
  final _done = Completer<RecordedResult>();
  final _cleanupUpdates = StreamController<CleanupSummary>.broadcast();
  final _saveUpdates = StreamController<RecordingSave>.broadcast();
  @override
  Future<RecordingSave> get prepared => _prepared.future;
  @override
  Future<LogicalSummary?> get logical => _logical.future;
  @override
  Future<RecordingSave> get logicalSaved => _logicalSaved.future;
  @override
  Future<CleanupSummary> get cleanupDone => _cleanupDone.future;
  @override
  Future<RecordingSave> get cleanupSaved => _cleanupSaved.future;
  @override
  Future<RecordedResult> get done => _done.future;
  @override
  Stream<CleanupSummary> get cleanupUpdates => _cleanupUpdates.stream;
  @override
  Stream<RecordingSave> get saveUpdates => _saveUpdates.stream;
  bool _canceled = false, _hostStopping = false, _logicalObserved = false;
  bool _registeringSubscriptions = false, _hostStopRequested = false;
  void Function()? _cancel;
  CleanupScopeSummary _core = CleanupScopeSummary();
  late CleanupScopeSummary _host;
  final _hostFailures = <FailureSummary>[];
  final _hostDone = Completer<void>();
  final _coreDone = Completer<void>();
  final _saves = <RecordingSave>[];
  final _pendingSaves = <Future<RecordingSave>>[];
  late RunStore _store;
  LocalId? _id;
  FailureSummary? _coordinationFailure;
  CleanupSummary get _cleanup => combineCleanup(_core, _host);

  @override
  Future<LogicalSummary?> cancel() {
    _canceled = true;
    _cancel?.call();
    return logical;
  }

  RecordingSave _report(RecordingSave value) {
    _saves.add(value);
    _saveUpdates.add(value);
    return value;
  }

  Future<RecordingSave> _save(
    RecordingPhase phase,
    Future<DiagnosticRun> Function() action, {
    bool finalCleanup = false,
  }) async {
    try {
      final snapshot = await action();
      // This callback only registers independent maintenance. It never awaits
      // pruning or changes the committed save outcome.
      onCommitted?.call(snapshot);
      return _report(
        RecordingSave(
          phase,
          RecordingSaveState.committed,
          snapshot: snapshot,
          finalCleanup: finalCleanup,
        ),
      );
    } on CoreException catch (e) {
      return _report(
        RecordingSave(
          phase,
          RecordingSaveState.failed,
          error: e,
          finalCleanup: finalCleanup,
        ),
      );
    }
  }

  void _changed() {
    _cleanupUpdates.add(_cleanup);
    if (_logicalObserved && _id != null) {
      final core = _core, host = _host;
      _pendingSaves.add(
        _save(
          RecordingPhase.cleanup,
          () => _store.saveCleanup(_id!, core: core, host: host),
        ),
      );
    }
  }

  void _own(int index, StreamSubscription<Object?> subscription) {
    _slots[index].subscription = subscription;
  }

  void _registerHostSubscriptions() {
    _registeringSubscriptions = true;
    try {
      for (var i = 0; i < plans.length; i++) {
        _own(
          _rawSlots + i,
          plans[i].subscribe(() {
            cancel().ignore();
          }),
        );
      }
    } finally {
      // A callback may synchronously cancel before returning its subscription.
      // Empty slots are not final until this pass returns or throws. Keep the
      // raw/task cancellation immediate while deferring only host settlement.
      _registeringSubscriptions = false;
      if (_hostStopRequested) _stopHost();
    }
  }

  void _stopHost() {
    if (_hostStopping) return;
    if (_registeringSubscriptions) {
      _hostStopRequested = true;
      return;
    }
    _hostStopRequested = false;
    _hostStopping = true;
    for (final slot in _slots) {
      final subscription = slot.subscription;
      if (subscription == null) {
        slot.finished = true;
        continue;
      }
      // Observe each source immediately, even when another cancellation hangs.
      unawaited(
        Future.sync(subscription.cancel).then<void>(
          (_) {
            slot.finished = true;
            _hostProgress();
          },
          onError: (Object e, StackTrace _) {
            slot.finished = true;
            _hostFailures.add(
              projectFailure(
                e,
                domain: FailureDomain.host,
                kind: FailureKind.cleanup,
                hostStage: slot.stage,
              ),
            );
            _hostProgress();
          },
        ),
      );
    }
    _hostProgress();
  }

  void _hostProgress() {
    final all = _slots.every((s) => s.finished);
    _host = CleanupScopeSummary(
      state: !all
          ? CleanupState.pending
          : _hostFailures.isNotEmpty
          ? CleanupState.failed
          : _slots.every((s) => s.subscription == null)
          ? CleanupState.notRequired
          : CleanupState.succeeded,
      failures: _hostFailures,
    );
    _changed();
    if (all && !_hostDone.isCompleted) _hostDone.complete();
    _completeCleanupObservation();
  }

  void _completeCleanupObservation() {
    if (_coreDone.isCompleted &&
        _hostDone.isCompleted &&
        !_cleanupDone.isCompleted) {
      _cleanupDone.complete(_cleanup);
    }
  }

  void _observeCore(Future<CleanupScopeSummary> future) {
    unawaited(
      future.then<void>(
        (value) {
          _core = value;
          _changed();
          _coreDone.complete();
          _completeCleanupObservation();
        },
        onError: (Object e, StackTrace _) {
          // A rejected Future settles the observation, but does not prove release.
          _core = CleanupScopeSummary(
            state: CleanupState.unconfirmed,
            failures: [
              projectFailure(
                e,
                domain: FailureDomain.cleanup,
                kind: FailureKind.cleanup,
              ),
            ],
          );
          _changed();
          _coreDone.complete();
          _completeCleanupObservation();
        },
      ),
    );
  }

  LogicalSummary _hostResult(LogicalReason reason) {
    final failure = reason == LogicalReason.canceled
        ? null
        : projectFailure(
            null,
            domain: FailureDomain.host,
            kind: FailureKind.unexpectedFailure,
            stage: DiagnosticStage.startup,
          );
    return switch (input.operation) {
      DiagnosticOperation.send => SendSummary(
        reason: reason,
        stage: DiagnosticStage.startup,
        failure: failure,
      ),
      DiagnosticOperation.listen => ListenSummary(
        reason: reason,
        stage: DiagnosticStage.startup,
        failure: failure,
        publishedEntries: 0,
        processedEntries: 0,
        matchingDatagrams: 0,
        filteredDatagrams: 0,
        ordinaryMessages: 0,
      ),
      DiagnosticOperation.ping => PingSummary(
        reason: reason,
        stage: DiagnosticStage.startup,
        failure: failure,
      ),
      DiagnosticOperation.respond => RespondSummary(
        reason: reason,
        stage: DiagnosticStage.startup,
        failure: failure,
      ),
    };
  }

  Future<void> _observeLogical(Future<LogicalSummary> future) async {
    LogicalSummary summary;
    try {
      summary = await future;
    } catch (_) {
      _coordinationFailure ??= projectFailure(
        null,
        domain: FailureDomain.host,
        kind: FailureKind.unexpectedFailure,
        stage: DiagnosticStage.settling,
      );
      summary = _hostResult(LogicalReason.unexpectedFailure);
      _cancel?.call();
    }
    // Capture the observation instant now, before entering the per-run queue.
    DateTime? observed;
    CoreException? clockError;
    try {
      observed = _store.observeTime();
    } on CoreException catch (e) {
      clockError = e;
    }
    _stopHost();
    _logical.complete(summary);
    final saving = clockError != null
        ? Future.value(
            _report(
              RecordingSave(
                RecordingPhase.logical,
                RecordingSaveState.failed,
                error: clockError,
              ),
            ),
          )
        : _save(
            RecordingPhase.logical,
            () => _store.saveLogical(_id!, summary, observed!),
          );
    // Queue the logical write before any buffered cleanup observation. Cleanup
    // itself has already started, and never waits on this database queue.
    _logicalObserved = true;
    _changed();
    _logicalSaved.complete(await saving);
  }

  /// The storage admission spans this Future, including all cleanup and saves.
  Future<void> run(CoreDatabase db) async {
    _store = RunStore(
      db,
      generateId: generateId,
      clock: clock,
      onChanged: onChanged,
    );
    final registration = await _save(
      RecordingPhase.registration,
      () => _store.register(
        appVersion: appVersion,
        configuration: projectConfiguration(input),
        profileId: input.profileId,
        hostRequired: _slots.isNotEmpty,
      ),
    );
    if (registration.snapshot case final run?) {
      _id = run.runId;
      onRegistered?.call(run.runId);
    }
    _prepared.complete(registration);
    if (registration.state != RecordingSaveState.committed) {
      _core = CleanupScopeSummary(state: CleanupState.notRequired);
      _host = CleanupScopeSummary(state: CleanupState.notRequired);
      _logical.complete(null);
      _logicalSaved.complete(
        const RecordingSave(
          RecordingPhase.logical,
          RecordingSaveState.notAttempted,
        ),
      );
      _cleanupDone.complete(_cleanup);
      _cleanupSaved.complete(
        const RecordingSave(
          RecordingPhase.cleanup,
          RecordingSaveState.notAttempted,
        ),
      );
    } else {
      _id = registration.snapshot!.runId;
      Future<LogicalSummary>? logicalFuture;
      Future<void>? observing;
      link.MeshCoreSession? session;
      bool delegated = false;
      try {
        if (_canceled) {
          _core = CleanupScopeSummary(state: CleanupState.notRequired);
          _coreDone.complete();
          logicalFuture = Future.value(_hostResult(LogicalReason.canceled));
        } else {
          final transport = createTransport();
          final b = input.parameters.budgets;
          session = link.MeshCoreSession(
            transport: transport,
            appName: 'Meshchan',
            maxQueuedCommands: 8,
            requestTimeout: Duration(seconds: b.requestTimeoutSeconds),
            initializationTimeout: Duration(
              seconds: b.initializationTimeoutSeconds,
            ),
            startupDelay: Duration(milliseconds: b.startupDelayMilliseconds),
          );
          final p = input.parameters;
          late Future<void> Function() start;
          if (p is PingProfileParameters || p is RespondProfileParameters) {
            final options = _taskOptions(p);
            if (p is PingProfileParameters) {
              final task = link.MeshchanPingTask(
                session: session,
                options: options,
                content: Uint8List.fromList(input.content!),
                responseTimeout: Duration(seconds: p.responseTimeoutSeconds),
              );
              logicalFuture = task.done.then(projectTask);
              _observeCore(task.cleanupDone.then(projectTaskCleanup));
              _cancel = () {
                task.cancel().ignore();
              };
              start = task.start;
            } else {
              final r = p as RespondProfileParameters;
              final task = link.MeshchanResponderTask(
                session: session,
                options: options,
                listenDuration: Duration(seconds: r.listenDurationSeconds),
                maxResponses: r.maxResponses,
              );
              logicalFuture = task.done.then(projectTask);
              _observeCore(task.cleanupDone.then(projectTaskCleanup));
              _cancel = () {
                task.cancel().ignore();
              };
              start = task.start;
            }
          } else {
            final raw = RawOperation(session, input, _own, _stopHost);
            logicalFuture = raw.done;
            _observeCore(raw.cleanupDone);
            _cancel = raw.cancel;
            start = raw.start;
          }
          delegated = true;
          // Attach result observation before invoking arbitrary host callbacks.
          observing = _observeLogical(logicalFuture);
          _registerHostSubscriptions();
          if (_canceled) {
            _cancel!();
          } else {
            _core = CleanupScopeSummary(state: CleanupState.pending);
            try {
              await start();
            } on link.DiagnosticTaskStartError {
              // start and done may carry the same rejection; done is authoritative.
            } catch (_) {
              _coordinationFailure ??= projectFailure(
                null,
                domain: FailureDomain.host,
                kind: FailureKind.unexpectedFailure,
                stage: DiagnosticStage.startup,
              );
              _cancel!();
            }
          }
          await observing;
        }
      } catch (_) {
        _coordinationFailure ??= projectFailure(
          null,
          domain: FailureDomain.host,
          kind: FailureKind.unexpectedFailure,
          stage: DiagnosticStage.startup,
        );
        if (delegated) {
          _cancel?.call();
        } else {
          if (session != null) {
            _observeCore(
              Future.sync(
                session.close,
              ).then((_) => CleanupScopeSummary(state: CleanupState.succeeded)),
            );
          } else {
            _core = CleanupScopeSummary(state: CleanupState.notRequired);
            _coreDone.complete();
          }
          logicalFuture = Future.value(
            _hostResult(LogicalReason.unexpectedFailure),
          );
        }
      }
      if (observing != null) {
        await observing;
      } else {
        await _observeLogical(logicalFuture!);
      }
      _stopHost();
      await Future.wait([_coreDone.future, _hostDone.future]);
      _completeCleanupObservation();
      await Future.wait(_pendingSaves);
      final finalSave = await _save(
        RecordingPhase.cleanup,
        () => _store.saveCleanup(_id!, core: _core, host: _host),
        finalCleanup:
            terminalCleanup(_core.state) && terminalCleanup(_host.state),
      );
      _cleanupSaved.complete(finalSave);
    }
    _done.complete(
      RecordedResult(
        logical: await logical,
        cleanup: await cleanupDone,
        registration: registration,
        logicalSave: await logicalSaved,
        cleanupSave: await cleanupSaved,
        saves: _saves,
        coordinationFailure: _coordinationFailure,
      ),
    );
    _cleanupUpdates.close().ignore();
    _saveUpdates.close().ignore();
  }
}

link.DiagnosticTaskOptions _taskOptions(ProfileParameters p) {
  final (send, receive, route, endpoints, entries) = switch (p) {
    PingProfileParameters() => (
      p.sendChannelIndex,
      p.receiveChannelIndex,
      p.route,
      p.endpoints,
      p.maxEntries,
    ),
    RespondProfileParameters() => (
      p.sendChannelIndex,
      p.receiveChannelIndex,
      p.route,
      p.endpoints,
      p.maxEntries,
    ),
    _ => throw StateError('Task parameters required.'),
  };
  return link.DiagnosticTaskOptions(
    sendChannelIndex: send,
    receiveChannelIndex: receive,
    routeDescriptor: route.routeDescriptor,
    path: Uint8List.fromList(route.path),
    localTestId: endpoints.localTestId,
    peerTestId: endpoints.peerTestId,
    taskTimeout: Duration(seconds: p.budgets.taskTimeoutSeconds),
    maxEntries: entries,
    maxReadsPerBatch: 8,
  );
}

final class _SubscriptionSlot {
  _SubscriptionSlot(this.stage);
  final HostCleanupStage stage;
  StreamSubscription<Object?>? subscription;
  bool finished = false;
}
