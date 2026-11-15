import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/diagnostics/model.dart';
import 'package:meshchan_app/diagnostics/view.dart';
import 'package:meshchan_app/diagnostics/outcomes.dart';
import 'package:meshchan_app/device/model.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/profiles/editor.dart';
import 'package:meshchan_app/profiles/parameter_form.dart';
import 'package:meshchan_app/profiles/preview.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart' show SerialPortDescription;

import 'device_widget_test.dart' show DeviceRuntime;
import 'support/draft_runtime.dart' show DraftRuntime;

class DiagnosticRuntime extends DeviceRuntime {
  EffectiveParameterRequest? request;
  var accepted = Completer<void>();
  int diagnosticStarts = 0;
  @override
  DiagnosticHandle startRecordedDiagnostic(
    String port,
    EffectiveParameterRequest parameters,
  ) {
    diagnosticStarts++;
    capturedPort = port;
    request = parameters;
    return DiagnosticHandle(1, diagnosticStarts, accepted.future);
  }

  @override
  Future<void> cancelRecordedDiagnostic(DiagnosticHandle handle) async {
    cancels.add(handle.id);
  }

  final previews = <Completer<EffectiveParameters>>[];
  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest request,
  ) {
    final c = Completer<EffectiveParameters>();
    previews.add(c);
    return c.future;
  }
}

void main() {
  late DiagnosticRuntime r;
  late DeviceModel d;
  late DiagnosticsModel m;
  setUp(() {
    r = DiagnosticRuntime();
    d = DeviceModel(r);
    m = DiagnosticsModel(r, d);
  });
  tearDown(() async {
    m.dispose();
    d.dispose();
    await r.states.close();
  });
  void select() {
    d.ports = const [SerialPortDescription(path: ' exact ')];
    d.listed = true;
    d.select(' exact ');
  }

  test('PING/respond invocation presence, lexical input and byte counts', () {
    expect(m.form.operation, DiagnosticOperation.ping);
    expect((m.form.request() as PingParameterRequest).content, null);
    m.mode = ContentMode.text;
    expect(m.bytes, isEmpty);
    m.content.text = '中文🙂';
    expect(m.bytes!.length, 10);
    m.mode = ContentMode.hex;
    m.content.text = '';
    expect(m.bytes, isEmpty);
    for (final bad in ['0x01', '01 02', 'a', '01\n']) {
      m.content.text = bad;
      expect(() => m.bytes, throwsFormatException);
    }
    m.changeOperation(DiagnosticOperation.respond);
    expect(m.form.request(), isA<RespondParameterRequest>());
    expect(m.form.fields, isNot(contains(ParameterField.dataType)));
    expect(m.form.explicit, isEmpty);
    m.form.inputs[ParameterField.routeDescriptor]!.text = '0xff';
    m.form.explicit.add(ParameterField.routeDescriptor);
    expect(
      (m.form.request() as RespondParameterRequest).overrides.route!.path,
      null,
    );
    m.form.explicit.add(ParameterField.path);
    expect(
      (m.form.request() as RespondParameterRequest).overrides.route!.path,
      isEmpty,
    );
  });
  test('exact current session port; stale/unavailable/fault cannot start; frozen request', () async {
    expect(m.canStart, false);
    select();
    expect(m.canStart, true);
    d.stale = true;
    await m.startDiagnostic();
    expect(r.diagnosticStarts, 0);
    d.stale = false;
    m.mode = ContentMode.text;
    m.content.text = '';
    final start = m.startDiagnostic();
    final duplicate = m.startDiagnostic();
    expect(r.diagnosticStarts, 1);
    expect(r.capturedPort, ' exact ');
    expect((r.request as PingParameterRequest).content, isEmpty);
    expect(m.locked, true);
    d.selected = 'later';
    await m.cancelDiagnostic();
    await m.cancelDiagnostic();
    expect(r.cancels, [1]);
    r.accepted.complete();
    await start;
    await duplicate;
    expect(m.frozenPort, ' exact ');
    r.snapshot = const RuntimeSnapshot(
      generation: 1,
      phase: RuntimePhase.fault,
      gate: DeviceGateState.quarantined,
    );
    expect(m.locked, false);
    m.content.text = 'next';
    expect(m.canStart, false);
    expect((m.frozenRequest as PingParameterRequest).content, isEmpty);
  });
  test('edited preview cannot replace newer invocation; preview has no device effects', () async {
    m.mode = ContentMode.text;
    final old = m.preview();
    m.changeOperation(DiagnosticOperation.respond);
    r.previews.single.complete(
      EffectiveParameters(
        profileId: null,
        parameters: RespondProfileParameters(
          budgets: ProfileBudgets(taskTimeoutSeconds: 2),
          sendChannelIndex: 0,
          receiveChannelIndex: 1,
          route: ProfileRoute(routeDescriptor: 255),
          endpoints: ProfileTestEndpoints(localTestId: 1, peerTestId: 2),
          listenDurationSeconds: 1,
        ),
      ),
    );
    await old;
    expect(m.result, null);
    expect(r.diagnosticStarts, 0);
    expect(r.enumerations, 0);
  });
  for (final observed in [false, true]) {
    test(
      'late admission failure preserves matching input identity, observed=$observed',
      () async {
        select();
        m.mode = ContentMode.text;
        m.content.text = 'first';
        final first = m.startDiagnostic();
        final previousRequest = m.frozenRequest;
        r.snapshot = const RuntimeSnapshot(
          generation: 1,
          phase: RuntimePhase.ready,
          operation: OperationSnapshot(generation: 1, attemptId: 1, done: true),
        );
        r.accepted.complete();
        await first;
        final previousResult = m.attempt;
        d.ports = const [SerialPortDescription(path: ' next explicit ')];
        d.select(' next explicit ');
        m.content.text = 'second';
        r.accepted = Completer<void>();
        final next = m.startDiagnostic();
        expect(m.attempt, null); // Old results are not shown with the new port.
        r.snapshot = RuntimeSnapshot(
          generation: 1,
          phase: RuntimePhase.fault,
          operation: observed
              ? const OperationSnapshot(generation: 2, attemptId: 2)
              : previousResult,
        );
        r.accepted.completeError(
          const RuntimeFault(host: CoordinationFault.requestUnknown),
        );
        await next;
        expect(m.handle!.id, 2);
        expect(m.frozenPort, ' next explicit ');
        expect(m.frozenRequest, isNot(same(previousRequest)));
        expect(m.attemptPort, observed ? ' next explicit ' : ' exact ');
        if (observed) {
          expect(m.attempt!.attemptId, 2);
        } else {
          expect(m.attempt, same(previousResult));
        }
        m.content.text = 'third';
        expect(m.canStart, false);
        expect(
          (m.frozenRequest as PingParameterRequest).content,
          'second'.codeUnits,
        );
        expect(m.actionFailure!.host, CoordinationFault.requestUnknown);
      },
    );
  }
  testWidgets(
    'real mouse pointer-down preserves marked content before Start and menus',
    (tester) async {
      select();
      m.mode = ContentMode.text;
      final profiles = ProfilesEditor(r, invalidatePreview: () {});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticsView(
              model: m,
              profiles: profiles,
              chooseDevice: () {},
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('diagnostic-content'));
      await tester.tap(field);
      await tester.pump();
      const editing = TextEditingValue(
        text: 'zhongwen',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 0, end: 8),
      );
      tester.testTextInput.updateEditingValue(editing);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      for (final target in [
        find.text('Start and record'),
        find.byKey(const ValueKey('diagnostic-operation')),
        find.byKey(const ValueKey('diagnostic-profile')),
        find.byKey(const ValueKey('diagnostic-content-mode')),
      ]) {
        await tester.tap(target, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(m.content.value, editing);
        expect(editable.focusNode.hasFocus, true);
        expect(find.byType(PopupMenuItem<Object>), findsNothing);
      }
      expect(r.diagnosticStarts, 0);
      expect(r.enumerations, 0);
      await tester.pumpWidget(const SizedBox());
      profiles.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  for (final operation in [
    DiagnosticOperation.ping,
    DiagnosticOperation.respond,
  ]) {
    testWidgets(
      'override collapse defers live composition before rebuild: ${operation.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final runtime = DraftRuntime();
        final quit = DraftQuitCoordinator(runtime);
        final model = quit.diagnostics;
        model.changeOperation(operation);
        model.form.explicit.add(ParameterField.requestTimeoutSeconds);
        final controller =
            model.form.inputs[ParameterField.requestTimeoutSeconds]!;
        controller.text = '5';
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          quit.disposeEditors();
          await runtime.states.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DiagnosticsView(
                model: model,
                profiles: quit.profiles,
                chooseDevice: () {},
              ),
            ),
          ),
        );
        final header = find.text('Invocation field overrides');
        final field = find.byKey(
          const ValueKey('diagnostic-requestTimeoutSeconds'),
        );
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await tester.tap(field, kind: PointerDeviceKind.mouse);
        await tester.pump();
        final element = tester.element(field);
        final editable = tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        const editing = TextEditingValue(
          text: '51',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        );
        tester.testTextInput.updateEditingValue(editing);
        final before = controller.value;
        // Do not pump: the header must read live composition, not a build-time
        // enabled value from before this input-method update.
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(tester.element(field), same(element));
        expect(controller.value, same(before));
        expect(editable.focusNode.hasFocus, true);
        expect(model.composing, true);
        expect(
          find.text('Finish composing text before changing this choice.'),
          findsOneWidget,
        );
        Future<Never> noPrompt({required bool unknown}) async =>
            throw StateError('No leave prompt expected');
        expect(await quit.leaveCurrent(noPrompt), false);
        expect(await quit.requestQuit(), false);
        expect(runtime.begins, 0);
        expect(runtime.shutdowns, 0);

        // Exercise both committing and canceling marked input before collapse.
        final resolved = operation == DiagnosticOperation.ping ? '51' : '5';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: resolved,
            selection: TextSelection.collapsed(offset: resolved.length),
          ),
        );
        await tester.pumpAndSettle();
        expect(model.composing, false);
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(field, findsNothing);
        expect(controller.text, resolved);
        expect(model.composing, false);
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(controller.text, resolved);
        expect(await quit.leaveCurrent(noPrompt), true);
        expect(await quit.requestQuit(), true);
        expect(runtime.shutdowns, 1);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  testWidgets(
    'nullable PING and zero responder render distinct facts without invented RTT',
    (tester) async {
      const ping = PingSummary(
        reason: LogicalReason.sendFailed,
        matchingPongObserved: true,
        exactContentValidated: true,
        roundTripSucceeded: false,
        firstMatchingPongElapsedUs: 123,
        matchingPongDuplicates: 0,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiagnosticOutcomes(
                value: OperationSnapshot(generation: 1, summary: ping),
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Successful application RTT (µs): Not observed'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Matching PONG duplicates: 0'),
        findsOneWidget,
      );
      expect(
        logicalFacts(
          const RespondSummary(
            reason: LogicalReason.completed,
            responseAttempts: 0,
          ),
        ).toString(),
        contains('(Response attempts, 0)'),
      );
    },
  );
}
