import 'package:test/test.dart';

import 'support/datagram_acceptance_scenarios.dart';

void main() {
  for (final id in datagramAcceptanceIds) {
    test('serial datagram acceptance: $id', () async {
      await runDatagramAcceptanceScenario(id);
    });
  }
}
