import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';

/// Owned test boundary only. Never used by product launch configuration.
class DeviceFixtureTransport implements CompanionTransport {
  DeviceFixtureTransport({
    this.openBarrier,
    this.closeBarrier,
    this.respondThrough = 2,
    this.failClose = false,
  });
  final Completer<void>? openBarrier, closeBarrier;
  final int respondThrough;
  final bool failClose;
  final received = StreamController<Uint8List>();
  final sent = <Uint8List>[];
  final opened = Completer<void>(), closing = Completer<void>();
  int opens = 0, closes = 0;
  @override
  Stream<Uint8List> get frames => received.stream;
  @override
  Future<void> open() async {
    opens++;
    opened.complete();
    await openBarrier?.future;
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    sent.add(Uint8List.fromList(content));
    received.add(Uint8List.fromList([0x83])); // Must not trigger an inbox read.
    if (sent.length <= respondThrough) {
      received.add(
        content[0] == 0x16 ? fixtureDeviceInfo() : fixtureSelfInfo(),
      );
    }
  }

  @override
  Future<void> close() async {
    closes++;
    if (!closing.isCompleted) closing.complete();
    await openBarrier?.future;
    await closeBarrier?.future;
    unawaited(received.close());
    if (failClose) {
      throw StateError('private native cause must not cross bridge');
    }
  }
}

Uint8List fixtureDeviceInfo() {
  final bytes = Uint8List(82)..setRange(0, 4, [0x0d, 14, 25, 8]);
  bytes.setRange(20, 25, utf8.encode('Model'));
  bytes.setRange(60, 64, utf8.encode('Test'));
  bytes[80] = 0;
  bytes[81] = 99;
  return bytes;
}

Uint8List fixtureSelfInfo() => Uint8List.fromList([
  0x05,
  1,
  0xfc,
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
  ...utf8.encode('Fixture node'),
]);

enum DeviceFixtureControl { release, releaseProfileAck }

final class DeviceFixtureFact {
  const DeviceFixtureFact(this.name);
  final String name;
}

final class DeviceFixtureReady {
  const DeviceFixtureReady(this.commands);
  final SendPort commands;
}

void Function(WorkerBootstrap) deviceFixtureEntry(
  SendPort observer, {
  bool failClose = false,
  bool delayAck = false,
  bool holdProfileCreate = false,
}) => (bootstrap) {
  final commands = ReceivePort();
  final release = Completer<void>();
  final heldReplies = <RequestReply>[];
  RequestReply? profileReply;
  bool profileHeld = false;
  final dispatcher = WorkerDispatcher(
    bootstrap,
    send: (event) {
      if (holdProfileCreate &&
          !profileHeld &&
          event is RequestReply &&
          event.value is ProfileValue) {
        profileHeld = true;
        profileReply = event;
        observer.send(const DeviceFixtureFact('profileCommitted'));
      } else if (delayAck &&
          event is RequestReply &&
          event.value is Accepted &&
          heldReplies.isEmpty) {
        heldReplies.add(event);
      } else {
        bootstrap.events.send(event);
      }
    },
    finish: commands.close,
    enumeratePorts: () => const [
      SerialPortDescription(path: ' fixture A ', transport: 'USB'),
      SerialPortDescription(path: 'fixture B', warning: 'Metadata unavailable'),
    ],
    createCheckTransport: (_) =>
        DeviceFixtureTransport(closeBarrier: release, failClose: failClose),
  );
  commands.listen((message) {
    if (message == DeviceFixtureControl.releaseProfileAck) {
      if (profileReply != null) {
        bootstrap.events.send(profileReply!);
      }
      profileReply = null;
    } else if (message == DeviceFixtureControl.release) {
      if (!release.isCompleted) release.complete();
      for (final reply in heldReplies) {
        bootstrap.events.send(reply);
      }
    } else {
      dispatcher.receive(message);
    }
  });
  observer.send(DeviceFixtureReady(commands.sendPort));
  bootstrap.events.send(WorkerHello(bootstrap.generation, commands.sendPort));
  dispatcher.start();
};
