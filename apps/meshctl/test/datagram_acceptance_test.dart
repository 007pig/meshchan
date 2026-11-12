import 'dart:io';

import 'package:test/test.dart';

import 'support/datagram_acceptance_scenarios.dart';

void main() {
  test(
    'recorded serial scenarios commit, close, reopen and safely export',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'meshchan-recorded-test-',
      );
      try {
        await runRecordedAcceptance(directory);
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
  for (final id in datagramAcceptanceIds) {
    test('serial datagram acceptance: $id', () async {
      await runDatagramAcceptanceScenario(id);
    });
  }
}
