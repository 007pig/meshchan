import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import 'fake_companion_transport.dart';

/// Observe immediately so an error is never detached from its owning test zone.
final class Outcome<T> {
  Outcome(Future<T> future) {
    future.then<void>(
      (result) {
        value = result;
        completionCount++;
        done = true;
      },
      onError: (Object failure, StackTrace _) {
        error = failure;
        completionCount++;
        done = true;
      },
    );
  }

  T? value;
  Object? error;
  bool done = false;
  int completionCount = 0;
}

// Minimal synthetic content, independent of codec test fixtures or live captures.
Uint8List deviceInfo({String model = 'private-model'}) {
  final content = Uint8List(82)
    ..setRange(0, 8, [0x0d, 14, 25, 8, 0x78, 0x56, 0x34, 0x12]);
  final modelBytes = utf8.encode(model);
  final firmware = utf8.encode('private-firmware');
  content.setRange(20, 20 + modelBytes.length, modelBytes);
  content.setRange(60, 60 + firmware.length, firmware);
  return content;
}

Uint8List selfInfo({String name = 'private-node'}) => Uint8List.fromList([
  0x05,
  1,
  20,
  22,
  ...List.filled(32, 0xab),
  ...List.filled(12, 0),
  0x95,
  0x44,
  0x0d,
  0,
  0x90,
  0xd0,
  3,
  0,
  11,
  7,
  ...utf8.encode(name),
]);

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
