import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import 'support/fake_companion_transport.dart';
import 'support/session_test_support.dart';

const second = Duration(seconds: 1);

void main() {
  test('commands reject every non-ready state through Futures without I/O', () {
    for (final state in MeshCoreSessionState.values.where(
      (s) => s != MeshCoreSessionState.ready,
    )) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final cleanup = Completer<void>();
        transport.closing = () => cleanup.future;
        final session = MeshCoreSession(transport: transport);
        Outcome<MeshCoreSessionInfo>? connecting;
        if (state == MeshCoreSessionState.opening ||
            state == MeshCoreSessionState.initializing ||
            state == MeshCoreSessionState.failed) {
          connecting = Outcome(session.connect());
          if (state != MeshCoreSessionState.opening) clock.flushMicrotasks();
          if (state == MeshCoreSessionState.failed) transport.receive([]);
        }
        if (state == MeshCoreSessionState.closing ||
            state == MeshCoreSessionState.closed) {
          Outcome(session.close());
          if (state == MeshCoreSessionState.closed) {
            cleanup.complete();
            clock.flushMicrotasks();
          }
        }
        expect(session.state, state);
        final calls = List.of(transport.calls);
        final send = Outcome(sendData(session));
        final read = Outcome(session.readNextMessage());
        expect(transport.calls, calls);
        clock.flushMicrotasks();
        expect(send.error, isStateError);
        expect(read.error, isStateError);
        // Opening may now dispatch its original initialization request only.
        expect(transport.sent.every((frame) => frame[0] == 0x16), isTrue);
        Outcome(session.close());
        if (!cleanup.isCompleted) cleanup.complete();
        clock.flushMicrotasks();
        if (connecting != null) expect(connecting.done, isTrue);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test('local validation leaves accepted work intact and configuration rejects negatives', () {
    fakeAsync((clock) {
      final unused = FakeCompanionTransport();
      expect(
        () => MeshCoreSession(transport: unused, maxQueuedCommands: -1),
        throwsArgumentError,
      );
      expect(unused.calls, isEmpty);
      final h = ReadyHarness(clock);
      expect(h.session.maxQueuedCommands, 8);
      final active = Outcome(h.session.readNextMessage());
      clock.flushMicrotasks();
      final calls = List.of(h.transport.calls);
      final invalid = [
        Outcome(sendData(h.session, channel: -1)),
        Outcome(sendData(h.session, descriptor: 0xff, path: Uint8List(1))),
      ];
      clock.flushMicrotasks();
      expect(invalid.every((o) => o.error is ArgumentError), isTrue);
      expect(h.transport.calls, calls);
      expect(h.session.lastFailure, isNull);
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(active.value, isA<NoMoreMessagesResponse>());
      h.close();
    });
  });

  test('send and read share a bounded FIFO and only one send is in flight', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock, capacity: 1);
      final write = Completer<void>();
      h.transport.sending = (_, index) =>
          index == 2 ? write.future : Future.value();
      final first = Outcome(sendData(h.session));
      final second = Outcome(h.session.readNextMessage());
      final rejected = Outcome(sendData(h.session));
      expect(h.transport.sent, hasLength(2));
      clock.flushMicrotasks();
      expect(rejected.error, isA<MeshCoreSessionQueueFull>());
      expect((rejected.error as MeshCoreSessionQueueFull).maxQueuedCommands, 1);
      expect(h.transport.sent.skip(2).map((f) => f[0]), [0x3e]);
      h.transport.receive([0x00]);
      clock.flushMicrotasks();
      expect(first.done, isFalse);
      expect(second.done, isFalse);
      write.complete();
      clock.flushMicrotasks();
      expect(first.value, isA<OkResponse>());
      expect(h.transport.sent.skip(2).map((f) => f[0]), [0x3e, 0x0a]);
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(second.value, isA<NoMoreMessagesResponse>());
      expect(h.session.lastFailure, isNull);
      expect(h.transport.listenCount, 1);
      h.close();
    });
  });

  test('capacity zero reserves an idle command before dispatch and rejects waiting', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock, capacity: 0);
      final first = Outcome(h.session.readNextMessage());
      final rejected = Outcome(sendData(h.session));
      // Neither input can satisfy the merely reserved command.
      h.transport.receive([0x0a]);
      h.transport.receive([0x01, 4]);
      clock.flushMicrotasks();
      expect(rejected.error, isA<MeshCoreSessionQueueFull>());
      expect(first.done, isFalse);
      expect(h.transport.sent.skip(2).single, [0x0a]);
      expect(h.session.lastFailure, isNull);
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(first.value, isA<NoMoreMessagesResponse>());
      final next = Outcome(sendData(h.session));
      clock.flushMicrotasks();
      h.transport.receive([0x00]);
      clock.flushMicrotasks();
      expect(next.value, isA<OkResponse>());
      h.close();
    });
  });

  test(
    'queued commands own bytes at admission and contain no serial header',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final first = Outcome(h.session.readNextMessage());
        final path = Uint8List.fromList([0xaa, 0xbb]);
        final payload = Uint8List.fromList([0x3c, 0, 0x3e]);
        final queued = Outcome(
          sendData(h.session, descriptor: 2, path: path, payload: payload),
        );
        path.fillRange(0, path.length, 0);
        payload.fillRange(0, payload.length, 0xff);
        clock.flushMicrotasks();
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        expect(first.value, isA<NoMoreMessagesResponse>());
        expect(h.transport.sent.last, [
          0x3e,
          2,
          2,
          0xaa,
          0xbb,
          0x34,
          0x12,
          0x3c,
          0,
          0x3e,
        ]);
        h.transport.receive([0x00]);
        clock.flushMicrotasks();
        expect(queued.value, isA<OkResponse>());
        h.close();
      });
    },
  );

  test(
    'both write and response are required in either order and during send',
    () {
      for (final read in [false, true]) {
        for (final order in ['inside-send', 'response-first', 'write-first']) {
          fakeAsync((clock) {
            final h = ReadyHarness(clock);
            final write = Completer<void>();
            final response = read ? [0x0a] : [0x00];
            h.transport.sending = (_, _) {
              if (order == 'inside-send') h.transport.receive(response);
              return write.future;
            };
            final result = Outcome(
              read ? h.session.readNextMessage() : sendData(h.session),
            );
            clock.flushMicrotasks();
            if (order == 'response-first') h.transport.receive(response);
            clock.flushMicrotasks();
            expect(result.done, isFalse);
            write.complete();
            clock.flushMicrotasks();
            expect(result.done, order != 'write-first');
            if (order == 'write-first') h.transport.receive(response);
            clock.flushMicrotasks();
            expect(result.error, isNull);
            expect(result.completionCount, 1);
            expect(
              result.value,
              read ? isA<NoMoreMessagesResponse>() : isA<OkResponse>(),
            );
            h.close();
          });
        }
      }
    },
  );

  test('early results cannot hide write failure and queued facts describe their own command', () {
    for (final read in [false, true]) {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final write = Completer<void>();
        final cleanup = Completer<void>();
        h.transport.closing = () => cleanup.future;
        h.transport.sending = (_, _) {
          h.transport.receive(read ? [0x0a] : [0x00]);
          return write.future;
        };
        final active = Outcome(
          read ? h.session.readNextMessage() : sendData(h.session),
        );
        final waiting = Outcome(
          read ? sendData(h.session) : h.session.readNextMessage(),
        );
        clock.flushMicrotasks();
        final cause = StateError('PRIVATE_WRITE');
        final stack = StackTrace.current;
        write.completeError(cause, stack);
        clock.flushMicrotasks();
        final failed = commandFailure(
          active,
          h.session,
          opcode: read ? 0x0a : 0x3e,
          dispatched: true,
          written: false,
          observed: true,
        );
        commandFailure(
          waiting,
          h.session,
          opcode: read ? 0x3e : 0x0a,
          dispatched: false,
          written: false,
          observed: false,
        );
        expect(
          failed.sessionFailure.kind,
          MeshCoreSessionFailureKind.transport,
        );
        expect(failed.sessionFailure.cause, same(cause));
        expect(failed.sessionFailure.stackTrace, same(stack));
        expect(h.transport.sent, hasLength(3));
        final closed = Outcome(h.session.close());
        expect(closed.done, isFalse);
        expect(h.transport.cancelCount, 0);
        h.transport.receiveError(StateError('late stream'));
        cleanup.completeError(StateError('PRIVATE_CLEANUP'));
        clock.flushMicrotasks();
        expect(closed.error, same(h.session.cleanupFailures.single));
        expect(h.session.lastFailure, same(failed.sessionFailure));
        expect(h.transport.closeCount, 1);
        expect(h.transport.cancelCount, 1);
        expect(h.transport.pauseCount, 0);
        expect(active.completionCount, 1);
        expect(waiting.completionCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test('single reads return datagrams, ordinary kinds, or empty with no automatic read', () {
    for (final (content, kind) in <(List<int>, QueuedMessageKind?)>[
      (datagram([7, 8]), null),
      ([0x0a], null),
      ([0x07, ...List.filled(12, 0)], QueuedMessageKind.legacyContact),
      ([0x10, ...List.filled(15, 0)], QueuedMessageKind.contactV3),
      (
        [0x08, ...List.filled(7, 0), ...utf8.encode('PRIVATE_CHAT')],
        QueuedMessageKind.legacyChannelText,
      ),
      ([0x11, ...List.filled(10, 0)], QueuedMessageKind.channelTextV3),
    ]) {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final result = Outcome(h.session.readNextMessage());
        clock.flushMicrotasks();
        h.transport.receive(content);
        h.transport.receive([0x83]);
        clock.flushMicrotasks();
        expect(result.error, isNull);
        expect(result.completionCount, 1);
        if (kind != null) {
          expect((result.value as QueuedMessageResponse).kind, kind);
        } else if (content[0] == 0x1b) {
          final response = result.value as ChannelDataResponse;
          expect(response.payload, [7, 8]);
          expect(response.channelIndex, 2);
          expect(response.dataType, 0x1234);
          expect(() => response.payload[0] = 0, throwsUnsupportedError);
          content[9] = 0;
          expect(response.payload, [7, 8]);
        } else {
          expect(result.value, isA<NoMoreMessagesResponse>());
        }
        clock.elapse(const Duration(seconds: 10));
        expect(h.session.state, MeshCoreSessionState.ready);
        expect(h.transport.sent.skip(2), [
          [0x0a],
        ]);
        h.close();
      });
    }
  });

  test(
    'wrong types and duplicates are structural and the first read result wins',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final events = <MeshCoreSessionEvent>[];
        h.session.events.listen(events.add);
        final send = Outcome(sendData(h.session));
        clock.flushMicrotasks();
        for (final response in [
          [0x83],
          datagram([9]),
          [0x0a],
          [0x08, ...List.filled(7, 0)],
          [0xfe, 99],
        ]) {
          h.transport.receive(response);
        }
        clock.flushMicrotasks();
        expect(send.done, isFalse);
        h.transport.receive([0x00]);
        clock.flushMicrotasks();
        expect(send.value, isA<OkResponse>());
        final write = Completer<void>();
        h.transport.sending = (_, _) => write.future;
        final read = Outcome(h.session.readNextMessage());
        clock.flushMicrotasks();
        h.transport.receive([0x00]);
        h.transport.receive(datagram([1]));
        h.transport.receive(datagram([2]));
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        expect(read.done, isFalse);
        write.complete();
        clock.flushMicrotasks();
        expect((read.value as ChannelDataResponse).payload, [1]);
        h.transport.receive([0x01, 254]);
        clock.flushMicrotasks();
        expect(h.session.lastFailure, isNull);
        final summaries = events
            .whereType<MeshCoreSessionUnassociatedResponse>()
            .toList();
        expect(summaries.map((e) => e.opcode), [
          0x83,
          0x1b,
          0x0a,
          0x08,
          0xfe,
          0,
          0x1b,
          0x0a,
          1,
        ]);
        expect(summaries.last.deviceErrorCode, 254);
        expect(h.transport.sent, hasLength(4));
        h.close();
      });
    },
  );

  test('waiting time consumes no request budget and duplicate input cannot supply the next read', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final first = Outcome(h.session.readNextMessage());
      final next = Outcome(h.session.readNextMessage());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 4));
      h.transport.receive([0x0a]);
      // The next command is reserved, not dispatched, in this callback gap.
      h.transport.receive(datagram([77]));
      final newcomer = Outcome(sendData(h.session));
      clock.flushMicrotasks();
      expect(first.value, isA<NoMoreMessagesResponse>());
      expect(next.done, isFalse);
      expect(h.transport.sent.skip(2).map((f) => f[0]), [0x0a, 0x0a]);
      clock.elapse(const Duration(seconds: 4));
      expect(next.done, isFalse);
      h.transport.receive(datagram([88]));
      clock.flushMicrotasks();
      expect((next.value as ChannelDataResponse).payload, [88]);
      expect(h.transport.sent.last[0], 0x3e);
      h.transport.receive([0x00]);
      clock.flushMicrotasks();
      expect(newcomer.value, isA<OkResponse>());
      h.close();
    });
  });

  test('dispatch deadline covers delayed write and unrelated input without restarting', () {
    for (final earlyResult in [false, true]) {
      for (final lateWriteFails in [false, true]) {
        fakeAsync((clock) {
          final h = ReadyHarness(clock);
          final write = Completer<void>();
          h.transport.sending = (_, _) => write.future;
          final active = Outcome(h.session.readNextMessage());
          final waiting = Outcome(sendData(h.session));
          clock.flushMicrotasks();
          if (earlyResult) h.transport.receive([0x0a]);
          clock.elapse(const Duration(seconds: 4));
          h.transport.receive([0x83]);
          h.transport.receive([0x00]);
          if (earlyResult) h.transport.receive(datagram([1]));
          clock.elapse(second);
          final failure = commandFailure(
            active,
            h.session,
            opcode: 0x0a,
            dispatched: true,
            written: false,
            observed: earlyResult,
          );
          commandFailure(
            waiting,
            h.session,
            opcode: 0x3e,
            dispatched: false,
            written: false,
            observed: false,
          );
          expect(
            failure.sessionFailure.kind,
            MeshCoreSessionFailureKind.requestTimeout,
          );
          expect(failure.sessionFailure.expectedResponseOpcode, isNull);
          expect(failure.sessionFailure.commandOpcode, 0x0a);
          if (lateWriteFails) {
            write.completeError(StateError('late write'));
          } else {
            write.complete();
          }
          h.transport.receive([0x00]);
          clock.flushMicrotasks();
          expect(failure.localWriteCompleted, isFalse);
          expect(h.transport.sent, hasLength(3));
          expect(active.completionCount, 1);
          expect(waiting.completionCount, 1);
          h.close();
        });
      }
    }
  });

  test('write completion does not renew a ready command deadline', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final write = Completer<void>();
      h.transport.sending = (_, _) => write.future;
      final result = Outcome(sendData(h.session));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 4));
      write.complete();
      clock.flushMicrotasks();
      clock.elapse(second);
      final failure = commandFailure(
        result,
        h.session,
        opcode: 0x3e,
        dispatched: true,
        written: true,
        observed: false,
      );
      expect(failure.sessionFailure.expectedResponseOpcode, 0);
      expect(
        failure.sessionFailure.kind,
        MeshCoreSessionFailureKind.requestTimeout,
      );
      h.close();
    });
  });

  test('close before dispatch or with active and waiting work settles all Futures promptly', () {
    for (final dispatched in [false, true]) {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final snapshot = h.session.info;
        final cleanup = Completer<void>();
        final write = Completer<void>();
        h.transport.closing = () => cleanup.future;
        h.transport.sending = (_, _) => write.future;
        final active = Outcome(sendData(h.session));
        final waiting = Outcome(h.session.readNextMessage());
        if (dispatched) {
          clock.flushMicrotasks();
          h.transport.receive([0x00]);
        }
        final closing = h.session.close();
        final closed = Outcome(closing);
        expect(h.session.close(), same(closing));
        clock.flushMicrotasks();
        final failure = commandFailure(
          active,
          h.session,
          opcode: 0x3e,
          dispatched: dispatched,
          written: false,
          observed: dispatched,
          canceled: true,
        );
        commandFailure(
          waiting,
          h.session,
          opcode: 0x0a,
          dispatched: false,
          written: false,
          observed: false,
          canceled: true,
        );
        expect(
          failure.sessionFailure.kind,
          MeshCoreSessionFailureKind.canceled,
        );
        expect(h.session.lastFailure, isNull);
        expect(closed.done, isFalse);
        expect(h.transport.cancelCount, 0);
        if (dispatched) write.completeError(StateError('late write'));
        h.transport.receive([]);
        clock.flushMicrotasks();
        expect(h.session.lastFailure, isNull);
        cleanup.complete();
        clock.flushMicrotasks();
        expect(closed.done, isTrue);
        expect(h.transport.sent, hasLength(dispatched ? 3 : 2));
        expect(h.session.info, same(snapshot));
        expect(active.completionCount, 1);
        expect(waiting.completionCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test(
    'committed success survives close in the gap before the next dispatch',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock, capacity: 1);
        final active = Outcome(sendData(h.session));
        final waiting = Outcome(h.session.readNextMessage());
        clock.flushMicrotasks();
        h.transport.receive([0x00]);
        // Success is already committed, even though its observers have not run.
        final accepted = Outcome(sendData(h.session));
        final excess = Outcome(h.session.readNextMessage());
        final closed = Outcome(h.session.close());
        clock.flushMicrotasks();
        expect(active.value, isA<OkResponse>());
        commandFailure(
          waiting,
          h.session,
          opcode: 0x0a,
          dispatched: false,
          written: false,
          observed: false,
          canceled: true,
        );
        commandFailure(
          accepted,
          h.session,
          opcode: 0x3e,
          dispatched: false,
          written: false,
          observed: false,
          canceled: true,
        );
        expect(excess.error, isA<MeshCoreSessionQueueFull>());
        expect(closed.done, isTrue);
        expect(h.transport.sent, hasLength(3));
        expect(active.completionCount, 1);
        expect(waiting.completionCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'terminal input stops the queue and preserves the first root failure',
    () {
      for (final trigger in [
        'device',
        'malformed',
        'stream',
        'done',
        'send-sync',
      ]) {
        fakeAsync((clock) {
          final h = ReadyHarness(clock);
          final write = Completer<void>();
          final cleanup = Completer<void>();
          h.transport.closing = () => cleanup.future;
          final cause = StateError('PRIVATE_NATIVE');
          h.transport.sending = (_, _) {
            if (trigger == 'send-sync') throw cause;
            return write.future;
          };
          final active = Outcome(sendData(h.session));
          final waiting = Outcome(h.session.readNextMessage());
          clock.flushMicrotasks();
          if (trigger == 'device') {
            // A saved OK does not commit while write is pending: ERROR still wins.
            h.transport.receive([0x00]);
            h.transport.receive([0x01, 254]);
          }
          if (trigger == 'malformed') h.transport.receive([0x83, 7]);
          if (trigger == 'stream') h.transport.receiveError(cause);
          if (trigger == 'done') Outcome(h.transport.finishInput());
          clock.flushMicrotasks();
          final failure = commandFailure(
            active,
            h.session,
            opcode: 0x3e,
            dispatched: true,
            written: false,
            observed: trigger == 'device',
          );
          commandFailure(
            waiting,
            h.session,
            opcode: 0x0a,
            dispatched: false,
            written: false,
            observed: false,
          );
          expect(failure.sessionFailure.stage, MeshCoreSessionState.ready);
          expect(failure.sessionFailure.kind, switch (trigger) {
            'device' => MeshCoreSessionFailureKind.deviceRejected,
            'malformed' => MeshCoreSessionFailureKind.protocol,
            'done' => MeshCoreSessionFailureKind.disconnected,
            _ => MeshCoreSessionFailureKind.transport,
          });
          if (trigger == 'device') {
            expect(failure.sessionFailure.deviceErrorCode, 254);
          }
          if (trigger == 'stream' || trigger == 'send-sync') {
            expect(failure.sessionFailure.cause, same(cause));
          }
          if (trigger != 'send-sync') {
            write.completeError(StateError('late send'));
          }
          final closed = Outcome(h.session.close());
          cleanup.complete();
          clock.flushMicrotasks();
          expect(h.session.lastFailure, same(failure.sessionFailure));
          expect(h.transport.sent, hasLength(3));
          expect(closed.done, isTrue);
          expect(active.completionCount, 1);
          expect(waiting.completionCount, 1);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test(
    'default summaries omit path, payload, chat text, and recursive causes',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final events = <MeshCoreSessionEvent>[];
        h.session.events.listen(events.add);
        final result = Outcome(
          sendData(
            h.session,
            descriptor: 4,
            path: Uint8List.fromList(utf8.encode('PATH')),
            payload: Uint8List.fromList(utf8.encode('PRIVATE_PAYLOAD')),
          ),
        );
        clock.flushMicrotasks();
        h.transport.receive(datagram(utf8.encode('PRIVATE_RECEIVED')));
        h.transport.receive([
          0x08,
          ...List.filled(7, 0),
          ...utf8.encode('PRIVATE_CHAT'),
        ]);
        h.transport.receiveError(StateError('PRIVATE_CAUSE'));
        clock.flushMicrotasks();
        final summary = '${result.error} ${h.session.lastFailure} $events';
        for (final secret in [
          'PATH',
          'PRIVATE_PAYLOAD',
          'PRIVATE_RECEIVED',
          'PRIVATE_CHAT',
          'PRIVATE_CAUSE',
        ]) {
          expect(summary, isNot(contains(secret)));
        }
        expect(
          (result.error as MeshCoreSessionCommandFailure).sessionFailure.cause
              .toString(),
          contains('PRIVATE_CAUSE'),
        );
        h.close();
      });
    },
  );
}

final class ReadyHarness {
  ReadyHarness(this.clock, {int capacity = 8}) {
    session = MeshCoreSession(
      transport: transport,
      maxQueuedCommands: capacity,
    );
    final connected = Outcome(session.connect());
    clock.flushMicrotasks();
    transport.receive(deviceInfo());
    clock.flushMicrotasks();
    transport.receive(selfInfo());
    clock.flushMicrotasks();
    expect(connected.error, isNull);
    expect(connected.done, isTrue);
    expect(session.state, MeshCoreSessionState.ready);
    expect(transport.sent, hasLength(2));
  }

  final FakeAsync clock;
  final transport = FakeCompanionTransport();
  late final MeshCoreSession session;

  void close() {
    final closed = Outcome(session.close());
    clock.flushMicrotasks();
    expect(closed.done, isTrue);
    expect(clock.pendingTimers, isEmpty);
  }
}

Future<OkResponse> sendData(
  MeshCoreSession session, {
  int channel = 2,
  int descriptor = 0xff,
  Uint8List? path,
  Uint8List? payload,
}) => session.sendChannelData(
  channelIndex: channel,
  dataType: 0x1234,
  routeDescriptor: descriptor,
  path: path ?? Uint8List(0),
  payload: payload ?? Uint8List.fromList([1, 2]),
);

List<int> datagram(List<int> payload) => [
  0x1b,
  0xfc,
  0,
  0,
  2,
  0xff,
  0x34,
  0x12,
  payload.length,
  ...payload,
];

MeshCoreSessionCommandFailure commandFailure(
  Outcome<CompanionResponse> outcome,
  MeshCoreSession session, {
  required int opcode,
  required bool dispatched,
  required bool written,
  required bool observed,
  bool canceled = false,
}) {
  expect(outcome.done, isTrue);
  final failure = outcome.error as MeshCoreSessionCommandFailure;
  expect(failure.commandOpcode, opcode);
  expect(failure.dispatched, dispatched);
  expect(failure.localWriteCompleted, written);
  expect(failure.matchingResponseObserved, observed);
  if (!canceled) {
    expect(failure.sessionFailure, same(session.lastFailure));
    expect(session.state, MeshCoreSessionState.failed);
  }
  return failure;
}
