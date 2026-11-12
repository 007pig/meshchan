import 'dart:async';
import 'dart:convert';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart' show CompanionTransport;
import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart';

import '../../../packages/meshchan_core/test/history/support.dart' as f;
import 'datagram_cli_test.dart' show args;
import 'session_cli_test.dart' show ControlledSink;

/// Gates host Futures around real SQLite; no repository or recording is faked.
final class StorageGates implements CoreStorage {
  StorageGates(this.inner, this.phase);
  final CoreStorage inner;
  final String phase;
  final entered = Completer<void>();
  final release = Completer<void>();
  int resolves = 0, recordings = 0, closes = 0;
  Future<void> gate(String at) async {
    if (phase != at) return;
    entered.complete();
    await release.future;
  }

  Future<CoreStorage> open() async {
    await gate('open');
    return this;
  }

  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest request,
  ) async {
    resolves++;
    await gate('resolve');
    return inner.resolveParameters(request);
  }

  @override
  Future<void> close() async {
    closes++;
    await gate('close');
    await inner.close();
  }

  @override
  StorageState get state => inner.state;
  @override
  DraftRepository get drafts => inner.drafts;
  @override
  ProfileRepository get profiles => inner.profiles;
  @override
  SettingsRepository get settings => inner.settings;
  @override
  DiagnosticHistory get history => inner.history;
  @override
  RecordedOperation record({
    required EffectiveParameters parameters,
    required String appVersion,
    required CompanionTransport Function() createTransport,
    List<RecordingSubscription> subscriptions = const [],
  }) {
    recordings++;
    return inner.record(
      parameters: parameters,
      appVersion: appVersion,
      createTransport: createTransport,
      subscriptions: subscriptions,
    );
  }
}

f.FakeCompanionTransport successfulSend() {
  final t = f.FakeCompanionTransport();
  t.sending = (bytes, _) async {
    scheduleMicrotask(() {
      if (bytes[0] == 0x16) t.receive(f.deviceInfo());
      if (bytes[0] == 0x01) t.receive(f.selfInfo());
      if (bytes[0] == 0x3e) t.receive([0]);
    });
  };
  return t;
}

void main() {
  late f.Fixture fixture;
  setUp(() {
    fixture = f.Fixture();
  });
  tearDown(() => fixture.close());
  for (final record in [false, true]) {
    for (final signal in CliStopRequest.values) {
      for (final phase in ['open', 'resolve', 'close']) {
        test(
          '${record ? 'recorded' : 'unrecorded'} $signal during $phase retains ownership and cancellation',
          () async {
            final storage = StorageGates(await fixture.open(), phase);
            final t = successfulSend();
            var subscriptions = 0, cancellations = 0, factories = 0;
            StorageState? stateAtCancel;
            final stops = StreamController<CliStopRequest>.broadcast(
              sync: true,
              onListen: () {
                subscriptions++;
              },
              onCancel: () {
                cancellations++;
                stateAtCancel = storage.state;
              },
            );
            final out = StringBuffer(), err = StringBuffer();
            var ended = false;
            final pending =
                runCli(
                  [
                    '--data-dir',
                    fixture.directory.path,
                    ...args('send'),
                    if (record) '--record',
                  ],
                  output: out,
                  error: err,
                  openStorage: (_) => storage.open(),
                  createTransport: (_) {
                    factories++;
                    return t;
                  },
                  stopRequests: stops.stream,
                ).then((code) {
                  ended = true;
                  return code;
                });
            try {
              await storage.entered.future;
              stops.add(signal);
              await f.turns();
              expect(ended, false);
              expect(out.toString(), isEmpty);
            } finally {
              storage.release.complete();
            }
            final code = await pending;
            await stops.close();
            expect(
              code,
              signal == CliStopRequest.sigint ? 130 : 143,
              reason: '$out$err',
            );
            expect(subscriptions, 1);
            expect(cancellations, 1);
            expect(stateAtCancel, StorageState.closed);
            expect(storage.closes, 1);
            final data = jsonDecode(out.toString()) as Map;
            expect(data['reason'], signal.name);
            expect(data['exitCode'], code);
            expect(const LineSplitter().convert(out.toString()), hasLength(1));
            if (phase == 'close') {
              expect(factories, 1);
              expect(t.sent.where((b) => b[0] == 0x3e), hasLength(1));
              expect(data['result'], isNotNull);
              if (record) expect(data['recording']['fullySuccessful'], true);
            } else {
              expect(factories, 0);
              expect(t.sent, isEmpty);
              expect(storage.recordings, 0);
              expect(data['result'], null);
              if (phase == 'open') expect(storage.resolves, 0);
            }
            final reopened = await fixture.open();
            expect(
              await fixture.count(reopened),
              record && phase == 'close' ? 1 : 0,
            );
          },
        );
      }
    }
  }
  for (final record in [false, true]) {
    for (final phase in ['open', 'resolve', 'close']) {
      test(
        '${record ? 'recorded' : 'unrecorded'} source error during $phase closes before propagation',
        () async {
          final storage = StorageGates(await fixture.open(), phase);
          final t = successfulSend();
          final stops = StreamController<CliStopRequest>.broadcast(sync: true);
          final out = StringBuffer(), err = StringBuffer();
          var factories = 0;
          final pending = runCli(
            [
              '--data-dir',
              fixture.directory.path,
              ...args('send'),
              if (record) '--record',
            ],
            output: out,
            error: err,
            openStorage: (_) => storage.open(),
            createTransport: (_) {
              factories++;
              return t;
            },
            stopRequests: stops.stream,
          );
          final observed = expectLater(pending, throwsStateError);
          await storage.entered.future;
          stops.addError(StateError('SECRET_SIGNAL_SOURCE'));
          await f.turns();
          expect(out.toString(), isEmpty);
          storage.release.complete();
          await observed;
          expect(storage.closes, 1);
          expect(storage.state, StorageState.closed);
          expect(factories, phase == 'close' ? 1 : 0);
          expect('$out$err', isNot(contains('SECRET_SIGNAL_SOURCE')));
          await stops.close();
        },
      );
    }
    test(
      '${record ? 'recorded' : 'unrecorded'} awaits real source cancellation after database close',
      () async {
        final storage = StorageGates(await fixture.open(), 'none');
        final t = successfulSend();
        final entered = Completer<void>(), release = Completer<void>();
        final stops = StreamController<CliStopRequest>(
          onCancel: () {
            expect(storage.state, StorageState.closed);
            entered.complete();
            return release.future;
          },
        );
        final out = StringBuffer(), err = StringBuffer();
        var ended = false;
        final pending =
            runCli(
              [
                '--data-dir',
                fixture.directory.path,
                ...args('send'),
                if (record) '--record',
              ],
              output: out,
              error: err,
              openStorage: (_) => storage.open(),
              createTransport: (_) => t,
              stopRequests: stops.stream,
            ).then((code) {
              ended = true;
              return code;
            });
        await entered.future;
        await f.turns();
        expect(ended, false);
        expect(out.toString(), isEmpty);
        release.completeError(StateError('SECRET_SIGNAL_CANCEL'));
        expect(await pending, 69);
        final data = jsonDecode(out.toString());
        expect(data['signalCleanup']['state'], 'failed');
        if (record) {
          expect(data['recording']['fullySuccessful'], true);
          expect(data['cleanup']['hostSubscriptions']['state'], 'succeeded');
        }
        expect('$out$err', isNot(contains('SECRET_SIGNAL_CANCEL')));
        expect(storage.closes, 1);
        expect(t.sent.where((b) => b[0] == 0x3e), hasLength(1));
        await stops.close();
      },
    );
    test(
      '${record ? 'recorded' : 'unrecorded'} frozen device failure beats a signal during storage close',
      () async {
        final storage = StorageGates(await fixture.open(), 'close');
        final t = f.FakeCompanionTransport();
        t.sending = (_, _) async {
          scheduleMicrotask(() => t.receiveError(StateError('SECRET_NATIVE')));
        };
        final stops = StreamController<CliStopRequest>.broadcast(sync: true);
        final out = StringBuffer(), err = StringBuffer();
        final pending = runCli(
          [
            '--data-dir',
            fixture.directory.path,
            ...args('send'),
            if (record) '--record',
          ],
          output: out,
          error: err,
          openStorage: (_) => storage.open(),
          createTransport: (_) => t,
          stopRequests: stops.stream,
        );
        await storage.entered.future;
        stops.add(CliStopRequest.sigterm);
        storage.release.complete();
        expect(await pending, 69);
        final data = jsonDecode(out.toString());
        expect(data['reason'], 'task_failure');
        expect(data['result'], isNotNull);
        expect('$out$err', isNot(contains('SECRET_NATIVE')));
        await stops.close();
      },
    );
    for (final signalFirst in [false, true]) {
      test(
        '${record ? 'recorded' : 'unrecorded'} close preserves ${signalFirst ? 'signal' : 'output failure'} first',
        () async {
          final storage = StorageGates(await fixture.open(), 'close');
          final stops = StreamController<CliStopRequest>.broadcast(sync: true);
          final out = StringBuffer(), err = ControlledSink();
          final pending = runCli(
            [
              '--data-dir',
              fixture.directory.path,
              ...args('send'),
              if (record) '--record',
            ],
            output: out,
            error: err,
            openStorage: (_) => storage.open(),
            createTransport: (_) => successfulSend(),
            stopRequests: stops.stream,
          );
          await storage.entered.future;
          if (signalFirst) stops.add(CliStopRequest.sigint);
          err.completion.completeError(StateError('SECRET_OUTPUT'));
          await f.turns();
          if (!signalFirst) stops.add(CliStopRequest.sigint);
          storage.release.complete();
          expect(await pending, signalFirst ? 130 : 74);
          final data = jsonDecode(out.toString());
          expect(data['reason'], signalFirst ? 'sigint' : 'output_failure');
          expect(data['result'], isNotNull);
          await stops.close();
        },
      );
    }
  }
}
