import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/ownership.dart';
import 'package:meshchan_core/src/storage/preflight.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'database_test.dart' show coreError;
import 'process_support.dart';

Map<String, List<int>?> bytes(String path) => {
  for (final suffix in sqliteSuffixes)
    suffix: File('$path$suffix').existsSync()
        ? File('$path$suffix').readAsBytesSync()
        : null,
};

void main() {
  late Directory directory;
  late String path;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meshchan-preflight-test-');
    path = '${directory.path}/$databaseFileName';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> rejected(CoreErrorCode category) async {
    final before = bytes(path);
    var factories = 0;
    await expectLater(
      openStorage(
        directory,
        hooks: StorageHooks(
          executorFactory: (_) {
            factories++;
            throw StateError('executor should not run');
          },
        ),
      ),
      throwsA(coreError(category)),
    );
    expect(factories, 0);
    expect(bytes(path), before);
  }

  for (final fixture in [
    'future',
    'random',
    'unrecognized-zero',
    'reserved-looking-zero',
    'missing-table',
    'missing-index',
  ]) {
    test(
      'reject $fixture before executor and preserve main/sidecars',
      () async {
        if (fixture == 'random') {
          File(path).writeAsStringSync('private content, not SQLite');
          File('$path-wal').writeAsStringSync('unrecognized private WAL');
          File('$path-shm').writeAsBytesSync([1, 2, 3]);
          File('$path-journal').writeAsBytesSync([4, 5, 6]);
        } else if (fixture.startsWith('missing-')) {
          final storage = await CoreStorage.open(dataDirectory: directory);
          await storage.close();
          final db = sqlite3.open(path);
          try {
            db.execute(
              fixture == 'missing-table'
                  ? 'DROP TABLE stored_drafts'
                  : 'DROP INDEX runs_prepared',
            );
          } finally {
            db.close();
          }
        } else {
          final db = sqlite3.open(path);
          try {
            if (fixture == 'future') {
              db.userVersion = 2;
            } else {
              db.execute(
                fixture == 'reserved-looking-zero'
                    ? 'CREATE TABLE sqliteXalien (secret TEXT)'
                    : 'CREATE TABLE unrelated (secret TEXT)',
              );
            }
          } finally {
            db.close();
          }
        }
        await rejected(
          fixture == 'future'
              ? CoreErrorCode.unsupportedDatabaseVersion
              : CoreErrorCode.databaseCorrupt,
        );
      },
    );
  }

  test(
    'empty existing version zero is retryable, not an alien schema',
    () async {
      final db = sqlite3.open(path);
      db.execute('PRAGMA user_version = 0');
      db.close();
      final storage = await CoreStorage.open(dataDirectory: directory);
      await storage.close();
    },
  );

  for (final journal in ['wal', 'journal']) {
    test(
      'isolation preserves rejected real $journal, including committed WAL version',
      () async {
        final child = await Peer.start(journal, directory);
        try {
          expect(await child.line(), 'ready');
          child.send('crash');
          await child.finish(23);
          expect(
            File('$path-${journal == 'wal' ? 'wal' : 'journal'}').lengthSync(),
            greaterThan(0),
          );
          if (journal == 'wal') {
            // The main header is still 0; committed version 2 lives in the WAL.
            final header = File(path).readAsBytesSync();
            expect(
              header.length < 64 || header.sublist(60, 64).every((v) => v == 0),
              isTrue,
            );
          } else {
            expect(File('$path-journal').readAsBytesSync().take(8), [
              0xd9,
              0xd5,
              0x05,
              0xf9,
              0x20,
              0xa1,
              0x63,
              0xd7,
            ]);
          }
          await rejected(CoreErrorCode.unsupportedDatabaseVersion);
        } finally {
          await child.dispose();
        }
      },
    );
  }

  test(
    'valid WAL sidecars are supported and accepted data is visible',
    () async {
      final storage = await CoreStorage.open(dataDirectory: directory);
      await storage.close();
      final child = await Peer.start('wal-supported', directory);
      try {
        expect(await child.line(), 'ready');
        child.send('crash');
        await child.finish(23);
        final opened = await CoreStorage.open(dataDirectory: directory);
        await (opened as StorageHandle).useDatabase((database) async {
          expect(
            (await database.select(database.storedDrafts).get()).single.title,
            'WAL',
          );
        });
        await opened.close();
      } finally {
        await child.dispose();
      }
    },
  );

  test('invalid host input and I/O failures stay safe and do not masquerade as busy', () async {
    await expectLater(
      CoreStorage.open(dataDirectory: Directory('')),
      throwsA(coreError(CoreErrorCode.invalidInput)),
    );
    final file = File('${directory.path}/ordinary-file')
      ..writeAsStringSync('secret');
    await expectLater(
      CoreStorage.open(dataDirectory: Directory(file.path)),
      throwsA(coreError(CoreErrorCode.storageOpenFailed)),
    );
    try {
      await openStorage(
        directory,
        hooks: StorageHooks(
          executorFactory: (_) =>
              throw const FileSystemException('SECRET path payload'),
        ),
      );
      fail('Expected open failure');
    } on CoreException catch (e) {
      expect(e.code, CoreErrorCode.storageOpenFailed);
      expect(e.toString(), 'CoreException(storage_open_failed)');
    }
    final storage = await CoreStorage.open(dataDirectory: directory);
    await storage.close();
  });

  for (final resource in [
    databaseFileName,
    ownershipFileName,
    '$databaseFileName-wal',
  ]) {
    test('reject resource symlink $resource outside owned directory', () async {
      final outside = directory.parent.createTempSync('meshchan-outside-test-');
      try {
        final target = File('${outside.path}/target')
          ..writeAsStringSync('private');
        Link('${directory.path}/$resource').createSync(target.path);
        await expectLater(
          CoreStorage.open(dataDirectory: directory),
          throwsA(coreError(CoreErrorCode.storageOpenFailed)),
        );
        expect(target.readAsStringSync(), 'private');
      } finally {
        outside.deleteSync(recursive: true);
      }
    });
    test(
      'reject resource hard link $resource outside owned directory',
      () async {
        final outside = directory.parent.createTempSync(
          'meshchan-hardlink-test-',
        );
        try {
          final target = File('${outside.path}/target')
            ..writeAsStringSync('private');
          final linked = Process.runSync('/bin/ln', [
            target.path,
            '${directory.path}/$resource',
          ]);
          expect(linked.exitCode, 0, reason: '${linked.stderr}');
          await expectLater(
            CoreStorage.open(dataDirectory: directory),
            throwsA(coreError(CoreErrorCode.storageOpenFailed)),
          );
          expect(target.readAsStringSync(), 'private');
        } finally {
          outside.deleteSync(recursive: true);
        }
      },
    );
  }
}
