import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:test/test.dart';

import '../storage/database_test.dart' show coreError;
import '../storage/fixtures.dart' show fixtureId, runs;
import 'draft_repository_test.dart' show Control;
import 'profile_fixtures.dart';

SendOverrides completeSend({RouteOverrides? route, BudgetOverrides? budgets}) =>
    SendOverrides(
      budgets: budgets ?? const BudgetOverrides(taskTimeoutSeconds: 1),
      sendChannelIndex: 0,
      dataType: 1,
      route: route ?? RouteOverrides(routeDescriptor: 0xff),
    );

void main() {
  late Directory directory;
  late StorageHandle s;
  late Control control;
  var writesAllowed = true;
  var ids = 0, clocks = 0;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('meshchan-resolution-');
    writesAllowed = true;
    ids = clocks = 0;
    control = Control(readTable: 'stored_profiles');
    s = await openStorage(
      directory,
      hooks: StorageHooks(
        profileId: () {
          expect(writesAllowed, isTrue);
          return fixtureId(++ids);
        },
        clock: () {
          expect(writesAllowed, isTrue);
          clocks++;
          return DateTime.utc(2026);
        },
        executorFactory: (file) => NativeDatabase(file).interceptWith(control),
      ),
    ) as StorageHandle;
  });
  tearDown(() async {
    await s.close();
    directory.deleteSync(recursive: true);
  });

  test('explicit/default/no profile selection and mismatch/missing references cannot be bypassed', () async {
    final send = await s.profiles.save(profileContent());
    final listen = await s.profiles.save(profileContent(listenParameters()));
    await s.settings.save(AppSettings(defaultProfileId: listen.id));
    expect(
      (await s.resolveParameters(const ListenParameterRequest())).profileId,
      listen.id,
    );
    expect(
      (await s.resolveParameters(
        SendParameterRequest(profileId: send.id, payload: []),
      )).profileId,
      send.id,
    );
    await expectLater(
      s.resolveParameters(
        SendParameterRequest(payload: [], overrides: completeSend()),
      ),
      throwsA(coreError(CoreErrorCode.invalidInput)),
    );
    await expectLater(
      s.resolveParameters(
        SendParameterRequest(
          profileId: fixtureId(999),
          payload: [],
          overrides: completeSend(),
        ),
      ),
      throwsA(coreError(CoreErrorCode.notFound)),
    );
    await s.useDatabase((db) async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement(
        'UPDATE stored_settings SET default_profile_id = ?',
        [fixtureId(999).value],
      );
      await db.customStatement('PRAGMA foreign_keys = ON');
    });
    await expectLater(
      s.resolveParameters(
        SendParameterRequest(payload: [], overrides: completeSend()),
      ),
      throwsA(coreError(CoreErrorCode.notFound)),
    );
    expect(
      (await s.resolveParameters(
        SendParameterRequest(profileId: send.id, payload: []),
      )).profileId,
      send.id,
    );
    // Explicit selection must not even decode unrelated corrupt settings.
    await s.useDatabase((db) async {
      await db.customStatement('PRAGMA ignore_check_constraints = ON');
      await db.customStatement(
        'UPDATE stored_settings SET diagnostic_history_limit = 0',
      );
    });
    expect(
      (await s.resolveParameters(
        SendParameterRequest(profileId: send.id, payload: []),
      )).profileId,
      send.id,
    );
    await s.settings.restoreDefaults();
    for (final storedNull in [false, true]) {
      if (storedNull) await s.settings.save(AppSettings());
      final result = await s.resolveParameters(
        SendParameterRequest(payload: [], overrides: completeSend()),
      );
      expect(result.profileId, isNull);
      final p = result.parameters as SendProfileParameters;
      expect(p.sendChannelIndex, 0);
      expect(p.budgets.requestTimeoutSeconds, 5);
      expect(p.budgets.initializationTimeoutSeconds, 15);
      expect(p.budgets.startupDelayMilliseconds, 0);
      expect(p.budgets.taskTimeoutSeconds, 1);
    }
  });

  test('partial budgets and endpoints inherit per field; explicit zero is preserved', () async {
    final profile = await s.profiles.save(
      profileContent(
        pingParameters(
          budgets: const ProfileBudgets(
            requestTimeoutSeconds: 9,
            initializationTimeoutSeconds: 20,
            startupDelayMilliseconds: 5,
            taskTimeoutSeconds: 1,
          ),
        ),
      ),
    );
    final result = await s.resolveParameters(
      PingParameterRequest(
        profileId: profile.id,
        content: [],
        overrides: PingOverrides(
          budgets: const BudgetOverrides(startupDelayMilliseconds: 0),
          sendChannelIndex: 0,
          endpoints: const EndpointOverrides(localTestId: 7),
          route: RouteOverrides(routeDescriptor: 0),
        ),
      ),
    );
    final p = result.parameters as PingProfileParameters;
    expect(p.sendChannelIndex, 0);
    expect(p.receiveChannelIndex, 4);
    expect(p.route.routeDescriptor, 0);
    expect(p.budgets.requestTimeoutSeconds, 9);
    expect(p.budgets.initializationTimeoutSeconds, 20);
    expect(p.budgets.startupDelayMilliseconds, 0);
    expect(p.budgets.taskTimeoutSeconds, 1); // Earlier task deadline is legal.
    expect(p.endpoints.localTestId, 7);
    expect(p.endpoints.peerTestId, 2);
    for (final overrides in [
      const PingOverrides(endpoints: EndpointOverrides(localTestId: 2)),
      const PingOverrides(
        budgets: BudgetOverrides(
          initializationTimeoutSeconds: 1,
          startupDelayMilliseconds: 1000,
        ),
      ),
    ]) {
      await expectLater(
        s.resolveParameters(
          PingParameterRequest(
            profileId: profile.id,
            content: [],
            overrides: overrides,
          ),
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
  });

  test(
    'listen filter has inherit, explicit null and explicit zero states',
    () async {
      final p = await s.profiles.save(
        profileContent(listenParameters(dataType: 42)),
      );
      for (final pair in <(DataTypeOverride?, int?)>[
        (null, 42),
        (const DataTypeOverride(null), null),
        (const DataTypeOverride(0), 0),
        (const DataTypeOverride(65535), 65535),
      ]) {
        final result = await s.resolveParameters(
          ListenParameterRequest(
            profileId: p.id,
            overrides: ListenOverrides(
              dataType: pair.$1,
              receiveChannelIndex: 0,
            ),
          ),
        );
        expect(
          (result.parameters as ListenProfileParameters).dataType,
          pair.$2,
        );
        expect(
          (result.parameters as ListenProfileParameters).receiveChannelIndex,
          0,
        );
      }
      for (final value in [-1, 65536]) {
        await expectLater(
          s.resolveParameters(
            ListenParameterRequest(
              profileId: p.id,
              overrides: ListenOverrides(dataType: DataTypeOverride(value)),
            ),
          ),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
    },
  );

  test('path absence inherits, empty replaces, descriptor alone never repairs inherited path', () async {
    final p = await s.profiles.save(
      profileContent(
        sendParameters(route: ProfileRoute(routeDescriptor: 2, path: [7, 9])),
      ),
    );
    final result = await s.resolveParameters(
      SendParameterRequest(profileId: p.id, payload: []),
    );
    expect((result.parameters as SendProfileParameters).route.path, [7, 9]);
    for (final route in [
      RouteOverrides(path: []),
      RouteOverrides(routeDescriptor: 0),
      RouteOverrides(routeDescriptor: 0xff),
    ]) {
      await expectLater(
        s.resolveParameters(
          SendParameterRequest(
            profileId: p.id,
            payload: [],
            overrides: SendOverrides(route: route),
          ),
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
    final empty = await s.resolveParameters(
      SendParameterRequest(
        profileId: p.id,
        payload: [],
        overrides: SendOverrides(
          route: RouteOverrides(routeDescriptor: 0x80, path: []),
        ),
      ),
    );
    expect(
      (empty.parameters as SendProfileParameters).route.routeDescriptor,
      0x80,
    );
    expect((empty.parameters as SendProfileParameters).route.path, isEmpty);
    for (final byte in [-1, 256, 65536]) {
      await expectLater(
        s.resolveParameters(
          SendParameterRequest(
            payload: [],
            overrides: completeSend(
              route: RouteOverrides(routeDescriptor: 1, path: [byte]),
            ),
          ),
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
  });

  test('each mandatory diagnostic field has no implicit default', () async {
    for (final operation in [
      DiagnosticOperation.ping,
      DiagnosticOperation.respond,
    ]) {
      for (final missing in [
        'task',
        'send',
        'receive',
        'route',
        'local',
        'peer',
        'window',
      ]) {
        final budgets = BudgetOverrides(
          taskTimeoutSeconds: missing == 'task' ? null : 1,
        );
        final endpoints = EndpointOverrides(
          localTestId: missing == 'local' ? null : 1,
          peerTestId: missing == 'peer' ? null : 2,
        );
        final route = missing == 'route'
            ? null
            : RouteOverrides(routeDescriptor: 0);
        final request = operation == DiagnosticOperation.ping
            ? PingParameterRequest(
                content: [],
                overrides: PingOverrides(
                  budgets: budgets,
                  endpoints: endpoints,
                  route: route,
                  sendChannelIndex: missing == 'send' ? null : 0,
                  receiveChannelIndex: missing == 'receive' ? null : 0,
                  responseTimeoutSeconds: missing == 'window' ? null : 1,
                ),
              )
            : RespondParameterRequest(
                overrides: RespondOverrides(
                  budgets: budgets,
                  endpoints: endpoints,
                  route: route,
                  sendChannelIndex: missing == 'send' ? null : 0,
                  receiveChannelIndex: missing == 'receive' ? null : 0,
                  listenDurationSeconds: missing == 'window' ? null : 1,
                ),
              );
        await expectLater(
          s.resolveParameters(request),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
    }
  });

  test(
    'only real defaults fill gaps, required fields/content remain missing',
    () async {
      for (final request in <EffectiveParameterRequest>[
        SendParameterRequest(),
        PingParameterRequest(),
        const ListenParameterRequest(),
        const RespondParameterRequest(),
        SendParameterRequest(
          payload: [],
          overrides: SendOverrides(
            sendChannelIndex: 0,
            route: RouteOverrides(routeDescriptor: 0),
            dataType: 1,
          ),
        ),
        SendParameterRequest(
          payload: [],
          overrides: const SendOverrides(
            budgets: BudgetOverrides(taskTimeoutSeconds: 1),
            dataType: 1,
          ),
        ),
        SendParameterRequest(
          payload: [],
          overrides: const SendOverrides(
            budgets: BudgetOverrides(taskTimeoutSeconds: 1),
            sendChannelIndex: 0,
            dataType: 1,
          ),
        ),
        SendParameterRequest(
          payload: [],
          overrides: SendOverrides(
            budgets: const BudgetOverrides(taskTimeoutSeconds: 1),
            sendChannelIndex: 0,
            route: RouteOverrides(routeDescriptor: 0),
          ),
        ),
        PingParameterRequest(
          content: [],
          overrides: PingOverrides(
            budgets: const BudgetOverrides(taskTimeoutSeconds: 1),
            sendChannelIndex: 0,
            receiveChannelIndex: 0,
            route: RouteOverrides(routeDescriptor: 0),
          ),
        ),
        const ListenParameterRequest(
          overrides: ListenOverrides(
            budgets: BudgetOverrides(taskTimeoutSeconds: 1),
            receiveChannelIndex: 0,
          ),
        ),
        RespondParameterRequest(
          overrides: RespondOverrides(
            budgets: const BudgetOverrides(taskTimeoutSeconds: 1),
            sendChannelIndex: 0,
            receiveChannelIndex: 0,
            route: RouteOverrides(routeDescriptor: 0),
            endpoints: const EndpointOverrides(localTestId: 1, peerTestId: 2),
          ),
        ),
      ]) {
        await expectLater(
          s.resolveParameters(request),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
      for (final p in [sendParameters(), pingParameters()]) {
        final saved = await s.profiles.save(profileContent(p));
        await expectLater(
          s.resolveParameters(
            p is SendProfileParameters
                ? SendParameterRequest(profileId: saved.id)
                : PingParameterRequest(profileId: saved.id),
          ),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
        expect(
          (await s.resolveParameters(
            p is SendProfileParameters
                ? SendParameterRequest(profileId: saved.id, payload: [])
                : PingParameterRequest(profileId: saved.id, content: []),
          )).content,
          isEmpty,
        );
      }
      final listen = await s.resolveParameters(
        const ListenParameterRequest(
          overrides: ListenOverrides(
            budgets: BudgetOverrides(taskTimeoutSeconds: 1),
            receiveChannelIndex: 0,
            listenDurationSeconds: 1,
          ),
        ),
      );
      expect((listen.parameters as ListenProfileParameters).maxEntries, 128);
      final respond = await s.resolveParameters(
        RespondParameterRequest(
          overrides: RespondOverrides(
            budgets: const BudgetOverrides(taskTimeoutSeconds: 1),
            sendChannelIndex: 0,
            receiveChannelIndex: 0,
            route: RouteOverrides(routeDescriptor: 0),
            endpoints: const EndpointOverrides(localTestId: 1, peerTestId: 2),
            listenDurationSeconds: 1,
          ),
        ),
      );
      expect((respond.parameters as RespondProfileParameters).maxEntries, 128);
      expect((respond.parameters as RespondProfileParameters).maxResponses, 1);
      expect(respond.content, isNull);
    },
  );

  for (final route in [
    ProfileRoute(routeDescriptor: 0xff),
    ProfileRoute(routeDescriptor: 0),
    ProfileRoute(routeDescriptor: 0x40),
    ProfileRoute(routeDescriptor: 0x80),
    ProfileRoute(routeDescriptor: 0x60, path: List.filled(64, 255)),
  ]) {
    for (final ping in [false, true]) {
      test(
        '${ping ? "PING" : "raw"} route ${route.routeDescriptor} capacity and binary ownership',
        () async {
          final capacity = route.path.isEmpty
              ? (ping ? 131 : 165)
              : (ping ? 73 : 107);
          final p = await s.profiles.save(
            profileContent(
              ping
                  ? pingParameters(route: route)
                  : sendParameters(route: route),
            ),
          );
          for (final count in [0, capacity, capacity + 1]) {
            final bytes = List.generate(count, (i) => i.isEven ? 255 : 0);
            final request = ping
                ? PingParameterRequest(profileId: p.id, content: bytes)
                : SendParameterRequest(profileId: p.id, payload: bytes);
            if (count > capacity) {
              await expectLater(
                s.resolveParameters(request),
                throwsA(coreError(CoreErrorCode.invalidInput)),
              );
            } else {
              final result = await s.resolveParameters(request);
              expect(result.content, bytes);
            }
          }
        },
      );
    }
  }

  test(
    'UTF-8 examples use encoded byte count; arbitrary bytes require no UTF-8',
    () async {
      final p = await s.profiles.save(profileContent(pingParameters()));
      final okay = utf8.encode('😀' * 32); // 128 bytes, 64 UTF-16 units.
      expect(
        (await s.resolveParameters(
          PingParameterRequest(profileId: p.id, content: okay),
        )).content,
        okay,
      );
      await expectLater(
        s.resolveParameters(
          PingParameterRequest(
            profileId: p.id,
            content: utf8.encode('😀' * 33),
          ),
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
      expect(
        (await s.resolveParameters(
          PingParameterRequest(profileId: p.id, content: [255, 0, 128]),
        )).content,
        [255, 0, 128],
      );
      for (final bytes in [
        [-1],
        [256],
      ]) {
        await expectLater(
          s.resolveParameters(
            PingParameterRequest(profileId: p.id, content: bytes),
          ),
          throwsA(coreError(CoreErrorCode.invalidInput)),
        );
      }
    },
  );

  test('resolve is read-only; copies mutable inputs before waits and keeps independent immutable snapshot', () async {
    final profile = await s.profiles.save(
      profileContent(
        sendParameters(route: ProfileRoute(routeDescriptor: 2, path: [1, 2])),
      ),
    );
    await s.settings.save(
      AppSettings(defaultProfileId: profile.id, diagnosticHistoryLimit: 11),
    );
    await s.drafts.create(
      const DraftContent(body: 'never use this as payload'),
    );
    await s.useDatabase(
      (db) => db.into(db.storedRuns).insert(encodeRun(runs.first)),
    );
    Future<List<Object>> snapshot() => s.useDatabase(
      (db) async => [
        for (final table in [
          'stored_profiles',
          'stored_settings',
          'stored_drafts',
          'stored_runs',
        ])
          (await db.customSelect('SELECT * FROM $table').get())
              .map((r) => r.data)
              .toList(),
      ],
    );
    final before = await snapshot();
    final entered = Completer<void>(), release = Completer<void>();
    control.afterRead = () async {
      entered.complete();
      await release.future;
    };
    final path = Uint8List.fromList([9, 8]);
    final payload = Uint8List.fromList([255, 0]);
    writesAllowed = false;
    final future = s.resolveParameters(
      SendParameterRequest(
        payload: payload,
        overrides: SendOverrides(route: RouteOverrides(path: path)),
      ),
    );
    path[0] = 0;
    payload[0] = 0;
    await entered.future;
    release.complete();
    final result = await future;
    expect(result.content, [255, 0]);
    expect((result.parameters as SendProfileParameters).route.path, [9, 8]);
    expect(() => result.content![0] = 1, throwsUnsupportedError);
    expect(
      () => (result.parameters as SendProfileParameters).route.path[0] = 1,
      throwsUnsupportedError,
    );
    await expectLater(
      s.resolveParameters(SendParameterRequest()),
      throwsA(coreError(CoreErrorCode.invalidInput)),
    );
    expect(await snapshot(), before);
    expect(ids, 1);
    expect(clocks, 2); // One profile and one draft, no resolver clock.
    writesAllowed = true;
    await s.profiles.save(profileContent(listenParameters()), id: profile.id);
    await s.profiles.delete(profile.id);
    expect(result.operation, DiagnosticOperation.send);
    expect(result.profileId, profile.id);
    expect(result.content, [255, 0]);
    expect((result.parameters as SendProfileParameters).route.path, [9, 8]);
  });

  test('default settings/profile snapshot remains coherent while deletion is queued', () async {
    final p = await s.profiles.save(profileContent());
    await s.settings.save(AppSettings(defaultProfileId: p.id));
    final entered = Completer<void>(), release = Completer<void>();
    control.afterRead = () async {
      entered.complete();
      await release.future;
    };
    final resolving = s.resolveParameters(SendParameterRequest(payload: []));
    await entered.future;
    final deleting = s.profiles.delete(p.id);
    release.complete();
    expect((await resolving).profileId, p.id);
    await deleting;
    expect((await s.settings.read()).defaultProfileId, isNull);
  });
}
