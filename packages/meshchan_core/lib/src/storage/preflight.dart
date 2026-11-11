import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import 'database.dart' show databaseSchemaVersion;
import 'ownership.dart';

const sqliteSuffixes = ['', '-wal', '-shm', '-journal'];
final _unreleasedPreflights = <Object>[];

/// Reads no business rows. Rejected originals are never opened for writing,
/// checkpointed, repaired, or deleted. WAL/hot-journal work happens on a copy.
void preflight(String path) {
  for (final suffix in sqliteSuffixes) {
    requireRegularOrAbsent('$path$suffix');
  }
  final file = File(path);
  final sidecars = sqliteSuffixes
      .skip(1)
      .where((s) => File('$path$s').existsSync())
      .toList();
  if (!file.existsSync()) {
    if (sidecars.isNotEmpty) {
      throw const CoreException(CoreErrorCode.storageOpenFailed);
    }
    return;
  }
  Directory? isolated;
  Database? connection;
  CoreException? failure;
  var cleanupUnconfirmed = false;
  try {
    // A rollback-mode file without sidecars can be inspected in true read-only
    // mode. A WAL-mode header may create sidecars even if none existed yet.
    final input = file.openSync();
    late final List<int> header;
    try {
      header = input.readSync(100);
    } finally {
      try {
        input.closeSync();
      } catch (_) {
        cleanupUnconfirmed = true;
        _unreleasedPreflights.add(input);
        rethrow;
      }
    }
    final needsCopy =
        sidecars.isNotEmpty ||
        (header.length > 19 && (header[18] == 2 || header[19] == 2));
    var inspected = path;
    if (needsCopy) {
      isolated = Directory.systemTemp.createTempSync('meshchan-preflight-');
      inspected = p.join(isolated.path, databaseFileName);
      file.copySync(inspected);
      for (final suffix in sidecars) {
        File('$path$suffix').copySync('$inspected$suffix');
      }
    }
    connection = sqlite3.open(
      inspected,
      mode: needsCopy ? OpenMode.readWrite : OpenMode.readOnly,
    );
    final version = connection.userVersion;
    if (version > databaseSchemaVersion) {
      throw const CoreException(CoreErrorCode.unsupportedDatabaseVersion);
    }
    if (version < 0) throw const CoreException(CoreErrorCode.databaseCorrupt);
    final objects = connection.select(
      "SELECT type, name FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*'",
    );
    if (version == 0) {
      if (objects.isNotEmpty) {
        throw const CoreException(CoreErrorCode.databaseCorrupt);
      }
    } else {
      _recognizeSchemaOne(connection, objects);
    }
  } catch (error) {
    failure = classifyStorageError(error, CoreErrorCode.storageOpenFailed);
  } finally {
    try {
      connection?.close();
    } catch (_) {
      cleanupUnconfirmed = true;
    }
    // Retain the private copy if connection release could not be confirmed.
    if (!cleanupUnconfirmed && isolated != null) {
      try {
        isolated.deleteSync(recursive: true);
      } catch (_) {
        cleanupUnconfirmed = true;
      }
    }
  }
  if (failure != null || cleanupUnconfirmed) {
    if (cleanupUnconfirmed) _unreleasedPreflights.add((connection, isolated));
    throw CoreException(
      failure?.code ?? CoreErrorCode.storageOpenFailed,
      cleanupUnconfirmed: cleanupUnconfirmed,
    );
  }
}

// Minimum structural recognition, not an integrity scan or row validation.
// Types/nullability/PK order, all query indexes (including direction), and the
// live settings FK must agree. Extra user objects are not a schema-1 database.
void _recognizeSchemaOne(Database db, ResultSet objects) {
  const columns = <String, String>{
    'stored_drafts': 'id:T!1 title:T!0 body:T!0 created_at_us:I!0 updated_at_us:I!0 revision:I!0',
    'stored_profiles': 'id:T!1 name:T!0 port_hint:T?0 operation:T!0 parameters_json:T!0 updated_at_us:I!0',
    'stored_settings':
        'singleton:I!1 default_profile_id:T?0 diagnostic_history_limit:I!0',
    'stored_runs': 'run_id:T!1 operation:T!0 app_version:T!0 profile_id:T?0 configuration_json:T!0 prepared_at_us:I!0 logical_ended_at_us:I?0 record_state:T!0 result_json:T?0 cleanup_json:T!0 recovered_at_us:I?0 recovery_reason:T?0 summary_format_version:I!0',
  };
  const indexes = <String, String>{
    'drafts_updated': 'stored_drafts:updated_at_us- id-',
    'profiles_updated': 'stored_profiles:updated_at_us- id-',
    'runs_prepared': 'stored_runs:prepared_at_us- run_id-',
    'runs_operation': 'stored_runs:operation+ prepared_at_us- run_id-',
    'runs_state': 'stored_runs:record_state+ prepared_at_us- run_id-',
    'runs_operation_state':
        'stored_runs:operation+ record_state+ prepared_at_us- run_id-',
  };
  void check(bool value) {
    if (!value) throw const CoreException(CoreErrorCode.databaseCorrupt);
  }

  check(objects.length == columns.length + indexes.length);
  for (final entry in columns.entries) {
    final info = db.select('PRAGMA table_info("${entry.key}")');
    final shape = info
        .map(
          (r) =>
              '${r['name']}:${r['type'] == 'TEXT'
                  ? 'T'
                  : r['type'] == 'INTEGER'
                  ? 'I'
                  : '?'}${r['notnull'] == 1 ? '!' : '?'}${r['pk']}',
        )
        .join(' ');
    check(shape == entry.value);
  }
  for (final entry in indexes.entries) {
    final table = db.select(
      "SELECT tbl_name FROM sqlite_schema WHERE type = 'index' AND name = ?",
      [entry.key],
    );
    check(table.length == 1);
    final info = db
        .select('PRAGMA index_xinfo("${entry.key}")')
        .where((r) => r['key'] == 1);
    final shape = info
        .map((r) => '${r['name']}${r['desc'] == 1 ? '-' : '+'}')
        .join(' ');
    check('${table.single['tbl_name']}:$shape' == entry.value);
  }
  final fk = db.select('PRAGMA foreign_key_list(stored_settings)');
  check(
    fk.length == 1 &&
        fk.single['table'] == 'stored_profiles' &&
        fk.single['from'] == 'default_profile_id' &&
        fk.single['to'] == 'id' &&
        fk.single['on_delete'] == 'SET NULL',
  );
  check(db.select('PRAGMA foreign_key_list(stored_runs)').isEmpty);
}

CoreException classifyStorageError(Object error, CoreErrorCode fallback) {
  if (error is CoreException) return error;
  if (error is SqliteException &&
      (error.resultCode == 11 || error.resultCode == 26)) {
    return const CoreException(CoreErrorCode.databaseCorrupt);
  }
  return CoreException(fallback);
}
