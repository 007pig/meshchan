import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/storage.dart'
    show openStorage, StorageHooks;
import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart';

import '../../../packages/meshchan_core/test/history/support.dart' as f;
import 'datagram_cli_test.dart' show args;
import 'datagram_storage_signals_test.dart' show StorageGates;
import 'session_cli_test.dart' show ControlledSink;
import 'support/audited_storage.dart';

void main() {
  late f.Fixture fixture;
  setUp(() {
    fixture = f.Fixture();
  });
  tearDown(() => fixture.close());

  void stop(
    String reason,
    StreamController<CliStopRequest> source,
    ControlledSink error,
  ) {
    if (reason == 'output_failure') {
      error.completion.completeError(StateError('SECRET_OUTPUT'));
    } else {
      source.add(
        reason == 'sigint' ? CliStopRequest.sigint : CliStopRequest.sigterm,
      );
    }
  }

  int codeFor(String reason) => switch (reason) {
    'sigint' => 130,
    'sigterm' => 143,
    _ => 74,
  };

  for (final record in [false, true]) {
    for (final phase in ['open', 'resolution']) {
      for (final reason in ['sigint', 'sigterm', 'output_failure']) {
        test(
          '${record ? 'recorded' : 'unrecorded'} $reason precedes later $phase failure',
          () async {
            final entered = Completer<void>(), release = Completer<void>();
            StorageGates? storage;
            Future<CoreStorage> open(Directory directory) async {
              if (phase == 'open') {
                return openStorage(
                  directory,
                  hooks: StorageHooks(
                    afterCreate: () async {
                      entered.complete();
                      await release.future;
                      throw const CoreException(
                        CoreErrorCode.storageOpenFailed,
                      );
                    },
                  ),
                );
              }
              return storage!;
            }

            if (phase == 'resolution') {
              storage = StorageGates(await fixture.open(), 'resolve');
            }
            final out = StringBuffer(), error = ControlledSink();
            var factories = 0, cancellations = 0;
            final source = StreamController<CliStopRequest>.broadcast(
              sync: true,
              onCancel: () {
                cancellations++;
              },
            );
            final arguments = [
              for (final argument in args('send'))
                if (phase != 'resolution' ||
                    !argument.startsWith('--data-type='))
                  argument,
            ];
            final pending = runCli(
              [
                '--data-dir',
                fixture.directory.path,
                ...arguments,
                if (record) '--record',
              ],
              output: out,
              error: error,
              openStorage: open,
              createTransport: (_) {
                factories++;
                throw StateError('Device must not start.');
              },
              stopRequests: source.stream,
            );
            await (phase == 'open' ? entered.future : storage!.entered.future);
            stop(reason, source, error);
            await f.turns();
            if (phase == 'open') {
              release.complete();
            } else {
              storage!.release.complete();
            }
            expect(await pending, codeFor(reason));
            final data = jsonDecode(out.toString());
            expect(data['reason'], reason);
            expect(data['failure'], null);
            final failure = (data['additionalFailures'] as List).single;
            expect(failure['source'], phase);
            expect(
              failure['code'],
              phase == 'open' ? 'storage_open_failed' : 'invalid_input',
            );
            expect(data['result'], null);
            expect(factories, 0);
            expect(cancellations, 1);
            if (storage != null) {
              expect(storage.closes, 1);
              expect(storage.state, StorageState.closed);
            }
            final reopened = await fixture.open();
            expect(await fixture.count(reopened), 0);
            expect('$out${error.buffer}', isNot(contains('SECRET_')));
            expect(const LineSplitter().convert(out.toString()), hasLength(1));
            await source.close();
          },
        );
      }
    }
    test(
      '${record ? 'recorded' : 'unrecorded'} observed resolution failure precedes later signal',
      () async {
        final storage = StorageGates(await fixture.open(), 'close');
        final source = StreamController<CliStopRequest>.broadcast(sync: true);
        final out = StringBuffer();
        final pending = runCli(
          [
            '--data-dir',
            fixture.directory.path,
            ...args('send').where((a) => !a.startsWith('--data-type=')),
            if (record) '--record',
          ],
          output: out,
          error: StringBuffer(),
          openStorage: (_) async => storage,
          createTransport: (_) => throw StateError('Unexpected device.'),
          stopRequests: source.stream,
        );
        await storage.entered.future;
        source.add(CliStopRequest.sigterm);
        storage.release.complete();
        expect(await pending, 64);
        final data = jsonDecode(out.toString());
        expect(data['reason'], 'business_failure');
        expect(data['failure']['code'], 'invalid_input');
        expect(data['additionalFailures'], isEmpty);
        expect(storage.closes, 1);
        await source.close();
      },
    );
  }

  for (final reason in ['sigint', 'sigterm', 'output_failure']) {
    test('$reason precedes later real registration rollback', () async {
      final control = f.HistoryControl();
      final storage = AuditedStorage(await fixture.open(control: control));
      final entered = Completer<void>(), release = Completer<void>();
      storage.onRecord = (_) {
        control.beforeCommit = () async {
          entered.complete();
          await release.future;
          throw StateError('SECRET_REGISTRATION');
        };
      };
      final out = StringBuffer(), error = ControlledSink();
      final source = StreamController<CliStopRequest>.broadcast(sync: true);
      final pending = runCli(
        ['--data-dir', fixture.directory.path, ...args('send'), '--record'],
        output: out,
        error: error,
        openStorage: (_) async => storage,
        createTransport: (_) => throw StateError('Device must not start.'),
        stopRequests: source.stream,
      );
      await entered.future;
      stop(reason, source, error);
      await f.turns();
      release.complete();
      expect(await pending, codeFor(reason));
      final data = jsonDecode(out.toString());
      expect(data['reason'], reason);
      expect(data['recording']['registration']['state'], 'failed');
      expect(
        data['recording']['registration']['error']['code'],
        'storage_write_failed',
      );
      expect(data['recording']['logical']['state'], 'notAttempted');
      expect(data['recording']['cleanup']['state'], 'notAttempted');
      expect(data['result'], null);
      expect(
        (data['additionalFailures'] as List).single['source'],
        'recording_registration',
      );
      expect(storage.transportFactories, 0);
      expect(storage.planFactories, 0);
      expect(storage.closes, 1);
      final reopened = await fixture.open();
      expect(await fixture.count(reopened), 0);
      expect('$out${error.buffer}', isNot(contains('SECRET_')));
      await source.close();
    });
  }
  test(
    'observed registration failure precedes later signal during close',
    () async {
      final control = f.HistoryControl();
      final gates = StorageGates(await fixture.open(control: control), 'close');
      final storage = AuditedStorage(gates);
      storage.onRecord = (_) {
        control.beforeCommit = () async =>
            throw StateError('SECRET_REGISTRATION');
      };
      final source = StreamController<CliStopRequest>.broadcast(sync: true);
      final out = StringBuffer();
      final pending = runCli(
        ['--data-dir', fixture.directory.path, ...args('send'), '--record'],
        output: out,
        error: StringBuffer(),
        openStorage: (_) async => storage,
        createTransport: (_) => throw StateError('Unexpected device.'),
        stopRequests: source.stream,
      );
      await gates.entered.future;
      source.add(CliStopRequest.sigterm);
      gates.release.complete();
      expect(await pending, 74);
      final data = jsonDecode(out.toString());
      expect(data['reason'], 'recording_save_failure');
      expect(data['failure']['code'], 'storage_write_failed');
      expect(storage.transportFactories, 0);
      expect(storage.closes, 1);
      await source.close();
    },
  );
}
