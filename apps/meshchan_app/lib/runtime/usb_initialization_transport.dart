import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

/// One worker-owned USB connection, with a finite completion-query handshake.
/// Queries solicit subsequent device output without repeating APP_START or
/// extending the owning session's deadlines. Normal commands pass through after
/// the two initialization steps and all extra replies have completed.
final class UsbInitializationTransport implements CompanionTransport {
  UsbInitializationTransport(this._inner);

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
        // The owning session receives the original protocol error unchanged.
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
      waiter.completeError(StateError('USB initialization was closed.'));
    }
    return _inner.close();
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    if (_closing || _writing) {
      throw StateError('USB initialization is closing or writing.');
    }
    if (_commands == 2) {
      await _inner.sendFrame(content);
      return;
    }
    final expected = _commands == 0 ? _query : _start;
    if (content.length != expected.length || !_same(content, expected)) {
      throw StateError('USB initialization command is out of order.');
    }
    _neededDeviceReplies = _commands == 0 ? 2 : 1;
    final waiter = _replyWaiter = Completer<void>();
    // Close can settle this waiter while the first native write is pending.
    waiter.future.ignore();
    _writing = true;
    try {
      await _inner.sendFrame(content);
      if (_closing) throw StateError('USB initialization was closed.');
      await _inner.sendFrame(_query);
      // No independent timer: the original session request/init budgets apply.
      // The extra reply must finish too, leaving no incomplete probe tail.
      await waiter.future;
      _commands++;
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

CompanionTransport createUsbCompanionTransport(String path) =>
    UsbInitializationTransport(SerialTransport(portPath: path));
