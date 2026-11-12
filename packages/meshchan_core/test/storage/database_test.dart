import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/ownership.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'generated/schema.dart';

Map<String, Object?> representation(Insertable row) => row
    .toColumns(false)
    .map((key, value) => MapEntry(key, (value as Variable).value));
Matcher coreError(CoreErrorCode code) =>
    isA<CoreException>().having((e) => e.code, 'code', code);

void main() {
  late Directory directory;
  final handles = <CoreStorage>[];
  Future<StorageHandle> open({
    StorageHooks hooks = const StorageHooks(),
  }) async {
    final handle = await openStorage(directory, hooks: hooks) as StorageHandle;
    handles.add(handle);
    return handle;
  }

  setUp(
    () => directory = Directory.systemTemp.createTempSync('meshchan-db-test-'),
  );
  tearDown(() async {
    for (final handle in handles.reversed) {
      await handle.close();
    }
    handles.clear();
    directory.deleteSync(recursive: true);
  });

  test('schema 1 and structural codec fixtures round trip before recovery', () async {
    final first = await open();
    await first.useDatabase((db) async {
      await SchemaVerifier(GeneratedHelper())
          .migrateAndValidate(db, databaseSchemaVersion);
      expect(await db.select(db.storedSettings).get(), isEmpty);
      await db.transaction(() async {
        await db.into(db.storedDrafts).insert(encodeDraft(draft));
        for (final profile in profiles) {
          await db.into(db.storedProfiles).insert(encodeProfile(profile));
        }
        await db
            .into(db.storedSettings)
            .insert(
              encodeSettings(AppSettings(defaultProfileId: profiles.first.id)),
            );
        for (final run in runs) {
          await db.into(db.storedRuns).insert(encodeRun(run));
        }
        // Exercise the send result discriminator in addition to absent result.
        await db
            .into(db.storedRuns)
            .insert(
              encodeRun(
                DiagnosticRun(
                  runId: fixtureId(24),
                  appVersion: 'fixture',
                  configuration: runs.first.configuration,
                  preparedAt: instant,
                  result: const SendSummary(send: sendFacts),
                ),
              ),
            );
      });
    });
    final second = first;
    await second.useDatabase((db) async {
      final read = decodeDraft((await db.select(db.storedDrafts).get()).single);
      expect(
        representation(encodeDraft(read)),
        representation(encodeDraft(draft)),
      );
      expect(read.createdAt.isUtc, isTrue);
      expect(read.createdAt.microsecond, 891);
      expect(read.updatedAt.isBefore(read.createdAt), isTrue);
      final readProfiles =
          (await (db.select(
                db.storedProfiles,
              )..orderBy([(t) => OrderingTerm.asc(t.id)])).get())
              .map(decodeProfile)
              .toList();
      expect(
        readProfiles.map((v) => representation(encodeProfile(v))),
        profiles.map((v) => representation(encodeProfile(v))),
      );
      final settings = decodeSettings(
        (await db.select(db.storedSettings).get()).single,
      );
      expect(settings.defaultProfileId, profiles.first.id);
      expect(settings.diagnosticHistoryLimit, 1000);
      final saved =
          (await (db.select(
                db.storedRuns,
              )..orderBy([(t) => OrderingTerm.asc(t.runId)])).get())
              .map(decodeRun)
              .toList();
      expect(
        saved.take(4).map((v) => representation(encodeRun(v))),
        runs.map((v) => representation(encodeRun(v))),
      );
      expect(
        (saved[2].result as PingSummary).firstMatchingPongElapsedUs,
        9007199254740993,
      );
      expect((saved[1].result as ListenSummary).reason, isNull);
      expect((saved[1].result as ListenSummary).ordinaryMessages, isNull);
      expect(saved.first.result, isNull);
      expect(saved.first.cleanup.aggregate, CleanupState.failed);
      expect((saved.last.result as SendSummary).send!.localOkObserved, isNull);
      for (final row in await db.select(db.storedRuns).get()) {
        expect(row.configurationJson, isNot(contains('/private/local-port')));
        expect(row.configurationJson, isNot(contains('localTestId')));
        expect(row.configurationJson, isNot(contains('"path":')));
      }
    });
  });

  test(
    'all four business objects survive reopen with terminal diagnostics',
    () async {
      final first = await open();
      await first.useDatabase((db) async {
        await db.into(db.storedDrafts).insert(encodeDraft(draft));
        await db.into(db.storedProfiles).insert(encodeProfile(legalProfile));
        await db
            .into(db.storedSettings)
            .insert(
              encodeSettings(AppSettings(defaultProfileId: profiles.first.id)),
            );
        for (final run in legalRuns) {
          await db.into(db.storedRuns).insert(encodeRun(run));
        }
      });
      await first.close();
      final second = await open();
      expect((await second.drafts.read(draft.id)).body, draft.body);
      expect(
        (await second.profiles.read(profiles.first.id)).name,
        profiles.first.name,
      );
      expect(
        (await second.settings.read()).defaultProfileId,
        profiles.first.id,
      );
      await second.useDatabase((db) async {
        final rows = await (db.select(
          db.storedRuns,
        )..orderBy([(t) => OrderingTerm.asc(t.runId)])).get();
        expect(
          rows.map(representation),
          legalRuns.map((v) => representation(encodeRun(v))),
        );
      });
    },
  );

  test('real constraints, live settings FK and historical association', () async {
    final handle = await open();
    await handle.useDatabase((db) async {
      await db.into(db.storedDrafts).insert(encodeDraft(draft));
      for (final sql in [
        "INSERT INTO stored_drafts VALUES ('bad', '', '', 1, 0, 1)",
        "UPDATE stored_drafts SET revision = 0",
        "UPDATE stored_drafts SET revision = 1.5",
        "UPDATE stored_drafts SET updated_at_us = 'not an instant'",
        "INSERT INTO stored_settings VALUES (2, NULL, 1000)",
        "INSERT INTO stored_settings VALUES (1, NULL, 0)",
        "INSERT INTO stored_settings VALUES (1, NULL, 100001)",
        "INSERT INTO stored_settings VALUES (1, '${fixtureId(99).value}', 1000)",
      ]) {
        await expectLater(
          db.customStatement(sql),
          throwsA(isA<SqliteException>()),
        );
      }
      await expectLater(
        db.into(db.storedDrafts).insert(encodeDraft(draft)),
        throwsA(isA<SqliteException>()),
      );
      await db.into(db.storedProfiles).insert(encodeProfile(profiles.first));
      await db
          .into(db.storedSettings)
          .insert(
            encodeSettings(AppSettings(defaultProfileId: profiles.first.id)),
          );
      await expectLater(
        db.into(db.storedSettings).insert(encodeSettings(AppSettings())),
        throwsA(isA<SqliteException>()),
      );
      await db.into(db.storedRuns).insert(encodeRun(runs.first));
      await db.delete(db.storedProfiles).go();
      expect(
        decodeSettings((await db.select(db.storedSettings).get()).single)
            .defaultProfileId,
        isNull,
      );
      expect(
        decodeRun((await db.select(db.storedRuns).get()).single).profileId,
        profiles.first.id,
      );
    });
  });

  test(
    'multi-statement failure rolls back content and revision across reopen',
    () async {
      final handle = await open();
      await handle.useDatabase((db) async {
        await db.into(db.storedDrafts).insert(encodeDraft(draft));
        await expectLater(
          db.transaction(() async {
            await db.customStatement(
              "UPDATE stored_drafts SET title = 'partial', body = 'lost', revision = revision + 1",
            );
            await db.customStatement(
              'INSERT INTO stored_settings VALUES (1, NULL, 0)',
            );
          }),
          throwsA(isA<SqliteException>()),
        );
      });
      await handle.close();
      await (await open()).useDatabase((db) async {
        expect(
          representation(
            encodeDraft(
              decodeDraft((await db.select(db.storedDrafts).get()).single),
            ),
          ),
          representation(encodeDraft(draft)),
        );
        expect(await db.select(db.storedSettings).get(), isEmpty);
      });
    },
  );

  test(
    'failure after first real CREATE rolls back DDL and version then retries',
    () async {
      var injected = false;
      await expectLater(
        open(
          hooks: StorageHooks(
            afterCreate: () {
              injected = true;
              throw StateError('private initialization failure');
            },
          ),
        ),
        throwsA(coreError(CoreErrorCode.storageOpenFailed)),
      );
      expect(injected, isTrue);
      final raw = sqlite3.open('${directory.path}/$databaseFileName');
      try {
        expect(raw.userVersion, 0);
        expect(
          raw.select(
            "SELECT name FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*'",
          ),
          isEmpty,
        );
      } finally {
        raw.close();
      }
      await (await open()).useDatabase((db) async {
        expect(await db.select(db.storedDrafts).get(), isEmpty);
      });
    },
  );

  test('persistent invalid representations are corrupt; caller input stays invalid', () async {
    final handle = await open();
    await handle.useDatabase((db) async {
      await db.into(db.storedProfiles).insert(encodeProfile(profiles.first));
      final profile = (await db.select(db.storedProfiles).get()).single;
      for (final malformed in [
        '{}',
        '{"operation":"send"}',
        profile.parametersJson.replaceFirst('"send"', '"ping"'),
        profile.parametersJson.replaceFirst(
          '"sendChannelIndex":3',
          '"sendChannelIndex":3.5',
        ),
      ]) {
        expect(
          () => decodeProfile(profile.copyWith(parametersJson: malformed)),
          throwsA(coreError(CoreErrorCode.databaseCorrupt)),
        );
      }
      expect(
        () => decodeProfile(profile.copyWith(id: 'BAD')),
        throwsA(coreError(CoreErrorCode.databaseCorrupt)),
      );
      expect(
        () => LocalId('BAD'),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
      await db.into(db.storedRuns).insert(encodeRun(runs[2]));
      final row = (await db.select(db.storedRuns).get()).single;
      for (final malformed in [
        row.copyWith(resultJson: const Value('{"operation":"ping"}')),
        row.copyWith(
          configurationJson: row.configurationJson.replaceFirst(
            '"operation":"ping"',
            '"operation":"send"',
          ),
        ),
        row.copyWith(
          configurationJson: row.configurationJson.replaceFirst(
            '{',
            '{"port":"SECRET",',
          ),
        ),
        row.copyWith(cleanupJson: '{}'),
        row.copyWith(recordState: 'unknown'),
      ]) {
        expect(
          () => decodeRun(malformed),
          throwsA(coreError(CoreErrorCode.databaseCorrupt)),
        );
      }
      expect(
        () => decodeRun(row.copyWith(summaryFormatVersion: 2)),
        throwsA(coreError(CoreErrorCode.storageReadFailed)),
      );
    });
  });

  test(
    'wrong persisted SQL types and native operation errors are safe',
    () async {
      final handle = await open();
      await handle.useDatabase((db) async {
        await db.into(db.storedDrafts).insert(encodeDraft(draft));
        // Model an externally damaged row, including a bypassed integer CHECK.
        await db.customStatement('PRAGMA ignore_check_constraints = ON');
      });
      for (final mutation in [
        "body = X'ff'",
        "body = '', updated_at_us = 1.5",
      ]) {
        await handle.useDatabase(
          (db) => db.customStatement('UPDATE stored_drafts SET $mutation'),
        );
        for (final alias in [false, true]) {
          await expectLater(
            handle.useDatabase((db) async {
              final table = alias
                  ? db.alias(db.storedDrafts, 'damaged')
                  : db.storedDrafts;
              return decodeDraft((await db.select(table).get()).single);
            }),
            throwsA(coreError(CoreErrorCode.databaseCorrupt)),
          );
        }
      }
      await handle.useDatabase(
        (db) => db.customStatement('PRAGMA ignore_check_constraints = OFF'),
      );
      await expectLater(
        handle.useDatabase(
          (db) => db.customStatement(
            'INSERT INTO stored_settings VALUES (1, NULL, 0)',
          ),
          failureCode: CoreErrorCode.storageWriteFailed,
        ),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      await expectLater(
        handle.useDatabase(
          (db) async => throw const CoreException(CoreErrorCode.invalidInput),
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    },
  );
}
