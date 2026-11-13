import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
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
  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool redo = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  for (final name in ['title', 'body']) {
    testWidgets(
      'focused $name composition blocks quit before a modal steals focus',
      (tester) async {
        final (r, q) = await launch(tester);
        await tester.tap(find.text('New'));
        await tester.pumpAndSettle();
        await tester.tap(field(name));
        const value = TextEditingValue(
          text: 'zhong',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        );
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        final exiting = q.requestQuit();
        await tester.pumpAndSettle();
        // Drive the former vulnerable dialog too, so the before-fix reproduction
        // observes the erroneous committed preedit and allowed exit.
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
          await tester.pumpAndSettle();
        }
        expect(await exiting, false);
        expect(r.writes, isEmpty);
        expect(r.shutdowns, 0);
        expect(r.begins, 0);
        expect(q.editor.quitting, false);
        expect(
          name == 'title' ? q.editor.title.value : q.editor.body.value,
          value,
        );
        expect(find.byType(AlertDialog), findsNothing);
        final editable = tester.widget<EditableText>(
          find.descendant(of: field(name), matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, true);
        expect(
          find.text('Finish composing text before leaving.'),
          findsOneWidget,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('mouse Save and Command+S preserve focused $name composition', (
      tester,
    ) async {
      final (r, q) = await launch(tester);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(field(name));
      const value = TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      tester.testTextInput.updateEditingValue(value);
      // A native text-input update can precede the next rendered frame.
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyS);
      expect(r.writes, isEmpty);
      expect(
        name == 'title' ? q.editor.title.value : q.editor.body.value,
        value,
      );
      expect(find.text('Finish composing text before saving.'), findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: field(name), matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, true);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets(
      '$name Undo cannot cross draft sessions; ordinary save keeps history',
      (tester) async {
        final r = DraftRuntime();
        r.records['a'] = draft('a', title: 'A title', body: 'A body');
        r.records['b'] = draft('b', title: 'B title', body: 'B body');
        final (_, q) = await launch(tester, runtime: r);
        await tester.tap(find.byKey(const ValueKey('a')));
        await tester.pumpAndSettle();
        await tester.tap(field(name));
        await tester.pump(const Duration(seconds: 1));
        await tester.enterText(field(name), 'A edited');
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        await tester.tap(field(name));
        await shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(
          name == 'title' ? q.editor.title.text : q.editor.body.text,
          name == 'title' ? 'A title' : 'A body',
        );
        await shortcut(tester, LogicalKeyboardKey.keyZ, redo: true);
        expect(
          name == 'title' ? q.editor.title.text : q.editor.body.text,
          'A edited',
        );
        expect(q.editor.dirty, false);
        await tester.tap(find.byKey(const ValueKey('b')));
        await tester.pumpAndSettle();
        await tester.tap(field(name));
        await tester.pump(const Duration(seconds: 1));
        await shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(q.editor.baseline!.id, 'b');
        expect(q.editor.title.text, 'B title');
        expect(q.editor.body.text, 'B body');
        expect(q.editor.dirty, false);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(r.writes.last.id, 'b');
        expect(r.writes.last.title, 'B title');
        expect(r.writes.last.body, 'B body');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final destination in ['New', 'Device', 'b']) {
    testWidgets(
      'composing departure to $destination keeps the actual input value',
      (tester) async {
        final r = DraftRuntime();
        r.records['b'] = draft('b', title: 'Other');
        final (_, q) = await launch(tester, runtime: r);
        await tester.tap(find.text('New'));
        await tester.pumpAndSettle();
        await tester.tap(field('body'));
        const value = TextEditingValue(
          text: 'zhong',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        );
        tester.testTextInput.updateEditingValue(value);
        // The departure guard must read live input, not the last build's value.
        await tester.tap(
          destination == 'b'
              ? find.byKey(const ValueKey('b'))
              : find.text(destination).first,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
          await tester.pumpAndSettle();
        }
        expect(r.writes, isEmpty);
        expect(q.editor.body.value, value);
        expect(q.editor.baseline, null);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const ValueKey('draft-body')), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final destination in ['Device', 'quit']) {
    testWidgets(
      'unknown during an open $destination dialog requires a second visible decision',
      (tester) async {
        final (r, q) = await launch(tester);
        await tester.tap(find.text('New'));
        await tester.pumpAndSettle();
        await tester.enterText(field('body'), 'local pending text');
        final pending = Completer<DraftSnapshot>();
        r.onSave = (_) => pending.future;
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pump();
        Future<bool>? exiting;
        if (destination == 'quit') {
          exiting = q.requestQuit();
          expect(q.requestQuit(), same(exiting));
        } else {
          await tester.tap(find.text('Device').first);
        }
        await tester.pumpAndSettle();
        expect(find.text('Leave this draft?'), findsOneWidget);
        pending.completeError(
          const RuntimeFault(host: CoordinationFault.requestUnknown),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.text('Write result unknown'), findsOneWidget);
        expect(
          find.textContaining('may already have committed'),
          findsOneWidget,
        );
        expect(q.editor.body.text, 'local pending text');
        await tester.tap(find.text('Continue editing'));
        await tester.pumpAndSettle();
        expect(q.editor.unknown, true);
        expect(q.editor.body.text, 'local pending text');
        expect(r.writes.length, 1);
        expect(r.shutdowns, 0);
        if (exiting != null) expect(await exiting, false);
      },
    );
  }

  for (final replacement in ['New', 'Reload']) {
    testWidgets(
      '$replacement discards the old undo stack and pending throttle',
      (tester) async {
        final r = DraftRuntime();
        r.records['a'] = draft('a', body: 'baseline');
        final (_, q) = await launch(tester, runtime: r);
        await tester.tap(find.byKey(const ValueKey('a')));
        await tester.pumpAndSettle();
        await tester.tap(field('body'));
        await tester.pump(const Duration(seconds: 1));
        await tester.enterText(field('body'), 'discarded local edit');
        // Replace before the SDK's 500 ms undo push can settle.
        if (replacement == 'New') {
          await tester.tap(find.text('New'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Discard'));
          await tester.pumpAndSettle();
        } else {
          r.onSave = (_) =>
              Future.error(const RuntimeFault(core: CoreErrorCode.conflict));
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
          r.records['a'] = draft('a', revision: 7, body: 'stored replacement');
          await tester.tap(find.text('View stored version'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Inspect stored revision 7 / Reload'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
          await tester.pumpAndSettle();
        }
        await tester.tap(field('body'));
        await tester.pump(const Duration(seconds: 1));
        await shortcut(tester, LogicalKeyboardKey.keyZ);
        expect(
          q.editor.body.text,
          replacement == 'New' ? '' : 'stored replacement',
        );
        expect(q.editor.dirty, false);
        if (replacement == 'New') {
          expect(q.editor.baseline, null);
        } else {
          expect(q.editor.baseline!.revision, 7);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
