import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

/// Source-only compatibility candidate, never a product default.
/// Each original initialization write is followed once by DEVICE_QUERY.
/// It keeps one receive stream and never changes the owning session's deadlines.
final class InitializationCompletionProbe implements CompanionTransport {
  InitializationCompletionProbe(this._inner);

  final CompanionTransport _inner;
  final _query = encodeDeviceQuery(
    appTargetVersion: meshCoreSessionAppTargetVersion,
  );
  final _start = encodeAppStart(appName: 'Meshchan');
  var _commands = 0;
  var _writing = false;
  var _closing = false;
  Completer<void>? _replyWaiter;
  var _neededDeviceReplies = 0;
  late final _frames = _inner.frames.map((content) {
    final waiter = _replyWaiter;
    if (waiter != null &&
        !waiter.isCompleted &&
        content.isNotEmpty &&
        content.first == 13) {
      try {
        if (decodeCompanionResponse(content) is DeviceInfoResponse &&
            --_neededDeviceReplies == 0) {
          waiter.complete();
        }
      } on CompanionProtocolException {
        // Forward unchanged; the owning session keeps its protocol failure.
      }
    }
    return content;
  });

  @override
  Stream<Uint8List> get frames => _frames;
  @override
  Future<void> open() => _inner.open();
  @override
  Future<void> close() {
    _closing = true;
    final waiter = _replyWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Completion probe was closed.'));
    }
    return _inner.close();
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    final expected = _commands == 0 ? _query : _start;
    if (_closing ||
        _writing ||
        _commands >= 2 ||
        content.length != expected.length ||
        !_same(content, expected)) {
      throw StateError('Completion probe permits only one initialization.');
    }
    _neededDeviceReplies = _commands == 0 ? 2 : 1;
    final waiter = _replyWaiter = Completer<void>();
    // Close may happen while the first native write is pending.
    waiter.future.ignore();
    _commands++;
    _writing = true;
    try {
      await _inner.sendFrame(content);
      if (_closing) throw StateError('Completion probe was closed.');
      await _inner.sendFrame(_query);
      // The probe reply must finish too, leaving no hidden partial tail.
      // No new timer: the owning session's original deadline remains active.
      await waiter.future;
    } finally {
      if (identical(_replyWaiter, waiter)) _replyWaiter = null;
      _writing = false;
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
