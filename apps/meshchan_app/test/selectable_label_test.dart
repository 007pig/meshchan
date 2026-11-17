import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshchan_app/widgets/selectable_label.dart';

void main() {
  testWidgets('live display labels keep static semantics across updates', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final value = ValueNotifier('Check 1: opening');
      addTearDown(value.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: value,
              builder: (context, text, _) => SelectableLabel(text),
            ),
          ),
        ),
      );
      void check(String text) {
        final nodes = <SemanticsNode>[];
        void visit(SemanticsNode node) {
          nodes.add(node);
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(tester.getSemantics(find.byType(SelectableLabel)));
        expect(
          nodes.any((node) => node.flagsCollection.isTextField),
          false,
          reason: 'Readonly status updates must not enter the native editable-text bridge',
        );
        expect(find.text(text), findsOneWidget);
        expect(find.byType(EditableText), findsNothing);
      }

      check(value.value);
      for (final text in ['Check 1: ready', 'Check 1: closed', '中文😀\nSaved']) {
        value.value = text;
        await tester.pump();
        check(text);
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('display text remains selectable and copies exact Unicode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': copied?.isNotEmpty ?? false};
        }
        if (call.method == 'Clipboard.getData') return {'text': copied};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const text = 'Status 中文😀\nSecond line';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SelectableLabel(text))),
    );
    await tester.tap(find.text(text), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, text);
  });
}
