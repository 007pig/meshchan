import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshctl/meshctl.dart';
import 'package:meshctl/src/business_storage.dart';
import 'package:test/test.dart';

import '../../../packages/meshchan_core/test/history/support.dart' as fixture;
import 'meshctl_test.dart' show FakeSerialPorts;
import 'session_cli_test.dart' show ControlledSink;

const id1 = '00000000000000000000000000000001';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meshctl-business-');
  });
  tearDown(() {
    directory.deleteSync(recursive: true);
  });
  Future<({int code, Map<String, dynamic>? data, String out, String err})> call(
    List<String> args, {
    Future<CoreStorage> Function(Directory)? opener,
    StringSink? sink,
  }) async {
    final out = StringBuffer(), err = StringBuffer();
    final ports = FakeSerialPorts();
    final code = await runCli(
      ['--data-dir', directory.path, ...args],
      output: sink ?? out,
      error: err,
      serialPorts: ports,
      openStorage: opener,
      createTransport: (_) =>
          throw StateError('Offline command constructed hardware.'),
    );
    expect(ports.listCalls, 0);
    expect(ports.checkedPaths, isEmpty);
    return (
      code: code,
      data: out.isEmpty
          ? null
          : jsonDecode(out.toString()) as Map<String, dynamic>,
      out: out.toString(),
      err: err.toString(),
    );
  }

  test(
    'platform directory policy uses absolute bases and exact explicit paths',
    () {
      expect(
        dataDirectoryPath(
          operatingSystem: 'macos',
          environment: {'HOME': '/Users/example'},
        ),
        '/Users/example/Library/Application Support/meshchan',
      );
      expect(
        dataDirectoryPath(
          operatingSystem: 'linux',
          environment: {'HOME': '/home/example', 'XDG_DATA_HOME': '/data base'},
        ),
        '/data base/meshchan',
      );
      for (final xdg in ['', 'relative', '  ', '/bad\u0000base']) {
        expect(
          dataDirectoryPath(
            operatingSystem: 'linux',
            environment: {'HOME': '/home/example', 'XDG_DATA_HOME': xdg},
          ),
          '/home/example/.local/share/meshchan',
        );
      }
      expect(
        dataDirectoryPath(
          operatingSystem: 'windows',
          environment: {'LOCALAPPDATA': r'C:\Users\example\AppData\Local'},
        ),
        r'C:\Users\example\AppData\Local\meshchan',
      );
      expect(
        dataDirectoryPath(
          operatingSystem: 'windows',
          environment: {'LOCALAPPDATA': r'\\server\share'},
        ),
        r'\\server\share\meshchan',
      );
      for (final os in ['macos', 'linux', 'windows', 'unknown']) {
        for (final env in [
          <String, String>{},
          {'HOME': 'relative', 'LOCALAPPDATA': r'C:relative'},
        ]) {
          expect(
            () => dataDirectoryPath(operatingSystem: os, environment: env),
            throwsFormatException,
          );
        }
        expect(
          dataDirectoryPath(
            explicit: ' relative path ',
            operatingSystem: os,
            environment: {},
          ),
          ' relative path ',
        );
      }
      for (final path in ['', ' \t ', 'x\u0000y']) {
        expect(() => dataDirectoryPath(explicit: path), throwsFormatException);
      }
      final before = dataDirectoryPath(
        operatingSystem: 'linux',
        environment: {'HOME': '/home/example'},
      );
      final original = Directory.current;
      try {
        Directory.current = directory;
        expect(
          dataDirectoryPath(
            operatingSystem: 'linux',
            environment: {'HOME': '/home/example'},
          ),
          before,
        );
      } finally {
        Directory.current = original;
      }
    },
  );

  test('help, syntax, lexical errors and old commands do not open storage or construct devices', () async {
    var opens = 0, devices = 0;
    final ports = FakeSerialPorts();
    final target = Directory('${directory.path}/must not exist');
    final cases = <(List<String>, int)>[
      (['--help'], 0),
      (['--version'], 0),
      for (final group in ['draft', 'profile', 'settings', 'history']) ...[
        ([group], 0),
        ([group, '--help'], 0),
        ([group, 'show', '--help'], 0),
        (['--version', group, 'show'], 0),
        ([group, 'show', '--help', 'SECRET_POSITION'], 64),
        ([group, 'show', '--SECRET_OPTION=SECRET_VALUE'], 64),
      ],
      (['draft', 'create', '--help', '--body-file=/missing/SECRET_FILE'], 0),
      (['draft', 'create', '--body=x', '--body-file=x'], 64),
      (['draft', 'show', '--id=0'], 64),
      (['draft', 'update', '--id=$id1', '--expected-revision=1'], 64),
      (['draft', 'delete', '--id=$id1', '--expected-revision=0x1'], 64),
      (['draft', 'list', '--after-id=$id1'], 64),
      (
        [
          'profile',
          'create',
          '--name=x',
          '--operation=listen',
          '--port=SECRET_PORT',
        ],
        64,
      ),
      (['settings', 'set'], 64),
      (
        [
          'settings',
          'set',
          '--clear-default-profile',
          '--default-profile-id=$id1',
        ],
        64,
      ),
      (['settings', 'set', '--history-limit=100001'], 64),
      for (final command in ['ports', 'port-check', 'info', 'watch'])
        ([command], 64),
      (['info', '--help'], 0),
      (['ports', '--help'], 0),
      for (final operation in ['send', 'listen', 'ping', 'respond']) ...[
        (['datagram', operation, '--help'], 0),
        (['datagram', operation], 64),
        (['datagram', operation, '--port=SECRET_PORT', '--timeout=0x1'], 64),
      ],
      (['datagram', 'send', '--port=x', '--text=x', '--payload-hex='], 64),
      (
        ['datagram', 'listen', '--port=x', '--data-type=0', '--all-data-types'],
        64,
      ),
      (['history', 'list', '--from=2026-02-30T00:00:00Z'], 64),
      (['history', 'list', '--from=2026-01-01T00:00:00.1234567Z'], 64),
      (['history', 'list', '--from=2026-01-01T00:00:00+00:00'], 64),
      (
        [
          'history',
          'list',
          '--from=2026-01-02T00:00:00Z',
          '--until=2026-01-01T00:00:00Z',
        ],
        64,
      ),
    ];
    for (final (args, expected) in cases) {
      final out = StringBuffer(), err = StringBuffer();
      final code = await runCli(
        ['--data-dir', target.path, ...args],
        output: out,
        error: err,
        serialPorts: ports,
        openStorage: (_) {
          opens++;
          throw StateError('Storage must not open.');
        },
        createTransport: (_) {
          devices++;
          throw StateError('Device must not construct.');
        },
      );
      expect(code, expected, reason: '$args');
      if (expected == 64) expect(out.toString(), isEmpty);
      expect('$err', isNot(contains('SECRET_')));
    }
    expect(opens, 0);
    expect(devices, 0);
    expect(ports.listCalls, 0);
    expect(ports.checkedPaths, isEmpty);
    expect(target.existsSync(), false);
    // Without the inapplicable data-dir, legacy paths also bypass the opener.
    await runCli(
      ['ports', '--json'],
      output: StringBuffer(),
      error: StringBuffer(),
      serialPorts: ports,
      openStorage: (_) {
        opens++;
        throw StateError('Unexpected open.');
      },
    );
    expect(ports.listCalls, 1);
    expect(opens, 0);
  });

  test('all offline leaf help short circuits before values, files and data directory policy', () async {
    final leaves = {
      'draft': ['create', 'show', 'update', 'delete', 'list'],
      'profile': ['create', 'show', 'update', 'delete', 'list'],
      'settings': ['show', 'set', 'reset'],
      'history': ['list', 'show', 'delete', 'export', 'prune'],
    };
    for (final entry in leaves.entries) {
      for (final leaf in entry.value) {
        expect(
          await runCli(
            ['--data-dir=', entry.key, leaf, '--help'],
            output: StringBuffer(),
            error: StringBuffer(),
            selectDataDirectory: (_) => throw StateError('Policy ran.'),
            openStorage: (_) => throw StateError('Storage opened.'),
          ),
          0,
        );
      }
    }
  });

  final missingRequired = <(List<String>, String)>[
    (['draft', 'show'], 'id'),
    (
      ['draft', 'update', '--expected-revision=1', '--title=SECRET_TITLE'],
      'id',
    ),
    (['draft', 'delete', '--expected-revision=1'], 'id'),
    (['profile', 'show'], 'id'),
    (
      [
        'profile',
        'update',
        '--name=SECRET_NAME',
        '--operation=listen',
        '--receive-channel=2',
        '--duration=1',
        '--task-timeout=5',
      ],
      'id',
    ),
    (['profile', 'delete'], 'id'),
    (['history', 'show'], 'id'),
    (['history', 'delete'], 'id'),
    (
      ['draft', 'update', '--id=$id1', '--title=SECRET_TITLE'],
      'expected-revision',
    ),
    (['draft', 'delete', '--id=$id1'], 'expected-revision'),
    (['draft', 'update', '--title=SECRET_TITLE'], 'id'),
    (['draft', 'delete'], 'id'),
    (
      [
        'draft',
        'update',
        '--expected-revision=1',
        '--body-file=/missing/SECRET_BODY_FILE',
      ],
      'id',
    ),
    (
      ['draft', 'update', '--id=$id1', '--body-file=/missing/SECRET_BODY_FILE'],
      'expected-revision',
    ),
  ];
  for (final (arguments, requiredOption) in missingRequired) {
    for (final json in [false, true]) {
      test(
        'missing --$requiredOption in ${arguments.join(' ')} (${json ? 'JSON' : 'text'}) is rejected before admission',
        () async {
          final target = Directory('${directory.path}/must not exist');
          final out = StringBuffer(), err = StringBuffer();
          final ports = FakeSerialPorts();
          var policies = 0, opens = 0, devices = 0, subscriptions = 0;
          final source = StreamController<CliStopRequest>.broadcast(
            onListen: () => subscriptions++,
          );
          addTearDown(source.close);
          final code = await runCli(
            ['--data-dir', target.path, ...arguments, if (json) '--json'],
            output: out,
            error: err,
            serialPorts: ports,
            selectDataDirectory: (_) {
              policies++;
              return target.path;
            },
            openStorage: (_) async {
              opens++;
              throw StateError('Storage must not open.');
            },
            createTransport: (_) {
              devices++;
              throw StateError('Device must not start.');
            },
            stopRequests: source.stream,
          );
          expect(code, 64);
          expect('$out', isEmpty);
          expect('$err', contains('--$requiredOption'));
          expect('$err', isNot(contains('SECRET_')));
          expect(policies, 0);
          expect(opens, 0);
          expect(devices, 0);
          expect(subscriptions, 0);
          expect(ports.listCalls, 0);
          expect(ports.checkedPaths, isEmpty);
          expect(target.existsSync(), false);
        },
      );
    }
  }

  test('missing required options still allow normal help and version short circuits', () async {
    for (final (arguments, _) in missingRequired) {
      for (final shortCircuit in ['--help', '--version']) {
        final out = StringBuffer();
        expect(
          await runCli(
            [
              if (shortCircuit == '--version') '--version',
              ...arguments,
              if (shortCircuit == '--help') '--help',
              '--json',
            ],
            output: out,
            error: StringBuffer(),
            selectDataDirectory: (_) =>
                throw StateError('Policy must not run.'),
            openStorage: (_) => throw StateError('Storage must not open.'),
            createTransport: (_) => throw StateError('Device must not start.'),
          ),
          0,
        );
        expect(
          '$out',
          contains(shortCircuit == '--help' ? 'Usage:' : 'meshctl '),
        );
        expect('$out', isNot(contains('SECRET_')));
      }
    }
  });

  test('draft exact UTF-8 file content persists across reopen, revision merge, no-op, stale and delete', () async {
    final body = ' 中文😀\r\nline\rnext\n${'large ' * 100}\t\n';
    final file = File('${directory.path}/body with spaces.txt')
      ..writeAsBytesSync([0xef, 0xbb, 0xbf, ...utf8.encode(body)]);
    final created = await call([
      'draft',
      'create',
      '--title= title\u001b ',
      '--body-file',
      file.path,
      '--json',
    ]);
    expect(created.code, 0);
    expect(created.data!['committed'], true);
    final draft = created.data!['draft'] as Map;
    final id = draft['id'] as String;
    expect(draft['body'], body);
    expect(draft['bodyUtf8ByteLength'], utf8.encode(body).length);
    expect(draft['revision'], 1);
    final read = await call(['draft', 'show', '--id=$id', '--json']);
    expect(read.data!['draft'], draft);
    final changed = await call([
      'draft',
      'update',
      '--id=$id',
      '--expected-revision=1',
      '--title=renamed',
      '--json',
    ]);
    expect(changed.data!['draft']['body'], body);
    expect(changed.data!['draft']['revision'], 2);
    final noop = await call([
      'draft',
      'update',
      '--id=$id',
      '--expected-revision=2',
      '--title=renamed',
      '--json',
    ]);
    expect(noop.data!['draft'], changed.data!['draft']);
    final stale = await call([
      'draft',
      'update',
      '--id=$id',
      '--expected-revision=1',
      '--body=',
      '--json',
    ]);
    expect(stale.code, 69);
    expect(stale.data!['failure']['code'], 'conflict');
    final empty = await call([
      'draft',
      'update',
      '--id=$id',
      '--expected-revision=2',
      '--body=',
      '--json',
    ]);
    expect(empty.data!['draft']['body'], '');
    expect(empty.data!['draft']['revision'], 3);
    expect(
      (await call([
        'draft',
        'delete',
        '--id=$id',
        '--expected-revision=2',
        '--json',
      ])).code,
      69,
    );
    expect(
      (await call([
        'draft',
        'delete',
        '--id=$id',
        '--expected-revision=3',
        '--json',
      ])).data!['deleted'],
      true,
    );
    expect((await call(['draft', 'show', '--id=$id', '--json'])).code, 64);
    final blank = await call(['draft', 'create', '--json']);
    expect(blank.data!['draft']['title'], '');
    expect(blank.data!['draft']['body'], '');
  });

  test('body-file invalid UTF-8 is 64, actual file I/O is 74, and text display escapes controls', () async {
    final file = File('${directory.path}/invalid')
      ..writeAsBytesSync([0xc3, 0x28]);
    var opens = 0;
    Future<CoreStorage> forbidden(Directory _) {
      opens++;
      throw StateError('Unexpected open.');
    }

    expect(
      (await call([
        'draft',
        'create',
        '--body-file',
        file.path,
      ], opener: forbidden)).code,
      64,
    );
    expect(
      (await call([
        'draft',
        'create',
        '--body-file',
        '${directory.path}/SECRET_MISSING',
      ], opener: forbidden)).code,
      74,
    );
    final missingJson = await call([
      'draft',
      'create',
      '--body-file',
      '${directory.path}/SECRET_MISSING',
      '--json',
    ], opener: forbidden);
    expect(missingJson.code, 74);
    expect(missingJson.data!['reason'], 'host_io_failure');
    expect(missingJson.data!['failure'], {
      'domain': 'host',
      'source': 'body_file',
      'code': 'io_failure',
    });
    expect(
      '${missingJson.out}${missingJson.err}',
      isNot(contains('SECRET_MISSING')),
    );
    expect(opens, 0);
    final out = StringBuffer();
    expect(
      await runCli(
        [
          '--data-dir',
          directory.path,
          'draft',
          'create',
          '--body=\u001b[31m\r\n中文',
        ],
        output: out,
        error: StringBuffer(),
      ),
      0,
    );
    expect('$out', isNot(contains('\u001b')));
    expect('$out', contains('中文'));
    final s = await CoreStorage.open(dataDirectory: directory);
    try {
      expect((await s.drafts.list()).items.single.body, '\u001b[31m\r\n中文');
    } finally {
      await s.close();
    }
  });

  test('draft and profile pagination emit reusable six-digit UTC cursors without large bodies', () async {
    for (var n = 0; n < 3; n++) {
      await call([
        'draft',
        'create',
        '--title=$n',
        '--body=${'x' * 500}',
        '--json',
      ]);
    }
    final first = (await call(['draft', 'list', '--limit=1', '--json'])).data!;
    expect(first['items'], hasLength(1));
    expect(first['items'][0].containsKey('body'), false);
    final c = first['nextCursor'];
    expect(c['updatedAt'], matches(r'\.\d{6}Z$'));
    final next = (await call([
      'draft',
      'list',
      '--limit=2',
      '--after-updated-at=${c['updatedAt']}',
      '--after-id=${c['id']}',
      '--json',
    ])).data!;
    expect(next['items'], hasLength(2));
    expect(next['nextCursor'], null);
    expect(
      (await call([
        'draft',
        'list',
        '--after-updated-at=2026-01-01T00:00:00Z',
        '--after-id=$id1',
        '--json',
      ])).code,
      0,
    );
    for (var n = 0; n < 3; n++) {
      await call([
        'profile',
        'create',
        '--name=same',
        '--operation=listen',
        '--task-timeout=5',
        '--receive-channel=$n',
        '--duration=1',
        '--json',
      ]);
    }
    final p = (await call(['profile', 'list', '--limit=1', '--json'])).data!;
    expect(p['items'], hasLength(1));
    expect(p['items'][0].containsKey('parameters'), false);
    final pc = p['nextCursor'];
    final pn = (await call([
      'profile',
      'list',
      '--limit=2',
      '--after-updated-at=${pc['updatedAt']}',
      '--after-id=${pc['id']}',
      '--json',
    ])).data!;
    expect(pn['items'], hasLength(2));
    expect(pn['nextCursor'], null);
  });

  test('four complete profile types and replacement clear incompatible fields and port hint', () async {
    for (final operation in ['send', 'listen', 'ping', 'respond']) {
      final result = await call([
        'profile',
        'create',
        '--name= same ',
        '--operation=$operation',
        '--port-hint= hint ',
        '--task-timeout=10',
        if (operation != 'listen') ...[
          '--send-channel=0x03',
          '--route-descriptor=0',
        ],
        if (operation != 'send') '--receive-channel=2',
        if (operation == 'send') '--data-type=7',
        if (operation == 'ping' || operation == 'respond') ...[
          '--local-id=1',
          '--peer-id=2',
        ],
        if (operation == 'ping') '--response-timeout=1',
        if (operation == 'listen' || operation == 'respond') '--duration=1',
        '--json',
      ]);
      expect(result.code, 0, reason: result.err);
      final id = result.data!['profile']['id'];
      final read = (await call(['profile', 'show', '--id=$id', '--json']))
          .data!['profile'];
      expect(read, result.data!['profile']);
      expect(read['name'], ' same ');
      expect(read['portHint'], ' hint ');
      final replacement = await call([
        'profile',
        'update',
        '--id=$id',
        '--name=listen',
        '--operation=listen',
        '--task-timeout=3',
        '--receive-channel=0',
        '--duration=1',
        '--json',
      ]);
      expect(replacement.code, 0);
      expect(replacement.data!['profile']['portHint'], null);
      expect(replacement.data!['profile']['parameters']['dataType'], null);
      expect(
        replacement.data!['profile']['parameters'].containsKey('route'),
        false,
      );
    }
  });

  test('profile validation shares core NUL name compatibility and rejects unrelated or incomplete fields', () async {
    final base = [
      'profile',
      'create',
      '--operation=listen',
      '--task-timeout=5',
      '--receive-channel=0',
      '--duration=1',
      '--json',
    ];
    for (final name in ['a\u0000b', '\t\u0000b']) {
      final r = await call([...base, '--name=$name']);
      expect(r.code, 0, reason: r.err);
      expect(r.data!['profile']['name'], name);
    }
    for (final name in ['', '  ', '\u0000x', '  \u0000x']) {
      expect((await call([...base, '--name=$name'])).code, 64);
    }
    for (final option in [
      '--send-channel=0',
      '--route-descriptor=0',
      '--path-hex=',
      '--response-timeout=1',
      '--local-id=1',
      '--max-responses=1',
      '--text=SECRET',
      '--record',
      '--port=SECRET',
    ]) {
      expect(
        (await call([...base, '--name=x', option])).code,
        64,
        reason: option,
      );
    }
    expect(
      (await call([
        'profile',
        'create',
        '--name=x',
        '--operation=send',
        '--json',
      ])).code,
      64,
    );
  });

  test('settings partial merge, complete replace, reset and atomic default-profile deletion', () async {
    final p = (await call([
      'profile',
      'create',
      '--name=default',
      '--operation=listen',
      '--task-timeout=2',
      '--receive-channel=0',
      '--duration=1',
      '--json',
    ])).data!['profile'];
    final id = p['id'];
    expect((await call(['settings', 'show', '--json'])).data!['settings'], {
      'defaultProfileId': null,
      'diagnosticHistoryLimit': 1000,
    });
    expect(
      (await call([
        'settings',
        'set',
        '--default-profile-id=$id',
        '--history-limit=8',
        '--json',
      ])).data!['committed'],
      true,
    );
    final changed = await call([
      'settings',
      'set',
      '--history-limit=2',
      '--json',
    ]);
    expect(changed.data!['settings'], {
      'defaultProfileId': id,
      'diagnosticHistoryLimit': 2,
    });
    expect(
      (await call(['settings', 'set', '--default-profile-id=$id1', '--json']))
          .code,
      64,
    );
    await call(['profile', 'delete', '--id=$id', '--json']);
    expect(
      (await call(['settings', 'show', '--json']))
          .data!['settings']['defaultProfileId'],
      null,
    );
    await call(['settings', 'reset', '--json']);
    expect(
      (await call(['settings', 'show', '--json']))
          .data!['settings']['diagnosticHistoryLimit'],
      1000,
    );
  });

  test('complete settings replace and reset bypass dangling old default; partial change reports it', () async {
    final f = fixture.Fixture();
    addTearDown(f.close);
    final s = await f.open();
    await s.useDatabase((db) async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement(
        "INSERT INTO stored_settings VALUES (1, '$id1', 1000)",
      );
      await db.customStatement('PRAGMA foreign_keys = ON');
    });
    Future<CoreStorage> opener(Directory _) async => s;
    final partial = await call([
      'settings',
      'set',
      '--history-limit=4',
      '--json',
    ], opener: opener);
    expect(partial.code, 64);
    final full = await runCli(
      [
        '--data-dir',
        f.directory.path,
        'settings',
        'set',
        '--clear-default-profile',
        '--history-limit=4',
        '--json',
      ],
      output: StringBuffer(),
      error: StringBuffer(),
    );
    expect(full, 0);
    final reopened = await f.open();
    await reopened.useDatabase((db) async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement(
        "UPDATE stored_settings SET default_profile_id = '$id1'",
      );
      await db.customStatement('PRAGMA foreign_keys = ON');
    });
    await reopened.close();
    expect(
      await runCli(
        ['--data-dir', f.directory.path, 'settings', 'reset', '--json'],
        output: StringBuffer(),
        error: StringBuffer(),
      ),
      0,
    );
  });

  test(
    'every core error maps with source/code and acquired storage closes',
    () async {
      for (final error in CoreErrorCode.values) {
        final r = await call([
          'draft',
          'list',
          '--json',
        ], opener: (_) async => throw CoreException(error));
        expect(r.code, switch (error) {
          CoreErrorCode.invalidInput || CoreErrorCode.notFound => 64,
          CoreErrorCode.conflict || CoreErrorCode.dataDirectoryBusy => 69,
          _ => 74,
        });
        expect(r.data!['failure']['code'], error.code);
        expect(r.data!['failure']['source'], 'open');
      }
      final sink = ControlledSink()..flushFails = true;
      expect(
        (await call([
          'draft',
          'create',
          '--body=committed',
          '--json',
        ], sink: sink)).code,
        74,
      );
      expect(
        const LineSplitter().convert(sink.buffer.toString()),
        hasLength(1),
      );
      final s = await CoreStorage.open(dataDirectory: directory);
      try {
        expect((await s.drafts.list()).items.single.body, 'committed');
      } finally {
        await s.close();
      }
    },
  );

  test('same directory is busy, explicit relative path works, and closed storage reopens', () async {
    final owner = await CoreStorage.open(dataDirectory: directory);
    try {
      final r = await call(['draft', 'list', '--json']);
      expect(r.code, 69);
      expect(r.data!['failure']['code'], 'data_directory_busy');
    } finally {
      await owner.close();
    }
    final original = Directory.current;
    try {
      Directory.current = directory;
      expect(
        await runCli(
          ['--data-dir=relative space', 'draft', 'create', '--json'],
          output: StringBuffer(),
          error: StringBuffer(),
        ),
        0,
      );
      expect(File('relative space/meshchan.sqlite').existsSync(), true);
    } finally {
      Directory.current = original;
    }
    expect((await call(['history', 'export'])).code, 0);
  });
  for (final action in ['partial', 'complete', 'reset']) {
    test(
      'damaged old settings are read only for a partial change: $action',
      () async {
        final f = fixture.Fixture();
        addTearDown(f.close);
        final s = await f.open();
        await s.useDatabase((db) async {
          await db.customStatement('PRAGMA ignore_check_constraints=ON');
          await db.customStatement(
            'INSERT INTO stored_settings VALUES (1, NULL, 0)',
          );
          await db.customStatement('PRAGMA ignore_check_constraints=OFF');
        });
        await s.close();
        final out = StringBuffer(), err = StringBuffer();
        final code = await runCli(
          [
            '--data-dir',
            f.directory.path,
            'settings',
            if (action == 'reset') 'reset' else 'set',
            if (action != 'reset') '--history-limit=4',
            if (action == 'complete') '--clear-default-profile',
            '--json',
          ],
          output: out,
          error: err,
        );
        final data = jsonDecode('$out');
        expect(code, 74);
        expect(data['committed'], action != 'partial');
        expect(data['operationSucceeded'], action != 'partial');
        expect(
          data['maintenance']['unacknowledgedFailure']['error']['code'],
          'database_corrupt',
        );
        if (action != 'partial') {
          final read = await f.open();
          expect(
            (await read.settings.read()).diagnosticHistoryLimit,
            action == 'reset' ? 1000 : 4,
          );
        }
      },
    );
  }
}
