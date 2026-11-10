import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart' hide test;
import 'package:test/test.dart' as testing show test;

import 'support/fake_companion_transport.dart';
import 'support/session_test_support.dart';

final _virtualClocks = <FakeAsync>[];
final _cleanupChecks = <void Function()>[];

void test(String description, void Function() body) {
  testing.test(description, () async {
    _virtualClocks.clear();
    _cleanupChecks.clear();
    body();
    // The SDK's shared cancellation Future predates fakeAsync. Cross one event
    // turn without advancing any task budget, then flush its owning fake zone.
    await Future<void>.delayed(Duration.zero);
    for (final clock in _virtualClocks) {
      clock.flushMicrotasks();
    }
    for (final check in _cleanupChecks) {
      check();
    }
  });
}

void cleanupIs(
  Outcome<DiagnosticCleanupResult> outcome,
  DiagnosticCleanupState state, {
  int? failures,
}) {
  _cleanupChecks.add(() {
    expect(outcome.value!.state, state);
    if (failures != null) expect(outcome.value!.failures, hasLength(failures));
  });
}

// Match the VM's Duration.inMilliseconds conversion while retaining the same
// fake elapsed domain. FakeAsync itself otherwise preserves microseconds.
void withMillisecondTimers(void Function(FakeAsync) body) {
  fakeAsync((clock) {
    runZoned(
      () => body(clock),
      zoneSpecification: ZoneSpecification(
        createTimer: (_, parent, zone, duration, callback) =>
            parent.createTimer(
              zone,
              Duration(milliseconds: duration.inMilliseconds),
              callback,
            ),
      ),
    );
  });
}

const second = Duration(seconds: 1);
DiagnosticTaskOptions options({
  Duration timeout = const Duration(seconds: 30),
  int entries = 128,
  int sendChannel = 3,
  int receiveChannel = 2,
  int local = 1,
  int peer = 2,
  int descriptor = 0xff,
  Uint8List? path,
  int batch = 8,
}) => DiagnosticTaskOptions(
  sendChannelIndex: sendChannel,
  receiveChannelIndex: receiveChannel,
  localTestId: local,
  peerTestId: peer,
  routeDescriptor: descriptor,
  path: path ?? Uint8List(0),
  taskTimeout: timeout,
  maxEntries: entries,
  maxReadsPerBatch: batch,
);

MeshchanDiagnosticMessage message({
  DiagnosticKind kind = DiagnosticKind.pong,
  int id = 1,
  int sender = 2,
  int target = 1,
  Uint8List? nonce,
  Uint8List? content,
}) => MeshchanDiagnosticMessage(
  kind: kind,
  runNonce: nonce ?? Uint8List(16),
  requestId: id,
  senderTestId: sender,
  targetTestId: target,
  content: content ?? Uint8List.fromList([0, 128, 255]),
);

List<int> frame(MeshchanDiagnosticMessage msg, {int channel = 2}) {
  final payload = encodeDiagnosticPayload(msg);
  return [0x1b, 0, 0, 0, channel, 0xff, 0xff, 0xff, payload.length, ...payload];
}

final class Harness {
  Harness(
    this.clock, {
    int slots = 8,
    Duration commandTimeout = const Duration(seconds: 5),
  }) {
    _virtualClocks.add(clock);
    session = MeshCoreSession(
      transport: transport,
      maxQueuedCommands: slots,
      requestTimeout: commandTimeout,
    );
  }
  final FakeAsync clock;
  final transport = FakeCompanionTransport();
  late final MeshCoreSession session;
  MeshchanPingTask ping({
    DiagnosticTaskOptions? config,
    Duration response = second,
    Uint8List Function()? nonce,
    Uint8List? content,
  }) => MeshchanPingTask(
    session: session,
    options: config ?? options(),
    responseTimeout: response,
    content: content ?? Uint8List.fromList([0, 128, 255]),
    elapsed: () => clock.elapsed,
    nonceFactory: nonce ?? () => Uint8List(16),
  );
  MeshchanResponderTask responder({
    DiagnosticTaskOptions? config,
    Duration listen = const Duration(seconds: 10),
    int responses = 1,
  }) => MeshchanResponderTask(
    session: session,
    options: config ?? options(),
    listenDuration: listen,
    maxResponses: responses,
    elapsed: () => clock.elapsed,
  );
  void ready() {
    clock.flushMicrotasks();
    transport.receive(deviceInfo());
    clock.flushMicrotasks();
    transport.receive(selfInfo());
    clock.flushMicrotasks();
    expect(session.state, MeshCoreSessionState.ready);
    expect(transport.sent[2], [0x0a]);
  }

  void empty() {
    transport.receive([0x0a]);
    clock.flushMicrotasks();
  }

  void ok() {
    transport.receive([0]);
    clock.flushMicrotasks();
  }
}

void main() {
  test(
    'construction/getters are inert; cancel before start and repeated start',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        var nonces = 0;
        final task = h.ping(
          nonce: () {
            nonces++;
            return Uint8List(16);
          },
        );
        final done = Outcome(task.done);
        final cleanup = Outcome(task.cleanupDone);
        expect(h.transport.calls, isEmpty);
        expect(clock.pendingTimers, isEmpty);
        expect(task.cleanupState, DiagnosticCleanupState.notStarted);
        expect(task.cancel(), same(task.done));
        expect(task.cancel(), same(task.done));
        final started = Outcome(task.start());
        clock.flushMicrotasks();
        expect(started.error, isA<DiagnosticTaskStartError>());
        expect(done.value!.reason, DiagnosticTaskReason.canceled);
        expect(cleanup.value!.state, DiagnosticCleanupState.notRequired);
        expect(nonces, 0);
        expect(h.session.state, MeshCoreSessionState.idle);
        expect(h.transport.calls, isEmpty);
      });
    },
  );

  test('first invalid start rejects consistently without ownership or I/O', () {
    final invalid = [
      options(sendChannel: -1),
      options(receiveChannel: 256),
      options(local: 0),
      options(peer: 1),
      options(peer: 0x100000000),
      options(timeout: Duration.zero),
      options(entries: 0),
      options(batch: 0),
      options(descriptor: 0xff, path: Uint8List(1)),
    ];
    for (final config in invalid) {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.ping(config: config);
        final done = Outcome(task.done);
        final cleanup = Outcome(task.cleanupDone);
        final start = Outcome(task.start());
        clock.flushMicrotasks();
        expect(start.error, isA<DiagnosticTaskStartError>());
        expect(done.value!.failure!.cause, same(start.error));
        expect(done.value!.reason, DiagnosticTaskReason.startRejected);
        expect(cleanup.value!.state, DiagnosticCleanupState.notRequired);
        expect(h.transport.calls, isEmpty);
        expect(h.session.state, MeshCoreSessionState.idle);
      });
    }
    for (final invalidKind in [
      'slots',
      'ready',
      'content',
      'response',
      'listen',
      'responses',
    ]) {
      fakeAsync((clock) {
        final h = Harness(clock, slots: invalidKind == 'slots' ? 0 : 8);
        if (invalidKind == 'ready') {
          Outcome(h.session.connect());
          clock.flushMicrotasks();
          h.transport.receive(deviceInfo());
          clock.flushMicrotasks();
          h.transport.receive(selfInfo());
          clock.flushMicrotasks();
        }
        final calls = List.of(h.transport.calls);
        final dynamic task = switch (invalidKind) {
          'content' => h.ping(content: Uint8List(132)),
          'response' => h.ping(response: Duration.zero),
          'listen' => h.responder(listen: Duration.zero),
          'responses' => h.responder(responses: 0),
          _ => h.ping(),
        };
        final start = Outcome<void>(task.start() as Future<void>);
        clock.flushMicrotasks();
        expect(start.error, isA<DiagnosticTaskStartError>());
        expect(h.transport.calls, calls);
        Outcome(h.session.close());
        clock.flushMicrotasks();
      });
    }
  });

  test(
    'claim is synchronous, nonce called once, and invalid nonce never opens',
    () {
      for (final fails in [false, true]) {
        fakeAsync((clock) {
          final h = Harness(clock);
          var calls = 0;
          final original = StateError('private nonce source');
          late Outcome<void> competing;
          final other = h.responder();
          final task = h.ping(
            nonce: () {
              calls++;
              competing = Outcome(other.start()); // Reentrant claim attempt.
              if (fails) throw original;
              return Uint8List(16);
            },
          );
          final done = Outcome(task.done);
          final cleanup = Outcome(task.cleanupDone);
          final started = Outcome(task.start());
          final duplicate = Outcome(task.start());
          clock.flushMicrotasks();
          expect(started.error, isNull);
          expect(competing.error, isA<DiagnosticTaskStartError>());
          expect(duplicate.error, isA<DiagnosticTaskStartError>());
          expect(calls, 1);
          if (fails) {
            expect(
              done.value!.reason,
              DiagnosticTaskReason.nonceGenerationFailed,
            );
            expect(done.value!.failure!.cause, same(original));
            expect(done.value!.failure!.stackTrace, isA<StackTrace>());
            expect(h.transport.openCount, 0);
            expect(h.transport.sent, isEmpty);
            cleanupIs(cleanup, DiagnosticCleanupState.succeeded);
          } else {
            Outcome(task.cancel());
            clock.flushMicrotasks();
          }
          expect(h.transport.closeCount, 1);
          expect(clock.pendingTimers, isEmpty);
        });
      }
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.ping(nonce: () => Uint8List(15));
        final done = Outcome(task.done);
        Outcome(task.start());
        clock.flushMicrotasks();
        expect(done.value!.reason, DiagnosticTaskReason.nonceGenerationFailed);
        expect(h.transport.openCount, 0);
      });
    },
  );

  test(
    'normal round trip copies configuration and preserves first elapsed',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final content = Uint8List.fromList([0, 128, 255]);
        final path = Uint8List.fromList([7]);
        final nonce = Uint8List(16);
        final config = options(descriptor: 1, path: path);
        final task = h.ping(
          config: config,
          content: content,
          nonce: () => nonce,
        );
        content.fillRange(0, content.length, 9);
        path[0] = 8;
        final done = Outcome(task.done);
        final cleanup = Outcome(task.cleanupDone);
        Outcome(task.start());
        nonce[0] = 8;
        h.ready();
        h.empty();
        expect(
          h.transport.sent.last,
          encodeSendChannelData(
            channelIndex: 3,
            dataType: diagnosticDataType,
            routeDescriptor: 1,
            path: Uint8List.fromList([7]),
            payload: encodeDiagnosticPayload(
              message(kind: DiagnosticKind.ping, sender: 1, target: 2),
            ),
          ),
        );
        h.ok();
        clock.elapse(const Duration(milliseconds: 200));
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        expect(done.value!.roundTripSucceeded, isTrue);
        expect(done.value!.applicationRtt, const Duration(milliseconds: 200));
        expect(done.value!.send.deviceAcceptanceConfirmed, isTrue);
        expect(done.value!.send.dispatched, isTrue);
        expect(done.value!.exactContentValidated, isTrue);
        cleanupIs(cleanup, DiagnosticCleanupState.succeeded);
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        expect(done.completionCount, 1);
        expect(h.transport.listenCount, 1);
        expect(h.transport.closeCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  for (final ending in ['success', 'writeFailure', 'deviceError']) {
    test('early PONG retained through late local settlement: $ending', () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final write = Completer<void>();
        h.transport.sending = (bytes, _) =>
            bytes[0] == 0x3e ? write.future : Future.value();
        final task = h.ping();
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.empty();
        clock.elapse(const Duration(milliseconds: 100));
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        h.transport.receive([0]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 1100));
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        expect(done.done, isFalse); // Retired remote deadline must not fire.
        if (ending == 'deviceError') h.transport.receive([1, 4]);
        if (ending == 'writeFailure') {
          write.completeError(StateError('private write'), StackTrace.current);
        } else {
          write.complete();
        }
        clock.flushMicrotasks();
        final result = done.value!;
        expect(result.matchingPongObserved, isTrue);
        expect(
          result.firstMatchingPongElapsed,
          const Duration(milliseconds: 100),
        );
        expect(result.matchingPongDuplicates, 1);
        expect(result.roundTripSucceeded, ending == 'success');
        expect(result.send.localOkObserved, isTrue);
        expect(result.send.localWriteCompleted, ending == 'success');
        expect(result.send.deviceAcceptanceConfirmed, ending == 'success');
        expect(
          result.applicationRtt,
          ending == 'success' ? const Duration(milliseconds: 100) : null,
        );
        expect(clock.pendingTimers, isEmpty);
      });
    });
  }

  test('entry limit waits for delivered last PONG and pending send', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final write = Completer<void>();
      h.transport.sending = (bytes, _) =>
          bytes[0] == 0x3e ? write.future : Future.value();
      final task = h.ping(config: options(entries: 1));
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      h.empty();
      h.transport.receive(frame(message()));
      clock.flushMicrotasks();
      expect(done.done, isFalse);
      h.transport.receive([0]);
      write.complete();
      clock.flushMicrotasks();
      expect(done.value!.roundTripSucceeded, isTrue);
      expect(done.value!.publishedEntries, 1);
      expect(done.value!.processedEntries, 1);
      expect(
        done.value!.reception!.reason,
        MeshCoreReceptionStopReason.entryLimit,
      );
    });
  });

  test('unmatched final entry is exhaustion, not remote timeout', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final task = h.ping(config: options(entries: 1));
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      h.transport.receive(frame(message(sender: 3)));
      clock.flushMicrotasks();
      expect(done.value!.reason, DiagnosticTaskReason.entryLimit);
      expect(done.value!.send.commandFailure!.dispatched, isTrue);
      expect(done.value!.send.pendingAtTermination, isTrue);
    });
  });

  test(
    'wrong peer/nonce/content/channel and chat cannot renew remote budget',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.ping();
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.empty();
        h.ok();
        clock.elapse(const Duration(milliseconds: 500));
        h.transport.receive(frame(message(sender: 3)));
        h.transport.receive(
          frame(message(nonce: Uint8List.fromList(List.filled(16, 1)))),
        );
        h.transport.receive(frame(message(content: Uint8List(0))));
        h.transport.receive(frame(message(), channel: 3));
        h.transport.receive([0x07, ...List.filled(12, 0)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 500));
        expect(done.value!.reason, DiagnosticTaskReason.responseTimeout);
        expect(done.value!.matchingPongObserved, isFalse);
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        expect(done.completionCount, 1);
      });
    },
  );

  for (final phase in ['connecting', 'queued', 'waiting', 'earlyPong']) {
    test('overall timeout and pending native cleanup: $phase', () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final close = Completer<void>();
        h.transport.closing = () => close.future;
        final task = h.ping(
          config: options(timeout: second),
          response: const Duration(seconds: 2),
        );
        final done = Outcome(task.done);
        final cleanup = Outcome(task.cleanupDone);
        Outcome(task.start());
        if (phase != 'connecting') h.ready();
        if (phase == 'waiting' || phase == 'earlyPong') {
          h.empty();
          h.ok();
        }
        if (phase == 'earlyPong') {
          h.transport.receive(frame(message()));
          // State failure before async PONG delivery must defeat apparent success.
          h.transport.receiveError(StateError('private failure'));
        }
        clock.elapse(second);
        expect(done.done, isTrue);
        expect(
          done.value!.reason,
          phase == 'earlyPong'
              ? DiagnosticTaskReason.sessionFailed
              : DiagnosticTaskReason.taskTimeout,
        );
        expect(done.value!.roundTripSucceeded, isFalse);
        expect(cleanup.done, isFalse);
        expect(task.cleanupState, DiagnosticCleanupState.pending);
        close.complete();
        clock.flushMicrotasks();
        cleanupIs(cleanup, DiagnosticCleanupState.succeeded);
      });
    });
  }

  test(
    'earlier remote deadline wins delayed callbacks; equal overall wins',
    () {
      for (final timeout in [second, const Duration(seconds: 2)]) {
        fakeAsync((clock) {
          final h = Harness(clock);
          final task = h.ping(config: options(timeout: timeout));
          final done = Outcome(task.done);
          Outcome(task.start());
          h.ready();
          h.empty();
          h.ok();
          clock.elapseBlocking(const Duration(seconds: 3));
          h.transport.receive(frame(message()));
          clock.flushMicrotasks();
          expect(
            done.value!.reason,
            timeout == second
                ? DiagnosticTaskReason.taskTimeout
                : DiagnosticTaskReason.responseTimeout,
          );
          expect(done.value!.matchingPongObserved, isFalse);
        });
      }
    },
  );

  test('queued send retains its own facts and the failing read root', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final task = h.ping();
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      h.transport.receive([1, 5]);
      clock.flushMicrotasks();
      final result = done.value!;
      expect(result.send.commandFailure!.commandOpcode, 0x3e);
      expect(result.send.dispatched, isFalse);
      expect(result.send.commandFailure!.sessionFailure.commandOpcode, 0x0a);
      expect(
        result.sessionFailure!.kind,
        MeshCoreSessionFailureKind.deviceRejected,
      );
      expect(result.roundTripSucceeded, isFalse);
    });
  });

  test('primary failure, all cleanup errors, and private cause remain separate', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final cause = StateError('PRIVATE PAYLOAD NONCE PORT');
      h.transport.closing = () => Future.error(cause);
      h.transport.canceling = () => Future.error(cause);
      final task = h.ping();
      final done = Outcome(task.done);
      final cleanup = Outcome(task.cleanupDone);
      Outcome(task.start());
      h.ready();
      h.empty();
      h.ok();
      h.transport.receiveError(cause, StackTrace.current);
      clock.flushMicrotasks();
      expect(done.value!.failure!.cause, isA<MeshCoreSessionFailure>());
      expect(done.value!.sessionFailure!.cause, same(cause));
      cleanupIs(cleanup, DiagnosticCleanupState.failed, failures: 2);
      expect(
        '${done.value} ${done.value!.failure} ${done.value!.send} ${cleanup.value}',
        isNot(contains('PRIVATE')),
      );
    });
  });

  for (final phase in ['connecting', 'waiting', 'responding']) {
    test('cancel closes once, logical result precedes cleanup: $phase', () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final closing = Completer<void>();
        h.transport.closing = () => closing.future;
        final dynamic task = phase == 'responding' ? h.responder() : h.ping();
        final done = Outcome<DiagnosticTaskResult>(
          task.done as Future<DiagnosticTaskResult>,
        );
        final cleanup = Outcome<DiagnosticCleanupResult>(
          task.cleanupDone as Future<DiagnosticCleanupResult>,
        );
        Outcome<void>(task.start() as Future<void>);
        if (phase != 'connecting') h.ready();
        if (phase == 'waiting') {
          h.empty();
          h.ok();
        }
        if (phase == 'responding') {
          h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
          clock.flushMicrotasks();
        }
        task.cancel();
        task.cancel();
        clock.flushMicrotasks();
        expect(done.value!.reason, DiagnosticTaskReason.canceled);
        expect(cleanup.done, isFalse);
        expect(h.transport.closeCount, 1);
        h.transport.receive([0]);
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        expect(done.completionCount, 1);
        closing.complete();
        clock.flushMicrotasks();
        cleanupIs(cleanup, DiagnosticCleanupState.succeeded);
        expect(clock.pendingTimers, isEmpty);
      });
    });
  }

  test(
    'responder sends exact targeted PONG with one attempt and waits for OK',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.responder();
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.transport.receive(frame(message())); // Not a PING.
        h.transport.receive(
          frame(message(kind: DiagnosticKind.ping, sender: 3)),
        );
        h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
        clock.flushMicrotasks();
        expect(h.transport.sent.where((v) => v[0] == 0x3e), hasLength(1));
        expect(
          h.transport.sent.last,
          encodeSendChannelData(
            channelIndex: 3,
            dataType: diagnosticDataType,
            routeDescriptor: 0xff,
            path: Uint8List(0),
            payload: encodeDiagnosticPayload(
              message(kind: DiagnosticKind.pong, sender: 1, target: 2),
            ),
          ),
        );
        expect(done.done, isFalse);
        h.ok();
        expect(done.value!.reason, DiagnosticTaskReason.completed);
        expect(
          done.value!.listenStopReason,
          DiagnosticListenStopReason.responseLimit,
        );
        expect(done.value!.responseAttempts, 1);
        expect(done.value!.localResponsesConfirmed, 1);
      });
    },
  );

  test(
    'responder rejects return capacity, duplicates by value, and conflicts',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.responder(
          config: options(descriptor: 0x3f, path: Uint8List(63)),
          responses: 5,
        );
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.transport.receive(
          frame(message(kind: DiagnosticKind.ping, content: Uint8List(100))),
        );
        h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
        clock.flushMicrotasks();
        h.ok();
        h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
        h.transport.receive(
          frame(message(kind: DiagnosticKind.ping, content: Uint8List(0))),
        );
        clock.flushMicrotasks();
        expect(h.transport.sent.where((v) => v[0] == 0x3e), hasLength(1));
        clock.elapse(Duration.zero); // Send yield delivers buffered entries.
        h.empty();
        clock.elapse(const Duration(seconds: 10));
        expect(done.value!.reason, DiagnosticTaskReason.completed);
        expect(done.value!.returnCapacityRejections, 1);
        expect(done.value!.duplicates, 1);
        expect(done.value!.conflicts, 1);
        expect(done.value!.responseAttempts, 1);
      });
    },
  );

  test(
    'entry-limit buffering is finite; last PING drains after send event turn',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.responder(config: options(entries: 3), responses: 2);
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.transport.receive(frame(message(kind: DiagnosticKind.ping, id: 1)));
        clock.flushMicrotasks();
        h.transport.receive(frame(message(kind: DiagnosticKind.ping, id: 1)));
        h.transport.receive(frame(message(kind: DiagnosticKind.ping, id: 2)));
        h.transport.receive(frame(message(kind: DiagnosticKind.ping, id: 3)));
        clock.flushMicrotasks();
        h.ok();
        expect(done.done, isFalse);
        expect(h.transport.sent.where((v) => v[0] == 0x3e), hasLength(1));
        clock.elapse(Duration.zero);
        expect(h.transport.sent.where((v) => v[0] == 0x3e), hasLength(2));
        h.ok();
        expect(done.value!.reason, DiagnosticTaskReason.completed);
        expect(done.value!.publishedEntries, 3);
        expect(done.value!.processedEntries, 3);
        expect(done.value!.duplicates, 1);
        expect(done.value!.responseAttempts, 2);
      });
    },
  );

  for (final ending in [
    'success',
    'readFailure',
    'sendFailure',
    'timeout',
    'cancel',
  ]) {
    test(
      'listen duration settles accepted FIFO send but rejects buffer: $ending',
      () {
        fakeAsync((clock) {
          final h = Harness(clock);
          final readWrite = Completer<void>();
          h.transport.sending = (bytes, _) =>
              bytes[0] == 0x0a ? readWrite.future : Future.value();
          final task = h.responder(
            listen: second,
            responses: 4,
            config: options(timeout: const Duration(seconds: 3)),
          );
          final done = Outcome(task.done);
          Outcome(task.start());
          h.ready();
          h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
          clock.flushMicrotasks();
          h.transport.receive(frame(message(kind: DiagnosticKind.ping, id: 2)));
          clock.elapse(second);
          expect(done.done, isFalse);
          expect(h.transport.sent.where((v) => v[0] == 0x3e), isEmpty);
          if (ending == 'readFailure') {
            readWrite.completeError(StateError('private read'));
          } else {
            readWrite.complete();
          }
          clock.flushMicrotasks();
          if (ending == 'success') h.ok();
          if (ending == 'sendFailure') {
            h.transport.receive([1, 4]);
            clock.flushMicrotasks();
          }
          if (ending == 'timeout') clock.elapse(const Duration(seconds: 2));
          if (ending == 'cancel') {
            Outcome(task.cancel());
            clock.flushMicrotasks();
          }
          expect(done.done, isTrue);
          expect(
            done.value!.listenStopReason,
            DiagnosticListenStopReason.durationElapsed,
          );
          expect(done.value!.responseAttempts, 1);
          expect(
            done.value!.reason == DiagnosticTaskReason.completed,
            ending == 'success',
          );
          expect(
            done.value!.localResponsesConfirmed,
            ending == 'success' ? 1 : 0,
          );
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }

  test('entries done cannot bypass unsettled reception read write', () {
    for (final fail in [false, true]) {
      fakeAsync((clock) {
        final h = Harness(clock);
        final readWrite = Completer<void>();
        h.transport.sending = (bytes, _) =>
            bytes[0] == 0x0a ? readWrite.future : Future.value();
        final task = h.responder(config: options(entries: 1));
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.transport.receive(frame(message()));
        clock.flushMicrotasks();
        expect(done.done, isFalse);
        if (fail) {
          readWrite.completeError(StateError('private read'));
        } else {
          readWrite.complete();
        }
        clock.flushMicrotasks();
        expect(done.value!.reason == DiagnosticTaskReason.completed, !fail);
        expect(
          done.value!.listenStopReason,
          DiagnosticListenStopReason.entryLimit,
        );
        expect(done.value!.responseAttempts, 0);
      });
    }
  });

  test(
    'unrelated buffered entries yield after eight; cancellation stops resume',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.responder(config: options(entries: 20));
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        for (var i = 0; i < 20; i++) {
          h.transport.receive(frame(message()));
        }
        clock.flushMicrotasks();
        expect(done.done, isFalse);
        expect(
          clock.pendingTimers.any((t) => t.duration == Duration.zero),
          isTrue,
        );
        Outcome(task.cancel());
        clock.flushMicrotasks();
        clock.elapse(Duration.zero);
        expect(done.value!.processedEntries, 8);
        expect(done.value!.publishedEntries, 20);
        expect(h.transport.sent.where((v) => v[0] == 0x3e), isEmpty);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test('remote timeout closes a still queued send without another read', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final task = h.ping();
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      clock.elapse(second);
      expect(done.value!.reason, DiagnosticTaskReason.responseTimeout);
      expect(done.value!.send.pendingAtTermination, isTrue);
      expect(done.value!.send.dispatched, isFalse);
      expect(done.value!.send.localWriteCompleted, isFalse);
      expect(done.value!.send.localOkObserved, isFalse);
      expect(h.transport.sent.map((v) => v[0]), [0x16, 1, 0x0a]);
    });
  });

  test('early PONG retires remote timer but not the overall send budget', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final write = Completer<void>();
      h.transport.sending = (bytes, _) =>
          bytes[0] == 0x3e ? write.future : Future.value();
      final task = h.ping(config: options(timeout: const Duration(seconds: 2)));
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      h.empty();
      clock.elapse(const Duration(milliseconds: 100));
      h.transport.receive(frame(message()));
      h.transport.receive([0]);
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 1900));
      expect(done.value!.reason, DiagnosticTaskReason.taskTimeout);
      expect(done.value!.matchingPongObserved, isTrue);
      expect(done.value!.applicationRtt, isNull);
      expect(done.value!.send.pendingAtTermination, isTrue);
      expect(done.value!.send.localOkObserved, isTrue);
      expect(done.value!.send.deviceAcceptanceConfirmed, isFalse);
      write.complete();
      clock.flushMicrotasks();
      expect(done.completionCount, 1);
    });
  });

  test('entry limit cannot bypass response attempt cap in buffered PINGs', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final task = h.responder(config: options(entries: 4), responses: 2);
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
      clock.flushMicrotasks();
      for (var i = 2; i <= 4; i++) {
        h.transport.receive(frame(message(kind: DiagnosticKind.ping, id: i)));
      }
      clock.flushMicrotasks();
      h.ok();
      clock.elapse(Duration.zero);
      h.ok();
      expect(done.value!.reason, DiagnosticTaskReason.completed);
      expect(done.value!.responseAttempts, 2);
      expect(done.value!.processedEntries, 2);
      expect(done.value!.publishedEntries, 4);
      expect(h.transport.sent.where((v) => v[0] == 0x3e), hasLength(2));
      clock.elapse(Duration.zero);
      expect(done.completionCount, 1);
    });
  });

  test(
    'listen boundary rejects buffered input before delayed Timer callback',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.responder(listen: second);
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.empty();
        clock.elapseBlocking(second);
        h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
        clock.flushMicrotasks();
        expect(done.value!.reason, DiagnosticTaskReason.completed);
        expect(
          done.value!.listenStopReason,
          DiagnosticListenStopReason.durationElapsed,
        );
        expect(done.value!.responseAttempts, 0);
        expect(done.value!.publishedEntries, 1);
        expect(done.value!.processedEntries, 0);
      });
    },
  );

  test('local success count survives failure before its continuation runs', () {
    fakeAsync((clock) {
      final h = Harness(clock);
      final task = h.responder();
      final done = Outcome(task.done);
      Outcome(task.start());
      h.ready();
      h.transport.receive(frame(message(kind: DiagnosticKind.ping)));
      clock.flushMicrotasks();
      h.transport.receive([0]);
      h.transport.receiveError(StateError('private failure'));
      clock.flushMicrotasks();
      expect(done.value!.reason, DiagnosticTaskReason.sessionFailed);
      expect(done.value!.localResponsesConfirmed, 1);
      expect(done.value!.send.deviceAcceptanceConfirmed, isTrue);
      expect(
        done.value!.listenStopReason,
        DiagnosticListenStopReason.responseLimit,
      );
    });
  });

  test(
    'overall budget starts before nonce generation and prevents late open',
    () {
      fakeAsync((clock) {
        final h = Harness(clock);
        final task = h.ping(
          config: options(timeout: second),
          nonce: () {
            clock.elapseBlocking(second);
            return Uint8List(16);
          },
        );
        final done = Outcome(task.done);
        Outcome(task.start());
        clock.flushMicrotasks();
        expect(done.value!.reason, DiagnosticTaskReason.taskTimeout);
        expect(done.value!.send.attempted, isFalse);
        expect(done.value!.send.dispatched, isNull);
        expect(h.transport.openCount, 0);
        expect(h.transport.closeCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test('fractional task deadlines survive millisecond timer truncation', () {
    for (final budget in [
      const Duration(microseconds: 999),
      const Duration(microseconds: 1999),
    ]) {
      for (final responder in [false, true]) {
        withMillisecondTimers((clock) {
          final h = Harness(clock);
          final opening = Completer<void>();
          final closing = Completer<void>();
          h.transport.opening = () => opening.future;
          h.transport.closing = () => closing.future;
          final config = options(timeout: budget);
          final dynamic task = responder
              ? h.responder(config: config)
              : h.ping(config: config);
          final done = Outcome<DiagnosticTaskResult>(
            task.done as Future<DiagnosticTaskResult>,
          );
          final cleanup = Outcome<DiagnosticCleanupResult>(
            task.cleanupDone as Future<DiagnosticCleanupResult>,
          );
          Outcome<void>(task.start() as Future<void>);
          clock.elapse(Duration.zero);
          expect(done.done, isFalse);
          clock.elapse(budget - const Duration(microseconds: 1));
          expect(done.done, isFalse);
          clock.elapse(const Duration(microseconds: 2));
          expect(done.done, isTrue);
          expect(done.value!.reason, DiagnosticTaskReason.taskTimeout);
          expect(done.value!.send.attempted, isFalse);
          expect(h.transport.closeCount, 1);
          expect(cleanup.done, isFalse);
          opening.complete();
          closing.complete();
          clock.flushMicrotasks();
          expect(h.transport.sent, isEmpty);
          cleanupIs(cleanup, DiagnosticCleanupState.succeeded);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    }
  });

  test(
    'fractional response deadlines survive millisecond timer truncation',
    () {
      for (final budget in [
        const Duration(microseconds: 999),
        const Duration(microseconds: 1999),
      ]) {
        withMillisecondTimers((clock) {
          final h = Harness(clock);
          final task = h.ping(
            config: options(timeout: const Duration(milliseconds: 50)),
            response: budget,
          );
          final done = Outcome(task.done);
          Outcome(task.start());
          h.ready();
          h.empty();
          h.ok();
          clock.elapse(Duration.zero);
          expect(done.done, isFalse);
          clock.elapse(budget - const Duration(microseconds: 1));
          expect(done.done, isFalse);
          clock.elapse(const Duration(microseconds: 2));
          expect(done.done, isTrue);
          expect(done.value!.reason, DiagnosticTaskReason.responseTimeout);
          expect(done.value!.send.deviceAcceptanceConfirmed, isTrue);
          expect(done.value!.matchingPongObserved, isFalse);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test(
    'rounded response wakeup preserves the exact PONG acceptance boundary',
    () {
      for (final arrival in [998, 999]) {
        withMillisecondTimers((clock) {
          final h = Harness(clock);
          final write = Completer<void>();
          h.transport.sending = (bytes, _) =>
              bytes[0] == 0x3e ? write.future : Future.value();
          final task = h.ping(
            config: options(timeout: const Duration(milliseconds: 50)),
            response: const Duration(microseconds: 999),
          );
          final done = Outcome(task.done);
          Outcome(task.start());
          h.ready();
          h.empty();
          h.transport.receive([0]);
          clock.flushMicrotasks();
          clock.elapse(Duration(microseconds: arrival));
          h.transport.receive(frame(message()));
          clock.flushMicrotasks();
          if (arrival == 998) {
            clock.elapse(const Duration(milliseconds: 3));
            expect(done.done, isFalse);
          }
          write.complete();
          clock.flushMicrotasks();
          expect(
            done.value!.reason,
            arrival == 998
                ? DiagnosticTaskReason.completed
                : DiagnosticTaskReason.responseTimeout,
          );
          expect(
            done.value!.applicationRtt,
            arrival == 998 ? const Duration(microseconds: 998) : null,
          );
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test('fractional listen windows do not stop at a truncated timer delay', () {
    for (final budget in [
      const Duration(microseconds: 999),
      const Duration(microseconds: 1999),
    ]) {
      withMillisecondTimers((clock) {
        final h = Harness(clock);
        final task = h.responder(
          config: options(timeout: const Duration(milliseconds: 50)),
          listen: budget,
        );
        final done = Outcome(task.done);
        Outcome(task.start());
        h.ready();
        h.empty();
        clock.elapse(Duration.zero);
        expect(done.done, isFalse);
        clock.elapse(budget - const Duration(microseconds: 1));
        expect(done.done, isFalse);
        clock.elapse(const Duration(microseconds: 2));
        expect(done.done, isTrue);
        expect(done.value!.reason, DiagnosticTaskReason.completed);
        expect(
          done.value!.listenStopReason,
          DiagnosticListenStopReason.durationElapsed,
        );
        expect(done.value!.responseAttempts, 0);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });
}
