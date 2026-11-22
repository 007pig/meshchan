part of 'serial_transport.dart';

/// Builds a single-port Meshchan session transport. The App's existing
/// completion queries are retained for unrecognized devices.
CompanionTransport createUsbCompanionTransport(
  String path, {
  bool appCompletionQueries = true,
}) => _UsbInitializationTransport(
  () => describeMacSerialPort(path),
  (startup) => SerialTransport._(
    path,
    115200,
    const Duration(seconds: 2),
    createNativeSerialConnection,
    null,
    _StopwatchClock.new,
    startup: startup,
  ),
  appCompletionQueries,
  _usbInitializationTrace(),
);

void Function(String, Map<String, Object?>)? _usbInitializationTrace() {
  if (Platform.environment['MESHCHAN_USB_INITIALIZATION_TRACE'] != '1') {
    return null;
  }
  // Use a separate sink so trace writes cannot fail the CLI's stderr sink.
  final sink = stderr.nonBlocking;
  sink.done.ignore();
  return (event, fields) =>
      sink.writeln(jsonEncode({'usbInitialization': event, ...fields}));
}

/// Existing App policy seam for a framed transport.
final class UsbInitializationTransport extends _UsbInitializationTransport {
  UsbInitializationTransport(CompanionTransport inner)
    : super(
        () => const SerialPortDescription(path: ''),
        (_) => inner,
        true,
        null,
      );
}

class _UsbInitializationTransport implements CompanionTransport {
  _UsbInitializationTransport(
    this._describe,
    this._create,
    this._app,
    this._trace,
  );

  final SerialPortDescription Function() _describe;
  final CompanionTransport Function(_UsbStartupSync?) _create;
  final bool _app;
  final void Function(String, Map<String, Object?>)? _trace;
  final _query = encodeDeviceQuery(
    appTargetVersion: meshCoreSessionAppTargetVersion,
  );
  final _appStartPrefix = encodeAppStart(appName: '');
  // Subscribe immediately without touching hardware. open() attaches the
  // sole native reader after checking the selected port's metadata.
  late final _frames = StreamController<Uint8List>(
    onPause: _closeFromStream,
    onCancel: _closeFromStream,
  );

  void _closeFromStream() {
    unawaited(close().then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  void _report(String event, Map<String, Object?> fields) {
    try {
      _trace?.call(event, fields);
    } catch (_) {
      // Optional diagnostics must not interfere with a frame or port cleanup.
    }
  }

  StreamSubscription<Uint8List>? _subscription;
  CompanionTransport? _inner;
  Future<void>? _closed;
  bool _candidate = false;
  bool _heltec = false;
  bool _selfSeen = false;
  bool _closing = false;
  int _commands = 0;
  int _receivedFrames = 0;
  int _needed = 0;
  Completer<void>? _waiter;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> open() async {
    if (_closing || _inner != null) {
      throw StateError('USB initialization already used.');
    }
    if (!_frames.hasListener) {
      throw StateError('Subscribe to frames before open().');
    }
    final metadata = _describe();
    _candidate = metadata.usbVid == 0x303a && metadata.usbPid == 0x1001;
    final inner = _inner = _create(
      _candidate ? _UsbStartupSync(_trace == null ? null : _report) : null,
    );
    _subscription = inner.frames.listen(
      _receive,
      onError: (Object error, StackTrace stack) {
        if (error is SerialTransportFailure) {
          _report('transportFailure', {
            // The wrapper knows the stage only during a managed send.
            if (_waiter != null)
              'stage': _commands == 0 ? 'deviceQuery' : 'appStart',
            'transportKind': error.kind.name,
            if (error.protocolError case final framing?)
              'framingKind': framing.kind.name,
          });
        }
        if (!_frames.isClosed) _frames.addError(error, stack);
      },
      onDone: () => unawaited(_frames.close()),
    );
    await inner.open();
  }

  void _receive(Uint8List content) {
    final frameNumber = ++_receivedFrames;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted && content.isNotEmpty) {
      if (_commands == 1 && _heltec && content.first == 0x05) {
        try {
          _selfSeen = decodeCompanionResponse(content) is SelfInfoResponse;
        } on CompanionProtocolException {
          // The owning session handles the original malformed response.
        }
      }
      final info = _deviceInfo(content);
      if (info != null) {
        final firstReply = _commands == 0 && _needed == (_app ? 2 : 1);
        if (firstReply && _candidate && _isHeltec(info)) {
          _heltec = true;
          _needed = 1;
        }
        final inner = _inner;
        final matches =
            _commands == 0 ||
            !_heltec ||
            (_selfSeen &&
                _isHeltec(info) &&
                inner is SerialTransport &&
                inner._isAfterCompletionQuery(frameNumber));
        if (matches && --_needed == 0) {
          waiter.complete();
        }
      }
    }
    if (!_frames.isClosed) _frames.add(content);
  }

  @override
  Future<void> close() => _closed ??= _close();

  Future<void> _close() async {
    _closing = true;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _report('handshakeClosed', {
        'stage': _commands == 0 ? 'deviceQuery' : 'appStart',
      });
      waiter.completeError(StateError('USB initialization was closed.'));
    }
    var closeFailed = false;
    try {
      await _inner?.close();
    } catch (_) {
      closeFailed = true;
      rethrow;
    } finally {
      try {
        await _subscription?.cancel();
      } catch (_) {
        // Preserve the transport close error when both cleanups fail.
        if (!closeFailed) rethrow;
      } finally {
        // The frame controller's onCancel can call back into close.
        unawaited(_frames.close());
      }
    }
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    if (_closing || _waiter != null) {
      throw StateError('USB initialization is closing or writing.');
    }
    final inner = _requireInner(_inner);
    if (_commands == 2 || (!_app && !_candidate)) {
      await inner.sendFrame(content);
      return;
    }
    final first = _commands == 0;
    if (first ? !_same(content, _query) : !_isAppStart(content)) {
      throw StateError('USB initialization command is out of order.');
    }
    _needed = first && _app ? 2 : 1;
    final waiter = _waiter = Completer<void>();
    waiter.future.ignore();
    try {
      await inner.sendFrame(content);
      if (_closing) throw StateError('USB initialization was closed.');
      if (!first && _heltec && inner is SerialTransport) {
        await inner._sendFrame(_query, completionQuery: true);
      } else if (_app) {
        await inner.sendFrame(_query);
      }
      if (first || _app || _heltec) await waiter.future;
      _commands++;
    } finally {
      _waiter = null;
    }
  }

  static CompanionTransport _requireInner(CompanionTransport? inner) =>
      inner ?? (throw StateError('USB initialization has not opened.'));

  bool _isAppStart(Uint8List content) {
    final prefixLength = _appStartPrefix.length;
    if (content.length < prefixLength ||
        content.length > maxSerialFrameContentLength ||
        !_same(
          _appStartPrefix,
          Uint8List.sublistView(content, 0, prefixLength),
        )) {
      return false;
    }
    final name = Uint8List.sublistView(content, prefixLength);
    if (name.contains(0)) return false;
    try {
      utf8.decode(name);
    } on FormatException {
      return false;
    }
    return true;
  }

  static bool _same(Uint8List a, Uint8List b) =>
      a.length == b.length &&
      a.indexed.every((entry) => b[entry.$1] == entry.$2);
}

/// Exercises the production wiring without enumerating or opening hardware.
CompanionTransport usbInitializationTransportForTest({
  required SerialPortDescription metadata,
  required NativeSerialConnection connection,
  required bool appCompletionQueries,
  void Function(String, Map<String, Object?>)? trace,
}) => _UsbInitializationTransport(
  () => metadata,
  (startup) => SerialTransport._(
    metadata.path,
    115200,
    const Duration(seconds: 2),
    (_) => connection,
    'macos',
    _StopwatchClock.new,
    startup: startup,
  ),
  appCompletionQueries,
  trace ?? _usbInitializationTrace(),
);
