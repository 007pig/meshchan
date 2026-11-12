import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart'
    show
        MeshchanDiagnosticMessage,
        DiagnosticKind,
        decodeDiagnosticPayload,
        encodeDiagnosticPayload;
import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart';

import '../../../packages/meshchan_core/test/history/support.dart' as f;
import 'datagram_cli_test.dart'
    show args, datagram, incomingPing, ImmediateSignal;
import 'session_cli_test.dart' show ControlledSink;
import 'support/audited_storage.dart';

void main() {
  late f.Fixture fixture;
  setUp(() {
    fixture = f.Fixture();
  });
  tearDown(() => fixture.close());

  Future<({int code, Map<String, dynamic> json, String err})> execute(
    List<String> arguments, {
    AuditedStorage? storage,
    f.FakeCompanionTransport? transport,
    Stream<CliStopRequest>? stops,
    StringSink? output,
    StringSink? error,
  }) async {
    final out = StringBuffer(), err = StringBuffer();
    final code = await runCli(
      ['--data-dir', fixture.directory.path, ...arguments],
      output: output ?? out,
      error: error ?? err,
      openStorage: storage == null ? null : (_) async => storage,
      createTransport: (_) =>
          transport ?? (throw StateError('Unexpected device.')),
      stopRequests: stops,
    );
    final lines = const LineSplitter().convert(out.toString());
    return (
      code: code,
      json: lines.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(lines.last) as Map<String, dynamic>,
      err: err.toString(),
    );
  }

  f.FakeCompanionTransport auto(String operation, {bool failWrite = false}) {
    final t = f.FakeCompanionTransport();
    t.sending = (bytes, index) async {
      scheduleMicrotask(() {
        switch (bytes[0]) {
          case 0x16:
            t.receive(f.deviceInfo());
          case 0x01:
            t.receive(f.selfInfo());
          case 0x0a:
            if (operation == 'listen') {
              t.receive(datagram([1], type: 0));
            } else if (operation == 'respond') {
              t.receive(incomingPing());
            } else {
              t.receive([0x0a]);
            }
          case 0x3e:
            if (operation == 'ping') {
              final ping = decodeMessage(bytes);
              t.receive(datagram(pongMessage(ping)));
            }
            t.receive([0]);
        }
      });
    };
    return t;
  }

  Future<AuditedStorage> open() async => AuditedStorage(await fixture.open());
  Future<void> seedProfile(
    AuditedStorage s,
    ProfileParameters parameters,
  ) async {
    final profile = await s.profiles.save(
      ProfileContent(
        name: 'SECRET_PROFILE',
        parameters: parameters,
        portHint: 'SECRET_HINT',
      ),
    );
    await s.settings.save(AppSettings(defaultProfileId: profile.id));
    await s.history.waitForMaintenance();
  }

  for (final operation in ['send', 'listen', 'ping', 'respond']) {
    test(
      '$operation without record uses resolver and retains legacy final output with zero history rows',
      () async {
        final s = await open();
        final t = auto(operation);
        final arguments = [
          ...args(operation),
          if (operation == 'listen') '--max-entries=1',
        ];
        final r = await execute(arguments, storage: s, transport: t);
        expect(r.code, 0, reason: r.err);
        expect(s.events.first, 'resolve');
        expect(s.operation, null);
        expect(s.closes, 1);
        expect(s.state, StorageState.closed);
        expect(r.json.containsKey('recording'), false);
        expect(r.json.containsKey('storageClose'), false);
        expect(r.json['cleanup']['state'], 'succeeded');
        if (operation == 'listen') {
          expect(r.json['event'], 'end');
          expect(r.json['result']['matchingDatagrams'], 1);
        }
        final reopened = await fixture.open();
        expect(await fixture.count(reopened), 0);
      },
    );
    test(
      '$operation records once, commits required phases, closes, and persists actual version and safe facts',
      () async {
        final control = f.HistoryControl();
        final s = AuditedStorage(await fixture.open(control: control));
        final t = auto(operation);
        var preparedAtFactory = false;
        s.onRecord = (op) {
          control.afterCommit = () {
            preparedAtFactory = true;
          };
        };
        final original = t.opening;
        t.opening = () async {
          expect(preparedAtFactory, true);
          await original?.call();
        };
        final r = await execute(
          [
            ...args(operation),
            '--record',
            if (operation == 'listen') '--max-entries=1',
          ],
          storage: s,
          transport: t,
        );
        expect(r.code, 0, reason: r.err);
        expect(t.openCount, 1);
        expect(t.closeCount, 1);
        expect(s.closes, 1);
        expect(r.json['recording']['fullySuccessful'], true);
        for (final phase in ['registration', 'logical', 'cleanup']) {
          expect(r.json['recording'][phase]['state'], 'committed');
        }
        expect(r.json['recording']['cleanup']['finalCleanup'], true);
        expect(r.json['storageClose']['state'], 'closed');
        if (operation == 'listen') {
          expect(r.json['event'], 'end');
        }
        final reopened = await fixture.open();
        final run = await reopened.history.read(
          LocalId(r.json['recording']['runId'] as String),
        );
        expect(run.appVersion, '0.1.0-dev.3');
        expect(run.operation.code, operation);
        expect(run.result!.reason, LogicalReason.completed);
        expect(s.events.where((e) => e == 'record'), hasLength(1));
        expect(s.events.contains('maintain'), false);
        expect(s.events.indexOf('wait'), lessThan(s.events.indexOf('close')));
      },
    );
  }

  test('recorded listen emits one end and no per-entry event; unrecorded listen retains datagrams', () async {
    for (final record in [false, true]) {
      final s = await open();
      final t = auto('listen');
      final sink = StringBuffer();
      final r = await execute(
        [...args('listen'), '--max-entries=1', if (record) '--record'],
        storage: s,
        transport: t,
        output: sink,
      );
      expect(r.code, 0);
      final lines = const LineSplitter()
          .convert(sink.toString())
          .map((line) => jsonDecode(line) as Map)
          .toList();
      expect(
        lines.map((r) => r['event']),
        record ? ['end'] : ['datagram', 'end'],
      );
    }
  });

  test('default send preset supplies missing fields and parser defaults remain absent', () async {
    final s = await open();
    await seedProfile(
      s,
      SendProfileParameters(
        budgets: const ProfileBudgets(
          taskTimeoutSeconds: 7,
          requestTimeoutSeconds: 9,
          initializationTimeoutSeconds: 18,
        ),
        sendChannelIndex: 0,
        route: ProfileRoute(routeDescriptor: 0),
        dataType: 123,
      ),
    );
    final t = auto('send');
    final r = await execute(
      ['datagram', 'send', '--port= exact path ', '--payload-hex=', '--json'],
      storage: s,
      transport: t,
    );
    expect(r.code, 0, reason: r.err);
    final p = s.effective!.parameters as SendProfileParameters;
    expect(p.budgets.requestTimeoutSeconds, 9);
    expect(p.budgets.initializationTimeoutSeconds, 18);
    expect(p.sendChannelIndex, 0);
    expect(p.dataType, 123);
    expect(s.effective!.content, isEmpty);
    final request = s.request as SendParameterRequest;
    expect(request.overrides.budgets.requestTimeoutSeconds, null);
    expect(request.overrides.route!.path, null);
    expect(t.sent.last, [0x3e, 0, 0, 123, 0]);
  });

  test('explicit values including zero, empty route path and content override selected profile independently', () async {
    final s = await open();
    final profile = await s.profiles.save(
      ProfileContent(
        name: 'p',
        parameters: SendProfileParameters(
          budgets: const ProfileBudgets(
            taskTimeoutSeconds: 3,
            startupDelayMilliseconds: 1,
          ),
          sendChannelIndex: 7,
          route: ProfileRoute(routeDescriptor: 1, path: [0xaa]),
          dataType: 9,
        ),
      ),
    );
    final t = auto('send');
    final r = await execute(
      [
        'datagram',
        'send',
        '--profile=${profile.id.value}',
        '--port=exact',
        '--send-channel=0',
        '--route-descriptor=0',
        '--path-hex=',
        '--startup-delay=0',
        '--text=',
        '--json',
      ],
      storage: s,
      transport: t,
    );
    expect(r.code, 0, reason: r.err);
    final p = s.effective!.parameters as SendProfileParameters;
    expect(p.sendChannelIndex, 0);
    expect(p.route.path, isEmpty);
    expect(p.route.routeDescriptor, 0);
    expect(p.budgets.startupDelayMilliseconds, 0);
    expect(s.effective!.content, isEmpty);
  });

  for (final override in ['', '--all-data-types', '--data-type=0']) {
    test(
      'listen filter preserves inherit, clear and explicit zero: $override',
      () async {
        final s = await open();
        await seedProfile(
          s,
          const ListenProfileParameters(
            budgets: ProfileBudgets(taskTimeoutSeconds: 2),
            receiveChannelIndex: 2,
            listenDurationSeconds: 1,
            maxEntries: 1,
            dataType: 7,
          ),
        );
        final r = await execute(
          [
            'datagram',
            'listen',
            '--port=x',
            '--json',
            if (override.isNotEmpty) override,
          ],
          storage: s,
          transport: auto('listen'),
        );
        expect(r.code, 0, reason: r.err);
        final p = s.effective!.parameters as ListenProfileParameters;
        expect(
          p.dataType,
          override.isEmpty
              ? 7
              : override == '--all-data-types'
              ? null
              : 0,
        );
        expect(r.json['result']['matchingDatagrams'], override.isEmpty ? 0 : 1);
      },
    );
  }

  test('selected profile bypasses dangling default while absent selection reports not_found', () async {
    for (final explicit in [false, true]) {
      final s = await open();
      final profile = await s.profiles.save(
        ProfileContent(
          name: 'p',
          parameters: SendProfileParameters(
            budgets: const ProfileBudgets(taskTimeoutSeconds: 2),
            sendChannelIndex: 3,
            route: ProfileRoute(routeDescriptor: 0xff),
            dataType: 1,
          ),
        ),
      );
      await (s.inner as dynamic).useDatabase((db) async {
        await db.customStatement('PRAGMA foreign_keys=OFF');
        await db.customStatement(
          "INSERT OR REPLACE INTO stored_settings VALUES (1, '00000000000000000000000000000001', 1000)",
        );
        await db.customStatement('PRAGMA foreign_keys=ON');
      });
      final t = auto('send');
      final r = await execute(
        [...args('send'), if (explicit) '--profile=${profile.id.value}'],
        storage: s,
        transport: t,
      );
      expect(r.code, explicit ? 0 : 64, reason: r.err);
      expect(t.openCount, explicit ? 1 : 0);
    }
  });

  test('merged capacity and inherited path are validated before factory; hint never authorizes a port', () async {
    for (final mode in ['path', 'capacity', 'port', 'mismatch', 'missing']) {
      final s = await open();
      final profile = await s.profiles.save(
        ProfileContent(
          name: 'p',
          portHint: 'SECRET_HINT',
          parameters: SendProfileParameters(
            budgets: const ProfileBudgets(taskTimeoutSeconds: 2),
            sendChannelIndex: 0,
            route: ProfileRoute(routeDescriptor: 1, path: [0xaa]),
            dataType: 1,
          ),
        ),
      );
      await s.settings.save(AppSettings(defaultProfileId: profile.id));
      final t = auto('send');
      final r = await execute(
        [
          'datagram',
          mode == 'mismatch' ? 'listen' : 'send',
          if (mode != 'port') '--port=x',
          '--json',
          if (mode != 'mismatch')
            '--payload-hex=${mode == 'capacity' ? '00' * 172 : ''}',
          if (mode == 'path') '--route-descriptor=0',
          if (mode == 'missing') '--profile=00000000000000000000000000000001',
        ],
        storage: s,
        transport: t,
      );
      expect(r.code, 64, reason: mode);
      expect(t.openCount, 0);
      expect(t.sent, isEmpty);
      if (mode == 'port') await s.close();
    }
  });

  test('registration fault starts neither transport nor subscription plan and reports notAttempted saves', () async {
    final control = f.HistoryControl();
    final inner = await fixture.open(control: control);
    final s = AuditedStorage(inner);
    s.onRecord = (_) {
      control.beforeCommit = () async => throw StateError('SECRET_PREPARED');
    };
    var device = 0, subscribed = 0, canceled = 0;
    final stream = StreamController<CliStopRequest>(
      onListen: () {
        subscribed++;
      },
      onCancel: () {
        canceled++;
      },
    );
    final out = StringBuffer(), err = StringBuffer();
    final code = await runCli(
      ['--data-dir', fixture.directory.path, ...args('send'), '--record'],
      output: out,
      error: err,
      openStorage: (_) async => s,
      createTransport: (_) {
        device++;
        throw StateError('unexpected');
      },
      stopRequests: stream.stream,
    );
    expect(code, 74);
    expect(device, 0);
    expect(s.planFactories, 0);
    expect(s.transportFactories, 0);
    expect(subscribed, 1);
    expect(canceled, 1);
    final result = await s.operation!.done;
    expect(result.logical, null);
    expect(result.registration.state, RecordingSaveState.failed);
    expect(result.logicalSave.state, RecordingSaveState.notAttempted);
    expect(result.cleanupSave.state, RecordingSaveState.notAttempted);
    expect((jsonDecode(out.toString()) as Map)['result'], null);
    expect('$out$err', isNot(contains('SECRET_PREPARED')));
    await stream.close();
  });

  for (final phase in ['logical', 'cleanup']) {
    test(
      '$phase commit fault preserves actual success facts, cleanup and one send',
      () async {
        final control = f.HistoryControl();
        final s = AuditedStorage(await fixture.open(control: control));
        final t = auto('send');
        if (phase == 'logical') {
          t.closing = () async {
            control.beforeCommit = () async => throw StateError('SECRET_SAVE');
          };
        } else {
          control.updated = (statement, values) {
            if (statement.contains('stored_runs') &&
                values.any(
                  (v) => v is String && v.contains('"aggregate":"succeeded"'),
                )) {
              control.beforeCommit = () async =>
                  throw StateError('SECRET_SAVE');
            }
          };
        }
        final r = await execute(
          [...args('send'), '--record'],
          storage: s,
          transport: t,
        );
        expect(r.code, 74, reason: r.err);
        expect(r.json['result']['reason'], 'completed');
        expect(r.json['result']['send']['deviceAcceptanceConfirmed'], true);
        expect(r.json['cleanup']['aggregate'], 'succeeded');
        expect(t.sent.where((b) => b[0] == 0x3e), hasLength(1));
        expect(r.json['recording'][phase]['state'], 'failed');
        expect(r.err, isNot(contains('SECRET_SAVE')));
      },
    );
  }

  test('logical result is observable before native cleanup and storage remains busy until real release', () async {
    final s = await open();
    final t = auto('send');
    final release = Completer<void>();
    t.closing = () => release.future;
    final out = StringBuffer(), err = StringBuffer();
    var ended = false;
    final pending =
        execute(
          [...args('send'), '--record'],
          storage: s,
          transport: t,
          output: out,
          error: err,
        ).then((r) {
          ended = true;
          return r;
        });
    await f.until(() => s.operation != null);
    await s.operation!.logicalSaved;
    expect('$err', contains('"reason":"completed"'));
    expect('$out', isEmpty);
    expect(ended, false);
    await expectLater(
      CoreStorage.open(dataDirectory: fixture.directory),
      throwsA(f.coreError(CoreErrorCode.dataDirectoryBusy)),
    );
    release.complete();
    expect((await pending).code, 0);
    expect(s.state, StorageState.closed);
  });

  for (final signal in CliStopRequest.values) {
    test(
      'recorded $signal latches synchronous cancellation before storage admission and starts zero devices',
      () async {
        final s = await open();
        final t = auto('send');
        var cancellations = 0;
        final source = StreamController<CliStopRequest>(
          onCancel: () {
            cancellations++;
          },
        );
        final stream = signal == CliStopRequest.sigint
            ? ImmediateSignal(source.stream)
            : ImmediateTerm(source.stream);
        final r = await execute(
          [...args('send'), '--record'],
          storage: s,
          transport: t,
          stops: stream,
        );
        expect(r.code, signal == CliStopRequest.sigint ? 130 : 143);
        expect(r.json['result'], null);
        expect(r.json['recording'], null);
        expect(t.openCount, 0);
        expect(t.closeCount, 0);
        expect(cancellations, 1);
        await source.close();
      },
    );
  }

  test('recorded output failure cancels and waits for required signal subscription and transport cleanup', () async {
    final s = await open();
    final t = auto('send');
    final release = Completer<void>(), cancel = Completer<void>();
    t.closing = () => release.future;
    final source = StreamController<CliStopRequest>(
      onCancel: () => cancel.future,
    );
    final sink = ControlledSink();
    final err = ControlledSink();
    var ended = false;
    final pending =
        execute(
          [...args('send'), '--record'],
          storage: s,
          transport: t,
          stops: source.stream,
          output: sink,
          error: err,
        ).then((r) {
          ended = true;
          return r;
        });
    await f.until(() => s.operation != null);
    await s.operation!.logical;
    // Logical result writes stderr while cleanup is pending; a sink done error
    // triggers cancellation after the result is already frozen as successful.
    err.completion.completeError(StateError('SECRET_OUTPUT'));
    await f.turns();
    expect(ended, false);
    release.complete();
    await f.turns();
    expect(ended, false);
    cancel.complete();
    final r = await pending;
    expect(r.code, 74);
    final data = jsonDecode(sink.buffer.toString());
    expect(data['result']['reason'], 'completed');
    expect(data['reason'], 'output_failure');
    expect(t.closeCount, 1);
    await source.close();
  });

  test('logical success with actual cleanup failure is independent from saves and returns 69', () async {
    final s = await open();
    final t = auto('ping')
      ..closing = () async => throw StateError('SECRET_CLOSE');
    final r = await execute(
      [...args('ping'), '--record'],
      storage: s,
      transport: t,
    );
    expect(r.code, 69, reason: r.err);
    expect(r.json['result']['roundTripSucceeded'], true);
    expect(r.json['cleanup']['core']['state'], 'failed');
    expect(r.json['recording']['cleanup']['state'], 'committed');
    expect(r.err, isNot(contains('SECRET_CLOSE')));
  });
  test(
    'recorded early PONG survives failed local write without a successful RTT',
    () async {
      final s = await open();
      final t = auto('ping');
      final write = Completer<void>();
      final normal = t.sending!;
      t.sending = (bytes, index) {
        if (bytes[0] == 0x3e) {
          scheduleMicrotask(() {
            t.receive([0]);
            t.receive(datagram(pongMessage(decodeMessage(bytes))));
          });
          return write.future;
        }
        return normal(bytes, index);
      };
      final pending = execute(
        [...args('ping'), '--record'],
        storage: s,
        transport: t,
      );
      await f.until(() => t.sent.any((b) => b[0] == 0x3e));
      await f.turns();
      write.completeError(StateError('SECRET_WRITE'));
      final r = await pending;
      expect(r.code, 69, reason: r.err);
      expect(r.json['result']['matchingPongObserved'], true);
      expect(r.json['result']['applicationRttUs'], null);
      expect(r.json['result']['roundTripSucceeded'], false);
      expect(r.json['result']['send']['localOkObserved'], true);
      expect(r.json['result']['send']['deviceAcceptanceConfirmed'], false);
      expect(r.err, isNot(contains('SECRET_WRITE')));
    },
  );

  for (final signal in CliStopRequest.values) {
    test(
      'recorded frozen session failure beats later $signal before result delivery',
      () async {
        final s = await open();
        final t = f.FakeCompanionTransport();
        final source = StreamController<CliStopRequest>(sync: true);
        final pending = execute(
          [...args('ping'), '--record'],
          storage: s,
          transport: t,
          stops: source.stream,
        );
        await f.until(() => t.sent.isNotEmpty);
        t.receiveError(StateError('SECRET_NATIVE'));
        source.add(signal);
        final r = await pending;
        expect(r.code, 69, reason: r.err);
        expect(r.json['reason'], 'task_failure');
        // Task cancellation may win before its asynchronous session callback;
        // the typed session evidence still preserves the earlier failure.
        expect(r.json['failure']['session']['kind'], 'transport');
        expect(t.closeCount, 1);
        expect(r.err, isNot(contains('SECRET_NATIVE')));
        await source.close();
      },
    );
  }

  test('signal during prepared commit is latched before any transport or plan factory', () async {
    final control = f.HistoryControl();
    final s = AuditedStorage(await fixture.open(control: control));
    final entered = Completer<void>(), release = Completer<void>();
    s.onRecord = (_) {
      control.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
    };
    final source = StreamController<CliStopRequest>(sync: true);
    final t = auto('send');
    final pending = execute(
      [...args('send'), '--record'],
      storage: s,
      transport: t,
      stops: source.stream,
    );
    await entered.future;
    source.add(CliStopRequest.sigterm);
    expect(t.openCount, 0);
    release.complete();
    final r = await pending;
    expect(r.code, 143);
    expect(r.json['result']['reason'], 'canceled');
    expect(s.transportFactories, 0);
    expect(s.planFactories, 0);
    expect(s.closes, 1);
    await source.close();
  });

  test('invocation signal cancellation failure does not rewrite successful core cleanup', () async {
    final s = await open();
    final t = auto('send');
    final release = Completer<void>();
    t.closing = () => release.future;
    final source = StreamController<CliStopRequest>(
      onCancel: () async => throw StateError('SECRET_CANCEL'),
    );
    final pending = execute(
      [...args('send'), '--record'],
      storage: s,
      transport: t,
      stops: source.stream,
    );
    await f.until(() => t.closeCount == 1);
    expect(s.state, StorageState.open);
    release.complete();
    final r = await pending;
    expect(r.code, 69);
    expect(r.json['result']['reason'], 'completed');
    expect(r.json['cleanup']['hostSubscriptions']['state'], 'succeeded');
    expect(r.json['signalCleanup']['state'], 'failed');
    expect(r.json['recording']['fullySuccessful'], true);
    expect(r.json['cleanup']['core']['state'], 'succeeded');
    expect(r.err, isNot(contains('SECRET_CANCEL')));
    await source.close();
  });

  test('recorded zero-response responder remains a finite result without round-trip claims', () async {
    final s = await open();
    final t = f.FakeCompanionTransport();
    t.sending = (bytes, index) async {
      scheduleMicrotask(() {
        if (bytes[0] == 0x16) t.receive(f.deviceInfo());
        if (bytes[0] == 0x01) t.receive(f.selfInfo());
        if (bytes[0] == 0x0a) t.receive([0x0a]);
      });
    };
    final r = await execute(
      [...args('respond'), '--record', '--duration=1'],
      storage: s,
      transport: t,
    );
    expect(r.code, 0, reason: r.err);
    expect(r.json['result']['responseAttempts'], 0);
    expect(r.json['result']['localResponsesConfirmed'], 0);
    expect(r.json['result'].containsKey('roundTripSucceeded'), false);
    expect(r.json['result']['lastSend']['attempted'], false);
    expect(r.json['result']['lastSend']['dispatched'], null);
  });

  test('exact explicit port and invocation bytes are forwarded while diagnostics omit local secrets', () async {
    final s = await open();
    final t = auto('send');
    final out = StringBuffer(), err = StringBuffer();
    final paths = <String>[];
    final code = await runCli(
      [
        '--data-dir',
        fixture.directory.path,
        'datagram',
        'send',
        '--port= SECRET_PORT\t ',
        '--send-channel=0',
        '--data-type=1',
        '--route-descriptor=0',
        '--task-timeout=2',
        '--text=SECRET_CONTENT中文😀',
        '--record',
        '--json',
      ],
      output: out,
      error: err,
      openStorage: (_) async => s,
      createTransport: (path) {
        paths.add(path);
        return t;
      },
    );
    expect(code, 0);
    expect(paths, [' SECRET_PORT\t ']);
    expect(t.sent.last.sublist(5), utf8.encode('SECRET_CONTENT中文😀'));
    expect('$out$err', isNot(contains('SECRET_')));
    final exported = StringBuffer();
    expect(
      await runCli(
        ['--data-dir', fixture.directory.path, 'history', 'export'],
        output: exported,
        error: StringBuffer(),
      ),
      0,
    );
    expect('$exported', isNot(contains('SECRET_')));
  });

  test(
    'unexpected factory bug closes the business owner before propagating',
    () async {
      final s = await open();
      await expectLater(execute(args('send'), storage: s), throwsStateError);
      expect(s.closes, 1);
      expect(s.state, StorageState.closed);
      expect((await fixture.open()).state, StorageState.open);
    },
  );
  test('a corrupt selected preset is rejected even when every explicit override is valid', () async {
    final s = await open();
    final profile = await s.profiles.save(
      ProfileContent(
        name: 'p',
        parameters: SendProfileParameters(
          budgets: const ProfileBudgets(taskTimeoutSeconds: 2),
          sendChannelIndex: 0,
          route: ProfileRoute(routeDescriptor: 0),
          dataType: 1,
        ),
      ),
    );
    await (s.inner as dynamic).useDatabase((db) async {
      await db.customStatement(
        "UPDATE stored_profiles SET parameters_json = '{}' ",
      );
    });
    final t = auto('send');
    final r = await execute(
      [...args('send'), '--profile=${profile.id.value}'],
      storage: s,
      transport: t,
    );
    expect(r.code, 74);
    expect(r.json['failure']['code'], 'database_corrupt');
    expect(t.openCount, 0);
    expect(s.closes, 1);
  });
  for (final signal in CliStopRequest.values) {
    test(
      'recorded late $signal remains observed while native cleanup is pending',
      () async {
        final s = await open();
        final t = auto('send');
        final release = Completer<void>();
        t.closing = () => release.future;
        final source = StreamController<CliStopRequest>(sync: true);
        final pending = execute(
          [...args('send'), '--record'],
          storage: s,
          transport: t,
          stops: source.stream,
        );
        await f.until(() => s.operation != null);
        await s.operation!.logicalSaved;
        source.add(signal);
        await f.turns();
        release.complete();
        final r = await pending;
        expect(r.code, signal == CliStopRequest.sigint ? 130 : 143);
        expect(r.json['reason'], signal.name);
        expect(r.json['result']['reason'], 'completed');
        expect(r.json['recording']['fullySuccessful'], true);
        expect(t.closeCount, 1);
        await source.close();
      },
    );
  }
}

// Test-only independent packet decoding uses the public protocol API.
MeshchanDiagnosticMessage decodeMessage(Uint8List bytes) =>
    decodeDiagnosticPayload(Uint8List.sublistView(bytes, 5)).message!;
Uint8List pongMessage(MeshchanDiagnosticMessage ping) =>
    encodeDiagnosticPayload(
      MeshchanDiagnosticMessage(
        kind: DiagnosticKind.pong,
        runNonce: ping.runNonce,
        requestId: ping.requestId,
        senderTestId: ping.targetTestId,
        targetTestId: ping.senderTestId,
        content: ping.content,
      ),
    );

final class ImmediateTerm extends Stream<CliStopRequest> {
  ImmediateTerm(this.source);
  final Stream<CliStopRequest> source;
  @override
  StreamSubscription<CliStopRequest> listen(
    void Function(CliStopRequest)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    onData?.call(CliStopRequest.sigterm);
    return subscription;
  }
}
