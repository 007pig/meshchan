part of 'diagnostic_tasks.dart';

/// A finite targeted responder with at most one unsettled PONG. An acknowledged
/// local response does not prove the remote peer received it.
final class MeshchanResponderTask
    extends _DiagnosticTask<DiagnosticResponderResult> {
  MeshchanResponderTask({
    required MeshCoreSession session,
    required DiagnosticTaskOptions options,
    required this.listenDuration,
    this.maxResponses = 1,
    Duration Function()? elapsed,
  }) : super(session, options, elapsed);

  final Duration listenDuration;
  final int maxResponses;
  final _cache = DiagnosticRequestCache();
  Timer? _listenTimer;
  Timer? _yieldTimer;
  Duration? _listenDeadline;
  DiagnosticListenStopReason? _listenStop;
  int _attempts = 0;
  int _confirmed = 0;
  int _duplicates = 0;
  int _conflicts = 0;
  int _cacheCapacity = 0;
  int _returnCapacity = 0;
  int _batchEntries = 0;

  @override
  void _validate() {
    _positive(listenDuration, 'listenDuration');
    if (maxResponses <= 0) {
      throw ArgumentError('maxResponses must be positive.');
    }
  }

  @override
  void _ready() {
    final now = _now;
    _listenDeadline = now + listenDuration;
    _listenTimer = Timer(_timerDelay(listenDuration), () {
      if (_check()) _stopListening(DiagnosticListenStopReason.durationElapsed);
    });
    final remaining = options.taskTimeout - now;
    _receiveFor(listenDuration < remaining ? listenDuration : remaining, () {});
  }

  bool _canProcess() {
    if (!_check()) return false;
    if (_listenDeadline != null && _now >= _listenDeadline!) {
      _stopListening(DiagnosticListenStopReason.durationElapsed);
      return false;
    }
    return _attempts < maxResponses &&
        (_listenStop == null ||
            _listenStop == DiagnosticListenStopReason.entryLimit);
  }

  @override
  void _entry(CompanionResponse entry) {
    if (!_canProcess()) return;
    _processed++;
    _batchEntries++;
    if (entry is ChannelDataResponse) {
      final pong = createDiagnosticPong(
        datagram: entry,
        expectedReceiveChannelIndex: options.receiveChannelIndex,
        localTestId: options.localTestId,
        peerTestId: options.peerTestId,
      );
      if (pong != null) {
        if (pong.content.length >
            maxDiagnosticContentLengthForRoute(
              routeDescriptor: options.routeDescriptor,
              path: options.path,
            )) {
          _returnCapacity++;
        } else {
          if (!_canProcess()) return;
          final ping = classifyDiagnosticDatagram(entry).message!;
          final key = DiagnosticRequestKey(options.receiveChannelIndex, ping);
          switch (_cache.reserve(key, ping.content, _now)) {
            case DiagnosticCacheAdmission.duplicate:
              _duplicates++;
            case DiagnosticCacheAdmission.conflict:
              _conflicts++;
            case DiagnosticCacheAdmission.capacity:
              _cacheCapacity++;
            case DiagnosticCacheAdmission.accepted:
              // Reservation, attempt budget, pause, and send are atomic with
              // respect to callbacks. No async listener or second request queue.
              _attempts++;
              _entries!.pause();
              _send(pong, () {
                _cache.settle(key);
                _stage = DiagnosticTaskStage.settling;
                if (_canProcess()) _yield();
                _receptionProgress();
              }, localSuccess: () => _confirmed++);
              if (_attempts == maxResponses) {
                _stopListening(DiagnosticListenStopReason.responseLimit);
              }
              return;
          }
        }
      }
    }
    // Bounded fairness for buffered unrelated entries as well as responses.
    if (_batchEntries >= 8) {
      _entries!.pause();
      _yield();
    }
  }

  void _yield() {
    if (_terminal || _yieldTimer != null) return;
    _yieldTimer = Timer(Duration.zero, () {
      _yieldTimer = null;
      _batchEntries = 0;
      // Entry-limit reception may already be stopped/done. Its finite published
      // buffer still has to drain; do not require a running receiver here.
      if (!_sendPending && _canProcess()) _entries!.resume();
    });
  }

  void _stopListening(DiagnosticListenStopReason reason) {
    if (_terminal) return;
    _listenStop ??= reason;
    _stage = DiagnosticTaskStage.settling;
    _listenTimer?.cancel();
    // Entry-limit drains its published buffer. Duration/response limit closes
    // admission immediately and waits only for accepted work/read settlement.
    if (_listenStop != DiagnosticListenStopReason.entryLimit) {
      _yieldTimer?.cancel();
      _yieldTimer = null;
    }
    _receiver?.stop();
    _receptionProgress();
  }

  @override
  void _receptionProgress() {
    if (_terminal || !_check()) return;
    final result = _receptionResult;
    if (_listenStop == null && result != null) {
      if (result.reason == MeshCoreReceptionStopReason.entryLimit) {
        _listenStop = DiagnosticListenStopReason.entryLimit;
      } else if (result.reason == MeshCoreReceptionStopReason.durationElapsed) {
        _listenStop = DiagnosticListenStopReason.durationElapsed;
      }
    }
    // Even if entryLimit occurred first, the application listen deadline gates
    // any buffered entries and permits finishing without draining after expiry.
    final listeningExpired =
        _listenDeadline != null && _now >= _listenDeadline!;
    if (_listenStop == null && listeningExpired) {
      _stopListening(DiagnosticListenStopReason.durationElapsed);
      return;
    }
    if (_listenStop == null || result == null || _sendPending) return;
    if (_listenStop == DiagnosticListenStopReason.entryLimit &&
        !_entriesEnded &&
        !listeningExpired &&
        _attempts < maxResponses) {
      return;
    }
    if (_readyToCommit()) _finish(DiagnosticTaskReason.completed);
  }

  @override
  void _cancelBusinessTimers() {
    _listenTimer?.cancel();
    _yieldTimer?.cancel();
    _cache.clear();
  }

  @override
  DiagnosticResponderResult _result() => DiagnosticResponderResult(
    reason: _reason,
    stage: _terminalStage,
    send: _sendFacts,
    processedEntries: _processed,
    failure: _failure,
    sessionInfo: session.info,
    sessionFailure: _sessionFailure,
    reception: _receptionResult,
    listenStopReason:
        _listenStop ??
        (_receptionResult?.reason == MeshCoreReceptionStopReason.entryLimit
            ? DiagnosticListenStopReason.entryLimit
            : null),
    responseAttempts: _attempts,
    localResponsesConfirmed: _confirmed,
    duplicates: _duplicates,
    conflicts: _conflicts,
    cacheCapacityRejections: _cacheCapacity,
    returnCapacityRejections: _returnCapacity,
  );
}
