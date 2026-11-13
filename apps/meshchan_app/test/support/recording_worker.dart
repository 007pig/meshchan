import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

enum HarnessCommand {
  startImmediateCancel,
  startPreparedCancel,
  startActive,
  releaseCleanup,
}

final class HarnessFact {
  const HarnessFact(this.name, this.count);
  final String name;
  final int count;
}

/// Test-only entry. Production never imports this file or accepts these commands.
/// Actual storage/transport/Completers are constructed in the worker isolate.
void recordingWorker(WorkerBootstrap bootstrap) {
  final commands = ReceivePort();
  final release = Completer<void>();
  var factories = 0, closes = 0;
  _Storage? storage;
  late WorkerDispatcher dispatcher;
  void report(String name, int count) =>
      bootstrap.events.send(HarnessFact(name, count));
  dispatcher = WorkerDispatcher(
    bootstrap,
    send: (event) {
      bootstrap.events.send(event);
      if (event is SnapshotEvent && event.snapshot.operation?.done == true) {
        report('factories', factories);
        report('closes', closes);
      }
    },
    finish: commands.close,
    openStorage: (directory) async {
      storage = _Storage(await CoreStorage.open(dataDirectory: directory));
      return storage!;
    },
  );
  commands.listen((message) {
    if (message == HarnessCommand.releaseCleanup) {
      release.complete();
      return;
    }
    if (message is HarnessCommand) {
      final immediate = message == HarnessCommand.startImmediateCancel;
      storage!.cancelBeforePrepared =
          message == HarnessCommand.startPreparedCancel;
      final work = dispatcher.startRecording(
        resolve: (storage) {
          // Public resolver also proves the host gate spans asynchronous reads.
          return storage.resolveParameters(
            ListenParameterRequest(
              overrides: const ListenOverrides(
                receiveChannelIndex: 0,
                maxEntries: 2,
                listenDurationSeconds: 10,
                budgets: BudgetOverrides(
                  startupDelayMilliseconds: 0,
                  taskTimeoutSeconds: 15,
                ),
              ),
            ),
          );
        },
        createTransport: () {
          factories++;
          report('factory', factories);
          return _Transport(
            opened: () => report('opened', 1),
            closed: () {
              closes++;
              report('closing', closes);
              return release.future;
            },
          );
        },
      );
      unawaited(
        work.then<void>(
          (_) {},
          onError: (Object _, StackTrace s) {
            report('unexpected', 1);
          },
        ),
      );
      if (immediate) {
        // Gate is already occupied but resolution has not begun. This cannot
        // construct a device even if prepared later becomes ready.
        dispatcher.receive(
          RequestEnvelope(bootstrap.generation, 1, const StopRuntime()),
        );
      }
      return;
    }
    dispatcher.receive(message);
  });
  bootstrap.events.send(WorkerHello(bootstrap.generation, commands.sendPort));
  dispatcher.start();
}

final class _Storage implements CoreStorage {
  _Storage(this.inner);
  final CoreStorage inner;
  bool cancelBeforePrepared = false;
  @override
  StorageState get state => inner.state;
  @override
  DiagnosticHistory get history => inner.history;
  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest request,
  ) => inner.resolveParameters(request);
  @override
  RecordedOperation record({
    required EffectiveParameters parameters,
    required String appVersion,
    required CompanionTransport Function() createTransport,
    List<RecordingSubscription> subscriptions = const [],
  }) {
    final op = inner.record(
      parameters: parameters,
      appVersion: appVersion,
      createTransport: createTransport,
      subscriptions: subscriptions,
    );
    if (cancelBeforePrepared) {
      unawaited(
        op.cancel().then<void>((_) {}, onError: (Object _, StackTrace s) {}),
      );
    }
    return op;
  }

  @override
  Future<void> close() => inner.close();
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

final class _Transport implements CompanionTransport {
  _Transport({required this.opened, required this.closed});
  final void Function() opened;
  final Future<void> Function() closed;
  final _frames = StreamController<Uint8List>();
  @override
  Stream<Uint8List> get frames => _frames.stream;
  @override
  Future<void> open() async {
    opened();
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    // Remain in simulated initialization. Cancellation is real session cleanup.
  }
  @override
  Future<void> close() => closed();
}
