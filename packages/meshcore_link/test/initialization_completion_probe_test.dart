import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart';
import 'package:test/test.dart';

import '../tool/support/initialization_completion_probe.dart';
import '../tool/support/initialization_trace.dart';

void main() {
  test('standard initialization still fails for the simulated held body', () {
    fakeAsync((clock) {
      final h = Harness(probe: false);
      MeshCoreSessionFailure? failure;
      h.session.connect().then<void>(
        (_) => fail('Must not reach ready'),
        onError: (Object e) => failure = e as MeshCoreSessionFailure,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 15));
      clock.flushMicrotasks();
      expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
      expect(failure!.commandOpcode, 22);
      expect(h.native.opcodes, [22]);
      expect(h.observed.disposeConfirmed, isTrue);
    });
  });

  test(
    'probe completes both held replies with exactly four bounded writes',
    () async {
      final h = Harness(probe: true);
      final info = await h.session.connect();
      expect(info.deviceInfo.protocolVersion, 14);
      expect(info.selfInfo.contentLength, 64);
      await h.session.close();
      expect(h.native.opcodes, [22, 22, 1, 22]);
      expect(h.observed.acceptedBytes, 34);
      expect(h.observed.completedCommandFrames, 4);
      expect(h.observed.blockedWrites, 0);
      expect(
        h.observed.readerStopConfirmed &&
            h.observed.portCloseConfirmed &&
            h.observed.disposeConfirmed,
        isTrue,
      );
      expect(h.native.closes, 1);
    },
  );

  test('a probe that does not release the body cannot manufacture success', () {
    fakeAsync((clock) {
      final h = Harness(probe: true)..native.releaseHeld = false;
      MeshCoreSessionFailure? failure;
      h.session.connect().then<void>(
        (_) => fail('Must not reach ready'),
        onError: (Object e) => failure = e as MeshCoreSessionFailure,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 14));
      expect(failure, isNull);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
      expect(h.session.info, isNull);
      expect(h.native.opcodes, [22, 22]);
      expect(h.observed.disposeConfirmed, isTrue);
    });
  });

  test(
    'duplicate DEVICE_INFO never satisfies SELF_INFO or renews its deadline',
    () {
      fakeAsync((clock) {
        final h = Harness(probe: true)..native.noSelf = true;
        MeshCoreSessionFailure? failure;
        h.session.connect().then<void>(
          (_) => fail('Wrong-type replies cannot reach ready'),
          onError: (Object e) => failure = e as MeshCoreSessionFailure,
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 14));
        h.native.emit(h.native.device);
        clock.flushMicrotasks();
        expect(failure, isNull);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
        expect(failure!.commandOpcode, 1);
        expect(failure!.expectedResponseOpcode, 5);
        expect(h.native.opcodes, [22, 22, 1, 22]);
        expect(h.session.info, isNull);
      });
    },
  );

  test(
    'post-initialization commands are refused before inner writes',
    () async {
      final h = Harness(probe: true);
      await h.session.connect();
      final count = h.native.opcodes.length;
      await expectLater(
        h.probe!.sendFrame(encodeSyncNextMessage()),
        throwsStateError,
      );
      expect(h.native.opcodes.length, count);
      expect(count, 4);
      await h.session.close();
    },
  );

  test(
    'close while first write is pending prevents a later probe write',
    () async {
      final inner = HeldTransport();
      final probe = InitializationCompletionProbe(inner);
      final sending = probe.sendFrame(encodeDeviceQuery(appTargetVersion: 3));
      final check = expectLater(sending, throwsStateError);
      await probe.close();
      inner.gate.complete();
      await check;
      expect(inner.writes, 1);
      expect(inner.closes, 1);
    },
  );

  test('original SELF_INFO cannot hide an incomplete final probe reply', () {
    fakeAsync((clock) {
      final h = Harness(probe: true)..native.holdLastDevice = true;
      MeshCoreSessionFailure? failure;
      h.session.connect().then<void>(
        (_) => fail('Probe reply must also finish'),
        onError: (Object e) => failure = e as MeshCoreSessionFailure,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 15));
      clock.flushMicrotasks();
      expect(h.native.opcodes, [22, 22, 1, 22]);
      expect(h.session.info, isNull);
      expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
      expect(failure!.commandOpcode, 1);
      expect(h.observed.disposeConfirmed, isTrue);
    });
  });
}

final class Harness {
  Harness({required bool probe}) {
    observed = InitializationTraceConnection(
      native,
      InitializationTrace(),
      completionProbe: probe,
    );
    final transport = serialTransportForTest(
      portPath: '/dev/test',
      createConnection: (_) => observed,
    );
    final completion = probe ? InitializationCompletionProbe(transport) : null;
    this.probe = completion;
    session = MeshCoreSession(
      transport: completion ?? transport,
      requestTimeout: const Duration(seconds: 15),
      initializationTimeout: const Duration(seconds: 30),
    );
  }
  final native = HeldDevice();
  late final InitializationTraceConnection observed;
  late final MeshCoreSession session;
  InitializationCompletionProbe? probe;
}

/// Software mechanism model, not firmware/hardware evidence.
final class HeldDevice implements NativeSerialConnection {
  final device = Uint8List(82)..setRange(0, 2, [13, 14]);
  final self = Uint8List(64)..[0] = 5;
  final opcodes = <int>[];
  bool releaseHeld = true;
  bool noSelf = false;
  bool holdLastDevice = false;
  Uint8List? held;
  late void Function(Uint8List) onData;
  int closes = 0;

  void emit(Uint8List content) {
    final framed = encodeSerialFrame(content)..[0] = 62;
    scheduleMicrotask(() => onData(framed));
  }

  void hold(Uint8List content, int firstBodyBytes) {
    final framed = encodeSerialFrame(content)..[0] = 62;
    final prefix = Uint8List.sublistView(framed, 0, 3 + firstBodyBytes);
    held = Uint8List.sublistView(framed, 3 + firstBodyBytes);
    scheduleMicrotask(() => onData(prefix));
  }

  @override
  void open() {}
  @override
  void configure(int baudRate) {}
  @override
  void startReader({
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  }) {
    this.onData = onData;
  }

  @override
  int write(Uint8List bytes) {
    final opcode = bytes[3];
    opcodes.add(opcode);
    if (opcode == 22) {
      if (held != null) {
        if (!releaseHeld) return bytes.length;
        final tail = held!;
        held = null;
        scheduleMicrotask(() => onData(tail));
      }
      if (opcodes.length == 1) {
        hold(device, 18);
      } else if (holdLastDevice && opcodes.length == 4) {
        hold(device, 18);
      } else {
        emit(device);
      }
    } else if (opcode == 1 && !noSelf) {
      hold(self, 0);
    }
    return bytes.length;
  }

  @override
  Future<void> stopReader() async {}
  @override
  void closePort() => closes++;
  @override
  void dispose() {}
}

final class HeldTransport implements CompanionTransport {
  final gate = Completer<void>();
  int writes = 0, closes = 0;
  @override
  Stream<Uint8List> get frames => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<void> close() async => closes++;
  @override
  Future<void> sendFrame(Uint8List content) async {
    writes++;
    await gate.future;
  }
}
