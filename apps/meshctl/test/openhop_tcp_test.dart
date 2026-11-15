import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../tool/support/openhop_frame_transport.dart';
import '../tool/support/openhop_peer_runner.dart';

void main() {
  late ServerSocket server;
  late StreamSubscription<Socket> accept;
  late Completer<Socket> peer;
  late List<Socket> owned;
  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    peer = Completer<Socket>();
    owned = [];
    accept = server.listen((socket) {
      owned.add(socket);
      peer.complete(socket);
    });
  });
  tearDown(() async {
    for (final socket in owned) {
      socket.destroy();
    }
    await accept.cancel();
    await server.close();
  });
  OpenHopTcpTransport transport({OpenHopTcpConnector? connector}) =>
      OpenHopTcpTransport(
        host: '127.0.0.1',
        port: server.port,
        connectTimeout: const Duration(seconds: 2),
        connector: connector,
      );

  test(
    'TCP uses the serial codec once, with split and coalesced input',
    () async {
      final pipe = transport();
      final received = <List<int>>[];
      final two = Completer<void>();
      final subscription = pipe.frames.listen((frame) {
        received.add(frame);
        if (received.length == 2) two.complete();
      });
      await pipe.open();
      final remote = await peer.future;
      final bytes = Completer<List<int>>();
      final input = <int>[];
      final remoteInput = remote.listen((chunk) {
        input.addAll(chunk);
        if (input.length >= 5 && !bytes.isCompleted) {
          bytes.complete(input.toList());
        }
      });
      await pipe.sendFrame(Uint8List.fromList([22, 3]));
      expect(await bytes.future, [0x3c, 2, 0, 22, 3]);
      remote.add([0x3e, 2]);
      await remote.flush();
      remote.add([0, 13, 14, 0x3e, 1, 0, 5]);
      await remote.flush();
      await two.future;
      expect(received, [
        [13, 14],
        [5],
      ]);
      await pipe.close();
      await pipe.close();
      await subscription.cancel();
      await remoteInput.cancel();
    },
  );

  test('close owns a late connection and does not reconnect', () async {
    final gate = Completer<void>();
    var attempts = 0;
    final pipe = transport(
      connector: (host, port, timeout) async {
        attempts++;
        await gate.future;
        return Socket.connect(host, port, timeout: timeout);
      },
    );
    final subscription = pipe.frames.listen((_) {});
    final opening = expectLater(
      pipe.open(),
      throwsA(isA<OpenHopTransportFailure>()),
    );
    var closed = false;
    final closing = pipe.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await opening;
    await closing;
    expect(attempts, 1);
    await expectLater(pipe.open(), throwsA(isA<OpenHopTransportFailure>()));
    await subscription.cancel();
  });

  test('paused public consumer cannot hold native cleanup', () async {
    final pipe = transport();
    final subscription = pipe.frames.listen((_) {});
    await pipe.open();
    subscription.pause();
    await pipe.close();
    subscription.resume();
    await subscription.cancel();
  });

  test('remote close is a controlled failure with no reconnect', () async {
    final pipe = transport();
    final error = Completer<Object>();
    final subscription = pipe.frames.listen((_) {}, onError: error.complete);
    await pipe.open();
    (await peer.future).destroy();
    expect(await error.future, isA<OpenHopTransportFailure>());
    await pipe.close();
    await subscription.cancel();
  });

  test('TCP mode requires an explicit valid port; WS remains the default', () {
    final config = <String, dynamic>{
      'baseUrl': 'http://127.0.0.1:8000/',
      'companionName': 'fixture',
      'endpointLabel': 'fixture',
      'jwt': {'env': 'NOT_READ'},
      'session': {
        'commandSeconds': 5,
        'initializationSeconds': 15,
        'startupDelayMilliseconds': 0,
        'taskSeconds': 90,
      },
    };
    expect(OpenHopPeerConfig(config, 'info').tcpPort, isNull);
    expect(
      OpenHopPeerConfig({
        ...config,
        'tcpPort': 5050,
      }, 'info').createTransport('unused'),
      isA<OpenHopTcpTransport>(),
    );
    for (final invalid in [0, 65536, '5050', true]) {
      expect(
        () => OpenHopPeerConfig({...config, 'tcpPort': invalid}, 'info'),
        throwsFormatException,
      );
    }
  });
}
