import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/src/cli_output.dart';
import 'package:meshctl/src/session_command.dart';
import 'package:test/test.dart';

import '../tool/support/openhop_frame_transport.dart';
import '../tool/support/openhop_idle_probe.dart';
import '../tool/support/openhop_peer_runner.dart';

const _jwt = 'test.header.signature';

// Models the SDK distinction: sink close can finish before receive EOF.
final class _ClosingWebSocket extends Stream<dynamic> implements WebSocket {
  final input = StreamController<dynamic>();
  final closeRequested = Completer<void>();
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<void> get done => Future.value();
  @override
  Future<void> close([int? code, String? reason]) async {
    if (!closeRequested.isCompleted) closeRequested.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List _rx(List<int> content) =>
    Uint8List.fromList([0x3e, content.length, 0, ...content]);
Uint8List _device() =>
    Uint8List.fromList([0x0d, 14, 25, 8, ...List.filled(76, 0), 1, 254]);
Uint8List _self() => Uint8List.fromList([5, 0, 0, 22, ...List.filled(54, 0)]);

// Commits the local command before failing in the same synchronous input turn.
final class _OkThenFailureTransport implements CompanionTransport {
  final controller = StreamController<Uint8List>(sync: true);
  final sent = <int>[];
  Future<void>? closing;
  @override
  Stream<Uint8List> get frames => controller.stream;
  @override
  Future<void> open() async {}
  @override
  Future<void> close() => closing ??= Future<void>(() async {
    await controller.close();
  });
  @override
  Future<void> sendFrame(Uint8List content) async {
    sent.add(content.first);
    switch (content.first) {
      case 0x16:
        controller.add(_device());
      case 1:
        controller.add(_self());
      case 0x3e:
        Timer.run(() {
          controller.add(Uint8List.fromList([0]));
          controller.addError(
            const OpenHopTransportFailure('receive', 'syntheticFailure'),
          );
        });
    }
  }
}

Map<String, dynamic> _json(Uri base, String operation) => {
  'baseUrl': base.toString(),
  'companionName': 'registered peer / +',
  'endpointLabel': 'loopback',
  'jwt': {'env': 'TEST_UNUSED_JWT'},
  'idleTimeoutSeconds': 30,
  'session': {
    'commandSeconds': 2,
    'initializationSeconds': 3,
    'taskSeconds': 5,
    'startupDelayMilliseconds': 0,
  },
  if (operation != 'info')
    'datagramArguments': [
      if (operation != 'listen') ...[
        '--send-channel=3',
        '--route-descriptor=0',
        '--path-hex=',
      ],
      if (operation != 'send') ...['--receive-channel=2', '--max-entries=4'],
      if (operation == 'ping' || operation == 'respond') ...[
        '--local-id=1',
        '--peer-id=2',
      ],
      if (operation == 'ping') ...[
        '--response-timeout=1',
        '--content-hex=0011133C3E80FF',
      ],
      if (operation == 'send') ...[
        '--data-type=4660',
        '--payload-hex=0011133C3E80FF',
      ],
      if (operation == 'listen') '--data-type=4660',
      if (operation == 'listen' || operation == 'respond') '--duration=1',
      if (operation == 'respond') '--max-responses=1',
    ],
  if (operation == 'listen') 'expectedPayloadHex': '0011133C3E80FF',
};

final class _Server {
  _Server(this.server);
  final HttpServer server;
  final connected = Completer<WebSocket>();
  final released = Completer<void>();
  final messages = StreamController<List<int>>.broadcast();
  int requests = 0;
  Uri? requestUri;
  WebSocket? socket;
  StreamSubscription<dynamic>? input;
  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/');
  static Future<_Server> start({
    int? closeCode,
    List<int>? initial,
    bool redirect = false,
  }) async {
    final h = _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    h.server.listen((request) async {
      h.requests++;
      h.requestUri = request.uri;
      if (redirect) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '${h.url}redirected');
        await request.response.close();
        return;
      }
      final ws = h.socket = await WebSocketTransformer.upgrade(request);
      h.input = ws.listen(
        (dynamic m) => h.messages.add((m as List).cast<int>()),
        onDone: () {
          if (!h.released.isCompleted) h.released.complete();
        },
      );
      h.connected.complete(ws);
      if (initial != null) ws.add(initial);
      if (closeCode != null) {
        await ws.close(closeCode, 'private response $_jwt');
      }
    });
    return h;
  }

  Future<void> close() async {
    await socket?.close();
    await input?.cancel();
    await messages.close();
    await server.close(force: true);
  }

  OpenHopFrameTransport transport({OpenHopConnector? connector}) =>
      OpenHopFrameTransport(
        baseUrl: url,
        companionName: 'registered peer / +',
        jwt: _jwt,
        connectTimeout: const Duration(seconds: 2),
        connector: connector,
      );
}

void main() {
  test(
    'raw OK facts survive a recorded session failure without a successful exit',
    () async {
      final transport = _OkThenFailureTransport();
      final out = StringBuffer();
      final code = await runOpenHopPeer(
        OpenHopPeerConfig(
          _json(Uri.parse('http://127.0.0.1:1/'), 'send'),
          'send',
        ),
        output: CliOutput(out, StringBuffer()),
        createTransport: () => transport,
      );
      final end = jsonDecode(out.toString().trim().split('\n').last) as Map;
      expect(code, 69);
      expect(end['reason'], 'session_failure');
      expect(end['failure']['session']['kind'], 'transport');
      expect(end['failure']['session']['stage'], 'ready');
      expect(end['failure']['transport']['reason'], 'syntheticFailure');
      expect(end['result']['send']['localWriteCompleted'], isTrue);
      expect(end['result']['send']['localOkObserved'], isTrue);
      expect(end['result']['send']['deviceAcceptanceConfirmed'], isTrue);
      expect(end['cleanup']['state'], 'succeeded');
      expect(transport.sent, [0x16, 1, 0x3e]);
      expect(transport.controller.hasListener, isFalse);
    },
  );

  test(
    'closing an unopened WS transport does not wait for a frame listener',
    () async {
      var connects = 0;
      final transport = OpenHopFrameTransport(
        baseUrl: Uri.parse('http://127.0.0.1:1/'),
        companionName: 'synthetic',
        jwt: _jwt,
        connectTimeout: const Duration(seconds: 1),
        connector: (_, _) async {
          connects++;
          throw StateError('Must remain unopened.');
        },
      );
      final closing = transport.close();
      expect(identical(closing, transport.close()), isTrue);
      try {
        await closing.timeout(const Duration(seconds: 1));
        expect(connects, 0);
      } finally {
        // Also releases the old implementation when this regression fails.
        await transport.frames.drain<void>();
      }
    },
  );

  test(
    'paused frame delivery does not hold actual WS cleanup after receive EOF',
    () async {
      final socket = _ClosingWebSocket();
      final transport = OpenHopFrameTransport(
        baseUrl: Uri.parse('http://127.0.0.1:1/'),
        companionName: 'synthetic',
        jwt: _jwt,
        connectTimeout: const Duration(seconds: 1),
        connector: (_, _) async => socket,
      );
      final frames = transport.frames.listen((_) {});
      await transport.open();
      frames.pause();
      final closing = transport.close();
      var finished = false;
      closing.then((_) => finished = true);
      await socket.closeRequested.future;
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(socket.input.hasListener, isTrue);
      await socket.input.close();
      try {
        await closing.timeout(const Duration(seconds: 1));
        expect(frames.isPaused, isTrue);
        expect(socket.input.hasListener, isFalse);
      } finally {
        await frames.cancel();
      }
    },
  );

  test('observed passive window is distinct from exact timeout and must cover the task', () {
    final json = _json(Uri.parse('http://127.0.0.1:1/'), 'respond');
    json['idleTimeoutSeconds'] = null;
    json['idleWindowLowerBoundSeconds'] = 5;
    expect(() => OpenHopPeerConfig(json, 'respond'), returnsNormally);
    json['idleWindowLowerBoundSeconds'] = 4;
    expect(() => OpenHopPeerConfig(json, 'respond'), throwsFormatException);
    json['idleTimeoutSeconds'] = 30;
    expect(() => OpenHopPeerConfig(json, 'respond'), throwsFormatException);
  });
  test(
    'passive probe holds a real loopback WS session without hidden sends',
    () async {
      final h = await _Server.start();
      addTearDown(h.close);
      final opcodes = <int>[];
      final messages = h.messages.stream.listen((wire) {
        opcodes.add(wire[3]);
        if (wire[3] == 0x16) h.socket!.add(_rx(_device()));
        if (wire[3] == 1) h.socket!.add(_rx(_self()));
      });
      addTearDown(messages.cancel);
      final result = await runOpenHopIdleProbe(
        transport: h.transport(),
        duration: const Duration(milliseconds: 30),
        commandTimeout: const Duration(seconds: 1),
        initializationTimeout: const Duration(seconds: 2),
      );
      expect(result['status'], 'PASS');
      expect(opcodes, [0x16, 1]);
      expect(result['transportFailure'], isNull);
      expect(result['cleanup'], 'succeeded');
    },
  );
  test(
    'WS cleanup waits for receive EOF after the outgoing sink has closed',
    () async {
      final socket = _ClosingWebSocket();
      final transport = OpenHopFrameTransport(
        baseUrl: Uri.parse('http://127.0.0.1:1/'),
        companionName: 'synthetic',
        jwt: _jwt,
        connectTimeout: const Duration(seconds: 1),
        connector: (_, _) async => socket,
      );
      final frames = transport.frames.listen((_) {});
      await transport.open();
      var finished = false;
      final closing = transport.close().then((_) {
        finished = true;
      });
      await socket.closeRequested.future;
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(socket.input.hasListener, isTrue);
      await socket.input.close();
      await closing;
      await frames.cancel();
      expect(finished, isTrue);
      expect(socket.input.hasListener, isFalse);
    },
  );
  test(
    'REST preflight selects every GET and discards unexpected sensitive fields',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((r) async {
        paths.add(r.uri.path);
        expect(r.method, 'GET');
        expect(r.uri.queryParameters['companion_name'], 'registered peer / +');
        expect(r.headers.value('Authorization'), 'Bearer $_jwt');
        final dynamic data = switch (r.uri.path) {
          '/api/companion/' => [
            {
              'companion_name': 'registered peer / +',
              'is_running': true,
              'private': _jwt,
            },
          ],
          '/api/companion/self_info' => {
            'frequency_hz': 869525000,
            'private': _jwt,
          },
          _ => [
            {'index': 3, 'name': _jwt, 'psk': _jwt},
          ],
        };
        r.response.write(jsonEncode({'success': true, 'data': data}));
        await r.response.close();
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/');
      final result = await openHopPreflight(
        OpenHopPeerConfig(_json(url, 'info'), 'info'),
        _jwt,
        true,
      );
      expect(paths, [
        '/api/companion/',
        '/api/companion/self_info',
        '/api/companion/channels',
      ]);
      expect(result['channelSlots'], [3]);
      expect(jsonEncode(result), isNot(contains(_jwt)));
      expect(result['channelKeysVerified'], isFalse);
    },
  );

  test(
    'current-time cannot complete or renew an initialization command',
    () async {
      final h = await _Server.start();
      addTearDown(h.close);
      Timer? notice;
      addTearDown(() => notice?.cancel());
      final messages = h.messages.stream.listen((_) {
        notice = Timer(const Duration(milliseconds: 700), () {
          h.socket!.add(_rx([9, 0, 0, 0, 0]));
        });
      });
      addTearDown(messages.cancel);
      final json = _json(h.url, 'info');
      (json['session'] as Map)['commandSeconds'] = 1;
      final out = StringBuffer();
      final watch = Stopwatch()..start();
      final code = await runOpenHopPeer(
        OpenHopPeerConfig(json, 'info'),
        output: CliOutput(out, StringBuffer()),
        createTransport: h.transport,
      );
      final end = jsonDecode(out.toString().trim().split('\n').last);
      expect(code, 69);
      expect(end['failure']['session']['kind'], 'requestTimeout');
      expect(end['failure']['session']['commandOpcode'], 0x16);
      expect(end['cleanup']['state'], 'succeeded');
      expect(out.toString(), isNot(contains('peer_session_ready')));
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
      await h.released.future;
    },
  );
  test('configuration and URI validation are inert and do not echo input', () {
    for (final option in [
      '--profile=SECRET_PROFILE',
      '--record',
      '--all-data-types',
    ]) {
      final json = _json(Uri.parse('http://127.0.0.1:1/'), 'ping');
      (json['datagramArguments'] as List).add(option);
      expect(() => OpenHopPeerConfig(json, 'ping'), throwsFormatException);
    }

    for (final url in [
      'file:///private',
      'http://user:secret@host/',
      'http://host/?token=private',
      'http://host/prefix',
      'http://host/#private',
    ]) {
      final json = _json(Uri.parse(url), 'ping');
      expect(() => OpenHopPeerConfig(json, 'ping'), throwsFormatException);
    }
    final config = _json(Uri.parse('http://127.0.0.1:1/'), 'ping');
    config['datagramArguments'] = ['--local-id=1'];
    expect(() => OpenHopPeerConfig(config, 'ping'), throwsFormatException);
    config['jwt'] = {'literal': _jwt};
    expect(() => OpenHopPeerConfig(config, 'info'), throwsFormatException);
    expect(
      () => OpenHopFrameTransport(
        baseUrl: Uri.parse('http://127.0.0.1/'),
        companionName: 'peer',
        jwt: 'ordinary-api-key',
        connectTimeout: const Duration(seconds: 1),
      ),
      throwsFormatException,
    );
  });

  test(
    'binary split and coalesced frames plus independent full TX vector',
    () async {
      final h = await _Server.start();
      addTearDown(h.close);
      final t = h.transport();
      final frames = <List<int>>[];
      final got = Completer<void>();
      final sub = t.frames.listen((f) {
        frames.add(f);
        if (frames.length == 2) got.complete();
      });
      await t.open();
      expect(
        h.requestUri!.queryParameters['companion_name'],
        'registered peer / +',
      );
      expect(h.requestUri!.queryParameters['token'], _jwt);
      h.socket!.add([0x3e, 2]);
      h.socket!.add([0, 0x09, 0, 0x3e, 1, 0, 0x83]);
      await got.future;
      expect(frames, [
        [9, 0],
        [0x83],
      ]);
      final sent = h.messages.stream.first;
      await t.sendFrame(
        Uint8List.fromList([
          0x3e,
          3,
          0,
          0x34,
          0x12,
          0,
          0x11,
          0x13,
          0x3c,
          0x3e,
          0x80,
          0xff,
        ]),
      );
      expect(await sent, [
        0x3c,
        12,
        0,
        0x3e,
        3,
        0,
        0x34,
        0x12,
        0,
        0x11,
        0x13,
        0x3c,
        0x3e,
        0x80,
        0xff,
      ]);
      await t.close();
      await t.close();
      await sub.cancel();
      await h.released.future;
      expect(h.requests, 1);
    },
  );

  for (final kind in ['auth', 'partial', 'text', 'oversized', 'clean']) {
    test('$kind termination is bounded and redacted', () async {
      final h = await _Server.start(closeCode: kind == 'auth' ? 1008 : null);
      addTearDown(h.close);
      final t = h.transport();
      final error = Completer<Object>();
      final sub = t.frames.listen(
        (_) {},
        onError: (Object e) {
          if (!error.isCompleted) error.complete(e);
        },
      );
      await t.open();
      if (kind == 'partial') {
        h.socket!.add([0x3e, 3, 0, 9]);
        await h.socket!.close();
      }
      if (kind == 'clean') await h.socket!.close();
      if (kind == 'text') h.socket!.add('private $_jwt');
      if (kind == 'oversized') {
        h.socket!.add(
          List.filled(OpenHopFrameTransport.maxMessageBytes + 1, 0),
        );
      }
      final failure = await error.future as OpenHopTransportFailure;
      expect(failure.toString(), isNot(contains(_jwt)));
      expect(failure.toString(), isNot(contains('ws://')));
      expect(failure.reason, switch (kind) {
        'auth' => 'authenticationOrSelectionRejected',
        'partial' => 'truncatedFrame',
        'text' => 'textMessageRejected',
        'clean' => 'webSocketClosed',
        _ => 'webSocketClosed',
      });
      await t.close();
      await sub.cancel();
      expect(h.requests, 1);
    });
  }

  test('cancel waits for and closes a late successful connection', () async {
    final h = await _Server.start();
    addTearDown(h.close);
    final gate = Completer<WebSocket>();
    final entered = Completer<void>();
    final t = h.transport(
      connector: (_, _) {
        entered.complete();
        return gate.future;
      },
    );
    final sub = t.frames.listen((_) {});
    final opening = t.open();
    final failed = expectLater(
      opening,
      throwsA(isA<OpenHopTransportFailure>()),
    );
    await entered.future;
    var closed = false;
    final closing = t.close().then((_) {
      closed = true;
    });
    final client = await WebSocket.connect(
      h.url.replace(scheme: 'ws').toString(),
    );
    expect(closed, isFalse);
    gate.complete(client);
    await failed;
    await closing;
    await h.released.future;
    await sub.cancel();
    expect(closed, isTrue);
    expect(h.requests, 1);
  });

  test(
    'upgrade redirects never create another connection or disclose a URL',
    () async {
      final h = await _Server.start(redirect: true);
      addTearDown(h.close);
      final t = h.transport();
      final sub = t.frames.listen((_) {});
      await expectLater(t.open(), throwsA(isA<OpenHopTransportFailure>()));
      await t.close();
      await sub.cancel();
      expect(h.requests, 1);
    },
  );

  for (final outcome in ['pong', 'time-only']) {
    test(
      'real loopback session ping $outcome preserves command and response budgets',
      () async {
        final h = await _Server.start();
        addTearDown(h.close);
        List<int>? pong;
        Timer? timeNotice;
        addTearDown(() => timeNotice?.cancel());
        final network = h.messages.stream.listen((wire) {
          final content = wire.sublist(3);
          switch (content.first) {
            case 0x16:
              h.socket!.add(_rx([9, 0, 0, 0, 0]));
              h.socket!.add(_rx(_device()));
            case 1:
              h.socket!.add(_rx(_self()));
            case 0x3e:
              final payload = content.sublist(5);
              // Synthetic remote endpoint, not a second application oracle.
              final response = List<int>.from(payload)..[5] = 2;
              response.setRange(26, 30, payload.sublist(30, 34));
              response.setRange(30, 34, payload.sublist(26, 30));
              pong = [
                0x1b,
                0,
                0,
                0,
                2,
                0,
                0xff,
                0xff,
                response.length,
                ...response,
              ];
              h.socket!.add(_rx([9, 1, 0, 0, 0]));
              h.socket!.add(_rx([0]));
              h.socket!.add(_rx([0x83]));
              if (outcome == 'time-only') {
                timeNotice = Timer(const Duration(milliseconds: 700), () {
                  h.socket!.add(_rx([9, 2, 0, 0, 0]));
                });
              }
            case 0x0a:
              h.socket!.add(
                _rx(outcome == 'pong' && pong != null ? pong! : [0x0a]),
              );
              pong = null;
          }
        });
        addTearDown(network.cancel);
        final config = OpenHopPeerConfig(_json(h.url, 'ping'), 'ping');
        final out = StringBuffer(), err = StringBuffer();
        final watch = Stopwatch()..start();
        final code = await runOpenHopPeer(
          config,
          output: CliOutput(out, err),
          createTransport: h.transport,
        );
        final records = out
            .toString()
            .trim()
            .split('\n')
            .map((e) => jsonDecode(e) as Map)
            .toList();
        expect(
          records.where((e) => e['event'] == 'peer_session_ready'),
          hasLength(1),
        );
        final end = records.last;
        expect(code, outcome == 'pong' ? 0 : 69);
        expect(end['cleanup']['state'], 'succeeded');
        expect(end['result']['roundTripSucceeded'], outcome == 'pong');
        expect(
          end['result']['applicationRttUs'],
          outcome == 'pong' ? isNotNull : isNull,
        );
        if (outcome == 'time-only') {
          expect(end['result']['reason'], 'responseTimeout');
          expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
        }
        await h.released.future;
        expect(h.requests, 1);
        expect(out.toString(), isNot(contains(_jwt)));
        expect(err.isEmpty, isTrue);
      },
    );
  }

  test(
    'raw listen compares only actual queue entries and ends at the quota',
    () async {
      final h = await _Server.start();
      addTearDown(h.close);
      var reads = 0;
      final wire = h.messages.stream.listen((message) {
        switch (message[3]) {
          case 0x16:
            h.socket!.add(_rx(_device()));
          case 1:
            h.socket!.add(_rx(_self()));
          case 0x0a:
            reads++;
            h.socket!.add(
              _rx(
                reads == 1
                    ? [
                        0x1b,
                        0,
                        0,
                        0,
                        2,
                        0,
                        0x34,
                        0x12,
                        7,
                        0,
                        0x11,
                        0x13,
                        0x3c,
                        0x3e,
                        0x80,
                        0xff,
                      ]
                    : [
                        0x1b,
                        0,
                        0,
                        0,
                        2,
                        0,
                        0x34,
                        0x12,
                        7,
                        ...List.filled(7, 0x41),
                      ],
              ),
            );
        }
      });
      addTearDown(wire.cancel);
      final json = _json(h.url, 'listen');
      (json['datagramArguments'] as List).add('--max-entries=2');
      final config = OpenHopPeerConfig(json, 'listen');
      final out = StringBuffer();
      expect(
        await runOpenHopPeer(
          config,
          output: CliOutput(out, StringBuffer()),
          createTransport: h.transport,
        ),
        0,
      );
      final records = out
          .toString()
          .trim()
          .split('\n')
          .map((e) => jsonDecode(e) as Map)
          .toList();
      expect(
        records
            .where((e) => e['event'] == 'raw_datagram')
            .map((e) => e['exactPayloadMatched']),
        [true, false],
      );
      expect(records.last['result']['exactPayloadMatches'], 1);
      expect(records.last['result']['processedEntries'], 2);
      expect(records.last['cleanup']['state'], 'succeeded');
      expect(reads, 2);
      expect(out.toString(), isNot(contains('AAAAAAA')));
      await h.released.future;
    },
  );

  test(
    'raw read timeout preserves reception facts without inventing an RF send',
    () async {
      final h = await _Server.start();
      addTearDown(h.close);
      final opcodes = <int>[];
      var reads = 0;
      final wire = h.messages.stream.listen((message) {
        opcodes.add(message[3]);
        switch (message[3]) {
          case 0x16:
            h.socket!.add(_rx(_device()));
          case 1:
            h.socket!.add(_rx(_self()));
          case 0x0a:
            reads++;
            if (reads == 1) {
              h.socket!.add(
                _rx([
                  0x1b,
                  0,
                  0,
                  0,
                  2,
                  0,
                  0x34,
                  0x12,
                  7,
                  0,
                  0x11,
                  0x13,
                  0x3c,
                  0x3e,
                  0x80,
                  0xff,
                ]),
              );
            }
        }
      });
      addTearDown(wire.cancel);
      final json = _json(h.url, 'listen');
      (json['session'] as Map)['commandSeconds'] = 1;
      (json['datagramArguments'] as List).add('--duration=3');
      final out = StringBuffer();
      final code = await runOpenHopPeer(
        OpenHopPeerConfig(json, 'listen'),
        output: CliOutput(out, StringBuffer()),
        createTransport: h.transport,
      );
      final end = jsonDecode(out.toString().trim().split('\n').last) as Map;
      expect(code, 69);
      expect(end['failure']['session']['kind'], 'requestTimeout');
      expect(end['failure']['session']['commandOpcode'], 0x0a);
      expect(end['result'].containsKey('send'), isFalse);
      expect(end['result']['reception']['reason'], 'sessionFailed');
      expect(end['result']['reception']['publishedEntries'], 1);
      expect(end['result']['processedEntries'], 1);
      expect(end['result']['matchingDatagrams'], 1);
      expect(end['result']['exactPayloadMatches'], 1);
      expect(opcodes, [0x16, 1, 0x0a, 0x0a]);
      expect(end['cleanup']['state'], 'succeeded');
      await h.released.future;
    },
  );

  test(
    'active responder cancellation releases signals and the WS session',
    () async {
      final h = await _Server.start();
      addTearDown(h.close);
      final signals = StreamController<CliStopRequest>();
      final wire = h.messages.stream.listen((message) {
        switch (message[3]) {
          case 0x16:
            h.socket!.add(_rx(_device()));
          case 1:
            h.socket!.add(_rx(_self()));
          case 0x0a:
            signals.add(CliStopRequest.sigint);
            h.socket!.add(_rx([0x0a]));
        }
      });
      addTearDown(wire.cancel);
      final out = StringBuffer();
      final code = await runOpenHopPeer(
        OpenHopPeerConfig(_json(h.url, 'respond'), 'respond'),
        output: CliOutput(out, StringBuffer()),
        createTransport: h.transport,
        stopRequests: signals.stream,
      );
      expect(code, 130);
      expect(signals.hasListener, isFalse);
      expect(
        jsonDecode(out.toString().trim().split('\n').last)['cleanup']['state'],
        'succeeded',
      );
      await signals.close();
      await h.released.future;
    },
  );
}
