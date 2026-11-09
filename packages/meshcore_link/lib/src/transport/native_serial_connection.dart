import 'dart:async';
import 'dart:typed_data';

import 'package:libserialport_plus/libserialport_plus.dart' as native;

import '../serial_ports.dart';

/// Internal boundary, not exported by meshcore_link.dart. No native objects
/// escape this adapter. Tests replace only this connection, not the codec.
abstract interface class NativeSerialConnection {
  /// Failure must recover any partial open, as openNativePort does.
  FutureOr<void> open();
  FutureOr<void> configure(int baudRate);
  void startReader({
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  });

  /// Complete only once the backend no longer uses the port. A failed stop
  /// leaves the port alive; the transport must not close or dispose it.
  Future<void> stopReader();
  int write(Uint8List bytes);
  void closePort();
  void dispose();
}

NativeSerialConnection createNativeSerialConnection(String path) =>
    nativeSerialOperation(
      () => _NativeSerialConnection(native.SerialPort(path)),
    );

class _NativeSerialConnection implements NativeSerialConnection {
  _NativeSerialConnection(this._port);

  final native.SerialPort _port;
  bool _opened = false;
  native.SerialPortReader? _reader;
  SerialReaderSession? _session;

  @override
  void open() {
    openNativePort(
      () => _port.open(native.SerialPortMode.readWrite),
      _port.close,
    );
    // Never use isOpen(): the pinned wrapper misreports descriptor 0.
    _opened = true;
  }

  @override
  void configure(int baudRate) => nativeSerialOperation(
    () => _port.setConfig(serialTransportConfig(baudRate)),
  );

  @override
  void startReader({
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  }) {
    final reader = nativeSerialOperation(() => native.SerialPortReader(_port));
    _reader = reader;
    _session = SerialReaderSession(
      stream: reader.stream,
      stopReader: reader.close,
      onData: onData,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  Future<void> stopReader() async {
    if (_reader == null) return;
    final session = _session;
    if (session == null) {
      // Subscription setup failed after reader creation. There is no reliable
      // controller.done evidence without a listener; retain the native port.
      throw const SerialPortFailure('Reader stop could not be confirmed.');
    }
    await session.stop();
  }

  @override
  int write(Uint8List bytes) =>
      nativeSerialOperation(() => _port.write(bytes, timeout: -1));

  @override
  void closePort() {
    if (_opened) nativeSerialOperation(_port.close);
  }

  @override
  void dispose() => nativeSerialOperation(_port.dispose);
}

/// Null RTS/DTR skip their native setters. Do not replace them with off.
/// Necessary configuration failures propagate, including inherited coupled
/// flow control that cannot be disabled without changing output lines.
native.SerialPortConfig serialTransportConfig(int baudRate) =>
    native.SerialPortConfig(
      baudRate: baudRate,
      bits: 8,
      parity: native.SerialPortParity.none,
      stopBits: 1,
      cts: native.SerialPortCts.ignore,
      dsr: native.SerialPortDsr.ignore,
      xonXoff: native.SerialPortXonXoff.disabled,
    );

/// The production reader lifecycle, with callbacks for hardware-free tests.
/// In 1.0.5 only isolate onExit closes the source controller. Keep listening
/// until then: canceling first would complete controller.done prematurely.
class SerialReaderSession {
  SerialReaderSession({
    required Stream<Uint8List> stream,
    required this.stopReader,
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  }) {
    _subscription = stream.listen(
      onData,
      onError: onError,
      onDone: () {
        _done.complete();
        onDone();
      },
      cancelOnError: false,
    );
  }

  final Future<void> Function() stopReader;
  final _done = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;
  Future<void>? _stopping;

  Future<void> stop() => _stopping ??= _stopAndCancel();

  Future<void> _stopAndCancel() async {
    await stopReader();
    await _done.future;
    await _subscription.cancel();
  }
}
