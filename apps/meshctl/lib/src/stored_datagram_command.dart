import 'dart:convert';
import 'dart:typed_data';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart' show CompanionTransport;

import 'business_storage.dart';
import 'cli_display.dart';
import 'cli_output.dart';
import 'datagram_command.dart';
import 'datagram_options.dart';
import 'datagram_signals.dart';
import 'recorded_datagram_command.dart';
import 'session_command.dart';

/// The host owns cancellation across open, resolution, execution and close.
/// Runners finalize this same owner before writing their unique final object.
Future<int> runStoredDatagram(
  DatagramInput input,
  CliOutput io,
  Future<CoreStorage> Function() open,
  CompanionTransport Function(String) createTransport,
  Stream<CliStopRequest>? stopRequests, {
  Duration Function()? elapsed,
  Uint8List Function()? nonceFactory,
}) async {
  final signals = DatagramSignals(stopRequests);
  BusinessStorage? life;
  EffectiveParameters? effective;
  CoreException? failure;
  var failureIsPrimary = false;
  var source = 'open';
  io.onFailure = signals.outputFailed;
  try {
    if (io.failed) signals.outputFailed();
    signals.start();
    try {
      if (!signals.stopped && !io.failed) {
        life = BusinessStorage(await open());
        if (!signals.stopped && !io.failed) {
          source = 'resolution';
          effective = await life.storage.resolveParameters(input.request);
        }
      }
    } on CoreException catch (error) {
      failure = error;
      // Freeze observation order now; later signals during cleanup must not
      // replace an earlier admission failure, or vice versa.
      failureIsPrimary = signals.firstReason == null;
    }
    if (effective != null && !signals.stopped && !io.failed) {
      if (input.record) {
        return await runRecordedDatagram(
          input,
          effective,
          life!,
          io,
          createTransport,
          signals,
        );
      }
      return await runDatagramCommand(
        DatagramOptions.effective(input, effective),
        io,
        createTransport,
        signals,
        elapsed: elapsed,
        nonceFactory: nonceFactory,
        storage: life,
      );
    }
    // Opening/resolution cannot be interrupted. Wait for the admitted Future,
    // then close its returned handle without admitting device/recording work.
    await life?.finish();
    await signals.finish();
    signals.rethrowError();
    await io.drain();
    final fields = failure == null ? null : coreErrorFields(failure, source);
    final external = signals.firstReason;
    final code = failureIsPrimary
        ? coreExitCode(failure!)
        : external != null
        ? switch (external) {
            'sigint' => 130,
            'sigterm' => 143,
            _ => 74,
          }
        : io.failed || (life?.failed ?? false)
        ? 74
        : signals.failure != null
        ? 69
        : 0;
    final reason = failureIsPrimary
        ? 'business_failure'
        : external ??
              (io.failed
                  ? 'output_failure'
                  : life?.failed == true
                  ? 'storage_finalization_failure'
                  : signals.failure != null
                  ? 'cleanup_failure'
                  : 'completed');
    if (fields != null) {
      io.err('Error: Business storage failed: ${jsonEncode(fields)}');
    }
    final envelope = {
      'schemaVersion': 1,
      'command': 'datagram',
      'operation': input.operation,
      if (input.operation == 'listen') 'event': 'end',
      'reason': reason,
      'exitCode': code,
      'failure': failureIsPrimary ? fields : null,
      'result': null,
      'cleanup': {
        'state': 'notRequired',
        'failureCount': 0,
        'failures': const [],
      },
      if (input.record) 'recording': null,
      'maintenance': life?.maintenance,
      'storageClose': life?.closeResult,
      'signalCleanup': signals.fields,
      'additionalFailures': [
        if (!failureIsPrimary && fields != null) fields,
        ...?life?.failures,
        if (signals.failure != null) signals.failure,
      ],
    };
    io.out(
      input.json
          ? jsonEncode(envelope)
          : 'datagram ${input.operation}: ${safeText(jsonEncode(envelope))}',
    );
    await io.drain();
    return code == 0 && io.failed ? 74 : code;
  } finally {
    try {
      await life?.finish();
    } finally {
      await signals.finish();
      io.onFailure = null;
    }
  }
}
