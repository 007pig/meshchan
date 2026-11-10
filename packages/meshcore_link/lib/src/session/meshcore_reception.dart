part of 'meshcore_session.dart';

/// The first reason reception stopped scheduling reads and publishing entries.
/// A later failure during read settlement is recorded separately in the result.
enum MeshCoreReceptionStopReason {
  startRejected,
  stopped,
  subscriptionCanceled,
  durationElapsed,
  entryLimit,
  sessionClosed,
  sessionFailed,
}

/// Logical reception settlement, independent of stream delivery/native cleanup.
/// Published counts mean added to the stream, not processed or persisted.
final class MeshCoreReceptionResult {
  const MeshCoreReceptionResult._({
    required this.reason,
    required this.publishedEntries,
    required this.dispatchedReads,
    required this.completedReads,
    this.startError,
    this.commandFailure,
    this.sessionFailure,
  });

  final MeshCoreReceptionStopReason reason;
  final int publishedEntries;
  final int dispatchedReads;

  /// Dispatched reads settled with success or failure; excludes withdrawn reads.
  final int completedReads;
  final StateError? startError;
  final MeshCoreSessionCommandFailure? commandFailure;
  final MeshCoreSessionFailure? sessionFailure;

  @override
  String toString() =>
      'MeshCoreReceptionResult(${reason.name}, '
      'publishedEntries: $publishedEntries, dispatchedReads: $dispatchedReads, '
      'completedReads: $completedReads, commandFailure: $commandFailure, '
      'sessionFailure: $sessionFailure)';
}

/// Explicit, finite consumption of the session's shared device queue.
/// This also consumes ordinary chat, whose body is discarded by the codec.
/// The session retains sole ownership of its unpaused transport subscription.
final class MeshCoreReception {
  MeshCoreReception._(
    this._session,
    this.duration,
    this.maxEntries,
    this.maxReadsPerBatch,
  ) {
    if (duration <= Duration.zero) {
      throw ArgumentError('duration must be positive.');
    }
    if (maxEntries <= 0) {
      throw ArgumentError('maxEntries must be positive.');
    }
    if (maxReadsPerBatch <= 0) {
      throw ArgumentError('maxReadsPerBatch must be positive.');
    }
    _entries = StreamController<CompanionResponse>(
      onPause: _pause,
      onResume: _wake,
      onCancel: () =>
          _stop(MeshCoreReceptionStopReason.subscriptionCanceled)
              .then<void>((_) {}),
    );
  }

  final MeshCoreSession _session;
  final Duration duration;
  final int maxEntries;
  final int maxReadsPerBatch;
  late final StreamController<CompanionResponse> _entries;
  final _done = Completer<MeshCoreReceptionResult>();
  _ReceptionState _state = _ReceptionState.created;
  MeshCoreReceptionStopReason? _reason;
  StateError? _startError;
  MeshCoreSessionCommandFailure? _commandFailure;
  MeshCoreSessionFailure? _sessionFailure;
  Timer? _deadline;
  Timer? _batchTurn;
  bool _pumpScheduled = false;
  bool _demand = false;
  int _noticeGeneration = 0;
  int _readNoticeGeneration = 0;
  int _batchReads = 0;
  int _publishedEntries = 0;
  int _dispatchedReads = 0;
  int _completedReads = 0;
  _ReadyCommand? _read;

  /// Single-subscription, asynchronous typed observations. Only datagrams and
  /// ordinary-message summaries are added, at most [maxEntries] in total.
  /// Pause stops new reads, not input observation or the lifetime deadline.
  Stream<CompanionResponse> get entries => _entries.stream;

  /// Settles after the owned read, without awaiting a paused listener's done or
  /// transport cleanup. Expected termination is expressed as a result value.
  Future<MeshCoreReceptionResult> get done => _done.future;

  /// Enables once, after a listener is installed and the session is ready.
  /// This Future represents activation, not completion of the receive lifetime.
  Future<void> start() {
    if (_state != _ReceptionState.created) {
      return Future.error(StateError('This reception permits one start.'));
    }
    try {
      _session._requireReady();
      if (!_entries.hasListener) {
        throw StateError('Reception requires an entries listener.');
      }
      if (_session._reception != null) {
        throw StateError('A reception already owns the shared queue.');
      }
      if (_session._activeCommand?.kind == _RequestKind.readNextMessage ||
          _session._queuedCommands.any(
            (command) => command.kind == _RequestKind.readNextMessage,
          )) {
        throw StateError('An accepted manual read owns the shared queue.');
      }
    } on StateError catch (error, stack) {
      _startError = error;
      _stop(MeshCoreReceptionStopReason.startRejected);
      return Future.error(error, stack);
    }
    // Establish the lease, observation gate, and deadline atomically before
    // scheduling the sole initial check. A paused listener still consumes time.
    _session._reception = this;
    _state = _ReceptionState.running;
    _deadline = Timer(duration, () {
      _stop(MeshCoreReceptionStopReason.durationElapsed);
    });
    _demand = true;
    _wake();
    return Future.value();
  }

  /// Idempotently stops observation and new reads immediately. An already
  /// dispatched read retains its original matching and request deadline.
  Future<MeshCoreReceptionResult> stop() =>
      _stop(MeshCoreReceptionStopReason.stopped);

  bool get _running => _state == _ReceptionState.running;

  void _observe(CompanionResponse response) {
    if (!_running) return;
    if (response is MessageWaitingResponse) {
      _noticeGeneration++;
      _demand = true;
      _wake();
    } else if (response is ChannelDataResponse ||
        response is QueuedMessageResponse) {
      if (_publishedEntries >= maxEntries) return;
      _publishedEntries++;
      _entries.add(response);
      if (_publishedEntries == maxEntries) {
        _stop(MeshCoreReceptionStopReason.entryLimit);
      }
    }
  }

  void _pause() {
    if (!_running) return;
    _session._withdrawReceptionRead(this);
  }

  // A single demand bit is enough while user commands occupy the FIFO. Idle
  // transitions wake us; there is no polling or secondary command queue.
  void _wake() {
    if (!_running ||
        !_demand ||
        _entries.isPaused ||
        _read != null ||
        _pumpScheduled ||
        _batchTurn != null ||
        !_session._commandIdle) {
      return;
    }
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      if (!_running ||
          !_demand ||
          _entries.isPaused ||
          _read != null ||
          _batchTurn != null ||
          !_session._commandIdle) {
        return;
      }
      // Idle check and synchronous reservation share this decision, with no
      // await. Even capacity zero works without changing user admission rules.
      final command = _read = _session._enqueue(
        _RequestKind.readNextMessage,
        encodeSyncNextMessage(),
      );
      _demand = false;
      unawaited(
        command.completed.future.then<void>(
          (response) => _readSettled(command, response: response),
          onError: (Object error, StackTrace _) =>
              _readSettled(command, error: error),
        ),
      );
    });
  }

  void _readDispatched(_ReadyCommand command) {
    if (!identical(_read, command)) return;
    _dispatchedReads++;
    // This sequence is local notification coverage, not a wire request ID.
    _readNoticeGeneration = _noticeGeneration;
  }

  void _readSettled(
    _ReadyCommand command, {
    CompanionResponse? response,
    Object? error,
  }) {
    assert(identical(_read, command));
    _read = null;
    if (command.dispatched) _completedReads++;
    if (error is MeshCoreSessionCommandFailure) {
      _commandFailure = error;
      _sessionFailure ??= error.sessionFailure;
    }
    // Settlement must run even after stopping or after success was committed
    // before this continuation. It alone releases ownership of this read.
    if (!_running) {
      _finishStop();
      return;
    }
    if (error is _ReceptionReadWithdrawn) {
      _demand = true;
      _wake();
      return;
    }
    // Session invalidation stops us before command errors.
    assert(error == null);
    _batchReads++;
    _demand =
        response is! NoMoreMessagesResponse ||
        _noticeGeneration != _readNoticeGeneration;
    if (!_demand) {
      _batchReads = 0;
    } else if (_batchReads >= maxReadsPerBatch) {
      _batchReads = 0;
      // A real event turn bounds even a chain of immediately satisfied reads.
      // Waiting notices, idle wakeups, and resume cannot bypass this barrier.
      _batchTurn = Timer(Duration.zero, () {
        _batchTurn = null;
        _wake();
      });
    } else {
      _wake();
    }
  }

  void _sessionTerminated(MeshCoreSessionFailure failure) {
    _sessionFailure ??= failure;
    _stop(
      failure.kind == MeshCoreSessionFailureKind.canceled
          ? MeshCoreReceptionStopReason.sessionClosed
          : MeshCoreReceptionStopReason.sessionFailed,
    );
  }

  Future<MeshCoreReceptionResult> _stop(MeshCoreReceptionStopReason reason) {
    if (_state == _ReceptionState.stopped ||
        _state == _ReceptionState.stopping) {
      return done;
    }
    _reason = reason;
    _state = _ReceptionState.stopping;
    _demand = false;
    _deadline?.cancel();
    _batchTurn?.cancel();
    _batchTurn = null;
    _session._withdrawReceptionRead(this);
    // close can wait forever for a paused/absent listener. Observe it without
    // making logical settlement or onCancel depend on that same Future.
    _entries.close().ignore();
    _finishStop();
    return done;
  }

  void _finishStop() {
    if (_state != _ReceptionState.stopping || _read != null) return;
    if (identical(_session._reception, this)) _session._reception = null;
    _state = _ReceptionState.stopped;
    _done.complete(
      MeshCoreReceptionResult._(
        reason: _reason!,
        publishedEntries: _publishedEntries,
        dispatchedReads: _dispatchedReads,
        completedReads: _completedReads,
        startError: _startError,
        commandFailure: _commandFailure,
        sessionFailure: _sessionFailure,
      ),
    );
  }
}

enum _ReceptionState { created, running, stopping, stopped }

final class _ReceptionReadWithdrawn implements Exception {
  const _ReceptionReadWithdrawn();
}
