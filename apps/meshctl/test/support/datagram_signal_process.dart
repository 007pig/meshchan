// Controlled child process for actual OS-signal/storage ownership tests.
import 'dart:io';

import 'package:meshctl/meshctl.dart';
import 'package:meshctl/src/process_io.dart';

import '../../../../packages/meshchan_core/test/history/support.dart' as f;
import '../datagram_cli_test.dart' show args;
import '../datagram_storage_signals_test.dart'
    show StorageGates, successfulSend;

Future<void> main(List<String> arguments) async {
  final fixture = f.Fixture(dataDirectory: Directory(arguments[0]));
  final storage = StorageGates(await fixture.open(), arguments[1]);
  final gate = storage.entered.future.then((_) async {
    stderr.writeln('TEST_READY');
    await stderr.flush();
    await stdin.first;
    storage.release.complete();
  });
  exitCode = await runCli(
    [
      '--data-dir',
      fixture.directory.path,
      ...args('send'),
      if (arguments[2] == 'record') '--record',
    ],
    output: stdout,
    error: stderr,
    openStorage: (_) => storage.open(),
    createTransport: (_) => successfulSend(),
    stopRequests: processStopRequests().map((request) {
      // Acknowledge actual OS delivery before the parent releases storage.
      stderr.writeln('TEST_SIGNAL:${request.name}');
      return request;
    }),
  );
  await gate;
}
