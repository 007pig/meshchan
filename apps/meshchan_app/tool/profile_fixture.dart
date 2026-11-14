import 'package:meshchan_core/meshchan_core.dart';

ProfileContent fixtureProfile(
  DiagnosticOperation op, {
  String name = '  中文🙂\n',
  String? hint = 'fixture hint\n',
}) {
  const b = ProfileBudgets(
    taskTimeoutSeconds: 7,
    requestTimeoutSeconds: 3,
    initializationTimeoutSeconds: 9,
    startupDelayMilliseconds: 2,
  );
  final route = ProfileRoute(routeDescriptor: 2, path: [7, 9]);
  const endpoints = ProfileTestEndpoints(
    localTestId: 0xffffffff,
    peerTestId: 12,
  );
  return ProfileContent(
    name: name,
    portHint: hint,
    parameters: switch (op) {
      DiagnosticOperation.send => SendProfileParameters(
        budgets: b,
        sendChannelIndex: 0,
        route: route,
        dataType: 0xffff,
      ),
      DiagnosticOperation.listen => const ListenProfileParameters(
        budgets: b,
        receiveChannelIndex: 255,
        dataType: 0,
        listenDurationSeconds: 6,
        maxEntries: 13,
      ),
      DiagnosticOperation.ping => PingProfileParameters(
        budgets: b,
        sendChannelIndex: 0,
        receiveChannelIndex: 255,
        route: route,
        endpoints: endpoints,
        responseTimeoutSeconds: 4,
        maxEntries: 13,
      ),
      DiagnosticOperation.respond => RespondProfileParameters(
        budgets: b,
        sendChannelIndex: 0,
        receiveChannelIndex: 255,
        route: route,
        endpoints: endpoints,
        listenDurationSeconds: 6,
        maxEntries: 13,
        maxResponses: 2,
      ),
    },
  );
}
