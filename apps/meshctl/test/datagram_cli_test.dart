import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart' hide test;
import 'package:test/test.dart' as testing show test;

import 'meshctl_test.dart' show FakeSerialPorts;
import 'session_cli_test.dart'
    show FakeCompanionTransport, ControlledSink, Outcome, deviceInfo, selfInfo;

const second = Duration(seconds: 1);
final clocks = <FakeAsync>[];
final checks = <void Function()>[];
void test(String description, FutureOr<void> Function() body) {
  testing.test(description, () async {
    clocks.clear();
    checks.clear();
    await body();
    // Cross the SDK's shared pre-zone cancellation Future without real sleeps.
    await Future<void>.delayed(Duration.zero);
    for (final clock in clocks) {
      clock.flushMicrotasks();
    }
    for (final check in checks) {
      check();
    }
  });
}

void virtual(void Function(FakeAsync) body) => fakeAsync((clock) {
  clocks.add(clock);
  body(clock);
});
void settled(void Function() check) => checks.add(check);

List<String> args(
  String operation, {
  String content = '',
  bool json = true,
}) => [
  'datagram',
  operation,
  '--port= synthetic ',
  if (json) '--json',
  '--task-timeout=20',
  if (operation != 'listen') ...['--send-channel=3', '--route-descriptor=0xFF'],
  if (operation != 'send') '--receive-channel=2',
  if (operation == 'send') ...['--data-type=0xFFFF', '--payload-hex=$content'],
  if (operation == 'ping' || operation == 'respond') ...[
    '--local-id=1',
    '--peer-id=0X02',
  ],
  if (operation == 'ping') ...[
    '--content-hex=$content',
    '--response-timeout=2',
  ],
  if (operation == 'listen' || operation == 'respond') '--duration=3',
];
List<String> replace(List<String> source, String option, String? value) => [
  for (final item in source)
    if (!item.startsWith('--$option=')) item,
  if (value != null) '--$option=$value',
];

final class Harness {
  Harness(
    this.clock,
    List<String> arguments, {
    StringSink? output,
    StringSink? error,
  }) {
    stops = StreamController<CliStopRequest>(
      sync: true,
      onListen: () {
        subscriptions++;
      },
      onCancel: () {
        cancellations++;
        return cancelError == null
            ? Future<void>.value()
            : Future<void>.error(cancelError!);
      },
    );
    transport.autoRespond = false;
    result = Outcome(
      Future.microtask(
        () => runCli(
          arguments,
          output: output ?? out,
          error: error ?? err,
          createTransport: (path) {
            paths.add(path);
            return transport;
          },
          stopRequests: stops.stream,
          diagnosticElapsed: () => clock.elapsed,
          diagnosticNonceFactory: () =>
              Uint8List.fromList(List.filled(16, 0xa5)),
        ),
      ),
    );
  }
  final FakeAsync clock;
  final transport = FakeCompanionTransport();
  final out = StringBuffer(), err = StringBuffer();
  final paths = <String>[];
  int subscriptions = 0, cancellations = 0;
  Object? cancelError;
  late final StreamController<CliStopRequest> stops;
  late final Outcome<int> result;
  List<Map<String, dynamic>> get lines => const LineSplitter()
      .convert(out.toString())
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .toList();
  Map<String, dynamic> get finalRecord => lines.last;
  Map<String, dynamic> get facts =>
      finalRecord['result'] as Map<String, dynamic>;
  void ready() {
    clock.flushMicrotasks();
    transport.receive(deviceInfo());
    clock.flushMicrotasks();
    transport.receive(selfInfo());
    clock.flushMicrotasks();
  }

  void receive(List<int> frame) {
    transport.receive(frame);
    clock.flushMicrotasks();
  }

  void empty() => receive([0x0a]);
  void ok() => receive([0]);
  void end(int code) => settled(() {
    expect(result.error, isNull);
    expect(result.value, code);
    expect(finalRecord['exitCode'], code);
    expect(finalRecord['schemaVersion'], 1);
    expect(finalRecord['command'], 'datagram');
    expect(transport.closes, 1);
    expect(subscriptions, 1);
    expect(cancellations, 1);
    expect(clock.pendingTimers, isEmpty);
  });
  MeshchanDiagnosticMessage get sentPing {
    final frame = transport.sent.firstWhere((f) => f[0] == 0x3e);
    return decodeDiagnosticPayload(Uint8List.sublistView(frame, 5)).message!;
  }

  void pong() {
    final ping = sentPing;
    receive(
      datagram(
        encodeDiagnosticPayload(
          MeshchanDiagnosticMessage(
            kind: DiagnosticKind.pong,
            runNonce: ping.runNonce,
            requestId: ping.requestId,
            senderTestId: 2,
            targetTestId: 1,
            content: ping.content,
          ),
        ),
      ),
    );
  }
}

List<int> datagram(List<int> payload, {int channel = 2, int type = 65535}) => [
  0x1b,
  0xf2,
  0,
  0,
  channel,
  0xff,
  type & 255,
  type >> 8,
  payload.length,
  ...payload,
];
List<int> incomingPing({int id = 1, List<int> content = const [0, 128, 255]}) =>
    datagram(
      encodeDiagnosticPayload(
        MeshchanDiagnosticMessage(
          kind: DiagnosticKind.ping,
          runNonce: Uint8List(16),
          requestId: id,
          senderTestId: 2,
          targetTestId: 1,
          content: Uint8List.fromList(content),
        ),
      ),
    );

/// Deliberately delivers a stop during subscription, before task.start().
final class ImmediateSignal extends Stream<CliStopRequest> {
  ImmediateSignal(this.source);
  final Stream<CliStopRequest> source;
  @override
  StreamSubscription<CliStopRequest> listen(
    void Function(CliStopRequest)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    onData?.call(CliStopRequest.sigint);
    return subscription;
  }
}

void main() {
  test('pre-start signal and output cancellation preserve intent without opening hardware', () {
    virtual((clock) {
      final transport = FakeCompanionTransport();
      final out = StringBuffer(), err = StringBuffer();
      var cancels = 0;
      final stops = StreamController<CliStopRequest>(
        onCancel: () {
          cancels++;
          return Future<void>.value();
        },
      );
      final result = Outcome(
        runCli(
          args('ping'),
          output: out,
          error: err,
          createTransport: (_) => transport,
          stopRequests: ImmediateSignal(stops.stream),
          diagnosticElapsed: () => clock.elapsed,
        ),
      );
      clock.flushMicrotasks();
      settled(() {
        expect(result.value, 130);
        expect(cancels, 1);
        expect(transport.opens, 0);
        expect(transport.closes, 0);
        final record = jsonDecode(out.toString());
        expect(record['reason'], 'sigint');
        expect(record['result']['reason'], 'canceled');
        expect(record['cleanup']['state'], 'notRequired');
      });
    });
    virtual((clock) {
      final sink = ControlledSink()..writeFails = true;
      final h = Harness(clock, [...args('ping'), '--verbose'], error: sink);
      clock.flushMicrotasks();
      settled(() {
        expect(h.result.value, 74);
        expect(h.cancellations, 1);
        expect(h.transport.opens, 0);
        expect(h.transport.closes, 0);
        expect(h.finalRecord['reason'], 'output_failure');
        expect(h.facts['reason'], 'canceled');
        expect(h.finalRecord['cleanup']['state'], 'notRequired');
      });
    });
  });

  test('failure of the final flush changes process exit without appending another record', () {
    virtual((clock) {
      final sink = ControlledSink();
      final h = Harness(clock, args('send'), output: sink);
      h.ready();
      sink.flushFails = true;
      h.ok();
      settled(() {
        expect(h.result.value, 74);
        expect(h.transport.closes, 1);
        expect(h.cancellations, 1);
        final lines = const LineSplitter().convert(sink.buffer.toString());
        expect(lines, hasLength(1));
        final record = jsonDecode(lines.single);
        expect(record['exitCode'], 0);
        expect(record['reason'], 'completed');
        expect(record['cleanup']['state'], 'succeeded');
      });
    });
  });
  test('nested syntax, help precedence, and pure validation have zero side effects', () async {
    final cases = <(List<String>, int)>[
      (['datagram'], 0),
      (['datagram', '--help'], 0),
      (['--help', 'datagram', 'ping'], 0),
      (['--version', 'datagram', 'ping'], 0),
      (['--version', 'datagram', '--help', 'ping', '--help'], 0),
      (['datagram', 'PRIVATE_POSITIONAL', '--help'], 64),
      (['--version', 'datagram', 'ping', 'PRIVATE_POSITIONAL'], 64),
      (['datagram', 'send', '--help', '--PRIVATE_UNKNOWN'], 64),
      (
        ['datagram', 'send', '--help', '--text=PRIVATE_TEXT', 'PRIVATE_REST'],
        64,
      ),
      for (final operation in ['send', 'listen', 'ping', 'respond']) ...[
        (['datagram', operation, '--help', '--json'], 0),
        (['datagram', operation], 64),
        (replace(args(operation), 'port', ' \t '), 64),
        (replace(args(operation), 'task-timeout', null), 64),
        for (final name in ['task-timeout', 'timeout', 'init-timeout'])
          for (final value in [
            '0',
            '86401',
            '0x1',
            '+1',
            ' 1',
            '1.0',
            '1_0',
            '',
          ])
            (replace(args(operation), name, value), 64),
        (replace(args(operation), 'startup-delay', '15000'), 64),
        (replace(args(operation), 'startup-delay', '86400000'), 64),
      ],
      for (final name in ['send-channel', 'route-descriptor'])
        for (final value in ['256', '-1', '0x100', ' 1', '1_0', '1.5'])
          (replace(args('send'), name, value), 64),
      for (final name in ['local-id', 'peer-id'])
        for (final value in ['0', '0x100000000', '-1', '0X', '1_0'])
          (replace(args('ping'), name, value), 64),
      (replace(args('ping'), 'peer-id', '1'), 64),
      for (final value in ['4097', '0', '0x10']) ...[
        (replace(args('listen'), 'max-entries', value), 64),
        (replace(args('respond'), 'max-responses', value), 64),
      ],
      (replace(args('send'), 'data-type', '0'), 64),
      (replace(args('listen'), 'data-type', '65536'), 64),
      for (final operation in ['send', 'ping']) ...[
        (
          replace(
            args(operation),
            operation == 'send' ? 'payload-hex' : 'content-hex',
            null,
          ),
          64,
        ),
        ([...args(operation), '--text=PRIVATE_TEXT'], 64),
        for (final value in [
          '0',
          '0x00',
          '00 00',
          'AA:BB',
          'AA,BB',
          '中文',
          'PRIVATE_HEX',
        ])
          (
            replace(
              args(operation),
              operation == 'send' ? 'payload-hex' : 'content-hex',
              value,
            ),
            64,
          ),
      ],
      (replace(args('send'), 'route-descriptor', '1'), 64),
      ([...args('ping'), '--path-hex=aabb'], 64),
      (replace(args('respond'), 'route-descriptor', '0xc0'), 64),
      (
        [
          ...replace(
            args('send', content: '00' * 109),
            'route-descriptor',
            '0x3f',
          ),
          '--path-hex=${'ab' * 63}',
        ],
        64,
      ),
      (
        [
          ...replace(
            args('ping', content: '00' * 75),
            'route-descriptor',
            '0x3f',
          ),
          '--path-hex=${'ab' * 63}',
        ],
        64,
      ),
      (
        replace(replace(args('ping'), 'content-hex', null), 'text', '中' * 44),
        64,
      ),
      for (final (operation, option) in [
        ('send', 'receive-channel'),
        ('listen', 'send-channel'),
        ('ping', 'payload-hex'),
        ('respond', 'text'),
      ])
        ([...args(operation), '--$option=PRIVATE_OPTION'], 64),
    ];
    for (final (arguments, code) in cases) {
      final out = StringBuffer(), err = StringBuffer();
      var factories = 0, subscribed = 0;
      final ports = FakeSerialPorts();
      final stops = StreamController<CliStopRequest>(
        onListen: () {
          subscribed++;
        },
      );
      expect(
        await runCli(
          arguments,
          output: out,
          error: err,
          serialPorts: ports,
          createTransport: (_) {
            factories++;
            throw StateError('hardware');
          },
          stopRequests: stops.stream,
        ),
        code,
        reason: '$arguments',
      );
      expect(factories, 0);
      expect(subscribed, 0);
      expect(ports.listCalls, 0);
      expect(ports.checkedPaths, isEmpty);
      if (code == 64) {
        expect(out.toString(), isEmpty);
        expect(err.toString(), contains('Error:'));
      }
      for (final secret in [
        'PRIVATE_POSITIONAL',
        'PRIVATE_TEXT',
        'PRIVATE_REST',
        'PRIVATE_UNKNOWN',
        'PRIVATE_HEX',
        'PRIVATE_OPTION',
        'abababab',
      ]) {
        expect(err.toString(), isNot(contains(secret)));
      }
      stops.close().ignore();
    }
  });

  test('raw send preserves empty, UTF-8, HEX and route bytes without reads or diagnostic headers', () {
    for (final (content, text) in [
      ('', false),
      ('0080ff', false),
      ('中文', true),
    ]) {
      virtual((clock) {
        final input = text
            ? replace(
                replace(args('send'), 'payload-hex', null),
                'text',
                content,
              )
            : args('send', content: content);
        final h = Harness(clock, replace(input, 'send-channel', '003'));
        h.ready();
        expect(h.transport.sent.map((f) => f[0]), [0x16, 1, 0x3e]);
        expect(h.transport.sent.last, [
          0x3e,
          3,
          255,
          255,
          255,
          ...text
              ? utf8.encode(content)
              : content.isEmpty
              ? <int>[]
              : [0, 128, 255],
        ]);
        h.ok();
        h.end(0);
        settled(() {
          expect(h.paths, [' synthetic ']);
          expect(h.lines, hasLength(1));
          expect(h.facts['send']['deviceAcceptanceConfirmed'], true);
        });
      });
    }
  });

  test('listen filters after consumption and drains the final entry before entry-limit settlement', () {
    virtual((clock) {
      final h = Harness(clock, [
        ...args('listen'),
        '--data-type=0',
        '--max-entries=4',
      ]);
      h.ready();
      h.receive(datagram([99], type: 0));
      h.receive([0x11, ...List.filled(10, 0), ...utf8.encode('PRIVATE_CHAT')]);
      h.receive(datagram([12], channel: 3, type: 0));
      h.receive(datagram([13], type: 2));
      h.end(0);
      settled(() {
        expect(h.transport.sent.any((f) => f[0] == 0x3e), false);
        expect(h.lines.map((e) => e['event']), ['datagram', 'end']);
        expect(h.lines.first, containsPair('snrDb', -3.5));
        expect(h.lines.first['payloadLength'], 1);
        expect(h.facts, {
          'receptionReason': 'entryLimit',
          'publishedEntries': 4,
          'processedEntries': 4,
          'matchingDatagrams': 1,
          'filteredDatagrams': 2,
          'ordinaryMessages': 1,
        });
        expect('${h.out}${h.err}', isNot(contains('PRIVATE_CHAT')));
      });
    });
  });

  test('listen silence ends normally and its duration begins after ready', () {
    virtual((clock) {
      final h = Harness(clock, args('listen'));
      clock.flushMicrotasks();
      clock.elapse(second);
      h.ready();
      h.empty();
      clock.elapse(const Duration(seconds: 2));
      expect(h.result.done, false);
      clock.elapse(second);
      h.end(0);
      settled(() {
        expect(h.facts['receptionReason'], 'durationElapsed');
        expect(h.facts['processedEntries'], 0);
      });
    });
  });

  test('ping uses real correlation, separate channels, exact content, and core microsecond RTT', () {
    virtual((clock) {
      final h = Harness(clock, args('ping', content: '0080ff'));
      h.ready();
      h.empty();
      h.ok();
      final ping = h.sentPing;
      expect(ping.senderTestId, 1);
      expect(ping.targetTestId, 2);
      expect(ping.content, [0, 128, 255]);
      clock.elapse(const Duration(microseconds: 1234));
      h.pong();
      h.end(0);
      settled(() {
        expect(h.lines, hasLength(1));
        expect(h.facts['reason'], 'completed');
        expect(h.facts['applicationRttUs'], 1234);
        expect(h.facts['firstMatchingPongElapsedUs'], 1234);
        expect(h.facts['roundTripSucceeded'], true);
        expect(h.facts['matchingPongObserved'], true);
      });
    });
  });

  test('early matching PONG remains observed after a failed local write, without success RTT', () {
    virtual((clock) {
      final h = Harness(clock, args('ping'));
      final write = Completer<void>();
      h.transport.sending = (frame) =>
          frame[0] == 0x3e ? write.future : Future<void>.value();
      h.ready();
      h.empty();
      h.ok();
      clock.elapse(const Duration(microseconds: 7));
      h.pong();
      write.completeError(StateError('PRIVATE_WRITE'));
      clock.flushMicrotasks();
      h.end(69);
      settled(() {
        expect(h.facts['matchingPongObserved'], true);
        expect(h.facts['firstMatchingPongElapsedUs'], 7);
        expect(h.facts['applicationRttUs'], isNull);
        expect(h.facts['roundTripSucceeded'], false);
        expect(h.facts['send']['localOkObserved'], true);
        expect(h.facts['send']['deviceAcceptanceConfirmed'], false);
        expect('${h.out}${h.err}', isNot(contains('PRIVATE_WRITE')));
      });
    });
  });

  test('responder uses real PONG task, local route and cumulative counts with a last-send projection', () {
    virtual((clock) {
      final h = Harness(clock, [...args('respond'), '--max-responses=2']);
      h.ready();
      h.receive(incomingPing());
      h.ok();
      clock.elapse(Duration.zero);
      h.receive(incomingPing(id: 2));
      h.ok();
      h.end(0);
      settled(() {
        expect(h.facts['reason'], 'completed');
        expect(h.facts['listenStopReason'], 'responseLimit');
        expect(h.facts['responseAttempts'], 2);
        expect(h.facts['localResponsesConfirmed'], 2);
        expect(h.facts['lastSend']['deviceAcceptanceConfirmed'], true);
        expect(h.facts.containsKey('send'), false);
        expect(
          h.transport.sent
              .where((f) => f[0] == 0x3e)
              .every((f) => f[1] == 3 && f[4] == 255),
          true,
        );
      });
    });
  });

  test('responder zero responses is a normal finite result with nullable send facts', () {
    virtual((clock) {
      final h = Harness(clock, args('respond'));
      h.ready();
      h.empty();
      clock.elapse(const Duration(seconds: 3));
      h.end(0);
      settled(() {
        expect(h.facts['listenStopReason'], 'durationElapsed');
        expect(h.facts['responseAttempts'], 0);
        expect(h.facts['lastSend']['dispatched'], isNull);
        expect(h.facts['lastSend']['attempted'], false);
      });
    });
  });

  test(
    'listen does not commit entry-limit success before the owned read settles',
    () {
      virtual((clock) {
        final h = Harness(clock, [...args('listen'), '--max-entries=1']);
        final read = Completer<void>();
        h.transport.sending = (f) =>
            f[0] == 0x0a ? read.future : Future<void>.value();
        h.ready();
        h.receive(datagram([]));
        expect(h.result.done, false);
        read.completeError(StateError('PRIVATE_READ'));
        clock.flushMicrotasks();
        h.end(69);
        settled(() {
          expect(h.finalRecord['reason'], 'task_failure');
          expect(h.lines.map((e) => e['event']), [
            'datagram',
            'failure',
            'end',
          ]);
        });
      });
    },
  );

  for (final operation in ['ping', 'send', 'listen']) {
    test(
      '$operation external cancellation closes once and waits for actual cleanup',
      () {
        for (final signal in CliStopRequest.values) {
          virtual((clock) {
            final h = Harness(clock, args(operation));
            final close = Completer<void>();
            h.transport.closing = () => close.future;
            h.ready();
            h.stops.add(signal);
            h.stops.add(signal);
            clock.flushMicrotasks();
            expect(h.transport.closes, 1);
            expect(h.result.done, false);
            expect(h.lines.where((e) => e['event'] == 'end'), isEmpty);
            expect(h.err.toString(), isNot(contains('Datagram failure')));
            close.complete();
            clock.flushMicrotasks();
            h.end(signal == CliStopRequest.sigint ? 130 : 143);
            settled(() {
              expect(h.finalRecord['reason'], signal.name);
              if (operation == 'ping') expect(h.facts['reason'], 'canceled');
            });
          });
        }
      },
    );
  }

  test('locked task timeout beats signal or output even before done delivery', () {
    for (final outputFailure in [false, true]) {
      virtual((clock) {
        final sink = ControlledSink();
        final h = Harness(clock, args('ping'), output: sink);
        h.ready();
        h.empty();
        h.ok();
        // Timer runs the core terminal gate; invoke external callback in close,
        // before core schedules logical settlement and publishes done.
        h.transport.closing = () {
          if (outputFailure) {
            sink.completion.completeError(StateError('PRIVATE_OUTPUT'));
          } else {
            h.stops.add(CliStopRequest.sigterm);
          }
          return Future<void>.value();
        };
        clock.elapse(const Duration(seconds: 2));
        settled(() {
          expect(h.result.value, 69);
          expect(h.err.toString(), contains('responseTimeout'));
          expect(h.cancellations, 1);
        });
      });
    }
  });

  test('completed core facts survive signal/output during pending cleanup', () {
    for (final outputFailure in [false, true]) {
      virtual((clock) {
        final sink = ControlledSink();
        final h = Harness(
          clock,
          args('ping'),
          output: outputFailure ? sink : null,
        );
        final close = Completer<void>();
        h.transport.closing = () => close.future;
        h.ready();
        h.empty();
        h.ok();
        h.pong();
        expect(h.result.done, false);
        if (outputFailure) {
          sink.completion.completeError(StateError('PRIVATE_OUTPUT'));
        } else {
          h.stops.add(CliStopRequest.sigint);
        }
        clock.flushMicrotasks();
        close.complete();
        clock.flushMicrotasks();
        settled(() {
          expect(h.result.value, outputFailure ? 74 : 130);
          if (!outputFailure) {
            expect(h.facts['reason'], 'completed');
            expect(h.facts['applicationRttUs'], 0);
          }
        });
      });
    }
  });

  test('finite result and event output failures stop hardware and preserve earlier failures', () {
    for (final operation in ['respond', 'listen']) {
      virtual((clock) {
        final sink = ControlledSink();
        final h = Harness(clock, args(operation), output: sink);
        h.ready();
        sink.completion.completeError(StateError('PRIVATE_OUTPUT'));
        clock.flushMicrotasks();
        settled(() {
          expect(h.result.value, 74);
          expect(h.transport.closes, 1);
          expect(h.cancellations, 1);
          expect(h.err.toString(), isNot(contains('PRIVATE_OUTPUT')));
        });
      });
    }
  });

  test('cleanup failures and CLI signal cancellation errors retain the primary reason', () {
    for (final primary in ['completed', 'signal', 'failure']) {
      virtual((clock) {
        final h = Harness(clock, args('ping'));
        h.cancelError = StateError('PRIVATE_CANCEL');
        h.transport.closing = () =>
            Future<void>.error(StateError('PRIVATE_CLOSE'));
        h.ready();
        h.empty();
        h.ok();
        if (primary == 'completed') {
          h.pong();
        }
        if (primary == 'signal') {
          h.stops.add(CliStopRequest.sigint);
        }
        if (primary == 'failure') {
          clock.elapse(const Duration(seconds: 2));
        }
        clock.flushMicrotasks();
        h.end(primary == 'signal' ? 130 : 69);
        settled(() {
          expect(
            h.finalRecord['reason'],
            primary == 'completed'
                ? 'cleanup_failure'
                : primary == 'signal'
                ? 'sigint'
                : 'task_failure',
          );
          expect(h.finalRecord['cleanup']['state'], 'failed');
          expect(h.finalRecord['cleanup']['failureCount'], 2);
          expect('${h.out}${h.err}', isNot(contains('PRIVATE_')));
        });
      });
    }
  });

  test('listen emits one safe primary failure for cleanup or stderr output failure', () {
    for (final outputFailure in [false, true]) {
      virtual((clock) {
        final sink = ControlledSink();
        final h = Harness(
          clock,
          args('listen'),
          error: outputFailure ? sink : null,
        );
        if (!outputFailure) {
          h.transport.closing = () =>
              Future<void>.error(StateError('PRIVATE_CLOSE'));
        }
        h.ready();
        h.empty();
        if (outputFailure) {
          sink.completion.completeError(StateError('PRIVATE_STDERR'));
          clock.flushMicrotasks();
        } else {
          clock.elapse(const Duration(seconds: 3));
        }
        h.end(outputFailure ? 74 : 69);
        settled(() {
          expect(h.lines.map((e) => e['event']), ['failure', 'end']);
          expect(
            h.finalRecord['reason'],
            outputFailure ? 'output_failure' : 'cleanup_failure',
          );
          expect(
            h.finalRecord['failure']['domain'],
            outputFailure ? 'cli' : 'cleanup',
          );
          expect('${h.out}${h.err}', isNot(contains('PRIVATE_')));
        });
      });
    }
  });

  test('overall raw deadline closes pending work and cannot dispatch later commands', () {
    for (final operation in ['send', 'listen']) {
      virtual((clock) {
        final h = Harness(clock, replace(args(operation), 'task-timeout', '1'));
        final opening = Completer<void>();
        h.transport.opening = () => opening.future;
        clock.flushMicrotasks();
        clock.elapse(second);
        expect(h.transport.closes, 1);
        opening.complete();
        clock.flushMicrotasks();
        h.end(69);
        settled(() {
          expect(h.transport.sent, isEmpty);
          expect(h.finalRecord['failure']['kind'], 'taskTimeout');
        });
      });
    }
  });

  test(
    'route-dependent exact capacity and UTF-8 boundaries reach real sends',
    () {
      for (final operation in ['send', 'ping']) {
        virtual((clock) {
          final count = operation == 'send' ? 108 : 74;
          final name = operation == 'send' ? 'payload-hex' : 'content-hex';
          final h = Harness(clock, [
            ...replace(
              replace(args(operation), name, '00' * count),
              'route-descriptor',
              '0x3f',
            ),
            '--path-hex=${'ab' * 63}',
            '--verbose',
          ]);
          h.ready();
          if (operation == 'ping') h.empty();
          final sent = h.transport.sent.last;
          expect(sent.length, 176);
          expect(sent.sublist(3, 66), List.filled(63, 0xab));
          if (operation == 'ping') {
            expect(
              decodeDiagnosticPayload(Uint8List.sublistView(sent, 68))
                  .message!
                  .content
                  .length,
              74,
            );
          }
          h.ok();
          if (operation == 'ping') clock.elapse(const Duration(seconds: 2));
          h.end(operation == 'send' ? 0 : 69);
          settled(() {
            final text = '${h.out}${h.err}';
            expect(text, isNot(contains('ab' * 63)));
            expect(text, isNot(contains('a5' * 16)));
            expect(text, isNot(contains('synthetic-model')));
            expect(text, isNot(contains('synthetic-node')));
          });
        });
      }
      virtual((clock) {
        final h = Harness(
          clock,
          replace(
            replace(args('ping'), 'content-hex', null),
            'text',
            '${'中' * 43}ab',
          ),
        );
        h.ready();
        h.empty();
        expect(h.sentPing.content.length, 131);
        h.ok();
        h.pong();
        h.end(0);
        settled(() {
          expect('${h.out}${h.err}', isNot(contains('中')));
        });
      });
    },
  );

  test(
    'ready-state command and whole-task budgets retain distinct failures',
    () {
      for (final operation in ['send', 'listen', 'ping']) {
        virtual((clock) {
          final h = Harness(clock, replace(args(operation), 'timeout', '1'));
          h.ready();
          clock.elapse(second);
          h.end(69);
          settled(() {
            expect(
              h.finalRecord['failure']['session']['kind'],
              'requestTimeout',
            );
            expect(
              h.finalRecord['failure']['session']['commandOpcode'],
              operation == 'send' ? 0x3e : 0x0a,
            );
          });
        });
      }
      virtual((clock) {
        final h = Harness(
          clock,
          replace(
            replace(args('ping'), 'task-timeout', '1'),
            'startup-delay',
            '2000',
          ),
        );
        clock.flushMicrotasks();
        clock.elapse(second);
        h.end(69);
        settled(() {
          expect(h.facts['reason'], 'taskTimeout');
          expect(h.transport.sent, isEmpty);
        });
      });
    },
  );

  test('session failure already recorded beats external raw signal before event delivery', () {
    for (final operation in ['send', 'listen']) {
      virtual((clock) {
        final h = Harness(clock, args(operation));
        h.ready();
        h.transport.receiveError(StateError('PRIVATE_NATIVE'));
        h.stops.add(CliStopRequest.sigterm);
        clock.flushMicrotasks();
        h.end(69);
        settled(() {
          expect(h.finalRecord['reason'], 'task_failure');
          expect('${h.out}${h.err}', isNot(contains('PRIVATE_NATIVE')));
        });
      });
    }
  });

  test('failure is visible while cleanup is pending and late input cannot add a second result', () {
    virtual((clock) {
      final h = Harness(clock, args('ping'));
      final close = Completer<void>();
      h.transport.closing = () => close.future;
      h.ready();
      h.empty();
      h.ok();
      clock.elapse(const Duration(seconds: 2));
      expect(h.err.toString(), contains('responseTimeout'));
      expect(h.out.toString(), isEmpty);
      expect(h.result.done, false);
      close.complete();
      clock.flushMicrotasks();
      h.end(69);
      settled(() {
        final previous = h.out.toString();
        h.stops.add(CliStopRequest.sigint);
        h.transport.receive([0]);
        clock.flushMicrotasks();
        expect(h.out.toString(), previous);
        expect(h.lines, hasLength(1));
        expect(h.cancellations, 1);
      });
    });
  });

  test('unexpected factory errors propagate without being classified as task failures', () async {
    final out = StringBuffer(), err = StringBuffer();
    await expectLater(
      runCli(
        args('send'),
        output: out,
        error: err,
        createTransport: (_) => throw StateError('PRIVATE_FACTORY'),
      ),
      throwsStateError,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), isEmpty);
  });
}
