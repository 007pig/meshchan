import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshctl/meshctl.dart';
import 'package:meshctl/src/process_io.dart';
import 'package:test/test.dart';

import '../../../packages/meshchan_core/test/history/support.dart' as f;
import 'datagram_cli_test.dart' show args, ImmediateSignal;
import 'session_cli_test.dart' show ControlledSink;
import 'support/audited_storage.dart';

void main() {
  late f.Fixture fixture;
  setUp(() {
    fixture = f.Fixture();
  });
  tearDown(() => fixture.close());
  Future<({int code, Map<String, dynamic>? data, String out, String err})> call(
    List<String> args, {
    CoreStorage? storage,
    StringSink? output,
  }) async {
    final out = StringBuffer(), err = StringBuffer();
    final code = await runCli(
      ['--data-dir', fixture.directory.path, ...args],
      output: output ?? out,
      error: err,
      openStorage: storage == null ? null : (_) async => storage,
      createTransport: (_) => throw StateError('Offline hardware.'),
    );
    return (
      code: code,
      data: out.isEmpty ? null : jsonDecode('$out') as Map<String, dynamic>,
      out: '$out',
      err: '$err',
    );
  }

  Future<void> seed() async {
    final s = await fixture.open();
    await fixture.seed(s, [
      f.sample(1, time: f.instant.subtract(const Duration(microseconds: 1))),
      f.sample(2, time: f.instant, operation: DiagnosticOperation.ping),
      f.sample(3, time: f.instant),
      f.sample(
        4,
        time: f.instant.add(const Duration(microseconds: 1)),
        state: DiagnosticRecordState.recoveredArchived,
      ),
    ]);
    await s.close();
  }

  test('history list defaults, filter intersection, microsecond cursor and deleted cursor continuation', () async {
    await seed();
    final all = await call(['history', 'list', '--json']);
    expect(all.code, 0);
    expect(all.data!['items'], hasLength(4));
    expect(all.data!['nextCursor'], null);
    final first = await call(['history', 'list', '--limit=2', '--json']);
    expect(first.data!['items'].map((r) => r['runId']), [
      f.fixtureId(4).value,
      f.fixtureId(3).value,
    ]);
    final c = first.data!['nextCursor'];
    expect(c['preparedAt'], '2026-11-11T12:03:04.567891Z');
    expect(c['runId'], f.fixtureId(3).value);
    expect(
      (await call(['history', 'delete', '--id=${c['runId']}', '--json'])).code,
      0,
    );
    final next = await call([
      'history',
      'list',
      '--limit=2',
      '--after-prepared-at=${c['preparedAt']}',
      '--after-run-id=${c['runId']}',
      '--json',
    ]);
    expect(next.data!['items'].map((r) => r['runId']), [
      f.fixtureId(2).value,
      f.fixtureId(1).value,
    ]);
    expect(next.data!['nextCursor'], null);
    final filtered = await call([
      'history',
      'list',
      '--operation=ping',
      '--state=settled',
      '--from=2026-11-11T12:03:04.567891Z',
      '--until=2026-11-11T12:03:04.567892Z',
      '--json',
    ]);
    expect(filtered.data!['items'].map((r) => r['runId']), [
      f.fixtureId(2).value,
    ]);
    final exclusive = await call([
      'history',
      'list',
      '--until=2026-11-11T12:03:04.567891Z',
      '--json',
    ]);
    expect(exclusive.data!['items'], hasLength(1));
  });

  test('show preserves independent recovery, logical and cleanup facts; delete is guarded and missing is not_found', () async {
    final s = await fixture.open();
    await fixture.seed(s, [
      f.sample(1, state: DiagnosticRecordState.prepared),
      f.sample(2, state: DiagnosticRecordState.recoveredArchived),
    ]);
    final protected = await call([
      'history',
      'delete',
      '--id=${f.fixtureId(1).value}',
      '--json',
    ], storage: s);
    expect(protected.code, 69);
    expect(protected.data!['failure']['code'], 'conflict');
    final recovered = await call([
      'history',
      'show',
      '--id=${f.fixtureId(1).value}',
      '--json',
    ]);
    expect(recovered.data!['run']['recordState'], 'recovered_archived');
    expect(recovered.data!['run']['result'], null);
    expect(recovered.data!['run']['logicalEndedAt'], null);
    expect(recovered.data!['run']['recoveryReason'], 'interrupted');
    expect(recovered.data!['run']['cleanup']['core']['state'], 'succeeded');
    expect(
      (await call([
        'history',
        'delete',
        '--id=${f.fixtureId(1).value}',
        '--json',
      ])).code,
      0,
    );
    expect(
      (await call([
        'history',
        'delete',
        '--id=${f.fixtureId(1).value}',
        '--json',
      ])).data!['failure']['code'],
      'not_found',
    );
  });

  test('export writes raw core envelope, preserves bounded precision/nulls and independent reliable metadata', () async {
    await seed();
    final first = await call(['history', 'export', '--limit=2', '--json']);
    expect(first.code, 0);
    expect(first.data!.keys.toSet(), {
      'diagnosticSummaryFormatVersion',
      'exportedAt',
      'runs',
    });
    expect(first.data!['runs'], hasLength(2));
    expect(first.out, isNot(contains('profileId')));
    expect(first.out, isNot(contains('schemaVersion')));
    final metadata = jsonDecode(first.err);
    expect(metadata['event'], 'metadata');
    expect(metadata['nextCursor']['preparedAt'], '2026-11-11T12:03:04.567891Z');
    expect(metadata['storageClose']['state'], 'closed');
    final c = metadata['nextCursor'];
    final second = await call([
      'history',
      'export',
      '--limit=2',
      '--after-prepared-at=${c['preparedAt']}',
      '--after-run-id=${c['runId']}',
    ]);
    expect(second.data!['runs'], hasLength(2));
    expect(jsonDecode(second.err)['nextCursor'], null);
    final sink = ControlledSink()..flushFails = true;
    final failed = await call(['history', 'export'], output: sink);
    expect(failed.code, 74);
    expect(const LineSplitter().convert(sink.buffer.toString()), hasLength(1));
    expect(jsonDecode(sink.buffer.toString())['runs'], hasLength(4));
  });

  test('query failure emits no invented export and unknown exceptions still close before propagation', () async {
    final control = f.HistoryControl();
    final s = AuditedStorage(await fixture.open(control: control));
    control.readFailure = const CoreException(CoreErrorCode.storageReadFailed);
    final bad = await call(['history', 'export'], storage: s);
    expect(bad.code, 74);
    expect(bad.out, isEmpty);
    expect(
      jsonDecode(
        const LineSplitter().convert(bad.err).first,
      )['operationSucceeded'],
      false,
    );
    expect(s.closes, 1);
    final control2 = f.HistoryControl();
    final inner = await fixture.open(control: control2);
    final wrapper = AuditedStorage(inner);
    // Unexpected output implementations are contained by CliOutput and release
    // the owner; application bugs continue to the existing process boundary.
    final sink = ControlledSink()..writeFails = true;
    expect(
      (await call(
        ['history', 'list', '--json'],
        storage: wrapper,
        output: sink,
      )).code,
      74,
    );
    expect(wrapper.closes, 1);
  });

  test(
    'startup maintenance failure stays sticky after successful explicit prune',
    () async {
      final control = f.HistoryControl();
      final s = await fixture.open(control: control);
      await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
      await s.history.waitForMaintenance();
      await fixture.seed(s, [f.sample(1), f.sample(2)]);
      await s.close();
      control.failDelete = control.deletes + 1;
      final reopened = AuditedStorage(await fixture.open(control: control));
      expect(
        reopened.history.latestMaintenance!.state,
        HistoryMaintenanceState.failed,
      );
      final r = await call(['history', 'prune', '--json'], storage: reopened);
      expect(r.code, 74);
      expect(r.data!['operationSucceeded'], true);
      expect(r.data!['prune']['state'], 'completed');
      expect(r.data!['maintenance']['latest']['state'], 'completed');
      expect(
        r.data!['maintenance']['unacknowledgedFailure']['state'],
        'failed',
      );
      expect(r.data!['maintenance']['unacknowledgedFailureCount'], 1);
      expect(reopened.events.where((e) => e == 'maintain'), hasLength(1));
    },
  );

  test('committed settings survive pruning failure and no ordinary command requests a retry', () async {
    final control = f.HistoryControl();
    final s = AuditedStorage(await fixture.open(control: control));
    await fixture.seed(s.inner as dynamic, [f.sample(1), f.sample(2)]);
    control.failDelete = control.deletes + 1;
    final r = await call([
      'settings',
      'set',
      '--clear-default-profile',
      '--history-limit=1',
      '--json',
    ], storage: s);
    expect(r.code, 74);
    expect(r.data!['operationSucceeded'], true);
    expect(r.data!['committed'], true);
    expect(r.data!['settings']['diagnosticHistoryLimit'], 1);
    expect(r.data!['maintenance']['latest']['state'], 'failed');
    expect(s.events.contains('maintain'), false);
    final reopened = await fixture.open();
    expect((await reopened.settings.read()).diagnosticHistoryLimit, 1);
    expect(await fixture.count(reopened), 1);
  });

  test(
    'explicit prune reports committed deletion count before failed batch',
    () async {
      final control = f.HistoryControl();
      final s = await fixture.open(control: control);
      await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
      await s.history.waitForMaintenance();
      await fixture.seed(s, [for (var i = 1; i <= 140; i++) f.sample(i)]);
      control.failDelete = control.deletes + 128;
      final r = await call(['history', 'prune', '--json'], storage: s);
      expect(r.code, 74);
      expect(r.data!['prune']['state'], 'failed');
      expect(r.data!['prune']['deletedCount'], 127);
      expect(r.data!['prune']['historyLimit'], 1);
      expect(r.data!['prune']['deferredCount'], 0);
    },
  );

  test('post-done unpin maintenance failure is observed through close and never causes another send', () async {
    final control = f.HistoryControl();
    final inner = await fixture.open(
      control: control,
      runId: () => f.fixtureId(1),
      clock: () => f.instant,
    );
    final s = AuditedStorage(inner);
    await s.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await s.history.waitForMaintenance();
    await fixture.seed(inner, [
      f.sample(2, time: f.instant.add(const Duration(days: 1))),
    ]);
    // The new run is older than the retained row. It stays pinned until done,
    // so deletion can fail only in the final unpin-triggered worker.
    control.failDelete = control.deletes + 1;
    final t = f.FakeCompanionTransport();
    t.sending = (bytes, _) async {
      scheduleMicrotask(() {
        if (bytes[0] == 0x16) t.receive(f.deviceInfo());
        if (bytes[0] == 0x01) t.receive(f.selfInfo());
        if (bytes[0] == 0x3e) t.receive([0]);
      });
    };
    final out = StringBuffer(), err = StringBuffer();
    final code = await runCli(
      ['--data-dir', fixture.directory.path, ...args('send'), '--record'],
      output: out,
      error: err,
      openStorage: (_) async => s,
      createTransport: (_) => t,
    );
    expect(code, 74);
    final data = jsonDecode('$out');
    expect(data['recording']['fullySuccessful'], true);
    expect(data['result']['reason'], 'completed');
    expect(data['maintenance']['unacknowledgedFailure']['state'], 'failed');
    expect(data['storageClose']['state'], 'closed');
    expect(t.sent.where((b) => b[0] == 0x3e), hasLength(1));
    expect(s.events.where((e) => e == 'close'), hasLength(1));
  });

  test('unrecorded success also waits for storage close and reports independent maintenance failure once', () async {
    final control = f.HistoryControl();
    final inner = await fixture.open(control: control);
    final s = AuditedStorage(inner);
    await inner.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await inner.history.waitForMaintenance();
    await fixture.seed(inner, [f.sample(1), f.sample(2)]);
    control.failDelete = control.deletes + 1;
    await inner.history.maintain();
    final t = f.FakeCompanionTransport();
    t.sending = (bytes, _) async {
      scheduleMicrotask(() {
        if (bytes[0] == 0x16) t.receive(f.deviceInfo());
        if (bytes[0] == 0x01) t.receive(f.selfInfo());
        if (bytes[0] == 0x3e) t.receive([0]);
      });
    };
    final out = StringBuffer(), err = StringBuffer();
    final code = await runCli(
      ['--data-dir', fixture.directory.path, ...args('send')],
      output: out,
      error: err,
      openStorage: (_) async => s,
      createTransport: (_) => t,
    );
    expect(code, 74);
    expect(const LineSplitter().convert('$out'), hasLength(1));
    final data = jsonDecode('$out');
    expect(data['result']['send']['deviceAcceptanceConfirmed'], true);
    expect(data['reason'], 'storage_finalization_failure');
    expect(data['failure'], null);
    expect(data['maintenance']['unacknowledgedFailureCount'], 1);
  });
  test('successful business output waits for actual native close and releases the same owner', () async {
    final barrier = CloseBarrier();
    final inner = await fixture.open(control: barrier);
    final s = AuditedStorage(inner);
    final out = StringBuffer();
    var ended = false;
    final pending = call(['draft', 'create', '--json'], storage: s, output: out)
        .then((r) {
          ended = true;
          return r;
        });
    await barrier.entered.future;
    expect(ended, false);
    expect('$out', isEmpty);
    expect(s.state, StorageState.closing);
    await expectLater(
      CoreStorage.open(dataDirectory: fixture.directory),
      throwsA(f.coreError(CoreErrorCode.dataDirectoryBusy)),
    );
    barrier.release.complete();
    expect((await pending).code, 0);
    expect(s.closes, 1);
    expect(s.state, StorageState.closed);
    expect((await fixture.open()).state, StorageState.open);
  });
  test('explicit prune reports deferred for a real recording pin and close waits for final unpin work', () async {
    final control = f.HistoryControl();
    final inner = await fixture.open(
      control: control,
      runId: () => f.fixtureId(1),
      clock: () => f.instant,
    );
    await inner.settings.save(AppSettings(diagnosticHistoryLimit: 1));
    await inner.history.waitForMaintenance();
    await fixture.seed(inner, [
      f.sample(2, time: f.instant.add(const Duration(days: 1))),
    ]);
    Future<({int code, Map<String, dynamic>? data, String out, String err})>?
    pruning;
    var armed = false;
    control.updated = (statement, values) {
      if (!armed &&
          statement.contains('stored_runs') &&
          values.any(
            (v) => v is String && v.contains('"aggregate":"succeeded"'),
          )) {
        armed = true;
        control.afterCommit = () {
          pruning = call(['history', 'prune', '--json'], storage: inner);
        };
      }
    };
    final t = f.FakeCompanionTransport();
    t.sending = (bytes, _) async {
      scheduleMicrotask(() {
        if (bytes[0] == 0x16) t.receive(f.deviceInfo());
        if (bytes[0] == 0x01) t.receive(f.selfInfo());
        if (bytes[0] == 0x3e) t.receive([0]);
      });
    };
    final op = inner.record(
      parameters: f.input(DiagnosticOperation.send),
      appVersion: 'test-host',
      createTransport: () => t,
    );
    await op.done;
    expect(pruning, isNotNull);
    final r = await pruning!;
    expect(r.code, 0, reason: r.out);
    expect(r.data!['prune']['state'], 'deferred');
    expect(r.data!['prune']['deferredCount'], 1);
    expect(r.data!['prune']['deletedCount'], 0);
    expect(r.data!['maintenance']['latest']['state'], 'completed');
    expect(r.data!['storageClose']['state'], 'closed');
  });
  test(
    'offline synchronous signal short circuits before storage admission',
    () async {
      var opens = 0, cancels = 0;
      final source = StreamController<CliStopRequest>(
        onCancel: () {
          cancels++;
        },
      );
      final out = StringBuffer();
      expect(
        await runCli(
          ['--data-dir', fixture.directory.path, 'draft', 'list', '--json'],
          output: out,
          error: StringBuffer(),
          openStorage: (_) async {
            opens++;
            throw StateError('Must not open.');
          },
          stopRequests: ImmediateSignal(source.stream),
        ),
        130,
      );
      expect(opens, 0);
      expect(cancels, 1);
      expect(jsonDecode('$out')['operationSucceeded'], false);
      expect(jsonDecode('$out')['reason'], 'sigint');
      await source.close();
    },
  );

  for (final outputFailure in [false, true]) {
    test(
      'offline admitted commit and close settle after ${outputFailure ? 'output failure' : 'SIGTERM'}',
      () async {
        final control = f.HistoryControl();
        final inner = await fixture.open(control: control);
        final s = AuditedStorage(inner);
        final entered = Completer<void>(), release = Completer<void>();
        control.beforeCommit = () async {
          entered.complete();
          await release.future;
        };
        final source = StreamController<CliStopRequest>(sync: true);
        final sink = ControlledSink();
        var ended = false;
        final pending =
            runCli(
              [
                '--data-dir',
                fixture.directory.path,
                'draft',
                'create',
                '--body=committed',
                '--json',
              ],
              output: sink,
              error: StringBuffer(),
              openStorage: (_) async => s,
              stopRequests: source.stream,
            ).then((code) {
              ended = true;
              return code;
            });
        await entered.future;
        if (outputFailure) {
          sink.completion.completeError(StateError('SECRET_OUTPUT'));
        } else {
          source.add(CliStopRequest.sigterm);
        }
        await f.turns();
        expect(ended, false);
        release.complete();
        expect(await pending, outputFailure ? 74 : 143);
        expect(s.closes, 1);
        expect(s.state, StorageState.closed);
        if (!outputFailure) {
          final data = jsonDecode(sink.buffer.toString());
          expect(data['committed'], true);
          expect(data['operationSucceeded'], true);
          expect(data['reason'], 'sigterm');
          expect(data['hostCleanup'], 'succeeded');
        }
        final reopened = await fixture.open();
        expect((await reopened.drafts.list()).items.single.body, 'committed');
        await source.close();
      },
    );
  }

  test('offline host subscription cancellation failure is independent of committed data', () async {
    final s = AuditedStorage(await fixture.open());
    final source = StreamController<CliStopRequest>(
      onCancel: () async => throw StateError('SECRET_CANCEL'),
    );
    final out = StringBuffer(), err = StringBuffer();
    expect(
      await runCli(
        ['--data-dir', fixture.directory.path, 'draft', 'create', '--json'],
        output: out,
        error: err,
        openStorage: (_) async => s,
        stopRequests: source.stream,
      ),
      69,
    );
    final data = jsonDecode('$out');
    expect(data['committed'], true);
    expect(data['operationSucceeded'], true);
    expect(data['hostCleanup'], 'failed');
    expect(data['additionalFailures'].single['source'], 'signalSubscription');
    expect('$out$err', isNot(contains('SECRET_CANCEL')));
    expect(s.closes, 1);
    await source.close();
  });
  for (final earlierSignal in [false, true]) {
    test(
      'offline maintenance failure precedes signal cleanup failure${earlierSignal ? ' while retaining earlier SIGTERM' : ''}',
      () async {
        final control = f.HistoryControl();
        final inner = await fixture.open(control: control);
        final s = AuditedStorage(inner);
        await fixture.seed(inner, [f.sample(1), f.sample(2)]);
        control.failDelete = control.deletes + 1;
        final entered = Completer<void>(), release = Completer<void>();
        control.beforeCommit = () async {
          entered.complete();
          await release.future;
        };
        var cancels = 0;
        StorageState? stateAtCancel;
        HistoryMaintenanceState? maintenanceAtCancel;
        final source = StreamController<CliStopRequest>(
          sync: true,
          onCancel: () async {
            cancels++;
            stateAtCancel = s.state;
            maintenanceAtCancel = s.history.unacknowledgedFailure?.state;
            throw StateError('SECRET_SIGNAL_CANCEL');
          },
        );
        final out = StringBuffer(), err = StringBuffer();
        final pending = runCli(
          [
            '--data-dir',
            fixture.directory.path,
            'settings',
            'set',
            '--clear-default-profile',
            '--history-limit=1',
            '--json',
          ],
          output: out,
          error: err,
          openStorage: (_) async => s,
          stopRequests: source.stream,
          createTransport: (_) => throw StateError('Offline hardware.'),
        );
        await entered.future;
        if (earlierSignal) source.add(CliStopRequest.sigterm);
        release.complete();
        expect(await pending, earlierSignal ? 143 : 74);
        final data = jsonDecode('$out');
        expect(
          data['reason'],
          earlierSignal ? 'sigterm' : 'storage_finalization_failure',
        );
        expect(data['exitCode'], earlierSignal ? 143 : 74);
        expect(data['operationSucceeded'], true);
        expect(data['committed'], true);
        expect(data['settings']['diagnosticHistoryLimit'], 1);
        expect(data['maintenance']['unacknowledgedFailure']['state'], 'failed');
        expect(data['storageClose']['state'], 'closed');
        expect(data['hostCleanup'], 'failed');
        expect(
          data['additionalFailures'],
          contains(
            equals({
              'domain': 'host',
              'source': 'signalSubscription',
              'code': 'cleanup_failure',
            }),
          ),
        );
        expect(
          data['additionalFailures'],
          contains(
            equals({
              'domain': 'storage',
              'source': 'maintenance',
              'code': 'storage_write_failed',
              'cleanupUnconfirmed': false,
            }),
          ),
        );
        expect(cancels, 1);
        expect(stateAtCancel, StorageState.closed);
        expect(maintenanceAtCancel, HistoryMaintenanceState.failed);
        expect(s.closes, 1);
        expect(s.events.where((event) => event == 'maintain'), isEmpty);
        expect(const LineSplitter().convert('$out'), hasLength(1));
        expect('$out$err', isNot(contains('SECRET_')));
        final reopened = await fixture.open();
        expect((await reopened.settings.read()).diagnosticHistoryLimit, 1);
        await source.close();
      },
    );
  }
  test('all process signal cancellations start even when one stays pending and another fails', () async {
    final release = Completer<void>();
    var first = 0, second = 0;
    final a = StreamController<ProcessSignal>(
      onCancel: () {
        first++;
        return release.future;
      },
    );
    final b = StreamController<ProcessSignal>(
      onCancel: () {
        second++;
        return Future<void>.error(StateError('SECRET_CANCEL'));
      },
    );
    final subscription = processStopRequests(
      windows: false,
      watch: (signal) => signal == ProcessSignal.sigint ? a.stream : b.stream,
    ).listen((_) {});
    var settled = false;
    final completion = expectLater(subscription.cancel(), throwsStateError)
        .then((_) {
          settled = true;
        });
    await f.turns();
    expect(first, 1);
    expect(second, 1);
    expect(settled, false);
    release.complete();
    await completion;
    await a.close();
    await b.close();
  });
}

class CloseBarrier extends f.HistoryControl {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> close(inner) async {
    entered.complete();
    await release.future;
    await inner.close();
  }
}
