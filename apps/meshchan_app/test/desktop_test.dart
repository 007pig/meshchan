import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/app.dart';
import 'package:meshchan_app/desktop/commands.dart';
import 'package:meshchan_app/desktop/host_dispatch.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/drafts/editor.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart' show AppSettings;

import 'support/draft_runtime.dart';
import 'profiles_test.dart' show ProfileRuntime;

class _DelayedSettingsRuntime extends ProfileRuntime {
  final settingsRead = Completer<AppSettings>();
  int settingsReads = 0;
  DraftSnapshot savedDraft = draft('a', title: 'Stored', body: 'baseline');
  final draftWrites = <WriteDraft>[];

  @override
  Future<AppSettings> readSettings() {
    settingsReads++;
    return settingsRead.future;
  }

  @override
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after}) async =>
      DraftPage([savedDraft], null);

  @override
  Future<DraftSnapshot> readDraft(String id) async => savedDraft;

  @override
  Future<DraftSnapshot> saveDraft({
    required String title,
    required String body,
    String? id,
    int? expectedRevision,
    int? session,
    DraftDecision? decision,
  }) async {
    draftWrites.add(
      WriteDraft(
        title: title,
        body: body,
        id: id,
        expectedRevision: expectedRevision,
        session: session,
        decision: decision,
      ),
    );
    return savedDraft = draft(
      id ?? 'new',
      revision: (expectedRevision ?? 0) + 1,
      title: title,
      body: body,
    );
  }
}

void main() {
  test('one platform dispatcher keeps Quit and fails closed without a business handler', () async {
    var quits = 0;
    final commands = DesktopCommands();
    final bridge = HostPlatformDispatch(() async {
      quits++;
      return false;
    }, commands: commands);
    expect(await bridge.handle(const MethodCall('requestQuit')), false);
    expect(quits, 1);
    expect(
      await bridge.handle(const MethodCall('desktopCommand', 'save')),
      false,
    );
    expect(
      await bridge.handle(
        const MethodCall('nativeSheetChanged', {'job': 3, 'active': true}),
      ),
      true,
    );
    expect(
      await bridge.handle(
        const MethodCall('nativeSheetChanged', {'job': 2, 'active': false}),
      ),
      true,
    );
    expect(commands.sheetActive, true);
    await expectLater(
      bridge.handle(const MethodCall('unknown')),
      throwsA(isA<MissingPluginException>()),
    );
    commands.dispose();
  });
  Future<void> key(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(key);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
  }

  Future<(_DelayedSettingsRuntime, DesktopCommands, DraftQuitCoordinator)>
  launchDelayedSettings(WidgetTester t) async {
    final r = _DelayedSettingsRuntime(), c = DesktopCommands();
    final q = DraftQuitCoordinator(r);
    t.view.physicalSize = const Size(1100, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MeshchanApp(
        runtime: r,
        quitCoordinator: q,
        desktopCommands: c,
        probe: (_) async => {},
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('a')));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      q.disposeEditors();
      c.dispose();
    });
    return (r, c, q);
  }

  for (final choice in ['Continue editing', 'Save', 'Discard']) {
    testWidgets('Settings rechecks edits entered during its read: $choice', (
      t,
    ) async {
      final (r, c, q) = await launchDelayedSettings(t);
      final navigation = c.invoke('settings');
      await t.pump();
      expect(r.settingsReads, 1);
      expect(q.auxiliaryActive, false);
      await t.enterText(
        find.byKey(const ValueKey('draft-body')),
        'new during Settings read',
      );
      r.settingsRead.complete(AppSettings());
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(q.auxiliaryActive, false);
      expect(await c.invoke('settings'), false);
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(choice),
        ),
      );
      await t.pumpAndSettle();
      expect(await navigation, choice != 'Continue editing');
      expect(r.draftWrites.length, choice == 'Save' ? 1 : 0);
      expect(
        q.editor.body.text,
        choice == 'Discard' ? 'baseline' : 'new during Settings read',
      );
      if (choice == 'Continue editing') {
        expect(find.byKey(const ValueKey('draft-body')), findsOneWidget);
        expect(q.editor.dirty, true);
        final exiting = q.requestQuit();
        await t.pumpAndSettle();
        expect(find.text('Leave this draft?'), findsOneWidget);
        await t.tap(find.text('Continue editing'));
        await t.pumpAndSettle();
        expect(await exiting, false);
        expect(r.shutdowns, 0);
      } else {
        expect(q.editor.dirty, false);
        expect(find.text('Save settings'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'Settings completion preserves live composition entered during its read',
    (t) async {
      final (r, c, q) = await launchDelayedSettings(t);
      final navigation = c.invoke('settings');
      await t.pump();
      final field = find.byKey(const ValueKey('draft-body'));
      await t.tap(field);
      const value = TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      t.testTextInput.updateEditingValue(value);
      // No build between the native input update and the async completion.
      r.settingsRead.complete(AppSettings());
      await t.pumpAndSettle();
      expect(await navigation, false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(q.auxiliaryActive, false);
      expect(q.editor.body.value, value);
      final input = t.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(input.focusNode.hasFocus, true);
      expect(input.readOnly, false);
      expect(r.draftWrites, isEmpty);
      expect(await q.requestQuit(), false);
      expect(r.begins, 0);
      expect(r.shutdowns, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Settings completion cannot navigate away from a replacement Draft session',
    (t) async {
      final (r, c, q) = await launchDelayedSettings(t);
      final navigation = c.invoke('settings');
      await t.pump();
      final original = q.editor.documentGeneration;
      expect(
        await q.editor.newDraft(
          ({required unknown}) async => LeaveChoice.discard,
        ),
        true,
      );
      expect(q.editor.documentGeneration, isNot(original));
      r.settingsRead.complete(AppSettings());
      await t.pumpAndSettle();
      expect(await navigation, false);
      expect(q.auxiliaryActive, false);
      expect(find.byKey(const ValueKey('draft-body')), findsOneWidget);
      expect(q.editor.baseline, null);
      expect(r.draftWrites, isEmpty);
    },
  );

  testWidgets(
    'supported viewports keep every existing page and long errors reachable',
    (t) async {
      final r = ProfileRuntime(),
          c = DesktopCommands(),
          q = DraftQuitCoordinator(ProfileRuntime());
      q.disposeEditors();
      final coordinator = DraftQuitCoordinator(r);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MeshchanApp(
          runtime: r,
          quitCoordinator: coordinator,
          desktopCommands: c,
          probe: (_) async => {},
        ),
      );
      await t.pumpAndSettle();
      for (final size in [
        const Size(800, 600),
        const Size(1024, 768),
        const Size(1280, 800),
        const Size(800, 600),
      ]) {
        t.view.physicalSize = size;
        await t.pumpAndSettle();
        for (final name in ['Device', 'Diagnostics', 'Drafts']) {
          await t.tap(find.text(name).first);
          await t.pumpAndSettle();
          expect(t.takeException(), null, reason: '$size $name');
        }
        expect(await c.invoke('settings'), true);
        await t.pumpAndSettle();
        coordinator.profiles.notice =
            'Controlled save failure: ${'long_owned_path_segment/' * 100} Continue editing or retry an explicit read.';
        coordinator.profiles.notify();
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Save settings'));
        await t.pumpAndSettle();
        expect(
          t.getRect(find.text('Save settings')).overlaps(Offset.zero & size),
          true,
        );
        for (final name in ['Offline preview', 'Profiles']) {
          await t.tap(find.text(name).first);
          await t.pumpAndSettle();
          expect(t.takeException(), null, reason: '$size $name');
        }
      }
      await t.pumpWidget(const SizedBox());
      coordinator.disposeEditors();
      c.dispose();
    },
  );

  testWidgets(
    'Save callbacks recheck live context, coalesce, and respect native sheets and dialogs',
    (t) async {
      final r = DraftRuntime(), c = DesktopCommands();
      final q = DraftQuitCoordinator(r);
      t.view.physicalSize = const Size(1024, 768);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MeshchanApp(
          runtime: r,
          quitCoordinator: q,
          desktopCommands: c,
          probe: (_) async => {},
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('New'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('draft-title')), '中文 🛰️');
      final pending = Completer<DraftSnapshot>();
      r.onSave = (_) => pending.future;
      final save = c.invoke('save');
      await key(t, LogicalKeyboardKey.keyS);
      expect(r.writes.length, 1);
      pending.complete(draft('saved', title: '中文 🛰️'));
      expect(await save, true);
      await t.pumpAndSettle();
      r.onSave = null;
      expect(c.canSave, true);
      await t.tap(find.byKey(const ValueKey('draft-title')));
      const preedit = TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      t.testTextInput.updateEditingValue(preedit);
      expect(await c.invoke('save'), false);
      expect(await c.invoke('settings'), false);
      expect(q.editor.title.value, preedit);
      expect(r.writes.length, 1);
      t.testTextInput.updateEditingValue(
        preedit.copyWith(composing: TextRange.empty),
      );
      c.sheetChanged(2, true);
      c.sheetChanged(1, false);
      expect(await c.invoke('save'), false);
      expect(await c.invoke('settings'), false);
      c.sheetChanged(2, false);
      c.sheetChanged(2, true);
      expect(c.sheetActive, false);
      await t.tap(find.text('Device').first);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await c.invoke('save'), false);
      expect(await c.invoke('settings'), false);
      expect(await c.invoke('cancelDialog'), true);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(q.editor.title.text, 'zhong');
      expect(r.writes.length, 1);
      await t.tap(find.text('Device').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Discard'));
      await t.pumpAndSettle();
      expect(c.canSave, false);
      expect(await c.invoke('save'), false);
      expect(r.writes.length, 1);
      await t.pumpWidget(const SizedBox());
      q.disposeEditors();
      c.dispose();
      await r.states.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Settings command reaches the actual subpage, merges navigation, and saves only settings',
    (t) async {
      final r = ProfileRuntime(),
          c = DesktopCommands(),
          q = DraftQuitCoordinator(ProfileRuntime());
      q.disposeEditors();
      final coordinator = DraftQuitCoordinator(r);
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MeshchanApp(
          runtime: r,
          quitCoordinator: coordinator,
          desktopCommands: c,
          probe: (_) async => {},
        ),
      );
      await t.pumpAndSettle();
      await key(t, LogicalKeyboardKey.comma);
      expect(find.text('Save settings'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('history-limit')), '42');
      expect(await c.invoke('save'), true);
      expect(r.settings.diagnosticHistoryLimit, 42);
      await t.tap(find.text('Offline preview'));
      await t.pumpAndSettle();
      expect(c.canSave, false);
      expect(await c.invoke('save'), false);
      expect(await c.invoke('settings'), true);
      await t.pumpAndSettle();
      expect(find.text('Save settings'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('history-limit')), '43');
      await t.tap(find.text('Profiles'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await c.invoke('settings'), false);
      await t.tap(find.text('Continue editing'));
      await t.pumpAndSettle();
      expect(coordinator.profiles.history.text, '43');
      expect(find.text('Save settings'), findsOneWidget);
      expect(t.takeException(), null);
      await t.pumpWidget(const SizedBox());
      coordinator.disposeEditors();
      c.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
