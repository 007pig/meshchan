// Controlled source-process fixture; never a product entry point.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshctl/meshctl.dart';

import '../../../../packages/meshchan_core/test/history/support.dart' as f;

class RefuseClose extends f.HistoryControl {
  @override
  Future<void> close(inner) async => throw StateError('SECRET_NATIVE_CLOSE');
}

Future<void> main(List<String> arguments) async {
  final directory = Directory(arguments[1]);
  final fixture = f.Fixture(dataDirectory: directory);
  if (arguments[0] == 'owner') {
    final s = await fixture.open();
    stdout.writeln('ready');
    await stdout.flush();
    await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
    await s.close();
    stdout.writeln('closed');
    return;
  }
  if (const {
    'close-failure',
    'close-signal-failure',
    'export-close-failure',
    'export-close-signal-failure',
  }.contains(arguments[0])) {
    final export = arguments[0].startsWith('export-');
    CoreStorage? storage;
    final signals = arguments[0].contains('close-signal-failure')
        ? StreamController<CliStopRequest>(
            onCancel: () async {
              if (storage?.state != StorageState.closeUnconfirmed) {
                throw StateError('Signal cleanup preceded native close.');
              }
              stderr.writeln('TEST_SIGNAL_CANCEL:closeUnconfirmed');
              throw StateError('SECRET_SIGNAL_CANCEL');
            },
          )
        : null;
    exitCode = await runCli(
      [
        '--data-dir',
        directory.path,
        if (!export) ...[
          'draft',
          'create',
          '--body=committed',
        ] else ...[
          'history',
          'export',
        ],
        '--json',
      ],
      output: stdout,
      error: stderr,
      openStorage: (_) async =>
          storage = await fixture.open(control: RefuseClose()),
      stopRequests: signals?.stream,
    );
    await signals?.close();
    try {
      await CoreStorage.open(dataDirectory: directory);
      stderr.writeln('TEST_LOCK:unexpected_open');
    } on CoreException catch (e) {
      stderr.writeln('TEST_LOCK:${e.code.code}');
    }
  }
}
