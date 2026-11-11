import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../errors.dart';
import 'database.dart';
import 'ownership.dart';
import 'preflight.dart';

/// A host-owned lifecycle. No SQL executor or bypass is exposed by the public
/// entry. Use one handle on its opening isolate; other isolates may call open
/// independently and are arbitrated by the same OS lock.
abstract interface class CoreStorage {
  static Future<CoreStorage> open({required Directory dataDirectory}) =>
      openStorage(dataDirectory);

  StorageState get state;
  Future<void> close();
}

enum StorageState { open, closing, closed, closeUnconfirmed }

/// Package-internal fault seams. The factory is invoked only after ownership
/// and successful preflight. Returned executors transfer close responsibility.
final class StorageHooks {
  const StorageHooks({this.executorFactory, this.afterCreate});
  final FutureOr<QueryExecutor> Function(File file)? executorFactory;
  final FutureOr<void> Function()? afterCreate;
}

// Strongly retain ambiguous failures, including their native connections. Never
// silently free their reservation or rely on GC/finalizers as close evidence.
final _quarantined = <Object>[];

Future<CoreStorage> openStorage(
  Directory requested, {
  StorageHooks hooks = const StorageHooks(),
}) async {
  if (requested.path.trim().isEmpty || requested.path.contains('\u0000')) {
    throw const CoreException(CoreErrorCode.invalidInput);
  }
  DirectoryOwnership? owner;
  CoreDatabase? db;
  QueryExecutor? executor;
  try {
    owner = DirectoryOwnership.acquire(requested);
    final path = p.join(owner.directory, databaseFileName);
    preflight(path);
    final marker = File(p.join(owner.directory, markerFileName));
    requireRegularOrAbsent(marker.path);
    marker.writeAsStringSync(
      jsonEncode({
        'pid': pid,
        'openedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    executor =
        await (hooks.executorFactory?.call(File(path)) ??
            NativeDatabase(
              File(path),
              setup: (connection) {
                connection.execute('PRAGMA foreign_keys = ON');
                connection.execute('PRAGMA journal_mode = DELETE');
                connection.execute('PRAGMA synchronous = FULL');
              },
            ));
    db = CoreDatabase(executor, afterCreate: hooks.afterCreate);
    // Required even for injected executors. No successful lazy-open handle.
    await db.customStatement('PRAGMA foreign_keys = ON');
    final foreignKeys = await db
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    if (foreignKeys.read<int>('foreign_keys') != 1) {
      throw const CoreException(CoreErrorCode.storageOpenFailed);
    }
    await db.customSelect('SELECT 1').get();
    return StorageHandle._(owner, db);
  } catch (error) {
    final primary = classifyStorageError(
      error,
      CoreErrorCode.storageOpenFailed,
    );
    var unconfirmed = primary.cleanupUnconfirmed;
    try {
      if (db != null) {
        await db.close();
      } else if (executor != null) {
        await executor.close();
      }
    } catch (_) {
      unconfirmed = true;
    }
    if (!unconfirmed) {
      try {
        owner?.release();
      } catch (_) {
        unconfirmed = true;
      }
    }
    if (unconfirmed) _quarantined.add((owner, db, executor));
    throw CoreException(primary.code, cleanupUnconfirmed: unconfirmed);
  }
}

/// Internal access for later repositories and fixtures. Every operation must
/// return a Future spanning all its queries/transactions; never retain [db].
final class StorageHandle implements CoreStorage {
  StorageHandle._(this._owner, this._db);
  final DirectoryOwnership _owner;
  final CoreDatabase _db;
  StorageState _state = StorageState.open;
  int _active = 0;
  Completer<void>? _idle;
  Future<void>? _closing;

  @override
  StorageState get state => _state;

  Future<T> useDatabase<T>(
    Future<T> Function(CoreDatabase db) action, {
    CoreErrorCode failureCode = CoreErrorCode.storageReadFailed,
  }) async {
    if (_state != StorageState.open) {
      throw CoreException(failureCode);
    }
    _active++;
    try {
      return await action(_db);
    } catch (error) {
      // Generated row readers cast SQLite values before typed codecs run.
      if (error is TypeError || error is FormatException) {
        throw const CoreException(CoreErrorCode.databaseCorrupt);
      }
      throw classifyStorageError(error, failureCode);
    } finally {
      if (--_active == 0) _idle?.complete();
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _state = StorageState.closing;
    return _closing = _close();
  }

  Future<void> _close() async {
    try {
      if (_active != 0) {
        _idle = Completer<void>();
        await _idle!.future;
      }
      await _db.close();
      _owner.release();
      _state = StorageState.closed;
    } catch (_) {
      _state = StorageState.closeUnconfirmed;
      _quarantined.add(this);
      throw const CoreException(
        CoreErrorCode.storageWriteFailed,
        cleanupUnconfirmed: true,
      );
    }
  }
}
