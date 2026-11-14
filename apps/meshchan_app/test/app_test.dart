import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/app.dart';
import 'package:meshchan_app/probe_request.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';

void main() {
  testWidgets(
    'normal launch starts one app runtime; navigation and rebuild keep its owner',
    (tester) async {
      var calls = 0;
      final runtime = _Runtime();
      await tester.pumpWidget(
        MeshchanApp(
          runtime: runtime,
          request: ProbeRequest.parse([
            '-NSDocumentRevisionsDebugMode',
            'YES',
            '-NSTreatUnknownArgumentsAsOpen',
            'NO',
            '-ApplePersistenceIgnoreState',
            'YES',
          ]),
          probe: (_) async {
            calls++;
            throw StateError('Normal navigation must not start native work.');
          },
        ),
      );
      expect(find.text('Select a draft or choose New'), findsOneWidget);
      await tester.tap(find.text('Device').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No ports have been listed or opened'),
        findsOneWidget,
      );
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No checks have been started'),
        findsOneWidget,
      );
      expect(find.textContaining('History is not connected'), findsOneWidget);
      await tester.tap(find.text('Drafts').first);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(runtime.starts, 1);
      expect(runtime.closes, 0);
      await tester.pumpWidget(
        MeshchanApp(runtime: runtime, probe: (_) async => {}),
      );
      expect(runtime.starts, 1);
      runtime.setPhase(RuntimePhase.ready);
      await tester.pump();
      expect(find.text('Storage ready'), findsOneWidget);
      for (final phase in [
        RuntimePhase.busy,
        RuntimePhase.fault,
        RuntimePhase.closing,
      ]) {
        runtime.setPhase(phase);
        await tester.pump();
        expect(
          find.textContaining(switch (phase) {
            RuntimePhase.busy => 'Directory in use',
            RuntimePhase.fault =>
              'Runtime fault — resource release may be unknown',
            _ => 'Closing',
          }),
          findsOneWidget,
        );
        await tester.tap(find.text('Device').first);
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
      runtime.setPhase(RuntimePhase.closed);
      await tester.pump();
      expect(tester.takeException(), null);
      expect(runtime.closes, 0);
      await runtime.states.close();
      await runtime.reads.close();
      expect(find.byType(ElevatedButton), findsNothing);
    },
  );

  testWidgets('explicit probe starts once and reports boundary failure', (
    tester,
  ) async {
    var calls = 0;
    final request = ProbeRequest.parse([
      '--meshchan-probe=write',
      '--fixture=/private/tmp/meshchan-1d2-widget',
    ])!;
    await tester.pumpWidget(
      MeshchanApp(
        request: request,
        probe: (_) async {
          calls++;
          throw StateError('Injected failure');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('probe_boundary_failed'), findsOneWidget);
    await tester.pump();
    expect(calls, 1);
  });

  test('Cocoa launch options preserve explicit probe selection', () {
    for (final option in [
      '-NSDocumentRevisionsDebugMode',
      '-NSTreatUnknownArgumentsAsOpen',
      '-ApplePersistenceIgnoreState',
    ]) {
      for (final enabled in ['YES', 'NO']) {
        expect(ProbeRequest.parse([option, enabled]), isNull);
        final request = ProbeRequest.parse([
          '--meshchan-probe=read',
          option,
          enabled,
          '--fixture=/private/tmp/meshchan-1d2-xcode',
          '--probe-exit',
        ])!;
        expect(request.mode, 'read');
        expect(request.directory, '/private/tmp/meshchan-1d2-xcode');
        expect(request.exitWhenDone, true);
      }
      for (final suffix in [
        <String>[],
        ['--meshchan-probe=write'],
        ['unexpected'],
      ]) {
        expect(
          () => ProbeRequest.parse([option, ...suffix]),
          throwsFormatException,
        );
      }
    }
  });

  test('invalid launch requests fail before a resource boundary exists', () {
    expect(ProbeRequest.parse([]), isNull);
    for (final arguments in [
      ['--meshchan-probe=delete', '--fixture=/private/tmp/meshchan-1d2-x'],
      ['--meshchan-probe=write', '--fixture=relative/meshchan-1d2-x'],
      [
        '--meshchan-probe=read',
        '--fixture=/Users/user/Library/Application Support/meshchan',
      ],
      ['--meshchan-probe=read', '--fixture=/private/tmp/../meshchan-1d2-x'],
      ['--enumerate-serial'],
      [
        '--meshchan-probe=write',
        '--fixture=/private/tmp/meshchan-1d2-x',
        '--enumerate-serial',
        '--enumerate-serial',
      ],
      ['-NSDocumentRevisionsDebugMode'],
      ['-NSDocumentRevisionsDebugMode', '--meshchan-probe=write'],
      ['-NSDocumentRevisionsDebugMode', 'unexpected'],
      ['-UnknownCocoaOption', 'YES'],
      [
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '--meshchan-probe=delete',
        '--fixture=/private/tmp/meshchan-1d2-xcode',
      ],
      [
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '--meshchan-probe=read',
        '--meshchan-probe=write',
        '--fixture=/private/tmp/meshchan-1d2-xcode',
      ],
    ]) {
      expect(() => ProbeRequest.parse(arguments), throwsFormatException);
    }
  });
}

class _Runtime implements AppRuntime {
  @override
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after}) async =>
      DraftPage([], null);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
  final states = StreamController<RuntimeSnapshot>.broadcast(sync: true);
  final reads = StreamController<OfflineSnapshot>.broadcast(sync: true);
  int starts = 0, closes = 0;
  @override
  RuntimeSnapshot snapshot = const RuntimeSnapshot(
    generation: 1,
    phase: RuntimePhase.opening,
  );
  void setPhase(RuntimePhase phase) {
    snapshot = RuntimeSnapshot(generation: 1, phase: phase);
    states.add(snapshot);
  }

  @override
  Stream<RuntimeSnapshot> get changes => states.stream;
  @override
  Stream<OfflineSnapshot> get offlineChanges => reads.stream;
  @override
  OfflineSnapshot? get offline => null;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<OfflineSnapshot> refresh({
    int pageSize = 20,
    DraftCursor? after,
  }) async => OfflineSnapshot(null, 1000, [], null);
  @override
  Future<ShutdownOutcome> shutdown() async {
    closes++;
    return const ShutdownOutcome(true, true);
  }
}
