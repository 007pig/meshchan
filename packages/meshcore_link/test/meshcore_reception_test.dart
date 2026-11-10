import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import 'support/fake_companion_transport.dart';
import 'support/session_test_support.dart';

const second = Duration(seconds: 1);
const window = Duration(seconds: 30);

void main() {
  test('creation and subscription are inert and budgets must be positive', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      for (final duration in [Duration.zero, -second]) {
        expect(
          () => h.session.createReception(duration: duration),
          throwsArgumentError,
        );
      }
      for (final limit in [0, -1]) {
        expect(
          () => h.session.createReception(duration: window, maxEntries: limit),
          throwsArgumentError,
        );
        expect(
          () => h.session.createReception(
            duration: window,
            maxReadsPerBatch: limit,
          ),
          throwsArgumentError,
        );
      }
      final receiver = h.session.createReception(duration: window);
      final done = Outcome(receiver.done);
      final entries = <CompanionResponse>[];
      receiver.entries.listen(entries.add);
      final diagnostics = <MeshCoreSessionEvent>[];
      h.session.events.listen(diagnostics.add);
      h.transport.receive([0x83]);
      h.transport.receive(datagram([1]));
      clock.flushMicrotasks();
      expect(receiver.maxEntries, 128);
      expect(receiver.maxReadsPerBatch, 8);
      expect(entries, isEmpty);
      expect(done.done, isFalse);
      expect(h.transport.sent, hasLength(2));
      expect(clock.pendingTimers, isEmpty);
      expect(
        diagnostics.whereType<MeshCoreSessionUnassociatedResponse>().map(
          (event) => event.opcode,
        ),
        [0x83, 0x1b],
      );
      final stopped = Outcome(receiver.stop());
      expect(receiver.stop(), same(receiver.done));
      clock.flushMicrotasks();
      expect(stopped.value, same(done.value));
      expect(done.value!.reason, MeshCoreReceptionStopReason.stopped);
      expect(done.value!.dispatchedReads, 0);
      h.close();
    });
  });

  test('first start rejection settles done without lease, timers, or I/O', () {
    for (final ready in [false, true]) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final h = ready ? ReadyHarness(clock) : null;
        final session = h?.session ?? MeshCoreSession(transport: transport);
        final receiver = session.createReception(duration: window);
        final done = Outcome(receiver.done);
        if (!ready) receiver.entries.listen((_) {});
        final started = Outcome(receiver.start());
        clock.flushMicrotasks();
        expect(started.error, isA<StateError>());
        expect(done.value!.reason, MeshCoreReceptionStopReason.startRejected);
        expect(done.value!.startError, same(started.error));
        expect(done.value!.dispatchedReads, 0);
        expect(clock.pendingTimers, isEmpty);
        expect(transport.calls, isEmpty);
        // Even a never-listened controller cannot block done or cleanup.
        final closed = Outcome(session.close());
        clock.flushMicrotasks();
        expect(closed.done, isTrue);
      });
    }
  });

  test(
    'start activates once and excludes another reception and manual reads',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        final done = Outcome(receiver.done);
        receiver.entries.listen((_) {});
        final started = Outcome(receiver.start());
        final duplicate = Outcome(receiver.start());
        final secondReceiver = h.session.createReception(duration: window);
        final secondDone = Outcome(secondReceiver.done);
        secondReceiver.entries.listen((_) {});
        final secondStart = Outcome(secondReceiver.start());
        final manual = Outcome(h.session.readNextMessage());
        clock.flushMicrotasks();
        expect(started.done, isTrue);
        expect(started.error, isNull);
        expect(done.done, isFalse);
        expect(duplicate.error, isA<StateError>());
        expect(secondStart.error, isA<StateError>());
        expect(
          secondDone.value!.reason,
          MeshCoreReceptionStopReason.startRejected,
        );
        expect(manual.error, isA<StateError>());
        expect(h.transport.sent.skip(2), [
          [0x0a],
        ]);
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        final stopped = Outcome(receiver.stop());
        clock.flushMicrotasks();
        expect(stopped.value, same(done.value));
        expect(done.value!.completedReads, 1);
        h.close();
      });
    },
  );

  test('reserved, queued, and dispatched manual reads reject start intact', () {
    for (final position in ['reserved', 'queued', 'dispatched']) {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final sending = position == 'queued'
            ? Outcome(sendData(h.session))
            : null;
        final manual = Outcome(h.session.readNextMessage());
        if (position == 'dispatched') clock.flushMicrotasks();
        final receiver = h.session.createReception(duration: window);
        final done = Outcome(receiver.done);
        receiver.entries.listen((_) {});
        final started = Outcome(receiver.start());
        clock.flushMicrotasks();
        expect(started.error, isA<StateError>());
        expect(done.value!.reason, MeshCoreReceptionStopReason.startRejected);
        expect(manual.done, isFalse);
        if (sending != null) {
          h.transport.receive([0]);
          clock.flushMicrotasks();
          expect(sending.value, isA<OkResponse>());
        }
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        expect(manual.value, isA<NoMoreMessagesResponse>());
        expect(
          h.transport.sent.skip(2).map((frame) => frame[0]),
          position == 'queued' ? [0x3e, 0x0a] : [0x0a],
        );
        h.close();
      });
    }
  });

  test('waiting bursts coalesce and only an owned empty controls demand', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final receiver = h.session.createReception(duration: window);
      final entries = <CompanionResponse>[];
      receiver.entries.listen(entries.add);
      final events = <MeshCoreSessionEvent>[];
      h.session.events.listen(events.add);
      Outcome(receiver.start());
      clock.flushMicrotasks();
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(h.transport.sent, hasLength(3));
      for (var i = 0; i < 20; i++) {
        h.transport.receive([0x83]);
      }
      // Unassociated empty input before reservation/dispatch cannot clear demand.
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(h.transport.sent, hasLength(4));
      for (var i = 0; i < 20; i++) {
        h.transport.receive([0x83]);
      }
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(h.transport.sent, hasLength(5));
      h.transport.receive([0x0a]);
      // A duplicate empty is also unassociated and cannot start another read.
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      clock.elapse(second);
      expect(h.transport.sent, hasLength(5));
      expect(entries, isEmpty);
      expect(
        events.whereType<MeshCoreSessionUnassociatedResponse>().where(
          (event) => event.opcode == 0x83,
        ),
        hasLength(40),
      );
      final stopped = Outcome(receiver.stop());
      clock.flushMicrotasks();
      expect(stopped.value!.dispatchedReads, 3);
      expect(stopped.value!.completedReads, 3);
      h.close();
    });
  });

  test('empty then waiting before write completion retains a later check', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final write = Completer<void>();
      h.transport.sending = (_, index) =>
          index == 2 ? write.future : Future.value();
      final receiver = h.session.createReception(duration: window);
      receiver.entries.listen((_) {});
      Outcome(receiver.start());
      clock.flushMicrotasks();
      h.transport.receive([0x0a]);
      h.transport.receive([0x83]);
      h.transport.receive([0x0a]); // Duplicate cannot consume the newer notice.
      clock.flushMicrotasks();
      expect(h.transport.sent, hasLength(3));
      write.complete();
      clock.flushMicrotasks();
      expect(h.transport.sent, hasLength(4));
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      expect(h.transport.sent, hasLength(4));
      Outcome(receiver.stop());
      h.close();
    });
  });

  test(
    'nonempty batches yield a real event turn and sends retain priority',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        var reads = 0;
        var eventTurns = 0;
        Timer(Duration.zero, () => eventTurns++);
        h.transport.sending = (content, _) {
          if (content[0] == 0x3e) {
            h.transport.receive([0]);
          } else {
            reads++;
            if (reads > 2) expect(eventTurns, 1);
            h.transport.receive(reads <= 5 ? datagram([reads]) : [0x0a]);
          }
          return Future.value();
        };
        final receiver = h.session.createReception(
          duration: window,
          maxReadsPerBatch: 2,
        );
        final entries = <CompanionResponse>[];
        final subscription = receiver.entries.listen(entries.add);
        Outcome(receiver.start());
        clock.flushMicrotasks();
        expect(reads, 2);
        expect(eventTurns, 0);
        expect(entries, hasLength(2));
        h.transport.receive([0x83]);
        subscription.pause();
        subscription.resume();
        final send = Outcome(sendData(h.session));
        clock.flushMicrotasks();
        expect(send.value, isA<OkResponse>());
        expect(
          reads,
          2,
        ); // Neither notice, resume, nor idle bypasses the barrier.
        clock.elapse(Duration.zero);
        expect(reads, 6); // Continuation needs no additional notice.
        expect(entries, hasLength(5));
        expect(h.transport.sent.skip(2).map((f) => f[0]), [
          0x0a,
          0x0a,
          0x3e,
          0x0a,
          0x0a,
          0x0a,
          0x0a,
        ]);
        final stopped = Outcome(receiver.stop());
        clock.flushMicrotasks();
        expect(stopped.value!.completedReads, 6);
        h.close();
      });
    },
  );

  test('busy FIFO retains one check behind all accepted sends', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final first = Outcome(sendData(h.session));
      final next = Outcome(sendData(h.session));
      final receiver = h.session.createReception(duration: window);
      receiver.entries.listen((_) {});
      Outcome(receiver.start());
      clock.flushMicrotasks();
      h.transport.receive([0x83]);
      h.transport.receive([0]);
      clock.flushMicrotasks();
      expect(first.done, isTrue);
      expect(h.transport.sent.skip(2).map((f) => f[0]), [0x3e, 0x3e]);
      h.transport.receive([0]);
      clock.flushMicrotasks();
      expect(next.done, isTrue);
      expect(h.transport.sent.last, [0x0a]);
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      Outcome(receiver.stop());
      h.close();
    });
  });

  test(
    'capacity zero permits automatic reads without adding send capacity',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock, capacity: 0);
        final receiver = h.session.createReception(duration: window);
        receiver.entries.listen((_) {});
        Outcome(receiver.start());
        clock.flushMicrotasks();
        final refused = Outcome(sendData(h.session));
        clock.flushMicrotasks();
        expect(refused.error, isA<MeshCoreSessionQueueFull>());
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        final send = Outcome(sendData(h.session));
        h.transport.receive([0x83]);
        clock.flushMicrotasks();
        expect(h.transport.sent.last[0], 0x3e);
        h.transport.receive([0]);
        clock.flushMicrotasks();
        expect(send.value, isA<OkResponse>());
        expect(h.transport.sent.last, [0x0a]);
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        Outcome(receiver.stop());
        h.close();
      });
    },
  );

  test('typed inputs are observed once in read, send, and idle positions', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final receiver = h.session.createReception(duration: window);
      final entries = <CompanionResponse>[];
      receiver.entries.listen(entries.add);
      Outcome(receiver.start());
      clock.flushMicrotasks();
      final frame = datagram(utf8.encode('PRIVATE_DATAGRAM'));
      h.transport.receive(frame);
      h.transport.receive(
        frame,
      ); // Two actual inputs, not payload deduplication.
      clock.flushMicrotasks();
      expect(entries, hasLength(2));
      h.transport.receive([0x0a]);
      clock.flushMicrotasks();
      h.transport.receive(
        datagram([3]),
      ); // Idle observation does not invent drain.
      final send = Outcome(sendData(h.session));
      clock.flushMicrotasks();
      h.transport.receive(datagram([4]));
      final ordinary = [
        0x08,
        ...List.filled(7, 0),
        ...utf8.encode('PRIVATE_CHAT'),
      ];
      h.transport.receive(ordinary);
      h.transport.receive([0xfe, 1]);
      h.transport.receive([0x0a]);
      h.transport.receive([0]);
      clock.flushMicrotasks();
      expect(send.value, isA<OkResponse>());
      expect(entries, hasLength(5));
      final response = entries.first as ChannelDataResponse;
      frame[9] = 0;
      expect(utf8.decode(response.payload), 'PRIVATE_DATAGRAM');
      expect(() => response.payload[0] = 0, throwsUnsupportedError);
      final chat = entries.last as QueuedMessageResponse;
      expect(chat.kind, QueuedMessageKind.legacyChannelText);
      expect(chat.contentLength, ordinary.length);
      expect('$entries', isNot(contains('PRIVATE_')));
      expect(h.transport.sent.skip(2).map((f) => f[0]), [0x0a, 0x0a, 0x3e]);
      final stopped = Outcome(receiver.stop());
      clock.flushMicrotasks();
      expect(stopped.value!.publishedEntries, 5);
      h.close();
    });
  });

  test(
    'ordinary queue kinds complete reads promptly and continue the drain',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        final entries = <CompanionResponse>[];
        receiver.entries.listen(entries.add);
        Outcome(receiver.start());
        clock.flushMicrotasks();
        for (final (opcode, prefix) in [
          (0x07, 12),
          (0x10, 15),
          (0x08, 7),
          (0x11, 10),
        ]) {
          h.transport.receive([opcode, ...List.filled(prefix, 0)]);
          clock.flushMicrotasks();
        }
        expect(
          entries.whereType<QueuedMessageResponse>().map((e) => e.kind),
          QueuedMessageKind.values,
        );
        expect(h.transport.sent, hasLength(7));
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        final stopped = Outcome(receiver.stop());
        clock.flushMicrotasks();
        expect(stopped.value!.completedReads, 5);
        h.close();
      });
    },
  );

  test('typed observation precedes write success and survives a later write failure', () {
    for (final sending in [false, true]) {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final write = Completer<void>();
        final cleanup = Completer<void>();
        h.transport.closing = () => cleanup.future;
        h.transport.sending = (_, _) => write.future;
        final send = sending ? Outcome(sendData(h.session)) : null;
        final receiver = h.session.createReception(duration: window);
        final done = Outcome(receiver.done);
        final entries = <CompanionResponse>[];
        receiver.entries.listen(entries.add);
        Outcome(receiver.start());
        clock.flushMicrotasks();
        h.transport.receive(datagram([5]));
        clock.flushMicrotasks();
        expect(entries, hasLength(1));
        expect(done.done, isFalse);
        if (send != null) expect(send.done, isFalse);
        final cause = StateError('PRIVATE_WRITE');
        final stack = StackTrace.current;
        write.completeError(cause, stack);
        clock.flushMicrotasks();
        expect(done.value!.reason, MeshCoreReceptionStopReason.sessionFailed);
        expect(done.value!.publishedEntries, 1);
        expect(done.value!.sessionFailure, same(h.session.lastFailure));
        expect(done.value!.sessionFailure!.cause, same(cause));
        expect(done.value!.sessionFailure!.stackTrace, same(stack));
        if (!sending) {
          expect(done.value!.commandFailure!.matchingResponseObserved, isTrue);
          expect(done.value!.commandFailure!.localWriteCompleted, isFalse);
          expect(done.value!.completedReads, 1);
        } else {
          expect(done.value!.commandFailure, isNull);
          expect(send!.error, isA<MeshCoreSessionCommandFailure>());
        }
        expect('${done.value}', isNot(contains('PRIVATE_WRITE')));
        final closed = Outcome(h.session.close());
        expect(closed.done, isFalse);
        expect(h.transport.cancelCount, 0);
        cleanup.complete();
        clock.flushMicrotasks();
        expect(closed.done, isTrue);
        expect(h.transport.pauseCount, 0);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test('paused entries have a hard total quota without pausing transport or cleanup', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final receiver = h.session.createReception(
        duration: window,
        maxEntries: 3,
      );
      final done = Outcome(receiver.done);
      final entries = <CompanionResponse>[];
      var streamDone = false;
      final subscription = receiver.entries.listen(
        entries.add,
        onDone: () => streamDone = true,
      );
      subscription.pause();
      Outcome(receiver.start());
      for (var i = 0; i < 6; i++) {
        final content = datagram([i]);
        content[6] = i; // Other applications/types are not filtered.
        h.transport.receive(content);
      }
      clock.flushMicrotasks();
      expect(entries, isEmpty);
      expect(done.value!.reason, MeshCoreReceptionStopReason.entryLimit);
      expect(done.value!.publishedEntries, 3);
      expect(done.value!.dispatchedReads, 0);
      expect(streamDone, isFalse);
      expect(h.transport.sent, hasLength(2));
      expect(h.transport.pauseCount, 0);
      h.close();
      expect(streamDone, isFalse);
      subscription.resume();
      clock.flushMicrotasks();
      expect(
        entries,
        hasLength(3),
      ); // Already-added entries remain deliverable.
      expect(streamDone, isTrue);
      expect(h.transport.sent, hasLength(2));
    });
  });

  test(
    'quota on a read result still permits original matching and settlement',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(
          duration: window,
          maxEntries: 1,
        );
        final done = Outcome(receiver.done);
        final entries = <CompanionResponse>[];
        receiver.entries.listen(entries.add);
        Outcome(receiver.start());
        clock.flushMicrotasks();
        h.transport.receive(datagram([1]));
        h.transport.receive(datagram([2]));
        clock.flushMicrotasks();
        expect(entries, hasLength(1));
        expect(done.value!.reason, MeshCoreReceptionStopReason.entryLimit);
        expect(done.value!.completedReads, 1);
        expect(done.value!.commandFailure, isNull);
        expect(h.transport.sent, hasLength(3));
        expect(h.session.lastFailure, isNull);
        h.close();
      });
    },
  );

  test(
    'pause retains continuation and resume never creates another initial check',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        final subscription = receiver.entries.listen((_) {});
        Outcome(receiver.start());
        clock.flushMicrotasks();
        subscription.pause();
        h.transport.receive([0x83]);
        h.transport.receive(datagram([1]));
        clock.flushMicrotasks();
        clock.elapse(second);
        expect(h.transport.sent, hasLength(3));
        expect(h.transport.pauseCount, 0);
        subscription.resume();
        clock.flushMicrotasks();
        expect(h.transport.sent, hasLength(4));
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        subscription.pause();
        subscription.resume();
        clock.flushMicrotasks();
        expect(h.transport.sent, hasLength(4));
        Outcome(receiver.stop());
        h.close();
      });
    },
  );

  test(
    'pause withdraws an undispatched reservation and resume retains its check',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        final subscription = receiver.entries.listen((_) {});
        Outcome(receiver.start());
        scheduleMicrotask(subscription.pause); // After pump, before dispatch.
        clock.flushMicrotasks();
        expect(h.transport.sent, hasLength(2));
        final send = Outcome(sendData(h.session));
        clock.flushMicrotasks();
        h.transport.receive([0]);
        clock.flushMicrotasks();
        expect(send.value, isA<OkResponse>());
        subscription.resume();
        clock.flushMicrotasks();
        expect(h.transport.sent.last, [0x0a]);
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        final stopped = Outcome(receiver.stop());
        clock.flushMicrotasks();
        expect(stopped.value!.dispatchedReads, 1);
        expect(stopped.value!.completedReads, 1);
        h.close();
      });
    },
  );

  test(
    'duration includes busy FIFO and pause without canceling a healthy send',
    () {
      for (final paused in [false, true]) {
        fakeAsync((clock) {
          final h = ReadyHarness(clock);
          final send = Outcome(sendData(h.session));
          final receiver = h.session.createReception(duration: second);
          final done = Outcome(receiver.done);
          final subscription = receiver.entries.listen((_) {});
          if (paused) subscription.pause();
          Outcome(receiver.start());
          clock.flushMicrotasks();
          clock.elapse(second);
          expect(
            done.value!.reason,
            MeshCoreReceptionStopReason.durationElapsed,
          );
          expect(done.value!.dispatchedReads, 0);
          expect(send.done, isFalse);
          h.transport.receive([0]);
          subscription.resume();
          clock.flushMicrotasks();
          expect(send.value, isA<OkResponse>());
          expect(h.transport.sent.skip(2).map((f) => f[0]), [0x3e]);
          expect(h.session.state, MeshCoreSessionState.ready);
          h.close();
        });
      }
    },
  );

  test(
    'stop before pump or while busy prevents delayed reads and keeps sends',
    () {
      for (final busy in [false, true]) {
        fakeAsync((clock) {
          final h = ReadyHarness(clock);
          final send = busy ? Outcome(sendData(h.session)) : null;
          final receiver = h.session.createReception(duration: window);
          receiver.entries.listen((_) {});
          Outcome(receiver.start());
          h.transport.receive([0x83]);
          final stopped = Outcome(receiver.stop());
          clock.flushMicrotasks();
          expect(stopped.value!.dispatchedReads, 0);
          if (send != null) {
            h.transport.receive([0]);
            clock.flushMicrotasks();
            expect(send.value, isA<OkResponse>());
          }
          clock.elapse(window);
          expect(h.transport.sent.skip(2).map((f) => f[0]), busy ? [0x3e] : []);
          expect(h.session.lastFailure, isNull);
          h.close();
        });
      }
    },
  );

  test(
    'stop withdraws only its reserved read and advances an accepted send',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        receiver.entries.listen((_) {});
        Outcome(receiver.start());
        late Outcome<OkResponse> send;
        late Outcome<MeshCoreReceptionResult> stopped;
        scheduleMicrotask(() {
          send = Outcome(sendData(h.session));
          stopped = Outcome(receiver.stop());
        });
        clock.flushMicrotasks();
        expect(stopped.value!.dispatchedReads, 0);
        expect(stopped.value!.commandFailure, isNull);
        expect(h.transport.sent.skip(2).map((f) => f[0]), [0x3e]);
        h.transport.receive([0]);
        clock.flushMicrotasks();
        expect(send.value, isA<OkResponse>());
        expect(h.session.lastFailure, isNull);
        h.close();
      });
    },
  );

  test(
    'stopping in-flight retains lease and matching while user sends continue',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        final entries = <CompanionResponse>[];
        receiver.entries.listen(entries.add);
        Outcome(receiver.start());
        clock.flushMicrotasks();
        final stopped = Outcome(receiver.stop());
        final manual = Outcome(h.session.readNextMessage());
        final nextReceiver = h.session.createReception(duration: window);
        nextReceiver.entries.listen((_) {});
        final nextStart = Outcome(nextReceiver.start());
        final send = Outcome(sendData(h.session));
        clock.flushMicrotasks();
        expect(stopped.done, isFalse);
        expect(manual.error, isA<StateError>());
        expect(nextStart.error, isA<StateError>());
        h.transport.receive(datagram([1]));
        clock.flushMicrotasks();
        expect(entries, isEmpty);
        expect(stopped.value!.completedReads, 1);
        expect(stopped.value!.commandFailure, isNull);
        expect(h.transport.sent.last[0], 0x3e);
        h.transport.receive([0]);
        clock.flushMicrotasks();
        expect(send.value, isA<OkResponse>());
        final newManual = Outcome(h.session.readNextMessage());
        clock.flushMicrotasks();
        expect(newManual.done, isFalse); // Old input was not replayed.
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        expect(newManual.value, isA<NoMoreMessagesResponse>());
        h.close();
      });
    },
  );

  test('stop after success commit still waits for the owned continuation', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final receiver = h.session.createReception(duration: window);
      receiver.entries.listen((_) {});
      Outcome(receiver.start());
      clock.flushMicrotasks();
      h.transport.receive([0x0a]);
      final stopped = Outcome(receiver.stop());
      final refused = Outcome(h.session.readNextMessage());
      clock.flushMicrotasks();
      expect(refused.error, isA<StateError>());
      expect(stopped.value!.completedReads, 1);
      expect(stopped.value!.sessionFailure, isNull);
      expect(h.transport.sent, hasLength(3));
      h.close();
    });
  });

  test(
    'duration reason survives a later in-flight timeout and cleanup failure',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final cleanup = Completer<void>();
        h.transport.closing = () => cleanup.future;
        final receiver = h.session.createReception(duration: second);
        final done = Outcome(receiver.done);
        receiver.entries.listen((_) {});
        Outcome(receiver.start());
        clock.flushMicrotasks();
        clock.elapse(second);
        expect(done.done, isFalse);
        h.transport.receive(datagram([1]));
        // Late input still settles the command but is no longer published.
        clock.flushMicrotasks();
        expect(done.value!.reason, MeshCoreReceptionStopReason.durationElapsed);
        expect(done.value!.publishedEntries, 0);
        expect(done.value!.completedReads, 1);
        cleanup.complete();
        h.close();
      });
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final cleanup = Completer<void>();
        h.transport.closing = () => cleanup.future;
        final receiver = h.session.createReception(duration: second);
        final done = Outcome(receiver.done);
        receiver.entries.listen((_) {});
        Outcome(receiver.start());
        clock.flushMicrotasks();
        clock.elapse(second);
        expect(done.done, isFalse);
        clock.elapse(const Duration(seconds: 4));
        expect(done.value!.reason, MeshCoreReceptionStopReason.durationElapsed);
        expect(done.value!.sessionFailure, same(h.session.lastFailure));
        expect(
          done.value!.sessionFailure!.kind,
          MeshCoreSessionFailureKind.requestTimeout,
        );
        expect(done.value!.commandFailure!.dispatched, isTrue);
        expect(done.value!.commandFailure!.matchingResponseObserved, isFalse);
        expect(done.value!.completedReads, 1);
        final closed = Outcome(h.session.close());
        expect(closed.done, isFalse);
        cleanup.completeError(StateError('PRIVATE_CLEANUP'));
        clock.flushMicrotasks();
        expect(closed.error, same(h.session.cleanupFailures.single));
        expect(h.session.lastFailure, same(done.value!.sessionFailure));
        expect(h.transport.pauseCount, 0);
        expect(h.transport.cancelCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test('quota retains an early observation and a later read write failure', () {
    fakeAsync((clock) {
      final h = ReadyHarness(clock);
      final write = Completer<void>();
      h.transport.sending = (_, _) => write.future;
      final receiver = h.session.createReception(
        duration: window,
        maxEntries: 1,
      );
      final done = Outcome(receiver.done);
      final entries = <CompanionResponse>[];
      receiver.entries.listen(entries.add);
      Outcome(receiver.start());
      clock.flushMicrotasks();
      h.transport.receive(datagram([7]));
      clock.flushMicrotasks();
      expect(entries, hasLength(1));
      expect(done.done, isFalse);
      write.completeError(StateError('PRIVATE_WRITE'));
      clock.flushMicrotasks();
      expect(done.value!.reason, MeshCoreReceptionStopReason.entryLimit);
      expect(done.value!.publishedEntries, 1);
      expect(done.value!.commandFailure!.matchingResponseObserved, isTrue);
      expect(done.value!.commandFailure!.localWriteCompleted, isFalse);
      expect(done.value!.sessionFailure, same(h.session.lastFailure));
      h.close();
    });
  });

  test(
    'empty idle reception expires and traffic never renews its lifetime',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(
          duration: const Duration(seconds: 2),
        );
        final done = Outcome(receiver.done);
        final subscription = receiver.entries.listen((_) {});
        Outcome(receiver.start());
        clock.flushMicrotasks();
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        clock.elapse(second);
        h.transport.receive([0x83]);
        clock.flushMicrotasks();
        h.transport.receive(datagram([8]));
        clock.flushMicrotasks();
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        subscription.pause();
        clock.elapse(second);
        expect(done.value!.reason, MeshCoreReceptionStopReason.durationElapsed);
        expect(done.value!.completedReads, 3);
        expect(done.value!.publishedEntries, 1);
        subscription.resume();
        h.close();
      });
    },
  );

  test(
    'cancel before start settles without acquiring a lease or doing I/O',
    () {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final receiver = h.session.createReception(duration: window);
        final done = Outcome(receiver.done);
        final subscription = receiver.entries.listen((_) {});
        final canceled = Outcome(subscription.cancel());
        final started = Outcome(receiver.start());
        clock.flushMicrotasks();
        expect(canceled.done, isTrue);
        expect(started.error, isA<StateError>());
        expect(
          done.value!.reason,
          MeshCoreReceptionStopReason.subscriptionCanceled,
        );
        expect(done.value!.dispatchedReads, 0);
        expect(h.transport.sent, hasLength(2));
        h.close();
      });
    },
  );

  test(
    'cancel and paused close settle independently of controller delivery',
    () {
      for (final cancel in [false, true]) {
        fakeAsync((clock) {
          final h = ReadyHarness(clock);
          final cleanup = Completer<void>();
          h.transport.closing = () => cleanup.future;
          final receiver = h.session.createReception(duration: window);
          final done = Outcome(receiver.done);
          var streamDone = false;
          final subscription = receiver.entries.listen(
            (_) {},
            onDone: () => streamDone = true,
          );
          Outcome(receiver.start());
          clock.flushMicrotasks();
          subscription.pause();
          if (cancel) {
            final canceled = Outcome(subscription.cancel());
            clock.flushMicrotasks();
            expect(canceled.done, isFalse);
            h.transport.receive([0x0a]);
            clock.flushMicrotasks();
            expect(canceled.done, isTrue);
            expect(
              done.value!.reason,
              MeshCoreReceptionStopReason.subscriptionCanceled,
            );
            expect(h.session.state, MeshCoreSessionState.ready);
            expect(h.transport.closeCount, 0);
            cleanup.complete();
            h.close();
          } else {
            final closed = Outcome(h.session.close());
            clock.flushMicrotasks();
            expect(
              done.value!.reason,
              MeshCoreReceptionStopReason.sessionClosed,
            );
            expect(
              done.value!.commandFailure!.sessionFailure.kind,
              MeshCoreSessionFailureKind.canceled,
            );
            expect(closed.done, isFalse);
            expect(streamDone, isFalse);
            cleanup.complete();
            clock.flushMicrotasks();
            expect(closed.done, isTrue);
            expect(streamDone, isFalse);
            subscription.resume();
            clock.flushMicrotasks();
            expect(streamDone, isTrue);
          }
          expect(h.transport.pauseCount, 0);
          expect(h.transport.listenCount, 1);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test('old pump, batch timer, deadline, and resume cannot revive a stopped handle', () {
    for (final batch in [false, true]) {
      fakeAsync((clock) {
        final h = ReadyHarness(clock);
        final old = h.session.createReception(
          duration: second,
          maxReadsPerBatch: 1,
        );
        final oldSubscription = old.entries.listen((_) {});
        Outcome(old.start());
        if (batch) {
          clock.flushMicrotasks();
          h.transport.receive(datagram([1]));
          clock.flushMicrotasks();
        }
        Outcome(old.stop());
        clock.flushMicrotasks();
        final current = h.session.createReception(duration: window);
        final done = Outcome(current.done);
        current.entries.listen((_) {});
        Outcome(current.start());
        oldSubscription.pause();
        oldSubscription.resume();
        clock.flushMicrotasks();
        h.transport.receive([0x0a]);
        clock.flushMicrotasks();
        clock.elapse(second);
        expect(done.done, isFalse);
        expect(h.transport.sent, hasLength(batch ? 4 : 3));
        Outcome(current.stop());
        h.close();
      });
    }
  });
}
