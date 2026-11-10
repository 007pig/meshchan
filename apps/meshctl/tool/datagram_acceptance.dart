import 'dart:convert';
import 'dart:io';

import '../test/support/datagram_acceptance_scenarios.dart';

/// Development-only fixed synthetic acceptance; never reads arguments or stdin.
Future<void> main() async {
  final scenarios = <Map<String, Object?>>[];
  for (final id in datagramAcceptanceIds) {
    try {
      scenarios.add((await runDatagramAcceptanceScenario(id)).toJson());
    } catch (error) {
      scenarios.add({'id': id, 'passed': false, 'cliExitCode': null});
      stderr.writeln('$id: $error');
      break;
    }
  }
  final failed = scenarios.where((s) => s['passed'] != true).length;
  final complete = scenarios.length == datagramAcceptanceIds.length;
  stdout.writeln(
    jsonEncode({
      'probe': datagramAcceptanceProbe,
      'schemaVersion': 1,
      'scenarios': scenarios,
      'completed': scenarios.length,
      'passed': scenarios.length - failed,
      'failed': failed,
    }),
  );
  if (!complete || failed != 0) exitCode = 1;
}
