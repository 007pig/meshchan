import 'dart:typed_data';

/// Maximum Companion content length, excluding the three-byte serial header.
/// MeshCore MAX_FRAME_SIZE in src/helpers/BaseSerialInterface.h at commit
/// 81dbae592ffad40b4212bc0b37e82b38da08f4bc:
/// https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h
const int maxSerialFrameContentLength = 176;

/// Wraps opaque content in a host-to-device (`<`) serial frame.
///
/// Meshchan accepts 1..176 content bytes. Invalid lengths throw [RangeError]
/// before allocating output. The returned bytes do not share input storage.
Uint8List encodeSerialFrame(Uint8List content) {
  RangeError.checkValueInInterval(
    content.length,
    1,
    maxSerialFrameContentLength,
    'content.length',
  );
  final frame = Uint8List(3 + content.length);
  frame[0] = 0x3c;
  ByteData.sublistView(frame).setUint16(1, content.length, Endian.little);
  frame.setRange(3, frame.length, content);
  return frame;
}

/// Protocol failures, independent of native serial diagnostics.
enum SerialFrameDecodeErrorKind {
  invalidLength,
  noiseLimitExceeded,
  truncatedFrame,
}

/// A protocol failure containing only its category and structural counts.
/// No input bytes are retained in the diagnostic.
final class SerialFrameDecodeError {
  const SerialFrameDecodeError._(this.kind, this.message);

  final SerialFrameDecodeErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Completed content in wire order, including frames completed before [error].
final class SerialFrameDecodeResult {
  SerialFrameDecodeResult._(List<Uint8List> frames, [this.error])
    : frames = List.unmodifiable(frames);

  /// The list is unmodifiable; each content buffer is independently owned and
  /// mutable. Neither later decoder operations nor input mutation can change it.
  final List<Uint8List> frames;
  final SerialFrameDecodeError? error;
}

enum _DecodeState { marker, lengthLow, lengthHigh, content, failed, finished }

/// Incrementally decodes device-to-host (`>`) frames without accessing hardware.
///
/// Use one instance per connection. Only a partial header and at most 176 bytes
/// of content are retained across calls. Errors stop parsing immediately; both
/// [add] and [finish] then throw [StateError] until [reset] is called. A successful
/// [finish] also requires [reset] before either method can be used again.
final class SerialFrameDecoder {
  /// [maxDiscardedBytes] is a nonnegative Meshchan noise budget, not a protocol
  /// limit. Exactly this many bytes may be skipped outside a frame, across calls.
  SerialFrameDecoder({this.maxDiscardedBytes = 1024}) {
    if (maxDiscardedBytes < 0) {
      throw RangeError.range(maxDiscardedBytes, 0, null, 'maxDiscardedBytes');
    }
  }

  final int maxDiscardedBytes;
  _DecodeState _state = _DecodeState.marker;
  int _discardedBytes = 0;
  int _declaredLength = 0;
  int _receivedLength = 0;
  Uint8List? _content;

  /// Consumes the logical range of [chunk], returning complete content only.
  /// Empty input leaves pending state unchanged. No input storage is retained.
  /// An error preserves earlier frames but discards the rest of this chunk.
  SerialFrameDecodeResult add(Uint8List chunk) {
    _checkActive();
    final frames = <Uint8List>[];
    for (final byte in chunk) {
      switch (_state) {
        case _DecodeState.marker:
          if (byte == 0x3e) {
            _state = _DecodeState.lengthLow;
          } else {
            if (_discardedBytes == maxDiscardedBytes) {
              return _fail(
                frames,
                SerialFrameDecodeErrorKind.noiseLimitExceeded,
                'Serial noise limit of $maxDiscardedBytes bytes exceeded '
                'at ${_discardedBytes + 1} bytes.',
              );
            }
            _discardedBytes++;
          }
        case _DecodeState.lengthLow:
          _declaredLength = byte;
          _state = _DecodeState.lengthHigh;
        case _DecodeState.lengthHigh:
          _declaredLength |= byte << 8;
          if (_declaredLength < 1 ||
              _declaredLength > maxSerialFrameContentLength) {
            return _fail(
              frames,
              SerialFrameDecodeErrorKind.invalidLength,
              'Invalid serial content length $_declaredLength; '
              'expected 1..$maxSerialFrameContentLength bytes.',
            );
          }
          _content = Uint8List(_declaredLength);
          _receivedLength = 0;
          _state = _DecodeState.content;
        case _DecodeState.content:
          _content![_receivedLength++] = byte;
          if (_receivedLength == _declaredLength) {
            // Transfer ownership; this buffer is never reused by the decoder.
            frames.add(_content!);
            _content = null;
            _declaredLength = 0;
            _receivedLength = 0;
            _discardedBytes = 0;
            _state = _DecodeState.marker;
          }
        case _DecodeState.failed:
        case _DecodeState.finished:
          throw StateError('Serial frame decoder is inactive; call reset().');
      }
    }
    return SerialFrameDecodeResult._(frames);
  }

  /// Ends input explicitly. A partial header or content reports truncation;
  /// allowed noise alone is a clean ending. No timeout is inferred.
  /// Repeated calls after success or failure throw [StateError] until [reset].
  SerialFrameDecodeResult finish() {
    _checkActive();
    if (_state != _DecodeState.marker) {
      final received = switch (_state) {
        _DecodeState.lengthLow => 1,
        _DecodeState.lengthHigh => 2,
        _ => 3 + _receivedLength,
      };
      final expected = _state == _DecodeState.content ? 3 + _declaredLength : 3;
      return _fail(
        [],
        SerialFrameDecodeErrorKind.truncatedFrame,
        'Truncated serial frame: received $received of $expected bytes.',
      );
    }
    _state = _DecodeState.finished;
    return SerialFrameDecodeResult._([]);
  }

  /// Discards pending content, header, noise, and failed/finished state.
  /// Repeated resets are safe and never deliver pending bytes.
  void reset() {
    _state = _DecodeState.marker;
    _discardedBytes = 0;
    _declaredLength = 0;
    _receivedLength = 0;
    _content = null;
  }

  void _checkActive() {
    if (_state == _DecodeState.failed || _state == _DecodeState.finished) {
      throw StateError('Serial frame decoder is inactive; call reset().');
    }
  }

  SerialFrameDecodeResult _fail(
    List<Uint8List> frames,
    SerialFrameDecodeErrorKind kind,
    String message,
  ) {
    _state = _DecodeState.failed;
    _content = null;
    return SerialFrameDecodeResult._(
      frames,
      SerialFrameDecodeError._(kind, message),
    );
  }
}
