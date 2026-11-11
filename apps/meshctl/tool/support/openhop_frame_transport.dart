import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

/// Safe categories only: never retain a credential, URL, close reason, or cause.
final class OpenHopTransportFailure implements Exception {
  const OpenHopTransportFailure(this.stage, this.reason);
  final String stage, reason;
  @override
  String toString() => 'OpenHopTransportFailure($stage, $reason)';
}

typedef OpenHopConnector = Future<WebSocket> Function(
  Uri uri,
  HttpClient client,
);

/// Development-only, single-use WS byte pipe. Not a product transport export.
final class OpenHopFrameTransport implements CompanionTransport {
  OpenHopFrameTransport({
    required Uri baseUrl,
    required String companionName,
    required String jwt,
    required this.connectTimeout,
    OpenHopConnector? connector,
  }) : _connector = connector ?? _connect {
    validateOpenHopEndpoint(baseUrl, companionName);
    if (!RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')
            .hasMatch(jwt) ||
        jwt.length > 8192 ||
        connectTimeout <= Duration.zero) {
      throw const FormatException('Invalid JWT reference or connect budget.');
    }
    _uri = baseUrl.replace(
      scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/companion_frame',
      queryParameters: {'token': jwt, 'companion_name': companionName},
    );
    _frames = StreamController<Uint8List>(
      onPause: _requestClose,
      onCancel: _requestClose,
    );
  }

  static const maxMessageBytes = 8192;
  static Future<WebSocket> _connect(Uri uri, HttpClient client) =>
      WebSocket.connect(
        uri.toString(),
        customClient: client,
        compression: CompressionOptions.compressionOff,
        maxPayloadLength: maxMessageBytes,
      );

  late final Uri _uri;
  final Duration connectTimeout;
  final OpenHopConnector _connector;
  final _decoder = SerialFrameDecoder();
  late final StreamController<Uint8List> _frames;
  HttpClient? _client;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _input;
  final _inputEnded = Completer<void>();
  Future<void>? _opening, _closing;
  bool _stopping = false, _failed = false, _used = false;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Future<void> open() {
    if (_used || _stopping || !_frames.hasListener) {
      return Future.error(
        const OpenHopTransportFailure('open', 'invalidState'),
      );
    }
    _used = true;
    final future = _opening = _open();
    // Observe immediately, even if the owner is concurrently canceling.
    future.ignore();
    return future;
  }

  Future<void> _open() async {
    final client = _client = _UpgradeClient(
      HttpClient()..connectionTimeout = connectTimeout,
    );
    try {
      final socket = await _connector(_uri, client);
      _socket = socket;
      // Observe the sink before either sending or closing it.
      socket.done.then<void>((_) {}, onError: (Object _) {}).ignore();
      _input = socket.listen(
        _message,
        onError: (Object _) => _fail('receive', 'webSocketError'),
        onDone: () {
          if (!_inputEnded.isCompleted) _inputEnded.complete();
          if (_stopping) return;
          final error = _decoder.finish().error;
          _fail(
            'receive',
            error != null
                ? error.kind.name
                : socket.closeCode == 1008
                ? 'authenticationOrSelectionRejected'
                : 'webSocketClosed',
          );
        },
      );
      if (_stopping) {
        await socket.close();
        throw const OpenHopTransportFailure('open', 'canceled');
      }
    } catch (_) {
      client.close(force: true);
      throw OpenHopTransportFailure(
        'open',
        _stopping ? 'canceled' : 'connectionFailed',
      );
    }
  }

  void _message(dynamic message) {
    if (_stopping || _failed) return;
    if (message is! List<int>) {
      _fail('receive', 'textMessageRejected');
      return;
    }
    if (message.length > maxMessageBytes) {
      _fail('receive', 'messageLimit');
      return;
    }
    final result = _decoder.add(Uint8List.fromList(message));
    for (final frame in result.frames) {
      _frames.add(frame);
    }
    if (result.error case final error?) _fail('decode', error.kind.name);
  }

  void _fail(String stage, String reason) {
    if (_failed || _stopping) return;
    _failed = true;
    _frames.addError(OpenHopTransportFailure(stage, reason));
    _requestClose();
  }

  void _requestClose() => close().ignore();

  @override
  Future<void> sendFrame(Uint8List content) async {
    final bytes = encodeSerialFrame(content);
    if (_socket == null || _stopping || _failed) {
      throw const OpenHopTransportFailure('send', 'invalidState');
    }
    try {
      // Completion means local WS submission only, never TCP/RF completion.
      await _socket!.addStream(Stream<List<int>>.value(bytes));
    } catch (_) {
      _fail('send', 'submissionFailed');
      throw const OpenHopTransportFailure('send', 'submissionFailed');
    }
  }

  @override
  Future<void> close() {
    if (_closing case final future?) return future;
    _stopping = true;
    final future = _closing = _close();
    future.ignore();
    return future;
  }

  Future<void> _close() async {
    // Abort a pending HTTP upgrade; a late injected/SDK success is still awaited.
    _client?.close(force: true);
    var failed = false;
    try {
      try {
        await _opening;
      } catch (_) {
        // The open owner retains its failure; cleanup must still release assets.
      }
      await _socket?.close();
      // WebSocket.close settles the outgoing sink, not the receive connection.
      // Keep input subscribed through the peer close/SDK close handshake so the
      // SDK cancels its close timer and releases the underlying connection.
      if (_input != null) await _inputEnded.future;
    } catch (_) {
      failed = true;
    } finally {
      try {
        await _input?.cancel();
      } catch (_) {
        failed = true;
      }
      _client?.close(force: true);
      // Public delivery owns no connection resources. An absent or paused
      // consumer must not hold completed socket/subscription cleanup hostage.
      _frames.close().ignore();
    }
    if (failed) {
      throw const OpenHopTransportFailure('close', 'releaseFailed');
    }
  }
}

// WebSocket.connect uses openUrl and close on its custom client. Reject
// redirects before submitting the upgrade, including credentialed URLs.
final class _UpgradeClient implements HttpClient {
  _UpgradeClient(this.inner);
  final HttpClient inner;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await inner.openUrl(method, url);
    request.followRedirects = false;
    return request;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void validateOpenHopEndpoint(Uri url, String name) {
  if (!['http', 'https'].contains(url.scheme) ||
      !url.hasAuthority ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      !['', '/'].contains(url.path) ||
      RegExp(r'\s').hasMatch(url.host) ||
      name.trim().isEmpty ||
      name.length > 128 ||
      name.runes.any((c) => c < 32 || c == 127)) {
    throw const FormatException(
      'Invalid base URL or Companion registration name.',
    );
  }
}
