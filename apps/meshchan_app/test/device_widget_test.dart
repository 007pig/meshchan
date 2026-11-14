import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/device/model.dart';
import 'package:meshchan_app/device/view.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshcore_link/meshcore_link.dart';

import '../tool/device_fixture.dart';

class DeviceRuntime implements AppRuntime {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
  @override
  RuntimeSnapshot snapshot = const RuntimeSnapshot(
    generation: 1,
    phase: RuntimePhase.ready,
  );
  final states = StreamController<RuntimeSnapshot>.broadcast(sync: true);
  @override
  Stream<RuntimeSnapshot> get changes => states.stream;
  int enumerations = 0, starts = 0;
  final cancels = <int>[];
  List<SerialPortDescription> ports = const [];
  DeviceFailure? failure;
  Completer<void>? ack;
  String? capturedPort;
  DeviceCheckOptions? capturedOptions;
  @override
  Future<DevicePortsValue> refreshDevicePorts(int generation) async {
    enumerations++;
    return DevicePortsValue(generation, ports, failure: failure);
  }

  @override
  DeviceCheckHandle startDeviceCheck(String port, DeviceCheckOptions options) {
    starts++;
    capturedPort = port;
    capturedOptions = options;
    return DeviceCheckHandle(starts, ack?.future ?? Future.value());
  }

  @override
  Future<void> cancelDeviceCheck(int id) async {
    cancels.add(id);
  }
}

void main() {
  late DeviceRuntime runtime;
  late DeviceModel model;
  setUp(() {
    runtime = DeviceRuntime();
    model = DeviceModel(runtime);
  });
  tearDown(() async {
    model.dispose();
    await runtime.states.close();
  });
  test('no implicit enumeration/selection; empty, partial, stale and disappeared paths', () async {
    expect(runtime.enumerations, 0);
    expect(model.selected, null);
    expect(model.options!.requestSeconds, 5);
    expect(model.options!.initializationSeconds, 15);
    expect(model.options!.startupMilliseconds, 0);
    await model.check();
    expect(runtime.starts, 0);
    await model.refresh();
    expect(model.listed, true);
    expect(model.ports, isEmpty);
    runtime.ports = const [
      SerialPortDescription(
        path: ' A ',
        transport: 'USB',
        usbVid: 1,
        usbPid: 2,
      ),
      SerialPortDescription(path: 'B', warning: 'partial'),
    ];
    await model.refresh();
    expect(model.selected, null);
    model.select(' A ');
    expect(model.selected, ' A ');
    runtime.failure = const DeviceFailure('enumerationFailed');
    await model.refresh();
    expect(model.stale, true);
    expect(model.ports.length, 2);
    await model.check();
    expect(runtime.starts, 0);
    runtime.failure = null;
    runtime.ports = const [SerialPortDescription(path: 'B')];
    await model.refresh();
    expect(model.selected, null);
    expect(model.stale, false);
  });
  test('raw integer validation, bounds and exact cross constraint', () {
    for (final invalid in ['', ' ', '-1', '+1', '1.5', '1e2', '86401', '0']) {
      model.request.text = invalid;
      expect(model.options, null, reason: invalid);
      expect(model.request.text, invalid);
    }
    model.request.text = '86400';
    model.initialization.text = '86400';
    model.startup.text = '86399999';
    expect(model.options, isNotNull);
    model.startup.text = '86400000';
    expect(model.options, null);
    model.initialization.text = '15';
    model.startup.text = '15000';
    expect(model.options, null);
    model.startup.text = '14999';
    expect(model.options, isNotNull);
    model.initialization.text = '0';
    expect(model.options, null);
  });
  test('frozen A/options, B selection and cancel intent before ack', () async {
    runtime.ports = const [
      SerialPortDescription(path: ' A '),
      SerialPortDescription(path: 'B'),
    ];
    await model.refresh();
    model.select(' A ');
    runtime.ack = Completer<void>();
    final started = model.check();
    model.request.text = '9';
    model.select('B');
    await model.cancel();
    expect(runtime.cancels, [1]);
    expect(model.cancelRequested, 1);
    expect(runtime.capturedPort, ' A ');
    expect(runtime.capturedOptions!.requestSeconds, 5);
    await model.check();
    expect(runtime.starts, 1);
    runtime.ack!.complete();
    await started;
  });
  testWidgets(
    'real controls show metadata, invalid raw text and composition guards',
    (tester) async {
      runtime.ports = const [
        SerialPortDescription(path: 'A', warning: 'partial'),
        SerialPortDescription(path: 'B'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeviceView(model: model)),
        ),
      );
      expect(runtime.enumerations, 0);
      expect(find.text('Not connected'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(model.selected, null);
      expect(find.textContaining('Metadata warning: partial'), findsOneWidget);
      model.request.value = const TextEditingValue(
        text: 'zhongwen',
        composing: TextRange(start: 0, end: 8),
      );
      await tester.pump();
      await tester.tap(find.text('Select a port'));
      await tester.pump();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(model.composing, true);
      model.request.value = const TextEditingValue(text: '5');
      await tester.pump();
      await tester.tap(find.text('Select a port'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A').last);
      await tester.pumpAndSettle();
      expect(model.selected, 'A');
      model.startup.text = '-1';
      await tester.pump();
      expect(model.startup.text, '-1');
      expect(model.inputError, isNotNull);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'focused Device inputs retain composition on mouse menu and refresh taps',
    (tester) async {
      runtime.ports = const [SerialPortDescription(path: 'A')];
      await model.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeviceView(model: model)),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 3; index++) {
        final field = find.byType(TextField).at(index);
        await tester.ensureVisible(field);
        await tester.tap(field, kind: PointerDeviceKind.mouse);
        await tester.showKeyboard(field);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'zhongwen',
            selection: TextSelection.collapsed(offset: 8),
            composing: TextRange(start: 0, end: 8),
          ),
        );
        await tester.pump();
        expect(
          tester
              .state<EditableTextState>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .widget
              .focusNode
              .hasFocus,
          true,
          reason: 'before mouse index $index',
        );
        await tester.tap(
          find.text('Select a port'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        final editable = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        expect(
          editable.widget.focusNode.hasFocus,
          true,
          reason: 'after mouse index $index',
        );
        expect(
          model.inputs[index].value.composing,
          const TextRange(start: 0, end: 8),
        );
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        await tester.tap(find.text('Refresh'), kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(
          editable.widget.focusNode.hasFocus,
          true,
          reason: 'after mouse index $index',
        );
        expect(runtime.enumerations, 1);
        model.inputs[index].value = TextEditingValue(
          text: ['5', '15', '0'][index],
        );
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'history keeps captured source/time and units after navigation/rebuild',
    (tester) async {
      final info = (await tester.runAsync(() async {
        final t = DeviceFixtureTransport();
        final session = MeshCoreSession(transport: t);
        final info = DeviceInformation(
          await session.connect(),
          'A',
          DateTime.utc(2026, 11, 14),
        );
        await session.close();
        return info;
      }))!;
      runtime.snapshot = RuntimeSnapshot(
        generation: 1,
        phase: RuntimePhase.ready,
        lastDeviceInfo: info,
        deviceCheck: const DeviceCheckSnapshot(
          id: 1,
          port: 'A',
          options: DeviceCheckOptions(),
          settled: true,
          state: MeshCoreSessionState.closed,
          sessionCleanup: DeviceCleanup.succeeded,
          observerCleanup: DeviceCleanup.succeeded,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeviceView(model: model)),
        ),
      );
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.textContaining('Source port: A'), findsOneWidget);
      expect(find.textContaining('Reported protocol code: 14'), findsOneWidget);
      expect(find.textContaining('TX power: -4 dBm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeviceView(model: model)),
        ),
      );
      expect(runtime.starts, 0);
      expect(runtime.enumerations, 0);
      expect(runtime.snapshot.lastDeviceInfo, same(info));
    },
  );
  test(
    'application quit/navigation defer for live Device composition',
    () async {
      final quit = DraftQuitCoordinator(runtime);
      quit.device.request.value = const TextEditingValue(
        text: 'zhongwen',
        composing: TextRange(start: 0, end: 8),
      );
      expect(
        await quit.leaveCurrent(
          ({required unknown}) async => throw StateError('modal'),
        ),
        false,
      );
      expect(await quit.requestQuit(), false);
      expect(quit.device.composing, true);
      quit.disposeEditors();
    },
  );
}
