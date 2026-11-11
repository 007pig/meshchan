import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

import 'package:meshctl/src/cli_display.dart';
import 'package:meshctl/src/cli_output.dart';
import 'package:meshctl/src/datagram_options.dart';
import 'package:meshctl/src/datagram_projection.dart';
import 'package:meshctl/src/session_command.dart';

import 'openhop_frame_transport.dart';

/// Pure configuration validation precedes secret reads and all network access.
final class OpenHopPeerConfig {
  OpenHopPeerConfig(Map<String, dynamic> json, this.operation) {
    baseUrl = Uri.parse(json['baseUrl'] as String);
    companionName = json['companionName'] as String;
    validateOpenHopEndpoint(baseUrl, companionName);
    endpointLabel = json['endpointLabel'] as String;
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(endpointLabel)) {
      throw const FormatException('Invalid endpoint label.');
    }
    jwtReference = _reference(json['jwt']);
    apiKeyReference = _reference(json['apiKey']);
    if (jwtReference == null && apiKeyReference == null) {
      throw const FormatException('A secret reference is required.');
    }
    if (operation != 'info' && jwtReference == null) {
      throw const FormatException(
        'WebSocket operations require a JWT reference.',
      );
    }
    final session = json['session'] as Map<String, dynamic>;
    requestTimeout = Duration(
      seconds: _number(session, 'commandSeconds', 1, 86400),
    );
    initializationTimeout = Duration(
      seconds: _number(session, 'initializationSeconds', 1, 86400),
    );
    taskTimeout = Duration(seconds: _number(session, 'taskSeconds', 1, 86400));
    startupDelay = Duration(
      milliseconds: _number(session, 'startupDelayMilliseconds', 0, 86399999),
    );
    if (startupDelay >= initializationTimeout) {
      throw const FormatException(
        'Startup delay exceeds initialization budget.',
      );
    }
    final exactIdle = json['idleTimeoutSeconds'];
    final observedWindow = json['idleWindowLowerBoundSeconds'];
    if (exactIdle != null && observedWindow != null) {
      throw const FormatException(
        'Use an exact timeout or an observed window, not both.',
      );
    }
    if (exactIdle != null) {
      _number(json, 'idleTimeoutSeconds', 1, 86400);
    } else if (observedWindow != null) {
      final seconds = _number(json, 'idleWindowLowerBoundSeconds', 1, 86400);
      if (operation != 'info' && seconds < taskTimeout.inSeconds) {
        throw const FormatException(
          'Observed passive window does not cover the task budget.',
        );
      }
    } else if (operation != 'info') {
      throw const FormatException(
        'Provide timeout or verified passive-window evidence.',
      );
    }
    if (operation != 'info') {
      final arguments = (json['datagramArguments'] as List).cast<String>();
      if (arguments.any(
        (s) =>
            s == '--port' ||
            s.startsWith('--port=') ||
            s == '--help' ||
            s == '-h',
      )) {
        throw const FormatException(
          'Port overrides and help are not configuration.',
        );
      }
      final parsed = datagramParser().parse([
        operation,
        ...arguments,
        '--port=development-openhop-peer',
        '--json',
        '--timeout=${requestTimeout.inSeconds}',
        '--init-timeout=${initializationTimeout.inSeconds}',
        '--startup-delay=${startupDelay.inMilliseconds}',
        '--task-timeout=${taskTimeout.inSeconds}',
      ]).command!;
      if (parsed.rest.isNotEmpty) {
        throw const FormatException('Unexpected arguments.');
      }
      options = DatagramOptions(parsed);
      if (operation != 'send' && !parsed.wasParsed('max-entries') ||
          operation == 'respond' && !parsed.wasParsed('max-responses')) {
        throw const FormatException(
          'Reception and response limits must be explicit.',
        );
      }
      if (operation == 'listen') {
        expectedPayload = _hex(json['expectedPayloadHex'] as String);
        if (options!.dataType == null) {
          throw const FormatException(
            'Raw listening requires an explicit data type.',
          );
        }
      }
    }
  }

  final String operation;
  late final Uri baseUrl;
  late final String companionName, endpointLabel;
  late final Map<String, String>? jwtReference, apiKeyReference;
  late final Duration requestTimeout,
      initializationTimeout,
      startupDelay,
      taskTimeout;
  DatagramOptions? options;
  Uint8List? expectedPayload;

  static int _number(Map<String, dynamic> json, String key, int min, int max) {
    final value = json[key];
    if (value is! int || value < min || value > max) {
      throw const FormatException('Missing or invalid finite budget.');
    }
    return value;
  }

  static Map<String, String>? _reference(dynamic value) {
    if (value == null) return null;
    if (value is! Map ||
        value.length != 1 ||
        !['env', 'file'].contains(value.keys.single) ||
        value.values.single is! String ||
        (value.values.single as String).trim().isEmpty) {
      throw const FormatException(
        'Use one environment or absolute file reference.',
      );
    }
    final result = Map<String, String>.from(value);
    if (result.containsKey('file') && !result['file']!.startsWith('/')) {
      throw const FormatException('Secret files must use an absolute path.');
    }
    return result;
  }

  static Uint8List _hex(String value) {
    if (value.length > 330 ||
        value.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
      throw const FormatException('Invalid expected payload.');
    }
    return Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);
  }
}

String? readOpenHopSecret(Map<String, String>? reference) {
  if (reference == null) return null;
  final String value;
  if (reference['env'] case final name?) {
    value = Platform.environment[name] ?? '';
  } else {
    final file = File(reference['file']!);
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file ||
        stat.size > 8192 ||
        !Platform.isWindows && stat.mode & 0x3f != 0) {
      throw const FormatException(
        'Secret file must be restricted to its owner.',
      );
    }
    value = file.readAsStringSync().trim();
  }
  if (value.isEmpty || value.length > 8192 || RegExp(r'\s').hasMatch(value)) {
    throw const FormatException('Secret reference is empty or invalid.');
  }
  return value;
}

/// Three allowlisted GETs; no raw server text, keys, names, or close reasons.
Future<Map<String, Object?>> openHopPreflight(
  OpenHopPeerConfig config,
  String credential,
  bool isJwt,
) async {
  final client = HttpClient()..connectionTimeout = config.requestTimeout;
  final deadline = Timer(config.taskTimeout, () => client.close(force: true));
  Future<dynamic> get(String path) async {
    final uri = config.baseUrl.replace(
      path: path,
      queryParameters: {'companion_name': config.companionName},
    );
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(
        isJwt ? 'Authorization' : 'X-API-Key',
        isJwt ? 'Bearer $credential' : credential,
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw const OpenHopTransportFailure('rest', 'httpRejected');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 65536) {
          throw const OpenHopTransportFailure('rest', 'responseLimit');
        }
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (body['success'] != true) {
        throw const OpenHopTransportFailure('rest', 'serverRejected');
      }
      return body['data'];
    } catch (_) {
      throw const OpenHopTransportFailure('rest', 'preflightFailed');
    }
  }

  try {
    final listing = await get('/api/companion/') as List;
    final selected = listing
        .where((e) => e is Map && e['companion_name'] == config.companionName)
        .toList();
    if (selected.length != 1) {
      throw const OpenHopTransportFailure('rest', 'selectionNotFound');
    }
    final self = await get('/api/companion/self_info') as Map;
    final channels = await get('/api/companion/channels') as List;
    return {
      'selectedRegistrationMatched': true,
      'isRunning': selected.single['is_running'] == true,
      'radio': {
        for (final k in [
          'frequency_hz',
          'bandwidth_hz',
          'spreading_factor',
          'coding_rate',
        ])
          k: self[k] is num ? self[k] : null,
      },
      'channelSlots': [
        for (final c in channels)
          if (c is Map && c['index'] is int) c['index'],
      ],
      'channelKeysVerified': false,
      'deploymentVersionsVerified': false,
    };
  } finally {
    deadline.cancel();
    client.close(force: true);
  }
}

Future<int> runOpenHopPeer(
  OpenHopPeerConfig config, {
  required CliOutput output,
  required CompanionTransport Function() createTransport,
  Stream<CliStopRequest>? stopRequests,
  Map<String, Object?>? preflight,
}) async {
  final session = MeshCoreSession(
    transport: createTransport(),
    appName: 'Meshchan',
    requestTimeout: config.requestTimeout,
    initializationTimeout: config.initializationTimeout,
    startupDelay: config.startupDelay,
  );
  void event(String name, Map<String, Object?> fields) => output.out(
    jsonEncode({
      'schemaVersion': 1,
      'tool': 'openhop_peer',
      'operation': config.operation,
      'endpointLabel': config.endpointLabel,
      'event': name,
      ...fields,
    }),
  );
  final observer = session.events.listen((e) {
    if (e is MeshCoreSessionStateChanged &&
        e.state == MeshCoreSessionState.ready) {
      event('peer_session_ready', {'meaning': 'Companion initialization only'});
    }
  });
  var code = 0;
  String reason = 'completed';
  Map<String, Object?>? result, failure;
  String cleanup = 'pending';
  void Function() cancel = () {};
  void stop(String why, int exitCode) {
    if (code == 0) {
      code = exitCode;
      reason = why;
    }
    cancel();
  }

  final signals = stopRequests?.listen(
    (s) => stop(s.name, s == CliStopRequest.sigint ? 130 : 143),
  );
  output.onFailure = () => stop('output_failure', 74);
  Timer? timer;
  StreamSubscription<CompanionResponse>? entries;
  Future<void>? rawClosing;
  try {
    final options = config.options;
    if (config.operation == 'ping' || config.operation == 'respond') {
      final dynamic task = config.operation == 'ping'
          ? MeshchanPingTask(
              session: session,
              options: options!.taskOptions(),
              content: options.bytes,
              responseTimeout: options.responseTimeout!,
            )
          : MeshchanResponderTask(
              session: session,
              options: options!.taskOptions(),
              listenDuration: options.duration!,
              maxResponses: options.maxResponses,
            );
      cancel = () {
        (task.cancel() as Future<DiagnosticTaskResult>).ignore();
      };
      // Observe actual cleanup immediately, separately from logical completion.
      final cleaning = task.cleanupDone as Future<DiagnosticCleanupResult>;
      cleaning.ignore();
      try {
        await task.start();
      } on DiagnosticTaskStartError {
        /* done is authoritative */
      }
      final done = await task.done as DiagnosticTaskResult;
      result = taskProjection(done);
      if (done.reason != DiagnosticTaskReason.completed &&
          !(done.reason == DiagnosticTaskReason.canceled && code != 0)) {
        code = 69;
        reason = 'task_failure';
        failure = taskFailureProjection(done);
      }
      final cleaned = await cleaning;
      cleanup = cleaned.state.name;
    } else {
      cancel = () {
        rawClosing ??= session.close();
        rawClosing!.ignore();
      };
      timer = Timer(config.taskTimeout, () => stop('taskTimeout', 69));
      await session.connect();
      if (config.operation == 'info') {
        final fields = infoFields(
          config.endpointLabel,
          session.info!,
          closed: false,
        );
        // Device-controlled display strings are not evidence of deployment versions.
        (fields['self'] as Map).remove('nodeName');
        result = {'session': fields, 'rest': preflight};
      } else if (config.operation == 'send') {
        await session.sendChannelData(
          channelIndex: options!.sendChannel!,
          dataType: options.dataType!,
          routeDescriptor: options.routeDescriptor!,
          path: options.path,
          payload: options.bytes,
        );
        result = {
          'send': {
            'attempted': true,
            'localWriteCompleted': true,
            'localOkObserved': true,
            'deviceAcceptanceConfirmed': true,
          },
        };
      } else {
        var matching = 0, exact = 0, processed = 0;
        final receiver = session.createReception(
          duration: options!.duration!,
          maxEntries: options.maxEntries,
        );
        final drained = Completer<void>();
        entries = receiver.entries.listen(
          (entry) {
            processed++;
            if (entry is ChannelDataResponse &&
                entry.channelIndex == options.receiveChannel &&
                entry.dataType == options.dataType) {
              matching++;
              final expected = config.expectedPayload!;
              final matched =
                  entry.payload.length == expected.length &&
                  List.generate(
                    expected.length,
                    (i) => entry.payload[i] == expected[i],
                  ).every((e) => e);
              if (matched) exact++;
              event('raw_datagram', {
                'channelIndex': entry.channelIndex,
                'dataType': entry.dataType,
                'payloadLength': entry.payload.length,
                'exactPayloadMatched': matched,
              });
            }
          },
          onDone: drained.complete,
          onError: (Object _) {
            stop('receptionFailed', 69);
          },
        );
        final completion = receiver.done;
        await receiver.start();
        event('peer_reception_active', {
          'durationMilliseconds': options.duration!.inMilliseconds,
        });
        final done = await completion;
        await drained.future;
        result = {
          'reception': receptionProjection(done),
          'processedEntries': processed,
          'matchingDatagrams': matching,
          'exactPayloadMatches': exact,
          'exactPayloadMatched': exact > 0,
        };
        if (done.commandFailure != null ||
            done.sessionFailure != null ||
            done.startError != null) {
          throw done.commandFailure ?? done.sessionFailure ?? done.startError!;
        }
      }
    }
  } catch (error) {
    final prior = sessionEvidence(error);
    if (prior != null && prior.kind != MeshCoreSessionFailureKind.canceled) {
      code = 69;
      reason = 'session_failure';
    }
    if (code == 0) {
      code = 69;
      reason = 'session_failure';
    }
    final evidence = sessionEvidence(error);
    failure = {
      'session': evidence == null ? null : failureFields(evidence),
      if (error is OpenHopTransportFailure)
        'transport': {'stage': error.stage, 'reason': error.reason},
    };
    if (config.operation == 'send' && error is MeshCoreSessionCommandFailure) {
      result = {
        'send': {
          'attempted': true,
          'dispatched': error.dispatched,
          'localWriteCompleted': error.localWriteCompleted,
          'localOkObserved': error.matchingResponseObserved,
          'deviceAcceptanceConfirmed': false,
        },
      };
    }
  } finally {
    timer?.cancel();
    // Tasks have already released their session; close remains idempotent.
    // Never close a task-owned session before cleanupDone has settled.
    try {
      await (rawClosing ?? session.close());
    } catch (_) {
      cleanup = 'failed';
    }
    await entries?.cancel();
    await observer.cancel();
    await signals?.cancel();
    if (cleanup != 'failed') {
      cleanup = session.cleanupFailures.isEmpty ? 'succeeded' : 'failed';
    }
    if (cleanup != 'succeeded' && code == 0) {
      code = 69;
      reason = 'cleanup_failure';
    }
    output.onFailure = null;
  }
  final recorded = session.lastFailure;
  if (config.operation != 'ping' &&
      config.operation != 'respond' &&
      recorded != null &&
      recorded.kind != MeshCoreSessionFailureKind.canceled) {
    // A command's OK may commit before a later synchronous input failure.
    // Preserve that command's completed facts, but reconcile raw-session health
    // just as the product raw runner does. Task terminal gates remain owned by
    // the diagnostic tasks and are not reinterpreted here.
    if (recorded.kind != MeshCoreSessionFailureKind.cleanup) {
      code = 69;
      reason = 'session_failure';
    } else if (code == 0) {
      code = 69;
      reason = 'cleanup_failure';
    }
    failure = {...?failure, 'session': failureFields(recorded)};
  }
  final cause = recorded?.cause;
  if (cause is OpenHopTransportFailure) {
    failure = {
      ...?failure,
      'transport': {'stage': cause.stage, 'reason': cause.reason},
    };
  }
  if (result?['session'] case final Map<String, Object?> fields) {
    fields['sessionClosed'] = cleanup == 'succeeded';
  }
  event('end', {
    'reason': reason,
    'exitCode': code,
    'cleanup': {'state': cleanup},
    'failure': failure,
    'preflight': preflight,
    'result': result,
    'localWriteMeaning': 'Local WebSocket submission only; Companion OK is separate; no RF completion claim',
  });
  await output.drain();
  return output.failed ? 74 : code;
}
