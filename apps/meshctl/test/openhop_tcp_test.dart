import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/src/cli_output.dart';
import 'package:meshctl/src/session_command.dart';
import 'package:test/test.dart';

import '../tool/support/openhop_frame_transport.dart';
import '../tool/support/openhop_peer_runner.dart';

const _freshA = 1251977030, _freshB = 2195432628;

MeshchanDiagnosticMessage _ping({required bool oldLabels, required int id}) =>
    MeshchanDiagnosticMessage(
      kind: DiagnosticKind.ping,
      runNonce: Uint8List.fromList(List.generate(16, (i) => i + 1)),
      requestId: id,
      senderTestId: oldLabels ? 3507552257 : _freshA,
      targetTestId: oldLabels ? 3507552258 : _freshB,
      content: Uint8List.fromList(utf8.encode('Meshchan D11 beta1')),
    );

Uint8List _entry(MeshchanDiagnosticMessage message) {
  final payload = encodeDiagnosticPayload(message);
  return Uint8List.fromList([
    0x1b,
    0,
    0,
    0,
    3,
    0,
    0xff,
    0xff,
    payload.length,
    ...payload,
  ]);
}

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

  for (final acknowledge in [true, false]) {
    test(
      acknowledge
          ? 'TCP responder ignores old labels and waits for a delayed split OK at response limit'
          : 'TCP responder preserves send failure when OK is absent at response limit',
      () async {
        // Local TCP integration only: no credentials, radio, or shared inbox.
        final config = OpenHopPeerConfig({
          'baseUrl': 'http://127.0.0.1/',
          'tcpPort': server.port,
          'companionName': 'fixture',
          'endpointLabel': 'loopback',
          'jwt': {'env': 'NOT_READ'},
          'idleWindowLowerBoundSeconds': 95,
          'session': {
            'commandSeconds': 15,
            'initializationSeconds': 30,
            'startupDelayMilliseconds': 0,
            'taskSeconds': 90,
          },
          'datagramArguments': [
            '--send-channel=3',
            '--receive-channel=3',
            '--route-descriptor=0',
            '--path-hex=',
            '--local-id=$_freshB',
            '--peer-id=$_freshA',
            '--max-entries=512',
            '--duration=60',
            '--max-responses=1',
          ],
        }, 'respond');
        final out = StringBuffer(), err = StringBuffer();
        final running = runOpenHopPeer(
          config,
          output: CliOutput(out, err),
          createTransport: () => config.createTransport('unused'),
        );
        final remote = await peer.future;
        final closed = Completer<void>(), pongWritten = Completer<void>();
        final bytes = <int>[], commands = <Uint8List>[];
        var reads = 0;
        void reply(List<int> content) =>
            remote.add([0x3e, content.length, 0, ...content]);
        final input = remote.listen((chunk) {
          bytes.addAll(chunk);
          while (bytes.length >= 3) {
            expect(bytes[0], 0x3c);
            final length = bytes[1] | bytes[2] << 8;
            if (bytes.length < 3 + length) break;
            final command = Uint8List.fromList(bytes.sublist(3, 3 + length));
            bytes.removeRange(0, 3 + length);
            commands.add(command);
            switch (command[0]) {
              case 0x16:
                reply([0x0d, 14, 25, 8, ...List.filled(76, 0), 1, 254]);
              case 1:
                reply([5, 0, 0, 22, ...List.filled(54, 0)]);
              case 0x0a:
                reads++;
                expect(reads, lessThanOrEqualTo(62));
                reply(_entry(_ping(oldLabels: reads < 62, id: reads)));
              case 0x3e:
                final request = _ping(oldLabels: false, id: 62);
                final pong = MeshchanDiagnosticMessage(
                  kind: DiagnosticKind.pong,
                  runNonce: request.runNonce,
                  requestId: request.requestId,
                  senderTestId: _freshB,
                  targetTestId: _freshA,
                  content: request.content,
                );
                expect(
                  command,
                  encodeSendChannelData(
                    channelIndex: 3,
                    dataType: diagnosticDataType,
                    routeDescriptor: 0,
                    path: Uint8List(0),
                    payload: encodeDiagnosticPayload(pong),
                  ),
                );
                pongWritten.complete();
              default:
                fail('Unexpected Companion command.');
            }
          }
        }, onDone: closed.complete);
        addTearDown(input.cancel);
        await pongWritten.future;
        if (acknowledge) {
          // A header alone is not an OK. Response-limit settlement must keep
          // the receive pipe open until the final content byte arrives.
          remote.add([0x3e, 1, 0]);
          await remote.flush();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(closed.isCompleted, isFalse);
          expect(out.toString(), isNot(contains('"event":"end"')));
          remote.add([0]);
          await remote.flush();
        }
        expect(await running, acknowledge ? 0 : 69);
        await closed.future;
        expect(err.toString(), isEmpty);
        final records = out
            .toString()
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map)
            .toList();
        final end = records.last;
        final result = end['result'] as Map;
        expect(end['cleanup']['state'], 'succeeded');
        expect(result['reason'], acknowledge ? 'completed' : 'sendFailed');
        expect(result['stage'], 'settling');
        expect(result['listenStopReason'], 'responseLimit');
        expect(result['responseAttempts'], 1);
        expect(result['localResponsesConfirmed'], acknowledge ? 1 : 0);
        expect(result['publishedEntries'], 62);
        expect(result['processedEntries'], 62);
        expect(result['reception']['dispatchedReads'], 62);
        expect(result['reception']['completedReads'], 62);
        expect(result['lastSend']['attempted'], isTrue);
        expect(result['lastSend']['dispatched'], isTrue);
        expect(result['lastSend']['localWriteCompleted'], isTrue);
        expect(result['lastSend']['localOkObserved'], acknowledge);
        expect(result['lastSend']['deviceAcceptanceConfirmed'], acknowledge);
        expect(result['lastSend']['pendingAtTermination'], isFalse);
        if (!acknowledge) {
          expect(end['reason'], 'task_failure');
          expect(end['failure']['session']['kind'], 'requestTimeout');
          expect(end['failure']['session']['commandOpcode'], 0x3e);
          expect(end['failure']['session']['expectedResponseOpcode'], 0);
        }
        expect(commands.map((command) => command[0]), [
          0x16,
          1,
          ...List.filled(62, 0x0a),
          0x3e,
        ]);
        expect(
          records.where((r) => r['event'] == 'peer_receive_read_written'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'TCP send preserves table-full rejection without retry or false acceptance',
    () async {
      // A busy upstream can refuse before queuing RF using existing ERR 3.
      // This proves client compatibility with that refusal, not its cause.
      final config = OpenHopPeerConfig({
        'baseUrl': 'http://127.0.0.1/',
        'tcpPort': server.port,
        'companionName': 'fixture',
        'endpointLabel': 'loopback',
        'jwt': {'env': 'NOT_READ'},
        'idleWindowLowerBoundSeconds': 95,
        'session': {
          'commandSeconds': 15,
          'initializationSeconds': 30,
          'startupDelayMilliseconds': 0,
          'taskSeconds': 90,
        },
        'datagramArguments': [
          '--send-channel=3',
          '--route-descriptor=0',
          '--path-hex=',
          '--data-type=65535',
          '--payload-hex=4f484f4b',
        ],
      }, 'send');
      final out = StringBuffer();
      final running = runOpenHopPeer(
        config,
        output: CliOutput(out, StringBuffer()),
        createTransport: () => config.createTransport('unused'),
      );
      final remote = await peer.future;
      final closed = Completer<void>();
      final pending = <int>[], opcodes = <int>[];
      final input = remote.listen((chunk) {
        pending.addAll(chunk);
        while (pending.length >= 3) {
          expect(pending[0], 0x3c);
          final length = pending[1] | pending[2] << 8;
          if (pending.length < length + 3) break;
          final opcode = pending[3];
          pending.removeRange(0, length + 3);
          opcodes.add(opcode);
          final response = switch (opcode) {
            0x16 => [0x0d, 14, 25, 8, ...List.filled(76, 0), 1, 254],
            1 => [5, 0, 0, 22, ...List.filled(54, 0)],
            0x3e => [1, 3],
            _ => throw StateError('Unexpected Companion command.'),
          };
          remote.add([0x3e, response.length, 0, ...response]);
        }
      }, onDone: closed.complete);
      addTearDown(input.cancel);
      expect(await running, 69);
      await closed.future;
      final end = jsonDecode(out.toString().trim().split('\n').last) as Map;
      expect(end['reason'], 'session_failure');
      expect(end['failure']['session']['kind'], 'deviceRejected');
      expect(end['failure']['session']['commandOpcode'], 0x3e);
      expect(end['failure']['session']['deviceErrorCode'], 3);
      expect(end['result']['send']['attempted'], isTrue);
      expect(end['result']['send']['localOkObserved'], isFalse);
      expect(end['result']['send']['deviceAcceptanceConfirmed'], isFalse);
      expect(end['cleanup']['state'], 'succeeded');
      expect(opcodes, [0x16, 1, 0x3e]);
    },
  );

  for (final outcome in ['pong', 'noPong', 'error', 'cancel']) {
    test('TCP delayed confirmation preserves $outcome and one send', () async {
      final config = OpenHopPeerConfig({
        'baseUrl': 'http://127.0.0.1/',
        'tcpPort': server.port,
        'companionName': 'fixture',
        'endpointLabel': 'loopback',
        'jwt': {'env': 'NOT_READ'},
        'idleWindowLowerBoundSeconds': 5,
        'session': {
          'commandSeconds': 1,
          'sendConfirmationSeconds': 3,
          'initializationSeconds': 2,
          'startupDelayMilliseconds': 0,
          'taskSeconds': 5,
        },
        'datagramArguments': [
          '--send-channel=3',
          '--receive-channel=3',
          '--route-descriptor=0',
          '--path-hex=',
          '--local-id=$_freshB',
          '--peer-id=$_freshA',
          '--max-entries=4',
          '--response-timeout=1',
          '--content-hex=0011133c3e80ff',
        ],
      }, 'ping');
      final out = StringBuffer();
      final stops = StreamController<CliStopRequest>();
      addTearDown(stops.close);
      final running = runOpenHopPeer(
        config,
        output: CliOutput(out, StringBuffer()),
        createTransport: () => config.createTransport('unused'),
        stopRequests: stops.stream,
      );
      final remote = await peer.future;
      final closed = Completer<void>();
      final bytes = <int>[], commands = <int>[];
      final timers = <Timer>[];
      addTearDown(() {
        for (final timer in timers) {
          timer.cancel();
        }
      });
      Uint8List? pong;
      void reply(List<int> content) =>
          remote.add([0x3e, content.length, 0, ...content]);
      final input = remote.listen((chunk) {
        bytes.addAll(chunk);
        while (bytes.length >= 3) {
          final length = bytes[1] | bytes[2] << 8;
          if (bytes.length < length + 3) break;
          final content = Uint8List.fromList(bytes.sublist(3, length + 3));
          bytes.removeRange(0, length + 3);
          commands.add(content[0]);
          switch (content[0]) {
            case 0x16:
              reply([0x0d, 14, 25, 8, ...List.filled(76, 0), 1, 254]);
            case 1:
              reply([5, 0, 0, 22, ...List.filled(54, 0)]);
            case 0x0a:
              reply(pong ?? [0x0a]);
              pong = null;
            case 0x3e:
              final ping = decodeDiagnosticPayload(
                Uint8List.sublistView(content, 5),
              ).message!;
              pong = _entry(
                MeshchanDiagnosticMessage(
                  kind: DiagnosticKind.pong,
                  runNonce: ping.runNonce,
                  requestId: ping.requestId,
                  senderTestId: ping.targetTestId,
                  targetTestId: ping.senderTestId,
                  content: ping.content,
                ),
              );
              // Cross both the original command and remote-response budgets.
              timers.add(
                Timer(const Duration(milliseconds: 1200), () {
                  if (outcome == 'cancel') {
                    stops.add(CliStopRequest.sigint);
                  } else if (outcome == 'error') {
                    reply([1, 3]);
                  } else {
                    remote.add([0x3e, 1]);
                    timers.add(
                      Timer(const Duration(milliseconds: 10), () {
                        remote.add([
                          0,
                          0,
                        ]); // Complete the one delayed OK frame.
                        if (outcome == 'pong') reply([0x83]);
                      }),
                    );
                  }
                }),
              );
          }
        }
      }, onDone: closed.complete);
      addTearDown(input.cancel);
      final code = await running;
      await closed.future;
      final records = out
          .toString()
          .trim()
          .split('\n')
          .map((line) => jsonDecode(line) as Map)
          .toList();
      final end = records.last;
      final result = end['result'] as Map;
      final policy = records.singleWhere(
        (record) => record['event'] == 'peer_timing_policy',
      );
      expect(policy['commandSeconds'], 1);
      expect(policy['sendConfirmationSeconds'], 3);
      expect(policy['pingResponseTimeoutOrigin'], 'localAcceptance');
      expect(end['cleanup']['state'], 'succeeded');
      expect(commands.where((opcode) => opcode == 0x3e), hasLength(1));
      expect(
        commands.where((opcode) => opcode == 0x0a),
        hasLength(outcome == 'pong' ? 2 : 1),
      );
      expect(result['roundTripSucceeded'], outcome == 'pong');
      expect(
        result['send']['deviceAcceptanceConfirmed'],
        outcome == 'pong' || outcome == 'noPong',
      );
      if (outcome == 'pong') {
        expect(code, 0);
        expect(result['exactContentValidated'], isTrue);
        expect(result['applicationRttUs'], greaterThanOrEqualTo(1200000));
      } else if (outcome == 'noPong') {
        expect(code, 69);
        expect(result['reason'], 'responseTimeout');
        expect(result['stage'], 'waiting');
      } else if (outcome == 'error') {
        expect(code, 69);
        expect(end['failure']['session']['kind'], 'deviceRejected');
      } else {
        expect(code, 130);
        expect(result['reason'], 'canceled');
        expect(result['stage'], 'sending');
        expect(result['send']['pendingAtTermination'], isTrue);
      }
    });
  }

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
