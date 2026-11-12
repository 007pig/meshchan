import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/storage.dart'
    show openStorage, StorageHooks;
import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart';

import '../../../packages/meshchan_core/test/history/support.dart' as f;
import 'datagram_storage_signals_test.dart' show StorageGates;
import 'session_cli_test.dart' show ControlledSink;
import 'support/audited_storage.dart';

void main() {
  late f.Fixture fixture;
  setUp(() => fixture = f.Fixture());
  tearDown(() => fixture.close());

  void stop(
    String reason,
    StreamController<CliStopRequest> source,
    ControlledSink sink,
  ) {
    if (reason == 'output_failure') {
      sink.completion.completeError(StateError('SECRET_OUTPUT'));
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

  Map<String, dynamic> terminal(
    bool export,
    StringBuffer out,
    StringBuffer err,
  ) => jsonDecode(
    export
        ? const LineSplitter()
              .convert('$err')
              .singleWhere((line) => line.startsWith('{'))
        : '$out',
  ) as Map<String, dynamic>;

  for (final export in [false, true]) {
    final arguments = export
        ? ['history', 'export', '--json']
        : ['draft', 'create', '--body=SECRET_BODY', '--json'];
    for (final phase in ['open', 'operation']) {
      for (final reason in ['sigint', 'sigterm', 'output_failure']) {
        test(
          '${export ? 'export' : 'offline JSON'} $reason precedes later $phase error fields',
          () async {
            final entered = Completer<void>(), release = Completer<void>();
            final control = f.HistoryControl();
            AuditedStorage? storage;
            Future<void> fault() async {
              entered.complete();
              await release.future;
              if (export) {
                throw const CoreException(CoreErrorCode.storageReadFailed);
              }
              throw StateError('SECRET_TRANSACTION');
            }

            if (phase == 'operation') {
              storage = AuditedStorage(await fixture.open(control: control));
              if (export) {
                control.afterRead = fault;
              } else {
                control.beforeCommit = fault;
              }
            }
            Future<CoreStorage> open(Directory directory) async {
              if (phase == 'operation') return storage!;
              return openStorage(
                directory,
                hooks: StorageHooks(
                  afterCreate: () async {
                    entered.complete();
                    await release.future;
                    throw const CoreException(CoreErrorCode.storageOpenFailed);
                  },
                ),
              );
            }

            final out = StringBuffer(), err = StringBuffer();
            final sink = ControlledSink();
            var cancels = 0, devices = 0;
            StorageState? stateAtCancel;
            final source = StreamController<CliStopRequest>.broadcast(
              sync: true,
              onCancel: () {
                cancels++;
                stateAtCancel = storage?.state;
              },
            );
            addTearDown(source.close);
            final pending = runCli(
              ['--data-dir', fixture.directory.path, ...arguments],
              // Fail the channel that does not carry this command's final fields.
              output: export ? sink : out,
              error: export ? err : sink,
              openStorage: open,
              stopRequests: source.stream,
              createTransport: (_) {
                devices++;
                throw StateError('Offline hardware.');
              },
            );
            await entered.future;
            stop(reason, source, sink);
            await f.turns();
            release.complete();
            expect(await pending, codeFor(reason));
            final data = terminal(export, out, err);
            expect(data['reason'], reason);
            expect(data['exitCode'], codeFor(reason));
            expect(data['failure'], null);
            expect(data['operationSucceeded'], false);
            if (!export) expect(data['committed'], false);
            expect(data['additionalFailures'], [
              {
                'domain': 'storage',
                'source': phase,
                'code': phase == 'open'
                    ? 'storage_open_failed'
                    : export
                    ? 'storage_read_failed'
                    : 'storage_write_failed',
                'cleanupUnconfirmed': false,
              },
            ]);
            expect(data['hostCleanup'], 'succeeded');
            expect(cancels, 1);
            expect(devices, 0);
            if (storage != null) {
              expect(storage.closes, 1);
              expect(stateAtCancel, StorageState.closed);
              expect(data['storageClose']['state'], 'closed');
            } else {
              expect(data['storageClose'], null);
            }
            if (export) {
              expect('${sink.buffer}', isEmpty);
            } else {
              expect(const LineSplitter().convert('$out'), hasLength(1));
            }
            expect('$out$err${sink.buffer}', isNot(contains('SECRET_')));
            final reopened = await fixture.open();
            expect((await reopened.drafts.list()).items, isEmpty);
            expect(await fixture.count(reopened), 0);
          },
        );
      }
    }

    for (final reason in ['sigint', 'sigterm', 'output_failure']) {
      test(
        '${export ? 'export' : 'offline JSON'} earlier operation error fields survive later $reason',
        () async {
          final control = f.HistoryControl();
          final inner = await fixture.open(control: control);
          final storage = StorageGates(inner, 'close');
          if (export) {
            control.readFailure = const CoreException(
              CoreErrorCode.storageReadFailed,
            );
          } else {
            control.beforeCommit = () async =>
                throw StateError('SECRET_TRANSACTION');
          }
          final source = StreamController<CliStopRequest>.broadcast(sync: true);
          addTearDown(source.close);
          final out = StringBuffer(),
              err = StringBuffer(),
              sink = ControlledSink();
          final pending = runCli(
            ['--data-dir', fixture.directory.path, ...arguments],
            output: export ? sink : out,
            error: export ? err : sink,
            openStorage: (_) async => storage,
            stopRequests: source.stream,
            createTransport: (_) => throw StateError('Offline hardware.'),
          );
          await storage.entered.future;
          stop(reason, source, sink);
          await f.turns();
          storage.release.complete();
          expect(await pending, 74);
          final data = terminal(export, out, err);
          expect(data['reason'], 'business_failure');
          expect(data['exitCode'], 74);
          expect(data['failure'], {
            'domain': 'storage',
            'source': 'operation',
            'code': export ? 'storage_read_failed' : 'storage_write_failed',
            'cleanupUnconfirmed': false,
          });
          expect(data['additionalFailures'], isEmpty);
          expect(data['operationSucceeded'], false);
          if (!export) expect(data['committed'], false);
          expect(storage.closes, 1);
          expect(storage.state, StorageState.closed);
          expect('$out$err${sink.buffer}', isNot(contains('SECRET_')));
        },
      );
    }
  }
}
