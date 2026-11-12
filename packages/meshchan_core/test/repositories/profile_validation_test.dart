import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/profile_validation.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:test/test.dart';

import '../storage/database_test.dart' show coreError;
import '../storage/fixtures.dart' show fixtureId, instant;
import 'profile_fixtures.dart';

class _ProfileSqlObserver extends QueryInterceptor {
  int transactions = 0;
  int selects = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    return parent.beginTransaction();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  final invalid = <String, ProfileParameters>{};
  for (final n in [0, 86401]) {
    for (final (field, b) in [
      (
        'request',
        ProfileBudgets(taskTimeoutSeconds: 1, requestTimeoutSeconds: n),
      ),
      (
        'initialization',
        ProfileBudgets(taskTimeoutSeconds: 1, initializationTimeoutSeconds: n),
      ),
      ('task', ProfileBudgets(taskTimeoutSeconds: n)),
    ]) {
      for (final p in [
        sendParameters(budgets: b),
        listenParameters(budgets: b),
        pingParameters(budgets: b),
        respondParameters(budgets: b),
      ]) {
        invalid['${p.operation.code} $field=$n'] = p;
      }
    }
  }
  for (final n in [-1, 86400000, 15000]) {
    final b = ProfileBudgets(
      taskTimeoutSeconds: 1,
      startupDelayMilliseconds: n,
    );
    for (final p in [
      sendParameters(budgets: b),
      listenParameters(budgets: b),
      pingParameters(budgets: b),
      respondParameters(budgets: b),
    ]) {
      invalid['${p.operation.code} startup=$n'] = p;
    }
  }
  for (final n in [-1, 256]) {
    invalid['send channel=$n'] = sendParameters(channel: n);
    invalid['listen channel=$n'] = listenParameters(channel: n);
    invalid['ping send=$n'] = pingParameters(send: n);
    invalid['ping receive=$n'] = pingParameters(receive: n);
    invalid['respond send=$n'] = respondParameters(send: n);
    invalid['respond receive=$n'] = respondParameters(receive: n);
  }
  for (final n in [0, 65536]) {
    invalid['send dataType=$n'] = sendParameters(dataType: n);
  }
  for (final n in [-1, 65536]) {
    invalid['listen dataType=$n'] = listenParameters(dataType: n);
  }
  for (final n in [0, 86401]) {
    invalid['ping response=$n'] = pingParameters(response: n);
    invalid['listen duration=$n'] = listenParameters(duration: n);
    invalid['respond duration=$n'] = respondParameters(duration: n);
  }
  for (final n in [0, 4097]) {
    invalid['listen entries=$n'] = listenParameters(maxEntries: n);
    invalid['ping entries=$n'] = pingParameters(maxEntries: n);
    invalid['respond entries=$n'] = respondParameters(maxEntries: n);
    invalid['respond responses=$n'] = respondParameters(maxResponses: n);
  }
  for (final n in [0, 0x100000000]) {
    for (final e in [
      ProfileTestEndpoints(localTestId: n, peerTestId: 2),
      ProfileTestEndpoints(localTestId: 1, peerTestId: n),
    ]) {
      invalid['ping endpoints ${e.localTestId}/${e.peerTestId}'] =
          pingParameters(endpoints: e);
      invalid['respond endpoints ${e.localTestId}/${e.peerTestId}'] =
          respondParameters(endpoints: e);
    }
  }
  invalid['ping same endpoint'] = pingParameters(
    endpoints: const ProfileTestEndpoints(localTestId: 1, peerTestId: 1),
  );
  invalid['respond same endpoint'] = respondParameters(
    endpoints: const ProfileTestEndpoints(localTestId: 1, peerTestId: 1),
  );
  for (final route in [
    ProfileRoute(routeDescriptor: 0xc0),
    ProfileRoute(routeDescriptor: 0xff, path: [0]),
    ProfileRoute(routeDescriptor: 2, path: [0]),
    ProfileRoute(routeDescriptor: 0x3f, path: List.filled(62, 0)),
    ProfileRoute(routeDescriptor: 0x61, path: List.filled(66, 0)),
  ]) {
    for (final p in [
      sendParameters(route: route),
      pingParameters(route: route),
      respondParameters(route: route),
    ]) {
      invalid['${p.operation.code} route=${route.routeDescriptor}/${route.path.length}'] =
          p;
    }
  }
  for (final entry in invalid.entries) {
    test('complete parameter validation rejects ${entry.key}', () {
      expect(
        () => validateProfileParameters(entry.value),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    });
  }

  test(
    'valid inclusive boundaries and earlier task deadline for all operations',
    () {
      for (final b in [
        const ProfileBudgets(
          taskTimeoutSeconds: 1,
          requestTimeoutSeconds: 1,
          initializationTimeoutSeconds: 1,
          startupDelayMilliseconds: 999,
        ),
        const ProfileBudgets(
          taskTimeoutSeconds: 86400,
          requestTimeoutSeconds: 86400,
          initializationTimeoutSeconds: 86400,
          startupDelayMilliseconds: 86399999,
        ),
      ]) {
        for (final n in [0, 255]) {
          for (final p in [
            sendParameters(budgets: b, channel: n, dataType: 65535),
            listenParameters(
              budgets: b,
              channel: n,
              dataType: 0,
              duration: 86400,
              maxEntries: 4096,
            ),
            pingParameters(
              budgets: b,
              send: n,
              receive: n,
              response: 86400,
              maxEntries: 4096,
              endpoints: const ProfileTestEndpoints(
                localTestId: 0xffffffff,
                peerTestId: 1,
              ),
            ),
            respondParameters(
              budgets: b,
              send: n,
              receive: n,
              duration: 86400,
              maxEntries: 4096,
              maxResponses: 4096,
            ),
          ]) {
            validateProfileParameters(p);
          }
        }
      }
      validateProfileParameters(
        listenParameters(dataType: null, maxEntries: 1, duration: 1),
      );
      validateProfileParameters(sendParameters(dataType: 1));
      validateProfileParameters(pingParameters(response: 1, maxEntries: 1));
      validateProfileParameters(
        respondParameters(duration: 1, maxEntries: 1, maxResponses: 1),
      );
    },
  );

  test('repository rejects invalid parameters/text before entropy/clock and preserves exact Unicode', () async {
    final directory = Directory.systemTemp.createTempSync(
      'meshchan-validation-',
    );
    var calls = 0;
    final s = await openStorage(
      directory,
      hooks: StorageHooks(
        clock: () {
          calls++;
          return DateTime.utc(2026);
        },
      ),
    );
    try {
      for (final p in invalid.values) {
        await expectLater(
          s.profiles.save(profileContent(p)),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
      for (final text in ['\uD800', '\uDC00', 'ok\uD800x', 'ok\uDC00😀']) {
        for (final content in [
          ProfileContent(name: text, parameters: sendParameters()),
          ProfileContent(
            name: 'name',
            portHint: text,
            parameters: sendParameters(),
          ),
        ]) {
          await expectLater(
            s.profiles.save(content),
            throwsA(coreError(CoreErrorCode.invalidInput)),
          );
        }
      }
      expect(calls, 0);
      expect((await s.profiles.list()).items, isEmpty);
      for (final text in ['', ' \t\r\n ']) {
        expect(
          () => ProfileContent(name: text, parameters: sendParameters()),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
        expect(
          () => ProfileContent(
            name: 'valid',
            portHint: text,
            parameters: sendParameters(),
          ),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
      for (final path in [
        [-1],
        [256],
      ]) {
        expect(
          () => ProfileRoute(routeDescriptor: 1, path: path),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
      const exact = ' \t中文 😀 e\u0301 \uFFFD\r\n ';
      final p = await s.profiles.save(
        ProfileContent(
          name: exact,
          portHint: exact,
          parameters: sendParameters(),
        ),
      );
      expect((await s.profiles.read(p.id)).name, exact);
      expect((await s.profiles.read(p.id)).portHint, exact);
    } finally {
      await s.close();
      directory.deleteSync(recursive: true);
    }
  });

  test('NUL names rejected by schema fail create/update before SQL or write dependencies', () async {
    final directory = Directory.systemTemp.createTempSync('meshchan-nul-name-');
    final observer = _ProfileSqlObserver();
    var ids = 0;
    var clocks = 0;
    final s = await openStorage(
      directory,
      hooks: StorageHooks(
        profileId: () => fixtureId(++ids),
        clock: () {
          clocks++;
          return instant;
        },
        executorFactory: (file) => NativeDatabase(file).interceptWith(observer),
      ),
    ) as StorageHandle;
    try {
      final original = await s.profiles.save(profileContent());
      for (final name in [
        '\u0000name',
        ' \u0000name',
        '\u0000',
        '  \u0000  ',
        ' \u0000\tname',
        '   \u0000\u0000name',
      ]) {
        // Exercise the real schema predicate without relying on a copied trim.
        final length = await s.useDatabase(
          (db) async =>
              (await db
                      .customSelect(
                        'SELECT length(trim(?)) AS name_length',
                        variables: [Variable.withString(name)],
                      )
                      .getSingle())
                  .read<int>('name_length'),
        );
        expect(length, 0);
        for (final id in [null, original.id]) {
          final transactions = observer.transactions;
          final selects = observer.selects;
          await expectLater(
            s.profiles.save(profileContent(null, name), id: id),
            throwsA(coreError(CoreErrorCode.invalidInput)),
          );
          expect(observer.transactions, transactions);
          expect(observer.selects, selects);
          expect(ids, 1);
          expect(clocks, 1);
        }
        final unchanged = await s.profiles.read(original.id);
        expect(unchanged.name, original.name);
        expect(unchanged.portHint, original.portHint);
        expect(unchanged.updatedAt, original.updatedAt);
      }
      expect((await s.profiles.list()).items, hasLength(1));
    } finally {
      await s.close();
      directory.deleteSync(recursive: true);
    }
  });

  test(
    'schema-compatible NUL names preserve exact text through update and reopen',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'meshchan-nul-text-',
      );
      CoreStorage s = await CoreStorage.open(dataDirectory: directory);
      final expected = <LocalId, String>{};
      try {
        for (final name in [
          'name\u0000',
          ' name\u0000tail ',
          '\t\u0000name',
          '\n\u0000name',
          '\u00a0\u0000name',
          ' 中文 😀\u0000 e\u0301\uFFFD ',
        ]) {
          final created = await s.profiles.save(
            ProfileContent(
              name: name,
              portHint: '\u0000/local',
              parameters: sendParameters(),
            ),
          );
          expect(created.name, name);
          expect((await s.profiles.read(created.id)).name, name);
          final updated = await s.profiles.save(
            ProfileContent(
              name: '$name updated',
              portHint: '\u0000/local',
              parameters: sendParameters(),
            ),
            id: created.id,
          );
          expect(updated.name, '$name updated');
          expected[updated.id] = updated.name;
        }
        await s.close();
        s = await CoreStorage.open(dataDirectory: directory);
        expect((await s.profiles.list()).items, hasLength(expected.length));
        for (final entry in expected.entries) {
          final read = await s.profiles.read(entry.key);
          expect(read.name, entry.value);
          expect(read.portHint, '\u0000/local');
        }
      } finally {
        await s.close();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('stored name violating the NUL constraint is corrupt at accessed boundaries', () async {
    final directory = Directory.systemTemp.createTempSync(
      'meshchan-nul-damage-',
    );
    final s = await openStorage(directory) as StorageHandle;
    try {
      final original = await s.profiles.save(profileContent());
      await s.useDatabase((db) async {
        await db.customStatement('PRAGMA ignore_check_constraints = ON');
        await db.customStatement('UPDATE stored_profiles SET name = ?', [
          ' \u0000name',
        ]);
      });
      for (final action in [
        () => s.profiles.read(original.id),
        () => s.profiles.list(),
        () => s.profiles.save(profileContent(), id: original.id),
        () => s.resolveParameters(
          SendParameterRequest(profileId: original.id, payload: []),
        ),
      ]) {
        await expectLater(
          action(),
          throwsA(coreError(CoreErrorCode.databaseCorrupt)),
        );
      }
    } finally {
      await s.close();
      directory.deleteSync(recursive: true);
    }
  });
}
