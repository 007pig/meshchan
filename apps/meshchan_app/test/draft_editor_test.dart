import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/drafts/editor.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'support/draft_runtime.dart';

Future<LeaveChoice> discard({required bool unknown}) async =>
    LeaveChoice.discard;
Future<LeaveChoice> save({required bool unknown}) async => LeaveChoice.save;
Future<LeaveChoice> stay({required bool unknown}) async =>
    LeaveChoice.continueEditing;

void main() {
  late DraftRuntime runtime;
  late DraftEditor editor;
  setUp(() {
    runtime = DraftRuntime();
    editor = DraftEditor(runtime);
  });
  tearDown(() async {
    editor.dispose();
    await runtime.states.close();
  });

  test(
    'New is local, empty explicit create binds identity, undo restores clean',
    () async {
      await editor.newDraft(discard);
      expect(runtime.writes, isEmpty);
      expect(editor.dirty, false);
      expect(editor.status, 'Not saved yet');
      expect(await editor.save(), true);
      expect(editor.baseline!.revision, 1);
      expect(editor.status, 'Saved');
      editor.body.text = 'changed';
      editor.body.text = '';
      expect(editor.dirty, false);
      editor.body.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(editor.dirty, false);
    },
  );

  for (final initial in [true, false]) {
    test('A/B save, coalescing and next revision (create=$initial)', () async {
      runtime.records['one'] = draft('one', revision: 7);
      if (initial) {
        await editor.newDraft(discard);
      } else {
        await editor.select('one', discard);
      }
      final pending = Completer<DraftSnapshot>();
      runtime.onSave = (_) => pending.future;
      editor.body.text = 'A';
      final first = editor.save();
      expect(identical(first, editor.save()), true);
      editor.body.value = const TextEditingValue(
        text: 'B中文🙂',
        selection: TextSelection(baseOffset: 1, extentOffset: 2),
        composing: TextRange(start: 1, end: 3),
      );
      final value = editor.body.value;
      pending.complete(draft('one', revision: initial ? 1 : 8, body: 'A'));
      expect(await first, true);
      expect(editor.body.value, value);
      expect(editor.dirty, true);
      expect(runtime.writes.length, 1);
      expect(editor.baseline!.body, 'A');
      editor.body.value = value.copyWith(composing: TextRange.empty);
      runtime.onSave = null;
      expect(await editor.save(), true);
      expect(runtime.writes.last.id, 'one');
      expect(runtime.writes.last.expectedRevision, initial ? 1 : 8);
      expect(editor.status, 'Saved');
    });
  }
  test(
    'generation changes do not prevent exact clean after A commits',
    () async {
      await editor.newDraft(discard);
      final pending = Completer<DraftSnapshot>();
      runtime.onSave = (_) => pending.future;
      editor.body.text = 'A';
      final saving = editor.save();
      editor.body.text = 'B';
      editor.body.text = 'A';
      pending.complete(draft('one', body: 'A'));
      await saving;
      expect(editor.dirty, false);
    },
  );
  for (final code in [
    CoreErrorCode.conflict,
    CoreErrorCode.notFound,
    CoreErrorCode.invalidInput,
    CoreErrorCode.storageWriteFailed,
  ]) {
    test(
      '$code preserves buffer and confirmed baseline; retry success clears request error',
      () async {
        runtime.records['one'] = draft('one', revision: 3);
        await editor.select('one', discard);
        editor.body.text = 'local';
        final baseline = editor.baseline;
        runtime.onSave = (_) => Future.error(RuntimeFault(core: code));
        expect(await editor.save(), false);
        expect(editor.body.text, 'local');
        expect(identical(editor.baseline, baseline), true);
        expect(editor.error!.core, code);
        expect(editor.unknown, false);
        runtime.onSave = null;
        expect(await editor.save(), true);
        expect(editor.error, null);
      },
    );
  }
  test(
    'composition blocks all Save paths without resetting selection',
    () async {
      await editor.newDraft(discard);
      editor.body.value = const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      final value = editor.body.value;
      expect(await editor.save(), false);
      expect(await editor.leave(save), false);
      expect(runtime.writes, isEmpty);
      expect(editor.body.value, value);
    },
  );
  test(
    'mutation commit survives list failure; refresh leaves dirty buffer alone',
    () async {
      await editor.newDraft(discard);
      runtime.onList = (_) => Future.error(
        const RuntimeFault(core: CoreErrorCode.storageReadFailed),
      );
      editor.body.text = 'saved';
      await editor.save();
      await editor.refresh();
      expect(editor.status, 'Saved');
      expect(editor.listError!.core, CoreErrorCode.storageReadFailed);
      editor.body.text = 'new';
      await editor.refresh();
      expect(editor.body.text, 'new');
    },
  );
  test(
    'late selection A cannot replace B; old list/page cannot replace refresh',
    () async {
      final a = Completer<DraftSnapshot>(), b = Completer<DraftSnapshot>();
      runtime.onRead = (id) => id == 'a' ? a.future : b.future;
      final first = editor.select('a', discard),
          second = editor.select('b', discard);
      await Future<void>.value();
      b.complete(draft('b', body: 'B'));
      await second;
      a.complete(draft('a', body: 'A'));
      await first;
      expect(editor.baseline!.id, 'b');
      final old = Completer<DraftPage>();
      runtime.onList = (_) => old.future;
      final refreshing = editor.refresh();
      runtime.onList = (_) async => DraftPage([draft('new')], null);
      await editor.refresh();
      old.complete(
        DraftPage([draft('old')], DraftCursor(DateTime.utc(2026), 'old')),
      );
      await refreshing;
      expect(editor.items.single.id, 'new');
      expect(editor.nextCursor, null);
    },
  );
  test(
    'conflict inspection does not adopt revision; explicit Reload does',
    () async {
      runtime.records['one'] = draft('one', revision: 1);
      await editor.select('one', discard);
      editor.body.text = 'local';
      runtime.records['one'] = draft('one', revision: 9, body: 'remote');
      await editor.inspectStored();
      expect(editor.baseline!.revision, 1);
      expect(editor.body.text, 'local');
      editor.reloadInspected();
      expect(editor.baseline!.revision, 9);
      expect(editor.body.text, 'remote');
    },
  );
  for (final kind in ['create', 'update', 'delete']) {
    test(
      '$kind unknown never retries and allows only acknowledged local discard',
      () async {
        if (kind != 'create') {
          runtime.records['one'] = draft('one');
          await editor.select('one', discard);
        } else {
          await editor.newDraft(discard);
        }
        const error = RuntimeFault(host: CoordinationFault.requestUnknown);
        runtime.onSave = (_) => Future.error(error);
        runtime.onDelete = (_, _) => Future.error(error);
        editor.body.text = 'local';
        expect(
          await (kind == 'delete' ? editor.delete() : editor.save()),
          false,
        );
        expect(editor.unknown, true);
        expect(editor.body.text, 'local');
        expect(await editor.save(), false);
        expect(await editor.leave(save), false);
        var warned = false;
        expect(
          await editor.leave(({required unknown}) async {
            warned = unknown;
            return LeaveChoice.discard;
          }),
          true,
        );
        expect(warned, true);
        expect(editor.status, 'Save/delete result unknown');
        expect(await editor.save(), false);
        expect(editor.unknownNotice, isNotNull);
        expect(runtime.writes.length + runtime.deletes.length, 1);
      },
    );
  }
  test(
    'delete serializes, locks editing/selection, removes only after commit',
    () async {
      runtime.records['one'] = draft('one', revision: 5);
      await editor.select('one', discard);
      final pending = Completer<String>();
      runtime.onDelete = (_, _) => pending.future;
      final deleting = editor.delete();
      expect(await editor.delete(), false);
      expect(await editor.newDraft(discard), false);
      expect(editor.hasDocument, true);
      expect(editor.deleting, true);
      expect(runtime.deletes.single.expectedRevision, 5);
      pending.complete('one');
      expect(await deleting, true);
      expect(editor.hasDocument, false);
    },
  );
  test(
    'navigation Save, Discard, Continue; newer editing prevents departure',
    () async {
      await editor.newDraft(discard);
      editor.body.text = 'local';
      expect(await editor.leave(stay), false);
      expect(editor.body.text, 'local');
      expect(await editor.leave(save), true);
      expect(editor.baseline!.body, 'local');
      editor.body.text = 'discard';
      await editor.leave(discard);
      expect(editor.body.text, 'local');
      final pending = Completer<DraftSnapshot>();
      runtime.onSave = (_) => pending.future;
      editor.body.text = 'A';
      final leaving = editor.leave(save);
      await Future<void>.value();
      editor.body.text = 'B';
      pending.complete(draft('one', body: 'A'));
      expect(await leaving, false);
      expect(editor.body.text, 'B');
    },
  );
  test(
    'pending discard settles actual commit before local replacement',
    () async {
      await editor.newDraft(discard);
      editor.body.text = 'A';
      final pending = Completer<DraftSnapshot>();
      runtime.onSave = (_) => pending.future;
      final saving = editor.save();
      editor.body.text = 'B';
      final leaving = editor.leave(discard);
      pending.complete(draft('one', body: 'A'));
      await saving;
      expect(await leaving, true);
      expect(editor.body.text, 'A');
      expect(editor.baseline!.id, 'one');
    },
  );
  test(
    'native/Flutter quit share final Save; cancel is reversible and not cached',
    () async {
      final quit = DraftQuitCoordinator(runtime);
      addTearDown(quit.editor.dispose);
      await quit.editor.newDraft(discard);
      quit.editor.body.text = 'quit';
      final decision = Completer<LeaveChoice>();
      var dialogs = 0;
      quit.prompt = ({required unknown}) {
        dialogs++;
        return decision.future;
      };
      final native = quit.requestQuit(), flutter = quit.requestQuit();
      expect(identical(native, flutter), true);
      await Future<void>.value();
      expect(runtime.snapshot.admissionPaused, true);
      expect(runtime.shutdowns, 0);
      decision.complete(LeaveChoice.continueEditing);
      expect(await native, false);
      expect(runtime.resumes, 1);
      quit.prompt = save;
      expect(await quit.requestQuit(), true);
      expect(dialogs, 1);
      expect(runtime.writes.length, 1);
      expect(runtime.writes.single.decision, isNotNull);
      expect(runtime.shutdowns, 1);
    },
  );
  test(
    'fault during quit dialog never resumes or starts close on Continue',
    () async {
      final quit = DraftQuitCoordinator(runtime);
      addTearDown(quit.editor.dispose);
      await quit.editor.newDraft(discard);
      quit.editor.body.text = 'keep';
      final decision = Completer<LeaveChoice>();
      quit.prompt = ({required unknown}) => decision.future;
      final exiting = quit.requestQuit();
      await Future<void>.value();
      runtime.setPhase(RuntimePhase.fault, paused: true);
      decision.complete(LeaveChoice.continueEditing);
      expect(await exiting, false);
      expect(runtime.shutdowns, 0);
      expect(runtime.resumes, 0);
      expect(runtime.snapshot.admissionPaused, true);
    },
  );
  test(
    'quit settles pending create then saves B once with its returned identity',
    () async {
      final quit = DraftQuitCoordinator(runtime);
      addTearDown(quit.editor.dispose);
      await quit.editor.newDraft(discard);
      quit.editor.body.text = 'A';
      final first = Completer<DraftSnapshot>();
      runtime.onSave = (_) => first.future;
      final saving = quit.editor.save();
      quit.editor.body.text = 'B';
      quit.prompt = save;
      final exiting = quit.requestQuit();
      await Future<void>.value();
      expect(runtime.snapshot.admissionPaused, true);
      expect(runtime.shutdowns, 0);
      runtime.onSave = null;
      first.complete(draft('created', body: 'A'));
      await saving;
      expect(await exiting, true);
      expect(runtime.writes.length, 2);
      expect(runtime.writes.last.id, 'created');
      expect(runtime.writes.last.expectedRevision, 1);
      expect(runtime.writes.last.body, 'B');
      expect(runtime.writes.last.decision, isNotNull);
    },
  );
  test('unknown final quit Save vetoes close; acknowledged Discard can safely close', () async {
    final quit = DraftQuitCoordinator(runtime);
    addTearDown(quit.editor.dispose);
    await quit.editor.newDraft(discard);
    quit.editor.body.text = 'keep';
    quit.prompt = save;
    runtime.onSave = (_) => Future.error(
      const RuntimeFault(host: CoordinationFault.requestUnknown),
    );
    expect(await quit.requestQuit(), false);
    expect(runtime.shutdowns, 0);
    expect(quit.editor.unknown, true);
    expect(quit.editor.body.text, 'keep');
    runtime.setPhase(RuntimePhase.fault, paused: true);
    var warning = false;
    quit.prompt = ({required unknown}) async {
      warning = unknown;
      return LeaveChoice.discard;
    };
    expect(await quit.requestQuit(), true);
    expect(warning, true);
    expect(runtime.writes.length, 1);
    expect(quit.editor.unknownNotice, isNotNull);
  });
  test(
    'save pending refuses delete; refreshed pages deduplicate by stable ID',
    () async {
      runtime.records['one'] = draft('one');
      await editor.select('one', discard);
      final pending = Completer<DraftSnapshot>();
      runtime.onSave = (_) => pending.future;
      editor.body.text = 'A';
      final saving = editor.save();
      expect(await editor.delete(), false);
      expect(runtime.deletes, isEmpty);
      pending.complete(draft('one', revision: 2, body: 'A'));
      await saving;
      runtime.onList = (cursor) async => cursor == null
          ? DraftPage([draft('one')], DraftCursor(DateTime.utc(2026), 'one'))
          : DraftPage([draft('one'), draft('two')], null);
      await editor.refresh();
      await editor.refresh(more: true);
      expect(editor.items.map((d) => d.id), ['one', 'two']);
    },
  );

  for (final failBeforeResponse in [true, false]) {
    for (final acknowledge in [true, false]) {
      test('unknown during leave prompt needs its own acknowledgement '
          '(before=$failBeforeResponse, discard=$acknowledge)', () async {
        await editor.newDraft(discard);
        editor.body.text = 'local text';
        final write = Completer<DraftSnapshot>();
        final response = Completer<LeaveChoice>();
        runtime.onSave = (_) => write.future;
        final saving = editor.save();
        final displayedUnknown = <bool>[];
        final leaving = editor.leave(({required unknown}) {
          displayedUnknown.add(unknown);
          return displayedUnknown.length == 1
              ? response.future
              : Future.value(
                  acknowledge
                      ? LeaveChoice.discard
                      : LeaveChoice.continueEditing,
                );
        });
        if (failBeforeResponse) {
          write.completeError(
            const RuntimeFault(host: CoordinationFault.requestUnknown),
          );
          await saving;
          response.complete(LeaveChoice.discard);
        } else {
          response.complete(LeaveChoice.discard);
          await Future<void>.value();
          write.completeError(
            const RuntimeFault(host: CoordinationFault.requestUnknown),
          );
          await saving;
        }
        expect(await leaving, acknowledge);
        expect(displayedUnknown, [false, true]);
        expect(editor.body.text, acknowledge ? '' : 'local text');
        expect(editor.unknownFailure!.host, CoordinationFault.requestUnknown);
        expect(runtime.writes.length, 1);
      });
    }
  }
}
