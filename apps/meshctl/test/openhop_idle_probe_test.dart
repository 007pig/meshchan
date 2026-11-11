import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import '../tool/support/openhop_idle_probe.dart';

final class _ProbeTransport implements CompanionTransport {
  final controller = StreamController<Uint8List>();
  final sent = <int>[];
  final ready = Completer<void>();
  @override
  Stream<Uint8List> get frames => controller.stream;
  @override
  Future<void> open() async {}
  @override
  Future<void> close() async {
    await controller.close();
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    sent.add(content.first);
    if (content.first == 0x16) {
      controller.add(
        Uint8List.fromList([0x0d, 14, 25, 8, ...List.filled(76, 0), 1, 254]),
      );
    }
    if (content.first == 1) {
      controller.add(Uint8List.fromList([5, 0, 0, 22, ...List.filled(54, 0)]));
      ready.complete();
    }
  }
}

void main() {
  test('passive window reuses initialization and never consumes or sends after ready', () async {
    final transport = _ProbeTransport();
    final result = await runOpenHopIdleProbe(
      transport: transport,
      duration: const Duration(milliseconds: 20),
      commandTimeout: const Duration(seconds: 1),
      initializationTimeout: const Duration(seconds: 2),
    );
    expect(result['status'], 'PASS');
    expect(result['cleanup'], 'succeeded');
    expect(transport.sent, [0x16, 1]);
    expect(result['effectiveConfiguredIdleTimeoutSeconds'], isNull);
    expect(result['noHostCommandsDuringObservation'], isTrue);
  });
  test(
    'disconnect during passive observation cannot pass its window',
    () async {
      final transport = _ProbeTransport();
      final pending = runOpenHopIdleProbe(
        transport: transport,
        duration: const Duration(seconds: 1),
        commandTimeout: const Duration(seconds: 1),
        initializationTimeout: const Duration(seconds: 2),
      );
      await transport.ready.future;
      await transport.controller.close();
      final result = await pending;
      expect(result['status'], 'FAIL');
      expect(result['verifiedIdleWindowLowerBoundSeconds'], isNull);
      expect(result['cleanup'], 'succeeded');
      expect(transport.sent, [0x16, 1]);
    },
  );
}
