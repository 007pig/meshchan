import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';

/// Source-tool observation only. No native bytes or display values are retained.
final class InitializationTrace {
  final _clock = Stopwatch()..start();
  final _decoder = SerialFrameDecoder();
  final _events = <Map<String, Object?>>[];
  bool _decoderActive = true;
  bool _finished = false;
  int omittedEvents = 0;
  int receivedBytes = 0;
  int receivedChunks = 0;
  int completeFrames = 0;

  void add(String event, [Map<String, Object?> fields = const {}]) {
    if (_events.length == 4096) {
      omittedEvents++;
      return;
    }
    _events.add({
      'event': event,
      'elapsedUs': _clock.elapsedMicroseconds,
      ...fields,
    });
  }

  void receive(Uint8List bytes) {
    receivedBytes += bytes.length;
    receivedChunks++;
    add('native_rx_chunk', {'bytes': bytes.length});
    if (!_decoderActive) return;
    final result = _decoder.add(bytes);
    for (final frame in result.frames) {
      completeFrames++;
      add('native_complete_frame', {
        'opcode': frame.first,
        'contentBytes': frame.length,
      });
    }
    if (result.error case final error?) {
      _decoderActive = false;
      add('native_decode_error', {
        'kind': error.kind.name,
        'structure': error.message,
      });
    }
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    if (!_decoderActive) return;
    final error = _decoder.finish().error;
    _decoderActive = false;
    add('native_input_projection', {
      'kind': error?.kind.name ?? 'complete',
      if (error != null) 'structure': error.message,
    });
  }

  Map<String, Object?> toJson() => {
    'receivedBytes': receivedBytes,
    'receivedChunks': receivedChunks,
    'completeFrames': completeFrames,
    'omittedEvents': omittedEvents,
    'events': List<Map<String, Object?>>.unmodifiable(_events),
  };
}

/// Decorates the existing sole native connection. It adds no reads or writes.
/// A write outside the selected exact initialization plan is blocked before I/O.
/// Extra queries require the explicit source-only completion-probe mode.
final class InitializationTraceConnection implements NativeSerialConnection {
  InitializationTraceConnection(
    this._inner,
    this.trace, {
    bool completionProbe = false,
  }) : _allowed = [
         encodeSerialFrame(
           encodeDeviceQuery(appTargetVersion: meshCoreSessionAppTargetVersion),
         ),
         if (completionProbe)
           encodeSerialFrame(
             encodeDeviceQuery(
               appTargetVersion: meshCoreSessionAppTargetVersion,
             ),
           ),
         encodeSerialFrame(encodeAppStart(appName: 'Meshchan')),
         if (completionProbe)
           encodeSerialFrame(
             encodeDeviceQuery(
               appTargetVersion: meshCoreSessionAppTargetVersion,
             ),
           ),
       ];

  final NativeSerialConnection _inner;
  final InitializationTrace trace;
  final List<Uint8List> _allowed;
  int _frame = 0;
  int _offset = 0;
  int nativeWriteCalls = 0;
  int acceptedBytes = 0;
  int blockedWrites = 0;
  bool readerStarted = false;
  bool readerStopConfirmed = false;
  bool portCloseConfirmed = false;
  bool disposeConfirmed = false;

  int get completedCommandFrames => _frame;

  @override
  Future<void> open() async {
    trace.add('native_open_begin');
    await _inner.open();
    trace.add('native_open_completed');
  }

  @override
  Future<void> configure(int baudRate) async {
    trace.add('native_configure_begin', {'baudRate': baudRate});
    await _inner.configure(baudRate);
    trace.add('native_configure_completed');
  }

  @override
  void startReader({
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  }) {
    _inner.startReader(
      onData: (bytes) {
        trace.receive(bytes);
        onData(bytes);
      },
      onError: (error, stack) {
        trace.add('native_reader_error', {
          'errorType': error.runtimeType.toString(),
        });
        onError(error, stack);
      },
      onDone: () {
        trace.add('native_reader_done');
        onDone();
      },
    );
    readerStarted = true;
    trace.add('native_reader_started');
  }

  @override
  Future<void> stopReader() async {
    trace.add('native_reader_stop_begin');
    await _inner.stopReader();
    readerStopConfirmed = true;
    trace.add('native_reader_stop_confirmed');
    trace.finish();
  }

  @override
  int write(Uint8List bytes) {
    var allowed = _frame < _allowed.length;
    if (allowed) {
      final expected = _allowed[_frame];
      allowed = bytes.length == expected.length - _offset;
      for (var i = 0; allowed && i < bytes.length; i++) {
        allowed = bytes[i] == expected[_offset + i];
      }
    }
    if (!allowed) {
      blockedWrites++;
      trace.add('unplanned_write_blocked');
      throw StateError('Unplanned native write blocked.');
    }
    nativeWriteCalls++;
    trace.add('native_write_begin', {
      'commandIndex': _frame,
      'commandOpcode': _allowed[_frame][3],
      'offset': _offset,
      'requestedBytes': bytes.length,
    });
    final accepted = _inner.write(bytes);
    trace.add('native_write_returned', {'acceptedBytes': accepted});
    if (accepted >= 0 && accepted <= bytes.length) {
      acceptedBytes += accepted;
      _offset += accepted;
      if (_offset == _allowed[_frame].length) {
        _frame++;
        _offset = 0;
      }
    }
    return accepted;
  }

  @override
  void closePort() {
    trace.add('native_port_close_begin');
    _inner.closePort();
    portCloseConfirmed = true;
    trace.add('native_port_close_confirmed');
  }

  @override
  void dispose() {
    trace.add('native_dispose_begin');
    _inner.dispose();
    disposeConfirmed = true;
    trace.add('native_dispose_confirmed');
  }
}

/// Parse completely before constructing a native object. No arbitrary budgets.
String? parseInitializationTraceArguments(List<String> arguments) {
  if (arguments.length != 3 ||
      arguments[0] != '--port' ||
      !arguments[1].startsWith('/dev/cu.') ||
      arguments[1].trim() != arguments[1] ||
      arguments[2] != '--execute') {
    return null;
  }
  return arguments[1];
}
