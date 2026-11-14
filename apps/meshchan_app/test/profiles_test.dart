import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show PointerDeviceKind;

import 'package:meshchan_app/runtime/worker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/app.dart';
import 'package:meshchan_app/drafts/editor.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/profiles/editor.dart';
import 'package:meshchan_app/profiles/view.dart';
import 'package:meshchan_app/profiles/parameter_form.dart';
import 'package:meshchan_app/profiles/preview.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../tool/profile_fixture.dart';

class ProfileRuntime implements AppRuntime {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
  @override
  RuntimeSnapshot snapshot = const RuntimeSnapshot(
    generation: 1,
    phase: RuntimePhase.ready,
  );
  @override
  Stream<RuntimeSnapshot> get changes => const Stream.empty();
  final writes = <ProfileContent>[];
  final requests = <EffectiveParameterRequest>[];
  final records = <String, ConnectionProfile>{};
  AppSettings settings = AppSettings();
  Future<ConnectionProfile> Function(ProfileContent, String?)? onSave;
  Future<EffectiveParameters> Function(EffectiveParameterRequest)? onResolve;
  int begins = 0, shutdowns = 0;
  @override
  Future<void> start() async {}
  @override
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after}) async =>
      DraftPage([], null);
  @override
  Future<ProfilePage> listProfiles({
    int size = 20,
    UpdatedCursor? after,
  }) async => ProfilePage(records.values, null);
  @override
  Future<ConnectionProfile> readProfile(String id) async => records[id]!;
  @override
  Future<ConnectionProfile> saveProfile(
    ProfileContent content, {
    String? id,
    required int session,
    DraftDecision? decision,
  }) async {
    writes.add(content);
    if (onSave != null) return onSave!(content, id);
    final p = ConnectionProfile(
      id: LocalId(id ?? writes.length.toRadixString(16).padLeft(32, '0')),
      content: content,
      updatedAt: DateTime.utc(2026),
    );
    records[p.id.value] = p;
    return p;
  }

  @override
  Future<AppSettings> readSettings() async => settings;
  @override
  Future<AppSettings> saveSettings(
    AppSettings value, {
    DraftDecision? decision,
  }) async => settings = value;
  @override
  Future<AppSettings> restoreSettings() async => settings = AppSettings();
  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest value,
  ) async {
    requests.add(value);
    return onResolve!(value);
  }

  @override
  Future<DraftDecision> beginDraftDecision(
    int documentGeneration, {
    EditorTarget target = EditorTarget.draft,
    String? targetId,
  }) async {
    begins++;
    return DraftDecision(
      begins,
      documentGeneration,
      target: target,
      targetId: targetId,
    );
  }

  @override
  Future<void> endDraftDecision(DraftDecision d) async {}
  @override
  Future<ShutdownOutcome> shutdown() async {
    shutdowns++;
    return const ShutdownOutcome(true, true);
  }
}

class SettingsFaultRuntime extends ProfileRuntime {
  int saves = 0, restores = 0;
  bool badRead = true, loseSave = false, loseRestore = false;
  @override
  Future<AppSettings> readSettings() async {
    if (badRead) throw const RuntimeFault(core: CoreErrorCode.notFound);
    return settings;
  }

  @override
  Future<AppSettings> saveSettings(
    AppSettings value, {
    DraftDecision? decision,
  }) async {
    saves++;
    if (loseSave) {
      throw const RuntimeFault(host: CoordinationFault.requestUnknown);
    }
    settings = value;
    snapshot = const RuntimeSnapshot(
      generation: 1,
      phase: RuntimePhase.ready,
      maintenance: MaintenanceSnapshot(
        HistoryMaintenanceState.failed,
        CoreErrorCode.storageWriteFailed,
        1,
      ),
    );
    return value;
  }

  @override
  Future<AppSettings> restoreSettings() async {
    restores++;
    if (loseRestore) {
      throw const RuntimeFault(host: CoordinationFault.requestUnknown);
    }
    return settings = AppSettings();
  }
}

Future<LeaveChoice> discard({required bool unknown}) async =>
    LeaveChoice.discard;
void fill(ProfilesEditor e, DiagnosticOperation op) {
  e.form.load(fixtureProfile(op).parameters);
  e.name.text = fixtureProfile(op).name;
  e.hintEnabled = true;
  e.hint.text = fixtureProfile(op).portHint!;
}

void main() {
  for (final op in DiagnosticOperation.values) {
    test(
      '$op all fields round trip, exact text, no-op time and type replacement',
      () async {
        final r = ProfileRuntime(),
            e = ProfilesEditor(ProfileRuntime(), invalidatePreview: () {});
        e.dispose();
        final editor = ProfilesEditor(r, invalidatePreview: () {});
        addTearDown(editor.dispose);
        await editor.newProfile(discard);
        fill(editor, op);
        final signature = editor.form.signature;
        expect(await editor.save(), true);
        final saved = editor.baseline!;
        expect(saved.name, '  中文🙂\n');
        expect(saved.portHint, 'fixture hint\n');
        expect(saved.operation, op);
        final restored = ParameterForm(op)..load(saved.parameters);
        addTearDown(restored.dispose);
        expect(restored.signature, signature);
        editor.name.text = 'changed';
        expect(await editor.save(), true);
        expect(editor.baseline!.updatedAt, saved.updatedAt);
        expect(editor.baseline!.id, saved.id);
        editor.changeType(
          op == DiagnosticOperation.send
              ? DiagnosticOperation.listen
              : DiagnosticOperation.send,
        );
        expect(
          editor.form.inputs[ParameterField.taskTimeoutSeconds]!.text,
          '7',
        );
        expect(editor.form.inputs[ParameterField.sendChannelIndex]!.text, '');
      },
    );
  }
  test(
    'A commits while B stays dirty and repeated Save coalesces create',
    () async {
      final r = ProfileRuntime(), done = Completer<ConnectionProfile>();
      r.onSave = (_, _) => done.future;
      final e = ProfilesEditor(r, invalidatePreview: () {});
      addTearDown(e.dispose);
      await e.newProfile(discard);
      fill(e, DiagnosticOperation.send);
      final a = e.save(), b = e.save();
      e.name.text = 'B';
      done.complete(
        ConnectionProfile(
          id: LocalId('a' * 32),
          content: r.writes.single,
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(await a, true);
      expect(await b, true);
      expect(r.writes.length, 1);
      expect(e.name.text, 'B');
      expect(e.dirty, true);
      expect(e.baseline!.name, '  中文🙂\n');
    },
  );
  test(
    'invalid numeric/raw invalid_input remains dirty with original text',
    () async {
      final r = ProfileRuntime();
      final editor = ProfilesEditor(r, invalidatePreview: () {});
      addTearDown(editor.dispose);
      await editor.newProfile(discard);
      fill(editor, DiagnosticOperation.send);
      editor.form.inputs[ParameterField.sendChannelIndex]!.text = '0x';
      expect(await editor.save(), false);
      expect(editor.dirty, true);
      expect(r.writes, isEmpty);
      editor.form.inputs[ParameterField.sendChannelIndex]!.text = '0';
      r.onSave = (_, _) =>
          Future.error(const RuntimeFault(core: CoreErrorCode.invalidInput));
      expect(await editor.save(), false);
      expect(editor.name.text, '  中文🙂\n');
      expect(editor.unknown, false);
    },
  );
  test(
    'settings full replacement preserves other field; restore both',
    () async {
      final r = ProfileRuntime()
        ..settings = AppSettings(
          defaultProfileId: LocalId('b' * 32),
          diagnosticHistoryLimit: 2345,
        );
      final e = ProfilesEditor(r, invalidatePreview: () {});
      addTearDown(e.dispose);
      await e.openSettings(discard);
      e.history.text = '4';
      expect(await e.save(), true);
      expect(r.settings.defaultProfileId!.value, 'b' * 32);
      e.defaultId.text = '';
      expect(await e.save(), true);
      expect(r.settings.diagnosticHistoryLimit, 4);
      expect(await e.restore(), true);
      expect(e.defaultId.text, '');
      expect(e.history.text, '1000');
    },
  );
  test('presence absent vs zero vs empty path and Listen three states', () {
    final f = ParameterForm(DiagnosticOperation.send, overrides: true);
    addTearDown(f.dispose);
    f.inputs[ParameterField.sendChannelIndex]!.text = '0';
    expect(
      (f.request() as SendParameterRequest).overrides.sendChannelIndex,
      null,
    );
    f.explicit.add(ParameterField.sendChannelIndex);
    expect((f.request() as SendParameterRequest).overrides.sendChannelIndex, 0);
    expect((f.request() as SendParameterRequest).overrides.route!.path, null);
    f.explicit.add(ParameterField.path);
    expect(
      (f.request() as SendParameterRequest).overrides.route!.path,
      isEmpty,
    );
    f.explicit.remove(ParameterField.sendChannelIndex);
    expect(
      (f.request() as SendParameterRequest).overrides.sendChannelIndex,
      null,
    );
    f.changeType(DiagnosticOperation.listen);
    expect((f.request() as ListenParameterRequest).overrides.dataType, null);
    f.explicit.add(ParameterField.dataType);
    expect(
      (f.request() as ListenParameterRequest).overrides.dataType!.value,
      null,
    );
    f.listenAll = false;
    f.inputs[ParameterField.dataType]!.text = '0';
    expect(
      (f.request() as ListenParameterRequest).overrides.dataType!.value,
      0,
    );
  });
  test('content absent/empty/UTF8/opaque hex; strict lexical rejection', () {
    final p = ParameterPreview(ProfileRuntime());
    addTearDown(p.dispose);
    expect(p.bytes, null);
    p.mode = ContentMode.text;
    expect(p.bytes, isEmpty);
    p.content.text = '中🙂';
    expect(p.bytes!.length, 7);
    p.mode = ContentMode.hex;
    p.content.text = '00ff80';
    expect(p.bytes, [0, 255, 128]);
    for (final text in ['0', 'gg', '0xff', 'aa bb', 'é0']) {
      expect(() => parseHex(text), throwsFormatException);
    }
    for (final text in ['', '-1', ' 0', '0x', '1.0']) {
      expect(() => parseNumber(text, protocol: true), throwsFormatException);
    }
    expect(parseNumber('0Xff', protocol: true), 255);
    expect(() => parseNumber('0xff'), throwsFormatException);
  });
  test(
    'explicit request maps ID without default read and late preview is stale',
    () async {
      final r = ProfileRuntime(), done = Completer<EffectiveParameters>();
      r.onResolve = (_) => done.future;
      final p = ParameterPreview(r);
      addTearDown(p.dispose);
      p.profileId = 'a' * 32;
      p.mode = ContentMode.text;
      final resolving = p.preview();
      expect(r.requests.single.profileId!.value, 'a' * 32);
      p.content.text = 'new';
      done.complete(
        EffectiveParameters(
          profileId: LocalId('a' * 32),
          parameters: fixtureProfile(DiagnosticOperation.send).parameters,
          content: [],
        ),
      );
      await resolving;
      expect(p.result, null);
      p.storageChanged();
      expect(p.result, null);
    },
  );
  test('pending to unknown asks a second explicit discard decision', () async {
    final r = ProfileRuntime(), done = Completer<ConnectionProfile>();
    r.onSave = (_, _) => done.future;
    final e = ProfilesEditor(r, invalidatePreview: () {});
    addTearDown(e.dispose);
    await e.newProfile(discard);
    fill(e, DiagnosticOperation.send);
    final save = e.save(), answer = Completer<LeaveChoice>();
    final shown = <bool>[];
    final leaving = e.leave(({required unknown}) {
      shown.add(unknown);
      return shown.length == 1
          ? answer.future
          : Future.value(LeaveChoice.continueEditing);
    });
    done.completeError(
      const RuntimeFault(host: CoordinationFault.requestUnknown),
    );
    await save;
    answer.complete(LeaveChoice.discard);
    expect(await leaving, false);
    expect(shown, [false, true]);
    expect(e.unknown, true);
    expect(await e.save(), false);
    expect(r.writes.length, 1);
  });
  test(
    'quit during create A waits and final-updates B using the confirmed ID',
    () async {
      final r = ProfileRuntime(), created = Completer<ConnectionProfile>();
      final ids = <String?>[];
      r.onSave = (content, id) {
        ids.add(id);
        return ids.length == 1
            ? created.future
            : Future.value(
                ConnectionProfile(
                  id: LocalId(id!),
                  content: content,
                  updatedAt: DateTime.utc(2026),
                ),
              );
      };
      final q = DraftQuitCoordinator(r)..auxiliaryActive = true;
      addTearDown(q.disposeEditors);
      await q.profiles.newProfile(discard);
      fill(q.profiles, DiagnosticOperation.send);
      final saving = q.profiles.save();
      q.profiles.name.text = 'B';
      q.prompt = ({required unknown}) async => LeaveChoice.save;
      final exiting = q.requestQuit();
      await Future<void>.delayed(Duration.zero);
      expect(r.shutdowns, 0);
      created.complete(
        ConnectionProfile(
          id: LocalId('c' * 32),
          content: r.writes.first,
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(await saving, true);
      expect(await exiting, true);
      expect(ids, [null, 'c' * 32]);
      expect(r.writes.last.name, 'B');
      expect(r.shutdowns, 1);
    },
  );
  test(
    'concurrent quit coalesces one decision, one final Save, one shutdown',
    () async {
      final r = ProfileRuntime(), q = DraftQuitCoordinator(ProfileRuntime());
      q.disposeEditors();
      final quit = DraftQuitCoordinator(r)..auxiliaryActive = true;
      addTearDown(quit.disposeEditors);
      await quit.profiles.newProfile(discard);
      fill(quit.profiles, DiagnosticOperation.send);
      final choice = Completer<LeaveChoice>();
      quit.prompt = ({required unknown}) => choice.future;
      final a = quit.requestQuit(), b = quit.requestQuit();
      await Future<void>.delayed(Duration.zero);
      expect(r.begins, 1);
      choice.complete(LeaveChoice.save);
      expect(await a, true);
      expect(await b, true);
      expect(r.shutdowns, 1);
      expect(r.writes.length, 1);
    },
  );
  test('real worker explicit/default mismatch and host/worker final Save isolation', () async {
    final dir = await Directory.systemTemp.createTemp('meshchan-profile-test-');
    addTearDown(() => dir.delete(recursive: true));
    final r = RuntimeController(resolveDirectory: () async => dir.path);
    await r.start();
    addTearDown(r.shutdown);
    final a = await r.saveProfile(
          fixtureProfile(DiagnosticOperation.send),
          session: 10,
        ),
        b = await r.saveProfile(
          fixtureProfile(DiagnosticOperation.listen),
          session: 11,
        );
    await r.saveSettings(AppSettings(defaultProfileId: b.id));
    expect(
      (await r.resolveParameters(
        SendParameterRequest(profileId: a.id, payload: []),
      )).profileId,
      a.id,
    );
    for (final request in [
      SendParameterRequest(payload: []),
      SendParameterRequest(profileId: a.id),
      RespondParameterRequest(profileId: a.id),
    ]) {
      await expectLater(
        r.resolveParameters(request),
        throwsA(isA<RuntimeFault>()),
      );
    }
    final permit = await r.beginDraftDecision(
      10,
      target: EditorTarget.profile,
      targetId: a.id.value,
    );
    final calls = <Future<Object?> Function()>[
      () => r.listProfiles(),
      () => r.readSettings(),
      () => r.resolveParameters(SendParameterRequest(payload: [])),
      () => r.saveProfile(
        a.content,
        id: b.id.value,
        session: 10,
        decision: permit,
      ),
      () => r.saveProfile(
        a.content,
        id: a.id.value,
        session: 11,
        decision: permit,
      ),
      () => r.saveSettings(AppSettings(), decision: permit),
      () => r.saveDraft(title: '', body: '', decision: permit),
    ];
    for (final call in calls) {
      await expectLater(call(), throwsA(isA<RuntimeFault>()));
    }
    expect(r.pendingCount, 0);
    await r.saveProfile(
      a.content,
      id: a.id.value,
      session: 10,
      decision: permit,
    );
    await expectLater(
      r.saveProfile(a.content, id: a.id.value, session: 10, decision: permit),
      throwsA(isA<RuntimeFault>()),
    );
    await r.endDraftDecision(permit);
    expect((await r.shutdown()).canExit, true);
  });

  for (final field in ['name', 'hint', 'number', 'settings']) {
    test(
      'live $field composition defers save, type, departure and quit before pause',
      () async {
        final r = ProfileRuntime(), q = DraftQuitCoordinator(ProfileRuntime());
        q.disposeEditors();
        final quit = DraftQuitCoordinator(r)..auxiliaryActive = true;
        addTearDown(quit.disposeEditors);
        final e = quit.profiles;
        if (field == 'settings') {
          await e.openSettings(discard);
        } else {
          await e.newProfile(discard);
          fill(e, DiagnosticOperation.send);
        }
        final c = switch (field) {
          'name' => e.name,
          'hint' => e.hint,
          'number' => e.form.inputs[ParameterField.sendChannelIndex]!,
          _ => e.history,
        };
        const marked = TextEditingValue(
          text: '123',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        );
        c.value = marked;
        var prompts = 0;
        quit.prompt = ({required unknown}) async {
          prompts++;
          return LeaveChoice.discard;
        };
        expect(await e.save(), false);
        expect(await e.leave(quit.prompt!), false);
        expect(await quit.requestQuit(), false);
        e.changeType(DiagnosticOperation.listen);
        expect(e.form.operation, DiagnosticOperation.send);
        expect(c.value, marked);
        expect(prompts, 0);
        expect(r.begins, 0);
        expect(r.writes, isEmpty);
      },
    );
  }
  test('new fields use only program defaults and strict lexing rejects final newline', () {
    final f = ParameterForm(DiagnosticOperation.ping);
    addTearDown(f.dispose);
    for (final field in [
      ParameterField.taskTimeoutSeconds,
      ParameterField.sendChannelIndex,
      ParameterField.receiveChannelIndex,
      ParameterField.routeDescriptor,
      ParameterField.localTestId,
      ParameterField.peerTestId,
      ParameterField.responseTimeoutSeconds,
    ]) {
      expect(f.inputs[field]!.text, '');
    }
    expect(() => parseNumber('1\n'), throwsFormatException);
    expect(() => parseHex('aa\n'), throwsFormatException);
    expect(() => textBytes(String.fromCharCode(0xd800)), throwsFormatException);
  });

  test(
    'worker independently rejects paused reads and cross-target/session saves',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'meshchan-worker-permit-',
      );
      final port = ReceivePort();
      final ready = Completer<void>();
      final replies = <int, Completer<RequestReply>>{};
      final released = Completer<void>();
      final w = WorkerDispatcher(
        WorkerBootstrap(1, dir.path, port.sendPort),
        send: (event) {
          if (event is SnapshotEvent &&
              event.snapshot.phase == RuntimePhase.ready &&
              !ready.isCompleted) {
            ready.complete();
          }
          if (event is RequestReply) replies.remove(event.id)!.complete(event);
          if (event is ReleaseReport) released.complete();
        },
        finish: () {},
      );
      var id = 0;
      Future<RequestReply> call(RuntimeRequest request) {
        final n = ++id, c = Completer<RequestReply>();
        replies[n] = c;
        w.receive(RequestEnvelope(1, n, request));
        return c.future;
      }

      w.start();
      await ready.future;
      final created =
          (await call(
                WriteProfile(
                  fixtureProfile(DiagnosticOperation.send),
                  session: 8,
                ),
              )).value
              as ProfileValue;
      final token = DraftDecision(
        1,
        8,
        target: EditorTarget.profile,
        targetId: created.profile.id.value,
      );
      await call(BeginDraftDecision(token));
      for (final request in <RuntimeRequest>[
        const ListProfiles(),
        const ReadSettings(),
        const RestoreSettings(),
        ResolveParameters(SendParameterRequest(payload: [])),
        WriteSettings(AppSettings(), decision: token),
        WriteProfile(
          created.profile.content,
          id: 'f' * 32,
          session: 8,
          decision: token,
        ),
        WriteProfile(
          created.profile.content,
          id: created.profile.id.value,
          session: 9,
          decision: token,
        ),
      ]) {
        expect((await call(request)).error, isNotNull);
      }
      expect(
        (await call(
          WriteProfile(
            created.profile.content,
            id: created.profile.id.value,
            session: 8,
            decision: token,
          ),
        )).value,
        isA<ProfileValue>(),
      );
      expect(
        (await call(
          WriteProfile(
            created.profile.content,
            id: created.profile.id.value,
            session: 8,
            decision: token,
          ),
        )).error,
        isNotNull,
      );
      w.receive(RequestEnvelope(1, ++id, const ShutdownRuntime()));
      await released.future;
      port.close();
      await dir.delete(recursive: true);
    },
  );

  test('failed settings read permits explicit complete recovery and independent maintenance failure', () async {
    final r = SettingsFaultRuntime(),
        e = ProfilesEditor(SettingsFaultRuntime(), invalidatePreview: () {});
    e.dispose();
    final editor = ProfilesEditor(r, invalidatePreview: () {});
    addTearDown(editor.dispose);
    expect(await editor.openSettings(discard), true);
    expect(editor.readError, 'not_found');
    expect(editor.history.text, '');
    editor.history.text = '42';
    expect(await editor.save(), true);
    expect(editor.settings!.diagnosticHistoryLimit, 42);
    expect(editor.readError, null);
    expect(editor.error, null);
    expect(r.snapshot.maintenance!.failureCount, 1);
    expect(r.saves, 1);
    expect(await editor.restore(), true);
    expect(editor.history.text, '1000');
  });
  for (final restoring in [false, true]) {
    test(
      'settings ${restoring ? 'restore' : 'save'} unknown freezes retries and keeps buffer',
      () async {
        final r = SettingsFaultRuntime()
          ..badRead = false
          ..loseSave = !restoring
          ..loseRestore = restoring;
        final e = ProfilesEditor(r, invalidatePreview: () {});
        addTearDown(e.dispose);
        await e.openSettings(discard);
        e.history.text = '321';
        expect(await (restoring ? e.restore() : e.save()), false);
        expect(e.unknown, true);
        expect(e.history.text, '321');
        expect(await e.save(), false);
        expect(await e.restore(), false);
        expect(r.saves + r.restores, 1);
      },
    );
  }

  for (final selector in [
    'profile type',
    'settings default',
    'preview operation',
    'preview profile',
    'content mode',
  ]) {
    testWidgets('live composition blocks $selector before its menu opens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = ProfileRuntime(),
          preview = ParameterPreview(ProfileRuntime());
      final editor = ProfilesEditor(runtime, invalidatePreview: () {});
      addTearDown(editor.dispose);
      addTearDown(preview.dispose);
      if (selector == 'settings default') {
        await editor.openSettings(discard);
      } else if (selector == 'profile type') {
        await editor.newProfile(discard);
        fill(editor, DiagnosticOperation.send);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfilesView(
              editor: editor,
              preview: preview,
              prompt: discard,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder input;
      Finder choice;
      if (selector == 'profile type') {
        input = find.byKey(const ValueKey('profile-name'));
        choice = find.text('send').last;
      } else if (selector == 'settings default') {
        input = find.byKey(const ValueKey('history-limit'));
        choice = find.text('No default (clear selection)').last;
      } else {
        await tester.tap(find.text('Offline preview'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Not provided'));
        await tester.tap(find.text('Not provided'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Text (UTF-8)').last);
        await tester.pumpAndSettle();
        input = find.byKey(const ValueKey('invocation-content'));
        choice = selector == 'preview operation'
            ? find.text('send').last
            : selector == 'preview profile'
            ? find.text('Use settings default (may be no preset)').last
            : find.text('Text (UTF-8)').last;
      }
      await tester.ensureVisible(input);
      await tester.tap(input);
      await tester.pump();
      const marked = TextEditingValue(
        text: 'zhongwen',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 0, end: 8),
      );
      tester.testTextInput.updateEditingValue(marked);
      await tester.pump();
      await tester.ensureVisible(choice);
      await tester.tap(choice, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.textContaining('Finish composing'), findsOneWidget);
      final current = selector == 'profile type'
          ? editor.name.value
          : selector == 'settings default'
          ? editor.history.value
          : preview.content.value;
      expect(current, marked);
      expect(runtime.writes, isEmpty);
      expect(editor.form.operation, DiagnosticOperation.send);
      expect(preview.form.operation, DiagnosticOperation.send);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
  for (final operation in DiagnosticOperation.values) {
    testWidgets(
      'real controls save every $operation field and isolate New Undo',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final r = ProfileRuntime(), p = ParameterPreview(ProfileRuntime());
        addTearDown(p.dispose);
        final e = ProfilesEditor(r, invalidatePreview: () {});
        addTearDown(e.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfilesView(editor: e, preview: p, prompt: discard),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('New preset'));
        await tester.pumpAndSettle();
        if (operation != DiagnosticOperation.send) {
          final dropdown = find.byKey(
            const ValueKey('profile-operation-choice'),
          );
          await tester.ensureVisible(dropdown);
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(operation.name).last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();
        }
        final name = find.byKey(const ValueKey('profile-name'));
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Same name');
        final values = e.form.values(fixtureProfile(operation).parameters);
        if (operation == DiagnosticOperation.listen) {
          final all = find.text('Receive all data types');
          await tester.ensureVisible(all);
          await tester.tap(all);
          await tester.pumpAndSettle();
        }
        for (final entry in values.entries) {
          final field = find.byKey(ValueKey('field-${entry.key.name}'));
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
        }
        final save = find.text('Save preset');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(r.writes.length, 1);
        final expected = ParameterForm(operation)
          ..load(fixtureProfile(operation).parameters);
        addTearDown(expected.dispose);
        expect(e.form.signature, expected.signature);
        expect(e.dirty, false);
        await tester.ensureVisible(name);
        await tester.enterText(name, 'document A');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('New preset'));
        await tester.pumpAndSettle();
        final fresh = find.byKey(const ValueKey('profile-name'));
        await tester.ensureVisible(fresh);
        await tester.tap(fresh);
        await tester.pump(const Duration(seconds: 1));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(e.name.text, '');
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  testWidgets(
    'buttons, scoped Command+S, composition, dirty Settings navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = ProfileRuntime(), quit = DraftQuitCoordinator(ProfileRuntime());
      quit.disposeEditors();
      final q = DraftQuitCoordinator(r);
      addTearDown(q.disposeEditors);
      await tester.pumpWidget(
        MeshchanApp(runtime: r, quitCoordinator: q, probe: (_) async => {}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profiles and settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New preset'));
      await tester.pumpAndSettle();
      fill(q.profiles, DiagnosticOperation.send);
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('profile-name'));
      await tester.ensureVisible(name);
      await tester.tap(name);
      await tester.pump();
      const composing = TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      await tester.ensureVisible(find.text('Save preset'));
      await tester.pump();
      await tester.tap(find.text('Save preset'));
      await tester.pump();
      expect(r.writes, isEmpty);
      expect(q.profiles.name.value.composing, composing.composing);
      expect(await q.requestQuit(), false);
      expect(r.begins, 0);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '中文',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(r.writes.length, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(name, 'newer');
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(q.profiles.name.text, '中文');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(q.profiles.name.text, 'newer');
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      expect(find.text('Leave this editor?'), findsOneWidget);
      await tester.tap(find.text('Continue editing'));
      await tester.pumpAndSettle();
      expect(q.profiles.name.text, 'newer');
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      final history = find.byKey(const ValueKey('history-limit'));
      await tester.enterText(history, '123');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(r.settings.diagnosticHistoryLimit, 123);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
