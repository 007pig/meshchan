import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

/// Source-peer evidence for the existing consuming read, without another reader.
///
/// This forwards the session's single stream and every operation unchanged. A
/// completed GET_MSG write proves that the receive pump issued its first read;
/// it does not prove a remote message, a response, or continued session health.
final class ReceptionObserverTransport implements CompanionTransport {
  ReceptionObserverTransport(this.inner, {required this.onFirstReadWritten});

  final CompanionTransport inner;
  final void Function() onFirstReadWritten;
  bool _reported = false;

  @override
  Stream<Uint8List> get frames => inner.frames;

  @override
  Future<void> open() => inner.open();

  @override
  Future<void> sendFrame(Uint8List content) async {
    await inner.sendFrame(content);
    if (!_reported && content.length == 1 && content.single == 0x0a) {
      _reported = true;
      onFirstReadWritten();
    }
  }

  @override
  Future<void> close() => inner.close();
}
