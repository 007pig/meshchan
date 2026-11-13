import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/app.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'support/draft_runtime.dart';

void main() {
  Future<(DraftRuntime, DraftQuitCoordinator)> launch(
    WidgetTester tester, {
    DraftRuntime? runtime,
  }) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final r = runtime ?? DraftRuntime();
    final quit = DraftQuitCoordinator(r);
    await tester.pumpWidget(
      MeshchanApp(runtime: r, quitCoordinator: quit, probe: (_) async => {}),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      quit.editor.dispose();
      await r.states.close();
    });
    return (r, quit);
  }

  Finder field(String name) => find.byKey(ValueKey('draft-$name'));
  Future<void> commandSave(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  testWidgets(
    'buttons and Command+S share create/update; A/B preserves selection/composition',
    (tester) async {
      final (r, q) = await launch(tester);
      expect(find.text('No drafts in this page.'), findsOneWidget);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      final text = ' 中文🙂 e\u0301 � \n${'long body ' * 100}';
      await tester.enterText(field('title'), ' \nTitle\r\n ');
      await tester.enterText(field('body'), text);
      await tester.pump();
      expect(
        find.text('Body UTF-8 bytes: ${utf8.encode(text).length}'),
        findsOneWidget,
      );
      final pending = Completer<DraftSnapshot>();
      r.onSave = (_) => pending.future;
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(field('body'));
      const value = TextEditingValue(
        text: 'B中文',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
        composing: TextRange(start: 1, end: 3),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      await commandSave(tester);
      expect(r.writes.length, 1);
      pending.complete(
        draft(
          'created',
          title: r.writes.single.title,
          body: r.writes.single.body,
        ),
      );
      await tester.pumpAndSettle();
      expect(q.editor.body.value, value);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await commandSave(tester);
      expect(r.writes.length, 1);
      expect(find.text('Finish composing text before saving.'), findsOneWidget);
      tester.testTextInput.updateEditingValue(
        value.copyWith(composing: TextRange.empty),
      );
      await tester.pump();
      r.onSave = null;
      await commandSave(tester);
      await tester.pumpAndSettle();
      expect(r.writes.last.id, 'created');
      expect(r.writes.last.expectedRevision, 1);
      expect(find.text('Saved'), findsOneWidget);
    },
  );

  testWidgets(
    'loaded mixed line endings stay exact when only other field changes',
    (tester) async {
      final r = DraftRuntime();
      const title = ' \n中文\r\n🙂 ', body = 'A\rB\nC\r\n';
      r.records['one'] = draft('one', title: title, body: body);
      final (_, q) = await launch(tester, runtime: r);
      await tester.tap(find.byKey(const ValueKey('one')));
      await tester.pumpAndSettle();
      expect(q.editor.title.text, title);
      expect(q.editor.body.text, body);
      await tester.enterText(field('body'), '$body+');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(r.writes.single.title, title);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('one')));
      await tester.pumpAndSettle();
      expect(q.editor.title.text, title);
      expect(q.editor.body.text, '$body+');
    },
  );

  testWidgets(
    'dirty page/New decisions use Save Discard Continue and restore editing',
    (tester) async {
      final (r, q) = await launch(tester);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(field('body'), 'local');
      await tester.tap(find.text('Device').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue editing'));
      await tester.pumpAndSettle();
      expect(q.editor.body.text, 'local');
      await tester.enterText(field('body'), 'still editable');
      await tester.tap(find.text('Device').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(r.writes.single.body, 'still editable');
      expect(find.textContaining('No ports have been listed'), findsOneWidget);
      await tester.tap(find.text('Drafts').first);
      await tester.pumpAndSettle();
      await tester.enterText(field('body'), 'discard');
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(q.editor.body.text, '');
      expect(r.deletes, isEmpty);
      expect(find.text('Not saved yet'), findsOneWidget);
    },
  );

  testWidgets(
    'conflict inspection and explicit Reload; unknown disables writes; narrow layout',
    (tester) async {
      final r = DraftRuntime();
      r.records['one'] = draft('one', title: 'existing');
      final (_, q) = await launch(tester, runtime: r);
      await tester.tap(find.byKey(const ValueKey('one')));
      await tester.pumpAndSettle();
      await tester.enterText(field('body'), 'local');
      r.onSave = (_) =>
          Future.error(const RuntimeFault(core: CoreErrorCode.conflict));
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Version conflict'), findsOneWidget);
      r.records['one'] = draft('one', revision: 9, body: 'stored');
      await tester.tap(find.text('View stored version'));
      await tester.pumpAndSettle();
      expect(q.editor.body.text, 'local');
      expect(q.editor.baseline!.revision, 1);
      await tester.tap(find.text('Inspect stored revision 9 / Reload'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
      await tester.pumpAndSettle();
      expect(q.editor.body.text, 'stored');
      expect(q.editor.baseline!.revision, 9);
      r.onSave = (_) => Future.error(
        const RuntimeFault(host: CoordinationFault.requestUnknown),
      );
      await tester.enterText(field('body'), 'unknown');
      await commandSave(tester);
      await tester.pumpAndSettle();
      expect(find.text('Save/delete result unknown'), findsOneWidget);
      final count = r.writes.length;
      await commandSave(tester);
      expect(r.writes.length, count);
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(680, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'delete confirmation binds saved target, failure retains it, committed success removes it',
    (tester) async {
      final r = DraftRuntime();
      r.records['one'] = draft('one', title: 'delete target');
      final (_, q) = await launch(tester, runtime: r);
      await tester.tap(find.byKey(const ValueKey('one')));
      await tester.pumpAndSettle();
      await tester.enterText(field('body'), 'local');
      r.onDelete = (_, _) =>
          Future.error(const RuntimeFault(core: CoreErrorCode.notFound));
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('discard these unsaved'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(q.editor.body.text, 'local');
      expect(q.editor.hasDocument, true);
      expect(find.textContaining('no longer exists'), findsOneWidget);
      r.onDelete = null;
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(q.editor.hasDocument, false);
      expect(r.deletes.last.id, 'one');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), null);
      expect(r.shutdowns, 0);
    },
  );
  testWidgets(
    'default macOS selection clipboard and Undo/Redo stay available',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var clipboard = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard.isNotEmpty};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (_, q) = await launch(tester);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(field('body'), 'one');
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(field('body'), 'two');
      await tester.pump(const Duration(seconds: 1));
      Future<void> shortcut(
        LogicalKeyboardKey key, {
        bool shift = false,
      }) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }

      await shortcut(LogicalKeyboardKey.keyZ);
      expect(q.editor.body.text, 'one');
      await shortcut(LogicalKeyboardKey.keyZ, shift: true);
      expect(q.editor.body.text, 'two');
      await shortcut(LogicalKeyboardKey.keyA);
      await shortcut(LogicalKeyboardKey.keyC);
      expect(clipboard, 'two');
      clipboard = ' 中文🙂 e\u0301 ';
      await shortcut(LogicalKeyboardKey.keyV);
      expect(q.editor.body.text, clipboard);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
