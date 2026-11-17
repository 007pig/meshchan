import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/device_check.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/usb_initialization_transport.dart';
import 'package:meshcore_link/meshcore_link.dart';

import '../tool/device_fixture.dart';

void main() {
  test(
    'production factory constructs an unopened compatible USB transport',
    () {
      expect(
        createUsbCompanionTransport('/dev/never-open-in-unit-test'),
        isA<UsbInitializationTransport>(),
      );
    },
  );

  test(
    'held replies complete with four frames and one receive subscription',
    () async {
      final raw = _Device();
      final transport = UsbInitializationTransport(raw);
      final session = _session(transport);
      final info = await session.connect();
      expect(info.deviceInfo.protocolVersion, 14);
      expect(raw.opcodes, [22, 22, 1, 22]);
      expect(raw.sent[0], raw.sent[1]);
      expect(raw.sent[2], encodeAppStart(appName: 'Meshchan'));
      expect(raw.sent[3], raw.sent[0]);
      expect(raw.sent.fold<int>(0, (n, frame) => n + frame.length + 3), 34);
      expect(raw.listeners, 1);
      await session.close();
      expect(raw.closes, 1);
    },
  );

  test(
    'finite Device Check uses the complete compatible handshake and closes',
    () async {
      final raw = _Device();
      final check = FiniteDeviceCheck(
        1,
        'explicit-owned-test-port',
        const DeviceCheckOptions(requestSeconds: 15, initializationSeconds: 30),
        createTransport: (_) => UsbInitializationTransport(raw),
        publish: (_) {},
      );
      await check.run();
      expect(check.snapshot.info, isNotNull);
      expect(check.snapshot.released, isTrue);
      expect(check.snapshot.failure, isNull);
      expect(raw.opcodes, [22, 22, 1, 22]);
      expect(raw.closes, 1);
    },
  );

  test(
    'after initialization normal commands pass through once without probes',
    () async {
      final raw = _Device();
      final transport = UsbInitializationTransport(raw);
      final session = _session(transport);
      await session.connect();
      final command = encodeSyncNextMessage();
      await transport.sendFrame(command);
      expect(raw.opcodes, [22, 22, 1, 22, 10]);
      expect(raw.sent.last, command);
      expect(raw.listeners, 1);
      await session.close();
      await expectLater(transport.sendFrame(command), throwsStateError);
      expect(raw.sent.length, 5);
    },
  );

  for (final mode in ['no release', 'no self', 'incomplete extra reply']) {
    testWidgets(
      '$mode retains the original request deadline and cannot reach ready',
      (tester) async {
        final raw = _Device()
          ..releaseHeld = mode != 'no release'
          ..selfReply = mode != 'no self'
          ..lastQueryReply = mode != 'incomplete extra reply';
        final session = _session(UsbInitializationTransport(raw));
        MeshCoreSessionFailure? failure;
        var ready = false;
        session.connect().then<void>(
          (_) => ready = true,
          onError: (Object error) => failure = error as MeshCoreSessionFailure,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 14));
        expect(failure, isNull);
        // An unrelated/duplicate DEVICE_INFO cannot extend the original deadline.
        if (mode == 'no self') raw.received.add(fixtureDeviceInfo());
        await tester.pump(const Duration(seconds: 1));
        expect(ready, isFalse);
        expect(session.info, isNull);
        expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
        expect(failure!.commandOpcode, mode == 'no release' ? 22 : 1);
        expect(raw.opcodes, mode == 'no release' ? [22, 22] : [22, 22, 1, 22]);
        expect(raw.closes, 1);
      },
    );
  }

  test(
    'close during a pending native write prevents the extra query',
    () async {
      final raw = _Device()..writeBarrier = Completer<void>();
      final transport = UsbInitializationTransport(raw);
      final sending = transport.sendFrame(
        encodeDeviceQuery(appTargetVersion: 3),
      );
      final failed = expectLater(sending, throwsStateError);
      await transport.close();
      raw.writeBarrier!.complete();
      await failed;
      expect(raw.opcodes, [22]);
      expect(raw.closes, 1);
    },
  );

  test(
    'cancel during held replies closes the same session without later writes',
    () async {
      final raw = _Device()..releaseHeld = false;
      final session = _session(UsbInitializationTransport(raw));
      final result = expectLater(
        session.connect(),
        throwsA(
          isA<MeshCoreSessionFailure>().having(
            (f) => f.kind,
            'kind',
            MeshCoreSessionFailureKind.canceled,
          ),
        ),
      );
      await raw.secondQuery.future;
      await session.close();
      await result;
      expect(raw.opcodes, [22, 22]);
      expect(raw.closes, 1);
    },
  );

  test('out of order command is refused before native writes', () async {
    final raw = _Device();
    final transport = UsbInitializationTransport(raw);
    await expectLater(transport.sendFrame(encodeAppStart()), throwsStateError);
    expect(raw.sent, isEmpty);
    await transport.close();
  });
}

MeshCoreSession _session(CompanionTransport transport) => MeshCoreSession(
  transport: transport,
  appName: 'Meshchan',
  requestTimeout: const Duration(seconds: 15),
  initializationTimeout: const Duration(seconds: 30),
  startupDelay: Duration.zero,
);

/// Mechanism model: the first device reply is held until a later query.
/// This is hardware-free regression evidence, never a real USB acceptance.
final class _Device implements CompanionTransport {
  _Device() {
    received = StreamController<Uint8List>(onListen: () => listeners++);
  }
  late final StreamController<Uint8List> received;
  final sent = <Uint8List>[];
  final secondQuery = Completer<void>();
  Completer<void>? writeBarrier;
  var releaseHeld = true, selfReply = true, lastQueryReply = true;
  var listeners = 0, closes = 0;
  List<int> get opcodes => sent.map((f) => f.first).toList();
  @override
  Stream<Uint8List> get frames => received.stream;
  @override
  Future<void> open() async {}
  @override
  Future<void> sendFrame(Uint8List frame) async {
    sent.add(Uint8List.fromList(frame));
    if (writeBarrier != null) {
      await writeBarrier!.future;
      return;
    }
    if (sent.length == 2) {
      secondQuery.complete();
      if (releaseHeld) {
        received.add(fixtureDeviceInfo());
        received.add(fixtureDeviceInfo());
      }
    } else if (sent.length == 3 && selfReply) {
      received.add(fixtureSelfInfo());
    } else if (sent.length == 4 && lastQueryReply) {
      received.add(fixtureDeviceInfo());
    }
  }

  @override
  Future<void> close() async {
    closes++;
    unawaited(received.close());
  }
}
