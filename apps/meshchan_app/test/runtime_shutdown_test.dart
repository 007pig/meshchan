import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';

void main() {
  for (final order in _ReleaseOrder.values) {
    test(
      'timed-out shutdown reconciles $order without closing again',
      () async {
        final probe = _WorkerProbe();
        addTearDown(probe.dispose);
        final runtime = RuntimeController(
          resolveDirectory: () async => '/unused',
          entry: _controlledEntry(
            probe.port.sendPort,
            order == _ReleaseOrder.beforeExitTimeout,
          ),
          deadline: const Duration(seconds: 2),
        );
        await runtime.start();
        final worker = await probe.waitFor<_WorkerReady>((_) => true);
        addTearDown(() => worker.commands.send(_WorkerControl.exit));

        var requestCompletions = 0;
        final pending = runtime
            .request(const ReadOffline())
            .then<Object?>(
              (value) {
                requestCompletions++;
                return value;
              },
              onError: (Object error) {
                requestCompletions++;
                return error;
              },
            );
        final read = await probe.waitFor<_ReadSeen>((_) => true);
        final firstShutdown = runtime.shutdown();
        expect(identical(firstShutdown, runtime.shutdown()), true);
        final close = await probe.waitFor<_ShutdownSeen>((_) => true);
        final unknown = await firstShutdown;
        expect(unknown.canExit, false);
        expect(runtime.pendingCount, 0);
        expect(runtime.openPortCount, 3);
        expect(
          await pending,
          isA<RuntimeFault>().having(
            (e) => e.host,
            'request outcome',
            CoordinationFault.requestUnknown,
          ),
        );
        expect(requestCompletions, 1);

        if (order == _ReleaseOrder.afterExit) {
          worker.commands.send(_WorkerControl.exit);
          await _state(runtime, (s) => s.workerExited);
          expect(runtime.snapshot.owner, OwnerFact.unknown);
          expect((await runtime.shutdown()).canExit, false);
          // Model a final release message delivered on the event port after the
          // independent onExit port. The worker has no native resources in this
          // client-protocol fixture; only these controlled facts are simulated.
          worker.events.send(_release(runtime.generation, close.id));
        } else {
          if (order == _ReleaseOrder.afterTimeout) {
            worker.commands.send(_WorkerControl.release);
          }
          await _state(runtime, (s) => s.owner == OwnerFact.released);
          await probe.waitFor<_Acknowledged>((_) => true);
          expect(runtime.snapshot.workerExited, false);
          expect((await runtime.shutdown()).canExit, false);
          expect(runtime.openPortCount, 3);
          // A timed-out request's late reply must remain ignored even though
          // authoritative release/exit facts can later permit application quit.
          worker.events.send(
            RequestReply(
              runtime.generation,
              read.id,
              value: OfflineSnapshot(null, 1000, [], null),
            ),
          );
          worker.commands.send(_WorkerControl.exit);
        }

        await _state(
          runtime,
          (s) => s.owner == OwnerFact.released && s.workerExited,
        );
        // Disposal is triggered by the late facts themselves, before another
        // caller asks permission to quit.
        await runtime.changes.drain<void>();
        expect(runtime.openPortCount, 0);
        final reconciled = runtime.shutdown();
        expect(identical(reconciled, runtime.shutdown()), true);
        final verified = await reconciled;
        expect(verified.canExit, true);
        expect(verified.resourcesReleased, true);
        expect(verified.workerWasSpawned, true);
        expect(verified.workerExited, true);
        expect(runtime.openPortCount, 0);
        expect(runtime.pendingCount, 0);
        expect(requestCompletions, 1);
        expect(
          (await firstShutdown).canExit,
          false,
          reason: 'The earlier unknown observation remains immutable',
        );
        expect(probe.seen.whereType<_ShutdownSeen>().length, 1);
        expect(close.count, 1);
      },
    );
  }

  test(
    'rejected Isolate.spawn owns nothing and permits exit without onExit',
    () async {
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      var resolutions = 0;
      final runtime = RuntimeController(
        resolveDirectory: () async {
          resolutions++;
          return '/unused';
        },
        entry: _unsendableEntry(unsendable),
      );
      final pending = expectLater(
        runtime.request(const ReadOffline()),
        throwsA(
          isA<RuntimeFault>()
              .having(
                (e) => e.host,
                'creation failure',
                CoordinationFault.spawnFailed,
              )
              .having((e) => e.cleanupUnconfirmed, 'no owner', false),
        ),
      );
      final start = runtime.start();
      expect(identical(start, runtime.start()), true);
      await start;
      await pending;
      expect(resolutions, 1);
      expect(runtime.snapshot.phase, RuntimePhase.fault);
      expect(runtime.snapshot.owner, OwnerFact.none);
      expect(runtime.snapshot.workerExited, false);
      expect(runtime.snapshot.error!.cleanupUnconfirmed, false);
      expect(runtime.pendingCount, 0);
      expect(runtime.openPortCount, 0);
      final shutdown = runtime.shutdown();
      expect(identical(shutdown, runtime.shutdown()), true);
      final result = await shutdown;
      expect(result.canExit, true);
      expect(result.resourcesReleased, true);
      expect(result.workerWasSpawned, false);
      expect(result.workerExited, false);
    },
  );
}

Future<RuntimeSnapshot> _state(
  RuntimeController runtime,
  bool Function(RuntimeSnapshot) predicate,
) async {
  if (predicate(runtime.snapshot)) return runtime.snapshot;
  return runtime.changes.firstWhere(predicate);
}

enum _ReleaseOrder { afterTimeout, beforeExitTimeout, afterExit }

enum _WorkerControl { release, exit }

final class _WorkerReady {
  const _WorkerReady(this.commands, this.events);
  final SendPort commands, events;
}

final class _ShutdownSeen {
  const _ShutdownSeen(this.id, this.count);
  final int id, count;
}

final class _ReadSeen {
  const _ReadSeen(this.id);
  final int id;
}

final class _Acknowledged {
  const _Acknowledged();
}

final class _WorkerProbe {
  _WorkerProbe() {
    subscription = port.listen((event) {
      seen.add(event);
      events.add(event);
    });
  }
  final port = ReceivePort();
  final seen = <Object?>[];
  final events = StreamController<Object?>.broadcast(sync: true);
  late final StreamSubscription<Object?> subscription;
  Future<T> waitFor<T>(bool Function(T) predicate) async {
    for (final event in seen.whereType<T>()) {
      if (predicate(event)) return event;
    }
    return await events.stream.where((e) => e is T && predicate(e)).first as T;
  }

  Future<void> dispose() async {
    await subscription.cancel();
    port.close();
    await events.close();
  }
}

// Separate factories keep closure capture graphs small and reviewable. One
// entry captures only sendable values; the other deliberately captures an
// unsendable ReceivePort so the real SDK rejects creation before worker entry.
void Function(WorkerBootstrap) _controlledEntry(
  SendPort observer,
  bool releaseEarly,
) =>
    (bootstrap) => _controlledWorker(bootstrap, observer, releaseEarly);
void Function(WorkerBootstrap) _unsendableEntry(ReceivePort unsendable) =>
    (bootstrap) => unsendable.sendPort.send(bootstrap.generation);

ReleaseReport _release(int generation, int id) => ReleaseReport(
  generation,
  id,
  RuntimeSnapshot(
    generation: generation,
    sequence: 2,
    phase: RuntimePhase.closed,
    owner: OwnerFact.released,
  ),
  true,
);

void _controlledWorker(
  WorkerBootstrap bootstrap,
  SendPort observer,
  bool releaseEarly,
) {
  final commands = ReceivePort();
  var shutdownId = 0, shutdownCount = 0;
  commands.listen((message) {
    if (message == _WorkerControl.exit) {
      commands.close();
      return;
    }
    if (message == _WorkerControl.release) {
      bootstrap.events.send(_release(bootstrap.generation, shutdownId));
      return;
    }
    if (message is ReleaseAcknowledged) {
      observer.send(const _Acknowledged());
      return; // Exit is held independently until the test permits it.
    }
    if (message is! RequestEnvelope) return;
    if (message.request is ShutdownRuntime) {
      shutdownId = message.id;
      observer.send(_ShutdownSeen(shutdownId, ++shutdownCount));
      if (releaseEarly) {
        bootstrap.events.send(_release(bootstrap.generation, shutdownId));
      }
    } else if (message.request is ReadOffline) {
      observer.send(_ReadSeen(message.id));
    } else {
      bootstrap.events.send(
        RequestReply(bootstrap.generation, message.id, value: const Accepted()),
      );
    }
  });
  bootstrap.events.send(WorkerHello(bootstrap.generation, commands.sendPort));
  bootstrap.events.send(
    SnapshotEvent(
      bootstrap.generation,
      RuntimeSnapshot(
        generation: bootstrap.generation,
        sequence: 1,
        phase: RuntimePhase.ready,
        owner: OwnerFact.held,
      ),
    ),
  );
  observer.send(_WorkerReady(commands.sendPort, bootstrap.events));
}
