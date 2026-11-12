import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/meshctl.dart' as cli;

export 'package:meshctl/meshctl.dart' show CliStopRequest;

/// Each virtual-clock scenario owns a real isolated SQLite directory.
Future<int> runCli(
  List<String> arguments, {
  required StringSink output,
  required StringSink error,
  SerialPorts? serialPorts,
  CompanionTransport Function(String)? createTransport,
  Stream<cli.CliStopRequest>? stopRequests,
  Duration Function()? diagnosticElapsed,
  Uint8List Function()? diagnosticNonceFactory,
}) async {
  final directory = Directory.systemTemp.createTempSync('meshctl-regression-');
  try {
    return await cli.runCli(
      ['--data-dir', directory.path, ...arguments],
      output: output,
      error: error,
      serialPorts: serialPorts,
      createTransport: createTransport,
      stopRequests: stopRequests,
      diagnosticElapsed: diagnosticElapsed,
      diagnosticNonceFactory: diagnosticNonceFactory,
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}
