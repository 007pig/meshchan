import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';

import 'device_fixture.dart';

EffectiveParameterRequest diagnosticRequest({bool respond = false}) => respond
    ? RespondParameterRequest(
        overrides: RespondOverrides(
          budgets: const BudgetOverrides(taskTimeoutSeconds: 10),
          sendChannelIndex: 3,
          receiveChannelIndex: 2,
          route: RouteOverrides(routeDescriptor: 255),
          endpoints: const EndpointOverrides(localTestId: 1, peerTestId: 2),
          listenDurationSeconds: 2,
        ),
      )
    : PingParameterRequest(
        content: const [0, 128, 255],
        overrides: PingOverrides(
          budgets: const BudgetOverrides(taskTimeoutSeconds: 10),
          sendChannelIndex: 3,
          receiveChannelIndex: 2,
          route: RouteOverrides(routeDescriptor: 255),
          endpoints: const EndpointOverrides(localTestId: 1, peerTestId: 2),
          responseTimeoutSeconds: 2,
        ),
      );

enum DiagnosticControl { releaseResolve, releaseCleanup }

final class DiagnosticReady {
  const DiagnosticReady(this.port);
  final SendPort port;
}

final class DiagnosticFact {
  const DiagnosticFact(this.name);
  final String name;
}

/// Test-only dependency plan. Product bootstrap has no path to this entry.
void Function(WorkerBootstrap) diagnosticFixtureEntry(
  SendPort observer, {
  bool holdResolve = false,
  bool holdCleanup = false,
  bool failCleanup = false,
  bool cancelBeforePrepared = false,
  bool delayAck = false,
}) => (b) {
  final commands = ReceivePort();
  final resolving = Completer<void>(), cleanup = Completer<void>();
  final held = <WorkerEvent>[];
  bool delayed = false;
  void fact(String name) => observer.send(DiagnosticFact(name));
  final dispatcher = WorkerDispatcher(
    b,
    finish: commands.close,
    send: (e) {
      if (delayAck && !delayed && e is RequestReply && e.value is Accepted) {
        delayed = true;
        held.add(e);
      } else {
        b.events.send(e);
      }
    },
    openStorage: (d) async => _Storage(
      await CoreStorage.open(dataDirectory: d),
      resolveBarrier: holdResolve ? resolving.future : null,
      cancelBeforePrepared: cancelBeforePrepared,
      fact: fact,
    ),
    createDiagnosticTransport: (path) {
      if (path != ' explicit fixture ') {
        throw StateError('Exact input was changed');
      }
      fact('factory');
      return DiagnosticFixtureTransport(
        closeBarrier: holdCleanup ? cleanup : null,
        failClose: failCleanup,
      );
    },
    createCheckTransport: (_) => DeviceFixtureTransport(),
    enumeratePorts: () => const [],
  );
  commands.listen((message) {
    if (message == DiagnosticControl.releaseResolve) {
      if (!resolving.isCompleted) resolving.complete();
    } else if (message == DiagnosticControl.releaseCleanup) {
      if (!cleanup.isCompleted) cleanup.complete();
      for (final e in held) {
        b.events.send(e);
      }
      held.clear();
    } else {
      dispatcher.receive(message);
    }
  });
  observer.send(DiagnosticReady(commands.sendPort));
  b.events.send(WorkerHello(b.generation, commands.sendPort));
  dispatcher.start();
};

final class _Storage implements CoreStorage {
  _Storage(
    this.inner, {
    this.resolveBarrier,
    required this.cancelBeforePrepared,
    required this.fact,
  });
  final CoreStorage inner;
  final Future<void>? resolveBarrier;
  final bool cancelBeforePrepared;
  final void Function(String) fact;
  @override
  StorageState get state => inner.state;
  @override
  DiagnosticHistory get history => inner.history;
  @override
  DraftRepository get drafts => inner.drafts;
  @override
  ProfileRepository get profiles => inner.profiles;
  @override
  SettingsRepository get settings => inner.settings;
  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest request,
  ) async {
    fact('resolving');
    await resolveBarrier;
    return inner.resolveParameters(request);
  }

  @override
  RecordedOperation record({
    required EffectiveParameters parameters,
    required String appVersion,
    required CompanionTransport Function() createTransport,
    List<RecordingSubscription> subscriptions = const [],
  }) {
    fact('record');
    final op = inner.record(
      parameters: parameters,
      appVersion: appVersion,
      createTransport: createTransport,
      subscriptions: subscriptions,
    );
    if (cancelBeforePrepared) {
      op.cancel().ignore();
    }
    return op;
  }

  @override
  Future<void> close() => inner.close();
}

/// Fixed fixture frames; correlation and response construction use public APIs.
class DiagnosticFixtureTransport extends DeviceFixtureTransport {
  DiagnosticFixtureTransport({super.closeBarrier, super.failClose});
  Uint8List? pending;
  bool responding = false, firstRead = true;
  @override
  Future<void> sendFrame(Uint8List bytes) async {
    sent.add(Uint8List.fromList(bytes));
    switch (bytes[0]) {
      case 0x16:
        received.add(fixtureDeviceInfo());
      case 0x01:
        received.add(fixtureSelfInfo());
      case 0x0a:
        if (pending != null) {
          received.add(pending!);
          pending = null;
        } else if (responding && firstRead) {
          firstRead = false;
          received.add(
            channel(
              encodeDiagnosticPayload(
                MeshchanDiagnosticMessage(
                  kind: DiagnosticKind.ping,
                  runNonce: Uint8List(16),
                  requestId: 1,
                  senderTestId: 2,
                  targetTestId: 1,
                  content: Uint8List(0),
                ),
              ),
            ),
          );
        } else {
          received.add(Uint8List.fromList([0x0a]));
        }
      case 0x3e:
        final message = decodeDiagnosticPayload(
          Uint8List.fromList(bytes.sublist(5)),
        ).message!;
        received.add(Uint8List.fromList([0]));
        if (message.kind == DiagnosticKind.ping) {
          pending = channel(
            encodeDiagnosticPayload(
              MeshchanDiagnosticMessage(
                kind: DiagnosticKind.pong,
                runNonce: message.runNonce,
                requestId: message.requestId,
                senderTestId: message.targetTestId,
                targetTestId: message.senderTestId,
                content: message.content,
              ),
            ),
          );
          received.add(Uint8List.fromList([0x83]));
        }
    }
  }

  Uint8List channel(Uint8List payload) => Uint8List.fromList([
    0x1b,
    0,
    0,
    0,
    2,
    255,
    255,
    255,
    payload.length,
    ...payload,
  ]);
}
