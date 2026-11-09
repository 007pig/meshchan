import 'dart:async';
import 'dart:typed_data';

import '../protocol/serial_framing.dart';
import '../serial_ports.dart';
import 'companion_transport.dart';
import 'native_serial_connection.dart';

enum SerialTransportFailureKind {
  platform,
  io,
  configuration,
  protocol,
  disconnected,
  writeTimeout,
  cleanup,
}

/// One terminal reason, shared by the failing operation and receive stream.
/// Cleanup details may be appended while shutdown completes. Messages contain
/// no frame bytes; [cause] preserves the original native or codec error.
final class SerialTransportFailure implements Exception {
  SerialTransportFailure(this.kind, this.message, {this.cause});

  final SerialTransportFailureKind kind;
  final String message;
  final Object? cause;
  final List<Object> _cleanupErrors = [];
  List<Object> get cleanupErrors => List.unmodifiable(_cleanupErrors);
  SerialFrameDecodeError? get protocolError =>
      cause is SerialFrameDecodeError ? cause as SerialFrameDecodeError : null;

  @override
  String toString() =>
      'Serial transport ${kind.name}: $message'
      '${_cleanupErrors.isEmpty ? '' : ' (cleanup also failed)'}';
}

enum _State { created, opening, open, closing, closed }

/// A single explicit-port connection attempt. Constructing or subscribing does
/// not access hardware. Subscribe before open(); pausing ends the connection.
final class SerialTransport implements CompanionTransport {
  SerialTransport({
    required this.portPath,
    this.baudRate = 115200,
    this.writeTimeout = const Duration(seconds: 2),
  }) : _createConnection = createNativeSerialConnection,
       _operatingSystem = null,
       _createClock = _StopwatchClock.new {
    _initializeStream();
  }

  SerialTransport._(
    this.portPath,
    this.baudRate,
    this.writeTimeout,
    this._createConnection,
    this._operatingSystem,
    this._createClock,
  ) {
    _initializeStream();
  }

  final String portPath;
  final int baudRate;
  final Duration writeTimeout;
  final NativeSerialConnection Function(String) _createConnection;
  final String? _operatingSystem;
  final SerialWriteClock Function() _createClock;
  final _decoder = SerialFrameDecoder();
  late final StreamController<Uint8List> _frames;
  _State _state = _State.created;
  bool _listening = false;
  bool _sending = false;
  NativeSerialConnection? _connection;
  Completer<void>? _openingDone;
  Future<void>? _closing;
  SerialTransportFailure? _primary;

  void _initializeStream() {
    _frames = StreamController<Uint8List>(
      onListen: () => _listening = true,
      onPause: () => _requestClose(),
      onCancel: () {
        _listening = false;
        // Do not return close(): controller completion must never depend on
        // its own onCancel future. Native subscription is separate.
        _requestClose();
      },
    );
  }

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> open() {
    if (_state != _State.created) {
      return Future.error(
        StateError('This connection attempt has already ended or started.'),
      );
    }
    _state = _State.opening;
    _openingDone = Completer<void>();
    return _open();
  }

  Future<void> _open() async {
    Object? failure;
    StackTrace? failureStack;
    var validated = false;
    var kind = SerialTransportFailureKind.io;
    try {
      if (portPath.trim().isEmpty) {
        throw ArgumentError.value(portPath, 'portPath', 'Must not be blank.');
      }
      if (baudRate <= 0) throw ArgumentError.value(baudRate, 'baudRate');
      if (writeTimeout <= Duration.zero) {
        throw ArgumentError.value(writeTimeout, 'writeTimeout');
      }
      if (!_listening) throw StateError('Subscribe to frames before open().');
      validated = true;
      kind = SerialTransportFailureKind.platform;
      nativeSerialOperation(() {}, operatingSystem: _operatingSystem);
      kind = SerialTransportFailureKind.io;
      final connection = _connection = _createConnection(portPath);
      await connection.open();
      _checkOpening();
      kind = SerialTransportFailureKind.configuration;
      await connection.configure(baudRate);
      _checkOpening();
      kind = SerialTransportFailureKind.io;
      connection.startReader(
        onData: _receive,
        onError: (error, stack) => _terminate(
          SerialTransportFailure(
            SerialTransportFailureKind.io,
            'Serial read failed.',
            cause: error,
          ),
          stack,
        ),
        onDone: _readerDone,
      );
      _checkOpening();
      _state = _State.open;
    } catch (error, stack) {
      failure =
          _primary ??
          (!validated || (_state != _State.opening && error is StateError)
              ? error
              : SerialTransportFailure(
                  kind,
                  'Could not open the serial connection.',
                  cause: error,
                ));
      failureStack = stack;
      if (failure is SerialTransportFailure) {
        if (_state == _State.opening) {
          _terminate(failure, stack);
        } else {
          _primary ??= failure;
        }
      }
    } finally {
      _openingDone!.complete();
    }
    if (failure != null) {
      await _closeIgnoringFailure();
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  void _checkOpening() {
    if (_state != _State.opening) throw StateError('Opening was canceled.');
  }

  void _receive(Uint8List chunk) {
    if (_state != _State.open && _state != _State.opening) return;
    final result = _decoder.add(chunk);
    for (final frame in result.frames) {
      _frames.add(frame);
    }
    if (result.error case final error?) {
      _terminate(_protocolFailure(error), StackTrace.current);
    }
  }

  void _readerDone() {
    if (_state != _State.open && _state != _State.opening) return;
    final error = _decoder.finish().error;
    _terminate(
      error == null
          ? SerialTransportFailure(
              SerialTransportFailureKind.disconnected,
              'Serial input ended unexpectedly.',
            )
          : _protocolFailure(error),
      StackTrace.current,
    );
  }

  SerialTransportFailure _protocolFailure(SerialFrameDecodeError error) =>
      SerialTransportFailure(
        SerialTransportFailureKind.protocol,
        error.message,
        cause: error,
      );

  @override
  Future<void> sendFrame(Uint8List content) async {
    if (_state != _State.open) {
      throw StateError('The serial connection is not open.');
    }
    if (_sending) throw StateError('Another frame is already being sent.');
    // Encoder validates and copies before the first asynchronous yield.
    final bytes = encodeSerialFrame(content);
    final clock = _createClock();
    _sending = true;
    try {
      var offset = 0;
      while (offset < bytes.length) {
        if (_state != _State.open) {
          throw _primary ?? StateError('Sending was canceled.');
        }
        _checkDeadline(clock);
        final int count;
        try {
          count = _connection!.write(Uint8List.sublistView(bytes, offset));
        } catch (error) {
          throw SerialTransportFailure(
            SerialTransportFailureKind.io,
            'Serial write failed.',
            cause: error,
          );
        }
        if (count < 0 || count > bytes.length - offset) {
          throw SerialTransportFailure(
            SerialTransportFailureKind.io,
            'Serial write returned an invalid byte count.',
          );
        }
        _checkDeadline(clock);
        offset += count;
        if (offset < bytes.length) {
          final remaining = writeTimeout - clock.elapsed;
          final retry = const Duration(milliseconds: 5);
          await clock.delay(
            count > 0 ? Duration.zero : (remaining < retry ? remaining : retry),
          );
        }
      }
    } on SerialTransportFailure catch (failure, stack) {
      _terminate(failure, stack);
      await _closeIgnoringFailure();
      Error.throwWithStackTrace(failure, stack);
    } finally {
      _sending = false;
    }
  }

  void _checkDeadline(SerialWriteClock clock) {
    if (clock.elapsed >= writeTimeout) {
      throw SerialTransportFailure(
        SerialTransportFailureKind.writeTimeout,
        'The frame write deadline expired.',
      );
    }
  }

  void _terminate(SerialTransportFailure failure, StackTrace stack) {
    if (_state == _State.closing || _state == _State.closed) return;
    _primary = failure;
    if (_listening) _frames.addError(failure, stack);
    _requestClose();
  }

  void _requestClose() {
    // Observe automatic cleanup failures; close() still returns the original
    // failing future to explicit callers. No detached asynchronous errors.
    unawaited(close().then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  @override
  Future<void> close() {
    if (_closing case final closing?) return closing;
    _state = _State.closing;
    return _closing = _cleanup();
  }

  Future<void> _closeIgnoringFailure() async {
    try {
      await close();
    } catch (_) {
      // Primary failure remains primary; cleanup details are attached to it.
    }
  }

  Future<void> _cleanup() async {
    final errors = <Object>[];
    try {
      await _openingDone?.future;
      final connection = _connection;
      if (connection != null) {
        var stopped = false;
        try {
          await connection.stopReader();
          stopped = true;
        } catch (error) {
          errors.add(error);
          // Keep a strong reference even if the caller drops this transport:
          // a native finalizer must not close a port still used by a reader.
          _unconfirmedConnections.add(connection);
        }
        if (stopped) {
          try {
            connection.closePort();
          } catch (error) {
            errors.add(error);
          }
          try {
            connection.dispose();
          } catch (error) {
            errors.add(error);
          }
          _connection = null;
        }
      }
      if (errors.isNotEmpty) {
        final failure = _primary ??= SerialTransportFailure(
          SerialTransportFailureKind.cleanup,
          'Serial cleanup failed.',
        );
        failure._cleanupErrors.addAll(errors);
        if (failure.kind == SerialTransportFailureKind.cleanup && _listening) {
          _frames.addError(failure);
        }
        throw failure;
      }
    } finally {
      _state = _State.closed;
      // A paused public subscriber cannot hold native resources hostage.
      unawaited(_frames.close());
    }
  }
}

// Stop failures are exceptional. There is deliberately no forced free or
// guessed shutdown timeout; retained resources remain valid until process exit.
final _unconfirmedConnections = <NativeSerialConnection>{};

/// Internal test seam: a monotonic elapsed clock and its matching delay.
abstract interface class SerialWriteClock {
  Duration get elapsed;
  Future<void> delay(Duration duration);
}

class _StopwatchClock implements SerialWriteClock {
  final _watch = Stopwatch()..start();
  @override
  Duration get elapsed => _watch.elapsed;
  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

/// Internal construction seam, intentionally omitted from public exports.
SerialTransport serialTransportForTest({
  required String portPath,
  required NativeSerialConnection Function(String) createConnection,
  String operatingSystem = 'macos',
  int baudRate = 115200,
  Duration writeTimeout = const Duration(seconds: 2),
  SerialWriteClock Function()? createClock,
}) => SerialTransport._(
  portPath,
  baudRate,
  writeTimeout,
  createConnection,
  operatingSystem,
  createClock ?? _StopwatchClock.new,
);
