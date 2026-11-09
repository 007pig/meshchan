import 'dart:async';
import 'dart:convert';

import 'package:meshcore_link/meshcore_link.dart';

import 'cli_display.dart';
import 'cli_output.dart';

enum CliStopRequest { sigint, sigterm }

/// All values have already passed CLI validation before this is constructed.
final class SessionOptions {
  const SessionOptions({
    required this.command,
    required this.port,
    required this.json,
    required this.verbose,
    required this.requestTimeout,
    required this.initializationTimeout,
    required this.startupDelay,
    this.duration,
  });

  final String command;
  final String port;
  final bool json;
  final bool verbose;
  final Duration requestTimeout;
  final Duration initializationTimeout;
  final Duration startupDelay;
  final Duration? duration;
}

Future<int> runSessionCommand(
  SessionOptions options,
  CliOutput io,
  CompanionTransport Function(String) createTransport,
  Stream<CliStopRequest>? stopRequests,
) async {
  final watch = options.command == 'watch';
  final stopped = Completer<void>();
  Timer? duration;
  String? reason;
  var code = 0;
  Object? internalError;
  StackTrace? internalStack;
  var additionalInternalFailure = false;
  MeshCoreSessionFailure? reportedFailure;
  MeshCoreSessionInfo? snapshot;
  MeshCoreSession? session;
  Future<void>? closing;
  StreamSubscription<MeshCoreSessionEvent>? observer;
  StreamSubscription<CliStopRequest>? stops;
  var cleanupFailed = false;

  void stop(String why, int exitCode) {
    // A successful intent may still fail during cleanup/output. A primary
    // failure or signal is never replaced by another terminal notification.
    if (reason == null || code == 0 && exitCode != 0) {
      reason = why;
      code = exitCode;
    }
    duration?.cancel();
    if (!stopped.isCompleted) stopped.complete();
    if (session != null && closing == null) {
      // Interrupt initialization immediately, including already queued request
      // advancement. The same Future is awaited in the shared cleanup below.
      final pendingClose = session.close();
      closing = pendingClose;
      pendingClose.ignore();
    }
  }

  void emit(String event, Map<String, Object?> fields) {
    if (options.json) {
      io.out(
        jsonEncode({
          'schemaVersion': 1,
          'command': 'watch',
          'event': event,
          ...fields,
        }),
      );
    } else {
      io.out('$event: ${jsonEncode(fields)}');
    }
  }

  void diagnose(String event, Map<String, Object?> fields) {
    if (options.verbose) {
      io.err('Diagnostic: ${jsonEncode({'event': event, ...fields})}');
    }
  }

  void fail(MeshCoreSessionFailure failure) {
    if (reportedFailure != null || code != 0) return;
    reportedFailure = failure;
    stop('failure', 69);
    final fields = failureFields(failure);
    io.err('Error: Session failure: ${jsonEncode(fields)}');
    if (watch) emit('failure', fields);
  }

  void unexpected(Object error, StackTrace stack) {
    if (code != 0 && reason != 'internal_error') {
      if (!additionalInternalFailure) {
        additionalInternalFailure = true;
        io.err('Error: Additional internal CLI failure during cleanup.');
      }
      return;
    }
    internalError ??= error;
    internalStack ??= stack;
    stop('internal_error', 70);
  }

  // Callbacks never return unobserved Futures or let errors escape the stream.
  void guard(void Function() action) {
    try {
      action();
    } catch (error, stack) {
      unexpected(error, stack);
    }
  }

  void outputFailed() {
    if (session?.lastFailure case final failure?) fail(failure);
    stop('output_failure', 74);
  }

  io.onFailure = outputFailed;
  try {
    if (io.failed) outputFailed();
    stops = stopRequests?.listen(
      (request) => guard(() {
        if (session?.lastFailure case final failure?) fail(failure);
        if (code != 0) return;
        stop(request.name, request == CliStopRequest.sigint ? 130 : 143);
        io.err('Stopping; waiting for transport cleanup.');
      }),
      onError: (Object error, StackTrace stack) => unexpected(error, stack),
    );
    if (!stopped.isCompleted) {
      final active = session = MeshCoreSession(
        transport: createTransport(options.port),
        appName: 'Meshchan',
        requestTimeout: options.requestTimeout,
        initializationTimeout: options.initializationTimeout,
        startupDelay: options.startupDelay,
      );
      observer = active.events.listen(
        (event) => guard(() {
          switch (event) {
            case MeshCoreSessionStateChanged():
              final fields = {
                'previous': event.previous.name,
                'state': event.state.name,
              };
              if (!stopped.isCompleted ||
                  event.state == MeshCoreSessionState.closing ||
                  event.state == MeshCoreSessionState.closed ||
                  event.state == MeshCoreSessionState.failed) {
                if (watch) emit('state', fields);
                diagnose('state', fields);
              }
            case MeshCoreSessionUnassociatedResponse():
              if (!stopped.isCompleted) {
                final fields = responseFields(event);
                if (watch) emit('unassociated_response', fields);
                diagnose('unassociated_response', fields);
              }
            case MeshCoreSessionFailed():
              // Cleanup is reported after the shared close Future settles.
              if (event.failure.kind != MeshCoreSessionFailureKind.cleanup) {
                fail(event.failure);
              }
          }
        }),
      );
      // Attach success and error observers immediately, before any other await.
      unawaited(
        active.connect().then<void>(
          (info) => guard(() {
            if (active.lastFailure case final failure?) fail(failure);
            if (stopped.isCompleted) return;
            snapshot = info;
            if (!watch) {
              stop('completed', 0);
              return;
            }
            final fields = infoFields(options.port, info, closed: false);
            if (options.json) {
              emit('ready', fields);
            } else {
              io.out('ready:\n${infoText(fields)}');
            }
            if (!stopped.isCompleted) {
              if (options.duration case final window?) {
                duration = Timer(window, () => stop('duration', 0));
              }
            }
          }),
          onError: (Object error, StackTrace stack) => guard(() {
            if (error is MeshCoreSessionFailure) {
              // close() completes an unfinished connect as canceled. The signal or
              // output failure that requested close remains the primary reason.
              if (error.kind != MeshCoreSessionFailureKind.canceled ||
                  code == 0) {
                fail(error);
              }
            } else {
              unexpected(error, stack);
            }
          }),
        ),
      );
      await stopped.future;
    }
  } catch (error, stack) {
    unexpected(error, stack);
  } finally {
    duration?.cancel();
    if (session case final active?) {
      try {
        await (closing ??= active.close());
      } on MeshCoreSessionFailure catch (_) {
        cleanupFailed = true;
      } catch (error, stack) {
        cleanupFailed = true;
        unexpected(error, stack);
      }
      // Failure need not transition to closed. Getters also cover queued events.
      if (active.lastFailure case final failure?) fail(failure);
      cleanupFailed = cleanupFailed || active.cleanupFailures.isNotEmpty;
      if (cleanupFailed) {
        if (code == 0) stop('failure', 69);
        io.err(
          'Error: Transport cleanup failed; resource release was not confirmed.',
        );
      }
    }
    try {
      // This session broadcast controller has no asynchronous onCancel work.
      // Cancellation removes the observer immediately; its empty completion is
      // still observed. The observer owns no transport or signal resources.
      observer?.cancel().ignore();
    } catch (error, stack) {
      cleanupFailed = true;
      unexpected(error, stack);
    }
    try {
      await stops?.cancel();
    } catch (error, stack) {
      cleanupFailed = true;
      unexpected(error, stack);
    }
  }

  // Observe all pending output before claiming the final result. A broken
  // channel discards its own queue; a permanently blocked consumer can still
  // keep a healthy channel's flush pending.
  await io.drain();
  if (watch) {
    emit('end', {
      'reason': reason ?? 'internal_error',
      'exitCode': code,
      'cleanup': cleanupFailed ? 'failed' : 'succeeded',
    });
  } else if (code == 0 && snapshot != null) {
    final fields = infoFields(options.port, snapshot!, closed: true);
    io.out(
      options.json
          ? jsonEncode({'schemaVersion': 1, 'command': 'info', ...fields})
          : infoText(fields),
    );
  }
  await io.drain();
  io.onFailure = null;
  if (internalError != null) {
    Error.throwWithStackTrace(internalError!, internalStack!);
  }
  return code;
}
