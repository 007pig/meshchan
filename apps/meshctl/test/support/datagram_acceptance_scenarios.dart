import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart';

import 'isolated_cli.dart';

// Development-only support: no test registration, test runner, real signals,
// environment lookup, native constructor fallback, or production encoder.
const datagramAcceptanceIds = [
  'raw_send',
  'bounded_listen',
  'ping_round_trip',
  'responder_reply',
  'partial_pong_timeout',
];
const datagramAcceptanceProbe = 'meshchan.datagram-acceptance.1b8';

final class DatagramAcceptanceResult {
  const DatagramAcceptanceResult(this.id, this.cliExitCode);
  final String id;
  final int cliExitCode;
  Map<String, Object> toJson() => {
    'id': id,
    'passed': true,
    'cliExitCode': cliExitCode,
  };
}

// Independent fixed serial vectors. Host '<', device '>', LE inner length.
// Runtime PING request is 1, unlike the protocol document's example request.
const _query = '3C 02 00 16 03';
const _start = '3C 10 00 01 00 00 00 00 00 00 00 4D 65 73 68 63 68 61 6E';
const _read = '3C 01 00 0A';
const _ok = '3E 01 00 00';
const _empty = '3E 01 00 0A';
const _notice = '3E 01 00 83';
const _raw = '3C 0D 00 3E 03 01 A7 34 12 00 11 13 3C 3E 80 FF';
const _nonce = '00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF';
const _pingTx =
    '3C 2C 00 3E 03 01 A7 FF FF 4D 43 48 50 01 01 $_nonce '
    '01 00 00 00 01 00 00 00 02 00 00 00 00 3C 80 FF';
const _pongRx =
    '3E 2F 00 1B F2 00 00 02 FF FF FF 26 4D 43 48 50 01 02 $_nonce '
    '01 00 00 00 02 00 00 00 01 00 00 00 00 3C 80 FF';
// This independent incoming PING uses request 0x12345678 and a different nonce.
// Its receive slot 2/Flood metadata must not become the local slot 7/Direct B8.
const _pingRx =
    '3E 2F 00 1B F2 00 00 02 FF FF FF 26 4D 43 48 50 01 01 '
    '10 21 32 43 54 65 76 87 98 A9 BA CB DC ED FE 0F '
    '78 56 34 12 02 00 00 00 01 00 00 00 00 3C 80 FF';
const _pongTx =
    '3C 2C 00 3E 07 01 B8 FF FF 4D 43 48 50 01 02 '
    '10 21 32 43 54 65 76 87 98 A9 BA CB DC ED FE 0F '
    '78 56 34 12 01 00 00 00 02 00 00 00 00 3C 80 FF';
const _ordinary =
    '3E 17 00 11 00 00 00 00 00 00 00 00 00 00 '
    '50 52 49 56 41 54 45 5F 43 48 41 54';
const _filtered = '3E 0D 00 1B F2 00 00 09 FF 34 12 04 00 11 80 FF';
const _matching = '3E 0D 00 1B F2 00 00 02 FF 34 12 04 00 11 80 FF';

Uint8List _hex(String value) => Uint8List.fromList([
  for (final byte in value.split(' ')) int.parse(byte, radix: 16),
]);

// Minimal fixed-shape protocol-14 initialization fixtures, with no live data.
Uint8List _device() => Uint8List.fromList([
  0x3e,
  82,
  0,
  0x0d,
  14,
  25,
  8,
  ...List.filled(76, 0),
  1,
  254,
]);
Uint8List _self() =>
    Uint8List.fromList([0x3e, 58, 0, 5, 0, 0, 22, ...List.filled(54, 0)]);

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _equal(Object? actual, Object? expected, String label) {
  // JSON equality is sufficient for these ordered, bounded structural values.
  _check(
    jsonEncode(actual) == jsonEncode(expected),
    '$label: expected ${jsonEncode(expected)}, got ${jsonEncode(actual)}',
  );
}

List<String> _arguments(String id) {
  final operation = switch (id) {
    'raw_send' => 'send',
    'bounded_listen' => 'listen',
    'responder_reply' => 'respond',
    _ => 'ping',
  };
  return [
    'datagram',
    operation,
    '--port=synthetic-1b8',
    '--json',
    '--task-timeout=20',
    if (operation != 'listen') ...[
      '--send-channel=${operation == 'respond' ? 7 : 3}',
      '--route-descriptor=0x01',
      '--path-hex=${operation == 'respond' ? 'B8' : 'A7'}',
    ],
    if (operation != 'send') '--receive-channel=2',
    if (operation == 'send') ...[
      '--data-type=0x1234',
      '--payload-hex=0011133C3E80FF',
    ],
    if (operation == 'listen') ...['--data-type=0x1234', '--max-entries=3'],
    if (operation == 'listen' || operation == 'respond') '--duration=4',
    if (operation == 'ping' || operation == 'respond') ...[
      '--local-id=1',
      '--peer-id=2',
    ],
    if (operation == 'ping') ...[
      '--content-hex=003C80FF',
      '--response-timeout=2',
      '--max-entries=1',
    ],
    if (operation == 'respond') ...['--max-responses=1', '--max-entries=1'],
  ];
}

List<String> _frames(String id) => [
  _query,
  _start,
  ...switch (id) {
    'raw_send' => [_raw],
    'bounded_listen' => [_read, _read, _read],
    'responder_reply' => [_read, _pongTx],
    _ => [_read, _pingTx, _read],
  },
];

/// Runs one fresh finite scenario with checks active in both VM and AOT.
/// One external event turn settles SDK cancellation Futures created outside
/// FakeAsync's zone. There is no polling, retry, real deadline sleep, or exit().
Future<DatagramAcceptanceResult> runDatagramAcceptanceScenario(
  String id,
) async {
  _check(datagramAcceptanceIds.contains(id), 'Unknown scenario: $id');
  final clock = FakeAsync();
  final asynchronousErrors = <Object>[];
  late _Harness h;
  Object? failure;
  StackTrace? failureStack;
  runZonedGuarded(() {
    clock.run((_) {
      h = _Harness(clock, id);
      try {
        h.ready();
        switch (id) {
          case 'raw_send':
            _rawSend(h);
          case 'bounded_listen':
            _boundedListen(h);
          case 'responder_reply':
            _responderReply(h);
          default:
            _ping(h, partial: id == 'partial_pong_timeout');
        }
        h.cleanupPending();
        h.connection.acknowledgeStop();
        clock.flushMicrotasks();
        h.cleanupPending(); // Stop acknowledgement alone is not reader done.
        h.connection.finishReader();
        clock.flushMicrotasks();
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      } finally {
        // Even a failed development check settles all resources before report.
        if (failure != null && !h.result.done) {
          h.stops.add(CliStopRequest.sigint);
          clock.flushMicrotasks();
        }
        h.connection.acknowledgeStop();
        h.connection.finishReader();
        clock.flushMicrotasks();
        h.stopClosed = _Outcome(h.stops.close());
        clock.flushMicrotasks();
      }
    });
  }, (error, stack) => asynchronousErrors.add(error));
  await Future<void>.delayed(Duration.zero);
  clock.flushMicrotasks();
  // Raw cleanup awaits transport, events, then signals in sequence. After the
  // single event turn, one explicit microtask barrier settles the final shared
  // SDK cancellation Future's continuation. No conditional pump or retry.
  await Future<void>.microtask(clock.flushMicrotasks);
  clock.flushMicrotasks();
  try {
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    _check(
      asynchronousErrors.isEmpty,
      'unobserved asynchronous errors: $asynchronousErrors',
    );
    _check(h.result.error == null, 'CLI asynchronous error: ${h.result.error}');
    _check(
      h.result.done,
      'CLI did not settle after cleanup and one event turn; '
      'lifecycle=${h.connection.calls}; output=${h.out}; error=${h.err}; '
      'microtasks=${clock.microtaskCount}; timers=${clock.pendingTimers}',
    );
    _check(h.stopClosed.done, 'controlled stop stream did not close');
    _equal(h.stopClosed.error, null, 'stop stream error');
    _equal(clock.pendingTimers.length, 0, 'remaining timers');
    _equal(clock.microtaskCount, 0, 'remaining microtasks');
    _equal(h.connection.calls, [
      'open',
      'configure:115200',
      'reader',
      'stop',
      'stop.ack',
      'reader.done',
      'stopped',
      'close',
      'dispose',
    ], 'native lifecycle');
    _equal(h.signalSubscriptions, 1, 'controlled stop subscriptions');
    _equal(h.signalCancellations, 1, 'controlled stop cancellations');
    h.verifyFinal();
    return DatagramAcceptanceResult(id, h.result.value!);
  } catch (error, stack) {
    Error.throwWithStackTrace(StateError('$id: $error'), stack);
  }
}

void _rawSend(_Harness h) {
  _equal(h.connection.completedFrames, 2, 'short write has no complete send');
  _equal(h.connection.acceptedInFrame, 4, 'accepted short prefix');
  _equal(h.connection.shortWrites, 1, 'successful short write count');
  _equal(h.out.toString(), '', 'no premature acceptance');
  _check(!h.result.done, 'short write cannot finish CLI');
  h.clock.elapse(Duration.zero); // The transport's genuine short-write retry.
  h.expectFrames(3);
  _equal(h.out.toString(), '', 'full write alone cannot confirm acceptance');
  _check(!h.connection.calls.contains('stop'), 'OK must precede cleanup');
  h.receive(_ok);
}

void _boundedListen(_Harness h) {
  h.expectFrames(3);
  final ordinary = _hex(_ordinary);
  h.connection.receive(ordinary.sublist(0, 5));
  h.clock.flushMicrotasks();
  h.expectFrames(3); // Split prefix is not a consumed queue item.
  // Coalesce the ordinary tail and a notification in one native callback.
  h.connection.receive([...ordinary.sublist(5), ..._hex(_notice)]);
  h.clock.flushMicrotasks();
  h.expectFrames(4);
  h.receive(_filtered);
  h.expectFrames(5);
  _equal(h.lines, [], 'filtered/ordinary bodies must not be published');
  h.receive(_matching);
  h.expectFrames(5); // Last item consumes the quota; no fourth read.
  _equal(h.lines.map((e) => e['event']).toList(), [
    'datagram',
  ], 'last matching event precedes final end');
}

void _ping(_Harness h, {required bool partial}) {
  h.expectFrames(3); // Initial read is dispatched, with PING queued behind it.
  h.receive(_empty);
  h.expectFrames(4);
  h.receive(_ok);
  h.expectFrames(4); // Empty queue does not poll.
  h.clock.elapse(const Duration(microseconds: 1234));
  h.receive(_notice);
  h.expectFrames(5); // Only the notice causes another real 0x0A.
  if (!partial) {
    h.receive(_pongRx);
    return;
  }
  final pong = _hex(_pongRx);
  h.connection.receive(pong.sublist(0, 12));
  h.clock.flushMicrotasks();
  _check(!h.connection.calls.contains('stop'), 'partial body is not a PONG');
  h.clock.elapse(const Duration(microseconds: 1998765));
  _check(!h.connection.calls.contains('stop'), 'response budget not yet due');
  h.clock.elapse(const Duration(microseconds: 1));
  h.cleanupPending();
  final diagnostic = h.err.toString();
  _check(
    diagnostic.contains('"domain":"task"') &&
        diagnostic.contains('"kind":"responseTimeout"'),
    'logical task timeout must commit before cleanup: $diagnostic',
  );
  _equal(
    const LineSplitter().convert(diagnostic).length,
    1,
    'one primary failure diagnostic',
  );
  h.connection.receive(pong.sublist(12));
  h.receive(_notice);
  h.clock.elapse(const Duration(seconds: 6));
  h.expectFrames(5);
  _equal(h.err.toString(), diagnostic, 'late input cannot replace first cause');
  h.cleanupPending();
}

void _responderReply(_Harness h) {
  h.expectFrames(3);
  h.receive(_pingRx);
  h.expectFrames(4); // Exact independent PONG vector includes local slot/path.
  _check(!h.connection.calls.contains('stop'), 'PONG needs local OK');
  h.receive(_ok);
}

final class _Harness {
  _Harness(this.clock, this.id) {
    connection = _Connection(_frames(id), shortWrite: id == 'raw_send');
    stops = StreamController<CliStopRequest>(
      sync: true,
      onListen: () => signalSubscriptions++,
      onCancel: () {
        signalCancellations++;
        return Future<void>.value();
      },
    );
    result = _Outcome(
      runCli(
        _arguments(id),
        output: out,
        error: err,
        createTransport: (path) {
          _equal(path, 'synthetic-1b8', 'CLI transport path');
          return serialTransportForTest(
            portPath: path,
            // Exercise the enabled platform policy without invoking native I/O,
            // including in Linux CI. This does not enable Linux native support.
            operatingSystem: 'macos',
            createConnection: (path) {
              _equal(path, 'synthetic-1b8', 'native connection path');
              return connection;
            },
            createClock: () => _WriteClock(clock),
          );
        },
        stopRequests: stops.stream,
        diagnosticElapsed: () => clock.elapsed,
        diagnosticNonceFactory: () => _hex(_nonce),
      ),
    );
  }
  final FakeAsync clock;
  final String id;
  final out = StringBuffer(), err = StringBuffer();
  late final _Connection connection;
  late final StreamController<CliStopRequest> stops;
  late final _Outcome<int> result;
  late final _Outcome<void> stopClosed;
  int signalSubscriptions = 0, signalCancellations = 0;

  List<Map<String, dynamic>> get lines => const LineSplitter()
      .convert(out.toString())
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();

  void expectFrames(int count) {
    _equal(connection.completedFrames, count, 'complete host frame count');
    _equal(connection.acceptedInFrame, 0, 'no partial command left');
  }

  void ready() {
    clock.flushMicrotasks();
    expectFrames(1);
    _equal(connection.calls, [
      'open',
      'configure:115200',
      'reader',
    ], 'initialization native lifecycle');
    // A new frame clock must start at its own origin, not at scenario start.
    clock.elapse(const Duration(seconds: 3));
    connection.receive(_device());
    clock.flushMicrotasks();
    expectFrames(2);
    connection.receive(_self());
    clock.flushMicrotasks();
  }

  void receive(String bytes) {
    connection.receive(_hex(bytes));
    clock.flushMicrotasks();
  }

  void cleanupPending() {
    _equal(
      connection.calls.where((call) => call == 'stop').length,
      1,
      'one requested reader stop',
    );
    _check(!result.done, 'CLI returned before actual reader stop');
    _check(
      !connection.calls.contains('close') &&
          !connection.calls.contains('dispose'),
      'port released before reader stop',
    );
    _equal(
      lines.map((line) => line['event']).toList(),
      id == 'bounded_listen' ? ['datagram'] : [],
      'no final output before cleanup',
    );
  }

  void verifyFinal() {
    final timeout = id == 'partial_pong_timeout';
    final code = timeout ? 69 : 0;
    _equal(result.value, code, 'CLI exit code');
    _equal(lines.length, id == 'bounded_listen' ? 2 : 1, 'record count');
    for (final line in lines) {
      _equal(line['schemaVersion'], 1, 'CLI schema');
      _equal(line['command'], 'datagram', 'CLI command');
      _equal(line['operation'], _arguments(id)[1], 'CLI operation');
    }
    final end = lines.last;
    _equal(end['exitCode'], code, 'reported exit code');
    _equal(end['reason'], timeout ? 'task_failure' : 'completed', 'CLI reason');
    _equal(end['cleanup'], {
      'state': 'succeeded',
      'failureCount': 0,
      'failures': <Object>[],
    }, 'actual cleanup result');
    if (timeout) {
      _equal(end['failure']['domain'], 'task', 'primary domain');
      _equal(end['failure']['kind'], 'responseTimeout', 'primary kind');
    } else {
      _equal(end['failure'], null, 'unexpected failure');
      _equal(err.toString(), '', 'successful CLI stderr');
    }
    expectFrames(connection.expected.length);
    // The connection checks every accepted byte against fixed complete frames.
    _equal(
      connection.acceptedBytes,
      connection.expected.expand((f) => f).toList(),
      'all accepted TX bytes exactly once',
    );
    final businessRx = switch (id) {
      'raw_send' => [_ok],
      'bounded_listen' => [_ordinary, _notice, _filtered, _matching],
      'responder_reply' => [_pingRx, _ok],
      _ => [_empty, _ok, _notice, _pongRx, if (timeout) _notice],
    };
    _equal(connection.received.expand((chunk) => chunk).toList(), [
      ..._device(),
      ..._self(),
      ...businessRx.expand(_hex),
    ], 'all outer serial RX bytes');
    _equal(connection.received.map((chunk) => chunk.length).toList(), [
      85,
      61,
      ...switch (id) {
        'raw_send' => [4],
        'bounded_listen' => [5, 25, 16, 16],
        'responder_reply' => [50, 4],
        'partial_pong_timeout' => [4, 4, 4, 12, 38, 4],
        _ => [4, 4, 4, 50],
      },
    ], 'split/coalesced reader callbacks');
    final facts = end['result'] as Map<String, dynamic>;
    if (id == 'bounded_listen') {
      _equal(lines.map((line) => line['event']).toList(), [
        'datagram',
        'end',
      ], 'NDJSON event order');
      _equal(lines.first['channelIndex'], 2, 'matching channel');
      _equal(lines.first['dataType'], 0x1234, 'matching type');
      _equal(lines.first['payloadLength'], 4, 'binary payload length');
      _equal(lines.first['snrDb'], -3.5, 'signed SNR');
      _equal(facts, {
        'receptionReason': 'entryLimit',
        'publishedEntries': 3,
        'processedEntries': 3,
        'matchingDatagrams': 1,
        'filteredDatagrams': 1,
        'ordinaryMessages': 1,
      }, 'bounded consumption');
    } else {
      _equal(facts[id == 'responder_reply' ? 'lastSend' : 'send'], {
        'attempted': true,
        'pendingAtTermination': false,
        'dispatched': true,
        'localWriteCompleted': true,
        'localOkObserved': true,
        'deviceAcceptanceConfirmed': true,
      }, 'retained local acceptance facts');
      if (id != 'raw_send') {
        _equal(
          facts['reason'],
          timeout ? 'responseTimeout' : 'completed',
          'core terminal reason',
        );
        _equal(facts['publishedEntries'], timeout ? 0 : 1, 'published count');
        _equal(facts['processedEntries'], timeout ? 0 : 1, 'processed count');
        final reception = facts['reception'] as Map<String, dynamic>;
        _equal(
          reception['dispatchedReads'],
          id == 'responder_reply' ? 1 : 2,
          'real queued reads',
        );
        _equal(
          reception['completedReads'],
          id == 'responder_reply' ? 1 : 2,
          'settled queued reads',
        );
      }
      if (id == 'responder_reply') {
        _equal(facts['listenStopReason'], 'responseLimit', 'finite responder');
        _equal(facts['responseAttempts'], 1, 'response attempts');
        _equal(facts['localResponsesConfirmed'], 1, 'local confirmations');
        for (final counter in [
          'duplicates',
          'conflicts',
          'cacheCapacityRejections',
          'returnCapacityRejections',
        ]) {
          _equal(facts[counter], 0, counter);
        }
      } else if (id != 'raw_send') {
        for (final field in [
          'matchingPongObserved',
          'exactContentValidated',
          'roundTripSucceeded',
        ]) {
          _equal(facts[field], !timeout, field);
        }
        for (final field in [
          'applicationRttUs',
          'firstMatchingPongElapsedUs',
        ]) {
          _equal(facts[field], timeout ? null : 1234, field);
        }
        _equal(facts['matchingPongDuplicates'], 0, 'PONG duplicates');
      }
    }
    final text = '$out$err';
    for (final secret in [
      'PRIVATE_CHAT',
      'payload',
      'content',
      'runNonce',
      'senderTestId',
      'targetTestId',
      'synthetic-1b8',
      '0011133C3E80FF',
    ]) {
      // payloadLength is the explicitly permitted structural length field.
      _check(
        !text.replaceAll('payloadLength', '').contains(secret),
        'private field or body leaked: $secret',
      );
    }
  }
}

final class _Outcome<T> {
  _Outcome(Future<T> future) {
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

final class _WriteClock implements SerialWriteClock {
  _WriteClock(this.clock) : origin = clock.elapsed;
  final FakeAsync clock;
  final Duration origin;
  @override
  Duration get elapsed => clock.elapsed - origin;
  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

/// A fixed byte script, not a firmware emulator. Only accepted prefixes count
/// as TX. Responses are injected explicitly after a full expected command.
final class _Connection implements NativeSerialConnection {
  _Connection(List<String> frames, {required this.shortWrite})
    : expected = frames.map(_hex).toList();
  final List<Uint8List> expected;
  final bool shortWrite;
  final calls = <String>[];
  final acceptedBytes = <int>[];
  final received = <Uint8List>[];
  final _stopAcknowledged = Completer<void>();
  final _readerDone = Completer<void>();
  void Function(Uint8List)? _data;
  void Function()? _done;
  int completedFrames = 0, acceptedInFrame = 0, shortWrites = 0;
  bool _stopped = false;
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
    _data = onData;
    _done = onDone;
  }

  void receive(List<int> bytes) {
    _check(
      _data != null && !_readerDone.isCompleted,
      'RX requires a running synthetic reader',
    );
    final chunk = Uint8List.fromList(bytes);
    received.add(Uint8List.fromList(chunk));
    _data!(chunk);
  }

  @override
  int write(Uint8List bytes) {
    _check(!calls.contains('stop'), 'TX after stop');
    _check(
      completedFrames < expected.length,
      'unexpected additional host frame',
    );
    final frame = expected[completedFrames];
    _equal(bytes, frame.sublist(acceptedInFrame), 'offered frame/retry suffix');
    final count = shortWrite && completedFrames == 2 && shortWrites == 0
        ? 4
        : bytes.length;
    if (count != bytes.length) shortWrites++;
    acceptedBytes.addAll(bytes.take(count));
    acceptedInFrame += count;
    if (acceptedInFrame == frame.length) {
      completedFrames++;
      acceptedInFrame = 0;
    }
    return count;
  }

  @override
  Future<void> stopReader() async {
    calls.add('stop');
    await _stopAcknowledged.future;
    await _readerDone.future;
    _stopped = true;
    calls.add('stopped');
  }

  void acknowledgeStop() {
    if (_stopAcknowledged.isCompleted) return;
    calls.add('stop.ack');
    _stopAcknowledged.complete();
  }

  void finishReader() {
    if (_readerDone.isCompleted) return;
    calls.add('reader.done');
    _done?.call();
    _readerDone.complete();
  }

  @override
  void closePort() {
    _check(_stopped, 'close requires confirmed reader stop');
    calls.add('close');
  }

  @override
  void dispose() {
    _check(_stopped, 'dispose requires confirmed reader stop');
    calls.add('dispose');
  }
}
