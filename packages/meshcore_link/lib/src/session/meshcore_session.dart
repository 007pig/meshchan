import 'dart:async';
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
/// and session. There is no public command queue, retry, or reconnection API.
final class MeshCoreSession {
  MeshCoreSession({
    required this._transport,
    String appName = 'Meshchan',
    this.requestTimeout = const Duration(seconds: 5),
    this.initializationTimeout = const Duration(seconds: 15),
    this.startupDelay = Duration.zero,
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
  }

  final CompanionTransport _transport;
  final Uint8List _appStart;
  final Uint8List _deviceQuery;
  final Duration requestTimeout;
  final Duration initializationTimeout;
  final Duration startupDelay;
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
      _send(_deviceQuery, 0x0d);
    } else {
      _startupTimer = Timer(startupDelay, () {
        if (_state == MeshCoreSessionState.initializing) {
          _send(_deviceQuery, 0x0d);
        }
      });
    }
  }

  void _send(Uint8List content, int expectedOpcode) {
    if (_state != MeshCoreSessionState.initializing) return;
    assert(_pending == null);
    final pending = _pending = _PendingRequest(
      ++_requestId,
      content[0],
      expectedOpcode,
    );
    pending.timer = Timer(requestTimeout, () {
      if (_isCurrent(pending)) {
        _fail(_failure(MeshCoreSessionFailureKind.requestTimeout));
      }
    });
    unawaited(
      Future.sync(() => _transport.sendFrame(content)).then<void>(
        (_) {
          if (!_isCurrent(pending)) return;
          pending.sent = true;
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
      _state == MeshCoreSessionState.initializing &&
      identical(_pending, pending);

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
        _send(_appStart, 0x05);
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
    commandOpcode: _pending?.commandOpcode,
    expectedResponseOpcode: _pending?.expectedOpcode,
    deviceErrorCode: cause is DeviceErrorResponse ? cause.errorCode : null,
    deviceErrorName: cause is DeviceErrorResponse ? cause.knownName : null,
    cause: cause,
    stackTrace: stack ?? StackTrace.current,
  );

  void _fail(MeshCoreSessionFailure failure) {
    if (!_active) return;
    _lastFailure = failure;
    _setState(MeshCoreSessionState.failed);
    _invalidate();
    _finishConnectWithError(failure);
    _emit(MeshCoreSessionFailed._(failure));
    _beginCleanup();
  }

  void _invalidate() {
    _initializationTimer?.cancel();
    _startupTimer?.cancel();
    _pending?.timer?.cancel();
    _pending = null;
    _deviceInfo = null;
    _requestId++;
  }

  void _finishConnectWithError(MeshCoreSessionFailure failure) {
    final connecting = _connecting;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(failure, failure.stackTrace);
    }
  }

  /// Shared cleanup result. This can remain pending while the transport waits
  /// for native exit confirmation. Logical connect failure does not await it.
  Future<void> close() {
    if (_closing case final closing?) return closing;
    final canceled = _failure(MeshCoreSessionFailureKind.canceled);
    _setState(MeshCoreSessionState.closing);
    _invalidate();
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

final class _PendingRequest {
  _PendingRequest(this.id, this.commandOpcode, this.expectedOpcode);

  final int id;
  final int commandOpcode;
  final int expectedOpcode;
  Timer? timer;
  bool sent = false;
  CompanionResponse? response;

  bool accepts(CompanionResponse response) => switch (expectedOpcode) {
    0x0d => response is DeviceInfoResponse,
    0x05 => response is SelfInfoResponse,
    _ => false,
  };
}
