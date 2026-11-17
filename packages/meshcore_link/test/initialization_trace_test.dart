import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart';
import 'package:test/test.dart';

import '../tool/support/initialization_trace.dart';

Uint8List incoming(List<int> body) =>
    encodeSerialFrame(Uint8List.fromList(body))..[0] = 0x3e;

List<Map<String, Object?>> events(InitializationTrace trace) =>
    trace.toJson()['events']! as List<Map<String, Object?>>;

void main() {
  test(
    'execution requires an explicit macOS callout path and exact arguments',
    () {
      expect(
        parseInitializationTraceArguments([
          '--port',
          '/dev/cu.test',
          '--execute',
        ]),
        '/dev/cu.test',
      );
      for (final args in <List<String>>[
        [],
        ['--port', '/dev/cu.test'],
        ['--port', '/dev/cu.test', '--help'],
        ['--port', ' /dev/cu.test', '--execute'],
        ['--port', '/dev/tty.test', '--execute'],
        ['--port', '/dev/cu.test', '--execute', '--retry'],
      ]) {
        expect(parseInitializationTraceArguments(args), isNull);
      }
    },
  );

  test('partial DEVICE_INFO is counted without printing received content', () {
    final trace = InitializationTrace();
    trace.receive(Uint8List.fromList([0x3e, 82, 0]));
    trace.receive(Uint8List.fromList([13, ...List<int>.filled(17, 42)]));
    trace.finish();
    trace.finish();
    expect(trace.receivedBytes, 21);
    expect(trace.receivedChunks, 2);
    expect(trace.completeFrames, 0);
    expect(events(trace).last, containsPair('kind', 'truncatedFrame'));
    expect(events(trace).last['structure'], contains('21 of 85 bytes'));
    expect(
      events(trace).where((e) => e['event'] == 'native_input_projection'),
      hasLength(1),
    );
    expect(jsonEncode(trace.toJson()), isNot(contains('42,42')));
  });

  test(
    'single reader receives the original chunk and logs only frame structure',
    () {
      final trace = InitializationTrace();
      final native = FakeConnection();
      final c = InitializationTraceConnection(native, trace);
      Uint8List? forwarded;
      c.startReader(
        onData: (b) => forwarded = b,
        onError: (_, _) {},
        onDone: () {},
      );
      final chunk = incoming(utf8.encode('sensitive-test-content'));
      native.onData(chunk);
      expect(identical(forwarded, chunk), isTrue);
      expect(native.readers, 1);
      expect(trace.completeFrames, 1);
      expect(
        jsonEncode(trace.toJson()),
        isNot(contains('sensitive-test-content')),
      );
      expect(events(trace).last['contentBytes'], 22);
    },
  );

  test('only exact handshake frames and their partial-write suffixes pass', () {
    final native = FakeConnection()..counts.addAll([2, 3]);
    final c = InitializationTraceConnection(native, InitializationTrace());
    final query = encodeSerialFrame(encodeDeviceQuery(appTargetVersion: 3));
    final app = encodeSerialFrame(encodeAppStart(appName: 'Meshchan'));
    expect(c.write(query), 2);
    expect(c.completedCommandFrames, 0);
    expect(c.write(Uint8List.sublistView(query, 2)), 3);
    expect(c.completedCommandFrames, 1);
    expect(c.write(app), 19);
    expect(c.completedCommandFrames, 2);
    expect(c.acceptedBytes, 24);
    expect(() => c.write(query), throwsStateError);
    expect(c.blockedWrites, 1);
    expect(native.writes, hasLength(3));
  });

  test('inbox command is blocked before any delegate write', () {
    final native = FakeConnection();
    final c = InitializationTraceConnection(native, InitializationTrace());
    expect(
      () => c.write(encodeSerialFrame(encodeSyncNextMessage())),
      throwsStateError,
    );
    expect(native.writes, isEmpty);
  });

  test('reader stop is confirmed only after the delegate completes', () async {
    final native = FakeConnection()..stopGate = Completer<void>();
    final c = InitializationTraceConnection(native, InitializationTrace());
    var stopped = false;
    final stopping = c.stopReader().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(c.readerStopConfirmed, isFalse);
    native.stopGate!.complete();
    await stopping;
    c.closePort();
    c.dispose();
    expect(c.readerStopConfirmed, isTrue);
    expect(native.lifecycle, ['stop', 'close', 'dispose']);
  });

  test(
    'real session timeout retains a header and sends no additional query',
    () {
      fakeAsync((clock) {
        final trace = InitializationTrace();
        final native = FakeConnection();
        final c = InitializationTraceConnection(native, trace);
        final transport = serialTransportForTest(
          portPath: '/dev/test',
          createConnection: (_) => c,
        );
        final session = MeshCoreSession(
          transport: transport,
          requestTimeout: const Duration(seconds: 15),
          initializationTimeout: const Duration(seconds: 30),
        );
        MeshCoreSessionFailure? failure;
        session.connect().then<void>(
          (_) => fail('Must time out'),
          onError: (Object e) {
            failure = e as MeshCoreSessionFailure;
          },
        );
        clock.flushMicrotasks();
        native.onData(Uint8List.fromList([0x3e, 82, 0]));
        clock.elapse(const Duration(seconds: 14));
        expect(failure, isNull);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
        expect(failure!.commandOpcode, 22);
        expect(c.nativeWriteCalls, 1);
        expect(c.acceptedBytes, 5);
        expect(
          c.readerStopConfirmed && c.portCloseConfirmed && c.disposeConfirmed,
          isTrue,
        );
        expect(
          events(trace)
              .where((e) => e['event'] == 'native_input_projection')
              .single['structure'],
          contains('3 of 85 bytes'),
        );
      });
    },
  );

  test(
    'APP_START header-only timeout stays primary after trace finalization',
    () {
      fakeAsync((clock) {
        final trace = InitializationTrace();
        final native = FakeConnection();
        final c = InitializationTraceConnection(native, trace);
        final session = MeshCoreSession(
          transport: serialTransportForTest(
            portPath: '/dev/test',
            createConnection: (_) => c,
          ),
          requestTimeout: const Duration(seconds: 15),
          initializationTimeout: const Duration(seconds: 30),
        );
        MeshCoreSessionFailure? failure;
        session.connect().then<void>(
          (_) => fail('Incomplete SELF_INFO must not reach ready'),
          onError: (Object error) => failure = error as MeshCoreSessionFailure,
        );
        clock.flushMicrotasks();
        final device = Uint8List(82)..setRange(0, 2, [13, 14]);
        final notification = Uint8List(100)..[0] = 0x88;
        native.onData(
          Uint8List.fromList([
            ...List<int>.filled(153, 0),
            ...incoming(notification),
            ...incoming(device),
          ]),
        );
        clock.flushMicrotasks();
        expect(native.writes.map((b) => b[3]), [22, 1]);
        native.onData(Uint8List.fromList([0x3e, 64, 0]));
        clock.elapse(const Duration(seconds: 14));
        expect(failure, isNull);
        expect(session.info, isNull);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(failure!.kind, MeshCoreSessionFailureKind.requestTimeout);
        expect(failure!.commandOpcode, 1);
        expect(failure!.expectedResponseOpcode, 5);
        expect(trace.receivedBytes, 344);
        expect(trace.receivedChunks, 2);
        expect(trace.completeFrames, 2);
        expect(c.acceptedBytes, 24);
        expect(c.nativeWriteCalls, 2);
        expect(c.completedCommandFrames, 2);
        expect(c.blockedWrites, 0);
        expect(
          events(trace)
              .where((e) => e['event'] == 'native_input_projection')
              .single['structure'],
          contains('3 of 67 bytes'),
        );
        expect(
          c.readerStopConfirmed && c.portCloseConfirmed && c.disposeConfirmed,
          isTrue,
        );
      });
    },
  );

  test(
    'real session completes both frames then closes without consuming inbox',
    () async {
      final trace = InitializationTrace();
      final native = FakeConnection();
      final c = InitializationTraceConnection(native, trace);
      native.onWrite = (bytes) {
        final body = Uint8List(bytes[3] == 22 ? 82 : 64);
        body[0] = bytes[3] == 22 ? 13 : 5;
        if (body[0] == 13) body[1] = 14;
        scheduleMicrotask(() => native.onData(incoming(body)));
      };
      final session = MeshCoreSession(
        transport: serialTransportForTest(
          portPath: '/dev/test',
          createConnection: (_) => c,
        ),
      );
      await session.connect();
      await session.close();
      expect(c.completedCommandFrames, 2);
      expect(c.nativeWriteCalls, 2);
      expect(c.blockedWrites, 0);
      expect(trace.completeFrames, 2);
      expect(
        c.readerStopConfirmed && c.portCloseConfirmed && c.disposeConfirmed,
        isTrue,
      );
    },
  );
}

final class FakeConnection implements NativeSerialConnection {
  final counts = <int>[];
  final writes = <Uint8List>[];
  final lifecycle = <String>[];
  int readers = 0;
  late void Function(Uint8List) onData;
  void Function(Uint8List)? onWrite;
  Completer<void>? stopGate;

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
    readers++;
    this.onData = onData;
  }

  @override
  Future<void> stopReader() async {
    lifecycle.add('stop');
    await stopGate?.future;
  }

  @override
  int write(Uint8List bytes) {
    writes.add(Uint8List.fromList(bytes));
    onWrite?.call(bytes);
    return counts.isEmpty ? bytes.length : counts.removeAt(0);
  }

  @override
  void closePort() => lifecycle.add('close');
  @override
  void dispose() => lifecycle.add('dispose');
}
