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
  final partialWrite = Completer<void>();
  final int firstWrites;
  final int? splitWriteNumber;
  int closed = 0;
  int? _partialOpcode;
  Uint8List? appStart;
  final Uint8List? beforeQuery;
  _Device(this.firstWrites, this.beforeQuery, this.splitWriteNumber);

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
    if (beforeQuery case final bytes?) onData(bytes);
  }

  @override
  int write(Uint8List bytes) {
    final opcode = _partialOpcode ?? bytes[3];
    if (commands.length + 1 == splitWriteNumber && !partialWrite.isCompleted) {
      _partialOpcode = opcode;
      partialWrite.complete();
      return 1;
    }
    _partialOpcode = null;
    commands.add(opcode);
    if (opcode == 1) appStart = bytes;
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
  _Run({
    bool app = true,
    bool candidate = true,
    Duration? timeout,
    Duration startupDelay = Duration.zero,
    Uint8List? beforeQuery,
    bool failTrace = false,
    int? splitWriteNumber,
    String appName = 'Meshchan',
  }) : device = _Device(app ? 2 : 1, beforeQuery, splitWriteNumber) {
    session = MeshCoreSession(
      transport: usbInitializationTransportForTest(
        metadata: SerialPortDescription(
          path: '/dev/fixture',
          usbVid: candidate ? 0x303a : null,
          usbPid: candidate ? 0x1001 : null,
        ),
        connection: device,
        appCompletionQueries: app,
        trace: (event, fields) {
          if (failTrace) throw StateError('diagnostic output closed');
          trace.add({'event': event, ...fields});
        },
      ),
      appName: appName,
      requestTimeout: timeout ?? const Duration(seconds: 1),
      startupDelay: startupDelay,
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

class _FailingCleanup implements CompanionTransport {
  _FailingCleanup(this.closeError);

  final StateError? closeError;
  final cancelError = StateError('cancel failed');
  late final _frames = StreamController<Uint8List>(
    onCancel: () async => throw cancelError,
  );

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> open() async {}

  @override
  Future<void> sendFrame(Uint8List content) async {}

  @override
  Future<void> close() async {
    if (closeError case final error?) throw error;
  }
}

void main() {
  test(
    'stale startup replies cannot satisfy or reject a fresh query',
    () async {
      final staleInfo = deviceInfo();
      final error = Uint8List.fromList([62, 2, 0, 1, 2]);
      for (final stale in [staleInfo, error]) {
        for (final split in [3, stale.length]) {
          final run = _Run(
            app: false,
            beforeQuery: Uint8List.sublistView(stale, 0, split),
            startupDelay: split == stale.length
                ? const Duration(milliseconds: 1)
                : Duration.zero,
          );
          final ready = expectLater(
            run.connecting,
            completion(
              isA<MeshCoreSessionInfo>().having(
                (info) => info.deviceInfo.hardwareModel,
                'model',
                'Another Board',
              ),
            ),
          );
          await run.device.startup.future;
          run.device.receive(
            Uint8List.fromList([
              ...stale.skip(split),
              ...deviceInfo('Another Board'),
            ]),
          );
          await Future<void>.delayed(Duration.zero);
          run.device.receive(selfInfo);
          await ready;
          expect(run.device.commands, [22, 1]);
          await run.close();
        }
      }
    },
  );

  test('a reply received during a short initial write is stale', () async {
    final run = _Run(app: false, splitWriteNumber: 1);
    final ready = expectLater(
      run.connecting,
      completion(
        isA<MeshCoreSessionInfo>().having(
          (info) => info.deviceInfo.hardwareModel,
          'model',
          'Another Board',
        ),
      ),
    );
    await run.device.partialWrite.future;
    run.device.receive(deviceInfo());
    await run.device.startup.future;
    run.device.receive(deviceInfo('Another Board'));
    await Future<void>.delayed(Duration.zero);
    run.device.receive(selfInfo);
    await ready;
    expect(run.device.commands, [22, 1]);
    await run.close();
  });

  test(
    'DEVICE_INFO bytes inside an aligned notification remain payload',
    () async {
      final embedded = deviceInfo();
      final notification = Uint8List.fromList([
        62,
        embedded.length + 2,
        0,
        0x88,
        ...embedded,
        0,
      ]);
      final run = _Run(app: false);
      await run.device.startup.future;
      run.device.receive(
        Uint8List.sublistView(notification, 0, notification.length - 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(run.device.commands, [22]);
      run.device.receive(
        Uint8List.fromList([notification.last, ...deviceInfo('Another Board')]),
      );
      await Future<void>.delayed(Duration.zero);
      run.device.receive(selfInfo);
      final info = await run.connecting;
      expect(info.deviceInfo.hardwareModel, 'Another Board');
      expect(run.device.commands, [22, 1]);
      await run.close();
    },
  );

  test('abandoning lookahead preserves an ordinary partial frame', () async {
    final run = _Run(app: false);
    await run.device.startup.future;
    run.device.receive(
      Uint8List.fromList([
        for (var i = 0; i < 300; i++) ...[62, 1, 0, 0x88],
        ...deviceInfo('Another Board'),
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    run.device.receive(selfInfo);
    expect((await run.connecting).deviceInfo.hardwareModel, 'Another Board');
    expect(run.device.commands, [22, 1]);
    await run.close();
  });

  test('aligned Heltec replies can start beyond the recovery limit', () async {
    for (final app in [false, true]) {
      final run = _Run(app: app);
      await run.device.startup.future;
      run.device.receive(
        Uint8List.fromList([
          for (var i = 0; i < 257; i++) ...[62, 1, 0, 0x83],
          ...deviceInfo(),
        ]),
      );
      await Future.any([
        run.device.last.future,
        run.connecting.then<void>((_) {}),
      ]);
      await run.finish();
      expect(run.trace.first, {
        'event': 'deviceInfo',
        'prefixBytes': 1028,
        'skippedBytes': 0,
        'recovered': false,
      });
      expect(run.device.commands, [22, if (app) 22, 1, 22]);
      await run.close();
    }
  });

  test('a reply that starts during a short final write is stale', () async {
    final stale = deviceInfo();
    for (final app in [false, true]) {
      for (final split in [stale.length, 2, 8]) {
        final run = _Run(app: app, splitWriteNumber: app ? 4 : 3);
        await run.device.startup.future;
        run.device.receive(deviceInfo());
        await run.device.partialWrite.future;
        run.device.receive(selfInfo);
        run.device.receive(Uint8List.sublistView(stale, 0, split));
        await run.device.last.future;
        run.device.receive(Uint8List.sublistView(stale, split));
        await Future<void>.delayed(Duration.zero);
        expect(run.session.state, MeshCoreSessionState.initializing);
        run.device.receive(deviceInfo());
        expect(
          (await run.connecting).deviceInfo.hardwareModel,
          'Heltec V4.3 OLED',
        );
        expect(run.session.state, MeshCoreSessionState.ready);
        await run.close();
      }
    }
  });

  test('SelfInfo can finish after the completion query write', () async {
    final run = _Run(app: false, splitWriteNumber: 3);
    await run.device.startup.future;
    run.device.receive(deviceInfo());
    await run.device.partialWrite.future;
    run.device.receive(Uint8List.sublistView(selfInfo, 0, 3));
    await run.device.last.future;
    run.device.receive(
      Uint8List.fromList([...selfInfo.skip(3), ...deviceInfo()]),
    );
    expect((await run.connecting).deviceInfo.hardwareModel, 'Heltec V4.3 OLED');
    expect(run.session.state, MeshCoreSessionState.ready);
    await run.close();
  });

  test(
    'notifications before the query do not exhaust the recovery window',
    () async {
      final run = _Run(
        beforeQuery: Uint8List.fromList([
          for (var i = 0; i < 310; i++) ...[62, 1, 0, 0x88],
        ]),
      );
      await run.device.startup.future;
      run.device.receive(Uint8List.fromList([62, 6, 1, ...deviceInfo()]));
      await run.finish();
      expect(run.trace.first['skippedBytes'], 3);
      await run.close();
    },
  );

  test(
    'an additional initial reply cannot reclassify an ordinary board',
    () async {
      final run = _Run();
      await run.device.startup.future;
      run.device.receive(
        Uint8List.fromList([...deviceInfo('Another Board'), ...deviceInfo()]),
      );
      await run.device.last.future;
      run.device.receive(deviceInfo('Another Board'));
      run.device.receive(selfInfo);
      expect((await run.connecting).deviceInfo.hardwareModel, 'Another Board');
      await run.close();
    },
  );

  test('a failing trace sink cannot interrupt recovery or close', () async {
    final run = _Run(failTrace: true);
    await run.device.startup.future;
    run.device.receive(Uint8List.fromList([62, 6, 1, ...deviceInfo()]));
    await run.finish();
    await run.close();

    final failed = _Run(failTrace: true);
    final disconnected = expectLater(
      failed.connecting,
      throwsA(isA<MeshCoreSessionFailure>()),
    );
    await failed.device.startup.future;
    failed.device.readError(
      StateError('simulated reader error'),
      StackTrace.current,
    );
    await disconnected;
    await failed.close();
  });

  test('an ordinary CLI read failure has no compatibility stage', () async {
    for (final candidate in [false, true]) {
      for (final ready in [false, true]) {
        final run = _Run(app: false, candidate: candidate);
        final result = ready
            ? run.connecting
            : expectLater(
                run.connecting,
                throwsA(isA<MeshCoreSessionFailure>()),
              );
        await run.device.startup.future;
        run.device.receive(deviceInfo('Another Board'));
        await Future<void>.delayed(Duration.zero);
        expect(run.device.commands, [22, 1]);
        if (ready) {
          run.device.receive(selfInfo);
          await result;
        }
        run.device.readError(
          StateError('simulated reader error'),
          StackTrace.current,
        );
        await result;
        await Future<void>.delayed(Duration.zero);
        await run.close();
        expect(
          run.session.lastFailure?.kind,
          MeshCoreSessionFailureKind.transport,
        );
        expect(
          run.trace.singleWhere(
            (event) => event['event'] == 'transportFailure',
          ),
          {'event': 'transportFailure', 'transportKind': 'io'},
        );
      }
    }
  });

  test('the USB transport preserves a valid custom APP_START name', () async {
    const name = '\uFEFFMesh test 网';
    for (final app in [false, true]) {
      final run = _Run(app: app, appName: name);
      await run.device.startup.future;
      run.device.receive(deviceInfo());
      await Future.any([
        run.device.last.future,
        run.connecting.then<void>((_) {}),
      ]);
      await run.finish();
      expect(
        run.device.appStart,
        encodeSerialFrame(encodeAppStart(appName: name)),
      );
      await run.close();
    }
  });

  test(
    'a session transport requires a subscriber before touching hardware',
    () async {
      final transport = createUsbCompanionTransport('/dev/test-only');
      await expectLater(
        transport.open(),
        throwsA(
          isStateError.having(
            (error) => error.message,
            'message',
            'Subscribe to frames before open().',
          ),
        ),
      );
      await transport.close();
    },
  );

  test(
    'cleanup always ends the stream and preserves the close failure',
    () async {
      for (final closeError in [null, StateError('close failed')]) {
        final inner = _FailingCleanup(closeError);
        final transport = UsbInitializationTransport(inner);
        final done = Completer<void>();
        transport.frames.listen((_) {}, onDone: done.complete);
        await transport.open();
        await expectLater(
          transport.close(),
          throwsA(same(closeError ?? inner.cancelError)),
        );
        await done.future.timeout(const Duration(milliseconds: 100));
      }
    },
  );

  test(
    'a malformed aligned prefix cannot hide the valid Heltec reply',
    () async {
      final run = _Run();
      await run.device.startup.future;
      run.device.receive(Uint8List.fromList([62, 1, 0, 0x0d, ...deviceInfo()]));
      await run.finish();
      expect(run.trace.first['recovered'], true);
      await run.close();
    },
  );

  test('recovers a reply enclosed by a malformed Companion frame', () async {
    final embedded = deviceInfo();
    final notification = [62, 1, 0, 0x83];
    for (final tail in <List<int>>[[], notification]) {
      final run = _Run(timeout: const Duration(milliseconds: 100));
      final events = <MeshCoreSessionEvent>[];
      final observer = run.session.events.listen(events.add);
      await run.device.startup.future;
      final prefix = [62, 1 + embedded.length + tail.length, 0, 0x00];
      run.device.receive(Uint8List.fromList([...prefix, ...embedded]));
      if (tail.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
        expect(run.device.commands, [22, 22]);
        run.device.receive(Uint8List.fromList(tail));
      }
      await Future.any([
        run.device.last.future,
        run.connecting.then<void>((_) {}),
      ]);
      await run.finish();
      expect(run.trace.first, {
        'event': 'deviceInfo',
        'prefixBytes': prefix.length,
        'skippedBytes': prefix.length,
        'recovered': true,
        'companionKind': 'unexpectedResponseLength',
      });
      expect(
        events.whereType<MeshCoreSessionUnassociatedResponse>().where(
          (response) => response.opcode == 0x83,
        ),
        hasLength(tail.isEmpty ? 0 : 1),
      );
      await run.close();
      await observer.cancel();
    }
  });

  test('recovers a new reply inside a malformed pre-query frame', () async {
    final embedded = deviceInfo();
    final run = _Run(
      beforeQuery: Uint8List.fromList([62, embedded.length + 2, 0, 0x0d, 0]),
    );
    await run.device.startup.future;
    run.device.receive(embedded);
    await Future.any([
      run.device.last.future,
      run.connecting.then<void>((_) {}),
    ]);
    await run.finish();
    expect(run.trace.first['recovered'], true);
    expect(run.trace.first['prefixBytes'], 0);
    await run.close();
  });

  test(
    'recovers a complete Heltec reply enclosed by an unsupported frame',
    () async {
      final embedded = deviceInfo();
      final run = _Run();
      await run.device.startup.future;
      run.device.receive(
        Uint8List.fromList([62, embedded.length + 2, 0, 0x0d, 2, ...embedded]),
      );
      await Future.any([
        run.device.last.future,
        run.connecting.then<void>((_) {}),
      ]);
      await run.finish();
      expect(run.trace.first['recovered'], true);
      expect(run.trace.first['companionKind'], 'unsupportedDeviceInfoVersion');
      await run.close();
    },
  );

  test('recovers a Heltec reply that overlaps an unsupported frame', () async {
    for (final app in [false, true]) {
      for (final (split, misalignedError) in [
        (0, false),
        (9, false),
        (9, true),
      ]) {
        final embedded = deviceInfo();
        if (misalignedError) embedded.setAll(10, [62, 2, 0, 1, 2]);
        final run = _Run(app: app);
        await run.device.startup.future;
        final input = Uint8List.fromList([62, 6, 0, 0x0d, 2, ...embedded]);
        run.device.receive(Uint8List.sublistView(input, 0, split));
        run.device.receive(Uint8List.sublistView(input, split));
        await Future.any([
          run.device.last.future,
          run.connecting.then<void>((_) {}),
        ]);
        await run.finish();
        expect(run.trace.first, {
          'event': 'deviceInfo',
          'prefixBytes': 5,
          'skippedBytes': 5,
          'recovered': true,
          'companionKind': 'unsupportedDeviceInfoVersion',
        });
        expect(run.device.commands, [22, if (app) 22, 1, 22]);
        await run.close();
      }
    }
  });

  test(
    'reports unsupported when the overlapping reply cannot validate',
    () async {
      final candidate = deviceInfo('Another Board')..setAll(10, [62, 6, 1]);
      for (final endOfInput in [false, true]) {
        final run = _Run(app: false);
        final failed = expectLater(
          run.connecting,
          throwsA(isA<MeshCoreSessionFailure>()),
        );
        await run.device.startup.future;
        run.device.receive(
          Uint8List.fromList([62, 6, 0, 0x0d, 2, ...candidate.take(4)]),
        );
        await Future<void>.delayed(Duration.zero);
        expect(run.session.state, MeshCoreSessionState.initializing);
        if (endOfInput) {
          run.device.done();
        } else {
          run.device.receive(Uint8List.sublistView(candidate, 4));
        }
        await failed;
        expect(
          run.session.lastFailure?.kind,
          MeshCoreSessionFailureKind.protocol,
        );
        expect(
          run.session.lastFailure?.cause,
          isA<CompanionProtocolException>().having(
            (error) => error.kind,
            'kind',
            CompanionProtocolExceptionKind.unsupportedDeviceInfoVersion,
          ),
        );
        expect(run.device.commands, [22]);
        await run.close();
      }
    },
  );

  test(
    'an unresolved startup retains its Companion decode error in tracing',
    () async {
      final run = _Run(timeout: const Duration(milliseconds: 50));
      final failed = expectLater(
        run.connecting,
        throwsA(isA<MeshCoreSessionFailure>()),
      );
      await run.device.startup.future;
      run.device.receive(Uint8List.fromList([62, 1, 0, 0x0d]));
      await failed;
      await run.close();
      expect(
        run.session.lastFailure?.kind,
        MeshCoreSessionFailureKind.requestTimeout,
      );
      expect(
        run.trace.singleWhere((event) => event['event'] == 'windowClosed'),
        {
          'event': 'windowClosed',
          'bufferedBytes': 4,
          'companionKind': 'truncatedResponse',
        },
      );
    },
  );

  test('an aligned unsupported DeviceInfo is a protocol failure', () async {
    for (final app in [false, true]) {
      final run = _Run(app: app, timeout: const Duration(milliseconds: 100));
      final failed = expectLater(
        run.connecting,
        throwsA(
          isA<MeshCoreSessionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                MeshCoreSessionFailureKind.protocol,
              )
              .having(
                (failure) => failure.cause,
                'cause',
                isA<CompanionProtocolException>().having(
                  (error) => error.kind,
                  'kind',
                  CompanionProtocolExceptionKind.unsupportedDeviceInfoVersion,
                ),
              ),
        ),
      );
      await run.device.startup.future;
      run.device.receive(deviceInfo()..[4] = 2);
      await failed;
      expect(run.device.commands, [22, if (app) 22]);
      await run.close();
    }
  });

  test('an aligned notification is delivered before startup EOF', () async {
    final run = _Run();
    final events = <MeshCoreSessionEvent>[];
    final observer = run.session.events.listen(events.add);
    final failed = expectLater(
      run.connecting,
      throwsA(isA<MeshCoreSessionFailure>()),
    );
    await run.device.startup.future;
    run.device.receive(Uint8List.fromList([62, 1, 0, 0x83]));
    run.device.done();
    await failed;
    await run.close();
    await observer.cancel();
    final response = events
        .whereType<MeshCoreSessionUnassociatedResponse>()
        .single;
    expect(response.opcode, 0x83);
  });

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
