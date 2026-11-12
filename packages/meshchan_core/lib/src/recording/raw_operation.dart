import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart' as link;

import '../models/connection_profile.dart';
import '../models/diagnostic_codes.dart';
import '../models/diagnostic_run.dart';
import '../models/effective_parameters.dart';
import 'projection.dart';

/// Finite raw adapter. Session close is triggered at the terminal gate; done
/// waits only for accepted commands/reception facts, never for native release.
final class RawOperation {
  RawOperation(this.session, this.input, this.ownSubscription, this.stopping);
  final link.MeshCoreSession session;
  final EffectiveParameters input;
  final void Function(int, StreamSubscription<Object?>) ownSubscription;
  final void Function() stopping;
  final _done = Completer<LogicalSummary>();
  final _cleanup = Completer<CleanupScopeSummary>();
  Future<LogicalSummary> get done => _done.future;
  Future<CleanupScopeSummary> get cleanupDone => _cleanup.future;
  final _watch = Stopwatch();
  Timer? _timer;
  bool _terminal = false;
  bool _started = false;
  DiagnosticStage _stage = DiagnosticStage.startup;
  DiagnosticStage? _endedStage;
  LogicalReason? _reason;
  FailureSummary? _failure;
  Future<void>? _working;
  Future<void>? _receiving;
  link.MeshCoreReception? _receiver;
  link.MeshCoreReceptionResult? _reception;
  bool _entriesEnded = false;
  int _processed = 0, _matching = 0, _filtered = 0, _ordinary = 0;
  bool _attempted = false,
      _pending = false,
      _pendingAtEnd = false,
      _accepted = false;
  link.MeshCoreSessionCommandFailure? _sendFailure;

  Future<void> start() async {
    if (_terminal) return;
    _started = true;
    _watch.start();
    ownSubscription(
      0,
      session.events.listen((event) {
        if (event is link.MeshCoreSessionFailed &&
            !_terminal &&
            event.failure.kind != link.MeshCoreSessionFailureKind.canceled) {
          _fail(event.failure);
        }
      }, onError: (Object e, StackTrace _) => _fail(e)),
    );
    _stage = DiagnosticStage.connecting;
    void deadline() {
      if (!_check()) return;
      final remaining =
          Duration(seconds: input.parameters.budgets.taskTimeoutSeconds) -
          _watch.elapsed;
      _timer = Timer(
        Duration(milliseconds: (remaining.inMicroseconds - 1) ~/ 1000 + 1),
        deadline,
      );
    }

    deadline();
    if (!_terminal) {
      _working = _work().then<void>(
        (_) {},
        onError: (Object e, StackTrace _) => _fail(e),
      );
    }
  }

  bool _check() {
    if (_terminal) return false;
    final failure = session.lastFailure;
    if (failure != null) {
      _fail(failure);
      return false;
    }
    if (_watch.elapsed >=
        Duration(seconds: input.parameters.budgets.taskTimeoutSeconds)) {
      _finish(
        LogicalReason.taskTimeout,
        projectFailure(
          null,
          domain: FailureDomain.host,
          kind: FailureKind.taskTimeout,
          stage: _stage,
        ),
      );
      return false;
    }
    return true;
  }

  void _fail(Object error) {
    if (_terminal) return;
    final reason = _stage == DiagnosticStage.connecting
        ? LogicalReason.initializationFailed
        : _stage == DiagnosticStage.sending
        ? LogicalReason.sendFailed
        : LogicalReason.receptionFailed;
    _finish(
      reason,
      projectFailure(
        error,
        domain: sessionEvidence(error) == null
            ? FailureDomain.host
            : FailureDomain.session,
        stage: _stage,
      ),
    );
  }

  void _progress() {
    if (!_check() || _reception == null) return;
    final r = _reception!;
    final error = r.commandFailure ?? r.sessionFailure ?? r.startError;
    if (error != null) {
      _fail(error);
      return;
    }
    // Normal done can precede the final entries/onDone delivery. Our unpaused
    // synchronous consumer completes all promised observations first.
    if (!_entriesEnded) return;
    if (r.reason == link.MeshCoreReceptionStopReason.durationElapsed ||
        r.reason == link.MeshCoreReceptionStopReason.entryLimit) {
      _finish(LogicalReason.completed);
    } else {
      _finish(
        LogicalReason.receptionFailed,
        projectFailure(
          null,
          domain: FailureDomain.host,
          kind: FailureKind.receptionFailed,
          stage: _stage,
        ),
      );
    }
  }

  Future<void> _work() async {
    await session.connect();
    if (!_check()) return;
    switch (input.parameters) {
      case SendProfileParameters p:
        _stage = DiagnosticStage.sending;
        _attempted = true;
        _pending = true;
        try {
          await session.sendChannelData(
            channelIndex: p.sendChannelIndex,
            dataType: p.dataType,
            routeDescriptor: p.route.routeDescriptor,
            path: Uint8List.fromList(p.route.path),
            payload: Uint8List.fromList(input.content!),
          );
          _pending = false;
          _accepted = true;
        } on link.MeshCoreSessionCommandFailure catch (e) {
          _pending = false;
          _sendFailure = e;
          rethrow;
        }
        if (_check()) _finish(LogicalReason.completed);
      case ListenProfileParameters p:
        _stage = DiagnosticStage.receiving;
        final receiver = _receiver = session.createReception(
          duration: Duration(seconds: p.listenDurationSeconds),
          maxEntries: p.maxEntries,
          maxReadsPerBatch: 8,
        );
        ownSubscription(
          1,
          receiver.entries.listen(
            (entry) {
              if (!_check()) return;
              _processed++;
              if (entry is link.ChannelDataResponse) {
                if (entry.channelIndex == p.receiveChannelIndex &&
                    (p.dataType == null || entry.dataType == p.dataType)) {
                  _matching++;
                } else {
                  _filtered++;
                }
              } else if (entry is link.QueuedMessageResponse) {
                _ordinary++;
              }
            },
            onError: (Object e, StackTrace _) => _fail(e),
            onDone: () {
              _entriesEnded = true;
              _progress();
            },
          ),
        );
        _receiving = receiver.done.then<void>((r) {
          _reception = r;
          _progress();
        }, onError: (Object e, StackTrace _) => _fail(e));
        await receiver.start();
      default:
        throw StateError('Raw operation requires send or listen.');
    }
  }

  void cancel() {
    if (_terminal) return;
    // Session invalidation precedes its asynchronous event/command callbacks.
    // Preserve that committed failure before honoring a later cancellation.
    final failure = session.lastFailure;
    if (failure != null) {
      _fail(failure);
      return;
    }
    _finish(LogicalReason.canceled);
  }

  void _finish(LogicalReason reason, [FailureSummary? failure]) {
    if (_terminal) return;
    _terminal = true;
    _reason = reason;
    _endedStage = _stage;
    _failure = failure;
    _pendingAtEnd = _pending;
    _timer?.cancel();
    _watch.stop();
    if (_started) {
      // Install the observer immediately; host cancellation also starts now.
      final closing = Future.sync(session.close);
      unawaited(
        closing.then<void>(
          (_) => _closed(null),
          onError: (Object e, StackTrace _) => _closed(e),
        ),
      );
      _receiver?.stop().ignore();
    } else {
      _cleanup.complete(CleanupScopeSummary(state: CleanupState.notRequired));
    }
    stopping();
    scheduleMicrotask(() {
      unawaited(_settle());
    });
  }

  void _closed(Object? error) {
    final failures = session.cleanupFailures
        .map(
          (e) => projectFailure(
            e,
            domain: FailureDomain.cleanup,
            kind: FailureKind.cleanup,
            stage: _endedStage,
          ),
        )
        .toList();
    if (error != null && session.cleanupFailures.isEmpty) {
      failures.add(
        projectFailure(
          error,
          domain: FailureDomain.cleanup,
          kind: FailureKind.cleanup,
          stage: _endedStage,
        ),
      );
    }
    _cleanup.complete(
      CleanupScopeSummary(
        state: failures.isEmpty ? CleanupState.succeeded : CleanupState.failed,
        failures: failures,
      ),
    );
  }

  Future<void> _settle() async {
    await Future.wait([?_working, ?_receiving]);
    final send = projectSend(
      link.DiagnosticSendFacts(
        attempted: _attempted,
        pendingAtTermination: _pendingAtEnd,
        deviceAcceptanceConfirmed: _accepted,
        dispatched: _accepted ? true : _sendFailure?.dispatched,
        localWriteCompleted: _accepted
            ? true
            : _sendFailure?.localWriteCompleted,
        localOkObserved: _accepted
            ? true
            : _sendFailure?.matchingResponseObserved,
        commandFailure: _sendFailure,
      ),
    );
    _done.complete(
      input.parameters is SendProfileParameters
          ? SendSummary(
              reason: _reason,
              stage: _endedStage,
              failure: _failure,
              send: send,
            )
          : ListenSummary(
              reason: _reason,
              stage: _endedStage,
              failure: _failure,
              reception: projectReception(_reception),
              receptionReason: _reception == null
                  ? null
                  : receptionReason(_reception!.reason),
              publishedEntries: _reception?.publishedEntries ?? 0,
              processedEntries: _processed,
              matchingDatagrams: _matching,
              filteredDatagrams: _filtered,
              ordinaryMessages: _ordinary,
            ),
    );
  }
}
