import 'dart:async';
import 'dart:convert';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart' show CompanionTransport;

import 'business_projection.dart';
import 'business_storage.dart';
import 'cli_display.dart';
import 'cli_output.dart';
import 'datagram_options.dart';
import 'datagram_signals.dart';
import 'session_command.dart';
import 'version.dart';

Future<int> runRecordedDatagram(
  DatagramInput input,
  EffectiveParameters parameters,
  BusinessStorage storage,
  CliOutput io,
  CompanionTransport Function(String) createTransport,
  DatagramSignals stopRequests,
) async {
  var code = 0;
  var reason = 'completed';
  Map<String, Object?>? failure;
  Object? unexpected;
  StackTrace? unexpectedStack;
  RecordedOperation? operation;
  StreamSubscription<CliStopRequest>? signals;
  var handedOff = false;
  var cancelRequested = false;
  final hostFailures = <Map<String, Object?>>[];
  final additionalSaveFailures = <Map<String, Object?>>[];
  RecordedResult? result;
  String? runId;
  final observedSaves = Set<RecordingSave>.identity();

  bool external() =>
      reason == 'sigint' || reason == 'sigterm' || reason == 'output_failure';
  void choose(String why, int value, [Map<String, Object?>? detail]) {
    if (code == 0) {
      reason = why;
      code = value;
      failure = detail;
    }
  }

  void internal(Object e, StackTrace s) {
    unexpected ??= e;
    unexpectedStack ??= s;
  }

  void cancel() {
    cancelRequested = true;
    final op = operation;
    if (op != null) {
      unawaited(op.cancel().then<void>((_) {}, onError: internal));
    }
  }

  void stop(String why, int value) {
    choose(
      why,
      value,
      why == 'output_failure'
          ? {'domain': 'cli', 'source': 'output', 'code': 'output_failure'}
          : null,
    );
    cancel();
  }

  void logical(LogicalSummary? value) {
    if (value == null) return;
    final why = value.reason;
    final session = value.failure?.session;
    final priorSessionFailure =
        session != null &&
        session.kind != FailureKind.canceled &&
        session.kind != FailureKind.cleanup;
    if (why != null &&
        why != LogicalReason.completed &&
        !(why == LogicalReason.canceled &&
            external() &&
            !priorSessionFailure)) {
      // A final typed non-canceled failure corrects provisional external intent,
      // including a frozen result whose Future callback arrived after a signal.
      if (code == 0 ||
          (external() || reason == 'cleanup_failure') &&
              (why != LogicalReason.canceled || priorSessionFailure)) {
        reason = 'task_failure';
        code = why == LogicalReason.unexpectedFailure ? 70 : 69;
        failure = priorSessionFailure
            ? {
                'domain': 'session',
                'kind': session.kind.code,
                'stage': session.stage.code,
                'session': sessionSummaryFields(session),
              }
            : failureSummaryFields(value.failure) ??
                  {
                    'domain': 'task',
                    'kind': why.code,
                    'stage': value.stage?.code,
                  };
      }
      io.err(
        'Error: Recorded datagram logical failure: ${jsonEncode(logicalFields(value))}',
      );
    } else {
      io.err('Recorded logical result: ${jsonEncode(logicalFields(value))}');
    }
  }

  void saved(RecordingSave value) {
    if (!observedSaves.add(value)) return;
    if (value.phase == RecordingPhase.registration) {
      runId = value.snapshot?.runId.value;
    }
    if (value.state == RecordingSaveState.failed) {
      final detail = value.error == null
          ? <String, Object?>{
              'domain': 'storage',
              'source': 'recording_${value.phase.name}',
              'code': 'storage_write_failed',
            }
          : coreErrorFields(value.error!, 'recording_${value.phase.name}');
      if (code != 0) additionalSaveFailures.add(detail);
      // Registration still has no logical/device result. Its failure is an
      // independent persistence fact when an earlier host stop already won.
      choose(
        'recording_save_failure',
        value.phase == RecordingPhase.registration && value.error != null
            ? coreExitCode(value.error!)
            : 74,
        detail,
      );
      io.err('Error: Recording save failed: ${jsonEncode(detail)}');
    }
  }

  void cleanup(CleanupSummary value) {
    if (value.aggregate != CleanupState.succeeded &&
        value.aggregate != CleanupState.notRequired) {
      choose('cleanup_failure', 69, {
        'domain': 'cleanup',
        'code': value.aggregate.code,
      });
      io.err(
        'Error: Recorded cleanup did not succeed: ${jsonEncode(cleanupFields(value))}',
      );
    }
  }

  io.onFailure = () => stop('output_failure', 74);
  stopRequests.onIdleStop = (request) =>
      stop(request.name, request == CliStopRequest.sigint ? 130 : 143);
  stopRequests.onIdleError = (e, s) {
    internal(e, s);
    cancel();
  };
  try {
    if (io.failed) stop('output_failure', 74);
    // Core owns this real forwarding observer. The invocation separately owns
    // the process source, including storage work before and after recording.
    signals = stopRequests.listen(
      (request) =>
          stop(request.name, request == CliStopRequest.sigint ? 130 : 143),
      (Object e, StackTrace s) {
        internal(e, s);
        cancel();
      },
    );
    if (input.verbose) io.err('Diagnostic: recorded datagram admitted.');
    operation = storage.storage.record(
      parameters: parameters,
      appVersion: meshctlVersion,
      createTransport: () => createTransport(input.port),
      subscriptions: [
        if (signals != null)
          RecordingSubscription(
            stage: HostCleanupStage.signalSubscription,
            subscribe: (_) {
              handedOff = true;
              return signals!;
            },
          ),
      ],
    );
    if (cancelRequested) cancel();
    // Attach every observer before the first await. These are bounded terminal
    // observations, without packet streams or a second inbox consumer.
    final observations = [
      operation.prepared.then<void>(saved, onError: internal),
      operation.logical.then<void>(logical, onError: internal),
      operation.logicalSaved.then<void>(saved, onError: internal),
      operation.cleanupDone.then<void>(cleanup, onError: internal),
      operation.cleanupSaved.then<void>(saved, onError: internal),
    ];
    result = await operation.done;
    await Future.wait(observations);
    for (final save in result.saves) {
      saved(save);
    }
    if (result.coordinationFailure != null) {
      unexpected ??= StateError('Recording coordination failed.');
      unexpectedStack ??= StackTrace.current;
    }
  } catch (e, s) {
    internal(e, s);
    cancel();
    if (operation != null) {
      try {
        await operation.done;
      } catch (e, s) {
        internal(e, s);
      }
    }
  } finally {
    // Preparation failure/pre-cancel can leave the plan uninvoked. Only then
    // does the host retain ownership of this real cancellation Future.
    if (!handedOff && signals != null) {
      try {
        await signals.cancel();
      } catch (_) {
        hostFailures.add({
          'domain': 'host',
          'source': 'signalSubscription',
          'code': 'cleanup_failure',
        });
        choose('cleanup_failure', 69, hostFailures.last);
      }
    }
    try {
      await storage.finish();
      if (storage.failed) {
        choose('storage_finalization_failure', 74, storage.failures.first);
      }
    } finally {
      await stopRequests.finish();
    }
    stopRequests.replay(
      (request) =>
          stop(request.name, request == CliStopRequest.sigint ? 130 : 143),
      internal,
    );
    if (stopRequests.failure case final failure?) {
      hostFailures.add(failure);
      choose('cleanup_failure', 69, failure);
    }
    await io.drain();
    if (io.failed) stop('output_failure', 74);
    stopRequests.onIdleStop = null;
    stopRequests.onIdleError = null;
    io.onFailure = null;
  }
  if (unexpected != null) {
    Error.throwWithStackTrace(unexpected!, unexpectedStack!);
  }
  final envelope = <String, Object?>{
    'schemaVersion': 1,
    'command': 'datagram',
    'operation': input.operation,
    if (input.operation == 'listen') 'event': 'end',
    'reason': reason,
    'exitCode': code,
    'failure': failure,
    'result': logicalFields(result?.logical),
    'cleanup': result == null ? null : cleanupFields(result.cleanup),
    'recording': result == null
        ? null
        : {
            'runId': runId,
            'registration': saveFields(result.registration),
            'logical': saveFields(result.logicalSave),
            'cleanup': saveFields(result.cleanupSave),
            'coordinationFailure': failureSummaryFields(
              result.coordinationFailure,
            ),
            'fullySuccessful': result.fullySuccessful,
            'saves': result.saves.map(saveFields).toList(),
          },
    'maintenance': storage.maintenance,
    'storageClose': storage.closeResult,
    'signalCleanup': stopRequests.fields,
    'additionalFailures': [
      ...additionalSaveFailures,
      ...hostFailures,
      ...storage.failures,
    ],
  };
  for (final f in storage.failures) {
    io.err('Error: Storage finalization failed: ${jsonEncode(f)}');
  }
  io.out(
    input.json
        ? jsonEncode(envelope)
        : 'datagram ${input.operation}: ${safeText(jsonEncode(envelope))}',
  );
  await io.drain();
  return code == 0 && io.failed ? 74 : code;
}
