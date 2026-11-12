import 'package:drift/drift.dart';

import '../errors.dart';
import '../models/draft.dart';
import '../repositories.dart';
import '../storage/codec.dart';
import '../storage/database.dart';
import '../storage/storage.dart';
import '../validation.dart';
import '../values.dart';
import 'write_support.dart';

// Only a targeted id conflict can consume another attempt. Other constraints,
// query failures, and commit failures leave immediately through useDatabase.
const _idAttempts = 8;
const _maxRevision = 9223372036854775807;

void _validateText(DraftContent content) {
  validateUnicode(content.title);
  validateUnicode(content.body);
}

// The locked Drift query builder has no tuple expression. Write the row
// comparison with generated columns and bound variables to seek both index keys.
final class _BeforeDraftCursor extends Expression<bool> {
  const _BeforeDraftCursor(this.table, this.cursor);
  final StoredDrafts table;
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
      other is _BeforeDraftCursor &&
      table == other.table &&
      cursor.updatedAt == other.cursor.updatedAt &&
      cursor.id == other.cursor.id;

  @override
  int get hashCode => Object.hash(table, cursor.updatedAt, cursor.id);
}

/// Internal implementation. Only StorageHandle constructs the production
/// instance; it neither owns a connection nor has a separate close lifecycle.
final class PersistentDraftRepository implements DraftRepository {
  PersistentDraftRepository(
    this._storage, {
    LocalId Function()? generateId,
    DateTime Function()? clock,
  }) : _generateId = generateId ?? randomLocalId,
       _clock = clock ?? DateTime.now;

  final StorageHandle _storage;
  final LocalId Function() _generateId;
  final DateTime Function() _clock;

  DateTime _now() => writeDependency(() => _clock().toUtc());

  Future<Draft> _read(CoreDatabase db, LocalId id) async {
    final row = await (db.select(
      db.storedDrafts,
    )..where((t) => t.id.equals(id.value))).getSingleOrNull();
    if (row == null) throw const CoreException(CoreErrorCode.notFound);
    return decodeDraft(row);
  }

  @override
  Future<Draft> create(DraftContent content) =>
      _storage.useDatabase((db) async {
        _validateText(content);
        return db.transaction(() async {
          final now = _now();
          for (var attempt = 0; attempt < _idAttempts; attempt++) {
            final draft = Draft(
              id: writeDependency(_generateId),
              content: content,
              createdAt: now,
            );
            final row = await db
                .into(db.storedDrafts)
                .insertReturningOrNull(
                  encodeDraft(draft),
                  onConflict: DoNothing(target: [db.storedDrafts.id]),
                );
            if (row != null) return decodeDraft(row);
          }
          throw const CoreException(CoreErrorCode.storageWriteFailed);
        });
      }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<Draft> read(LocalId id) => _storage.useDatabase((db) => _read(db, id));

  @override
  Future<Draft> update(
    LocalId id,
    DraftContent content, {
    required int expectedRevision,
  }) => _storage.useDatabase((db) async {
    requireValid(expectedRevision > 0);
    _validateText(content);
    return db.transaction(() async {
      final current = await _read(db, id);
      if (current.revision != expectedRevision) {
        throw const CoreException(CoreErrorCode.conflict);
      }
      if (current.title == content.title && current.body == content.body) {
        return current;
      }
      if (current.revision == _maxRevision) {
        throw const CoreException(CoreErrorCode.storageWriteFailed);
      }
      final saved = Draft(
        id: current.id,
        content: content,
        createdAt: current.createdAt,
        updatedAt: _now(),
        revision: current.revision + 1,
      );
      final changed =
          await (db.update(db.storedDrafts)..where(
                (t) =>
                    t.id.equals(id.value) & t.revision.equals(expectedRevision),
              ))
              .write(encodeDraft(saved));
      if (changed != 1) {
        throw const CoreException(CoreErrorCode.storageWriteFailed);
      }
      return saved;
    });
  }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<void> delete(LocalId id, {required int expectedRevision}) =>
      _storage.useDatabase((db) async {
        requireValid(expectedRevision > 0);
        await db.transaction(() async {
          final current = await _read(db, id);
          if (current.revision != expectedRevision) {
            throw const CoreException(CoreErrorCode.conflict);
          }
          final changed =
              await (db.delete(db.storedDrafts)..where(
                    (t) =>
                        t.id.equals(id.value) &
                        t.revision.equals(expectedRevision),
                  ))
                  .go();
          if (changed != 1) {
            throw const CoreException(CoreErrorCode.storageWriteFailed);
          }
        });
      }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<Page<Draft, UpdatedCursor>> list({
    PageSize? size,
    UpdatedCursor? after,
  }) => _storage.useDatabase((db) async {
    final limit = (size ?? PageSize()).value;
    final query = db.select(db.storedDrafts);
    if (after != null) {
      query.where((t) => _BeforeDraftCursor(t, after));
    }
    query
      ..orderBy([
        (t) => OrderingTerm.desc(t.updatedAtUs),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit + 1);
    // Decode the probe row too: never disguise a damaged page as complete.
    final rows = (await query.get()).map(decodeDraft).toList();
    final items = rows.take(limit).toList();
    return Page(
      items: items,
      nextCursor: rows.length > limit
          ? UpdatedCursor(updatedAt: items.last.updatedAt, id: items.last.id)
          : null,
    );
  });
}
