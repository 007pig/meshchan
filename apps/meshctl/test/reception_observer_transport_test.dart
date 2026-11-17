import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import '../tool/support/reception_observer_transport.dart';

final class _Transport implements CompanionTransport {
  final input = StreamController<Uint8List>();
  final sent = <Uint8List>[];
  final pending = <Completer<void>>[];
  int opens = 0, closes = 0, streamGets = 0;

  @override
  Stream<Uint8List> get frames {
    streamGets++;
    return input.stream;
  }

  @override
  Future<void> open() async => opens++;

  @override
  Future<void> sendFrame(Uint8List content) {
    sent.add(content);
    final done = Completer<void>();
    pending.add(done);
    return done.future;
  }

  @override
  Future<void> close() async {
    closes++;
    await input.close();
  }
}

void main() {
  test(
    'forwards one stream and reports only the first completed GET_MSG write',
    () async {
      final inner = _Transport();
      var observed = 0;
      final wire = ReceptionObserverTransport(
        inner,
        onFirstReadWritten: () => observed++,
      );
      final received = <Uint8List>[];
      final subscription = wire.frames.listen(received.add);
      await wire.open();
      expect(inner.opens, 1);
      expect(inner.streamGets, 1);
      final incoming = Uint8List.fromList([0x0a]);
      inner.input.add(incoming);
      await Future<void>.delayed(Duration.zero);
      expect(received.single, same(incoming));
      expect(observed, 0);
      for (final bytes in [
        [0x16],
        [1],
        [0x0a, 1],
        [0x0a],
        [0x0a],
      ]) {
        final frame = Uint8List.fromList(bytes);
        final sent = wire.sendFrame(frame);
        expect(inner.sent.last, same(frame));
        expect(observed, inner.sent.length == 5 ? 1 : 0);
        inner.pending.last.complete();
        await sent;
      }
      expect(observed, 1);
      expect(inner.sent.map((v) => v.toList()), [
        [0x16],
        [1],
        [0x0a, 1],
        [0x0a],
        [0x0a],
      ]);
      await wire.close();
      await subscription.cancel();
      expect(inner.closes, 1);
      expect(inner.streamGets, 1);
    },
  );

  test(
    'a failed GET_MSG write is preserved without a false active event',
    () async {
      final inner = _Transport();
      var observed = 0;
      final wire = ReceptionObserverTransport(
        inner,
        onFirstReadWritten: () => observed++,
      );
      final subscription = wire.frames.listen((_) {});
      final sent = wire.sendFrame(Uint8List.fromList([0x0a]));
      final failure = StateError('synthetic write failure');
      final assertion = expectLater(sent, throwsA(same(failure)));
      inner.pending.single.completeError(failure);
      await assertion;
      expect(observed, 0);
      expect(inner.sent, hasLength(1));
      await wire.close();
      await subscription.cancel();
    },
  );
}
