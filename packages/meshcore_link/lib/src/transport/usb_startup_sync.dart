part of 'serial_transport.dart';

bool _isHeltec(DeviceInfoResponse info) =>
    info.hardwareModel == 'Heltec V4.3 OLED';

DeviceInfoResponse? _deviceInfo(Uint8List content) {
  if (content.isEmpty || content.first != 0x0d) return null;
  final response = _startupResponse(content);
  return response is DeviceInfoResponse ? response : null;
}

CompanionResponse? _startupResponse(Uint8List content) {
  try {
    return decodeCompanionResponse(content);
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
  final _candidatesByEnd = <int, List<int>>{};
  SerialFrameDecodeError? firstError;
  int _received = 0;
  int _scanned = 0;
  int? _strictFrameStart;
  int? _queryOffset;
  Uint8List? _malformedFrame;
  CompanionProtocolExceptionKind? _companionError;
  ({int offset, int end})? _nestedCandidate;
  int? _unsupportedReplyEnd;

  Uint8List? get deferredUnsupportedFrame =>
      _unsupportedReplyEnd == null ? null : _malformedFrame;

  void arm() {
    _queryOffset ??= _received;
  }

  void report(String event, Map<String, Object?> fields) =>
      trace?.call(event, fields);

  void reportClose() => report('windowClosed', {
    'bufferedBytes': _scanned,
    if (firstError case final error?) 'framingKind': error.kind.name,
    if (_companionError case final error?) 'companionKind': error.name,
  });

  void receive(SerialTransport transport, Uint8List chunk) {
    for (var index = 0; index < chunk.length; index++) {
      _received++;
      Uint8List? alignedFrame;
      var alignedFrameMalformed = false;
      var unsupportedReply = false;
      if (firstError == null) {
        if (chunk[index] == 0x3e) _strictFrameStart ??= _received - 1;
        final strict = transport._decoder.add(
          Uint8List.sublistView(chunk, index, index + 1),
        );
        firstError = strict.error;
        if (strict.frames.isNotEmpty) {
          final frame = alignedFrame = strict.frames.single;
          final queryOffset = _queryOffset;
          final stale = queryOffset == null || _strictFrameStart! < queryOffset;
          final opcode = frame.first;
          final staleReply =
              stale && (opcode == 0x01 || opcode == 0x05 || opcode == 0x0d);
          // An initialization reply must start after the query write completes.
          // A stale frame that crosses that point can still cover a new reply.
          if (!staleReply || queryOffset != null) {
            final (response, error) = _decodeAligned(
              frame,
              staleReply: staleReply,
            );
            alignedFrameMalformed = error != null;
            unsupportedReply =
                !staleReply &&
                identical(_malformedFrame, frame) &&
                error ==
                    CompanionProtocolExceptionKind.unsupportedDeviceInfoVersion;
            if (_unsupportedReplyEnd == null &&
                !staleReply &&
                (response is DeviceErrorResponse ||
                    (response is DeviceInfoResponse && !_isHeltec(response)))) {
              _forwardStrict(transport, chunk, index + 1, frame);
              return;
            }
            if (!staleReply &&
                response is DeviceInfoResponse &&
                _malformedFrame == null) {
              // The prefix cap bounds recovery, not normally framed input.
              _reportDeviceInfo(
                _strictFrameStart! - queryOffset!,
                recovered: false,
              );
              _forwardStrict(transport, chunk, index + 1, frame);
              return;
            }
            if (!staleReply &&
                response != null &&
                response is! DeviceInfoResponse &&
                _malformedFrame == null) {
              transport._emitFrame(frame);
            }
          }
        }
      }
      final strictStart = _strictFrameStart;
      if (alignedFrame != null) _strictFrameStart = null;
      final queryOffset = _queryOffset;
      if (queryOffset == null) continue;
      _bytes[_scanned++] = chunk[index];
      if (alignedFrameMalformed && _nestedCandidate != null) {
        _accept(transport, chunk, index + 1, _nestedCandidate!);
        return;
      }
      if (alignedFrame != null) _nestedCandidate = null;
      final start = _scanned - 4;
      if (_unsupportedReplyEnd == null && start >= 0 && start <= _prefixLimit) {
        final size = _bytes[start + 1] | (_bytes[start + 2] << 8);
        if (_bytes[start] == 0x3e &&
            _bytes[start + 3] == 0x0d &&
            size >= 80 &&
            size <= maxSerialFrameContentLength) {
          (_candidatesByEnd[start + 3 + size] ??= []).add(start);
        }
      }
      for (final offset in _candidatesByEnd.remove(_scanned) ?? const <int>[]) {
        final candidate = Uint8List.sublistView(_bytes, offset + 3, _scanned);
        final info = _deviceInfo(candidate);
        if (info == null || !_isHeltec(info)) continue;
        final match = (offset: offset, end: _scanned);
        final absoluteOffset = queryOffset + offset;
        if (firstError == null &&
            strictStart != null &&
            strictStart < absoluteOffset &&
            !alignedFrameMalformed) {
          // Wait for the enclosing frame to validate before treating the
          // candidate as payload. A malformed frame can hide a full reply.
          if (alignedFrame == null) _nestedCandidate ??= match;
          continue;
        }
        _accept(transport, chunk, index + 1, match);
        return;
      }
      if (unsupportedReply) {
        // An overlapping candidate can finish after the apparent frame. Give
        // only the already registered candidates time to finish.
        var lastEnd = _scanned;
        for (final end in _candidatesByEnd.keys) {
          if (end > lastEnd) lastEnd = end;
        }
        _unsupportedReplyEnd = lastEnd;
      }
      if (_scanned == _unsupportedReplyEnd) {
        _forwardStrict(transport, chunk, index + 1);
        return;
      }
      if (_scanned == _limit) {
        final error = firstError;
        if (error == null) {
          // The bound limits compatibility scanning, not valid strict traffic.
          _forwardStrict(transport, chunk, index + 1);
        } else {
          transport._terminate(
            transport._protocolFailure(error),
            StackTrace.current,
          );
        }
        return;
      }
    }
  }

  (CompanionResponse?, CompanionProtocolExceptionKind?) _decodeAligned(
    Uint8List frame, {
    required bool staleReply,
  }) {
    try {
      return (decodeCompanionResponse(frame), null);
    } on CompanionProtocolException catch (error) {
      if (!staleReply) _malformedFrame ??= frame;
      _companionError ??= error.kind;
      return (null, error.kind);
    }
  }

  void _reportDeviceInfo(int prefixBytes, {required bool recovered}) {
    report('deviceInfo', {
      'prefixBytes': prefixBytes,
      'skippedBytes': recovered ? prefixBytes : 0,
      'recovered': recovered,
      if (firstError case final error?) 'framingKind': error.kind.name,
      if (_companionError case final error?) 'companionKind': error.name,
    });
  }

  void _accept(
    SerialTransport transport,
    Uint8List chunk,
    int next,
    ({int offset, int end}) match,
  ) {
    _reportDeviceInfo(match.offset, recovered: true);
    transport._startup = null;
    transport._decoder.reset();
    transport._emitFrame(
      Uint8List.fromList(
        Uint8List.sublistView(_bytes, match.offset + 3, match.end),
      ),
    );
    if (match.end < _scanned) {
      transport._decode(Uint8List.sublistView(_bytes, match.end, _scanned));
    }
    transport._receive(Uint8List.sublistView(chunk, next));
  }

  void _forwardStrict(
    SerialTransport transport,
    Uint8List chunk,
    int next, [
    Uint8List? response,
  ]) {
    transport._startup = null;
    if (_malformedFrame case final frame?) transport._emitFrame(frame);
    if (response != null) transport._emitFrame(response);
    if (firstError case final error?) {
      transport._terminate(
        transport._protocolFailure(error),
        StackTrace.current,
      );
    } else {
      transport._decode(Uint8List.sublistView(chunk, next));
    }
  }
}
