import '../errors.dart';
import '../models/app_settings.dart';
import '../repositories.dart';
import '../storage/codec.dart';
import '../storage/database.dart';
import '../storage/storage.dart';
import '../validation.dart';
import 'profile_repository.dart';

// Caller owns the short transaction, including any selected-profile read.
Future<AppSettings> readStoredSettings(CoreDatabase db) async {
  final rows = await (db.select(db.storedSettings)..limit(2)).get();
  if (rows.length > 1) {
    throw const CoreException(CoreErrorCode.databaseCorrupt);
  }
  return rows.isEmpty ? AppSettings() : decodeSettings(rows.single);
}

final class PersistentSettingsRepository implements SettingsRepository {
  PersistentSettingsRepository(this._storage);
  final StorageHandle _storage;

  @override
  Future<AppSettings> read() => _storage.useDatabase(
    (db) => db.transaction(() async {
      final settings = await readStoredSettings(db);
      if (settings.defaultProfileId case final id?) {
        await readStoredProfile(db, id);
      }
      return settings;
    }),
  );

  @override
  Future<AppSettings> save(AppSettings settings) =>
      _storage.useDatabase((db) async {
        requireValid(
          settings.diagnosticHistoryLimit >= 1 &&
              settings.diagnosticHistoryLimit <= 100000,
        );
        final saved = await db.transaction(() async {
          if (settings.defaultProfileId case final id?) {
            await readStoredProfile(db, id);
          }
          await db
              .into(db.storedSettings)
              .insertOnConflictUpdate(encodeSettings(settings));
          _storage.invalidateHistorySelection();
          return settings;
        });
        _storage.requestHistoryMaintenance();
        return saved;
      }, failureCode: CoreErrorCode.storageWriteFailed);

  @override
  Future<AppSettings> restoreDefaults() => _storage.useDatabase((db) async {
    final saved = await db.transaction(() async {
      await db.delete(db.storedSettings).go();
      _storage.invalidateHistorySelection();
      return AppSettings();
    });
    _storage.requestHistoryMaintenance();
    return saved;
  }, failureCode: CoreErrorCode.storageWriteFailed);
}
