import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/companion_messages.dart';
import '../session/meshcore_session.dart';
import 'diagnostic_cache.dart';
import 'diagnostic_results.dart';
import 'ping_pong.dart';

part 'ping_task.dart';
part 'responder_task.dart';

/// Explicit local configuration. Copies path at construction; validation occurs
/// on first start, before the task takes ownership of a fresh idle session.
final class DiagnosticTaskOptions {
  DiagnosticTaskOptions({
    required this.sendChannelIndex,
    required this.receiveChannelIndex,
    required this.localTestId,
    required this.peerTestId,
    required this.routeDescriptor,
    required Uint8List path,
    required this.taskTimeout,
    this.maxEntries = 128,
    this.maxReadsPerBatch = 8,
  }) : path = Uint8List.fromList(path).asUnmodifiableView();

  final int sendChannelIndex;
  final int receiveChannelIndex;
  final int localTestId;
  final int peerTestId;
  final int routeDescriptor;
  final Uint8List path;
  final Duration taskTimeout;
  final int maxEntries;
  final int maxReadsPerBatch;

  void _validate() {
    if (sendChannelIndex < 0 ||
        sendChannelIndex > 255 ||
        receiveChannelIndex < 0 ||
        receiveChannelIndex > 255) {
      throw ArgumentError('Channel indexes must be uint8 values.');
    }
    if (localTestId < 1 ||
        localTestId > 0xffffffff ||
        peerTestId < 1 ||
        peerTestId > 0xffffffff ||
        localTestId == peerTestId) {
      throw ArgumentError(
        'Test endpoints must be distinct nonzero uint32 labels.',
      );
    }
    _positive(taskTimeout, 'taskTimeout');
    if (maxEntries <= 0 || maxReadsPerBatch <= 0) {
      throw ArgumentError('Reception limits must be positive.');
    }
    maxDiagnosticContentLengthForRoute(
      routeDescriptor: routeDescriptor,
      path: path,
    );
  }
}

void _positive(Duration value, String name) {
  if (value <= Duration.zero) throw ArgumentError('$name must be positive.');
}

// VM timers truncate fractional milliseconds. Round positive scheduling delays
// up so an early callback cannot consume the only deadline check. Absolute
// elapsed deadlines retain their original precision for admission/commitment.
Duration _timerDelay(Duration duration) => Duration(
  milliseconds:
      (duration.inMicroseconds - 1) ~/ Duration.microsecondsPerMillisecond + 1,
);

// These two tasks share ownership and settlement, not a general executor API.
abstract class _DiagnosticTask<R extends DiagnosticTaskResult> {
  _DiagnosticTask(this.session, this.options, this._elapsed);
  final MeshCoreSession session;
  final DiagnosticTaskOptions options;
  final Duration Function()? _elapsed;
  final _watch = Stopwatch();
  static final _claims = Expando<bool>();
  final _done = Completer<R>();
  final _cleanup = Completer<DiagnosticCleanupResult>();
  final _cleanupFailures = <DiagnosticTaskFailure>[];
  DiagnosticCleanupState _cleanupState = DiagnosticCleanupState.notStarted;
  DiagnosticCleanupState get cleanupState => _cleanupState;
  Future<R> get done => _done.future;
  Future<DiagnosticCleanupResult> get cleanupDone => _cleanup.future;
  bool _used = false;
  bool _owned = false;
  bool _terminal = false;
  Duration _origin = Duration.zero;
  Duration get _now => (_elapsed?.call() ?? _watch.elapsed) - _origin;
  Timer? _taskTimer;
  StreamSubscription<MeshCoreSessionEvent>? _events;
  StreamSubscription<CompanionResponse>? _entries;
  MeshCoreReception? _receiver;
  MeshCoreReceptionResult? _receptionResult;
  bool _entriesEnded = false;
  Future<void>? _connecting;
  Future<void>? _startingReception;
  Future<void>? _receptionDone;
  Future<void>? _sending;
  bool _sendPending = false;
  bool _sendAttempted = false;
  bool _sendSucceeded = false;
  bool _pendingAtTermination = false;
  MeshCoreSessionCommandFailure? _commandFailure;
  DiagnosticTaskStage _stage = DiagnosticTaskStage.startup;
  late DiagnosticTaskStage _terminalStage;
  late DiagnosticTaskReason _reason;
  DiagnosticTaskFailure? _failure;
  MeshCoreSessionFailure? _sessionFailure;
  int _processed = 0;

  void _validate();
  void _prepare() {}
  void _ready();
  void _entry(CompanionResponse entry);
  void _receptionProgress();
  void _cancelBusinessTimers() {}
  R _result();

  /// Acceptance only. Ownership check, claim, and connect occur synchronously.
  /// After acceptance, callers must not operate this session independently.
  Future<void> start() {
    if (_used) {
      return _rejected(
        StateError('This task permits one start.'),
        StackTrace.current,
      );
    }
    _used = true;
    try {
      options._validate();
      _validate();
      if (session.state != MeshCoreSessionState.idle ||
          _claims[session] == true) {
        throw StateError('Task requires a fresh idle session.');
      }
      if (session.maxQueuedCommands < 1) {
        throw StateError('Task requires at least one waiting command slot.');
      }
    } catch (error, stack) {
      final rejected = DiagnosticTaskStartError(error, stack);
      _finish(DiagnosticTaskReason.startRejected, rejected, stack);
      return _rejected(rejected, stack);
    }
    _claims[session] = true;
    _owned = true;
    _watch.start();
    _origin = _elapsed?.call() ?? Duration.zero;
    _taskTimer = Timer(_timerDelay(options.taskTimeout), () => _check());
    _events = session.events.listen(
      (event) {
        if (!_terminal && event is MeshCoreSessionFailed) _check();
      },
      onError: (Object error, StackTrace stack) {
        _finish(DiagnosticTaskReason.sessionFailed, error, stack);
      },
    );
    try {
      _prepare();
    } catch (error, stack) {
      _finish(DiagnosticTaskReason.nonceGenerationFailed, error, stack);
    }
    if (!_terminal && _check()) {
      _stage = DiagnosticTaskStage.connecting;
      _connecting = _observe(
        session.connect(),
        (_) {
          if (_check()) _ready();
        },
        (error, stack) {
          _finish(DiagnosticTaskReason.initializationFailed, error, stack);
        },
      );
    }
    return Future.value();
  }

  Future<void> _rejected(Object error, StackTrace stack) {
    final future = Future<void>.error(
      error is DiagnosticTaskStartError
          ? error
          : DiagnosticTaskStartError(error, stack),
      stack,
    );
    future.ignore();
    return future;
  }

  /// Idempotent; before start this neither claims nor closes the session.
  Future<R> cancel() {
    if (!_terminal) {
      _used = true;
      _finish(DiagnosticTaskReason.canceled);
    }
    return done;
  }

  DiagnosticTaskReason? _expired(Duration now) =>
      now >= options.taskTimeout ? DiagnosticTaskReason.taskTimeout : null;

  bool _check() {
    if (_terminal) return false;
    final failure = session.lastFailure;
    if (failure != null) {
      _sessionFailure ??= failure;
      _finish(
        _stage == DiagnosticTaskStage.connecting
            ? DiagnosticTaskReason.initializationFailed
            : DiagnosticTaskReason.sessionFailed,
        failure,
        failure.stackTrace,
      );
      return false;
    }
    final expired = _expired(_now);
    if (expired != null) {
      _finish(expired);
      return false;
    }
    return true;
  }

  bool _readyToCommit() {
    if (!_check()) return false;
    if (session.state != MeshCoreSessionState.ready) {
      _finish(
        DiagnosticTaskReason.sessionFailed,
        StateError('Owned session is no longer ready.'),
        StackTrace.current,
      );
      return false;
    }
    return true;
  }

  Future<void> _observe<T>(
    Future<T> future,
    void Function(T) success,
    void Function(Object, StackTrace) failure,
  ) => future
      .then<void>(success, onError: failure)
      .then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _finish(DiagnosticTaskReason.sessionFailed, error, stack);
        },
      );

  void _receiveFor(Duration duration, void Function() started) {
    if (duration <= Duration.zero) {
      // The monotonic budget may expire between ready and receiver creation.
      _finish(DiagnosticTaskReason.taskTimeout);
      return;
    }
    _stage = DiagnosticTaskStage.receiving;
    final receiver = _receiver = session.createReception(
      duration: _timerDelay(duration),
      maxEntries: options.maxEntries,
      maxReadsPerBatch: options.maxReadsPerBatch,
    );
    _entries = receiver.entries.listen(
      (entry) {
        try {
          if (_check()) _entry(entry);
        } catch (error, stack) {
          _finish(DiagnosticTaskReason.receptionFailed, error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        _finish(DiagnosticTaskReason.receptionFailed, error, stack);
      },
      onDone: () {
        _entriesEnded = true;
        if (_check()) _receptionProgress();
      },
    );
    _receptionDone = _observe(
      receiver.done,
      (result) {
        _receptionResult = result;
        if (_terminal) return;
        final failure =
            result.commandFailure ?? result.sessionFailure ?? result.startError;
        if (failure != null) {
          _finish(
            DiagnosticTaskReason.receptionFailed,
            failure,
            StackTrace.current,
          );
        } else if (_check()) {
          _receptionProgress();
        }
      },
      (error, stack) =>
          _finish(DiagnosticTaskReason.receptionFailed, error, stack),
    );
    _startingReception = _observe(
      receiver.start(),
      (_) {
        if (_check()) started();
      },
      (error, stack) =>
          _finish(DiagnosticTaskReason.receptionFailed, error, stack),
    );
  }

  void _send(
    MeshchanDiagnosticMessage message,
    void Function() succeeded, {
    void Function()? localSuccess,
  }) {
    _stage = DiagnosticTaskStage.sending;
    _sendAttempted = true;
    _sendPending = true;
    _sendSucceeded = false;
    _commandFailure = null;
    _sending = _observe(
      session.sendChannelData(
        channelIndex: options.sendChannelIndex,
        dataType: diagnosticDataType,
        routeDescriptor: options.routeDescriptor,
        path: options.path,
        payload: encodeDiagnosticPayload(message),
      ),
      (_) {
        _sendPending = false;
        _sendSucceeded = true;
        localSuccess?.call();
        if (_check()) succeeded();
      },
      (error, stack) {
        _sendPending = false;
        if (error is MeshCoreSessionCommandFailure) {
          _commandFailure = error;
          if (error.sessionFailure.kind !=
              MeshCoreSessionFailureKind.canceled) {
            _sessionFailure ??= error.sessionFailure;
          }
        }
        _finish(DiagnosticTaskReason.sendFailed, error, stack);
      },
    );
  }

  DiagnosticSendFacts get _sendFacts => DiagnosticSendFacts(
    attempted: _sendAttempted,
    pendingAtTermination: _pendingAtTermination,
    deviceAcceptanceConfirmed: _sendSucceeded,
    dispatched: _sendSucceeded ? true : _commandFailure?.dispatched,
    localWriteCompleted: _sendSucceeded
        ? true
        : _commandFailure?.localWriteCompleted,
    localOkObserved: _sendSucceeded
        ? true
        : _commandFailure?.matchingResponseObserved,
    commandFailure: _commandFailure,
  );

  void _finish(
    DiagnosticTaskReason reason, [
    Object? error,
    StackTrace? stack,
  ]) {
    if (_terminal) return;
    _terminal = true;
    _reason = reason;
    _terminalStage = _stage;
    _pendingAtTermination = _sendPending;
    if (error != null) {
      _failure = DiagnosticTaskFailure(
        _stage,
        error,
        stack ?? StackTrace.current,
      );
    }
    _sessionFailure ??= session.lastFailure;
    _taskTimer?.cancel();
    _watch.stop();
    _cancelBusinessTimers();
    if (_owned) {
      _cleanupState = DiagnosticCleanupState.pending;
      // Close invalidates connect/send/read immediately, before any await/cancel.
      final closing = session.close();
      final observedClose = _observeCleanup(closing);
      _receiver?.stop(); // Its done Future was observed before activation.
      unawaited(_clean(observedClose));
    } else {
      _cleanupState = DiagnosticCleanupState.notRequired;
      _cleanup.complete(DiagnosticCleanupResult(_cleanupState, const []));
    }
    // All accepted core operations settle logically on close, independently of
    // native cleanup. Capture their frozen facts before publishing the snapshot.
    scheduleMicrotask(() {
      unawaited(_settle());
    });
  }

  Future<void> _settle() async {
    await Future.wait([
      ?_connecting,
      ?_startingReception,
      ?_sending,
      ?_receptionDone,
    ]);
    _done.complete(_result());
  }

  Future<void> _observeCleanup(Future<void> future) => future.then<void>(
    (_) {},
    onError: (Object error, StackTrace stack) {
      _cleanupFailures.add(DiagnosticTaskFailure(_terminalStage, error, stack));
    },
  );

  Future<void> _clean(Future<void> closing) async {
    // Cancel both owned application subscriptions even if native close failed.
    // Install every cancellation observer immediately.
    final entries = _entries;
    final events = _events;
    final cancellations = <Future<void>>[
      if (entries != null) _observeCleanup(Future.sync(entries.cancel)),
      if (events != null) _observeCleanup(Future.sync(events.cancel)),
    ];
    await closing;
    await Future.wait(cancellations);
    for (final failure in session.cleanupFailures) {
      if (!_cleanupFailures.any((f) => identical(f.cause, failure))) {
        _cleanupFailures.add(
          DiagnosticTaskFailure(_terminalStage, failure, failure.stackTrace),
        );
      }
    }
    _cleanupState = _cleanupFailures.isEmpty
        ? DiagnosticCleanupState.succeeded
        : DiagnosticCleanupState.failed;
    _cleanup.complete(DiagnosticCleanupResult(_cleanupState, _cleanupFailures));
  }
}
