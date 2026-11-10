import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/meshctl.dart';
import 'package:meshctl/src/process_io.dart';
import 'package:test/test.dart';

import 'meshctl_test.dart' show FakeSerialPorts;

const second = Duration(seconds: 1);

void main() {
  test(
    'session syntax, semantic bounds, and short circuits precede all effects',
    () async {
      final cases = <(List<String>, int)>[
        for (final command in ['info', 'watch']) ...[
          ([command, '--help'], 0),
          ([command, '-h', '--timeout=bad'], 0),
          (['--help', command], 0),
          (['--version', command], 0),
          ([command], 64),
          ([command, '--port'], 64),
          ([command, '--port='], 64),
          ([command, '--port', ' \t '], 64),
          ([command, '--help', '--unknown'], 64),
          ([command, '--port=synthetic', 'extra'], 64),
          for (final option in [
            'timeout',
            'init-timeout',
            'duration',
            'startup-delay',
          ])
            for (final value in [
              '',
              '-1',
              '1.1',
              'NaN',
              'Infinity',
              ' 1',
              '+1',
              '999999999999999999999999',
            ])
              ([command, '--port=synthetic', '--$option=$value'], 64),
          ([command, '--port=synthetic', '--timeout=0'], 64),
          ([command, '--port=synthetic', '--init-timeout=86401'], 64),
          ([command, '--port=synthetic', '--timeout=86401'], 64),
          ([command, '--port=synthetic', '--startup-delay=86400000'], 64),
          ([command, '--port=synthetic', '--startup-delay=15000'], 64),
          (
            [
              command,
              '--port=synthetic',
              '--startup-delay=1000',
              '--init-timeout=1',
            ],
            64,
          ),
        ],
        (['watch', '--port=synthetic', '--duration=0'], 64),
        (['watch', '--port=synthetic', '--duration=86401'], 64),
        (['info', '--port=synthetic', '--duration=1'], 64),
        (['--version', 'info', 'extra'], 64),
        (['--version', 'watch', '--unknown'], 64),
      ];
      for (final (args, expected) in cases) {
        final ports = FakeSerialPorts();
        var creations = 0;
        var listeners = 0;
        final stops = StreamController<CliStopRequest>.broadcast(
          onListen: () => listeners++,
        );
        final out = StringBuffer();
        final err = StringBuffer();
        expect(
          await runCli(
            args,
            output: out,
            error: err,
            serialPorts: ports,
            createTransport: (_) {
              creations++;
              throw StateError('Unexpected device access');
            },
            stopRequests: stops.stream,
          ),
          expected,
          reason: '$args',
        );
        expect(creations, 0);
        expect(listeners, 0);
        expect(ports.listCalls, 0);
        expect(ports.checkedPaths, isEmpty);
        if (expected == 64) expect(out.toString(), isEmpty);
        expect(err.toString(), isNot(contains('#0')));
        await stops.close();
      }
    },
  );

  test(
    'ports and port-check JSON retain sorting, nulls, warnings and failures',
    () async {
      final ports = FakeSerialPorts()
        ..descriptions = [
          const SerialPortDescription(path: 'z', warning: 'gone\nnow'),
          const SerialPortDescription(path: 'a', usbVid: 42, usbPid: 7),
        ];
      var out = StringBuffer();
      final err = StringBuffer();
      expect(
        await runCli(
          ['ports', '--json'],
          output: out,
          error: err,
          serialPorts: ports,
        ),
        0,
      );
      final data = jsonDecode(out.toString()) as Map;
      expect(data['schemaVersion'], 1);
      expect(data['command'], 'ports');
      expect((data['ports'] as List).map((p) => p['path']), ['a', 'z']);
      expect(data['ports'][0]['description'], isNull);
      expect(data['ports'][0]['transport'], isNull);
      expect(data['ports'][0]['usbVid'], 42);
      expect(data['ports'][1]['warning'], 'gone\nnow');
      expect(err.toString(), contains(r'gone\nnow'));
      out = StringBuffer();
      ports.descriptions = [];
      expect(
        await runCli(
          ['ports', '--json'],
          output: out,
          error: err,
          serialPorts: ports,
        ),
        0,
      );
      expect(jsonDecode(out.toString())['ports'], isEmpty);
      out = StringBuffer();
      expect(
        await runCli(
          ['port-check', '--port', ' exact path ', '--json'],
          output: out,
          error: err,
          serialPorts: ports,
        ),
        0,
      );
      expect(ports.checkedPaths, [' exact path ']);
      expect(
        jsonDecode(out.toString()),
        containsPair('protocolChecked', false),
      );
      expect(jsonDecode(out.toString()), containsPair('openedAndClosed', true));
      ports.failure = const SerialPortFailure('Enumeration failed');
      for (final args in [
        ['ports', '--json'],
        ['port-check', '--port=synthetic', '--json'],
      ]) {
        out = StringBuffer();
        expect(
          await runCli(args, output: out, error: err, serialPorts: ports),
          69,
        );
        expect(out.toString(), isEmpty);
      }
    },
  );

  test(
    'info uses two real session sends and publishes only after close completes',
    () {
      fakeAsync((clock) {
        final h = Harness(['info', '--port', ' exact synthetic path ']);
        final closing = Completer<void>();
        h.transport.closing = () => closing.future;
        clock.flushMicrotasks();
        expect(h.result.done, isFalse);
        expect(h.out.toString(), isEmpty);
        expect(h.paths, [' exact synthetic path ']);
        expect(h.transport.sent, [
          [0x16, 3],
          encodeAppStart(),
        ]);
        expect(h.transport.opens, 1);
        expect(h.transport.closes, 1);
        closing.complete();
        clock.flushMicrotasks();
        expect(h.result.value, 0);
        expect(h.out.toString(), contains('sessionClosed: true'));
        expect(h.out.toString(), contains('appTargetVersion: 3'));
        expect(h.out.toString(), contains('protocolVersion: 14'));
        expect(h.out.toString(), contains('radioFrequencyKhz: 869525'));
        expect(h.out.toString(), contains('radioBandwidthHz: 125000'));
        expect(h.out.toString(), contains('firmwareVersion: synthetic-fw'));
        expect(h.transport.cancels, 1);
        expect(h.stopCancels, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'info JSON is one complete whitelist projection with nulls and key prefix',
    () {
      fakeAsync((clock) {
        final h = Harness(['info', '--port=synthetic', '--json', '--verbose']);
        h.transport.protocol = 8;
        clock.flushMicrotasks();
        expect(h.result.value, 0);
        final data = jsonDecode(h.out.toString()) as Map;
        expect(data['schemaVersion'], 1);
        expect(data['command'], 'info');
        expect(data['initializationCompleted'], true);
        expect(data['sessionClosed'], true);
        expect(data['appTargetVersion'], 3);
        expect(data['device']['protocolVersion'], 8);
        expect(data['device']['repeatEnabled'], isNull);
        expect(data['device']['pathHashMode'], isNull);
        expect(data['self']['publicKeyPrefix'], 'a0a1a2a3a4a5a6a7');
        expect(data['self']['advertType'], 254);
        expect(data['self']['txPowerDbm'], -4);
        expect(data['self']['maxTxPowerDbm'], 22);
        expect(data['self'].containsKey('publicKey'), false);
        expect(
          h.out.toString().split('\n').where((s) => s.isNotEmpty),
          hasLength(1),
        );
        expect(h.err.toString(), contains('Diagnostic:'));
      });
    },
  );

  test(
    'classified initialization failures report once before pending cleanup',
    () {
      for (final mode in [
        'request',
        'total',
        'rejected',
        'protocol',
        'malformed-control',
        'transport',
      ]) {
        fakeAsync((clock) {
          final h = Harness([
            'info',
            '--port=synthetic',
            if (mode == 'total') '--init-timeout=1',
          ]);
          h.transport.autoRespond = false;
          final close = Completer<void>();
          h.transport.closing = () => close.future;
          if (mode == 'transport') {
            h.transport.opening = () =>
                Future.error(StateError('NATIVE_SECRET'));
          }
          clock.flushMicrotasks();
          if (mode == 'request') clock.elapse(const Duration(seconds: 5));
          if (mode == 'total') clock.elapse(second);
          if (mode == 'rejected') h.transport.receive([1, 4]);
          if (mode == 'protocol') h.transport.receive([5]);
          if (mode == 'malformed-control') h.transport.receive([0x83, 0x42]);
          clock.flushMicrotasks();
          expect(h.result.done, false);
          expect(h.out.toString(), isEmpty);
          expect('Session failure:'.allMatches(h.err.toString()), hasLength(1));
          expect(h.err.toString(), isNot(contains('NATIVE_SECRET')));
          expect(h.transport.closes, 1);
          close.complete();
          clock.flushMicrotasks();
          expect(h.result.value, 69);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test(
    'cleanup failure upgrades success and preserves a prior signal or failure',
    () {
      for (final primary in ['success', 'failure', 'signal', 'stop-cancel']) {
        fakeAsync((clock) {
          final h = Harness(['info', '--port=synthetic']);
          h.transport.autoRespond = primary == 'success';
          h.transport.closing = () =>
              Future.error(StateError('CLEANUP_SECRET'));
          if (primary == 'stop-cancel') {
            h.stopCancellationFailure = StateError('STOP_SECRET');
          }
          clock.flushMicrotasks();
          if (primary == 'failure') h.transport.receive([1, 4]);
          if (primary == 'signal' || primary == 'stop-cancel') {
            h.stops.add(CliStopRequest.sigint);
          }
          clock.flushMicrotasks();
          expect(
            h.result.value,
            primary == 'signal' || primary == 'stop-cancel' ? 130 : 69,
          );
          expect(h.result.error, isNull);
          expect(h.out.toString(), isEmpty);
          expect(
            h.err.toString(),
            contains('resource release was not confirmed'),
          );
          expect(h.err.toString(), isNot(contains('CLEANUP_SECRET')));
          expect(h.err.toString(), isNot(contains('STOP_SECRET')));
          expect(h.transport.closes, 1);
          expect(h.stopCancels, 1);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test('watch emits early states, one ready, and structural summaries without extra sends', () {
    fakeAsync((clock) {
      final h = Harness([
        'watch',
        '--port=synthetic',
        '--json',
        '--duration=1',
      ]);
      clock.flushMicrotasks();
      h.transport.receive([0xfe, ...utf8.encode('PAYLOAD_SECRET')]);
      h.transport.receive([0x83]);
      h.transport.receive([0x00]);
      h.transport.receive([0x0a]);
      h.transport.receive([
        0x1b,
        0xf2,
        0xa5,
        0x5a,
        5,
        0xff,
        0x34,
        0x12,
        14,
        ...utf8.encode('PAYLOAD_SECRET'),
      ]);
      h.transport.receive([
        0x11,
        ...List.filled(10, 0xff),
        ...utf8.encode('CHAT_SECRET'),
      ]);
      h.transport.receive([1, 254]);
      h.transport.receive(selfInfo());
      clock.flushMicrotasks();
      final lines = h.lines;
      expect(lines.where((e) => e['event'] == 'state').map((e) => e['state']), [
        'opening',
        'initializing',
        'ready',
      ]);
      expect(lines.where((e) => e['event'] == 'ready'), hasLength(1));
      expect(
        lines.firstWhere((e) => e['event'] == 'ready')['sessionClosed'],
        false,
      );
      expect(
        lines.where((e) => e['event'] == 'unassociated_response'),
        hasLength(8),
      );
      expect(lines.firstWhere((e) => e['opcode'] == 0xfe)['contentLength'], 15);
      expect(lines.firstWhere((e) => e['opcode'] == 0x83)['contentLength'], 1);
      expect(lines.firstWhere((e) => e['opcode'] == 0x1b)['contentLength'], 23);
      expect(
        lines.firstWhere((e) => e['deviceErrorCode'] == 254)['deviceErrorName'],
        isNull,
      );
      expect(h.out.toString(), isNot(contains('PAYLOAD_SECRET')));
      expect(h.out.toString(), isNot(contains('CHAT_SECRET')));
      expect(h.transport.sent, hasLength(2));
      clock.elapse(second);
      expect(h.result.value, 0);
      expect(h.lines.last, containsPair('event', 'end'));
      expect(h.lines.last, containsPair('reason', 'duration'));
    });
  });

  test('watch NDJSON deduplicates failed event, connect error, getter and later signal', () {
    fakeAsync((clock) {
      final h = Harness(['watch', '--port=synthetic', '--json']);
      h.transport.autoRespond = false;
      final close = Completer<void>();
      h.transport.closing = () => close.future;
      clock.flushMicrotasks();
      h.transport.receive([1, 4]);
      // Signal delivery races the asynchronously queued failure notifications.
      h.stops.add(CliStopRequest.sigterm);
      clock.flushMicrotasks();
      expect(h.lines.where((e) => e['event'] == 'failure'), hasLength(1));
      expect(h.lines.where((e) => e['event'] == 'end'), isEmpty);
      expect(h.result.done, false);
      close.complete();
      clock.flushMicrotasks();
      expect(h.result.value, 69);
      expect('Session failure:'.allMatches(h.err.toString()), hasLength(1));
      expect(h.lines.last, containsPair('cleanup', 'succeeded'));
      expect(h.lines.last, containsPair('reason', 'failure'));
      for (final line in h.lines) {
        expect(line['schemaVersion'], 1);
        expect(line['command'], 'watch');
      }
      expect(h.lines.where((e) => e['event'] == 'end'), hasLength(1));
      expect(h.transport.closes, 1);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('duration starts after ready and startup/request/total budgets map separately', () {
    fakeAsync((clock) {
      final h = Harness([
        'watch',
        '--port=synthetic',
        '--json',
        '--duration=2',
        '--startup-delay=1000',
        '--timeout=2',
        '--init-timeout=4',
      ]);
      h.transport.autoRespond = false;
      clock.flushMicrotasks();
      expect(h.transport.sent, isEmpty);
      clock.elapse(second);
      expect(h.transport.sent, hasLength(1));
      clock.elapse(second);
      h.transport.receive(deviceInfo());
      clock.flushMicrotasks();
      clock.elapse(second);
      h.transport.receive(selfInfo());
      clock.flushMicrotasks();
      expect(h.lines.where((e) => e['event'] == 'ready'), hasLength(1));
      clock.elapse(
        second,
      ); // Past the total initialization deadline, still watching.
      expect(h.result.done, false);
      clock.elapse(second);
      expect(h.result.value, 0);
      expect(h.transport.closes, 1);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'SIGINT/SIGTERM cancel opening, initialization, ready and queued success',
    () {
      for (final request in CliStopRequest.values) {
        for (final phase in [
          'opening',
          'initializing',
          'ready',
          'queued-ready',
          'queued-query',
        ]) {
          fakeAsync((clock) {
            final h = Harness([
              'watch',
              '--port=synthetic',
              '--json',
              '--duration=10',
            ]);
            final opening = Completer<void>();
            final closing = Completer<void>();
            h.transport.closing = () => closing.future;
            if (phase == 'opening') h.transport.opening = () => opening.future;
            h.transport.autoRespond = phase == 'ready';
            clock.flushMicrotasks();
            if (phase == 'queued-ready' || phase == 'queued-query') {
              h.transport.receive(deviceInfo());
              if (phase == 'queued-ready') {
                clock.flushMicrotasks();
                h.transport.receive(selfInfo());
              }
            }
            h.stops.add(request);
            h.stops.add(request);
            clock.flushMicrotasks();
            expect(h.result.done, false);
            expect(h.transport.closes, 1);
            expect(h.lines.where((e) => e['event'] == 'end'), isEmpty);
            if (phase != 'ready') {
              expect(h.lines.where((e) => e['event'] == 'ready'), isEmpty);
            }
            if (phase == 'opening') opening.complete();
            closing.complete();
            clock.flushMicrotasks();
            expect(
              h.result.value,
              request == CliStopRequest.sigint ? 130 : 143,
            );
            expect(h.lines.last['reason'], request.name);
            expect('Stopping;'.allMatches(h.err.toString()), hasLength(1));
            expect(h.stopCancels, 1);
            if (phase == 'queued-query') {
              expect(h.transport.sent, hasLength(1));
            }
            expect(clock.pendingTimers, isEmpty);
          });
        }
      }
    },
  );

  test('ready disconnect terminates once without reconnect, even with failed cleanup', () {
    fakeAsync((clock) {
      final h = Harness([
        'watch',
        '--port=synthetic',
        '--json',
        '--duration=10',
      ]);
      h.transport.closing = () => Future.error(StateError('CLOSE_SECRET'));
      clock.flushMicrotasks();
      h.transport.finish();
      clock.flushMicrotasks();
      expect(h.result.value, 69);
      expect(h.paths, hasLength(1));
      expect(h.transport.opens, 1);
      expect(h.transport.closes, 1);
      expect(h.lines.where((e) => e['event'] == 'failure'), hasLength(1));
      expect(h.lines.last['cleanup'], 'failed');
      expect(h.lines.last['exitCode'], 69);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'sync writes, asynchronous done and flush failures stop the same session',
    () {
      for (final mode in ['sync', 'done', 'flush', 'stderr', 'prior-failure']) {
        fakeAsync((clock) {
          final sink = ControlledSink();
          final h = Harness(
            ['watch', '--port=synthetic', '--json', '--verbose'],
            output: mode == 'stderr' ? null : sink,
            error: mode == 'stderr' ? sink : null,
          );
          clock.flushMicrotasks();
          final writes = sink.writes;
          if (mode == 'prior-failure') {
            sink.writeFails = true;
            h.transport.receiveError(StateError('NATIVE_SECRET'));
          } else if (mode == 'done' || mode == 'stderr') {
            sink.completion.completeError(StateError('OUTPUT_SECRET'));
          } else {
            if (mode == 'sync') sink.writeFails = true;
            if (mode == 'flush') sink.flushFails = true;
            h.transport.receive([0x83]);
          }
          clock.flushMicrotasks();
          expect(h.result.value, mode == 'prior-failure' ? 69 : 74);
          expect(h.transport.closes, 1);
          expect(h.stopCancels, 1);
          expect(h.err.toString(), isNot(contains('OUTPUT_SECRET')));
          expect(sink.writes, lessThanOrEqualTo(writes + 1));
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test('bounded output queue overflows at 128 pending records and observes late flush errors', () {
    fakeAsync((clock) {
      final sink = ControlledSink();
      final h = Harness(['watch', '--port=synthetic', '--json'], output: sink);
      clock.flushMicrotasks();
      final flush = Completer<void>();
      sink.flushing = () => flush.future;
      for (var i = 0; i < 129; i++) {
        h.transport.receive([0x83]);
      }
      clock.flushMicrotasks();
      expect(h.result.value, 74);
      expect(h.transport.closes, 1);
      expect(sink.writes, lessThan(10));
      flush.completeError(StateError('LATE_OUTPUT_SECRET'));
      clock
          .flushMicrotasks(); // The in-flight worker's error is still observed.
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('default and verbose diagnostics omit secrets and terminal text escapes controls', () {
    for (final verbose in [false, true]) {
      fakeAsync((clock) {
        final h = Harness([
          'watch',
          '--port=synthetic',
          if (verbose) '--verbose',
        ]);
        h.transport.nodeName = 'node\n\r\x1b[31m\x07';
        h.transport.model = 'model\n\x1b';
        clock.flushMicrotasks();
        h.transport.receive([0xfe, ...utf8.encode('PAYLOAD_SECRET')]);
        h.transport.receive([0x83]);
        h.transport.receiveError(StateError('NATIVE_SECRET'));
        clock.flushMicrotasks();
        final text = '${h.out}${h.err}';
        for (final secret in [
          'PIN!',
          'LOC!',
          'PAYLOAD_SECRET',
          'NATIVE_SECRET',
          List.generate(32, (i) => (0xa0 + i).toRadixString(16)).join(),
        ]) {
          expect(text, isNot(contains(secret)));
        }
        expect(text, isNot(contains('\x1b')));
        expect(text, isNot(contains('\x07')));
        expect(text, isNot(contains('\r')));
        expect(h.out.toString(), contains(r'node\n\r\u001b[31m\u0007'));
        expect(h.err.toString(), isNot(contains('node')));
        expect(h.err.toString(), isNot(contains('model')));
        expect(h.result.value, 69);
      });
    }
  });

  test(
    'completed invocations release stops/timers and cannot affect the next run',
    () {
      fakeAsync((clock) {
        final first = Harness(['watch', '--port=synthetic', '--duration=1']);
        clock.flushMicrotasks();
        clock.elapse(second);
        expect(first.result.value, 0);
        final previous = first.out.toString();
        first.stops.add(CliStopRequest.sigint);
        first.transport.receive([0x83]);
        final next = Harness([
          'info',
          '--port=other-synthetic',
          '--timeout=86400',
          '--init-timeout=86400',
          '--startup-delay=86399999',
          '--json',
        ]);
        clock.flushMicrotasks();
        expect(next.transport.sent, isEmpty);
        clock.elapse(const Duration(milliseconds: 86399999));
        expect(next.result.value, 0);
        expect(first.out.toString(), previous);
        expect(first.stopCancels, 1);
        expect(next.stopCancels, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test('signal adapter maps supported signals lazily and cancels every subscription', () {
    for (final windows in [false, true]) {
      fakeAsync((clock) {
        final sources = <ProcessSignal, StreamController<ProcessSignal>>{};
        final canceled = <ProcessSignal>[];
        final stream = processStopRequests(
          windows: windows,
          watch: (signal) {
            return (sources[signal] = StreamController<ProcessSignal>(
              onCancel: () {
                canceled.add(signal);
                return Future<void>.value();
              },
            )).stream;
          },
        );
        expect(sources, isEmpty);
        final received = <CliStopRequest>[];
        final sub = stream.listen(received.add);
        expect(
          sources.keys,
          windows
              ? [ProcessSignal.sigint]
              : [ProcessSignal.sigint, ProcessSignal.sigterm],
        );
        for (final entry in sources.entries) {
          entry.value.add(entry.key);
        }
        clock.flushMicrotasks();
        expect(
          received,
          windows ? [CliStopRequest.sigint] : CliStopRequest.values,
        );
        final done = Outcome(sub.cancel());
        clock.flushMicrotasks();
        expect(done.done, true);
        expect(canceled, sources.keys);
      });
    }
  });
}

final class Harness {
  Harness(List<String> args, {StringSink? output, StringSink? error}) {
    stops = StreamController<CliStopRequest>(
      sync: true,
      onCancel: () {
        stopCancels++;
        if (stopCancellationFailure != null) {
          return Future<void>.error(stopCancellationFailure!);
        }
        return Future<void>.value();
      },
    );
    // Configure gates before the command begins, inside the fakeAsync zone.
    result = Outcome(
      Future.microtask(
        () => runCli(
          args,
          output: output ?? out,
          error: error ?? err,
          serialPorts: FakeSerialPorts(),
          createTransport: (path) {
            paths.add(path);
            return transport;
          },
          stopRequests: stops.stream,
        ),
      ),
    );
  }
  final out = StringBuffer();
  final err = StringBuffer();
  final transport = FakeCompanionTransport();
  final paths = <String>[];
  late final StreamController<CliStopRequest> stops;
  late final Outcome<int> result;
  int stopCancels = 0;
  Object? stopCancellationFailure;
  List<Map<String, dynamic>> get lines => const LineSplitter()
      .convert(out.toString())
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .toList();
}

final class Outcome<T> {
  Outcome(Future<T> future) {
    future.then<void>(
      (value) {
        this.value = value;
        done = true;
      },
      onError: (Object error, StackTrace _) {
        this.error = error;
        done = true;
      },
    );
  }
  T? value;
  Object? error;
  bool done = false;
}

/// Only the public transport contract; no native handles or core test imports.
final class FakeCompanionTransport implements CompanionTransport {
  FakeCompanionTransport() {
    controller = StreamController<Uint8List>(
      sync: true,
      onCancel: () {
        cancels++;
        return Future<void>.value();
      },
    );
  }
  late final StreamController<Uint8List> controller;
  final sent = <Uint8List>[];
  int opens = 0;
  int closes = 0;
  int cancels = 0;
  bool autoRespond = true;
  int protocol = 14;
  String nodeName = 'synthetic-node';
  String model = 'synthetic-model';
  Future<void> Function()? opening;
  Future<void> Function()? closing;
  @override
  Stream<Uint8List> get frames => controller.stream;
  @override
  Future<void> open() {
    opens++;
    return opening?.call() ?? Future<void>.value();
  }

  @override
  Future<void> sendFrame(Uint8List content) {
    sent.add(Uint8List.fromList(content));
    if (autoRespond) {
      receive(
        content[0] == 0x16
            ? deviceInfo(protocol: protocol, model: model)
            : selfInfo(name: nodeName),
      );
    }
    return Future<void>.value();
  }

  @override
  Future<void> close() {
    closes++;
    return closing?.call() ?? Future<void>.value();
  }

  void receive(List<int> bytes) => controller.add(Uint8List.fromList(bytes));
  void receiveError(Object error) =>
      controller.addError(error, StackTrace.current);
  void finish() {
    unawaited(controller.close());
  }
}

Uint8List deviceInfo({int protocol = 14, String model = 'synthetic-model'}) {
  final content = Uint8List(
    protocol < 9
        ? 80
        : protocol == 9
        ? 81
        : 82,
  )..setRange(0, 8, [0x0d, protocol, 25, 8, ...ascii.encode('PIN!')]);
  for (final (offset, value) in [
    (8, '2026-11-09'),
    (20, model),
    (60, 'synthetic-fw'),
  ]) {
    final bytes = utf8.encode(value);
    content.setRange(offset, offset + bytes.length, bytes);
  }
  if (protocol >= 9) content[80] = 1;
  if (protocol >= 10) content[81] = 254;
  return content;
}

Uint8List selfInfo({String name = 'synthetic-node'}) {
  final content = Uint8List(58 + utf8.encode(name).length)
    ..setRange(0, 4, [5, 254, 252, 22])
    ..setRange(4, 36, List.generate(32, (i) => 0xa0 + i))
    ..setRange(36, 44, ascii.encode('LOC!LOC!'))
    ..setRange(58, 58 + utf8.encode(name).length, utf8.encode(name));
  ByteData.sublistView(content)
    ..setUint32(48, 869525, Endian.little)
    ..setUint32(52, 125000, Endian.little);
  content[56] = 7;
  content[57] = 5;
  return content;
}

final class ControlledSink implements IOSink {
  final buffer = StringBuffer();
  final completion = Completer<void>();
  int writes = 0;
  bool writeFails = false;
  bool flushFails = false;
  Future<void> Function()? flushing;
  @override
  Future<void> get done => completion.future;
  @override
  void writeln([Object? object = '']) {
    writes++;
    if (writeFails) throw StateError('OUTPUT_SECRET');
    buffer.writeln(object);
  }

  @override
  Future<void> flush() => flushFails
      ? Future.error(StateError('OUTPUT_SECRET'))
      : flushing?.call() ?? Future<void>.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
