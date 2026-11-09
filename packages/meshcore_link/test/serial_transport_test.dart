import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:libserialport_plus/libserialport_plus.dart' as native;
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);
Future<void> turn() => Future<void>.delayed(Duration.zero);
Matcher failureKind(SerialTransportFailureKind kind) =>
    isA<SerialTransportFailure>().having((e) => e.kind, 'kind', kind);

void main() {
  test(
    'lazy access, listener/argument/platform guards precede acquisition',
    () async {
      for (final scenario in [
        'lazy',
        'listener',
        'path',
        'baud',
        'timeout',
        'windows',
        'ios',
        'fuchsia',
      ]) {
        var acquisitions = 0;
        final transport = serialTransportForTest(
          portPath: scenario == 'path' ? ' \t' : '/dev/test',
          baudRate: scenario == 'baud' ? 0 : 115200,
          writeTimeout: scenario == 'timeout'
              ? Duration.zero
              : const Duration(seconds: 2),
          operatingSystem: ['windows', 'ios', 'fuchsia'].contains(scenario)
              ? scenario
              : 'macos',
          createConnection: (_) {
            acquisitions++;
            throw StateError('Must not acquire');
          },
        );
        final events = <Object>[];
        final subscription = scenario == 'listener'
            ? null
            : transport.frames.listen(events.add, onError: events.add);
        expect(acquisitions, 0);
        if (scenario != 'lazy') {
          await expectLater(transport.open(), throwsA(anything));
        }
        await transport.close();
        await subscription?.cancel();
        expect(acquisitions, 0, reason: scenario);
      }
    },
  );

  test(
    'exact path, single open, and minimal native configuration mapping',
    () async {
      final h = Harness(path: ' /dev/explicit ');
      expect(h.paths, isEmpty);
      await h.transport.open();
      expect(h.paths, [' /dev/explicit ']);
      expect(h.connection.calls, ['open', 'configure:115200', 'reader']);
      await expectLater(h.transport.open(), throwsStateError);
      final config = serialTransportConfig(115200);
      expect(config.baudRate, 115200);
      expect(config.bits, 8);
      expect(config.parity, native.SerialPortParity.none);
      expect(config.stopBits, 1);
      expect(config.xonXoff, native.SerialPortXonXoff.disabled);
      expect(config.cts, native.SerialPortCts.ignore);
      expect(config.dsr, native.SerialPortDsr.ignore);
      expect(config.rts, isNull);
      expect(config.dtr, isNull);
      await h.finish();
      await expectLater(h.transport.open(), throwsStateError);
      expect(h.connection.calls, [
        'open',
        'configure:115200',
        'reader',
        'stop',
        'cancelReader',
        'close',
        'dispose',
      ]);
    },
  );

  test(
    'open, configuration, and reader setup failures clean acquired resources',
    () async {
      for (final stage in ['open', 'configure', 'reader']) {
        final h = Harness();
        h.connection.failAt.add(stage);
        final opening = h.transport.open();
        await expectLater(
          opening,
          throwsA(
            failureKind(
              stage == 'configure'
                  ? SerialTransportFailureKind.configuration
                  : SerialTransportFailureKind.io,
            ),
          ),
        );
        await h.finish();
        expect(h.connection.calls.last, 'dispose', reason: stage);
        expect(
          h.connection.calls.where((c) => c == 'close'),
          hasLength(stage == 'open' ? 0 : 1),
        );
        expect(h.errors, hasLength(1));
      }
    },
  );

  test(
    'real decoder receives split/coalesced frames with independent ownership',
    () async {
      final h = Harness();
      await h.transport.open();
      h.connection.data([0x3e, 3]);
      final chunk = bytes([0, 0x11, 0x13, 0xff, 0x3e, 1, 0, 7]);
      h.connection.onData(chunk);
      chunk.fillRange(0, chunk.length, 0);
      await turn();
      expect(h.frames, [
        [0x11, 0x13, 0xff],
        [7],
      ]);
      h.connection.data([0x3e, 1, 0, 8]);
      await turn();
      expect(h.frames.first, [0x11, 0x13, 0xff]);
      await h.finish();
    },
  );

  test(
    'valid frames precede terminal decoder error and late data is ignored',
    () async {
      for (final tail in [
        [0x3e, 0, 0],
        List<int>.filled(1025, 0),
      ]) {
        final h = Harness();
        await h.transport.open();
        h.connection.data([0x3e, 1, 0, 9, ...tail]);
        h.connection.data([0x3e, 1, 0, 10]);
        await h.finish();
        expect(
          h.events.map(
            (e) => e is Uint8List
                ? 'frame'
                : e is SerialTransportFailure
                ? 'error'
                : e,
          ),
          ['frame', 'error', 'done'],
        );
        expect(h.frames.single, [9]);
        final error = h.errors.single as SerialTransportFailure;
        expect(error.kind, SerialTransportFailureKind.protocol);
        expect(
          error.protocolError!.kind,
          tail.first == 0x3e
              ? SerialFrameDecodeErrorKind.invalidLength
              : SerialFrameDecodeErrorKind.noiseLimitExceeded,
        );
      }
    },
  );

  test('session waits for the complete body after a standalone serial header', () async {
    for (final bodyArrives in [true, false]) {
      final clock = FakeAsync();
      var cleaned = false;
      clock.run((_) {
        final connection = TestConnection();
        final transport = serialTransportForTest(
          portPath: '/dev/synthetic',
          createConnection: (_) => connection,
        );
        final session = MeshCoreSession(transport: transport);
        MeshCoreSessionInfo? result;
        Object? failure;
        session.connect().then<void>(
          (info) => result = info,
          onError: (Object error) => failure = error,
        );
        clock.flushMicrotasks();
        expect(connection.writes, [
          encodeSerialFrame(encodeDeviceQuery(appTargetVersion: 3)),
        ]);
        final deviceInfo = Uint8List(82)..setRange(0, 2, [0x0d, 14]);
        connection.data([0x3e, 82, 0, ...deviceInfo]);
        clock.flushMicrotasks();
        expect(connection.writes, hasLength(2));
        expect(connection.writes.last, encodeSerialFrame(encodeAppStart()));

        // USB/native read boundaries need not match complete serial frames.
        // A header declaring 64 bytes is not a SELF_INFO response by itself.
        connection.data([0x3e, 64, 0]);
        clock.elapse(const Duration(seconds: 4));
        expect(result, isNull);
        expect(failure, isNull);
        expect(session.info, isNull);
        final body = Uint8List(64)..[0] = 0x05;
        if (bodyArrives) {
          connection.data(body);
          clock.flushMicrotasks();
          expect(result, same(session.info));
          expect(result!.selfInfo.contentLength, 64);
          expect(session.state, MeshCoreSessionState.ready);
        } else {
          clock.elapse(const Duration(seconds: 1));
          expect(failure, same(session.lastFailure));
          expect(
            session.lastFailure!.kind,
            MeshCoreSessionFailureKind.requestTimeout,
          );
          expect(session.lastFailure!.commandOpcode, 0x01);
          expect(session.state, MeshCoreSessionState.failed);
          // A late body cannot revive the terminated session or trigger a
          // diagnostic query/retry to force additional USB traffic.
          connection.data(body);
          clock.flushMicrotasks();
          expect(result, isNull);
          expect(session.info, isNull);
        }
        session.close().then<void>((_) => cleaned = true);
        clock.flushMicrotasks();
        expect(connection.writes, hasLength(2));
        expect(connection.calls.where((call) => call == 'close'), hasLength(1));
        expect(connection.calls.last, 'dispose');
        expect(clock.pendingTimers, isEmpty);
      });
      // The SDK may reuse a cancellation Future from outside the fake zone.
      // Settle that microtask, then finish the zone-local cleanup continuation.
      await turn();
      clock.flushMicrotasks();
      expect(cleaned, isTrue);
    }
  });

  test('encoder, byte ownership, short writes, zero progress, and one in-flight frame', () async {
    final clock = TestClock()..gate = Completer<void>();
    final h = Harness(clock: clock);
    await h.transport.open();
    h.connection.writeCounts.addAll([2, 0, 1, 3]);
    final input = bytes([0x11, 0x13, 5]);
    final sending = h.transport.sendFrame(input);
    input.fillRange(0, input.length, 0);
    await expectLater(h.transport.sendFrame(bytes([99])), throwsStateError);
    expect(h.connection.writes, [
      [0x3c, 3, 0, 0x11, 0x13, 5],
    ]);
    clock.gate!.complete();
    await sending;
    expect(h.connection.writes, [
      [0x3c, 3, 0, 0x11, 0x13, 5],
      [0, 0x11, 0x13, 5],
      [0, 0x11, 0x13, 5],
      [0x11, 0x13, 5],
    ]);
    expect(clock.delays, [
      Duration.zero,
      const Duration(milliseconds: 5),
      Duration.zero,
    ]);
    await expectLater(h.transport.sendFrame(Uint8List(0)), throwsRangeError);
    await h.transport.sendFrame(bytes([7]));
    expect(h.errors, isEmpty);
    await h.finish();
  });

  test('total monotonic deadline is not renewed by partial progress', () async {
    for (final count in [0, 1]) {
      final clock = TestClock();
      final h = Harness(
        clock: clock,
        timeout: const Duration(milliseconds: 12),
      );
      await h.transport.open();
      h.connection.writeOverride = (data) {
        clock.elapsed += const Duration(milliseconds: 4);
        return count;
      };
      Object? caught;
      try {
        await h.transport.sendFrame(bytes([1, 2, 3]));
      } catch (error) {
        caught = error;
      }
      expect(caught, failureKind(SerialTransportFailureKind.writeTimeout));
      expect(h.connection.writes.length, lessThanOrEqualTo(3));
      expect(h.errors.single, same(caught));
      await expectLater(h.transport.sendFrame(bytes([7])), throwsStateError);
      await h.finish();
    }
  });

  test(
    'native write errors and invalid counts terminate without retrying a frame',
    () async {
      for (final result in [-1, 1000, null]) {
        final h = Harness();
        await h.transport.open();
        h.connection.writeOverride = (_) {
          if (result == null) throw const SerialPortFailure('Write failed');
          return result;
        };
        await expectLater(
          h.transport.sendFrame(bytes([1])),
          throwsA(failureKind(SerialTransportFailureKind.io)),
        );
        expect(h.connection.writes, hasLength(1));
        expect(h.errors, hasLength(1));
        await h.finish();
      }
    },
  );

  for (final mode in ['read', 'eof', 'protocol', 'truncated']) {
    test('$mode failure reaches an interrupted send with its terminal reason', () async {
      for (final resumeAfterCleanup in [false, true]) {
        for (final cleanupFails in [false, true]) {
          final clock = TestClock()..gate = Completer<void>();
          final h = Harness(clock: clock);
          final stopped = h.connection.stopGate = Completer<void>();
          await h.transport.open();
          h.connection.writeCounts.add(1);
          if (cleanupFails) h.connection.failAt.add('close');
          final sending = h.transport.sendFrame(bytes([1, 2]));
          final sendResult = sending.then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          final nativeError = const SerialPortFailure('Read interrupted send');
          switch (mode) {
            case 'read':
              h.connection.onError(nativeError, StackTrace.current);
              h.connection.onDone();
            case 'eof':
              h.connection.onDone();
            case 'protocol':
              h.connection.data([0x3e, 0, 0]);
            case 'truncated':
              h.connection.data([0x3e, 2, 0, 1]);
              h.connection.onDone();
          }
          final closeResult = h.transport.close().then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          await turn();
          if (resumeAfterCleanup) {
            stopped.complete();
            await closeResult;
          }
          clock.gate!.complete();
          if (!resumeAfterCleanup) {
            await turn();
            stopped.complete();
          }
          final sendError = await sendResult;
          final closeError = await closeResult;
          await turn();
          await h.subscription.cancel();

          final primary = h.errors.single as SerialTransportFailure;
          expect(
            sendError,
            same(primary),
            reason:
                'cleanup finished before retry: $resumeAfterCleanup; cleanup failed: $cleanupFails',
          );
          expect(primary.kind, switch (mode) {
            'read' => SerialTransportFailureKind.io,
            'eof' => SerialTransportFailureKind.disconnected,
            _ => SerialTransportFailureKind.protocol,
          });
          if (mode == 'read') expect(primary.cause, same(nativeError));
          if (mode == 'protocol' || mode == 'truncated') {
            expect(
              primary.protocolError!.kind,
              mode == 'protocol'
                  ? SerialFrameDecodeErrorKind.invalidLength
                  : SerialFrameDecodeErrorKind.truncatedFrame,
            );
          }
          expect(primary.cleanupErrors, hasLength(cleanupFails ? 1 : 0));
          expect(closeError, cleanupFails ? same(primary) : isNull);
          expect(h.connection.writes, hasLength(1));
          expect(
            h.connection.calls.where((call) => call == 'dispose'),
            hasLength(1),
          );
          expect(h.events.last, 'done');
        }
      }
    });
  }

  test(
    'close interrupts opening/configuration and sending without late access',
    () async {
      for (final stage in ['open', 'configure']) {
        final h = Harness();
        final gate = Completer<void>();
        if (stage == 'open') {
          h.connection.openGate = gate;
        } else {
          h.connection.configureGate = gate;
        }
        final opening = h.transport.open();
        final rejected = expectLater(opening, throwsStateError);
        await expectLater(h.transport.open(), throwsStateError);
        await expectLater(h.transport.sendFrame(bytes([1])), throwsStateError);
        await turn();
        final closing = h.transport.close();
        expect(identical(closing, h.transport.close()), isTrue);
        expect(h.connection.calls, isNot(contains('dispose')));
        gate.complete();
        await rejected;
        await closing;
        expect(h.connection.calls, isNot(contains('reader')));
        expect(h.errors, isEmpty);
        await h.finish();
      }
      for (final action in ['close', 'cancel', 'pause']) {
        final clock = TestClock()..gate = Completer<void>();
        final h = Harness(clock: clock);
        await h.transport.open();
        h.connection.writeCounts.add(1);
        final sending = h.transport.sendFrame(bytes([1, 2]));
        final canceled = expectLater(sending, throwsStateError);
        if (action == 'cancel') await h.subscription.cancel();
        if (action == 'pause') h.subscription.pause();
        await h.transport.close();
        clock.gate!.complete();
        await canceled;
        expect(h.connection.writes, hasLength(1));
        expect(h.errors, isEmpty);
        await h.finish();
      }
    },
  );

  test(
    'reader stop completes before internal cancel and native release',
    () async {
      final h = Harness();
      h.connection.stopGate = Completer<void>();
      await h.transport.open();
      final closing = h.transport.close();
      await turn();
      expect(h.connection.calls.last, 'stop');
      h.connection.data([0x3e, 1, 0, 1]);
      h.connection.onError(
        const SerialPortFailure('Late error'),
        StackTrace.current,
      );
      h.connection.onDone();
      expect(h.events, isEmpty);
      h.connection.stopGate!.complete();
      await closing;
      await h.finish();
      expect(h.connection.calls.sublist(3), [
        'stop',
        'cancelReader',
        'close',
        'dispose',
      ]);
      expect(h.errors, isEmpty);
    },
  );

  test(
    'production reader session keeps subscription until natural done',
    () async {
      var canceled = false;
      final source = StreamController<Uint8List>(
        onCancel: () => canceled = true,
      );
      final stopRequested = Completer<void>();
      final stopResult = Completer<void>();
      final errors = <Object>[];
      final session = SerialReaderSession(
        stream: source.stream,
        stopReader: () {
          stopRequested.complete();
          return stopResult.future;
        },
        onData: (_) {},
        onError: (error, _) => errors.add(error),
        onDone: () {},
      );
      final stopping = session.stop();
      expect(identical(stopping, session.stop()), isTrue);
      await stopRequested.future;
      source.addError(const SerialPortFailure('Read failed'));
      await turn();
      expect(errors, hasLength(1));
      expect(canceled, isFalse);
      stopResult.complete();
      var stopped = false;
      unawaited(stopping.then((_) => stopped = true));
      await turn();
      expect(
        stopped,
        isFalse,
        reason: 'Stop return alone is not natural done evidence.',
      );
      expect(canceled, isFalse);
      await source.close();
      await stopping;
      expect(stopped, isTrue);
      expect(canceled, isTrue);
    },
  );

  test('unexpected EOF, truncation, read error, and deliberate close stay distinct', () async {
    for (final mode in ['eof', 'truncated', 'read', 'close']) {
      final h = Harness();
      await h.transport.open();
      if (mode != 'eof') h.connection.data([0x3e, 2, 0, 1]);
      final nativeError = const SerialPortFailure('Read error');
      if (mode == 'read') {
        h.connection.onError(nativeError, StackTrace.current);
        h.connection.onDone();
      } else if (mode != 'close') {
        h.connection.onDone();
      }
      await h.finish();
      if (mode == 'close') {
        expect(h.errors, isEmpty);
      } else {
        final error = h.errors.single as SerialTransportFailure;
        expect(
          error.kind,
          mode == 'eof'
              ? SerialTransportFailureKind.disconnected
              : mode == 'read'
              ? SerialTransportFailureKind.io
              : SerialTransportFailureKind.protocol,
        );
        if (mode == 'truncated') {
          expect(
            error.protocolError!.kind,
            SerialFrameDecodeErrorKind.truncatedFrame,
          );
        }
        if (mode == 'read') {
          expect(error.cause, same(nativeError));
        }
      }
    }
  });

  test('public pause/cancel and close before opening are idempotent and do not deadlock', () async {
    for (final mode in ['pause', 'cancel', 'created']) {
      final h = Harness();
      if (mode != 'created') await h.transport.open();
      if (mode == 'pause') h.subscription.pause();
      if (mode == 'cancel') await h.subscription.cancel();
      final closing = h.transport.close();
      expect(identical(closing, h.transport.close()), isTrue);
      await closing;
      expect(h.errors, isEmpty);
      if (mode == 'created') {
        expect(h.paths, isEmpty);
      } else {
        expect(h.connection.calls.where((c) => c == 'dispose'), hasLength(1));
      }
      await h.subscription.cancel();
    }
  });

  test('cleanup failures preserve primary; unconfirmed stop never frees; instances stay separate', () async {
    for (final stage in ['stop', 'close', 'dispose']) {
      final h = Harness();
      await h.transport.open();
      h.connection.failAt.add(stage);
      final cause = const SerialPortFailure('Primary read failure');
      h.connection.onError(cause, StackTrace.current);
      Object? closingError;
      try {
        await h.transport.close();
      } catch (error) {
        closingError = error;
      }
      await turn();
      final primary = h.errors.single as SerialTransportFailure;
      expect(closingError, same(primary));
      expect(primary.cause, same(cause));
      expect(primary.cleanupErrors, hasLength(1));
      if (stage == 'stop') {
        expect(h.connection.calls, isNot(contains('cancelReader')));
        expect(h.connection.calls, isNot(contains('close')));
        expect(h.connection.calls, isNot(contains('dispose')));
      }
      await expectLater(h.transport.close(), throwsA(same(primary)));
      await h.subscription.cancel();
      final next = Harness();
      await next.transport.open();
      h.connection.data([0x3e, 1, 0, 1]);
      h.connection.onDone();
      await turn();
      expect(next.events, isEmpty);
      await next.finish();
    }
    final h = Harness();
    await h.transport.open();
    h.connection.failAt.addAll(['close', 'dispose']);
    await expectLater(
      h.transport.close(),
      throwsA(failureKind(SerialTransportFailureKind.cleanup)),
    );
    await turn();
    expect(
      (h.errors.single as SerialTransportFailure).cleanupErrors,
      hasLength(2),
    );
    await h.subscription.cancel();
  });
}

class Harness {
  Harness({
    String path = '/dev/test',
    TestClock? clock,
    Duration timeout = const Duration(seconds: 2),
  }) {
    transport = serialTransportForTest(
      portPath: path,
      writeTimeout: timeout,
      createConnection: (path) {
        paths.add(path);
        return connection;
      },
      createClock: () => clock ?? TestClock(),
    );
    subscription = transport.frames.listen(
      events.add,
      onError: events.add,
      onDone: () => events.add('done'),
    );
  }
  final connection = TestConnection();
  final paths = <String>[];
  final events = <Object>[];
  Iterable<Uint8List> get frames => events.whereType<Uint8List>();
  Iterable<Object> get errors => events.whereType<SerialTransportFailure>();
  late final SerialTransport transport;
  late final StreamSubscription<Uint8List> subscription;

  Future<void> finish() async {
    await transport.close();
    await turn();
    await subscription.cancel();
  }
}

class TestConnection implements NativeSerialConnection {
  final calls = <String>[];
  final failAt = <String>{};
  final writes = <Uint8List>[];
  final writeCounts = <int>[];
  int Function(Uint8List)? writeOverride;
  Completer<void>? openGate;
  Completer<void>? configureGate;
  Completer<void>? stopGate;
  late void Function(Uint8List) onData;
  late void Function(Object, StackTrace) onError;
  late void Function() onDone;
  bool opened = false;
  bool released = false;
  bool reader = false;

  void call(String stage) {
    if (released) throw StateError('Native access after disposal');
    calls.add(stage);
    if (failAt.contains(stage.split(':').first)) {
      throw SerialPortFailure('$stage failed');
    }
  }

  @override
  Future<void> open() async {
    call('open');
    await openGate?.future;
    opened = true;
  }

  @override
  Future<void> configure(int baudRate) async {
    call('configure:$baudRate');
    await configureGate?.future;
  }

  @override
  void startReader({
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  }) {
    call('reader');
    reader = true;
    this.onData = onData;
    this.onError = onError;
    this.onDone = onDone;
  }

  void data(List<int> chunk) => onData(bytes(chunk));
  @override
  Future<void> stopReader() async {
    call('stop');
    await stopGate?.future;
    if (reader) {
      onDone();
      call('cancelReader');
    }
  }

  @override
  int write(Uint8List bytes) {
    call('write');
    writes.add(Uint8List.fromList(bytes));
    return writeOverride?.call(bytes) ??
        (writeCounts.isEmpty ? bytes.length : writeCounts.removeAt(0));
  }

  @override
  void closePort() {
    if (opened) call('close');
  }

  @override
  void dispose() {
    call('dispose');
    released = true;
  }
}

class TestClock implements SerialWriteClock {
  @override
  Duration elapsed = Duration.zero;
  final delays = <Duration>[];
  Completer<void>? gate;
  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    await gate?.future;
    elapsed += duration;
  }
}
