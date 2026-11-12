import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:test/test.dart';

import '../storage/database_test.dart' show coreError, representation;
import '../storage/fixtures.dart' show instant, fixtureId, legalRuns;
import 'draft_repository_test.dart' show Control;
import 'profile_fixtures.dart';

void sameProfile(ConnectionProfile a, ConnectionProfile b) =>
    expect(representation(encodeProfile(a)), representation(encodeProfile(b)));

void main() {
  late Directory directory;
  final handles = <StorageHandle>[];
  Future<StorageHandle> open({
    LocalId Function()? id,
    DateTime Function()? clock,
    QueryInterceptor? control,
    LocalId Function()? draftId,
  }) async {
    final storage = await openStorage(
      directory,
      hooks: StorageHooks(
        profileId: id,
        draftId: draftId,
        clock: clock,
        executorFactory: control == null
            ? null
            : (file) => NativeDatabase(file).interceptWith(control),
      ),
    ) as StorageHandle;
    handles.add(storage);
    return storage;
  }

  setUp(
    () => directory = Directory.systemTemp.createTempSync('meshchan-profiles-'),
  );
  tearDown(() async {
    for (final h in handles.reversed) {
      await h.close();
    }
    handles.clear();
    directory.deleteSync(recursive: true);
  });

  test('canonical deep no-op ignores stored JSON layout and never clocks or updates', () async {
    var clocks = 0;
    var writes = 0;
    final control = Control(readTable: 'stored_profiles');
    final storage = await open(
      clock: () {
        clocks++;
        return instant;
      },
      control: control,
    );
    final repo = storage.profiles;
    final first = await repo.save(
      profileContent(
        sendParameters(route: ProfileRoute(routeDescriptor: 2, path: [1, 2])),
      ),
    );
    await storage.useDatabase((db) async {
      final row = await db.select(db.storedProfiles).getSingle();
      final object = jsonDecode(row.parametersJson) as Map<String, dynamic>;
      final reversed = Map.fromEntries(object.entries.toList().reversed);
      await db.customStatement(
        'UPDATE stored_profiles SET parameters_json = ?',
        [const JsonEncoder.withIndent('  ').convert(reversed)],
      );
    });
    control.afterWrite = (_) async {
      writes++;
    };
    final same = await repo.save(
      profileContent(
        sendParameters(route: ProfileRoute(routeDescriptor: 2, path: [1, 2])),
      ),
      id: first.id,
    );
    sameProfile(same, first);
    expect(clocks, 1);
    expect(writes, 0);
    final changed = await repo.save(
      profileContent(listenParameters(dataType: 0)),
      id: first.id,
    );
    expect(changed.updatedAt, instant);
    expect(changed.operation, DiagnosticOperation.listen);
    expect(writes, 1);
    expect(clocks, 2);
    await storage.useDatabase((db) async {
      final json = jsonDecode(
        (await db.select(db.storedProfiles).getSingle()).parametersJson,
      ) as Map;
      expect(json.keys, isNot(contains('route')));
      expect(json.keys, isNot(contains('sendChannelIndex')));
      expect(json.keys, isNot(contains('endpoints')));
    });
    await storage.close();
    sameProfile(await (await open()).profiles.read(first.id), changed);
  });

  test('exact UTC microseconds and backward times are not clamped', () async {
    var now = instant.toLocal();
    final storage = await open(clock: () => now);
    final p = await storage.profiles.save(profileContent());
    expect(p.updatedAt, instant);
    now = instant.subtract(const Duration(microseconds: 9));
    final changed = await storage.profiles.save(
      profileContent(null, 'changed'),
      id: p.id,
    );
    expect(changed.updatedAt, now);
    await storage.close();
    sameProfile(await (await open()).profiles.read(p.id), changed);
  });

  test('missing IDs never create; names can repeat; profile IDs do not consume draft sequence', () async {
    var n = 0;
    final s = await open(draftId: () => fixtureId(++n));
    for (final op in [
      () => s.profiles.read(fixtureId(999)),
      () => s.profiles.save(profileContent(), id: fixtureId(999)),
      () => s.profiles.delete(fixtureId(999)),
    ]) {
      await expectLater(op(), throwsA(coreError(CoreErrorCode.notFound)));
    }
    for (var i = 0; i < 2; i++) {
      await s.profiles.save(profileContent());
    }
    expect((await s.profiles.list()).items, hasLength(2));
    expect(n, 0);
    expect((await s.drafts.create(const DraftContent())).id, fixtureId(1));
  });

  test(
    'targeted collisions retry eight times at most and retain old rows',
    () async {
      var calls = 0;
      final s = await open(id: () => fixtureId(++calls <= 2 ? 1 : 2));
      final p = await s.profiles.save(profileContent());
      expect((await s.profiles.save(profileContent())).id, fixtureId(2));
      expect(calls, 3);
      await s.close();
      calls = 0;
      final reopened = await open(
        id: () {
          calls++;
          return fixtureId(1);
        },
      );
      await expectLater(
        reopened.profiles.save(profileContent()),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      expect(calls, 8);
      sameProfile(await reopened.profiles.read(p.id), p);
      expect((await reopened.profiles.list()).items, hasLength(2));
    },
  );

  test(
    'non-ID constraints, including another primary key, do not retry',
    () async {
      var calls = 0;
      final s = await open(id: () => fixtureId(++calls));
      await s.settings.save(AppSettings());
      for (final singleton in [1, 2]) {
        await s.useDatabase(
          (db) => db.customStatement('''
        CREATE TEMP TRIGGER reject_profile AFTER INSERT ON stored_profiles BEGIN
          INSERT INTO stored_settings VALUES ($singleton, NULL, 1000);
        END
      '''),
        );
        final before = calls;
        await expectLater(
          s.profiles.save(profileContent()),
          throwsA(coreError(CoreErrorCode.storageWriteFailed)),
        );
        expect(calls, before + 1);
        expect((await s.profiles.list()).items, isEmpty);
        await s.useDatabase(
          (db) => db.customStatement('DROP TRIGGER reject_profile'),
        );
      }
      await s.profiles.save(profileContent());
    },
  );

  for (final error in [
    const FormatException('PRIVATE'),
    TypeError(),
    StateError('PRIVATE'),
    UnsupportedError('PRIVATE'),
  ]) {
    for (final clockFails in [false, true]) {
      test(
        '${error.runtimeType} ${clockFails ? "clock" : "ID"} failure uses safe write category',
        () async {
          var fail = false;
          var n = 0;
          final s = await open(
            id: () {
              if (fail && !clockFails) throw error;
              return fixtureId(++n);
            },
            clock: () {
              if (fail && clockFails) throw error;
              return instant;
            },
          );
          final p = await s.profiles.save(profileContent());
          fail = true;
          await expectLater(
            s.profiles.save(profileContent()),
            throwsA(coreError(CoreErrorCode.storageWriteFailed)),
          );
          if (clockFails) {
            await expectLater(
              s.profiles.save(profileContent(null, 'changed'), id: p.id),
              throwsA(coreError(CoreErrorCode.storageWriteFailed)),
            );
          }
          sameProfile(await s.profiles.save(profileContent(), id: p.id), p);
          sameProfile(await s.profiles.read(p.id), p);
        },
      );
    }
  }

  test('concurrent complete saves serialize successfully without revision conflicts', () async {
    final control = Control(readTable: 'stored_profiles');
    final s = await open(control: control);
    final p = await s.profiles.save(profileContent());
    final entered = Completer<void>(), release = Completer<void>();
    control.afterRead = () async {
      entered.complete();
      await release.future;
    };
    final first = s.profiles.save(
      profileContent(pingParameters(), 'first'),
      id: p.id,
    );
    await entered.future;
    final second = s.profiles.save(
      profileContent(respondParameters(), 'second'),
      id: p.id,
    );
    release.complete();
    final a = await first, b = await second;
    expect(a.name, 'first');
    expect(a.operation, DiagnosticOperation.ping);
    expect(b.name, 'second');
    sameProfile(await s.profiles.read(p.id), b);
  });

  test('absent settings do not write; deletion preserves history limit, other business data and run association', () async {
    final s = await open();
    expect((await s.settings.read()).diagnosticHistoryLimit, 1000);
    await s.useDatabase((db) async {
      expect(await db.select(db.storedSettings).get(), isEmpty);
    });
    // Use the historical fixture ID so the run keeps its original association.
    await s.close();
    var nextId = 0;
    final owned = await open(
      id: () => nextId++ == 0 ? legalRuns.first.profileId! : fixtureId(999),
    );
    final p = await owned.profiles.save(profileContent());
    final kept = await owned.profiles.save(profileContent(listenParameters()));
    final other = await owned.drafts.create(const DraftContent(body: 'keep'));
    await owned.useDatabase(
      (db) => db.into(db.storedRuns).insert(encodeRun(legalRuns.first)),
    );
    await owned.settings.save(
      AppSettings(defaultProfileId: p.id, diagnosticHistoryLimit: 7),
    );
    await owned.profiles.delete(p.id);
    final settings = await owned.settings.read();
    expect(settings.defaultProfileId, isNull);
    expect(settings.diagnosticHistoryLimit, 7);
    sameProfile(await owned.profiles.read(kept.id), kept);
    expect((await owned.drafts.read(other.id)).body, 'keep');
    await owned.useDatabase((db) async {
      expect(
        representation(await db.select(db.storedRuns).getSingle()),
        representation(encodeRun(legalRuns.first)),
      );
    });
    await expectLater(
      owned.settings.save(
        AppSettings(defaultProfileId: p.id, diagnosticHistoryLimit: 19),
      ),
      throwsA(coreError(CoreErrorCode.notFound)),
    );
    expect((await owned.settings.read()).diagnosticHistoryLimit, 7);
    await owned.settings.restoreDefaults();
    expect((await owned.drafts.read(other.id)).body, 'keep');
    await owned.close();
    expect((await (await open()).settings.read()).diagnosticHistoryLimit, 1000);
  });

  for (final deleteFirst in [false, true]) {
    test('default save/delete race: deleteFirst=$deleteFirst', () async {
      final c = Control(readTable: 'stored_profiles');
      final s = await open(control: c);
      final p = await s.profiles.save(profileContent());
      await s.settings.save(AppSettings(diagnosticHistoryLimit: 9));
      final entered = Completer<void>(), release = Completer<void>();
      c.afterRead = () async {
        entered.complete();
        await release.future;
      };
      final Future<Object?> first = deleteFirst
          ? s.profiles.delete(p.id)
          : s.settings.save(
              AppSettings(defaultProfileId: p.id, diagnosticHistoryLimit: 17),
            );
      await entered.future;
      final second = deleteFirst
          ? expectLater(
              s.settings.save(
                AppSettings(defaultProfileId: p.id, diagnosticHistoryLimit: 17),
              ),
              throwsA(coreError(CoreErrorCode.notFound)),
            )
          : s.profiles.delete(p.id);
      release.complete();
      await first;
      await second;
      expect((await s.settings.read()).defaultProfileId, isNull);
      expect(
        (await s.settings.read()).diagnosticHistoryLimit,
        deleteFirst ? 9 : 17,
      );
    });
  }

  test(
    'dangling defaults fail reads but explicit reset/save can repair them',
    () async {
      final s = await open();
      for (final reset in [false, true]) {
        await s.useDatabase((db) async {
          await db.customStatement('PRAGMA foreign_keys = OFF');
          await db
              .into(db.storedSettings)
              .insertOnConflictUpdate(
                encodeSettings(
                  AppSettings(
                    defaultProfileId: fixtureId(999),
                    diagnosticHistoryLimit: 23,
                  ),
                ),
              );
          await db.customStatement('PRAGMA foreign_keys = ON');
        });
        await expectLater(
          s.settings.read(),
          throwsA(coreError(CoreErrorCode.notFound)),
        );
        if (reset) {
          await s.settings.restoreDefaults();
        } else {
          await s.settings.save(AppSettings(diagnosticHistoryLimit: 11));
        }
        expect((await s.settings.read()).defaultProfileId, isNull);
        expect(
          (await s.settings.read()).diagnosticHistoryLimit,
          reset ? 1000 : 11,
        );
      }
      for (final limit in [1, 100000]) {
        expect(
          (await s.settings.save(AppSettings(diagnosticHistoryLimit: limit)))
              .diagnosticHistoryLimit,
          limit,
        );
      }
      for (final limit in [0, 100001]) {
        expect(
          () => AppSettings(diagnosticHistoryLimit: limit),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
    },
  );

  for (final operation in [
    'create',
    'update',
    'delete',
    'settings',
    'restore',
  ]) {
    for (final stage in ['write', 'commit']) {
      test(
        '$operation $stage failure immediately rolls back complete state and handle remains usable',
        () async {
          final c = Control(readTable: 'stored_profiles');
          final s = await open(control: c);
          final p = await s.profiles.save(profileContent());
          await s.settings.save(
            AppSettings(defaultProfileId: p.id, diagnosticHistoryLimit: 7),
          );
          final before = c.rollbacks;
          if (stage == 'write') {
            c.afterWrite = (e) => e.runCustom(
              'INSERT INTO stored_settings VALUES (2, NULL, 1000)',
              [],
            );
          } else {
            c.beforeCommit = () async => throw StateError('PRIVATE COMMIT');
          }
          await expectLater(switch (operation) {
            'create' => s.profiles.save(profileContent(null, 'new')),
            'update' => s.profiles.save(
              profileContent(listenParameters(), 'changed'),
              id: p.id,
            ),
            'delete' => s.profiles.delete(p.id),
            'settings' => s.settings.save(
              AppSettings(diagnosticHistoryLimit: 99),
            ),
            _ => s.settings.restoreDefaults(),
          }, throwsA(coreError(CoreErrorCode.storageWriteFailed)));
          expect(c.rollbacks, before + 1);
          sameProfile(await s.profiles.read(p.id), p);
          expect((await s.profiles.list()).items, hasLength(1));
          expect((await s.settings.read()).defaultProfileId, p.id);
          expect((await s.settings.read()).diagnosticHistoryLimit, 7);
          final next = await s.profiles.save(
            profileContent(pingParameters(), 'next'),
            id: p.id,
          );
          await s.settings.save(
            AppSettings(defaultProfileId: p.id, diagnosticHistoryLimit: 19),
          );
          await s.close();
          final reopened = await open();
          sameProfile(await reopened.profiles.read(p.id), next);
          expect((await reopened.settings.read()).diagnosticHistoryLimit, 19);
        },
      );
    }
  }

  test(
    'bounded double-key pagination decodes probe and seeks profile index',
    () async {
      final c = Control(readTable: 'stored_profiles');
      var n = 0;
      final s = await open(
        id: () => fixtureId(++n),
        clock: () => instant.add(Duration(microseconds: n ~/ 7)),
        control: c,
      );
      expect((await s.profiles.list()).items, isEmpty);
      final saved = <ConnectionProfile>[];
      for (var i = 0; i < 203; i++) {
        saved.add(await s.profiles.save(profileContent()));
      }
      final expected = saved.reversed.map((p) => p.id).toList();
      final first = await s.profiles.list();
      expect(first.items, hasLength(50));
      expect(first.nextCursor!.id, first.items.last.id);
      for (final size in [1, 50, 200]) {
        final actual = <LocalId>[];
        UpdatedCursor? cursor;
        do {
          final page = await s.profiles.list(
            size: PageSize(size),
            after: cursor,
          );
          actual.addAll(page.items.map((p) => p.id));
          cursor = page.nextCursor;
        } while (cursor != null);
        expect(actual, expected);
      }
      final cursor = first.nextCursor!;
      for (final deleted in [false, true]) {
        if (deleted) await s.profiles.delete(cursor.id);
        for (final size in [2, 50]) {
          c.explainDraftReads = true;
          final page = await s.profiles.list(
            size: PageSize(size),
            after: cursor,
          );
          c.explainDraftReads = false;
          expect(page.items.map((p) => p.id), expected.skip(50).take(size));
        }
      }
      for (final plan in c.draftQueryPlans) {
        expect(
          plan,
          anyElement(
            allOf(
              contains('SEARCH stored_profiles USING INDEX profiles_updated'),
              contains('(updated_at_us,id)<(?,?)'),
            ),
          ),
        );
        expect(plan, isNot(anyElement(contains('SCAN stored_profiles'))));
        expect(plan, isNot(anyElement(contains('USE TEMP B-TREE'))));
      }
      expect(c.draftQueryPlans, hasLength(4));
      final tail = await s.profiles.list(
        size: PageSize(3),
        after: UpdatedCursor(updatedAt: saved[3].updatedAt, id: saved[3].id),
      );
      expect(tail.items, hasLength(3));
      expect(tail.nextCursor, isNull);
      await s.useDatabase(
        (db) => db.customStatement(
          'UPDATE stored_profiles SET parameters_json = ? WHERE id = ?',
          ['{}', saved[201].id.value],
        ),
      );
      await expectLater(
        s.profiles.list(size: PageSize(1)),
        throwsA(coreError(CoreErrorCode.databaseCorrupt)),
      );
    },
  );

  for (final damage in [
    "name = X'ff'",
    "updated_at_us = 1.5",
    "operation = 'unknown'",
    "parameters_json = '{}'",
    "parameters_json = replace(parameters_json, '\"taskTimeoutSeconds\":3', '\"taskTimeoutSeconds\":0')",
    "parameters_json = replace(parameters_json, '\"routeDescriptor\":255', '\"routeDescriptor\":192')",
  ]) {
    test('stored profile damage fails accessed boundaries: $damage', () async {
      final s = await open();
      final p = await s.profiles.save(profileContent());
      await s.useDatabase((db) async {
        await db.customStatement('PRAGMA ignore_check_constraints = ON');
        await db.customStatement('UPDATE stored_profiles SET $damage');
      });
      for (final action in [
        () => s.profiles.read(p.id),
        () => s.profiles.list(),
        () => s.profiles.save(profileContent(), id: p.id),
        () => s.profiles.delete(p.id),
        () => s.resolveParameters(
          SendParameterRequest(
            profileId: p.id,
            payload: [],
            overrides: SendOverrides(
              budgets: const BudgetOverrides(taskTimeoutSeconds: 1),
              route: RouteOverrides(routeDescriptor: 0),
            ),
          ),
        ),
      ]) {
        await expectLater(
          action(),
          throwsA(coreError(CoreErrorCode.databaseCorrupt)),
        );
      }
    });
  }

  for (final damage in [
    'diagnostic_history_limit = 0',
    'diagnostic_history_limit = 1.5',
    "default_profile_id = 'bad'",
    "default_profile_id = X'ff'",
  ]) {
    test('stored setting damage is corrupt: $damage', () async {
      final s = await open();
      await s.settings.save(AppSettings());
      await s.useDatabase((db) async {
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement('PRAGMA ignore_check_constraints = ON');
        await db.customStatement('UPDATE stored_settings SET $damage');
      });
      await expectLater(
        s.settings.read(),
        throwsA(coreError(CoreErrorCode.databaseCorrupt)),
      );
      await expectLater(
        s.resolveParameters(SendParameterRequest(payload: [])),
        throwsA(coreError(CoreErrorCode.databaseCorrupt)),
      );
      await s.settings.restoreDefaults();
      expect((await s.settings.read()).diagnosticHistoryLimit, 1000);
    });
  }

  test('query failures use operation fallback, including SELECT in write transactions', () async {
    final c = Control(readTable: 'stored_profiles');
    final s = await open(control: c);
    final p = await s.profiles.save(profileContent());
    await s.settings.save(AppSettings(defaultProfileId: p.id));
    for (final op in [
      'read',
      'list',
      'resolve',
      'update',
      'delete',
      'settingsRead',
      'settingsSave',
    ]) {
      c.readFailure = StateError('PRIVATE SQL');
      await expectLater(
        switch (op) {
          'read' => s.profiles.read(p.id),
          'list' => s.profiles.list(),
          'resolve' => s.resolveParameters(SendParameterRequest(payload: [])),
          'update' => s.profiles.save(profileContent(), id: p.id),
          'delete' => s.profiles.delete(p.id),
          'settingsRead' => s.settings.read(),
          _ => s.settings.save(AppSettings(defaultProfileId: p.id)),
        },
        throwsA(
          coreError(
            ['update', 'delete', 'settingsSave'].contains(op)
                ? CoreErrorCode.storageWriteFailed
                : CoreErrorCode.storageReadFailed,
          ),
        ),
      );
    }
  });

  for (final operation in [
    'profile',
    'settingsRead',
    'settingsSave',
    'resolve',
  ]) {
    test(
      'close drains admitted $operation, rejects new/old handles and never nests admission',
      () async {
        final c = Control(
          readTable: operation.startsWith('settings') || operation == 'resolve'
              ? 'stored_settings'
              : 'stored_profiles',
        );
        final s = await open(control: c);
        final p = await s.profiles.save(profileContent());
        await s.settings.save(AppSettings(defaultProfileId: p.id));
        final entered = Completer<void>(), release = Completer<void>();
        if (operation == 'settingsSave') {
          c.beforeCommit = () async {
            entered.complete();
            await release.future;
          };
        } else {
          c.afterRead = () async {
            entered.complete();
            await release.future;
          };
        }
        final work = switch (operation) {
          'profile' => s.profiles.save(
            profileContent(listenParameters()),
            id: p.id,
          ),
          'settingsRead' => s.settings.read(),
          'settingsSave' => s.settings.save(
            AppSettings(diagnosticHistoryLimit: 21),
          ),
          _ => s.resolveParameters(SendParameterRequest(payload: [])),
        };
        await entered.future;
        var closed = false;
        final closing = s.close().then((_) {
          closed = true;
        });
        for (final action in [
          () => s.profiles.read(p.id),
          () => s.profiles.list(),
          () => s.profiles.save(profileContent()),
          () => s.profiles.delete(p.id),
          () => s.settings.read(),
          () => s.settings.save(AppSettings()),
          () => s.settings.restoreDefaults(),
          () => s.resolveParameters(SendParameterRequest(payload: [])),
        ]) {
          await expectLater(action(), throwsA(isA<CoreException>()));
        }
        expect(closed, isFalse);
        release.complete();
        await work;
        await closing;
        final reopened = await open();
        expect((await reopened.profiles.list()).items, hasLength(1));
        await expectLater(
          s.settings.read(),
          throwsA(coreError(CoreErrorCode.storageReadFailed)),
        );
        await expectLater(
          s.resolveParameters(SendParameterRequest(payload: [])),
          throwsA(coreError(CoreErrorCode.storageReadFailed)),
        );
      },
    );
  }
}
