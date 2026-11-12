import 'package:drift/drift.dart';

import '../errors.dart';
import '../models/connection_profile.dart';
import '../profile_validation.dart';
import '../repositories.dart';
import '../storage/codec.dart';
import '../storage/database.dart';
import '../storage/storage.dart';
import '../values.dart';
import 'write_support.dart';

ConnectionProfile decodeValidProfile(StoredProfile row) {
  final profile = decodeProfile(row);
  // Only pure business validation is translated to stored semantic damage.
  try {
    validateProfileContent(profile.content);
  } on CoreException catch (error) {
    if (error.code != CoreErrorCode.invalidInput) rethrow;
    throw const CoreException(CoreErrorCode.databaseCorrupt);
  }
  return profile;
}

Future<ConnectionProfile> readStoredProfile(CoreDatabase db, LocalId id) async {
  final row = await (db.select(
    db.storedProfiles,
  )..where((t) => t.id.equals(id.value))).getSingleOrNull();
  if (row == null) throw const CoreException(CoreErrorCode.notFound);
  return decodeValidProfile(row);
}

// The expression is bound to profiles, independently of the draft expression.
final class _BeforeProfileCursor extends Expression<bool> {
  const _BeforeProfileCursor(this.table, this.cursor);
  final StoredProfiles table;
  final UpdatedCursor cursor;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('(');
    table.updatedAtUs.writeInto(context);
    context.buffer.write(', ');
    table.id.writeInto(context);
    context.buffer.write(') < (');
    Variable<int>(cursor.updatedAt.microsecondsSinceEpoch).writeInto(context);
    context.buffer.write(', ');
    Variable<String>(cursor.id.value).writeInto(context);
    context.buffer.write(')');
  }

  @override
  bool operator ==(Object other) =>
      other is _BeforeProfileCursor &&
      table == other.table &&
      cursor.updatedAt == other.cursor.updatedAt &&
      cursor.id == other.cursor.id;

  @override
  int get hashCode => Object.hash(table, cursor.updatedAt, cursor.id);
}

final class PersistentProfileRepository implements ProfileRepository {
  PersistentProfileRepository(
    this._storage, {
    LocalId Function()? generateId,
    DateTime Function()? clock,
  }) : _generateId = generateId ?? randomLocalId,
       _clock = clock ?? DateTime.now;

  final StorageHandle _storage;
  final LocalId Function() _generateId;
  final DateTime Function() _clock;
  DateTime _now() => writeDependency(() => _clock().toUtc());

  @override
  Future<ConnectionProfile> read(LocalId id) =>
      _storage.useDatabase((db) => readStoredProfile(db, id));

  @override
  Future<ConnectionProfile> save(
    ProfileContent content, {
    LocalId? id,
  }) => _storage.useDatabase((db) async {
    validateProfileContent(content);
    return db.transaction(() async {
      if (id != null) {
        final current = await readStoredProfile(db, id);
        // Both values use the same typed canonical codec, excluding ID/time.
        if (current.name == content.name &&
            current.portHint == content.portHint &&
            encodeProfile(current).parametersJson.value ==
                encodeProfile(
                  ConnectionProfile(
                    id: id,
                    content: content,
                    updatedAt: current.updatedAt,
                  ),
                ).parametersJson.value) {
          return current;
        }
        final saved = ConnectionProfile(
          id: id,
          content: content,
          updatedAt: _now(),
        );
        final changed = await (db.update(
          db.storedProfiles,
        )..where((t) => t.id.equals(id.value))).write(encodeProfile(saved));
        if (changed != 1) {
          throw const CoreException(CoreErrorCode.storageWriteFailed);
        }
        return saved;
      }
      final now = _now();
      for (var attempt = 0; attempt < 8; attempt++) {
        final saved = ConnectionProfile(
          id: writeDependency(_generateId),
          content: content,
          updatedAt: now,
        );
        final row = await db
            .into(db.storedProfiles)
            .insertReturningOrNull(
              encodeProfile(saved),
              onConflict: DoNothing(target: [db.storedProfiles.id]),
            );
        if (row != null) return decodeValidProfile(row);
      }
      throw const CoreException(CoreErrorCode.storageWriteFailed);
    });
  }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<void> delete(LocalId id) => _storage.useDatabase((db) async {
    await db.transaction(() async {
      await readStoredProfile(db, id);
      final changed = await (db.delete(
        db.storedProfiles,
      )..where((t) => t.id.equals(id.value))).go();
      if (changed != 1) {
        throw const CoreException(CoreErrorCode.storageWriteFailed);
      }
      // The enabled ON DELETE SET NULL FK clears only the default reference.
    });
  }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<Page<ConnectionProfile, UpdatedCursor>> list({
    PageSize? size,
    UpdatedCursor? after,
  }) => _storage.useDatabase((db) async {
    final limit = (size ?? PageSize()).value;
    final query = db.select(db.storedProfiles);
    if (after != null) query.where((t) => _BeforeProfileCursor(t, after));
    query
      ..orderBy([
        (t) => OrderingTerm.desc(t.updatedAtUs),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit + 1);
    final rows = (await query.get()).map(decodeValidProfile).toList();
    final items = rows.take(limit).toList();
    return Page(
      items: items,
      nextCursor: rows.length > limit
          ? UpdatedCursor(updatedAt: items.last.updatedAt, id: items.last.id)
          : null,
    );
  });
}
