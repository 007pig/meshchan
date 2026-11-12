import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/ownership.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'database_test.dart' show coreError;
import 'process_support.dart';

class CloseBarrier extends QueryInterceptor {
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<void> close(QueryExecutor inner) async {
    calls++;
    entered.complete();
    await release.future;
    await inner.close();
  }
}

void main() {
  late Directory directory;
  final peers = <Peer>[];
  setUp(
    () =>
        directory = Directory.systemTemp.createTempSync('meshchan-owner-test-'),
  );
  tearDown(() async {
    for (final peer in peers) {
      await peer.dispose();
    }
    peers.clear();
    directory.deleteSync(recursive: true);
  });
  Future<Peer> peer(String mode) async {
    final child = await Peer.start(mode, directory);
    peers.add(child);
    return child;
  }

  Future<void> busyProcess() async {
    final child = await peer('try');
    final report = jsonDecode(await child.line()) as Map;
    expect(report['code'], 'data_directory_busy');
    expect(report['factories'], 0);
    await child.finish();
  }

  test('opening reservation rejects aliases before another executor is created', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var factories = 0;
    final opening = openStorage(
      directory,
      hooks: StorageHooks(
        executorFactory: (file) async {
          factories++;
          entered.complete();
          await release.future;
          return NativeDatabase(file);
        },
      ),
    );
    await entered.future;
    try {
      final alias = Directory('${directory.path}/child/..');
      final link = Link(
        '${directory.parent.path}/${directory.uri.pathSegments.where((s) => s.isNotEmpty).last}-alias',
      );
      link.createSync(directory.path);
      try {
        final caseAlias = Directory(
          p.join(
            directory.parent.path,
            p.basename(directory.path).toUpperCase(),
          ),
        );
        for (final path in [
          directory,
          alias,
          Directory(link.path),
          Directory('${directory.path}/.'),
          Directory(p.relative(directory.path)),
          if (caseAlias.existsSync() &&
              FileSystemEntity.identicalSync(caseAlias.path, directory.path))
            caseAlias,
        ]) {
          await expectLater(
            openStorage(path),
            throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
          );
        }
      } finally {
        link.deleteSync();
      }
      await busyProcess();
      expect(factories, 1);
    } finally {
      release.complete();
      await (await opening).close();
    }
    final next = await CoreStorage.open(dataDirectory: directory);
    await next.close();
  });

  test(
    'different isolates compete through OS flock; a loser cannot release owner',
    () async {
      final storage = await CoreStorage.open(dataDirectory: directory);
      try {
        expect(
          File('${directory.path}/$ownershipFileName').statSync().mode & 0x1ff,
          0x180,
        );
        await expectLater(
          CoreStorage.open(dataDirectory: directory),
          throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
        );
        final path = directory.path;
        final code = await Isolate.run(() async {
          try {
            final other = await CoreStorage.open(
              dataDirectory: Directory(path),
            );
            await other.close();
            return 'unexpected';
          } on CoreException catch (e) {
            return e.code.code;
          }
        });
        expect(code, 'data_directory_busy');
        await busyProcess();
      } finally {
        await storage.close();
      }
    },
  );

  test(
    'competing creation through directory aliases produces one owner',
    () async {
      final link = Link('${directory.path}-alias')..createSync(directory.path);
      final target = Directory('${directory.path}/new/data');
      final attempts = await Future.wait([
        CoreStorage.open(dataDirectory: target)
            .then<Object>((v) => v, onError: (Object e) => e),
        CoreStorage.open(dataDirectory: Directory('${link.path}/new/data'))
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      try {
        expect(attempts.whereType<CoreStorage>(), hasLength(1));
        expect(
          attempts.whereType<CoreException>().single.code,
          CoreErrorCode.dataDirectoryBusy,
        );
      } finally {
        for (final storage in attempts.whereType<CoreStorage>()) {
          await storage.close();
        }
        link.deleteSync();
      }
    },
  );

  test(
    'real executor close and in-flight work retain owner; close is shared',
    () async {
      final barrier = CloseBarrier();
      final storage = await openStorage(
        directory,
        hooks: StorageHooks(
          executorFactory: (file) =>
              NativeDatabase(file).interceptWith(barrier, sticky: false),
        ),
      ) as StorageHandle;
      final workEntered = Completer<void>();
      final workRelease = Completer<void>();
      final work = storage.useDatabase((db) async {
        workEntered.complete();
        await workRelease.future;
        await db.customSelect('SELECT 1').get();
      });
      await workEntered.future;
      final closing = storage.close();
      try {
        expect(identical(closing, storage.close()), isTrue);
        expect(storage.state, StorageState.closing);
        await expectLater(
          storage.useDatabase((db) => db.customSelect('SELECT 1').get()),
          throwsA(coreError(CoreErrorCode.storageReadFailed)),
        );
        expect(barrier.calls, 0);
        await busyProcess();
        workRelease.complete();
        await work;
        await barrier.entered.future;
        await expectLater(
          CoreStorage.open(dataDirectory: directory),
          throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
        );
        await busyProcess();
      } finally {
        if (!workRelease.isCompleted) workRelease.complete();
        if (!barrier.release.isCompleted) barrier.release.complete();
        await work;
        await closing;
      }
      await storage.close();
      expect(barrier.calls, 1);
      final reopened = await CoreStorage.open(dataDirectory: directory);
      await reopened.close();
    },
  );

  for (final ending in ['release', 'crash']) {
    test(
      'cross-process ownership survives duplicate/marker operations then $ending',
      () async {
        final owner = await peer('hold');
        expect(await owner.line(), 'ready');
        await busyProcess();
        await expectLater(
          CoreStorage.open(dataDirectory: directory),
          throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
        );
        await busyProcess(); // A third independent open after an in-process loser.
        File('${directory.path}/$markerFileName').deleteSync();
        await busyProcess();
        owner.send(ending);
        if (ending == 'release') expect(await owner.line(), 'closed');
        await owner.finish(ending == 'crash' ? 23 : 0);
        File('${directory.path}/$markerFileName')
            .writeAsStringSync('{"pid":1,"stale":true}');
        final storage = await CoreStorage.open(dataDirectory: directory);
        await storage.close();
      },
    );
  }

  for (final mode in ['fail-close', 'fail-open-close']) {
    test(
      '$mode retains ownership and safe primary failure until process exit',
      () async {
        final child = await peer(mode);
        final report = jsonDecode(await child.line()) as Map;
        expect(
          report['code'],
          mode == 'fail-close' ? 'storage_write_failed' : 'database_corrupt',
        );
        expect(report['unconfirmed'], isTrue);
        if (mode == 'fail-close') {
          expect(report['state'], 'closeUnconfirmed');
          expect(report['draftErrors'], [
            'storage_read_failed',
            'storage_write_failed',
          ]);
          expect(report['profileSettingsErrors'], [
            'storage_read_failed',
            'storage_write_failed',
            'storage_read_failed',
            'storage_write_failed',
            'storage_write_failed',
            'storage_read_failed',
          ]);
        }
        expect(await child.line(), 'data_directory_busy');
        await busyProcess();
        child.send('release');
        await child.finish();
        final storage = await CoreStorage.open(dataDirectory: directory);
        await storage.close();
      },
    );
  }
}
