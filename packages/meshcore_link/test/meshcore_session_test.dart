import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import 'support/fake_companion_transport.dart';
import 'support/session_test_support.dart';

const second = Duration(seconds: 1);

void main() {
  test(
    'sequential initialization owns one subscription and sends inner content',
    () {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final session = MeshCoreSession(
          transport: transport,
          appName: 'Test App',
        );
        final events = <MeshCoreSessionEvent>[];
        session.events.listen(events.add);
        expect(transport.calls, isEmpty);
        expect(session.state, MeshCoreSessionState.idle);
        final result = Outcome(session.connect());
        expect(transport.calls, ['listen', 'open']);
        expect(session.state, MeshCoreSessionState.opening);
        clock.flushMicrotasks();
        expect(transport.sent, [
          [0x16, 3],
        ]);
        expect(session.info, isNull);
        transport.receive(deviceInfo());
        clock.flushMicrotasks();
        expect(transport.sent, [
          [0x16, 3],
          encodeAppStart(appName: 'Test App'),
        ]);
        expect(session.info, isNull);
        transport.receive(selfInfo());
        clock.flushMicrotasks();
        expect(result.value, same(session.info));
        expect(session.state, MeshCoreSessionState.ready);
        expect(session.info!.appTargetVersion, 3);
        expect(session.info!.deviceInfo.protocolVersion, 14);
        expect(session.info!.selfInfo.nodeName, 'private-node');
        final snapshot = session.info;
        transport.receive(selfInfo(name: 'replacement'));
        clock.flushMicrotasks();
        expect(session.info, same(snapshot));
        final closed = Outcome(session.close());
        clock.flushMicrotasks();
        expect(closed.done, isTrue);
        expect(session.state, MeshCoreSessionState.closed);
        expect(session.info, same(snapshot));
        expect(transport.listenCount, 1);
        expect(transport.closeCount, 1);
        expect(transport.pauseCount, 0);
        expect(transport.calls.last, 'cancel');
        expect(
          events.whereType<MeshCoreSessionStateChanged>().map((e) => e.state),
          [
            MeshCoreSessionState.opening,
            MeshCoreSessionState.initializing,
            MeshCoreSessionState.ready,
            MeshCoreSessionState.closing,
            MeshCoreSessionState.closed,
          ],
        );
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'unrelated, premature, and duplicate responses never supply a later step',
    () {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final write = Completer<void>();
        transport.sending = (_, index) =>
            index == 0 ? write.future : Future.value();
        final session = MeshCoreSession(transport: transport);
        final events = <MeshCoreSessionEvent>[];
        session.events.listen(events.add);
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        for (final content in [
          [0x00],
          [0x83],
          [0x0a],
          [0x1b, 0xf2, 0xa5, 0x5a, 5, 0xff, 0x34, 0x12, 0],
          [0x07, ...List.filled(12, 0xff)],
          [0x10, ...List.filled(15, 0xff)],
          [0x08, ...List.filled(7, 0xff)],
          [0x11, ...List.filled(10, 0xff)],
          [0xfe, 0x55],
          selfInfo(name: 'too-early'),
        ]) {
          transport.receive(content);
        }
        expect(session.state, MeshCoreSessionState.initializing);
        expect(result.done, isFalse);
        transport.receive(deviceInfo(model: 'first-model'));
        transport.receive(deviceInfo(model: 'duplicate-model'));
        clock.flushMicrotasks();
        expect(transport.sent, hasLength(1));
        write.complete();
        clock.flushMicrotasks();
        expect(transport.sent, hasLength(2));
        transport.receive(deviceInfo());
        clock.flushMicrotasks();
        expect(result.done, isFalse);
        transport.receive(selfInfo(name: 'requested-node'));
        clock.flushMicrotasks();
        expect(result.value!.selfInfo.nodeName, 'requested-node');
        expect(result.value!.deviceInfo.hardwareModel, 'first-model');
        expect(
          events.whereType<MeshCoreSessionUnassociatedResponse>(),
          hasLength(12),
        );
        session.close();
        clock.flushMicrotasks();
      });
    },
  );

  test('responses during send are retained but both sends must finish successfully', () {
    for (final failWrite in [false, true]) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final writes = [Completer<void>(), Completer<void>()];
        transport.sending = (_, index) {
          transport.receive(index == 0 ? deviceInfo() : selfInfo());
          return writes[index].future;
        };
        final session = MeshCoreSession(transport: transport);
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        expect(transport.sent, hasLength(1));
        expect(session.info, isNull);
        writes[0].complete();
        clock.flushMicrotasks();
        expect(transport.sent, hasLength(2));
        expect(result.done, isFalse);
        expect(session.info, isNull);
        final cause = StateError('private-write-path');
        if (failWrite) {
          writes[1].completeError(cause);
        } else {
          writes[1].complete();
        }
        clock.flushMicrotasks();
        if (failWrite) {
          expectFailure(result, MeshCoreSessionFailureKind.transport, session);
          expect(session.lastFailure!.cause, same(cause));
          expect(session.info, isNull);
        } else {
          expect(session.state, MeshCoreSessionState.ready);
        }
        session.close();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test(
    'each request has one fixed deadline including pending writes and noise',
    () {
      for (final step in [0, 1]) {
        for (final earlyResponse in [false, true]) {
          fakeAsync((clock) {
            final transport = FakeCompanionTransport();
            final write = Completer<void>();
            transport.sending = (_, index) =>
                index == step ? write.future : Future.value();
            final session = MeshCoreSession(transport: transport);
            final result = Outcome(session.connect());
            clock.flushMicrotasks();
            if (step == 1) {
              clock.elapse(const Duration(seconds: 4));
              transport.receive(deviceInfo());
              clock.flushMicrotasks();
            }
            if (earlyResponse) {
              transport.receive(step == 0 ? deviceInfo() : selfInfo());
            }
            clock.elapse(const Duration(seconds: 4));
            transport.receive([0x83]);
            transport.receive([0x00]);
            transport.receive([0x0a]);
            transport.receive([0x1b, 0, 0, 0, 0, 0xff, 0, 0, 0]);
            transport.receive([0x08, ...List.filled(7, 0xff)]);
            transport.receive(step == 0 ? selfInfo() : deviceInfo());
            clock.elapse(second);
            expectFailure(
              result,
              MeshCoreSessionFailureKind.requestTimeout,
              session,
            );
            expect(session.lastFailure!.commandOpcode, step == 0 ? 0x16 : 0x01);
            expect(
              session.lastFailure!.expectedResponseOpcode,
              step == 0 ? 0x0d : 0x05,
            );
            expect(transport.closeCount, 1);
            final cleaned = Outcome(session.close());
            write.complete();
            transport.receive(step == 0 ? deviceInfo() : selfInfo());
            clock.flushMicrotasks();
            clock.elapse(const Duration(seconds: 30));
            expect(transport.sent, hasLength(step + 1));
            expect(session.info, isNull);
            expect(cleaned.done, isTrue);
            expect(cleaned.error, isNull);
            expect(clock.pendingTimers, isEmpty);
          });
        }
      }
    },
  );

  test('send completion does not restart the response budget', () {
    fakeAsync((clock) {
      final transport = FakeCompanionTransport();
      final write = Completer<void>();
      transport.sending = (_, _) => write.future;
      final session = MeshCoreSession(transport: transport);
      final result = Outcome(session.connect());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 4));
      write.complete();
      clock.flushMicrotasks();
      transport.receive([0x00]);
      clock.elapse(second);
      expectFailure(result, MeshCoreSessionFailureKind.requestTimeout, session);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('total deadline covers open, startup delay, and combined requests', () {
    for (final phase in ['open-success', 'open-error', 'delay', 'requests']) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final open = Completer<void>();
        if (phase.startsWith('open')) transport.opening = () => open.future;
        final session = MeshCoreSession(
          transport: transport,
          initializationTimeout: const Duration(seconds: 3),
          startupDelay: phase == 'delay'
              ? const Duration(seconds: 5)
              : Duration.zero,
        );
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        if (phase == 'requests') {
          clock.elapse(const Duration(seconds: 2));
          transport.receive(deviceInfo());
          clock.flushMicrotasks();
          clock.elapse(second);
        } else {
          clock.elapse(const Duration(seconds: 3));
        }
        expectFailure(
          result,
          MeshCoreSessionFailureKind.initializationTimeout,
          session,
        );
        if (phase == 'open-success') open.complete();
        if (phase == 'open-error') open.completeError(StateError('late open'));
        clock.flushMicrotasks();
        expect(transport.sent, hasLength(phase == 'requests' ? 2 : 0));
        expect(transport.closeCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test('old request timer cannot terminate the next step', () {
    fakeAsync((clock) {
      final transport = FakeCompanionTransport();
      final session = MeshCoreSession(transport: transport);
      final result = Outcome(session.connect());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 4));
      transport.receive(deviceInfo());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      transport.receive(selfInfo());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 30));
      expect(result.value, isNotNull);
      expect(session.state, MeshCoreSessionState.ready);
      expect(clock.pendingTimers, isEmpty);
      session.close();
      clock.flushMicrotasks();
    });
  });

  test('device rejection keeps raw code, known name, stage, and command', () {
    for (final code in [4, 254]) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final session = MeshCoreSession(transport: transport);
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        transport.receive([0x01, code]);
        clock.flushMicrotasks();
        expectFailure(
          result,
          MeshCoreSessionFailureKind.deviceRejected,
          session,
        );
        final failure = session.lastFailure!;
        expect(failure.deviceErrorCode, code);
        expect(failure.deviceErrorName, code == 4 ? 'bad state' : null);
        expect(failure.cause, isA<DeviceErrorResponse>());
        expect(failure.stage, MeshCoreSessionState.initializing);
        expect(failure.commandOpcode, 0x16);
        expect(transport.sent, hasLength(1));
      });
    }
  });

  test(
    'unassociated device errors are data while malformed content is terminal',
    () {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final session = MeshCoreSession(
          transport: transport,
          startupDelay: second,
        );
        final events = <MeshCoreSessionEvent>[];
        session.events.listen(events.add);
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        transport.receive([0x01, 6]);
        clock.flushMicrotasks();
        expect(session.lastFailure, isNull);
        final errorEvent = events
            .whereType<MeshCoreSessionUnassociatedResponse>()
            .single;
        expect(errorEvent.deviceErrorCode, 6);
        expect(errorEvent.deviceErrorName, 'illegal argument');
        clock.elapse(second);
        transport.receive(deviceInfo());
        clock.flushMicrotasks();
        transport.receive(selfInfo());
        clock.flushMicrotasks();
        expect(result.value, isNotNull);
        final snapshot = session.info;
        transport.receive([0x05]);
        clock.flushMicrotasks();
        expect(session.lastFailure!.kind, MeshCoreSessionFailureKind.protocol);
        expect(session.lastFailure!.cause, isA<CompanionProtocolException>());
        expect(session.lastFailure!.stage, MeshCoreSessionState.ready);
        expect(session.info, same(snapshot));
      });
      for (final content in [
        <int>[],
        [0x05],
        [0x0d, 2],
        [0x83, 0x42], // Known controls reject unexpected tails.
        [0x1b, 0, 0, 0, 0, 0xff, 0, 0, 1], // Missing declared payload.
      ]) {
        fakeAsync((clock) {
          final transport = FakeCompanionTransport();
          final session = MeshCoreSession(transport: transport);
          final result = Outcome(session.connect());
          clock.flushMicrotasks();
          transport.receive(content);
          clock.flushMicrotasks();
          expectFailure(result, MeshCoreSessionFailureKind.protocol, session);
          expect(session.lastFailure!.cause, isA<CompanionProtocolException>());
          expect(session.lastFailure!.stackTrace, isA<StackTrace>());
          final closed = Outcome(session.close());
          clock.flushMicrotasks();
          expect(closed.done, isTrue);
          expect(transport.closeCount, 1);
          expect(transport.calls.last, 'cancel');
          expect(transport.sent, hasLength(1));
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test(
    'sync and async transport failures, stream errors, and EOF terminate once',
    () {
      for (final phase in [
        'open-sync',
        'open-async',
        'send-sync',
        'send-async',
        'stream',
        'done',
        'both',
      ]) {
        fakeAsync((clock) {
          final transport = FakeCompanionTransport();
          final cause = SerialTransportFailure(
            SerialTransportFailureKind.io,
            'private-path',
          );
          final write = Completer<void>();
          if (phase == 'open-sync') transport.opening = () => throw cause;
          if (phase == 'open-async') {
            transport.opening = () => Future.error(cause);
          }
          if (phase == 'send-sync') transport.sending = (_, _) => throw cause;
          if (phase == 'send-async') {
            transport.sending = (_, _) => Future.error(cause);
          }
          if (phase == 'both') transport.sending = (_, _) => write.future;
          final session = MeshCoreSession(transport: transport);
          final events = <MeshCoreSessionEvent>[];
          session.events.listen(events.add);
          final result = Outcome(session.connect());
          clock.flushMicrotasks();
          if (phase == 'stream' || phase == 'both') {
            transport.receiveError(cause);
          }
          if (phase == 'both') write.completeError(cause);
          if (phase == 'done') transport.finishInput();
          clock.flushMicrotasks();
          expectFailure(
            result,
            phase == 'done'
                ? MeshCoreSessionFailureKind.disconnected
                : MeshCoreSessionFailureKind.transport,
            session,
          );
          if (phase != 'done') expect(session.lastFailure!.cause, same(cause));
          expect(events.whereType<MeshCoreSessionFailed>(), hasLength(1));
          expect(transport.closeCount, 1);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test(
    'active close cancels promptly, shares cleanup, and rejects late callbacks',
    () {
      for (final phase in ['idle', 'open', 'delay', 'query', 'app', 'ready']) {
        fakeAsync((clock) {
          final transport = FakeCompanionTransport();
          final open = Completer<void>();
          final write = Completer<void>();
          final cleanup = Completer<void>();
          transport.closing = () => cleanup.future;
          if (phase == 'open') transport.opening = () => open.future;
          if (phase == 'query' || phase == 'app') {
            transport.sending = (_, index) =>
                (phase == 'query' ? index == 0 : index == 1)
                ? write.future
                : Future.value();
          }
          final session = MeshCoreSession(
            transport: transport,
            startupDelay: phase == 'delay' ? second : Duration.zero,
          );
          final result = phase == 'idle' ? null : Outcome(session.connect());
          clock.flushMicrotasks();
          if (phase == 'app' || phase == 'ready') {
            transport.receive(deviceInfo());
            clock.flushMicrotasks();
          }
          if (phase == 'ready') {
            transport.receive(selfInfo());
            clock.flushMicrotasks();
          }
          final sentCount = transport.sent.length;
          final closing = session.close();
          expect(session.close(), same(closing));
          final closed = Outcome(closing);
          clock.flushMicrotasks();
          if (result != null && phase != 'ready') {
            expect(
              (result.error as MeshCoreSessionFailure).kind,
              MeshCoreSessionFailureKind.canceled,
            );
          }
          expect(session.lastFailure, isNull);
          expect(session.state, MeshCoreSessionState.closing);
          expect(closed.done, isFalse);
          expect(transport.cancelCount, 0);
          expect(transport.pauseCount, 0);
          transport.receive([]); // Terminal callbacks must not even be parsed.
          transport.receiveError(StateError('late stream'));
          if (phase == 'open') open.complete();
          if (phase == 'query' || phase == 'app') {
            write.completeError(StateError('late write'));
          }
          clock.elapse(const Duration(seconds: 30));
          expect(transport.sent, hasLength(sentCount));
          expect(session.lastFailure, isNull);
          cleanup.complete();
          clock.flushMicrotasks();
          expect(closed.done, isTrue);
          expect(session.state, MeshCoreSessionState.closed);
          expect(transport.closeCount, 1);
          expect(transport.openCount, phase == 'idle' ? 0 : 1);
          expect(clock.pendingTimers, isEmpty);
        });
      }
    },
  );

  test('logical failure precedes pending cleanup and all cleanup errors stay observable', () {
    for (final trigger in ['timeout', 'device', 'stream']) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final cleanup = Completer<void>();
        transport.closing = () => cleanup.future;
        final cancelCause = StateError('cancel failure');
        transport.canceling = () => Future.error(cancelCause);
        final session = MeshCoreSession(transport: transport);
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        if (trigger == 'timeout') clock.elapse(const Duration(seconds: 5));
        if (trigger == 'device') transport.receive([0x01, 4]);
        if (trigger == 'stream') {
          transport.receiveError(StateError('read failure'));
        }
        clock.flushMicrotasks();
        expect(result.done, isTrue);
        expect(session.state, MeshCoreSessionState.failed);
        final primary = session.lastFailure;
        final closing = session.close();
        expect(session.close(), same(closing));
        expect(transport.cancelCount, 0);
        transport.receive([]);
        final cleanupCause = StateError('private-cleanup-path');
        cleanup.completeError(cleanupCause);
        // Automatic cleanup must observe errors even before an explicit caller
        // attaches an error handler to the shared close future.
        clock.flushMicrotasks();
        final closed = Outcome(session.close());
        clock.flushMicrotasks();
        expect(session.lastFailure, same(primary));
        expect(closed.error, same(session.cleanupFailures.first));
        expect(session.cleanupFailures.map((e) => e.cause), [
          cleanupCause,
          cancelCause,
        ]);
        expect(
          session.cleanupFailures.every(
            (e) => e.kind == MeshCoreSessionFailureKind.cleanup,
          ),
          isTrue,
        );
        expect(transport.cancelCount, 1);
        expect(transport.closeCount, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    }
  });

  test('cleanup failure after user cancellation is recorded without replacing canceled result', () {
    for (final synchronous in [false, true]) {
      fakeAsync((clock) {
        final transport = FakeCompanionTransport();
        final cause = StateError('close failure');
        transport.closing = () =>
            synchronous ? throw cause : Future.error(cause);
        final session = MeshCoreSession(transport: transport);
        final result = Outcome(session.connect());
        clock.flushMicrotasks();
        final closed = Outcome(session.close());
        clock.flushMicrotasks();
        expect(
          (result.error as MeshCoreSessionFailure).kind,
          MeshCoreSessionFailureKind.canceled,
        );
        expect(session.lastFailure!.kind, MeshCoreSessionFailureKind.cleanup);
        expect(session.lastFailure!.cause, same(cause));
        expect(closed.error, same(session.lastFailure));
        expect(transport.cancelCount, 1);
        expect(session.state, MeshCoreSessionState.failed);
      });
    }
  });

  test('observers are asynchronous, independent, and cannot block cleanup', () {
    fakeAsync((clock) {
      final transport = FakeCompanionTransport();
      final session = MeshCoreSession(transport: transport);
      final observed = <MeshCoreSessionEvent>[];
      final paused = session.events.listen(observed.add)..pause();
      final canceled = session.events.listen(
        (_) => fail('Canceled observer called'),
      );
      canceled.cancel();
      final result = Outcome(session.connect());
      expect(observed, isEmpty);
      clock.flushMicrotasks();
      transport.receive(deviceInfo());
      clock.flushMicrotasks();
      transport.receive(selfInfo());
      clock.flushMicrotasks();
      expect(result.value, isNotNull);
      final closed = Outcome(session.close());
      clock.flushMicrotasks();
      expect(closed.done, isTrue);
      expect(transport.closeCount, 1);
      expect(transport.pauseCount, 0);
      expect(transport.cancelCount, 1);
      expect(observed, isEmpty);
      paused.cancel();
      clock.flushMicrotasks();
    });
  });

  test('single-use sessions reject extra connects without disturbing independent instances', () {
    fakeAsync((clock) {
      final transport = FakeCompanionTransport();
      final session = MeshCoreSession(transport: transport);
      final result = Outcome(session.connect());
      final concurrent = Outcome(session.connect());
      clock.flushMicrotasks();
      expect(concurrent.error, isStateError);
      transport.receive(deviceInfo());
      clock.flushMicrotasks();
      transport.receive(selfInfo());
      clock.flushMicrotasks();
      expect(result.value, isNotNull);
      final repeated = Outcome(session.connect());
      clock.flushMicrotasks();
      expect(repeated.error, isStateError);
      session.close();
      clock.flushMicrotasks();
      final afterClose = Outcome(session.connect());
      final unopened = MeshCoreSession(transport: FakeCompanionTransport());
      unopened.close();
      final afterIdleClose = Outcome(unopened.connect());
      final otherTransport = FakeCompanionTransport();
      final other = MeshCoreSession(transport: otherTransport);
      final independent = Outcome(other.connect());
      clock.flushMicrotasks();
      expect(afterClose.error, isStateError);
      expect(afterIdleClose.error, isStateError);
      otherTransport.receive(deviceInfo());
      clock.flushMicrotasks();
      otherTransport.receive(selfInfo());
      clock.flushMicrotasks();
      expect(independent.value, isNotNull);
      expect(transport.openCount, 1);
      expect(transport.sent, hasLength(2));
      other.close();
      clock.flushMicrotasks();
    });
  });

  test('invalid local settings perform no I/O and all default summaries redact content', () {
    fakeAsync((clock) {
      final transport = FakeCompanionTransport();
      for (final create in <MeshCoreSession Function()>[
        () =>
            MeshCoreSession(transport: transport, appName: 'private\u0000name'),
        () => MeshCoreSession(transport: transport, appName: 'a' * 169),
        () => MeshCoreSession(
          transport: transport,
          requestTimeout: Duration.zero,
        ),
        () => MeshCoreSession(
          transport: transport,
          initializationTimeout: -second,
        ),
        () => MeshCoreSession(transport: transport, startupDelay: -second),
      ]) {
        expect(create, throwsArgumentError);
      }
      expect(transport.calls, isEmpty);
      final session = MeshCoreSession(transport: transport);
      final events = <MeshCoreSessionEvent>[];
      session.events.listen(events.add);
      final result = Outcome(session.connect());
      clock.flushMicrotasks();
      transport.receive([0xfe, ...utf8.encode('private-payload')]);
      transport.receive(selfInfo());
      transport.receive(deviceInfo());
      clock.flushMicrotasks();
      transport.receive(selfInfo());
      clock.flushMicrotasks();
      transport.receiveError(StateError('private-native-path'));
      clock.flushMicrotasks();
      final summary = '${result.value} ${session.lastFailure} $events';
      for (final secret in [
        'private-node',
        'private-model',
        'private-firmware',
        'private-payload',
        'private-native-path',
        List.filled(32, 0xab).toString(),
        '305419896',
      ]) {
        expect(summary, isNot(contains(secret)));
      }
      expect(
        session.lastFailure!.cause.toString(),
        contains('private-native-path'),
      );
      expect(transport.sent, hasLength(2));
      expect(clock.pendingTimers, isEmpty);
    });
  });
}

void expectFailure(
  Outcome<MeshCoreSessionInfo> result,
  MeshCoreSessionFailureKind kind,
  MeshCoreSession session,
) {
  expect(result.done, isTrue);
  expect(result.error, same(session.lastFailure));
  expect(session.lastFailure!.kind, kind);
  expect(session.state, MeshCoreSessionState.failed);
}
