import 'dart:async';
import 'dart:io';

import 'package:meshcore_link/meshcore_link.dart';

import '../meshctl.dart';
import 'cli_output.dart';

/// Lazily register supported signals only when a validated invocation subscribes.
Stream<CliStopRequest> processStopRequests({
  bool? windows,
  Stream<ProcessSignal> Function(ProcessSignal)? watch,
}) {
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  late final StreamController<CliStopRequest> controller;
  controller = StreamController<CliStopRequest>(
    onListen: () {
      final signals = {
        ProcessSignal.sigint: CliStopRequest.sigint,
        if (!(windows ?? Platform.isWindows))
          ProcessSignal.sigterm: CliStopRequest.sigterm,
      };
      try {
        for (final entry in signals.entries) {
          subscriptions.add(
            (watch?.call(entry.key) ?? entry.key.watch()).listen(
              (_) => controller.add(entry.value),
              onError: controller.addError,
            ),
          );
        }
      } catch (error, stack) {
        controller.addError(error, stack);
      }
    },
    onCancel: () async {
      Object? failure;
      StackTrace? failureStack;
      await Future.wait([
        for (final subscription in subscriptions)
          Future.sync(subscription.cancel).then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              failure ??= error;
              failureStack ??= stack;
            },
          ),
      ]);
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
    },
  );
  return controller.stream;
}

/// Only the process boundary translates unexpected errors into exit code 70.
Future<int> runProcessCli(
  List<String> arguments, {
  required StringSink output,
  required StringSink error,
  SerialPorts? serialPorts,
  Stream<CliStopRequest>? stopRequests,
}) async {
  try {
    return await runCli(
      arguments,
      output: output,
      error: error,
      serialPorts: serialPorts,
      stopRequests: stopRequests ?? processStopRequests(),
    );
  } catch (_) {
    final io = CliOutput(output, error);
    io.err('Error: Unexpected internal CLI failure.');
    await io.drain();
    return 70;
  }
}
