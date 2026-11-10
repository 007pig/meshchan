import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../protocol/companion_messages.dart';
import '../transport/companion_transport.dart';

/// Meshchan's minimal initialization policy, not full protocol-version support.
const meshCoreSessionAppTargetVersion = 3;

enum MeshCoreSessionState {
  idle,
  opening,
  initializing,
  ready,
  closing,
  closed,
  failed,
}

enum MeshCoreSessionFailureKind {
  transport,
  protocol,
  deviceRejected,
  requestTimeout,
  initializationTimeout,
  disconnected,
  canceled,
  cleanup,
}

/// Complete initialization data. After termination this is historical data;
/// only [MeshCoreSessionState.ready] means the session is currently usable.
final class MeshCoreSessionInfo {
  const MeshCoreSessionInfo._(this.deviceInfo, this.selfInfo);

  final DeviceInfoResponse deviceInfo;
  final SelfInfoResponse selfInfo;
  int get appTargetVersion => meshCoreSessionAppTargetVersion;

  @override
  String toString() =>
      'MeshCoreSessionInfo(appTargetVersion: $appTargetVersion, '
      'protocolVersion: ${deviceInfo.protocolVersion})';
}

/// Structural diagnostic. Explicit debugging can inspect [cause] and
/// [stackTrace]; the default summary never formats the original cause.
final class MeshCoreSessionFailure implements Exception {
  const MeshCoreSessionFailure._(
    this.kind, {
    required this.stage,
    this.commandOpcode,
    this.expectedResponseOpcode,
    this.deviceErrorCode,
    this.deviceErrorName,
    this.cause,
    required this.stackTrace,
  });

  final MeshCoreSessionFailureKind kind;
  final MeshCoreSessionState stage;
  final int? commandOpcode;
  final int? expectedResponseOpcode;
  final int? deviceErrorCode;
  final String? deviceErrorName;
  final Object? cause;
  final StackTrace stackTrace;

  @override
  String toString() =>
      'MeshCoreSessionFailure(${kind.name}, stage: ${stage.name}, '
      'commandOpcode: $commandOpcode, '
      'expectedResponseOpcode: $expectedResponseOpcode, '
      'deviceErrorCode: $deviceErrorCode)';
}

/// Local admission failure. Existing commands and the session remain usable.
final class MeshCoreSessionQueueFull implements Exception {
  const MeshCoreSessionQueueFull._(this.maxQueuedCommands);

  final int maxQueuedCommands;

  @override
  String toString() =>
      'MeshCoreSessionQueueFull(maxQueuedCommands: $maxQueuedCommands)';
}

/// Frozen facts about this command when the session terminated it.
/// A false [localWriteCompleted] does not prove that no bytes reached the device.
/// [sessionFailure] can describe a different command that failed ahead of this one.
final class MeshCoreSessionCommandFailure implements Exception {
  MeshCoreSessionCommandFailure._(_ReadyCommand command, this.sessionFailure)
    : commandOpcode = command.kind.commandOpcode,
      dispatched = command.dispatched,
      localWriteCompleted = command.localWriteCompleted,
      matchingResponseObserved = command.matchingResponseObserved;

  final int commandOpcode;
  final bool dispatched;
  final bool localWriteCompleted;
  final bool matchingResponseObserved;
  final MeshCoreSessionFailure sessionFailure;

  @override
  String toString() =>
      'MeshCoreSessionCommandFailure(commandOpcode: $commandOpcode, '
      'dispatched: $dispatched, localWriteCompleted: $localWriteCompleted, '
      'matchingResponseObserved: $matchingResponseObserved, '
      'sessionFailure: $sessionFailure)';
}

sealed class MeshCoreSessionEvent {
  const MeshCoreSessionEvent._();
}

final class MeshCoreSessionStateChanged extends MeshCoreSessionEvent {
  const MeshCoreSessionStateChanged._(this.previous, this.state) : super._();

  final MeshCoreSessionState previous;
  final MeshCoreSessionState state;

  @override
  String toString() => 'MeshCoreSessionStateChanged(${state.name})';
}

/// An unhandled, wrong-type, duplicate, or unassociated device-error summary.
/// No payload or device display text is retained.
final class MeshCoreSessionUnassociatedResponse extends MeshCoreSessionEvent {
  MeshCoreSessionUnassociatedResponse._(CompanionResponse response, this.stage)
    : opcode = response.opcode,
      contentLength = response.contentLength,
      deviceErrorCode = response is DeviceErrorResponse
          ? response.errorCode
          : null,
      deviceErrorName = response is DeviceErrorResponse
          ? response.knownName
          : null,
      super._();

  final int opcode;
  final int contentLength;
  final MeshCoreSessionState stage;
  final int? deviceErrorCode;
  final String? deviceErrorName;

  @override
  String toString() =>
      'MeshCoreSessionUnassociatedResponse(opcode: $opcode, '
      'contentLength: $contentLength, stage: ${stage.name}, '
      'deviceErrorCode: $deviceErrorCode)';
}

final class MeshCoreSessionFailed extends MeshCoreSessionEvent {
  const MeshCoreSessionFailed._(this.failure) : super._();

  final MeshCoreSessionFailure failure;

  @override
  String toString() => 'MeshCoreSessionFailed($failure)';
}

/// One initialization attempt, exclusively owning an unused [CompanionTransport].
/// Construction and event observation perform no I/O. Retry with a new transport
/// and session. Ready commands share one bounded FIFO without retries.
final class MeshCoreSession {
  MeshCoreSession({
    required this._transport,
    String appName = 'Meshchan',
    this.requestTimeout = const Duration(seconds: 5),
    this.initializationTimeout = const Duration(seconds: 15),
    this.startupDelay = Duration.zero,
    this.maxQueuedCommands = 8,
  }) : _appStart = encodeAppStart(appName: appName),
       _deviceQuery = encodeDeviceQuery(
         appTargetVersion: meshCoreSessionAppTargetVersion,
       ) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('requestTimeout must be positive.');
    }
    if (initializationTimeout <= Duration.zero) {
      throw ArgumentError('initializationTimeout must be positive.');
    }
    if (startupDelay < Duration.zero) {
      throw ArgumentError('startupDelay must not be negative.');
    }
    if (maxQueuedCommands < 0) {
      throw ArgumentError('maxQueuedCommands must not be negative.');
    }
  }

  final CompanionTransport _transport;
  final Uint8List _appStart;
  final Uint8List _deviceQuery;
  final Duration requestTimeout;
  final Duration initializationTimeout;
  final Duration startupDelay;

  /// Waiting commands only, excluding the one active or reserved command.
  /// Zero permits an idle command but rejects waiting behind an active command.
  /// This is a local resource policy, not the firmware inbox capacity.
  final int maxQueuedCommands;
  final _events = StreamController<MeshCoreSessionEvent>.broadcast();
  MeshCoreSessionState _state = MeshCoreSessionState.idle;
  MeshCoreSessionInfo? _info;
  MeshCoreSessionFailure? _lastFailure;
  final List<MeshCoreSessionFailure> _cleanupFailures = [];
  StreamSubscription<Uint8List>? _subscription;
  Completer<MeshCoreSessionInfo>? _connecting;
  Future<void>? _closing;
  Timer? _initializationTimer;
  Timer? _startupTimer;
  _PendingRequest? _pending;
  final _queuedCommands = Queue<_ReadyCommand>();
  _ReadyCommand? _activeCommand;
  int _requestId = 0;
  DeviceInfoResponse? _deviceInfo;

  MeshCoreSessionState get state => _state;
  MeshCoreSessionInfo? get info => _info;
  MeshCoreSessionFailure? get lastFailure => _lastFailure;
  List<MeshCoreSessionFailure> get cleanupFailures =>
      List.unmodifiable(_cleanupFailures);

  /// Asynchronous broadcast data events; observers do not own the transport.
  /// No history is cached without listeners. Paused observers buffer their own
  /// events and should cancel when no longer needed.
  Stream<MeshCoreSessionEvent> get events => _events.stream;

  bool get _active =>
      _state == MeshCoreSessionState.opening ||
      _state == MeshCoreSessionState.initializing ||
      _state == MeshCoreSessionState.ready;

  /// Sends owned inner content using the existing codec. Success requires both
  /// local write completion and the first OK; it proves no wireless delivery.
  /// Parameters are validated and copied before any asynchronous waiting.
  ///
  /// Returned Future errors are [StateError] outside ready, codec [ArgumentError]
  /// or [RangeError] for invalid input, [MeshCoreSessionQueueFull] on admission,
  /// and [MeshCoreSessionCommandFailure] after an accepted command terminates.
  Future<OkResponse> sendChannelData({
    required int channelIndex,
    required int dataType,
    required int routeDescriptor,
    required Uint8List path,
    required Uint8List payload,
  }) {
    try {
      _requireReady();
      final content = encodeSendChannelData(
        channelIndex: channelIndex,
        dataType: dataType,
        routeDescriptor: routeDescriptor,
        path: path,
        payload: payload,
      );
      return _enqueue(
        _RequestKind.sendChannelData,
        content,
      ).then((response) => response as OkResponse);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  /// Consumes one shared device-queue entry with exactly one command.
  /// Success returns [ChannelDataResponse], [QueuedMessageResponse] (structure
  /// only, discarding ordinary chat text), or [NoMoreMessagesResponse]. This is
  /// not a peek and never automatically reads again, including after 0x83.
  /// Requires both local write completion and the first permitted result.
  ///
  /// Returned Future errors are [StateError] outside ready,
  /// [MeshCoreSessionQueueFull] on admission, or [MeshCoreSessionCommandFailure]
  /// when an accepted command is terminated. [close] cancels all accepted work.
  Future<CompanionResponse> readNextMessage() {
    try {
      _requireReady();
      return _enqueue(_RequestKind.readNextMessage, encodeSyncNextMessage());
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  void _requireReady() {
    if (_state != MeshCoreSessionState.ready) {
      throw StateError('Commands require a ready session.');
    }
  }

  Future<CompanionResponse> _enqueue(_RequestKind kind, Uint8List content) {
    if (_activeCommand != null && _queuedCommands.length >= maxQueuedCommands) {
      throw MeshCoreSessionQueueFull._(maxQueuedCommands);
    }
    final command = _ReadyCommand(kind, content);
    if (_activeCommand == null) {
      // Reserve immediately, including before the first dispatch microtask.
      _scheduleCommand(command);
    } else {
      _queuedCommands.addLast(command);
    }
    return command.completed.future;
  }

  void _scheduleCommand(_ReadyCommand command) {
    _activeCommand = command;
    final token = _requestId;
    scheduleMicrotask(() {
      if (_state != MeshCoreSessionState.ready ||
          token != _requestId ||
          !identical(_activeCommand, command)) {
        return;
      }
      // Reservation alone cannot match input. Register and send synchronously.
      _send(command.content, command.kind, command: command);
    });
  }

  Future<MeshCoreSessionInfo> connect() {
    if (_state != MeshCoreSessionState.idle || _connecting != null) {
      return Future.error(
        StateError('This session permits one connect attempt.'),
      );
    }
    final connecting = _connecting = Completer<MeshCoreSessionInfo>();
    _setState(MeshCoreSessionState.opening);
    try {
      _subscription = _transport.frames.listen(
        _receive,
        onError: (Object error, StackTrace stack) =>
            _fail(_failure(MeshCoreSessionFailureKind.transport, error, stack)),
        onDone: () => _fail(_failure(MeshCoreSessionFailureKind.disconnected)),
      );
      _initializationTimer = Timer(initializationTimeout, () {
        _fail(_failure(MeshCoreSessionFailureKind.initializationTimeout));
      });
      // Future.sync observes both synchronous throws and eventual async errors.
      unawaited(
        Future.sync(_transport.open).then<void>(
          (_) => _opened(),
          onError: (Object error, StackTrace stack) => _fail(
            _failure(MeshCoreSessionFailureKind.transport, error, stack),
          ),
        ),
      );
    } catch (error, stack) {
      _fail(_failure(MeshCoreSessionFailureKind.transport, error, stack));
    }
    return connecting.future;
  }

  void _opened() {
    if (_state != MeshCoreSessionState.opening) return;
    _setState(MeshCoreSessionState.initializing);
    if (startupDelay == Duration.zero) {
      _send(_deviceQuery, _RequestKind.deviceQuery);
    } else {
      _startupTimer = Timer(startupDelay, () {
        if (_state == MeshCoreSessionState.initializing) {
          _send(_deviceQuery, _RequestKind.deviceQuery);
        }
      });
    }
  }

  void _send(Uint8List content, _RequestKind kind, {_ReadyCommand? command}) {
    if (_state != kind.stage) return;
    assert(_pending == null);
    final pending = _pending = _PendingRequest(++_requestId, kind, command);
    pending.timer = Timer(requestTimeout, () {
      if (_isCurrent(pending)) {
        _fail(_failure(MeshCoreSessionFailureKind.requestTimeout));
      }
    });
    unawaited(
      Future.sync(() {
        command?.dispatched = true;
        return _transport.sendFrame(content);
      }).then<void>(
        (_) {
          if (!_isCurrent(pending)) return;
          pending.sent = true;
          command?.localWriteCompleted = true;
          _completeRequest(pending);
        },
        onError: (Object error, StackTrace stack) {
          if (_isCurrent(pending)) {
            _fail(_failure(MeshCoreSessionFailureKind.transport, error, stack));
          }
        },
      ),
    );
  }

  bool _isCurrent(_PendingRequest pending) =>
      _state == pending.kind.stage && identical(_pending, pending);

  void _receive(Uint8List content) {
    if (!_active) return;
    final CompanionResponse response;
    try {
      response = decodeCompanionResponse(content);
    } on CompanionProtocolException catch (error, stack) {
      _fail(_failure(MeshCoreSessionFailureKind.protocol, error, stack));
      return;
    }
    final pending = _pending;
    if (response is DeviceErrorResponse && pending != null) {
      _fail(_failure(MeshCoreSessionFailureKind.deviceRejected, response));
    } else if (pending != null &&
        pending.accepts(response) &&
        pending.response == null) {
      pending.response = response;
      pending.command?.matchingResponseObserved = true;
      _completeRequest(pending);
    } else {
      _emit(MeshCoreSessionUnassociatedResponse._(response, _state));
    }
  }

  void _completeRequest(_PendingRequest pending) {
    if (!_isCurrent(pending) || !pending.sent || pending.response == null) {
      return;
    }
    pending.timer?.cancel();
    if (pending.command case final command?) {
      // Commit success before releasing the record: close cannot strand its
      // Future or change an already committed result in the pump window.
      command.completed.complete(pending.response!);
      _pending = null;
      _activeCommand = null;
      if (_queuedCommands.isNotEmpty) {
        _scheduleCommand(_queuedCommands.removeFirst());
      }
      return;
    }
    _pending = null;
    // Advance outside a receive callback, including a synchronous fake stream.
    // The local token isolates continuations; it is not a wire request ID.
    scheduleMicrotask(() {
      if (_state != MeshCoreSessionState.initializing ||
          pending.id != _requestId) {
        return;
      }
      final response = pending.response!;
      if (response is DeviceInfoResponse) {
        _deviceInfo = response;
        _send(_appStart, _RequestKind.appStart);
      } else {
        _info = MeshCoreSessionInfo._(
          _deviceInfo!,
          response as SelfInfoResponse,
        );
        _initializationTimer?.cancel();
        _setState(MeshCoreSessionState.ready);
        _connecting!.complete(_info!);
      }
    });
  }

  MeshCoreSessionFailure _failure(
    MeshCoreSessionFailureKind kind, [
    Object? cause,
    StackTrace? stack,
  ]) => MeshCoreSessionFailure._(
    kind,
    stage: _state,
    commandOpcode: _pending?.kind.commandOpcode,
    expectedResponseOpcode: _pending?.kind.expectedOpcode,
    deviceErrorCode: cause is DeviceErrorResponse ? cause.errorCode : null,
    deviceErrorName: cause is DeviceErrorResponse ? cause.knownName : null,
    cause: cause,
    stackTrace: stack ?? StackTrace.current,
  );

  void _fail(MeshCoreSessionFailure failure) {
    if (!_active) return;
    _lastFailure = failure;
    _setState(MeshCoreSessionState.failed);
    _invalidate(failure);
    _finishConnectWithError(failure);
    _emit(MeshCoreSessionFailed._(failure));
    _beginCleanup();
  }

  void _invalidate(MeshCoreSessionFailure failure) {
    _initializationTimer?.cancel();
    _startupTimer?.cancel();
    _pending?.timer?.cancel();
    if (_activeCommand case final command?) {
      _terminateCommand(command, failure);
    }
    for (final command in _queuedCommands) {
      _terminateCommand(command, failure);
    }
    _activeCommand = null;
    _queuedCommands.clear();
    _pending?.response = null;
    _pending = null;
    _deviceInfo = null;
    _requestId++;
  }

  void _terminateCommand(
    _ReadyCommand command,
    MeshCoreSessionFailure failure,
  ) {
    command.completed.completeError(
      MeshCoreSessionCommandFailure._(command, failure),
      failure.stackTrace,
    );
  }

  void _finishConnectWithError(MeshCoreSessionFailure failure) {
    final connecting = _connecting;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(failure, failure.stackTrace);
    }
  }

  /// Shared cleanup result. This can remain pending while the transport waits
  /// for native exit confirmation. Logical connect/command failure does not
  /// await it. Accepted commands fail promptly with frozen cancellation facts.
  Future<void> close() {
    if (_closing case final closing?) return closing;
    final canceled = _failure(MeshCoreSessionFailureKind.canceled);
    _setState(MeshCoreSessionState.closing);
    _invalidate(canceled);
    _finishConnectWithError(canceled);
    return _beginCleanup();
  }

  Future<void> _beginCleanup() {
    if (_closing case final closing?) return closing;
    final completed = Completer<void>();
    final closing = _closing = completed.future;
    // Observe automatic cleanup without hiding the same result from close().
    unawaited(closing.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    unawaited(
      _cleanup().then<void>(
        (_) => completed.complete(),
        onError: (Object error, StackTrace stack) =>
            completed.completeError(error, stack),
      ),
    );
    return closing;
  }

  Future<void> _cleanup() async {
    // Keep reception alive and unpaused until transport cleanup settles.
    try {
      await _transport.close();
    } catch (error, stack) {
      _recordCleanupFailure(error, stack);
    }
    try {
      await _subscription?.cancel();
    } catch (error, stack) {
      _recordCleanupFailure(error, stack);
    }
    if (_state == MeshCoreSessionState.closing) {
      _setState(MeshCoreSessionState.closed);
    }
    // A paused observer must not hold transport cleanup or close() hostage.
    unawaited(
      _events.close().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            _recordCleanupFailure(error, stack),
      ),
    );
    if (_cleanupFailures.isNotEmpty) {
      final failure = _cleanupFailures.first;
      Error.throwWithStackTrace(failure, failure.stackTrace);
    }
  }

  void _recordCleanupFailure(Object error, StackTrace stack) {
    final failure = _failure(MeshCoreSessionFailureKind.cleanup, error, stack);
    _cleanupFailures.add(failure);
    if (_lastFailure == null) {
      _lastFailure = failure;
      _setState(MeshCoreSessionState.failed);
    }
    _emit(MeshCoreSessionFailed._(failure));
  }

  void _setState(MeshCoreSessionState state) {
    final previous = _state;
    _state = state;
    _emit(MeshCoreSessionStateChanged._(previous, state));
  }

  void _emit(MeshCoreSessionEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

enum _RequestKind {
  deviceQuery(0x16, 0x0d, MeshCoreSessionState.initializing),
  appStart(0x01, 0x05, MeshCoreSessionState.initializing),
  sendChannelData(0x3e, 0x00, MeshCoreSessionState.ready),
  readNextMessage(0x0a, null, MeshCoreSessionState.ready);

  const _RequestKind(this.commandOpcode, this.expectedOpcode, this.stage);

  final int commandOpcode;
  final int? expectedOpcode;
  final MeshCoreSessionState stage;
}

final class _ReadyCommand {
  _ReadyCommand(this.kind, this.content);

  final _RequestKind kind;
  final Uint8List content;
  final completed = Completer<CompanionResponse>();
  bool dispatched = false;
  bool localWriteCompleted = false;
  bool matchingResponseObserved = false;
}

final class _PendingRequest {
  _PendingRequest(this.id, this.kind, this.command);

  final int id;
  final _RequestKind kind;
  final _ReadyCommand? command;
  Timer? timer;
  bool sent = false;
  CompanionResponse? response;

  bool accepts(CompanionResponse response) => switch (kind) {
    _RequestKind.deviceQuery => response is DeviceInfoResponse,
    _RequestKind.appStart => response is SelfInfoResponse,
    _RequestKind.sendChannelData => response is OkResponse,
    _RequestKind.readNextMessage =>
      response is ChannelDataResponse ||
          response is QueuedMessageResponse ||
          response is NoMoreMessagesResponse,
  };
}
