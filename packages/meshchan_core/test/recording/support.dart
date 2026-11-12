import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/recording/run_store.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

export '../../../meshcore_link/test/support/fake_companion_transport.dart';
export '../storage/database_test.dart' show coreError, representation;
export '../storage/fixtures.dart' show instant, fixtureId;

const budgets = ProfileBudgets(taskTimeoutSeconds: 5);
EffectiveParameters input(
  DiagnosticOperation operation, {
  int entries = 8,
  int? filter,
  int timeout = 5,
}) {
  final b = ProfileBudgets(taskTimeoutSeconds: timeout);
  final route = ProfileRoute(routeDescriptor: 0xff);
  const endpoints = ProfileTestEndpoints(
    localTestId: 0x12345678,
    peerTestId: 0x87654321,
  );
  return EffectiveParameters(
    profileId: null,
    parameters: switch (operation) {
      DiagnosticOperation.send => SendProfileParameters(
        budgets: b,
        sendChannelIndex: 3,
        dataType: 99,
        route: route,
      ),
      DiagnosticOperation.listen => ListenProfileParameters(
        budgets: b,
        receiveChannelIndex: 2,
        dataType: filter,
        listenDurationSeconds: 3,
        maxEntries: entries,
      ),
      DiagnosticOperation.ping => PingProfileParameters(
        budgets: b,
        sendChannelIndex: 3,
        receiveChannelIndex: 2,
        route: route,
        endpoints: endpoints,
        responseTimeoutSeconds: 2,
        maxEntries: entries,
      ),
      DiagnosticOperation.respond => RespondProfileParameters(
        budgets: b,
        sendChannelIndex: 3,
        receiveChannelIndex: 2,
        route: route,
        endpoints: endpoints,
        listenDurationSeconds: 3,
        maxEntries: entries,
      ),
    },
    content:
        operation == DiagnosticOperation.send ||
            operation == DiagnosticOperation.ping
        ? [0, 128, 255]
        : null,
  );
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 1000 && !predicate(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Expected a controlled asynchronous boundary to settle.',
  );
}

Future<void> turns([int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<DiagnosticRun> stored(StorageHandle storage, LocalId id) =>
    storage.useDatabase((db) => readRun(db, id));

Uint8List deviceInfo() =>
    Uint8List(82)..setRange(0, 8, [0x0d, 14, 25, 8, 0x78, 0x56, 0x34, 0x12]);
Uint8List selfInfo() => Uint8List.fromList([
  0x05,
  1,
  20,
  22,
  ...List.filled(44, 0xab),
  0x95,
  0x44,
  0x0d,
  0,
  0x90,
  0xd0,
  3,
  0,
  11,
  7,
  ...utf8.encode('PRIVATE NODE'),
]);
List<int> channelFrame(List<int> payload, {int type = 99, int channel = 2}) => [
  0x1b,
  0,
  0,
  0,
  channel,
  0xff,
  type & 255,
  type >> 8,
  payload.length,
  ...payload,
];

MeshchanDiagnosticMessage diagnostic({
  required DiagnosticKind kind,
  Uint8List? nonce,
  int sender = 0x87654321,
  int target = 0x12345678,
}) => MeshchanDiagnosticMessage(
  kind: kind,
  runNonce: nonce ?? Uint8List(16),
  requestId: 1,
  senderTestId: sender,
  targetTestId: target,
  content: Uint8List.fromList([0, 128, 255]),
);

// Subscription cancellation, with a real stream and a controlled cancel Future.
StreamSubscription<Object?> cancellation(Future<void> Function() cancel) =>
    StreamController<Object?>(onCancel: cancel).stream.listen((_) {});
