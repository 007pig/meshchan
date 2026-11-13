import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'support/storage_control_worker.dart';

void main() {
  for (final barrier in StorageBarrier.values) {
    test(
      'first shutdown after $barrier timeout drains the real owner',
      () async {
        await _timeoutCase(barrier);
      },
    );
  }
  test('first shutdown waits for late hello after its own deadline', () async {
    await _timeoutCase(
      StorageBarrier.handshake,
      helloAfterShutdownDeadline: true,
    );
  });
}

Future<void> _timeoutCase(
  StorageBarrier barrier, {
  bool helloAfterShutdownDeadline = false,
}) async {
  final directory = Directory.systemTemp.createTempSync(
    'meshchan-timeout-review-',
  );
  final seed = await CoreStorage.open(dataDirectory: directory);
  final draft = await seed.drafts.create(
    DraftContent(title: runtimeFixtureTitle, body: runtimeFixtureBody),
  );
  await seed.close();
  final observer = ReceivePort();
  final events = StreamController<Object?>.broadcast(sync: true);
  final seen = <Object?>[];
  final subscription = observer.listen((event) {
    seen.add(event);
    events.add(event);
  });
  Future<T> wait<T>(bool Function(T) predicate) async {
    for (final event in seen.whereType<T>()) {
      if (predicate(event)) return event;
    }
    return await events.stream
            .where((e) => e is T && predicate(e))
            .first
            .timeout(const Duration(seconds: 10))
        as T;
  }

  var verified = false;
  StorageControlReady? control;
  addTearDown(() async {
    try {
      control?.commands.send(StorageControl.cleanup);
      await wait<StorageCounts>((e) => e.closed);
      if (verified) directory.deleteSync(recursive: true);
    } finally {
      await subscription.cancel();
      observer.close();
      await events.close();
    }
  });
  final runtime = RuntimeController(
    resolveDirectory: () async => directory.path,
    entry: storageControlEntry(observer.sendPort, barrier),
    deadline: const Duration(seconds: 2),
  );
  final starting = runtime.start();
  control = await wait<StorageControlReady>((_) => true);
  await wait<StorageStage>((e) => e.name == 'owner_held');
  if (barrier == StorageBarrier.read) {
    await starting;
    final read = runtime.refresh();
    final observed = expectLater(
      read,
      throwsA(
        isA<RuntimeFault>().having(
          (e) => e.host,
          'timed-out read',
          CoordinationFault.requestUnknown,
        ),
      ),
    );
    await wait<StorageStage>((e) => e.name == 'read_pending');
    await observed;
  } else {
    await starting;
  }
  expect(runtime.snapshot.error!.host, CoordinationFault.requestUnknown);
  expect(runtime.snapshot.owner, OwnerFact.unknown);
  await expectLater(runtime.refresh(), throwsA(isA<RuntimeFault>()));
  await expectLater(
    CoreStorage.open(dataDirectory: directory),
    throwsA(
      isA<CoreException>().having(
        (e) => e.code,
        'held real owner',
        CoreErrorCode.dataDirectoryBusy,
      ),
    ),
  );

  final closing = runtime.shutdown();
  expect(identical(closing, runtime.shutdown()), true);
  if (helloAfterShutdownDeadline) {
    expect((await closing).canExit, false);
  } else if (barrier != StorageBarrier.handshake) {
    // A real open/read remains pending, but the production dispatcher must
    // receive the shutdown intent before that work is released.
    await wait<StorageStage>((e) => e.name == 'shutdown_received');
  }
  control.commands.send(StorageControl.release);
  if (helloAfterShutdownDeadline) {
    await runtime.changes.drain<void>().timeout(const Duration(seconds: 10));
  }
  final result = await runtime.shutdown();
  expect(result.canExit, true);
  expect(result.workerWasSpawned, true);
  expect(result.workerExited, true);
  expect(result.resourcesReleased, true);
  expect(runtime.snapshot.owner, OwnerFact.released);
  expect(runtime.pendingCount, 0);
  expect(runtime.openPortCount, 0);
  final counts = await wait<StorageCounts>((e) => e.closed);
  expect(counts.opens, 1);
  expect(counts.closes, 1);
  expect(counts.shutdowns, 1);
  expect(counts.reads, barrier == StorageBarrier.read ? 1 : 0);
  final reopened = await CoreStorage.open(dataDirectory: directory);
  final saved = await reopened.drafts.read(draft.id);
  expect(saved.revision, draft.revision);
  expect(saved.body, runtimeFixtureBody);
  await reopened.close();
  verified = true;
}
