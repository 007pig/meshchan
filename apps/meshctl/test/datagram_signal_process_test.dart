import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

void main() {
  for (final record in [false, true]) {
    for (final phase in ['open', 'close']) {
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
        test(
          '${record ? 'recorded' : 'unrecorded'} actual $signal during $phase awaits storage release',
          () async {
            final directory = Directory.systemTemp.createTempSync(
              'meshctl-signal-process-',
            );
            final process = await Process.start(Platform.resolvedExecutable, [
              'run',
              'test/support/datagram_signal_process.dart',
              directory.path,
              phase,
              record ? 'record' : 'unrecorded',
            ]);
            final output = process.stdout.transform(utf8.decoder).join();
            final errors = StreamIterator(
              process.stderr
                  .transform(utf8.decoder)
                  .transform(const LineSplitter()),
            );
            final captured = <String>[];
            Future<void> untilLine(String expected) async {
              while (await errors.moveNext().timeout(
                const Duration(seconds: 45),
              )) {
                final line = errors.current.replaceAll(
                  'Running build hooks...',
                  '',
                );
                captured.add(line);
                if (line == expected) return;
              }
              fail('Child exited before $expected: ${captured.join('\n')}');
            }

            try {
              await untilLine('TEST_READY');
              expect(process.kill(signal), true);
              await untilLine(
                'TEST_SIGNAL:${signal == ProcessSignal.sigint ? 'sigint' : 'sigterm'}',
              );
              // The still-gated owner has handled the signal without exiting.
              await expectLater(
                CoreStorage.open(dataDirectory: directory),
                throwsA(
                  isA<CoreException>().having(
                    (e) => e.code,
                    'code',
                    CoreErrorCode.dataDirectoryBusy,
                  ),
                ),
              );
              process.stdin.writeln('release');
              expect(
                await process.exitCode.timeout(const Duration(seconds: 45)),
                signal == ProcessSignal.sigint ? 130 : 143,
              );
              final lines = const LineSplitter().convert(await output);
              expect(lines, hasLength(1));
              final data = jsonDecode(lines.single);
              if (record || phase == 'open') {
                expect(data['storageClose']['state'], 'closed');
                expect(data['signalCleanup']['state'], 'succeeded');
              } else {
                expect(data['cleanup']['state'], 'succeeded');
              }
              if (phase == 'open') expect(data['result'], null);
              if (record && phase == 'close') {
                expect(data['recording']['fullySuccessful'], true);
              }
              while (await errors.moveNext()) {
                captured.add(errors.current);
              }
              expect(
                captured.join('\n'),
                isNot(contains('Unhandled exception')),
              );
              final reopened = await CoreStorage.open(dataDirectory: directory);
              await reopened.close();
            } finally {
              process.kill(ProcessSignal.sigkill);
              await process.exitCode;
              await output;
              await errors.cancel();
              await process.stdin.close();
              directory.deleteSync(recursive: true);
            }
          },
        );
      }
    }
  }
}
