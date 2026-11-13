import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/host_bootstrap.dart';
import 'package:meshchan_app/launch_configuration.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';

void main() {
  test('live-owner quit acceptance requires an explicit isolated fixture', () {
    final config = LaunchConfiguration.parse([
      '--meshchan-runtime=quit-ready',
      '--data-dir=/unused/meshchan-1d3-quit',
    ]);
    expect(config.mode, LaunchMode.runtimeVerification);
    expect(config.verification, 'quit-ready');
    for (final args in [
      ['--meshchan-runtime=quit-ready'],
      ['--meshchan-runtime=quit-ready', '--data-dir=/unused/user-data'],
      [
        '--meshchan-runtime=quit-ready',
        '--data-dir=/unused/meshchan-1d3-quit',
        '--runtime-exit',
      ],
    ]) {
      expect(() => LaunchConfiguration.parse(args), throwsFormatException);
    }
  });
  test(
    'first rendered frame and native grant precede directory/worker access',
    () async {
      final frame = Completer<void>();
      final granting = Completer<void>();
      final grant = Completer<bool>();
      final bootstrap = HostResourceBootstrap(
        firstFrame: () => frame.future,
        authorize: () {
          granting.complete();
          return grant.future;
        },
      );
      final directory = Directory.systemTemp.createTempSync(
        'meshchan-first-frame-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      var resolutions = 0;
      final runtime = RuntimeController(
        prepareForResources: bootstrap.prepare,
        resolveDirectory: () async {
          resolutions++;
          return directory.path;
        },
      );
      final starting = runtime.start();
      expect(identical(starting, runtime.start()), true);
      expect(resolutions, 0);
      expect(granting.isCompleted, false);
      expect(directory.listSync(), isEmpty);
      frame.complete();
      await granting.future;
      expect(resolutions, 0);
      expect(directory.listSync(), isEmpty);
      grant.complete(true);
      await starting;
      expect(resolutions, 1);
      expect(runtime.snapshot.phase, RuntimePhase.ready);
      expect(File('${directory.path}/meshchan.sqlite').existsSync(), true);
      expect((await runtime.shutdown()).canExit, true);
      expect(runtime.openPortCount, 0);
    },
  );

  for (final duringGrant in [false, true]) {
    test(
      'startup quit releases the bootstrap barrier (grant pending: $duringGrant)',
      () async {
        final frame = Completer<void>();
        final granting = Completer<void>();
        final grant = Completer<bool>();
        var grants = 0, resolutions = 0;
        final bootstrap = HostResourceBootstrap(
          firstFrame: () => frame.future,
          authorize: () {
            grants++;
            granting.complete();
            return grant.future;
          },
        );
        final runtime = RuntimeController(
          prepareForResources: bootstrap.prepare,
          resolveDirectory: () async {
            resolutions++;
            throw StateError('Startup quit must not touch a directory');
          },
        );
        final starting = runtime.start();
        if (duringGrant) {
          frame.complete();
          await granting.future;
        }
        final closing = runtime
            .shutdown(); // Save stop before opening the barrier.
        bootstrap.stop();
        expect(bootstrap.stopped, true);
        final closed = await closing;
        await starting;
        expect(closed.canExit, true);
        expect(closed.workerWasSpawned, false);
        expect(closed.workerExited, false);
        expect(runtime.snapshot.phase, RuntimePhase.closed);
        expect(runtime.snapshot.owner, OwnerFact.none);
        expect(runtime.openPortCount, 0);
        expect(runtime.pendingCount, 0);
        expect(resolutions, 0);
        if (duringGrant) {
          grant.complete(true); // Late grant cannot authorize a new owner.
          await grant.future;
        } else {
          frame.complete();
          await frame.future;
        }
        expect(grants, duringGrant ? 1 : 0);
        expect(resolutions, 0);
      },
    );
  }

  test(
    'denied native bootstrap fails resource-free without a directory fallback',
    () async {
      var resolutions = 0;
      final bootstrap = HostResourceBootstrap(
        firstFrame: () async {},
        authorize: () async => false,
      );
      final runtime = RuntimeController(
        prepareForResources: bootstrap.prepare,
        resolveDirectory: () async {
          resolutions++;
          throw StateError('Denied bootstrap must not resolve a directory');
        },
      );
      await runtime.start();
      expect(resolutions, 0);
      expect(runtime.snapshot.phase, RuntimePhase.fault);
      expect(runtime.snapshot.owner, OwnerFact.none);
      final closed = await runtime.shutdown();
      expect(closed.canExit, true);
      expect(closed.workerWasSpawned, false);
      expect(runtime.openPortCount, 0);
    },
  );

  test(
    'stop before prepare never requests a frame or native permission',
    () async {
      final bootstrap = HostResourceBootstrap(
        firstFrame: () => throw StateError('Stopped before first frame'),
        authorize: () => throw StateError('No resource permission after stop'),
      );
      bootstrap.stop();
      final preparing = bootstrap.prepare();
      expect(identical(preparing, bootstrap.prepare()), true);
      await preparing;
    },
  );
}
