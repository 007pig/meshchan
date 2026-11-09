import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

/// Only the session-facing contract, with deliberately synchronous reception.
final class FakeCompanionTransport implements CompanionTransport {
  FakeCompanionTransport() {
    _frames = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        listenCount++;
        calls.add('listen');
      },
      onPause: () {
        pauseCount++;
        calls.add('pause');
      },
      onCancel: () {
        cancelCount++;
        calls.add('cancel');
        // Keep completion in the test's zone instead of the SDK's shared
        // already-completed cancellation future, which predates fakeAsync.
        return canceling?.call() ?? Future<void>.value();
      },
    );
  }

  late final StreamController<Uint8List> _frames;
  final calls = <String>[];
  final sent = <Uint8List>[];
  int listenCount = 0;
  int openCount = 0;
  int closeCount = 0;
  int cancelCount = 0;
  int pauseCount = 0;
  Future<void> Function()? opening;
  Future<void> Function(Uint8List content, int index)? sending;
  Future<void> Function()? closing;
  Future<void> Function()? canceling;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> open() {
    openCount++;
    calls.add('open');
    return opening?.call() ?? Future.value();
  }

  @override
  Future<void> sendFrame(Uint8List content) {
    final index = sent.length;
    sent.add(Uint8List.fromList(content));
    calls.add('send:${content[0]}');
    return sending?.call(content, index) ?? Future.value();
  }

  @override
  Future<void> close() {
    closeCount++;
    calls.add('close');
    return closing?.call() ?? Future.value();
  }

  void receive(List<int> content) => _frames.add(Uint8List.fromList(content));
  void receiveError(Object error, [StackTrace? stack]) =>
      _frames.addError(error, stack ?? StackTrace.current);
  Future<void> finishInput() => _frames.close();
}
