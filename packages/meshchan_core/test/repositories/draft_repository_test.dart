import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/database.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:test/test.dart';

import '../storage/database_test.dart' show coreError, representation;
import '../storage/fixtures.dart';
import '../storage/ownership_test.dart' show CloseBarrier;

// One-shot hooks wrap the real executor, including its transaction executors.
// A commit rejection occurs before send(), leaving Drift to perform rollback.
class Control extends QueryInterceptor {
  Control({this.readTable = 'stored_drafts'});
  final String readTable;
  Future<void> Function()? afterRead;
  Future<void> Function(QueryExecutor)? afterWrite;
  Future<void> Function()? beforeCommit;
  Object? readFailure;
  int rollbacks = 0;
  bool explainDraftReads = false;
  final draftQueryPlans = <List<String>>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.startsWith('SELECT') && statement.contains(readTable)) {
      final failure = readFailure;
      readFailure = null;
      if (failure != null) throw failure;
      if (explainDraftReads) {
        final plan = await executor.runSelect(
          'EXPLAIN QUERY PLAN $statement',
          args,
        );
        draftQueryPlans.add(
          plan.map((row) => row['detail'] as String).toList(),
        );
      }
      final rows = await executor.runSelect(statement, args);
      final action = afterRead;
      afterRead = null;
      await action?.call();
      return rows;
    }
    final rows = await executor.runSelect(statement, args);
    if (statement.startsWith('INSERT INTO "$readTable"')) {
      await _written(executor);
    }
    return rows;
  }

  Future<void> _written(QueryExecutor executor) async {
    final action = afterWrite;
    afterWrite = null;
    await action?.call(executor);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final id = await executor.runInsert(statement, args);
    await _written(executor);
    return id;
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final count = await executor.runUpdate(statement, args);
    await _written(executor);
    return count;
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final count = await executor.runDelete(statement, args);
    await _written(executor);
    return count;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    final action = beforeCommit;
    beforeCommit = null;
    await action?.call();
    await inner.send();
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await inner.rollback();
    rollbacks++;
  }
}

void sameDraft(Draft actual, Draft expected) => expect(
  representation(encodeDraft(actual)),
  representation(encodeDraft(expected)),
);

void main() {
  late Directory directory;
  final handles = <CoreStorage>[];
  Future<StorageHandle> open({
    LocalId Function()? id,
    DateTime Function()? clock,
    QueryInterceptor? interceptor,
  }) async {
    final storage = await openStorage(
      directory,
      hooks: StorageHooks(
        draftId: id,
        clock: clock,
        executorFactory: interceptor == null
            ? null
            : (file) => NativeDatabase(file).interceptWith(interceptor),
      ),
    ) as StorageHandle;
    handles.add(storage);
    return storage;
  }

  setUp(
    () => directory = Directory.systemTemp.createTempSync('meshchan-drafts-'),
  );
  tearDown(() async {
    for (final handle in handles.reversed) {
      await handle.close();
    }
    handles.clear();
    directory.deleteSync(recursive: true);
  });

  test(
    'changed fields, exact microseconds, repeated and backward clocks',
    () async {
      final times = [
        instant,
        instant,
        instant.subtract(const Duration(microseconds: 9)),
        instant.add(const Duration(microseconds: 1)),
      ].iterator;
      var clockReads = 0;
      final storage = await open(
        clock: () {
          clockReads++;
          times.moveNext();
          return times.current;
        },
      );
      final repo = storage.drafts;
      final first = await repo.create(const DraftContent());
      sameDraft(
        await repo.update(first.id, const DraftContent(), expectedRevision: 1),
        first,
      );
      expect(clockReads, 1);
      var current = first;
      for (final content in [
        const DraftContent(title: 'title'),
        const DraftContent(title: 'title', body: 'body'),
        const DraftContent(title: 'both', body: 'changed'),
      ]) {
        final next = await repo.update(
          current.id,
          content,
          expectedRevision: current.revision,
        );
        expect(next.revision, current.revision + 1);
        expect(next.id, first.id);
        expect(next.createdAt, instant);
        expect(next.updatedAt, times.current);
        sameDraft(await repo.read(next.id), next);
        current = next;
      }
      expect(clockReads, 4);
      expect(current.updatedAt.microsecond, 892);
      await storage.close();
      sameDraft(await (await open()).drafts.read(first.id), current);
    },
  );

  for (final text in ['\uD800', '\uDC00', 'ok\uD800x', 'ok\uDC00😀']) {
    test(
      'unpaired UTF-16 is invalid before any write (${text.codeUnits})',
      () async {
        var idCalls = 0;
        final storage = await open(id: () => fixtureId(++idCalls));
        final repo = storage.drafts;
        final saved = await repo.create(
          const DraftContent(body: '😀\uFFFD e\u0301'),
        );
        for (final content in [
          DraftContent(title: text),
          DraftContent(body: text),
        ]) {
          await expectLater(
            repo.create(content),
            throwsA(coreError(CoreErrorCode.invalidInput)),
          );
          await expectLater(
            repo.update(saved.id, content, expectedRevision: 1),
            throwsA(coreError(CoreErrorCode.invalidInput)),
          );
          sameDraft(await repo.read(saved.id), saved);
        }
        expect(idCalls, 1);
        expect((await repo.list()).items, hasLength(1));
      },
    );
  }

  test('positive revision, missing, stale and no-op precedence', () async {
    final repo = (await open()).drafts;
    final saved = await repo.create(
      const DraftContent(title: 'same', body: 'exact'),
    );
    for (final revision in [0, -1]) {
      await expectLater(
        repo.update(
          fixtureId(999),
          const DraftContent(),
          expectedRevision: revision,
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
      await expectLater(
        repo.delete(fixtureId(999), expectedRevision: revision),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
    for (final operation in [
      () => repo.read(fixtureId(999)),
      () => repo.update(
        fixtureId(999),
        const DraftContent(),
        expectedRevision: 1,
      ),
      () => repo.delete(fixtureId(999), expectedRevision: 1),
    ]) {
      await expectLater(
        operation(),
        throwsA(coreError(CoreErrorCode.notFound)),
      );
    }
    await expectLater(
      repo.update(
        saved.id,
        const DraftContent(title: 'same', body: 'exact'),
        expectedRevision: 2,
      ),
      throwsA(coreError(CoreErrorCode.conflict)),
    );
    await expectLater(
      repo.delete(saved.id, expectedRevision: 2),
      throwsA(coreError(CoreErrorCode.conflict)),
    );
    sameDraft(
      await repo.update(
        saved.id,
        DraftContent(title: saved.title, body: saved.body),
        expectedRevision: 1,
      ),
      saved,
    );
    await repo.delete(saved.id, expectedRevision: 1);
    await expectLater(
      repo.delete(saved.id, expectedRevision: 1),
      throwsA(coreError(CoreErrorCode.notFound)),
    );
  });

  test('hard delete isolates other drafts and all other tables', () async {
    final storage = await open();
    final repo = storage.drafts;
    final removed = await repo.create(const DraftContent(body: 'remove'));
    final kept = await repo.create(const DraftContent(body: 'keep'));
    await storage.useDatabase((db) async {
      await db.into(db.storedProfiles).insert(encodeProfile(profiles.first));
      await db
          .into(db.storedSettings)
          .insert(
            encodeSettings(AppSettings(defaultProfileId: profiles.first.id)),
          );
      await db.into(db.storedRuns).insert(encodeRun(runs.first));
    });
    await repo.delete(removed.id, expectedRevision: 1);
    sameDraft(await repo.read(kept.id), kept);
    await storage.close();
    final reopened = await open();
    sameDraft(await reopened.drafts.read(kept.id), kept);
    await reopened.useDatabase((db) async {
      expect(
        representation(await db.select(db.storedProfiles).getSingle()),
        representation(encodeProfile(profiles.first)),
      );
      expect(
        decodeSettings(await db.select(db.storedSettings).getSingle())
            .defaultProfileId,
        profiles.first.id,
      );
      expect(
        representation(await db.select(db.storedRuns).getSingle()),
        representation(encodeRun(runs.first)),
      );
    });
  });

  for (final secondIsDelete in [false, true]) {
    test(
      'transaction serializes changed update with ${secondIsDelete ? "stale delete" : "competing update"}',
      () async {
        final control = Control();
        final storage = await open(interceptor: control);
        final repo = storage.drafts;
        final saved = await repo.create(const DraftContent());
        final entered = Completer<void>();
        final release = Completer<void>();
        control.afterRead = () async {
          entered.complete();
          await release.future;
        };
        final first = repo.update(
          saved.id,
          const DraftContent(title: 'first', body: 'complete first'),
          expectedRevision: 1,
        );
        await entered.future;
        final second = expectLater(
          secondIsDelete
              ? repo.delete(saved.id, expectedRevision: 1)
              : repo.update(
                  saved.id,
                  const DraftContent(title: 'second', body: 'complete second'),
                  expectedRevision: 1,
                ),
          throwsA(coreError(CoreErrorCode.conflict)),
        );
        try {
          release.complete();
          final committed = await first;
          await second;
          expect(committed.revision, 2);
          sameDraft(await repo.read(saved.id), committed);
          await storage.close();
          sameDraft(await (await open()).drafts.read(saved.id), committed);
        } finally {
          if (!release.isCompleted) release.complete();
        }
      },
    );
  }

  test(
    'bounded double-key pages, default, ties, exact tail and deleted cursor',
    () async {
      var n = 0;
      // Adjacent microseconds exercise the primary sort key without rounding.
      final storage = await open(
        id: () => fixtureId(++n),
        clock: () => instant.add(Duration(microseconds: n ~/ 13)),
      );
      final repo = storage.drafts;
      expect((await repo.list()).items, isEmpty);
      expect((await repo.list()).nextCursor, isNull);
      final saved = <Draft>[];
      for (var i = 0; i < 213; i++) {
        saved.add(await repo.create(DraftContent(title: '$i')));
      }
      final expected = saved.reversed.map((v) => v.id).toList();
      final first = await repo.list();
      expect(first.items, hasLength(50));
      expect(first.nextCursor!.id, first.items.last.id);
      expect(first.nextCursor!.updatedAt, first.items.last.updatedAt);
      for (final size in [1, 50, 200]) {
        final actual = <LocalId>[];
        UpdatedCursor? cursor;
        do {
          final page = await repo.list(size: PageSize(size), after: cursor);
          expect(page.items.length, lessThanOrEqualTo(size));
          actual.addAll(page.items.map((v) => v.id));
          cursor = page.nextCursor;
        } while (cursor != null);
        expect(actual, expected);
      }
      final cursorRow = first.items.last;
      await repo.delete(cursorRow.id, expectedRevision: cursorRow.revision);
      expect(
        (await repo.list(after: first.nextCursor)).items.map((v) => v.id),
        expected.skip(50).take(50),
      );
      final tail = await repo.list(
        size: PageSize(13),
        after: UpdatedCursor(updatedAt: saved[13].updatedAt, id: saved[13].id),
      );
      expect(tail.items, hasLength(13));
      expect(tail.nextCursor, isNull);
      final empty = await repo.list(
        after: UpdatedCursor(
          updatedAt: saved.first.updatedAt,
          id: saved.first.id,
        ),
      );
      expect(empty.items, isEmpty);
      expect(empty.nextCursor, isNull);
    },
  );

  test(
    'continuation seeks through the composite index without a sort',
    () async {
      final control = Control();
      var n = 0;
      final storage = await open(
        interceptor: control,
        id: () => fixtureId(++n),
        clock: () => instant.add(Duration(microseconds: n ~/ 5)),
      );
      final saved = <Draft>[];
      for (var i = 0; i < 20; i++) {
        saved.add(await storage.drafts.create(const DraftContent()));
      }
      final cursorRow = saved[16];
      final cursor = UpdatedCursor(
        updatedAt: cursorRow.updatedAt,
        id: cursorRow.id,
      );
      final version = await storage.useDatabase(
        (db) async =>
            (await db
                    .customSelect('SELECT sqlite_version() AS version')
                    .getSingle())
                .read<String>('version'),
      );
      for (final deleteCursor in [false, true]) {
        if (deleteCursor) {
          await storage.drafts.delete(
            cursorRow.id,
            expectedRevision: cursorRow.revision,
          );
        }
        for (final size in [2, 50]) {
          control.explainDraftReads = true;
          final page = await storage.drafts.list(
            size: PageSize(size),
            after: cursor,
          );
          control.explainDraftReads = false;
          expect(
            page.items.map((item) => item.id),
            saved.take(16).toList().reversed.take(size).map((item) => item.id),
          );
        }
      }
      printOnFailure(
        'SQLite $version continuation query plans: ${control.draftQueryPlans}',
      );
      expect(control.draftQueryPlans, hasLength(4));
      for (final plan in control.draftQueryPlans) {
        expect(
          plan,
          anyElement(
            allOf(
              contains('SEARCH stored_drafts USING INDEX drafts_updated'),
              contains('(updated_at_us,id)<(?,?)'),
            ),
          ),
        );
        expect(plan, isNot(anyElement(contains('SCAN stored_drafts'))));
        expect(plan, isNot(anyElement(contains('USE TEMP B-TREE'))));
      }
    },
  );

  test(
    'collision retries do not overwrite and stop after eight attempts',
    () async {
      var calls = 0;
      final storage = await open(id: () => fixtureId(++calls <= 2 ? 1 : 2));
      final original = await storage.drafts.create(
        const DraftContent(title: 'original'),
      );
      final retried = await storage.drafts.create(
        const DraftContent(title: 'new'),
      );
      expect(retried.id, fixtureId(2));
      expect(calls, 3);
      sameDraft(await storage.drafts.read(original.id), original);
      await storage.close();
      calls = 0;
      final exhausted = await open(
        id: () {
          calls++;
          return fixtureId(1);
        },
      );
      await expectLater(
        exhausted.drafts.create(const DraftContent(title: 'lost')),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      expect(calls, 8);
      sameDraft(await exhausted.drafts.read(original.id), original);
      expect((await exhausted.drafts.list()).items, hasLength(2));
      await exhausted.close();
      sameDraft(await (await open()).drafts.read(original.id), original);
    },
  );

  for (final failure in [
    const FormatException('PRIVATE SOURCE'),
    StateError('PRIVATE SOURCE'),
    UnsupportedError('PRIVATE SOURCE'),
    TypeError(),
  ]) {
    for (final clockFails in [false, true]) {
      test(
        '${failure.runtimeType} ${clockFails ? "clock" : "entropy"} failure is safe write failure',
        () async {
          var fail = false;
          final storage = await open(
            id: () {
              if (fail && !clockFails) throw failure;
              return fixtureId(1);
            },
            clock: () {
              if (fail && clockFails) throw failure;
              return instant;
            },
          );
          final saved = await storage.drafts.create(
            const DraftContent(body: 'PRIVATE BODY'),
          );
          fail = true;
          await expectLater(
            storage.drafts.create(const DraftContent(body: 'PRIVATE BODY')),
            throwsA(
              isA<CoreException>()
                  .having(
                    (e) => e.code,
                    'code',
                    CoreErrorCode.storageWriteFailed,
                  )
                  .having(
                    (e) => e.toString(),
                    'safe',
                    'CoreException(storage_write_failed)',
                  ),
            ),
          );
          if (clockFails) {
            await expectLater(
              storage.drafts.update(
                saved.id,
                const DraftContent(body: 'change'),
                expectedRevision: 1,
              ),
              throwsA(coreError(CoreErrorCode.storageWriteFailed)),
            );
            sameDraft(
              await storage.drafts.update(
                saved.id,
                saved.content,
                expectedRevision: 1,
              ),
              saved,
            );
          }
          sameDraft(await storage.drafts.read(saved.id), saved);
          expect((await storage.drafts.list()).items, hasLength(1));
        },
      );
    }
  }

  test(
    'other insert constraints, including another primary key, never retry IDs',
    () async {
      var calls = 0;
      final storage = await open(id: () => fixtureId(++calls));
      await storage.useDatabase((db) async {
        await db.into(db.storedSettings).insert(encodeSettings(AppSettings()));
      });
      for (final singleton in [1, 2]) {
        await storage.useDatabase(
          (db) => db.customStatement('''
        CREATE TEMP TRIGGER reject_draft AFTER INSERT ON stored_drafts BEGIN
          INSERT INTO stored_settings VALUES ($singleton, NULL, 1000);
        END
      '''),
        );
        final before = calls;
        await expectLater(
          storage.drafts.create(const DraftContent(body: 'rejected')),
          throwsA(coreError(CoreErrorCode.storageWriteFailed)),
        );
        expect(calls, before + 1);
        expect((await storage.drafts.list()).items, isEmpty);
        await storage.useDatabase(
          (db) => db.customStatement('DROP TRIGGER reject_draft'),
        );
      }
      await storage.drafts.create(const DraftContent(body: 'accepted'));
    },
  );

  test(
    'signed 64-bit revision limit allows last increment, no-op and delete',
    () async {
      final storage = await open(clock: () => instant);
      final saved = await storage.drafts.create(const DraftContent());
      const max = 9223372036854775807;
      await storage.useDatabase(
        (db) =>
            (db.update(db.storedDrafts)
                  ..where((t) => t.id.equals(saved.id.value)))
                .write(const StoredDraftsCompanion(revision: Value(max - 1))),
      );
      final last = await storage.drafts.update(
        saved.id,
        const DraftContent(title: 'last'),
        expectedRevision: max - 1,
      );
      expect(last.revision, max);
      await expectLater(
        storage.drafts.update(
          saved.id,
          const DraftContent(title: 'overflow'),
          expectedRevision: max,
        ),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
      sameDraft(
        await storage.drafts.update(
          saved.id,
          last.content,
          expectedRevision: max,
        ),
        last,
      );
      await storage.close();
      final reopened = await open();
      sameDraft(await reopened.drafts.read(saved.id), last);
      await reopened.drafts.delete(saved.id, expectedRevision: max);
      expect((await reopened.drafts.list()).items, isEmpty);
    },
  );

  for (final operation in ['create', 'update', 'delete']) {
    for (final stage in ['write', 'commit']) {
      test(
        '$operation $stage rejection rolls back immediately and permits next mutation',
        () async {
          final control = Control();
          var n = 0;
          final storage = await open(
            interceptor: control,
            id: () => fixtureId(++n),
          );
          final repo = storage.drafts;
          final saved = await repo.create(
            const DraftContent(title: 'PRIVATE TITLE', body: 'PRIVATE BODY'),
          );
          final before = control.rollbacks;
          if (stage == 'write') {
            control.afterWrite = (executor) => executor.runCustom(
              'INSERT INTO stored_settings VALUES (2, NULL, 1000)',
              [],
            );
          } else {
            control.beforeCommit = () async =>
                throw StateError('PRIVATE COMMIT REASON');
          }
          await expectLater(
            switch (operation) {
              'create' => repo.create(const DraftContent(body: 'new')),
              'update' => repo.update(
                saved.id,
                const DraftContent(title: 'changed', body: 'changed'),
                expectedRevision: 1,
              ),
              _ => repo.delete(saved.id, expectedRevision: 1),
            },
            throwsA(
              isA<CoreException>()
                  .having(
                    (e) => e.code,
                    'code',
                    CoreErrorCode.storageWriteFailed,
                  )
                  .having(
                    (e) => e.toString(),
                    'safe',
                    'CoreException(storage_write_failed)',
                  ),
            ),
          );
          expect(control.rollbacks, before + 1);
          sameDraft(await repo.read(saved.id), saved);
          expect((await repo.list()).items, hasLength(1));
          final next = await repo.update(
            saved.id,
            const DraftContent(body: 'normal mutation'),
            expectedRevision: 1,
          );
          expect(next.revision, 2);
          await storage.close();
          final reopened = (await open()).drafts;
          sameDraft(await reopened.read(saved.id), next);
          expect((await reopened.list()).items, hasLength(1));
        },
      );
    }
  }

  for (final reject in [false, true]) {
    test(
      'close waits through admitted mutation ${reject ? "rollback" : "commit"}',
      () async {
        final control = Control();
        final closeBarrier = CloseBarrier();
        // Reuse the established native close barrier as well as a commit barrier.
        final storage = await openStorage(
          directory,
          hooks: StorageHooks(
            executorFactory: (file) =>
                NativeDatabase(file)
                    .interceptWith(control)
                    .interceptWith(closeBarrier, sticky: false),
          ),
        );
        handles.add(storage);
        final repo = storage.drafts;
        final saved = await repo.create(const DraftContent(body: 'old'));
        final enteredRead = Completer<void>();
        final releaseRead = Completer<void>();
        final enteredCommit = Completer<void>();
        final releaseCommit = Completer<void>();
        control.afterRead = () async {
          enteredRead.complete();
          await releaseRead.future;
        };
        control.beforeCommit = () async {
          enteredCommit.complete();
          await releaseCommit.future;
          if (reject) throw StateError('refuse before COMMIT');
        };
        var settled = false;
        final mutation = repo
            .update(
              saved.id,
              const DraftContent(body: 'new'),
              expectedRevision: 1,
            )
            .then<Object>(
              (v) {
                settled = true;
                return v;
              },
              onError: (Object e) {
                settled = true;
                return e;
              },
            );
        await enteredRead.future;
        final closing = storage.close();
        try {
          expect(storage.state, StorageState.closing);
          for (final request in [
            () => repo.read(saved.id),
            () => repo.list(),
            () => repo.create(const DraftContent()),
            () => repo.update(
              saved.id,
              const DraftContent(),
              expectedRevision: 1,
            ),
            () => repo.delete(saved.id, expectedRevision: 1),
          ]) {
            await expectLater(request(), throwsA(isA<CoreException>()));
          }
          releaseRead.complete();
          await enteredCommit.future;
          expect(settled, isFalse);
          expect(closeBarrier.calls, 0);
          await expectLater(
            CoreStorage.open(dataDirectory: directory),
            throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
          );
          releaseCommit.complete();
          final result = await mutation;
          expect(
            result,
            reject ? coreError(CoreErrorCode.storageWriteFailed) : isA<Draft>(),
          );
          await closeBarrier.entered.future;
          expect(storage.state, StorageState.closing);
        } finally {
          if (!releaseRead.isCompleted) releaseRead.complete();
          if (!releaseCommit.isCompleted) releaseCommit.complete();
          if (!closeBarrier.release.isCompleted) {
            closeBarrier.release.complete();
          }
          await mutation;
          await closing;
        }
        final reopened = await open();
        expect(
          (await reopened.drafts.read(saved.id)).body,
          reject ? 'old' : 'new',
        );
        await expectLater(
          repo.read(saved.id),
          throwsA(coreError(CoreErrorCode.storageReadFailed)),
        );
        await expectLater(
          repo.create(const DraftContent()),
          throwsA(coreError(CoreErrorCode.storageWriteFailed)),
        );
        expect((await reopened.drafts.list()).items, hasLength(1));
      },
    );
  }

  test('strict damaged rows fail read, list and mutation as corrupt', () async {
    final storage = await open();
    final saved = await storage.drafts.create(const DraftContent());
    await storage.useDatabase(
      (db) => db.customStatement('PRAGMA ignore_check_constraints = ON'),
    );
    for (final damage in [
      "body = X'ff'",
      "body = '', updated_at_us = 1.5",
      'updated_at_us = 0, revision = 0',
    ]) {
      await storage.useDatabase(
        (db) => db.customStatement('UPDATE stored_drafts SET $damage'),
      );
      for (final operation in [
        () => storage.drafts.read(saved.id),
        () => storage.drafts.list(),
        () => storage.drafts.update(
          saved.id,
          const DraftContent(body: 'change'),
          expectedRevision: 1,
        ),
        () => storage.drafts.delete(saved.id, expectedRevision: 1),
      ]) {
        await expectLater(
          operation(),
          throwsA(coreError(CoreErrorCode.databaseCorrupt)),
        );
      }
    }
  });

  test(
    'damaged probe row cannot produce a deceptively complete page',
    () async {
      var n = 0;
      final storage = await open(
        id: () => fixtureId(++n),
        clock: () => instant,
      );
      final probe = await storage.drafts.create(const DraftContent());
      await storage.drafts.create(const DraftContent());
      await storage.useDatabase(
        (db) => db.customStatement(
          "UPDATE stored_drafts SET body = X'ff' WHERE id = ?",
          [probe.id.value],
        ),
      );
      await expectLater(
        storage.drafts.list(size: PageSize(1)),
        throwsA(coreError(CoreErrorCode.databaseCorrupt)),
      );
    },
  );

  test(
    'ordinary read failure follows operation boundary and typed errors survive',
    () async {
      final control = Control();
      final storage = await open(interceptor: control);
      final saved = await storage.drafts.create(
        const DraftContent(body: 'PRIVATE BODY'),
      );
      for (final operation in ['read', 'list', 'update', 'delete']) {
        control.readFailure = StateError('PRIVATE SQL REASON');
        await expectLater(
          switch (operation) {
            'read' => storage.drafts.read(saved.id),
            'list' => storage.drafts.list(),
            'update' => storage.drafts.update(
              saved.id,
              const DraftContent(),
              expectedRevision: 1,
            ),
            _ => storage.drafts.delete(saved.id, expectedRevision: 1),
          },
          throwsA(
            coreError(
              operation == 'read' || operation == 'list'
                  ? CoreErrorCode.storageReadFailed
                  : CoreErrorCode.storageWriteFailed,
            ),
          ),
        );
        sameDraft(await storage.drafts.read(saved.id), saved);
      }
      control.readFailure = const CoreException(
        CoreErrorCode.databaseCorrupt,
        cleanupUnconfirmed: true,
      );
      await expectLater(
        storage.drafts.read(saved.id),
        throwsA(
          isA<CoreException>()
              .having((e) => e.code, 'code', CoreErrorCode.databaseCorrupt)
              .having((e) => e.cleanupUnconfirmed, 'cleanup', isTrue),
        ),
      );
    },
  );
}
