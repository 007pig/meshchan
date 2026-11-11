import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/src/cli_output.dart';
import 'package:meshctl/src/session_command.dart';

import 'openhop_frame_transport.dart';

final class _InitializationOnlyTransport implements CompanionTransport {
  _InitializationOnlyTransport(this.inner);
  final CompanionTransport inner;
  final sent = <int>[];
  final received = <String, int>{};
  Map<String, Object?>? failure;
  @override
  Stream<Uint8List> get frames => inner.frames
      .map((frame) {
        if (frame.isNotEmpty) {
          received.update('${frame.first}', (n) => n + 1, ifAbsent: () => 1);
        }
        return frame;
      })
      .handleError((Object error, StackTrace stack) {
        if (error is OpenHopTransportFailure) {
          failure = {'stage': error.stage, 'reason': error.reason};
        }
        Error.throwWithStackTrace(error, stack);
      });
  @override
  Future<void> open() => inner.open();
  @override
  Future<void> close() => inner.close();
  @override
  Future<void> sendFrame(Uint8List content) {
    final expected = sent.isEmpty
        ? 0x16
        : sent.length == 1
        ? 1
        : -1;
    if (content.isEmpty || content.first != expected) {
      return Future.error(
        StateError('Idle probe permits initialization only.'),
      );
    }
    sent.add(content.first);
    return inner.sendFrame(content);
  }
}

// Captures only structural watch events. Device display strings never leave it.
final class _ProbeSink implements StringSink {
  final watch = Stopwatch()..start();
  Duration? ready, closing;
  Map<String, dynamic>? end, failure;
  @override
  void writeln([Object? value = '']) {
    final event = jsonDecode(value.toString()) as Map<String, dynamic>;
    if (event['event'] == 'ready') ready ??= watch.elapsed;
    if (event['event'] == 'state' && event['state'] == 'closing') {
      closing ??= watch.elapsed;
    }
    if (event['event'] == 'end') end = event;
    if (event['event'] == 'failure') failure = event;
  }

  @override
  void write(Object? object) => writeln(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      write(objects.join(separator));
  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
}

Future<Map<String, Object?>> runOpenHopIdleProbe({
  required CompanionTransport transport,
  required Duration duration,
  required Duration commandTimeout,
  required Duration initializationTimeout,
  Stream<CliStopRequest>? stopRequests,
}) async {
  if (duration <= Duration.zero || duration > const Duration(seconds: 120)) {
    throw ArgumentError('Use a finite observation of at most 120 seconds.');
  }
  final wire = _InitializationOnlyTransport(transport);
  final sink = _ProbeSink();
  final code = await runSessionCommand(
    SessionOptions(
      command: 'watch',
      port: 'openhop-b',
      json: true,
      verbose: false,
      requestTimeout: commandTimeout,
      initializationTimeout: initializationTimeout,
      startupDelay: Duration.zero,
      duration: duration,
    ),
    CliOutput(sink, StringBuffer()),
    (_) => wire,
    stopRequests,
  );
  final elapsed = sink.ready != null && sink.closing != null
      ? sink.closing! - sink.ready!
      : Duration.zero;
  final passed =
      code == 0 &&
      sink.end?['reason'] == 'duration' &&
      sink.end?['cleanup'] == 'succeeded';
  return {
    'schemaVersion': 1,
    'tool': 'openhop_idle_probe',
    'status': passed ? 'PASS' : 'FAIL',
    'exitCode': code,
    'initializationCompleted': sink.ready != null,
    'requestedObservationMilliseconds': duration.inMilliseconds,
    'observedReadyMilliseconds': elapsed.inMilliseconds,
    'verifiedIdleWindowLowerBoundSeconds': passed ? elapsed.inSeconds : null,
    'effectiveConfiguredIdleTimeoutSeconds': null,
    'reason': sink.end?['reason'],
    'cleanup': sink.end?['cleanup'],
    'failure': sink.failure == null
        ? null
        : {
            for (final key in [
              'kind',
              'stage',
              'commandOpcode',
              'expectedResponseOpcode',
            ])
              key: sink.failure![key],
          },
    'hostCommandOpcodes': wire.sent,
    'transportFailure': wire.failure,
    'incomingOpcodeCounts': wire.received,
    'noHostCommandsDuringObservation': wire.sent.length == 2,
    'applicationDatagramsSent': 0,
    'queueReadCommandsSent': 0,
    'evidenceScope': 'Observed passive control window only; exact server timeout remains unknown',
  };
}
