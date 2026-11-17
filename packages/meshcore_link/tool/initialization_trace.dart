import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/native_serial_connection.dart';
import 'package:meshcore_link/src/transport/serial_transport.dart';

import 'support/initialization_trace.dart';
import 'support/initialization_completion_probe.dart';

const _usage = '''
Usage: initialization_trace --port /dev/cu.EXPLICIT --execute [--completion-probe]
One macOS initialization attempt. Request/init budgets: 15/30 seconds.
Startup delay: zero. App name: Meshchan. Native write budget unchanged (2 s).
Only DEVICE_QUERY and, after its complete reply, APP_START are allowed.
Standard mode: QUERY, APP_START (2 frames / 24 bytes maximum).
Completion probe: QUERY, QUERY, APP_START, QUERY (4 frames / 34 bytes maximum).
The opt-in probe is an unaccepted compatibility candidate, not a product default.
No application sends, inbox reads, reset, flush, line toggle, or reconnect.
Native events are buffered in memory and emitted only after awaited cleanup.
Opening/configuring a serial port may itself affect some devices.
Source diagnostic only; not a GUI acceptance or product CLI command.''';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--help') {
    stdout.writeln(_usage);
    return;
  }
  final completionProbe =
      arguments.isNotEmpty && arguments.last == '--completion-probe';
  final port = parseInitializationTraceArguments(
    completionProbe ? arguments.sublist(0, arguments.length - 1) : arguments,
  );
  if (port == null || !Platform.isMacOS) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final startedAt = DateTime.now().toUtc();
  final trace = InitializationTrace();
  InitializationTraceConnection? connection;
  var acquisitions = 0;
  final transport = serialTransportForTest(
    portPath: port,
    operatingSystem: Platform.operatingSystem,
    createConnection: (path) {
      acquisitions++;
      if (acquisitions != 1 || path != port) {
        throw StateError('A second native acquisition is forbidden.');
      }
      return connection = InitializationTraceConnection(
        createNativeSerialConnection(path),
        trace,
        completionProbe: completionProbe,
      );
    },
  );
  final session = MeshCoreSession(
    transport: completionProbe
        ? InitializationCompletionProbe(transport)
        : transport,
    appName: 'Meshchan',
    requestTimeout: const Duration(seconds: 15),
    initializationTimeout: const Duration(seconds: 30),
    startupDelay: Duration.zero,
  );
  final observer = session.events.listen((event) {
    switch (event) {
      case MeshCoreSessionStateChanged():
        trace.add('session_state', {'state': event.state.name});
      case MeshCoreSessionUnassociatedResponse():
        trace.add('session_unassociated', {
          'opcode': event.opcode,
          'contentBytes': event.contentLength,
          'stage': event.stage.name,
        });
      case MeshCoreSessionFailed():
        trace.add('session_failed', {'kind': event.failure.kind.name});
    }
  });
  final signals = <StreamSubscription<ProcessSignal>>[];
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signals.add(
      signal.watch().listen((_) {
        trace.add('signal', {'signal': signal.toString()});
        unawaited(session.close().catchError((Object _) {}));
      }),
    );
  }
  var ready = false;
  String? errorType;
  String? closeErrorType;
  try {
    await session.connect();
    ready = true;
    trace.add('connect_completed');
  } catch (error) {
    errorType = error.runtimeType.toString();
    trace.add('connect_failed', {'errorType': errorType});
  } finally {
    try {
      await session.close();
    } catch (error) {
      closeErrorType = error.runtimeType.toString();
      trace.add('session_close_failed', {'errorType': closeErrorType});
    }
    await observer.cancel();
    for (final signal in signals) {
      await signal.cancel();
    }
  }
  final c = connection;
  final failure = session.lastFailure;
  final cleanupConfirmed =
      closeErrorType == null &&
      session.cleanupFailures.isEmpty &&
      c != null &&
      c.readerStopConfirmed &&
      c.portCloseConfirmed &&
      c.disposeConfirmed;
  final successful = ready && cleanupConfirmed && trace.omittedEvents == 0;
  stdout.writeln(
    jsonEncode({
      'tool': 'meshchan-initialization-trace',
      'formatVersion': 1,
      'pid': pid,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'port': port,
      'requestSeconds': 15,
      'initializationSeconds': 30,
      'startupMilliseconds': 0,
      'nativeWriteSeconds': 2,
      'completionProbe': completionProbe,
      'controlCommandCeiling': completionProbe ? 4 : 2,
      'ready': ready,
      'failure': failure == null
          ? null
          : {
              'kind': failure.kind.name,
              'stage': failure.stage.name,
              'commandOpcode': failure.commandOpcode,
              'expectedResponseOpcode': failure.expectedResponseOpcode,
            },
      'errorType': errorType,
      'closeErrorType': closeErrorType,
      'cleanupConfirmed': cleanupConfirmed,
      'cleanupFailureCount': session.cleanupFailures.length,
      'acquisitions': acquisitions,
      'readerStarted': c?.readerStarted ?? false,
      'readerStopConfirmed': c?.readerStopConfirmed ?? false,
      'portCloseConfirmed': c?.portCloseConfirmed ?? false,
      'disposeConfirmed': c?.disposeConfirmed ?? false,
      'nativeWriteCalls': c?.nativeWriteCalls ?? 0,
      'nativeAcceptedBytes': c?.acceptedBytes ?? 0,
      'completedCommandFrames': c?.completedCommandFrames ?? 0,
      'blockedWrites': c?.blockedWrites ?? 0,
      'applicationSendAttempts': 0,
      'inboxReads': 0,
      'trace': trace.toJson(),
    }),
  );
  exitCode = successful ? 0 : 69;
}
