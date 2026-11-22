part of 'serial_transport.dart';

/// Builds a single-port Meshchan session transport. The App's existing
/// completion queries are retained for unrecognized devices.
CompanionTransport createUsbCompanionTransport(
  String path, {
  bool appCompletionQueries = true,
}) {
  final trace = Platform.environment['MESHCHAN_USB_INITIALIZATION_TRACE'] == '1'
      ? (String event, Map<String, Object?> fields) =>
            stderr.writeln(jsonEncode({'usbInitialization': event, ...fields}))
      : null;
  return _UsbInitializationTransport(
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
    trace,
  );
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
  final _start = encodeAppStart(appName: 'Meshchan');
  // Subscribe immediately without touching hardware. open() attaches the
  // sole native reader after checking the selected port's metadata.
  late final _frames = StreamController<Uint8List>(
    onPause: _closeFromStream,
    onCancel: _closeFromStream,
  );

  void _closeFromStream() {
    unawaited(close().then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  StreamSubscription<Uint8List>? _subscription;
  CompanionTransport? _inner;
  Future<void>? _closed;
  bool _candidate = false;
  bool _heltec = false;
  bool _selfSeen = false;
  bool _completionQueryStarted = false;
  bool _closing = false;
  int _commands = 0;
  int _needed = 0;
  Completer<void>? _waiter;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> open() async {
    if (_closing || _inner != null) {
      throw StateError('USB initialization already used.');
    }
    final metadata = _describe();
    _candidate = metadata.usbVid == 0x303a && metadata.usbPid == 0x1001;
    final inner = _inner = _create(_candidate ? _UsbStartupSync(_trace) : null);
    _subscription = inner.frames.listen(
      _receive,
      onError: (Object error, StackTrace stack) {
        if (error is SerialTransportFailure) {
          _trace?.call('transportFailure', {
            'stage': _commands == 0
                ? 'deviceQuery'
                : _commands == 1
                ? 'appStart'
                : 'ready',
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
        if (_commands == 0 && _candidate && _isHeltec(info)) {
          _heltec = true;
          _needed = 1;
        }
        final matches =
            _commands == 0 ||
            !_heltec ||
            (_selfSeen && _completionQueryStarted && _isHeltec(info));
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
      _trace?.call('handshakeClosed', {
        'stage': _commands == 0 ? 'deviceQuery' : 'appStart',
      });
      waiter.completeError(StateError('USB initialization was closed.'));
    }
    try {
      await _inner?.close();
    } finally {
      await _subscription?.cancel();
      // The frame controller's onCancel can call back into close.
      unawaited(_frames.close());
    }
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    final inner = _inner;
    if (_closing || _waiter != null) {
      throw StateError('USB initialization is closing or writing.');
    }
    if (_commands == 2 || (!_app && !_candidate)) {
      await _requireInner(inner).sendFrame(content);
      return;
    }
    final first = _commands == 0;
    if (!_same(content, first ? _query : _start)) {
      throw StateError('USB initialization command is out of order.');
    }
    _needed = first && _app ? 2 : 1;
    final waiter = _waiter = Completer<void>();
    waiter.future.ignore();
    try {
      await _requireInner(inner).sendFrame(content);
      if (_closing) throw StateError('USB initialization was closed.');
      if (_app || (!first && _heltec)) {
        _completionQueryStarted = !first;
        await inner!.sendFrame(_query);
      }
      if (first || _app || _heltec) await waiter.future;
      _commands++;
    } finally {
      _waiter = null;
    }
  }

  static CompanionTransport _requireInner(CompanionTransport? inner) =>
      inner ?? (throw StateError('USB initialization has not opened.'));

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
  trace,
);
