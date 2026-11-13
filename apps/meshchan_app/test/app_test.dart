import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/app.dart';
import 'package:meshchan_app/probe_request.dart';

void main() {
  testWidgets(
    'normal launch and all navigation never invoke the resource boundary',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MeshchanApp(
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
      expect(
        find.textContaining('Draft storage is not connected'),
        findsOneWidget,
      );
      await tester.tap(find.text('Device'));
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
