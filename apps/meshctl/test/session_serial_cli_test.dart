import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart';
import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart';

import 'session_cli_test.dart'
    show ControlledSink, Outcome, deviceInfo, selfInfo;

const _traceFixture = 'usb-trace-fixture';

Future<void> main([List<String> arguments = const []]) async {
  if (arguments.length == 1 && arguments.single == _traceFixture) {
    await _runTraceFixture();
    return;
  }

  for (final closePipe in [true, false]) {
    test(
      'optional USB trace leaves CLI info healthy (closed: $closePipe)',
      () async {
        final child = await Process.start(
          Platform.resolvedExecutable,
          ['run', 'test/session_serial_cli_test.dart', _traceFixture],
          environment: {'MESHCHAN_USB_INITIALIZATION_TRACE': '1'},
        );
        final started = Completer<void>();
        final stdoutLines = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .map((line) {
              if (line == _traceFixture) started.complete();
              return line;
            })
            .toList();
        final diagnostics = StringBuffer();
        final diagnosticsDone = Completer<void>();
        final errors = child.stderr
            .transform(utf8.decoder)
            .listen(diagnostics.write, onDone: diagnosticsDone.complete);
        try {
          await started.future.timeout(const Duration(seconds: 20));
          if (closePipe) await errors.cancel();
          child.stdin.writeln('start');
          await child.stdin.close();
          final code = await child.exitCode.timeout(
            const Duration(seconds: 10),
          );
          final lines = await stdoutLines;
          expect(code, 0, reason: '$lines\n$diagnostics');
          expect(jsonDecode(lines.last)['sessionClosed'], true);
          if (!closePipe) {
            await diagnosticsDone.future;
            expect(
              diagnostics.toString(),
              contains('"usbInitialization":"deviceInfo"'),
            );
          }
        } finally {
          child.kill();
          await child.exitCode;
          await errors.cancel();
        }
      },
      skip: Platform.isWindows ? 'Uses POSIX pipe behavior.' : false,
    );
  }

  test('info and watch share initialization across split bodies and blocked output', () async {
    for (final command in ['info', 'watch']) {
      for (final stage in ['device', 'self']) {
        for (final bodyArrives in [true, false]) {
          for (final blockedOutput in [false, true]) {
            final clock = FakeAsync();
            late Outcome<int> result;
            late SyntheticConnection connection;
            late StringBuffer error;
            late StringBuffer output;
            late ControlledSink sink;
            late Completer<void> flushing;
            clock.run((_) {
              connection = SyntheticConnection();
              error = StringBuffer();
              output = StringBuffer();
              sink = ControlledSink();
              flushing = Completer<void>();
              if (blockedOutput) sink.flushing = () => flushing.future;
              result = Outcome(
                runCli(
                  [
                    command,
                    '--port=synthetic',
                    '--json',
                    if (command == 'watch') ...['--duration', '1'],
                  ],
                  output: blockedOutput ? sink : output,
                  error: error,
                  createTransport: (_) => serialTransportForTest(
                    portPath: 'synthetic',
                    createConnection: (_) => connection,
                  ),
                ),
              );
              clock.flushMicrotasks();
              expect(connection.calls.take(3), [
                'open',
                'configure:115200',
                'reader',
              ]);
              expect(connection.writes, [
                encodeSerialFrame(encodeDeviceQuery(appTargetVersion: 3)),
              ]);
              if (stage == 'self') {
                connection.receive(incoming(deviceInfo()));
                clock.flushMicrotasks();
              }
              final expectedWrites = [
                encodeSerialFrame(encodeDeviceQuery(appTargetVersion: 3)),
                if (stage == 'self') encodeSerialFrame(encodeAppStart()),
              ];
              expect(connection.writes, expectedWrites);
              final content = stage == 'device'
                  ? deviceInfo()
                  : selfInfo(name: 'sixsix');
              final frame = incoming(content);
              // Mirror both captured boundaries: 21/85 or 3/67 bytes, each
              // missing a final 64-byte block, without using any live data.
              final prefixLength = stage == 'device' ? 21 : 3;
              final remainder = frame.sublist(prefixLength);
              expect(remainder, hasLength(64));
              connection.receive(frame.sublist(0, prefixLength));
              clock.elapse(const Duration(milliseconds: 4999));
              expect(connection.calls, isNot(contains('stop')));
              expect(result.done, false);
              final before = blockedOutput
                  ? sink.buffer.toString()
                  : output.toString();
              if (command == 'info') {
                expect(before, isEmpty);
              } else {
                expect(before, isNot(contains('"event":"ready"')));
              }
              if (bodyArrives) {
                connection.receive(remainder);
                clock.flushMicrotasks();
                if (stage == 'device') {
                  expect(
                    connection.writes.last,
                    encodeSerialFrame(encodeAppStart()),
                  );
                  connection.receive(incoming(selfInfo(name: 'sixsix')));
                  clock.flushMicrotasks();
                }
                if (command == 'watch') {
                  // Ready, rather than process start or the header, starts duration.
                  expect(connection.calls, isNot(contains('stop')));
                  clock.elapse(const Duration(seconds: 1));
                }
              } else {
                clock.elapse(const Duration(milliseconds: 1));
                // Late data cannot revive either command or send APP_START.
                connection.receive(remainder);
                clock.flushMicrotasks();
              }
              expect(
                connection.calls.where((call) => call == 'stop'),
                hasLength(1),
              );
              expect(
                connection.calls.sublist(connection.calls.indexOf('stop')),
                ['stop', 'reader.done', 'close', 'dispose'],
              );
              expect(
                connection.writes,
                hasLength(bodyArrives || stage == 'self' ? 2 : 1),
              );
              if (blockedOutput) flushing.complete();
              clock.flushMicrotasks();
            });
            // A canceled SDK stream can return a shared Future from outside the
            // virtual-time zone. Settle it without a real request-budget sleep.
            await Future<void>.delayed(Duration.zero);
            clock.flushMicrotasks();
            expect(result.error, isNull);
            expect(
              result.value,
              bodyArrives ? 0 : 69,
              reason:
                  '$command stage=$stage body=$bodyArrives blocked=$blockedOutput',
            );
            final text = blockedOutput
                ? sink.buffer.toString()
                : output.toString();
            if (command == 'info') {
              if (bodyArrives) {
                expect(jsonDecode(text)['sessionClosed'], true);
              } else {
                expect(text, isEmpty);
              }
            } else {
              final lines = const LineSplitter()
                  .convert(text)
                  .map((line) => jsonDecode(line) as Map)
                  .toList();
              expect(
                lines.where((line) => line['event'] == 'ready'),
                hasLength(bodyArrives ? 1 : 0),
              );
              expect(
                lines.where((line) => line['event'] == 'failure'),
                hasLength(bodyArrives ? 0 : 1),
              );
              expect(lines.last['event'], 'end');
              expect(lines.last['cleanup'], 'succeeded');
              expect(lines.last['exitCode'], result.value);
            }
            if (!bodyArrives) {
              expect(
                'Session failure:'.allMatches(error.toString()),
                hasLength(1),
              );
              expect(error.toString(), contains('"kind":"requestTimeout"'));
              expect(
                error.toString(),
                contains('"commandOpcode":${stage == 'self' ? 1 : 22}'),
              );
              expect(
                error.toString(),
                contains(
                  '"expectedResponseOpcode":${stage == 'self' ? 5 : 13}',
                ),
              );
            }
            expect(clock.pendingTimers, isEmpty);
          }
        }
      }
    }
  });
}

Future<void> _runTraceFixture() async {
  stdout.writeln(_traceFixture);
  await stdout.flush();
  if (stdin.readLineSync() != 'start') {
    throw StateError('Missing fixture start.');
  }
  late final SyntheticConnection connection;
  connection = SyntheticConnection(
    onWrite: (opcode) {
      // Let an asynchronous stderr failure settle before completing the handshake.
      Timer(const Duration(milliseconds: 25), () {
        final reply = opcode == 0x16
            ? deviceInfo(model: 'Heltec V4.3 OLED')
            : selfInfo();
        connection.receive(incoming(reply));
      });
    },
  );
  exitCode = await runCli(
    ['info', '--port=synthetic', '--json'],
    output: stdout,
    error: stderr,
    createTransport: (_) => usbInitializationTransportForTest(
      metadata: const SerialPortDescription(
        path: 'synthetic',
        usbVid: 0x303a,
        usbPid: 0x1001,
      ),
      connection: connection,
      appCompletionQueries: false,
    ),
  );
}

Uint8List incoming(Uint8List content) =>
    Uint8List.fromList([0x3e, content.length, 0, ...content]);

/// Replaces only the native connection; transport, framing, session, CLI, and
/// asynchronous event delivery are the production implementations.
final class SyntheticConnection implements NativeSerialConnection {
  SyntheticConnection({this.onWrite});

  final void Function(int opcode)? onWrite;
  final calls = <String>[];
  final writes = <Uint8List>[];
  late void Function(Uint8List) data;
  late void Function() done;
  @override
  void open() => calls.add('open');
  @override
  void configure(int baudRate) => calls.add('configure:$baudRate');
  @override
  void startReader({
    required void Function(Uint8List) onData,
    required void Function(Object, StackTrace) onError,
    required void Function() onDone,
  }) {
    calls.add('reader');
    data = onData;
    done = onDone;
  }

  void receive(List<int> bytes) => data(Uint8List.fromList(bytes));
  @override
  int write(Uint8List bytes) {
    calls.add('write');
    writes.add(Uint8List.fromList(bytes));
    onWrite?.call(bytes[3]);
    return bytes.length;
  }

  @override
  Future<void> stopReader() {
    calls.add('stop');
    done();
    calls.add('reader.done');
    return Future<void>.value();
  }

  @override
  void closePort() => calls.add('close');
  @override
  void dispose() => calls.add('dispose');
}
