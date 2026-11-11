import 'dart:async';

import 'package:drift/drift.dart';

import '../errors.dart';

part 'database.g.dart';

/// Physical schema version only, independent of the diagnostic summary format.
const databaseSchemaVersion = 1;

/// Internal SQL boundary. Production construction belongs to storage.dart after
/// ownership and preflight. Tests may inject an executor through an internal import.
@DriftDatabase(include: {'schema.drift'})
class CoreDatabase extends _$CoreDatabase {
  CoreDatabase(super.executor, {this.afterCreate});

  /// Internal failure seam, called after real DDL, inside the creation transaction.
  final FutureOr<void> Function()? afterCreate;

  // Drift 2.35 coerces strings with toString() and fractional integers with
  // toInt(). Guard raw table rows first so damaged storage is never normalized.
  late final _draftRows = _StrictDrafts(this);
  late final _profileRows = _StrictProfiles(this);
  late final _settingsRows = _StrictSettings(this);
  late final _runRows = _StrictRuns(this);
  @override
  StoredDrafts get storedDrafts => _draftRows;
  @override
  StoredProfiles get storedProfiles => _profileRows;
  @override
  StoredSettings get storedSettings => _settingsRows;
  @override
  StoredRuns get storedRuns => _runRows;

  @override
  int get schemaVersion => databaseSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => transaction(() async {
      var created = 0;
      for (final entity in allSchemaEntities) {
        await migrator.create(entity);
        if (++created == 1) await afterCreate?.call();
      }
      // Keep DDL and version atomic even though Drift also writes user_version
      // after onCreate returns. A failed create must leave an empty version 0.
      await customStatement('PRAGMA user_version = $databaseSchemaVersion');
    }),
    onUpgrade: (migrator, from, to) async {
      // There is no released predecessor or v2. Add real, transactional steps
      // here when the structure changes, with a new immutable schema snapshot.
      throw CoreException(
        from > databaseSchemaVersion
            ? CoreErrorCode.unsupportedDatabaseVersion
            : CoreErrorCode.databaseCorrupt,
      );
    },
  );
}

void _checkRow(TableInfo table, Map<String, dynamic> data, String? prefix) {
  final start = prefix == null ? '' : '$prefix.';
  for (final column in table.$columns) {
    final value = data['$start${column.name}'];
    final valid = value == null
        ? column.$nullable
        : switch (column.type) {
            DriftSqlType.string => value is String,
            DriftSqlType.int => value is int,
            _ => false,
          };
    if (!valid) throw const CoreException(CoreErrorCode.databaseCorrupt);
  }
}

class _StrictDrafts extends StoredDrafts {
  _StrictDrafts(super.db, [super.alias]);
  @override
  StoredDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    _checkRow(this, data, tablePrefix);
    return super.map(data, tablePrefix: tablePrefix);
  }

  @override
  StoredDrafts createAlias(String alias) =>
      _StrictDrafts(attachedDatabase, alias);
}

class _StrictProfiles extends StoredProfiles {
  _StrictProfiles(super.db, [super.alias]);
  @override
  StoredProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    _checkRow(this, data, tablePrefix);
    return super.map(data, tablePrefix: tablePrefix);
  }

  @override
  StoredProfiles createAlias(String alias) =>
      _StrictProfiles(attachedDatabase, alias);
}

class _StrictSettings extends StoredSettings {
  _StrictSettings(super.db, [super.alias]);
  @override
  StoredSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    _checkRow(this, data, tablePrefix);
    return super.map(data, tablePrefix: tablePrefix);
  }

  @override
  StoredSettings createAlias(String alias) =>
      _StrictSettings(attachedDatabase, alias);
}

class _StrictRuns extends StoredRuns {
  _StrictRuns(super.db, [super.alias]);
  @override
  StoredRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    _checkRow(this, data, tablePrefix);
    return super.map(data, tablePrefix: tablePrefix);
  }

  @override
  StoredRuns createAlias(String alias) => _StrictRuns(attachedDatabase, alias);
}
