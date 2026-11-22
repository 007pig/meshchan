part of 'serial_transport.dart';

bool _isHeltec(DeviceInfoResponse info) =>
    info.hardwareModel == 'Heltec V4.3 OLED';

DeviceInfoResponse? _deviceInfo(Uint8List content) {
  if (content.isEmpty || content.first != 0x0d) return null;
  try {
    return decodeCompanionResponse(content) as DeviceInfoResponse;
  } on CompanionProtocolException {
    return null;
  }
}

/// Bounded lookahead for one DEVICE_QUERY on a candidate USB interface.
final class _UsbStartupSync {
  _UsbStartupSync(this.trace);

  static const _prefixLimit = 1024;
  static const _limit = _prefixLimit + 3 + maxSerialFrameContentLength;
  final void Function(String, Map<String, Object?>)? trace;
  final _bytes = Uint8List(_limit);
  final _strictFrames = <Uint8List>[];
  final _candidatesByEnd = <int, List<int>>{};
  SerialFrameDecodeError? firstError;
  int _length = 0;
  int? _queryOffset;

  void arm() {
    _queryOffset ??= _length;
  }

  void report(String event, Map<String, Object?> fields) =>
      trace?.call(event, fields);

  void reportClose() => report('windowClosed', {
    'bufferedBytes': _length,
    if (firstError case final error?) 'framingKind': error.kind.name,
  });

  void receive(SerialTransport transport, Uint8List chunk) {
    for (var index = 0; index < chunk.length; index++) {
      _bytes[_length++] = chunk[index];
      Uint8List? alignedFrame;
      if (firstError == null) {
        final strict = transport._decoder.add(
          Uint8List.sublistView(chunk, index, index + 1),
        );
        _strictFrames.addAll(strict.frames);
        firstError = strict.error;
        // Preserve aligned DEVICE_INFO (including malformed replies for the
        // session to reject) and explicit device errors on the original path.
        if (strict.frames.isNotEmpty && _queryOffset != null) {
          final frame = alignedFrame = strict.frames.single;
          final info = _deviceInfo(frame);
          if (frame.first == 0x01 ||
              (frame.first == 0x0d && (info == null || !_isHeltec(info)))) {
            _forwardStrict(transport, chunk, index + 1);
            return;
          }
        }
      }
      final start = _length - 4;
      if (_queryOffset case final queryOffset?
          when start >= queryOffset && start <= _prefixLimit) {
        final size = _bytes[start + 1] | (_bytes[start + 2] << 8);
        if (_bytes[start] == 0x3e &&
            _bytes[start + 3] == 0x0d &&
            size >= 80 &&
            size <= maxSerialFrameContentLength) {
          (_candidatesByEnd[start + 3 + size] ??= []).add(start);
        }
      }
      for (final offset in _candidatesByEnd.remove(_length) ?? const <int>[]) {
        final candidate = Uint8List.sublistView(_bytes, offset + 3, _length);
        final info = _deviceInfo(candidate);
        if (info == null || !_isHeltec(info)) continue;
        final aligned =
            alignedFrame != null && alignedFrame.length == candidate.length;
        report('deviceInfo', {
          'prefixBytes': offset,
          'skippedBytes': aligned ? 0 : offset,
          'recovered': !aligned,
          if (firstError case final error?) 'framingKind': error.kind.name,
        });
        if (aligned) {
          // A DEVICE_INFO already buffered before our query is not its reply.
          _strictFrames.removeWhere(
            (frame) => !identical(frame, alignedFrame) && frame.first == 0x0d,
          );
          _forwardStrict(transport, chunk, index + 1);
        } else {
          transport._startup = null;
          transport._decoder.reset();
          transport._frames.add(Uint8List.fromList(candidate));
          transport._decode(Uint8List.sublistView(chunk, index + 1));
        }
        return;
      }
      if (_length == _limit) {
        final error = firstError;
        transport._terminate(
          error != null
              ? transport._protocolFailure(error)
              : SerialTransportFailure(
                  SerialTransportFailureKind.protocol,
                  'USB initialization synchronization window exhausted.',
                ),
          StackTrace.current,
        );
        return;
      }
    }
  }

  void _forwardStrict(SerialTransport transport, Uint8List chunk, int next) {
    transport._startup = null;
    for (final frame in _strictFrames) {
      transport._frames.add(frame);
    }
    transport._decode(Uint8List.sublistView(chunk, next));
  }
}
