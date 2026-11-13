import 'dart:async';
import 'dart:isolate';

import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';
import 'package:meshchan_core/meshchan_core.dart';

enum StorageBarrier { open, handshake, read }

enum StorageControl { release, cleanup }

final class StorageControlReady {
  const StorageControlReady(this.commands);
  final SendPort commands;
}

final class StorageStage {
  const StorageStage(this.name);
  final String name;
}

final class StorageCounts {
  const StorageCounts(
    this.opens,
    this.closes,
    this.shutdowns,
    this.reads, {
    this.closed = false,
  });
  final int opens, closes, shutdowns, reads;
  final bool closed;
}

/// Test-only entry factory captures sendable values, never storage or barriers.
void Function(WorkerBootstrap) storageControlEntry(
  SendPort observer,
  StorageBarrier barrier,
) =>
    (bootstrap) => _worker(bootstrap, observer, barrier);

void _worker(
  WorkerBootstrap bootstrap,
  SendPort observer,
  StorageBarrier barrier,
) {
  final commands = ReceivePort();
  final gate = Completer<void>();
  final buffered = <WorkerEvent>[];
  var opens = 0, closes = 0, shutdowns = 0, reads = 0;
  var helloSent = barrier != StorageBarrier.handshake, cleanup = false;
  _Storage? storage;
  ReleaseReport? release;
  late WorkerDispatcher dispatcher;
  StorageCounts counts() => StorageCounts(
    opens,
    closes,
    shutdowns,
    reads,
    closed: storage?.state == StorageState.closed,
  );
  void sendHello() {
    bootstrap.events.send(WorkerHello(bootstrap.generation, commands.sendPort));
    for (final event in buffered) {
      bootstrap.events.send(event);
    }
    buffered.clear();
  }

  void receive(Object? message) {
    if (message is RequestEnvelope && message.request is ShutdownRuntime) {
      shutdowns++;
      observer.send(const StorageStage('shutdown_received'));
    }
    dispatcher.receive(message);
  }

  dispatcher = WorkerDispatcher(
    bootstrap,
    openStorage: (directory) async {
      opens++;
      final inner = await CoreStorage.open(dataDirectory: directory);
      storage = _Storage(
        inner,
        () {
          closes++;
        },
        () async {
          reads++;
          if (barrier == StorageBarrier.read && reads == 1) {
            observer.send(const StorageStage('read_pending'));
            await gate.future;
          }
        },
      );
      observer.send(const StorageStage('owner_held'));
      if (barrier == StorageBarrier.open) await gate.future;
      return storage!;
    },
    send: (event) {
      if (helloSent) {
        bootstrap.events.send(event);
      } else {
        buffered.add(event);
      }
      if (event is ReleaseReport) {
        release = event;
        if (cleanup && event.resourcesReleased) {
          dispatcher.receive(ReleaseAcknowledged(bootstrap.generation));
        }
      }
    },
    finish: () {
      observer.send(counts());
      commands.close();
    },
  );
  commands.listen((message) {
    if (message == StorageControl.release ||
        message == StorageControl.cleanup) {
      if (!gate.isCompleted) gate.complete();
      if (!helloSent) {
        helloSent = true;
        sendHello();
      }
      if (message == StorageControl.cleanup) {
        // Failure-path test reclamation still uses the production close and
        // only acknowledges confirmed release; it cannot force-unlock storage.
        cleanup = true;
        if (shutdowns == 0) {
          receive(
            RequestEnvelope(
              bootstrap.generation,
              1000000,
              const ShutdownRuntime(),
            ),
          );
        } else if (release?.resourcesReleased == true) {
          dispatcher.receive(ReleaseAcknowledged(bootstrap.generation));
        }
      }
      return;
    }
    receive(message);
  });
  observer.send(StorageControlReady(commands.sendPort));
  if (helloSent) sendHello();
  dispatcher.start();
}

final class _Storage implements CoreStorage {
  _Storage(this.inner, this.onClose, Future<void> Function() beforeRead)
    : settings = _Settings(inner.settings, beforeRead);
  final CoreStorage inner;
  final void Function() onClose;
  @override
  final SettingsRepository settings;
  @override
  StorageState get state => inner.state;
  @override
  DraftRepository get drafts => inner.drafts;
  @override
  DiagnosticHistory get history => inner.history;
  @override
  Future<void> close() {
    onClose();
    return inner.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Settings implements SettingsRepository {
  const _Settings(this.inner, this.beforeRead);
  final SettingsRepository inner;
  final Future<void> Function() beforeRead;
  @override
  Future<AppSettings> read() async {
    await beforeRead();
    return inner.read();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
