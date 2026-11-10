import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

import 'cli_display.dart';
import 'cli_output.dart';
import 'datagram_options.dart';
import 'datagram_projection.dart';
import 'session_command.dart';

Future<int> runDatagramCommand(
  DatagramOptions options,
  CliOutput io,
  CompanionTransport Function(String) createTransport,
  Stream<CliStopRequest>? stopRequests, {
  Duration Function()? elapsed,
  Uint8List Function()? nonceFactory,
}) async {
  final report = _Report(options, io);
  MeshCoreSession? session;
  void Function() interrupt = () {};
  void stop(String reason, int code) {
    // Session failure may already be committed before its async event arrives.
    report.checkSession(session);
    report.choose(reason, code);
    interrupt();
  }

  io.onFailure = () => stop('output_failure', 74);
  try {
    if (io.failed) stop('output_failure', 74);
    if (report.code == 0) {
      session = MeshCoreSession(
        transport: createTransport(options.port),
        appName: 'Meshchan',
        requestTimeout: options.requestTimeout,
        initializationTimeout: options.initializationTimeout,
        startupDelay: options.startupDelay,
      );
      if (options.operation == 'ping' || options.operation == 'respond') {
        if (options.operation == 'ping') {
          final task = MeshchanPingTask(
            session: session,
            options: options.taskOptions(),
            content: options.bytes,
            responseTimeout: options.responseTimeout!,
            elapsed: elapsed,
            nonceFactory: nonceFactory,
          );
          await _runTask(
            report,
            session,
            task.start,
            task.cancel,
            task.done,
            task.cleanupDone,
            stopRequests,
            stop,
            (callback) => interrupt = callback,
          );
        } else {
          final task = MeshchanResponderTask(
            session: session,
            options: options.taskOptions(),
            listenDuration: options.duration!,
            maxResponses: options.maxResponses,
            elapsed: elapsed,
          );
          await _runTask(
            report,
            session,
            task.start,
            task.cancel,
            task.done,
            task.cleanupDone,
            stopRequests,
            stop,
            (callback) => interrupt = callback,
          );
        }
      } else {
        await _runRaw(
          report,
          session,
          stopRequests,
          stop,
          (callback) => interrupt = callback,
          elapsed,
        );
      }
    }
    // CLI subscriptions are settled by the runners before the final snapshot.
    await io.drain();
    if (io.failed) stop('output_failure', 74);
    report.rethrowInternal();
    report.finish();
    await io.drain();
    return report.code;
  } finally {
    io.onFailure = null;
  }
}

/// Reporting/exit bookkeeping shared by these four CLI operations, not a core
/// executor. External intents remain provisional until the real task settles.
final class _Report {
  _Report(this.options, this.io);
  final DatagramOptions options;
  final CliOutput io;
  int code = 0;
  String reason = 'completed';
  Map<String, Object?>? failure;
  Map<String, Object?>? result;
  final cleanupFailures = <Map<String, Object?>>[];
  String cleanupState = 'notRequired';
  Object? internalError;
  StackTrace? internalStack;
  bool _reported = false;
  bool _finalWritten = false;

  bool get external =>
      reason == 'sigint' || reason == 'sigterm' || reason == 'output_failure';
  void choose(String why, int exitCode) {
    if (code == 0) {
      reason = why;
      code = exitCode;
      if (why == 'output_failure') {
        failure = diagnosticFailure('cli', 'output_failure', null);
        if (options.operation == 'listen' && !_reported) {
          _reported = true;
          event('failure', {'failure': failure});
        }
      }
    }
  }

  void fail(Map<String, Object?> fields, {bool committedTask = false}) {
    if (code == 0 ||
        committedTask && (external || reason == 'cleanup_failure')) {
      reason = 'task_failure';
      code = 69;
      failure = fields;
    }
    if (reason == 'task_failure' && !_reported) {
      _reported = true;
      failure ??= fields;
      io.err('Error: Datagram failure: ${jsonEncode(failure)}');
      if (options.operation == 'listen') event('failure', {'failure': failure});
    }
  }

  void checkSession(MeshCoreSession? session) {
    final f = session?.lastFailure;
    if (f == null || f.kind == MeshCoreSessionFailureKind.canceled) return;
    if (f.kind == MeshCoreSessionFailureKind.cleanup) {
      if (code == 0) {
        choose('cleanup_failure', 69);
        failure = diagnosticFailure('cleanup', f.kind.name, f.stage.name, f);
      }
    } else {
      fail(diagnosticFailure('session', f.kind.name, f.stage.name, f));
    }
  }

  void cleanupFailure(String? stage, [Object? error]) {
    final session = sessionEvidence(error);
    final fields = diagnosticFailure(
      'cleanup',
      session?.kind.name,
      stage,
      session,
    );
    cleanupFailures.add(fields);
    if (code == 0) {
      choose('cleanup_failure', 69);
      failure = fields;
    }
    io.err(
      'Error: Cleanup failed; resource release was not confirmed: ${jsonEncode(fields)}',
    );
    if (reason == 'cleanup_failure' &&
        options.operation == 'listen' &&
        !_reported) {
      _reported = true;
      event('failure', {'failure': failure});
    }
  }

  void unexpected(Object error, StackTrace stack) {
    internalError ??= error;
    internalStack ??= stack;
  }

  void rethrowInternal() {
    if (internalError case final error?) {
      Error.throwWithStackTrace(error, internalStack!);
    }
  }

  void event(String event, Map<String, Object?> fields) {
    if (_finalWritten && event != 'end') return;
    final data = {
      'schemaVersion': 1,
      'command': 'datagram',
      'operation': options.operation,
      'event': event,
      ...fields,
    };
    io.out(
      options.json
          ? jsonEncode(data)
          : '$event: ${safeText(jsonEncode(fields))}',
    );
  }

  void finish() {
    _finalWritten = true;
    final envelope = <String, Object?>{
      'schemaVersion': 1,
      'command': 'datagram',
      'operation': options.operation,
      'reason': reason,
      'exitCode': code,
      'cleanup': {
        'state': cleanupState,
        'failureCount': cleanupFailures.length,
        'failures': cleanupFailures,
      },
      'failure': failure,
      'result': result,
    };
    if (options.operation == 'listen') {
      event('end', envelope);
    } else if (options.json) {
      io.out(jsonEncode(envelope));
    } else {
      io.out(
        'datagram ${options.operation}: ${safeText(reason)} (exitCode: $code)',
      );
      if (result != null) {
        io.out('result: ${safeText(jsonEncode(result))}');
      }
      if (options.operation == 'send' && code == 0) {
        io.out('Local write completed; device accepted the datagram.');
      }
      if (options.operation == 'respond') {
        io.out(
          'Responder stopped; local confirmations do not prove remote receipt.',
        );
      }
      io.out(
        'cleanup: $cleanupState (failureCount: ${cleanupFailures.length})',
      );
    }
  }
}

Future<void> _cancelSubscription(
  _Report report,
  StreamSubscription<Object?>? subscription,
  String stage,
) async {
  if (subscription == null) return;
  try {
    await subscription.cancel();
  } catch (error) {
    report.cleanupFailure(stage, error);
  }
}

Future<void> _runTask(
  _Report report,
  MeshCoreSession session,
  Future<void> Function() start,
  Future<DiagnosticTaskResult> Function() cancel,
  Future<DiagnosticTaskResult> done,
  Future<DiagnosticCleanupResult> cleanupDone,
  Stream<CliStopRequest>? requests,
  void Function(String, int) stop,
  void Function(void Function()) installInterrupt,
) async {
  var cancelRequested = false;
  void interrupt() {
    if (cancelRequested) return;
    cancelRequested = true;
    // Observe cancellation even when a core terminal gate has already won.
    unawaited(cancel().then<void>((_) {}, onError: report.unexpected));
  }

  installInterrupt(interrupt);
  // Attach both observers before subscribing to signals or starting hardware.
  final logical = done
      .then<void>((result) {
        report.result = taskProjection(result);
        if (result.reason != DiagnosticTaskReason.completed &&
            !(result.reason == DiagnosticTaskReason.canceled &&
                report.external)) {
          report.fail(taskFailureProjection(result), committedTask: true);
        }
      }, onError: report.unexpected)
      .then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          report.unexpected(error, stack);
          interrupt();
        },
      );
  final cleanup = cleanupDone.then<void>(
    (result) {
      report.cleanupState = result.state.name;
      if (result.state == DiagnosticCleanupState.failed &&
          result.failures.isEmpty &&
          report.code == 0) {
        report.choose('cleanup_failure', 69);
        report.failure = diagnosticFailure('cleanup', null, null);
      }
      for (final failure in result.failures) {
        report.cleanupFailure(failure.stage.name, failure.cause);
      }
    },
    onError: (Object error, StackTrace stack) {
      report.unexpected(error, stack);
    },
  );
  StreamSubscription<CliStopRequest>? signals;
  try {
    signals = requests?.listen(
      (request) {
        stop(request.name, request == CliStopRequest.sigint ? 130 : 143);
      },
      onError: (Object error, StackTrace stack) {
        report.unexpected(error, stack);
        interrupt();
      },
    );
    if (report.io.failed) stop('output_failure', 74);
    if (report.options.verbose) {
      report.io.err('Diagnostic: datagram task starting.');
    }
    try {
      await start();
    } on DiagnosticTaskStartError {
      /* The authoritative done result is observed above. */
    }
    await logical;
  } catch (error, stack) {
    report.unexpected(error, stack);
    interrupt();
  } finally {
    // Never bypass task ownership by closing its session here.
    await logical;
    await cleanup;
    await _cancelSubscription(report, signals, 'signalSubscription');
    if (report.cleanupFailures.isNotEmpty) report.cleanupState = 'failed';
    installInterrupt(() {});
  }
}

// Round scheduling up, retaining the original monotonic deadline for admission.
Duration _timerDelay(Duration duration) => Duration(
  milliseconds:
      (duration.inMicroseconds - 1) ~/ Duration.microsecondsPerMillisecond + 1,
);

Future<void> _runRaw(
  _Report report,
  MeshCoreSession session,
  Stream<CliStopRequest>? requests,
  void Function(String, int) stop,
  void Function(void Function()) installInterrupt,
  Duration Function()? elapsed,
) async {
  final options = report.options;
  final watch = Stopwatch()..start();
  final origin = elapsed?.call() ?? Duration.zero;
  Duration now() => (elapsed?.call() ?? watch.elapsed) - origin;
  final stopped = Completer<void>();
  Timer? timer;
  Future<void>? closing;
  bool terminal = false;
  String stage = 'connecting';
  StreamSubscription<CliStopRequest>? signals;
  StreamSubscription<MeshCoreSessionEvent>? events;
  StreamSubscription<CompanionResponse>? entries;
  MeshCoreReceptionResult? reception;
  Future<void>? receptionDone;
  bool entriesEnded = false;
  var processed = 0, matching = 0, filtered = 0, ordinary = 0;
  var attempted = false,
      pending = false,
      pendingAtTermination = false,
      accepted = false;
  MeshCoreSessionCommandFailure? sendFailure;
  Future<void>? working;

  void finish() {
    if (terminal) return;
    terminal = true;
    pendingAtTermination = pending;
    timer?.cancel();
    watch.stop();
    report.cleanupState = 'pending';
    // Close first: no waiting on reception.stop or subscription cancellation.
    closing = session.close().then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        // The session supplies every actual cleanup failure below, without double counting.
        if (error is! MeshCoreSessionFailure) report.unexpected(error, stack);
      },
    );
    stopped.complete();
  }

  installInterrupt(finish);

  void fail(Object error, StackTrace stack) {
    final evidence = sessionEvidence(error);
    if (evidence != null) {
      if (!(terminal && evidence.kind == MeshCoreSessionFailureKind.canceled)) {
        report.fail(
          diagnosticFailure(
            'session',
            evidence.kind.name,
            evidence.stage.name,
            evidence,
          ),
        );
      }
    } else {
      report.unexpected(error, stack);
    }
    finish();
  }

  void guard(void Function() callback) {
    try {
      callback();
    } catch (error, stack) {
      fail(error, stack);
    }
  }

  bool check() {
    if (terminal) return false;
    report.checkSession(session);
    if (report.code != 0) {
      finish();
      return false;
    }
    if (now() >= options.taskTimeout) {
      report.fail(diagnosticFailure('cli', 'taskTimeout', stage));
      finish();
      return false;
    }
    return true;
  }

  void progress() {
    if (!check()) return;
    final result = reception;
    if (result == null) return;
    final failure =
        result.commandFailure ?? result.sessionFailure ?? result.startError;
    if (failure != null) {
      fail(failure, StackTrace.current);
      return;
    }
    if (!entriesEnded) return;
    if (session.state != MeshCoreSessionState.ready ||
        !(result.reason == MeshCoreReceptionStopReason.durationElapsed ||
            result.reason == MeshCoreReceptionStopReason.entryLimit)) {
      report.fail(diagnosticFailure('session', 'receptionFailed', stage));
    }
    finish();
  }

  Future<void> work() async {
    await session.connect();
    if (!check()) return;
    if (options.operation == 'send') {
      stage = 'sending';
      attempted = true;
      pending = true;
      try {
        await session.sendChannelData(
          channelIndex: options.sendChannel!,
          dataType: options.dataType!,
          routeDescriptor: options.routeDescriptor!,
          path: options.path,
          payload: options.bytes,
        );
        pending = false;
        accepted = true;
      } on MeshCoreSessionCommandFailure catch (failure) {
        pending = false;
        sendFailure = failure;
        rethrow;
      }
      if (check()) {
        if (session.state != MeshCoreSessionState.ready) {
          report.fail(diagnosticFailure('session', null, stage));
        }
        finish();
      }
    } else {
      stage = 'receiving';
      final receiver = session.createReception(
        duration: options.duration!,
        maxEntries: options.maxEntries,
      );
      entries = receiver.entries.listen(
        (entry) => guard(() {
          if (!check()) return;
          processed++;
          if (entry is ChannelDataResponse) {
            if (entry.channelIndex == options.receiveChannel &&
                (options.dataType == null ||
                    entry.dataType == options.dataType)) {
              matching++;
              report.event('datagram', {
                'channelIndex': entry.channelIndex,
                'dataType': entry.dataType,
                'payloadLength': entry.payload.length,
                'snrDb': entry.snrDb,
                'routeMetadata': entry.routeMetadata,
                'isDirect': entry.isDirect,
              });
            } else {
              filtered++;
            }
          } else if (entry is QueuedMessageResponse) {
            ordinary++;
          }
        }),
        onError: fail,
        onDone: () => guard(() {
          entriesEnded = true;
          progress();
        }),
      );
      receptionDone = receiver.done.then<void>(
        (result) => guard(() {
          reception = result;
          progress();
        }),
        onError: fail,
      );
      await receiver.start();
    }
  }

  try {
    signals = requests?.listen(
      (request) => guard(
        () => stop(request.name, request == CliStopRequest.sigint ? 130 : 143),
      ),
      onError: fail,
    );
    events = session.events.listen(
      (event) => guard(() {
        if (event is MeshCoreSessionFailed &&
            event.failure.kind != MeshCoreSessionFailureKind.canceled) {
          report.checkSession(session);
          finish();
        }
      }),
      onError: fail,
    );
    if (report.io.failed) stop('output_failure', 74);
    if (!terminal) {
      void deadline() {
        if (check()) {
          timer = Timer(
            _timerDelay(options.taskTimeout - now()),
            () => guard(deadline),
          );
        }
      }

      deadline();
      if (options.verbose) {
        report.io.err('Diagnostic: datagram ${options.operation} starting.');
      }
      if (!terminal) working = work().then<void>((_) {}, onError: fail);
    }
    await stopped.future;
  } catch (error, stack) {
    report.unexpected(error, stack);
    finish();
  } finally {
    finish();
    await closing;
    await working;
    await receptionDone;
    await _cancelSubscription(report, entries, 'entriesSubscription');
    await _cancelSubscription(report, events, 'sessionSubscription');
    await _cancelSubscription(report, signals, 'signalSubscription');
    for (final failure in session.cleanupFailures) {
      report.cleanupFailure(failure.stage.name, failure);
    }
    report.cleanupState = report.cleanupFailures.isEmpty
        ? 'succeeded'
        : 'failed';
    if (options.operation == 'send') {
      report.result = {
        'send': sendProjection(
          DiagnosticSendFacts(
            attempted: attempted,
            pendingAtTermination: pendingAtTermination,
            deviceAcceptanceConfirmed: accepted,
            dispatched: accepted ? true : sendFailure?.dispatched,
            localWriteCompleted: accepted
                ? true
                : sendFailure?.localWriteCompleted,
            localOkObserved: accepted
                ? true
                : sendFailure?.matchingResponseObserved,
            commandFailure: sendFailure,
          ),
        ),
      };
    } else {
      report.result = {
        'receptionReason': reception?.reason.name,
        'publishedEntries': reception?.publishedEntries ?? 0,
        'processedEntries': processed,
        'matchingDatagrams': matching,
        'filteredDatagrams': filtered,
        'ordinaryMessages': ordinary,
      };
    }
    timer?.cancel();
    watch.stop();
    installInterrupt(() {});
  }
}
