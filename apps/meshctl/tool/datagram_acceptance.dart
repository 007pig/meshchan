import 'dart:convert';
import 'dart:io';

import '../test/support/datagram_acceptance_scenarios.dart';

/// Development-only fixed synthetic acceptance; optional retained synthetic recording fixture.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 &&
            arguments.length != 4 &&
            arguments.length != 5 ||
        arguments.first != '--recording-directory' ||
        (arguments.length >= 4 && arguments[2] != '--expected-version') ||
        (arguments.length == 5 && arguments.last != '--legacy-fixture')) {
      stderr.writeln(
        'Usage: datagram_acceptance --recording-directory <isolated-directory> [--expected-version <version> [--legacy-fixture]]',
      );
      exitCode = 64;
      return;
    }
    try {
      stdout.writeln(
        jsonEncode(
          await runRecordedAcceptance(
            Directory(arguments[1]),
            expectedVersion: arguments.length >= 4
                ? arguments[3]
                : '0.1.0-dev.3',
            legacyFixture: arguments.length == 5,
          ),
        ),
      );
    } catch (error) {
      stderr.writeln('Recording acceptance failed: $error');
      exitCode = 1;
    }
    return;
  }
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
