import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/platform_probe.dart';
import 'package:meshchan_app/probe_request.dart';
import 'package:meshchan_core/meshchan_core.dart';

void main() {
  late Directory parent;
  late String fixture;
  setUp(() {
    parent = Directory.systemTemp.createTempSync('meshchan-probe-test-');
    fixture = '${parent.resolveSymbolicLinksSync()}/meshchan-1d2-fake';
  });
  tearDown(() => parent.deleteSync(recursive: true));

  test(
    'unsafe existing or missing read fixture never opens storage or enumerates',
    () async {
      var opens = 0;
      var enumerations = 0;
      for (final mode in ['read', 'write']) {
        if (mode == 'write') {
          Directory(fixture).createSync();
        }
        final result = await executeFixtureProbe(
          ProbeRequest(mode, fixture, enumerate: true),
          openStorage: (_) async {
            opens++;
            throw StateError('Unexpected open');
          },
          enumeratePorts: () {
            enumerations++;
            return 0;
          },
        );
        expect(result['passed'], false);
      }
      expect(opens, 0);
      expect(enumerations, 0);
    },
  );

  test(
    'final close failure preserves the read success but fails the whole probe',
    () async {
      var opens = 0;
      final stores = <_Storage>[];
      final report = await executeFixtureProbe(
        ProbeRequest('write', fixture),
        openStorage: (_) async {
          opens++;
          File('$fixture/meshchan.sqlite')
              .writeAsStringSync('Fake file for the injected boundary');
          final store = _Storage(failClose: opens == 2);
          stores.add(store);
          return store;
        },
      );
      expect(opens, 2);
      expect(report['draft'], isNotNull);
      expect(report['passed'], false);
      expect(report['closes'], ['closed', 'closeUnconfirmed']);
      expect(stores.every((store) => store.closeCalled), true);
      expect(
        File('$fixture/meshchan-1d2-receipt.json').readAsStringSync(),
        contains('incomplete'),
      );
    },
  );

  test('first close failure prevents reopen and serial work', () async {
    var opens = 0;
    final report = await executeFixtureProbe(
      ProbeRequest('write', fixture, enumerate: true),
      openStorage: (_) async {
        opens++;
        return _Storage(failClose: true);
      },
      enumeratePorts: () => throw StateError('Unexpected enumeration'),
    );
    expect(opens, 1);
    expect(report['passed'], false);
    expect(report['serialEnumeration'], 'NOT_RUN');
  });

  test('read close failure invalidates the receipt before another process can reopen', () async {
    Directory(fixture).createSync();
    File('$fixture/meshchan.sqlite').writeAsStringSync('Fake database');
    final receipt = File('$fixture/meshchan-1d2-receipt.json');
    receipt.writeAsStringSync(
      jsonEncode({
        'probe': 'meshchan.macos.1d2',
        'state': 'closed',
        'fixture': fixture,
        'draft': {
          'id': _draft.id.value,
          'revision': 1,
          'bodyUtf8Bytes': probeContent.bodyUtf8ByteLength,
          'createdAt': _draft.createdAt.toIso8601String(),
          'updatedAt': _draft.updatedAt.toIso8601String(),
        },
      }),
    );
    var opens = 0;
    for (var attempt = 0; attempt < 2; attempt++) {
      final report = await executeFixtureProbe(
        ProbeRequest('read', fixture),
        openStorage: (_) async {
          opens++;
          return _Storage(failClose: true);
        },
      );
      expect(report['passed'], false);
    }
    expect(opens, 1);
    expect(receipt.readAsStringSync(), contains('incomplete'));
  });

  test('maintenance and create failures still await real close', () async {
    for (final failure in ['maintenance', 'create']) {
      final path = '$fixture-$failure';
      final storage = _Storage(
        failMaintenance: failure == 'maintenance',
        failCreate: failure == 'create',
      );
      final report = await executeFixtureProbe(
        ProbeRequest('write', path),
        openStorage: (_) async => storage,
      );
      expect(report['passed'], false);
      expect(storage.closeCalled, true);
      expect(report['closes'], ['closed']);
      expect(report['failures'], isNotEmpty);
    }
  });
}

final _draft = Draft(
  id: LocalId('0123456789abcdef0123456789abcdef'),
  content: probeContent,
  createdAt: DateTime.utc(2026, 11, 12),
);

class _Storage implements CoreStorage {
  _Storage({
    this.failClose = false,
    bool failMaintenance = false,
    bool failCreate = false,
  }) : history = _History(failMaintenance),
       drafts = _Drafts(failCreate);
  final bool failClose;
  bool closeCalled = false;
  @override
  StorageState state = StorageState.open;
  @override
  final DiagnosticHistory history;
  @override
  final DraftRepository drafts;
  @override
  Future<void> close() async {
    await Future<void>.delayed(Duration.zero);
    closeCalled = true;
    state = failClose ? StorageState.closeUnconfirmed : StorageState.closed;
    if (failClose) {
      throw const CoreException(
        CoreErrorCode.storageWriteFailed,
        cleanupUnconfirmed: true,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _History implements DiagnosticHistory {
  _History(this.fail);
  final bool fail;
  @override
  Future<HistoryMaintenanceReport> waitForMaintenance() async =>
      HistoryMaintenanceReport(
        state: fail
            ? HistoryMaintenanceState.failed
            : HistoryMaintenanceState.completed,
        deletedCount: 0,
        historyLimit: 1000,
      );
  @override
  HistoryMaintenanceReport? get unacknowledgedFailure => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Drafts implements DraftRepository {
  _Drafts(this.fail);
  final bool fail;
  @override
  Future<Draft> create(DraftContent content) async {
    if (fail) throw const CoreException(CoreErrorCode.storageWriteFailed);
    return _draft;
  }

  @override
  Future<Draft> read(LocalId id) async => _draft;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
