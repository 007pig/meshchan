import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../drafts/editor.dart';
import '../runtime/controller.dart';
import '../runtime/protocol.dart';
import 'parameter_form.dart';

/// One persistent auxiliary editing session. Catalog/preview reads never adopt
/// an editing baseline. Only a confirmed write advances that baseline.
class ProfilesEditor extends ChangeNotifier {
  ProfilesEditor(this.runtime, {required this.invalidatePreview}) {
    for (final c in controllers) {
      c.addListener(edited);
    }
    for (final c in form.inputs.values) {
      c.addListener(edited);
    }
  }
  final AppRuntime runtime;
  final VoidCallback invalidatePreview;
  final name = TextEditingController(),
      hint = TextEditingController(),
      defaultId = TextEditingController(),
      history = TextEditingController();
  final form = ParameterForm(DiagnosticOperation.send);
  List<TextEditingController> get controllers => [
    name,
    hint,
    defaultId,
    history,
  ];
  EditorTarget target = EditorTarget.profile;
  ConnectionProfile? baseline;
  AppSettings? settings;
  bool hasDocument = false,
      hintEnabled = false,
      deciding = false,
      quitting = false,
      confirming = false,
      deleting = false,
      restoring = false,
      reading = false,
      unknown = false;
  bool _disposed = false, _replacing = false;
  int session = 0, fieldGeneration = 0, _read = 0, _list = 0;
  String _baselineSignature = '';
  String? notice, error, listError, readError;
  Future<bool>? _mutation;
  Object? inFlight;
  List<ConnectionProfile> items = const [];
  UpdatedCursor? nextCursor;
  bool loading = false;
  String get signature => jsonEncode(
    target == EditorTarget.profile
        ? [name.text, hintEnabled, hint.text, form.signature]
        : [defaultId.text, history.text],
  );
  bool get dirty => hasDocument && signature != _baselineSignature;
  bool get pending => _mutation != null;
  bool get composing => [
    ...controllers,
    ...form.inputs.values,
  ].any((c) => c.value.isComposingRangeValid && !c.value.composing.isCollapsed);
  bool get needsDecision => dirty || pending || unknown;
  bool get available =>
      runtime.snapshot.phase == RuntimePhase.ready &&
      !runtime.snapshot.admissionPaused;
  bool get canOperate =>
      available &&
      !unknown &&
      !deciding &&
      !quitting &&
      !confirming &&
      !deleting &&
      !restoring &&
      !reading;
  bool get locked =>
      deciding || quitting || confirming || deleting || restoring || reading;
  String get status => unknown
      ? 'Write result unknown; do not retry in this session.'
      : pending
      ? 'Saving…'
      : error != null
      ? 'Not saved: $error'
      : dirty
      ? 'Unsaved changes'
      : hasDocument
      ? target == EditorTarget.profile && baseline == null
            ? 'Not saved yet'
            : target == EditorTarget.settings && settings == null
            ? 'Settings not loaded'
            : 'Saved'
      : 'Choose New or select a saved preset';
  void notify() {
    if (!_disposed) notifyListeners();
  }

  void edited() {
    if (!_replacing) {
      invalidatePreview();
      notify();
    }
  }

  bool deferDepartureForComposition() {
    if (!composing) return false;
    notice = 'Finish composing text before this action.';
    notify();
    return true;
  }

  void setQuitting(bool value) {
    quitting = value;
    notify();
  }

  void _replace({
    ConnectionProfile? profile,
    AppSettings? value,
    bool empty = false,
  }) {
    _replacing = true;
    session++;
    fieldGeneration++;
    _read++;
    baseline = profile;
    settings = value;
    hasDocument = !empty;
    error = readError = notice = null;
    if (target == EditorTarget.profile) {
      name.text = profile?.name ?? '';
      hint.text = profile?.portHint ?? '';
      hintEnabled = profile?.portHint != null;
      if (profile == null) {
        form.operation = DiagnosticOperation.send;
        form.loadDefaults();
      } else {
        form.load(profile.parameters);
      }
    } else {
      defaultId.text = value?.defaultProfileId?.value ?? '';
      history.text = value == null ? '' : '${value.diagnosticHistoryLimit}';
    }
    reading = false;
    _baselineSignature = signature;
    _replacing = false;
    notify();
  }

  Future<void> refresh({bool more = false}) async {
    if (more && (loading || nextCursor == null)) return;
    final generation = ++_list, cursor = more ? nextCursor : null;
    if (!more) nextCursor = null;
    loading = true;
    listError = null;
    notify();
    try {
      final page = await runtime.listProfiles(after: cursor);
      if (_disposed || generation != _list) return;
      items = List.unmodifiable(
        {
          if (more)
            for (final p in items) p.id.value: p,
          for (final p in page.items) p.id.value: p,
        }.values,
      );
      nextCursor = page.nextCursor;
    } catch (e) {
      if (generation == _list) listError = RuntimeFault.from(e).code;
    } finally {
      if (generation == _list) {
        loading = false;
        notify();
      }
    }
  }

  Future<bool> newProfile(LeavePrompt prompt) async {
    if (!canOperate || !await leave(prompt)) return false;
    target = EditorTarget.profile;
    _replace();
    return true;
  }

  Future<bool> select(String id, LeavePrompt prompt) async {
    if (!canOperate || !await leave(prompt)) return false;
    final generation = ++_read;
    reading = true;
    readError = null;
    notify();
    try {
      final p = await runtime.readProfile(id);
      if (_disposed || generation != _read) return false;
      target = EditorTarget.profile;
      _replace(profile: p);
      return true;
    } catch (e) {
      if (generation == _read) readError = RuntimeFault.from(e).code;
      return false;
    } finally {
      if (generation == _read) {
        reading = false;
        notify();
      }
    }
  }

  Future<bool> openSettings(LeavePrompt prompt) async {
    if (!canOperate || !await leave(prompt)) return false;
    target = EditorTarget.settings;
    _replace();
    final generation = ++_read;
    reading = true;
    notify();
    try {
      final value = await runtime.readSettings();
      if (_disposed || generation != _read) return false;
      _replace(value: value);
      return true;
    } catch (e) {
      if (generation == _read) readError = RuntimeFault.from(e).code;
      return true;
    } finally {
      reading = false;
      notify();
    }
  }

  void changeType(DiagnosticOperation next) {
    if (!canOperate || pending || deferDepartureForComposition()) return;
    form.changeType(next);
    fieldGeneration++;
    edited();
  }

  void fail(Object e) {
    final f = RuntimeFault.from(e);
    error = e is FormatException
        ? 'invalid_input (check the displayed numeric or hex syntax)'
        : f.code;
    if (e is! FormatException &&
        f.host != null &&
        ![
          CoordinationFault.stopped,
          CoordinationFault.invalidState,
          CoordinationFault.staleRequest,
        ].contains(f.host)) {
      unknown = true;
    }
    notify();
  }

  Future<bool> save({DraftDecision? decision, bool finalSave = false}) {
    if (_mutation != null) return _mutation!;
    if (!hasDocument ||
        unknown ||
        reading ||
        deleting ||
        restoring ||
        confirming ||
        (!finalSave && !canOperate) ||
        deferDepartureForComposition()) {
      return Future.value(false);
    }
    try {
      final Object content = target == EditorTarget.profile
          ? ProfileContent(
              name: name.text,
              portHint: hintEnabled ? hint.text : null,
              parameters: form.parameters(),
            )
          : AppSettings(
              defaultProfileId: defaultId.text.isEmpty
                  ? null
                  : LocalId(defaultId.text),
              diagnosticHistoryLimit: parseNumber(history.text),
            );
      inFlight = content;
      final captured = signature, generation = session, id = baseline?.id.value;
      error = notice = null;
      _mutation = _save(content, captured, generation, id, decision);
      notify();
      return _mutation!;
    } catch (e) {
      fail(e);
      return Future.value(false);
    }
  }

  Future<bool> _save(
    Object value,
    String captured,
    int generation,
    String? id,
    DraftDecision? decision,
  ) async {
    try {
      if (value is ProfileContent) {
        final saved = await runtime.saveProfile(
          value,
          id: id,
          session: generation,
          decision: decision,
        );
        if (generation != session) return false;
        baseline = saved;
      } else {
        final saved = await runtime.saveSettings(
          value as AppSettings,
          decision: decision,
        );
        if (generation != session) return false;
        settings = saved;
      }
      readError = null;
      _baselineSignature = captured;
      invalidatePreview();
      notice = 'Saved.';
      if (decision == null) unawaited(refresh());
      return true;
    } catch (e) {
      fail(e);
      return false;
    } finally {
      inFlight = null;
      _mutation = null;
      notify();
    }
  }

  Future<bool> delete() {
    if (!canOperate || pending || deferDepartureForComposition()) {
      return Future.value(false);
    }
    final id = baseline?.id.value;
    if (id == null) {
      _replace(empty: true);
      return Future.value(true);
    }
    deleting = true;
    _mutation = _delete(id, session);
    notify();
    return _mutation!;
  }

  Future<bool> _delete(String id, int generation) async {
    try {
      await runtime.deleteProfile(id);
      if (generation != session) return false;
      items = List.unmodifiable(items.where((p) => p.id.value != id));
      _replace(empty: true);
      invalidatePreview();
      notice =
          'Deleted. The matching default reference was cleared atomically.';
      unawaited(refresh());
      return true;
    } catch (e) {
      fail(e);
      return false;
    } finally {
      deleting = false;
      _mutation = null;
      notify();
    }
  }

  Future<bool> restore() {
    if (!canOperate || pending || deferDepartureForComposition()) {
      return Future.value(false);
    }
    restoring = true;
    _mutation = _restore();
    notify();
    return _mutation!;
  }

  Future<bool> _restore() async {
    try {
      final value = await runtime.restoreSettings();
      _replace(value: value);
      invalidatePreview();
      notice = 'Settings restored to no default and 1000.';
      return true;
    } catch (e) {
      fail(e);
      return false;
    } finally {
      restoring = false;
      _mutation = null;
      notify();
    }
  }

  Future<bool> leave(LeavePrompt prompt, {DraftDecision? decision}) async {
    if (deciding ||
        confirming ||
        deleting ||
        restoring ||
        reading ||
        deferDepartureForComposition()) {
      return false;
    }
    if (!needsDecision) return true;
    deciding = true;
    notify();
    try {
      final displayedUnknown = unknown, generation = session;
      var choice = await prompt(unknown: displayedUnknown);
      if (choice == LeaveChoice.continueEditing) return false;
      if (_mutation != null) await _mutation;
      if (generation != session) return false;
      if (choice == LeaveChoice.discard) {
        if (unknown && !displayedUnknown) choice = await prompt(unknown: true);
        if (choice != LeaveChoice.discard) return false;
        _replace(profile: baseline, value: settings, empty: !hasDocument);
        return true;
      }
      if (unknown) return false;
      if (dirty && !await save(decision: decision, finalSave: true)) {
        return false;
      }
      return !dirty && !unknown && !composing && error == null;
    } finally {
      deciding = false;
      notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in controllers) {
      c.dispose();
    }
    form.dispose();
    super.dispose();
  }
}
