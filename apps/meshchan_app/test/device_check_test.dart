import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/device_check.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshcore_link/meshcore_link.dart';

import '../tool/device_fixture.dart';

Future<void> turn() => Future<void>.delayed(Duration.zero);
void main() {
  test('fresh real sessions publish info before actual close; only initialization pair', () async {
    const portPath = ' exact\tpath ';
    for (var n = 1; n <= 2; n++) {
      final release = Completer<void>();
      final transport = DeviceFixtureTransport(closeBarrier: release);
      final seen = <DeviceCheckSnapshot>[];
      final check = FiniteDeviceCheck(
        n,
        UsbSerialTarget(portPath: portPath),
        const DeviceCheckOptions(),
        createTransport: (target) {
          expect(target, isA<UsbSerialTarget>());
          expect(target.kind, CompanionTransportKind.usbSerial);
          expect((target as UsbSerialTarget).portPath, portPath);
          return transport;
        },
        publish: seen.add,
      );
      final work = check.run();
      await transport.closing.future;
      expect(check.snapshot.info, isNotNull);
      final info = check.snapshot.info!;
      expect(info.port, portPath);
      expect(check.snapshot.port, portPath);
      expect(info.observedAt.isUtc, true);
      expect(info.protocolVersion, 14);
      expect(info.appTargetVersion, 3);
      expect(info.txPowerDbm, -4);
      expect(info.radioFrequencyKhz, 869525);
      expect(info.radioBandwidthHz, 250000);
      expect(info.repeatEnabled, false);
      expect(info.pathHashMode, 99);
      expect(check.snapshot.sessionCleanup, DeviceCleanup.pending);
      expect(check.snapshot.released, false);
      expect(transport.sent[0], [0x16, 3]);
      expect(transport.sent[1], encodeAppStart());
      expect(transport.sent.length, 2);
      expect(seen.any((s) => s.state == MeshCoreSessionState.opening), true);
      check.cancel();
      check.cancel();
      release.complete();
      await work;
      expect(transport.closes, 1);
      expect(check.snapshot.released, true);
      expect(check.snapshot.info, same(info));
    }
  });
  for (final stage in [
    'before construction',
    'open',
    'startup',
    'device response',
    'self response',
  ]) {
    test('scoped cancel during $stage uses one real close', () async {
      final opening = stage == 'open' ? Completer<void>() : null;
      final transport = DeviceFixtureTransport(
        openBarrier: opening,
        respondThrough: stage == 'self response' ? 1 : 0,
      );
      var constructed = 0;
      final check = FiniteDeviceCheck(
        1,
        UsbSerialTarget(portPath: 'A'),
        DeviceCheckOptions(startupMilliseconds: stage == 'startup' ? 5000 : 0),
        createTransport: (_) {
          constructed++;
          return transport;
        },
        publish: (_) {},
      );
      final work = check.run();
      if (stage != 'before construction') {
        await transport.opened.future;
        await turn();
      }
      check.cancel();
      check.cancel();
      opening?.complete();
      await work;
      expect(constructed, stage == 'before construction' ? 0 : 1);
      expect(transport.closes, stage == 'before construction' ? 0 : 1);
      expect(check.snapshot.cancelApplied, true);
      expect(check.snapshot.released, true);
      if (stage != 'before construction') {
        expect(check.snapshot.failure!.kind, 'canceled');
      }
    });
  }
  test(
    'primary protocol failure remains after close success and later cancel',
    () async {
      final release = Completer<void>();
      final t = DeviceFixtureTransport(
        respondThrough: 0,
        closeBarrier: release,
      );
      final check = FiniteDeviceCheck(
        1,
        UsbSerialTarget(portPath: 'A'),
        const DeviceCheckOptions(),
        createTransport: (_) => t,
        publish: (_) {},
      );
      final work = check.run();
      await t.opened.future;
      await turn();
      t.received.add(fixtureSelfInfo().sublist(0, 2));
      await t.closing.future;
      await turn();
      check.cancel();
      release.complete();
      await work;
      expect(check.snapshot.failure!.kind, 'protocol');
      expect(check.snapshot.released, true);
    },
  );
  test('successful information survives close failure', () async {
    final check = FiniteDeviceCheck(
      1,
      UsbSerialTarget(portPath: 'A'),
      const DeviceCheckOptions(),
      createTransport: (_) => DeviceFixtureTransport(failClose: true),
      publish: (_) {},
    );
    await check.run();
    expect(check.snapshot.info, isNotNull);
    expect(check.snapshot.failure, null);
    expect(check.snapshot.cleanupFailure!.kind, 'cleanup');
    expect(check.snapshot.sessionCleanup, DeviceCleanup.failed);
    expect(check.snapshot.released, false);
  });
  test('factory failure leaves both cleanup scopes not required', () async {
    final check = FiniteDeviceCheck(
      1,
      UsbSerialTarget(portPath: 'A'),
      const DeviceCheckOptions(),
      createTransport: (_) => throw StateError('private construction failure'),
      publish: (_) {},
    );
    await check.run();
    expect(check.snapshot.failure?.kind, 'observationFailed');
    expect(check.snapshot.sessionCleanup, DeviceCleanup.notRequired);
    expect(check.snapshot.observerCleanup, DeviceCleanup.notRequired);
    expect(check.snapshot.released, true);
  });
  test('session constructor failure safely closes transport not yet owned by session', () async {
    final release = Completer<void>();
    final t = DeviceFixtureTransport(closeBarrier: release);
    final check = FiniteDeviceCheck(
      1,
      UsbSerialTarget(portPath: 'A'),
      const DeviceCheckOptions(),
      createTransport: (_) => t,
      createSession: (_, _) => throw StateError('construct'),
      publish: (_) {},
    );
    final work = check.run();
    await t.closing.future;
    expect(check.snapshot.sessionCleanup, DeviceCleanup.pending);
    expect(check.snapshot.settled, false);
    release.complete();
    await work;
    expect(t.opens, 0);
    expect(t.closes, 1);
    expect(check.snapshot.released, true);
  });
  test(
    'native success and host observer cleanup failure remain separate',
    () async {
      final observerEntered = Completer<void>(), release = Completer<void>();
      final check = FiniteDeviceCheck(
        1,
        UsbSerialTarget(portPath: 'A'),
        const DeviceCheckOptions(),
        createTransport: (_) => DeviceFixtureTransport(),
        cancelObserver: (s) async {
          await s.cancel();
          observerEntered.complete();
          await release.future;
          throw StateError('observer');
        },
        publish: (_) {},
      );
      final work = check.run();
      await observerEntered.future;
      expect(check.snapshot.sessionCleanup, DeviceCleanup.succeeded);
      expect(check.snapshot.observerCleanup, DeviceCleanup.pending);
      expect(check.snapshot.settled, false);
      release.complete();
      await work;
      expect(check.snapshot.sessionCleanup, DeviceCleanup.succeeded);
      expect(check.snapshot.observerCleanup, DeviceCleanup.failed);
      expect(check.snapshot.released, false);
    },
  );
  for (final requestTimeout in [true, false]) {
    test(
      'real session ${requestTimeout ? 'request' : 'initialization'} timeout never retries',
      () async {
        final t = DeviceFixtureTransport(respondThrough: 0);
        final check = FiniteDeviceCheck(
          1,
          UsbSerialTarget(portPath: 'A'),
          DeviceCheckOptions(
            requestSeconds: requestTimeout ? 1 : 5,
            initializationSeconds: requestTimeout ? 5 : 1,
          ),
          createTransport: (_) => t,
          publish: (_) {},
        );
        await check.run();
        expect(
          check.snapshot.failure!.kind,
          requestTimeout ? 'requestTimeout' : 'initializationTimeout',
        );
        expect(t.sent.length, 1);
        expect(t.closes, 1);
        expect(check.snapshot.released, true);
      },
    );
  }
}
