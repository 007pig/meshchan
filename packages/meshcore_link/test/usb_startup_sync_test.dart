import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart'
    show usbInitializationTransportForTest;
import 'package:test/test.dart';

Uint8List deviceInfo([String model = 'Heltec V4.3 OLED']) {
  final bytes = Uint8List(85)..setAll(0, [62, 82, 0, 13, 14]);
  bytes.setAll(23, ascii.encode(model));
  return bytes;
}

final selfInfo = Uint8List(67)..setAll(0, [62, 64, 0, 5]);

class _Device implements NativeSerialConnection {
  late void Function(Uint8List) receive;
  late void Function(Object, StackTrace) readError;
  late void Function() done;
  final List<int> commands = [];
  final startup = Completer<void>();
  final last = Completer<void>();
  final int firstWrites;
  int closed = 0;
  _Device(this.firstWrites);

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
    receive = onData;
    readError = onError;
    done = onDone;
  }

  @override
  int write(Uint8List bytes) {
    commands.add(bytes[3]);
    if (commands.length == firstWrites) startup.complete();
    if (commands.length == firstWrites + 2) last.complete();
    return bytes.length;
  }

  @override
  Future<void> stopReader() async => done();
  @override
  void closePort() => closed++;
  @override
  void dispose() {}
}

class _Run {
  final _Device device;
  final trace = <Map<String, Object?>>[];
  late final MeshCoreSession session;
  late final Future<MeshCoreSessionInfo> connecting;
  _Run({bool app = true, bool candidate = true, Duration? timeout})
    : device = _Device(app ? 2 : 1) {
    session = MeshCoreSession(
      transport: usbInitializationTransportForTest(
        metadata: SerialPortDescription(
          path: '/dev/fixture',
          usbVid: candidate ? 0x303a : null,
          usbPid: candidate ? 0x1001 : null,
        ),
        connection: device,
        appCompletionQueries: app,
        trace: (event, fields) => trace.add({'event': event, ...fields}),
      ),
      appName: 'Meshchan',
      requestTimeout: timeout ?? const Duration(seconds: 1),
    );
    connecting = session.connect();
  }

  Future<void> finish() async {
    await device.last.future;
    device.receive(deviceInfo());
    device.receive(selfInfo);
    await Future<void>.delayed(Duration.zero);
    expect(session.state, MeshCoreSessionState.initializing);
    device.receive(deviceInfo());
    final info = await connecting;
    expect(info.deviceInfo.hardwareModel, 'Heltec V4.3 OLED');
    expect(session.state, MeshCoreSessionState.ready);
  }

  Future<void> close() async {
    await session.close();
    expect(device.closed, 1);
  }
}

void main() {
  test('recovers the attempt 10 structure at every byte split', () async {
    final input = Uint8List(395)
      ..setAll(18, [62, 6, 1])
      ..setAll(225, deviceInfo())
      ..setAll(310, deviceInfo());
    for (final app in [false, true]) {
      for (var split = 0; split <= input.length; split++) {
        final run = _Run(app: app);
        await run.device.startup.future;
        run.device.receive(Uint8List.sublistView(input, 0, split));
        run.device.receive(Uint8List.sublistView(input, split));
        await run.finish();
        expect(run.trace.first, {
          'event': 'deviceInfo',
          'prefixBytes': 225,
          'skippedBytes': 225,
          'recovered': true,
          'framingKind': 'invalidLength',
        });
        expect(run.device.commands, [22, if (app) 22, 1, 22]);
        await run.close();
      }
    }
  });

  for (final swallowed in [false, true]) {
    test('one valid first reply suffices (swallowed: $swallowed)', () async {
      final run = _Run();
      await run.device.startup.future;
      // The preceding frame claims 78 bytes, covering part of the reply.
      run.device.receive(
        Uint8List.fromList([
          if (swallowed) ...[62, 78, 0, 62, ...List.filled(29, 0)],
          ...deviceInfo(),
        ]),
      );
      await run.finish();
      expect(run.trace.first['recovered'], swallowed);
      // Established sessions keep strict framing.
      run.device.receive(Uint8List.fromList([62, 6, 1]));
      await Future<void>.delayed(Duration.zero);
      expect(
        run.session.lastFailure?.kind,
        MeshCoreSessionFailureKind.transport,
      );
      await run.close();
    });
  }

  test(
    'ordinary CLI uses two writes with absent metadata or another model',
    () async {
      for (final candidate in [false, true]) {
        final run = _Run(app: false, candidate: candidate);
        await run.device.startup.future;
        run.device.receive(
          deviceInfo(candidate ? 'Another Board' : 'Heltec V4.3 OLED'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(run.device.commands, [22, 1]);
        run.device.receive(selfInfo);
        await run.connecting;
        await run.close();
      }
    },
  );

  test(
    'rejects invalid prefixes followed by wrong or over-limit replies',
    () async {
      for (final payload in [
        deviceInfo('Another Board'),
        Uint8List.fromList([...List.filled(1022, 0), ...deviceInfo()]),
      ]) {
        final run = _Run();
        final failed = expectLater(
          run.connecting,
          throwsA(isA<MeshCoreSessionFailure>()),
        );
        await run.device.startup.future;
        run.device.receive(
          Uint8List.fromList([62, 6, 1, ...payload, ...List.filled(1203, 0)]),
        );
        await failed;
        expect(
          run.session.lastFailure?.cause,
          isA<SerialTransportFailure>().having(
            (error) => error.protocolError?.kind,
            'framing kind',
            SerialFrameDecodeErrorKind.invalidLength,
          ),
        );
        expect(run.device.commands, [22, 22]);
        await run.close();
      }
    },
  );

  test('truncated startup can be canceled and native error stays a transport error', () async {
    for (final cancel in [false, true]) {
      final run = _Run();
      final failed = expectLater(
        run.connecting,
        throwsA(
          isA<MeshCoreSessionFailure>().having(
            (failure) => failure.kind,
            'kind',
            cancel
                ? MeshCoreSessionFailureKind.canceled
                : MeshCoreSessionFailureKind.transport,
          ),
        ),
      );
      await run.device.startup.future;
      run.device.receive(Uint8List.sublistView(deviceInfo(), 0, 8));
      if (cancel) {
        await run.close();
      } else {
        run.device.readError(
          StateError('simulated read failure'),
          StackTrace.current,
        );
      }
      await failed;
      await run.close();
    }
  });

  test('duplicate DeviceInfo without SelfInfo cannot complete', () async {
    final run = _Run(timeout: const Duration(milliseconds: 50));
    final failed = expectLater(
      run.connecting,
      throwsA(isA<MeshCoreSessionFailure>()),
    );
    await run.device.startup.future;
    run.device.receive(deviceInfo());
    await run.device.last.future;
    run.device.receive(deviceInfo());
    await failed;
    expect(
      run.session.lastFailure?.kind,
      MeshCoreSessionFailureKind.requestTimeout,
    );
    expect(run.session.lastFailure?.commandOpcode, 1);
    await run.close();
  });
}
