import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshcore_link/meshcore_link.dart';

import '../tool/device_fixture.dart';

void main() {
  for (final stopBeforeCreate in [true, false]) {
    test(
      'authoritative raw gate and stop checkpoint: early=$stopBeforeCreate',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'meshchan-device-dispatch-',
        );
        final port = ReceivePort();
        final events = <WorkerEvent>[];
        var factories = 0, enumerationFails = true;
        final dispatcher = WorkerDispatcher(
          WorkerBootstrap(1, directory.path, port.sendPort),
          send: events.add,
          finish: () {},
          enumeratePorts: () {
            if (enumerationFails) {
              throw const SerialPortFailure('private cause');
            }
            return const [];
          },
          createCheckTransport: (_) {
            factories++;
            return DeviceFixtureTransport();
          },
        );
        dispatcher.start();
        Future<void> until(bool Function() predicate) async {
          while (!predicate()) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        await until(() => dispatcher.snapshot.phase == RuntimePhase.ready);
        var id = 0;
        void send(RuntimeRequest request) =>
            dispatcher.receive(RequestEnvelope(1, ++id, request));
        send(const RefreshDevicePorts(1));
        expect(
          (events.whereType<RequestReply>().last.value as DevicePortsValue)
              .failure!
              .kind,
          'enumerationFailed',
        );
        expect(dispatcher.gate.state, DeviceGateState.free);
        expect(dispatcher.snapshot.phase, RuntimePhase.ready);
        enumerationFails = false;
        send(const RefreshDevicePorts(2));
        expect(
          (events.whereType<RequestReply>().last.value as DevicePortsValue)
              .ports,
          isEmpty,
        );
        send(const StartDeviceCheck(1, '  ', DeviceCheckOptions()));
        expect(factories, 0);
        send(const StartDeviceCheck(1, ' A ', DeviceCheckOptions()));
        send(const StartDeviceCheck(2, 'B', DeviceCheckOptions()));
        expect(
          events.whereType<RequestReply>().last.error!.host,
          CoordinationFault.deviceBusy,
        );
        expect(dispatcher.gate.state, DeviceGateState.occupied);
        send(const RefreshDevicePorts(3));
        expect(
          events.whereType<RequestReply>().last.error!.host,
          CoordinationFault.deviceBusy,
        );
        if (stopBeforeCreate) send(const StopRuntime());
        await until(
          () =>
              dispatcher.snapshot.deviceCheck?.settled == true &&
              dispatcher.gate.state == DeviceGateState.free,
        );
        expect(factories, stopBeforeCreate ? 0 : 1);
        if (stopBeforeCreate) {
          send(const ResumeAdmission());
          expect(events.whereType<RequestReply>().last.error, isNotNull);
        }
        send(const ShutdownRuntime());
        await until(() => events.whereType<ReleaseReport>().isNotEmpty);
        expect(
          events.whereType<ReleaseReport>().single.resourcesReleased,
          true,
        );
        port.close();
        directory.deleteSync(recursive: true);
      },
    );
  }
  test('old lease cannot free or quarantine a newer lease', () {
    final gate = DeviceGate();
    final old = gate.acquire();
    gate.settle(old, released: true);
    final next = gate.acquire();
    gate.settle(old, released: true);
    gate.settle(old, released: false);
    expect(gate.state, DeviceGateState.occupied);
    gate.settle(next, released: false);
    expect(gate.state, DeviceGateState.quarantined);
    expect(gate.acquire, throwsA(isA<RuntimeFault>()));
  });
}
