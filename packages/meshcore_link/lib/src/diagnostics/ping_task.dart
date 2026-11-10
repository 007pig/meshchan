part of 'diagnostic_tasks.dart';

/// One secure run, one send, and one exact application response. No retries.
/// Construction/getters are inert. Use a new transport/session for each task.
final class MeshchanPingTask extends _DiagnosticTask<DiagnosticPingResult> {
  MeshchanPingTask({
    required MeshCoreSession session,
    required DiagnosticTaskOptions options,
    required Uint8List content,
    required this.responseTimeout,
    Uint8List Function()? nonceFactory,
    Duration Function()? elapsed,
  }) : _content = Uint8List.fromList(content).asUnmodifiableView(),
       _nonceFactory = nonceFactory ?? _secureNonce,
       super(session, options, elapsed);

  final Uint8List _content;
  final Duration responseTimeout;
  final Uint8List Function() _nonceFactory;
  late MeshchanDiagnosticMessage _ping;
  Timer? _responseTimer;
  Duration? _sendOrigin;
  Duration? _responseDeadline;
  Duration? _firstPong;
  int _duplicates = 0;

  static Uint8List _secureNonce() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  }

  @override
  void _validate() {
    _positive(responseTimeout, 'responseTimeout');
    if (_content.length >
        maxDiagnosticContentLengthForRoute(
          routeDescriptor: options.routeDescriptor,
          path: options.path,
        )) {
      throw ArgumentError('Content exceeds the configured route capacity.');
    }
  }

  @override
  void _prepare() {
    _stage = DiagnosticTaskStage.nonceGeneration;
    _ping = MeshchanDiagnosticMessage(
      kind: DiagnosticKind.ping,
      runNonce: _nonceFactory(),
      requestId: 1,
      senderTestId: options.localTestId,
      targetTestId: options.peerTestId,
      content: _content,
    );
  }

  @override
  DiagnosticTaskReason? _expired(Duration now) {
    final remote = _responseDeadline;
    // Equal deadlines consistently favor the whole-task budget. An observed
    // PONG retires the remote deadline, including during local send settlement.
    if (_firstPong == null &&
        remote != null &&
        now >= remote &&
        remote < options.taskTimeout) {
      return DiagnosticTaskReason.responseTimeout;
    }
    return super._expired(now);
  }

  @override
  void _ready() {
    _receiveFor(options.taskTimeout - _now, () {
      // Active correlation context and time origin precede the high-level send
      // in this synchronous segment, including FIFO waiting in application RTT.
      _sendOrigin = _now;
      _responseDeadline = _sendOrigin! + responseTimeout;
      _responseTimer = Timer(_timerDelay(responseTimeout), () => _check());
      _send(_ping, () {
        _stage = DiagnosticTaskStage.waiting;
        _maybeSucceed();
      });
    });
  }

  @override
  void _entry(CompanionResponse entry) {
    _processed++;
    if (_sendOrigin == null || entry is! ChannelDataResponse) return;
    if (!matchesDiagnosticPong(
      expectedPing: _ping,
      datagram: entry,
      expectedReceiveChannelIndex: options.receiveChannelIndex,
    )) {
      return;
    }
    if (!_check()) return;
    if (_firstPong != null) {
      _duplicates++;
      return;
    }
    _firstPong = _now - _sendOrigin!;
    _responseTimer?.cancel();
    _maybeSucceed();
  }

  void _maybeSucceed() {
    if (_firstPong != null && _sendSucceeded && _readyToCommit()) {
      _finish(DiagnosticTaskReason.completed);
    }
  }

  @override
  void _receptionProgress() {
    final result = _receptionResult;
    if (result == null || !_entriesEnded) return;
    if (result.reason == MeshCoreReceptionStopReason.entryLimit &&
        _firstPong == null) {
      _finish(DiagnosticTaskReason.entryLimit);
    }
    // A last-entry PONG can still be waiting for its local send to settle.
  }

  @override
  void _cancelBusinessTimers() => _responseTimer?.cancel();

  @override
  DiagnosticPingResult _result() => DiagnosticPingResult(
    reason: _reason,
    stage: _terminalStage,
    send: _sendFacts,
    processedEntries: _processed,
    failure: _failure,
    sessionInfo: session.info,
    sessionFailure: _sessionFailure,
    reception: _receptionResult,
    firstMatchingPongElapsed: _firstPong,
    matchingPongDuplicates: _duplicates,
  );
}
