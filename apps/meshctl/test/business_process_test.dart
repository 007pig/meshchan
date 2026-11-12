import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync('meshctl-process-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));
  Future<ProcessResult> cli(Directory target, List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/meshctl.dart', '--data-dir', target.path, ...args],
  ).timeout(const Duration(seconds: 45));

  test('product entry rejects missing IDs and revisions without creating a database', () async {
    final target = Directory('${directory.path}/must not exist');
    for (final arguments in <List<String>>[
      [
        'profile',
        'update',
        '--name=SECRET_NAME',
        '--operation=listen',
        '--receive-channel=2',
        '--duration=1',
        '--task-timeout=5',
      ],
      ['draft', 'show'],
      ['draft', 'delete', '--id=00000000000000000000000000000001'],
    ]) {
      final child = await cli(target, [...arguments, '--json']);
      expect(child.exitCode, 64);
      expect(child.stdout, isEmpty);
      expect(child.stderr, isNot(contains('SECRET_')));
      expect(child.stderr, isNot(contains('#0')));
      expect(target.existsSync(), false);
    }
  });

  test('another process owns same directory while independent directories work; normal close permits reopen', () async {
    final owner = await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/support/business_process.dart',
      'owner',
      directory.path,
    ]);
    final errors = owner.stderr.transform(utf8.decoder).join();
    final lines = StreamIterator(
      owner.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      expect(await lines.moveNext().timeout(const Duration(seconds: 45)), true);
      expect(lines.current, 'ready');
      final busy = await cli(directory, ['draft', 'list', '--json']);
      expect(busy.exitCode, 69);
      expect(
        jsonDecode(busy.stdout as String)['failure']['code'],
        'data_directory_busy',
      );
      final independent = Directory('${directory.path}/independent');
      expect(
        (await cli(independent, [
          'draft',
          'create',
          '--body=independent',
          '--json',
        ])).exitCode,
        0,
      );
      owner.stdin.writeln('close');
      expect(await lines.moveNext().timeout(const Duration(seconds: 45)), true);
      expect(lines.current, 'closed');
      expect(await owner.exitCode.timeout(const Duration(seconds: 45)), 0);
      final create = await cli(directory, [
        'draft',
        'create',
        '--body=persisted',
        '--json',
      ]);
      expect(create.exitCode, 0);
      final id = jsonDecode(create.stdout as String)['draft']['id'];
      final read = await cli(directory, [
        'draft',
        'show',
        '--id=$id',
        '--json',
      ]);
      expect(read.exitCode, 0);
      expect(jsonDecode(read.stdout as String)['draft']['body'], 'persisted');
      expect(
        (await errors).replaceAll('Running build hooks...', '').trim(),
        isEmpty,
      );
    } finally {
      owner.kill(ProcessSignal.sigkill);
      await owner.exitCode;
      await lines.cancel();
      await owner.stdin.close();
      await errors;
    }
  });

  for (final signalFailure in [false, true]) {
    test(
      'actual native close rejection ${signalFailure ? 'before signal cleanup failure ' : ''}is 74, preserves committed facts and quarantine until process exit',
      () async {
        final child = await Process.run(Platform.resolvedExecutable, [
          'run',
          'test/support/business_process.dart',
          signalFailure ? 'close-signal-failure' : 'close-failure',
          directory.path,
        ]).timeout(const Duration(seconds: 45));
        expect(child.exitCode, 74);
        final lines = const LineSplitter().convert(child.stdout as String);
        expect(lines, hasLength(1));
        final data = jsonDecode(lines.single);
        expect(data['operationSucceeded'], true);
        expect(data['committed'], true);
        expect(data['reason'], 'storage_finalization_failure');
        expect(data['exitCode'], 74);
        expect(data['storageClose']['state'], 'closeUnconfirmed');
        expect(data['storageClose']['error']['cleanupUnconfirmed'], true);
        expect(child.stderr, contains('TEST_LOCK:data_directory_busy'));
        expect(child.stderr, isNot(contains('SECRET_NATIVE_CLOSE')));
        if (signalFailure) {
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
          expect(child.stderr, contains('TEST_SIGNAL_CANCEL:closeUnconfirmed'));
          expect(child.stderr, isNot(contains('SECRET_SIGNAL_CANCEL')));
        }
        expect(child.stderr, isNot(contains('#0')));
        final reopened = await CoreStorage.open(dataDirectory: directory);
        try {
          expect((await reopened.drafts.list()).items.single.body, 'committed');
        } finally {
          await reopened.close();
        }
      },
    );
    test(
      'a generated export stays usable when actual native close is unconfirmed${signalFailure ? ' and signal cleanup fails' : ''}',
      () async {
        final child = await Process.run(Platform.resolvedExecutable, [
          'run',
          'test/support/business_process.dart',
          signalFailure
              ? 'export-close-signal-failure'
              : 'export-close-failure',
          directory.path,
        ]).timeout(const Duration(seconds: 45));
        expect(child.exitCode, 74);
        final data = jsonDecode(child.stdout as String);
        expect(data.keys.toSet(), {
          'diagnosticSummaryFormatVersion',
          'exportedAt',
          'runs',
        });
        expect(data['runs'], isEmpty);
        final metadata = const LineSplitter()
            .convert(
              (child.stderr as String).replaceAll('Running build hooks...', ''),
            )
            .where((line) => line.startsWith('{'))
            .map((line) => jsonDecode(line) as Map)
            .single;
        expect(metadata['operationSucceeded'], true);
        expect(metadata['storageClose']['state'], 'closeUnconfirmed');
        expect(metadata['exitCode'], 74);
        expect(metadata['reason'], 'storage_finalization_failure');
        if (signalFailure) {
          expect(metadata['hostCleanup'], 'failed');
          expect(
            metadata['additionalFailures'],
            contains(
              equals({
                'domain': 'host',
                'source': 'signalSubscription',
                'code': 'cleanup_failure',
              }),
            ),
          );
          expect(child.stderr, contains('TEST_SIGNAL_CANCEL:closeUnconfirmed'));
          expect(child.stderr, isNot(contains('SECRET_')));
        }
      },
    );
  }
}
