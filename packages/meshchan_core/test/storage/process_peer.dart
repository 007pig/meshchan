// Controlled process fixture, never a product entry point.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/ownership.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:sqlite3/sqlite3.dart';

class RefuseClose extends QueryInterceptor {
  @override
  Future<void> close(QueryExecutor inner) async =>
      throw StateError('private close failure');
}

Future<void> main(List<String> args) async {
  final mode = args[0];
  final directory = Directory(args[1]);
  if (mode == 'wal' || mode == 'wal-supported' || mode == 'journal') {
    final db = sqlite3.open('${directory.path}/$databaseFileName');
    if (mode.startsWith('wal')) {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA wal_autocheckpoint = 0');
      if (mode == 'wal') {
        db.userVersion = 2;
      } else {
        db.execute(
          "INSERT INTO stored_drafts VALUES ('00000000000000000000000000000001', 'WAL', '', 1, 1, 1)",
        );
      }
    } else {
      db.userVersion = 2;
      db.execute('CREATE TABLE foreign_data (value BLOB)');
      db.execute('INSERT INTO foreign_data VALUES (zeroblob(262144))');
      db.execute('PRAGMA cache_size = 5');
      db.execute('BEGIN IMMEDIATE');
      db.execute('UPDATE foreign_data SET value = randomblob(262144)');
    }
    stdout.writeln('ready');
    await stdout.flush();
    await stdin.first;
    exit(23); // Deliberately skip SQLite close/checkpoint/rollback.
  }
  var factories = 0;
  final failedClose = mode == 'fail-close' || mode == 'fail-open-close';
  try {
    final storage = await openStorage(
      directory,
      hooks: StorageHooks(
        executorFactory: (file) {
          factories++;
          final native = NativeDatabase(file);
          return failedClose
              ? native.interceptWith(RefuseClose(), sticky: false)
              : native;
        },
        afterCreate: mode == 'fail-open-close'
            ? () => throw const CoreException(CoreErrorCode.databaseCorrupt)
            : null,
      ),
    );
    if (mode == 'try') {
      await storage.close();
      stdout.writeln(jsonEncode({'code': 'opened', 'factories': factories}));
      return;
    }
    if (mode == 'fail-close') {
      final drafts = storage.drafts;
      try {
        await storage.close();
      } on CoreException catch (e) {
        final rejected = <String>[];
        for (final action in [
          () => drafts.list(),
          () => drafts.create(const DraftContent()),
        ]) {
          try {
            await action();
            rejected.add('unexpected_success');
          } on CoreException catch (failure) {
            rejected.add(failure.code.code);
          }
        }
        stdout.writeln(
          jsonEncode({
            'code': e.code.code,
            'unconfirmed': e.cleanupUnconfirmed,
            'state': storage.state.name,
            'draftErrors': rejected,
          }),
        );
      }
      try {
        await CoreStorage.open(dataDirectory: directory);
      } on CoreException catch (e) {
        stdout.writeln(e.code.code);
      }
      await stdout.flush();
      await stdin.first;
      return;
    }
    stdout.writeln('ready');
    await stdout.flush();
    final command = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    if (command == 'crash') exit(23);
    await storage.close();
    stdout.writeln('closed');
  } on CoreException catch (e) {
    stdout.writeln(
      jsonEncode({
        'code': e.code.code,
        'factories': factories,
        'unconfirmed': e.cleanupUnconfirmed,
      }),
    );
    if (mode == 'fail-open-close') {
      try {
        await CoreStorage.open(dataDirectory: directory);
      } on CoreException catch (e) {
        stdout.writeln(e.code.code);
      }
      await stdout.flush();
      await stdin.first;
    }
  }
}
