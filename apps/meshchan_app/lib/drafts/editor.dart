import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';

enum LeaveChoice { save, discard, continueEditing }

typedef LeavePrompt = Future<LeaveChoice> Function({required bool unknown});

final class PendingDraft {
  const PendingDraft(
    this.documentGeneration,
    this.editGeneration,
    this.baseline,
    this.title,
    this.body,
  );
  final int documentGeneration, editGeneration;
  final DraftSnapshot? baseline;
  final String title, body;
}

/// Main-isolate document session. Controller values change only on intentional
/// document replacement; commit/status/list results never write to them.
final class DraftEditor extends ChangeNotifier {
  DraftEditor(this.runtime) {
    title.addListener(_edited);
    body.addListener(_edited);
  }
  final AppRuntime runtime;
  final title = TextEditingController(), body = TextEditingController();
  DraftSnapshot? baseline, storedVersion;
  PendingDraft? inFlight;
  RuntimeFault? error, listError, readError;
  RuntimeFault? unknownFailure;
  PendingDraft? uncertainSave;
  String? uncertainDeleteId;
  List<DraftSnapshot> items = const [];
  DraftCursor? nextCursor;
  String? selectedId;
  bool hasDocument = false, loading = false, reading = false, deleting = false;
  bool deciding = false, quitting = false, unknown = false, confirming = false;
  String? unknownNotice, notice;
  int documentGeneration = 0, editGeneration = 0;
  int _listGeneration = 0, _readGeneration = 0, _storedGeneration = 0;
  bool _disposed = false, _replacing = false;
  Future<bool>? _mutation;
  String _lastTitle = '', _lastBody = '';

  bool get dirty =>
      hasDocument &&
      (title.text != (baseline?.title ?? '') ||
          body.text != (baseline?.body ?? ''));
  bool get composing => [
    title.value,
    body.value,
  ].any((v) => v.isComposingRangeValid && !v.composing.isCollapsed);

  /// Check before any modal, read-only transition, or admission await can make
  /// Flutter drop marked text on focus loss. Leave this attempt reversible.
  bool deferDepartureForComposition() {
    if (!composing) return false;
    notice = 'Finish composing text before leaving.';
    _notify();
    return true;
  }

  int _bodyBytes = 0;
  int get bodyUtf8Bytes => _bodyBytes;
  void setQuitting(bool value) {
    quitting = value;
    _notify();
  }

  bool beginConfirmation() {
    if (!canOperate || pending) return false;
    confirming = true;
    _notify();
    return true;
  }

  void endConfirmation() {
    confirming = false;
    _notify();
  }

  bool get pending => _mutation != null;
  bool get needsDecision => dirty || composing || pending || unknown;
  bool get available =>
      runtime.snapshot.phase == RuntimePhase.ready &&
      !runtime.snapshot.admissionPaused;
  bool get canOperate =>
      available &&
      unknownFailure == null &&
      !deciding &&
      !quitting &&
      !deleting &&
      !confirming;
  bool get canSave => hasDocument && canOperate && !unknown && !reading;
  String get status => unknownFailure != null
      ? 'Save/delete result unknown'
      : deleting
      ? 'Deleting…'
      : inFlight != null
      ? 'Saving…'
      : error != null
      ? 'Not saved: ${error!.code}'
      : !hasDocument
      ? 'Select a draft or choose New'
      : baseline == null
      ? 'Not saved yet'
      : dirty
      ? 'Unsaved changes'
      : 'Saved';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _edited() {
    if (_replacing) return;
    if (_lastTitle != title.text || _lastBody != body.text) {
      if (_lastBody != body.text) _bodyBytes = utf8.encode(body.text).length;
      editGeneration++;
      _lastTitle = title.text;
      _lastBody = body.text;
    }
    _notify();
  }

  Future<void> refresh({bool more = false}) async {
    if (more && (loading || nextCursor == null)) return;
    final generation = ++_listGeneration;
    final cursor = more ? nextCursor : null;
    if (!more) nextCursor = null; // Invalidate the former cursor chain now.
    loading = true;
    listError = null;
    _notify();
    try {
      final page = await runtime.listDrafts(after: cursor);
      if (_disposed || generation != _listGeneration) return;
      items = List.unmodifiable(
        {
          if (more)
            for (final d in items) d.id: d,
          for (final d in page.items) d.id: d,
        }.values,
      );
      nextCursor = page.nextCursor;
    } catch (e) {
      if (generation == _listGeneration) listError = RuntimeFault.from(e);
    } finally {
      if (generation == _listGeneration) {
        loading = false;
        _notify();
      }
    }
  }

  void _replace(DraftSnapshot? draft, {bool empty = false}) {
    documentGeneration++;
    _readGeneration++;
    _storedGeneration++;
    baseline = draft;
    storedVersion = null;
    selectedId = draft?.id;
    hasDocument = !empty;
    error = readError = null;
    unknown = false;
    notice = null;
    reading = false;
    _replacing = true;
    title.value = TextEditingValue(
      text: draft?.title ?? '',
      selection: const TextSelection.collapsed(offset: 0),
    );
    body.value = TextEditingValue(
      text: draft?.body ?? '',
      selection: const TextSelection.collapsed(offset: 0),
    );
    _lastTitle = title.text;
    _lastBody = body.text;
    _bodyBytes = utf8.encode(body.text).length;
    _replacing = false;
    _notify();
  }

  Future<bool> newDraft(LeavePrompt prompt) async {
    if (!canOperate || !await leave(prompt)) return false;
    _replace(null);
    return true;
  }

  Future<bool> select(String id, LeavePrompt prompt) async {
    if (!canOperate || selectedId == id) return false;
    if (!await leave(prompt)) return false;
    final generation = ++_readGeneration;
    selectedId = id;
    reading = true;
    readError = null;
    _notify();
    try {
      final draft = await runtime.readDraft(id);
      if (_disposed || generation != _readGeneration) return false;
      _replace(draft);
      return true;
    } catch (e) {
      if (generation == _readGeneration) {
        readError = RuntimeFault.from(e);
        selectedId = baseline?.id;
      }
      return false;
    } finally {
      if (generation == _readGeneration) {
        reading = false;
        _notify();
      }
    }
  }

  Future<bool> save({DraftDecision? decision}) =>
      _beginSave(decision: decision);

  Future<bool> _beginSave({
    DraftDecision? decision,
    bool fromDecision = false,
  }) {
    if (_mutation != null) {
      return _mutation!; // Coalesce; never queue more writes.
    }
    if (!hasDocument ||
        reading ||
        deleting ||
        unknownFailure != null ||
        (decision != null &&
            decision.documentGeneration != documentGeneration) ||
        (decision == null &&
            (!available || deciding || quitting) &&
            !fromDecision)) {
      return Future.value(false);
    }
    if (composing) {
      notice = 'Finish composing text before saving.';
      _notify();
      return Future.value(false);
    }
    final captured = PendingDraft(
      documentGeneration,
      editGeneration,
      baseline,
      title.text,
      body.text,
    );
    inFlight = captured;
    error = null;
    notice = null;
    _mutation = _save(captured, decision);
    _notify();
    return _mutation!;
  }

  Future<bool> _save(PendingDraft captured, DraftDecision? decision) async {
    try {
      final saved = await runtime.saveDraft(
        title: captured.title,
        body: captured.body,
        id: captured.baseline?.id,
        expectedRevision: captured.baseline?.revision,
        session: captured.documentGeneration,
        decision: decision,
      );
      if (captured.documentGeneration != documentGeneration) return false;
      baseline = saved;
      selectedId = saved.id;
      _invalidateReads();
      if (decision == null) {
        unawaited(refresh()); // Refresh is independent of commit.
      }
      return true;
    } catch (e) {
      if (captured.documentGeneration == documentGeneration) _mutationError(e);
      return false;
    } finally {
      inFlight = null;
      _mutation = null;
      _notify();
    }
  }

  void _invalidateReads() {
    storedVersion = null;
    _readGeneration++;
    _storedGeneration++;
  }

  void _mutationError(Object e) {
    error = RuntimeFault.from(e);
    unknown =
        error!.host != null &&
        error!.host != CoordinationFault.stopped &&
        error!.host != CoordinationFault.invalidState &&
        error!.host != CoordinationFault.staleRequest;
    if (unknown) {
      unknownFailure ??= error;
      uncertainSave ??= inFlight;
      if (deleting) uncertainDeleteId ??= baseline?.id;
      unknownNotice =
          'A save or delete may have committed. Do not retry in this session. '
          'After safe shutdown, explicitly inspect the stored records in a new session.';
    }
  }

  Future<bool> delete() {
    final target = baseline;
    if (!canOperate || target == null || pending || unknown || reading) {
      return Future.value(false);
    }
    deleting = true;
    error = null;
    _mutation = _delete(target, documentGeneration);
    _notify();
    return _mutation!;
  }

  Future<bool> _delete(DraftSnapshot target, int generation) async {
    try {
      final id = await runtime.deleteDraft(
        target.id,
        expectedRevision: target.revision,
      );
      if (generation != documentGeneration || id != target.id) return false;
      items = List.unmodifiable(items.where((d) => d.id != id));
      _replace(null, empty: true);
      unawaited(refresh());
      return true;
    } catch (e) {
      if (generation == documentGeneration) _mutationError(e);
      return false;
    } finally {
      deleting = false;
      _mutation = null;
      _notify();
    }
  }

  /// Read for inspection only. Neither the buffer nor expectedRevision changes.
  Future<void> inspectStored() async {
    final target = baseline;
    if (target == null || !canOperate || pending || unknown) return;
    final generation = ++_storedGeneration;
    try {
      final value = await runtime.readDraft(target.id);
      if (generation == _storedGeneration && !_disposed) storedVersion = value;
    } catch (e) {
      if (generation == _storedGeneration) {
        notice = 'Stored version read failed: ${RuntimeFault.from(e).code}';
      }
    }
    _notify();
  }

  void reloadInspected([DraftSnapshot? inspected]) {
    final value = inspected ?? storedVersion;
    if (value != null && !pending && !unknown && canOperate) _replace(value);
  }

  /// First navigation target wins until this decision settles. Discard settles
  /// admitted work; it cannot cancel a commit. Unknown requires explicit notice.
  Future<bool> leave(LeavePrompt prompt, {DraftDecision? decision}) async {
    if (deciding || deleting || confirming) return false;
    if (deferDepartureForComposition()) return false;
    if (!needsDecision) return true;
    deciding = true;
    final generation = documentGeneration;
    _notify();
    try {
      final displayedUnknown = unknown;
      var choice = await prompt(unknown: displayedUnknown);
      if (choice == LeaveChoice.continueEditing) return false;
      if (_mutation != null) await _mutation;
      if (generation != documentGeneration) return false;
      if (choice == LeaveChoice.discard) {
        if (unknown && !displayedUnknown) choice = await prompt(unknown: true);
        if (choice != LeaveChoice.discard) return false;
        _replace(baseline, empty: !hasDocument);
        return true;
      }
      if (unknown) {
        notice = 'The previous write result is unknown. Save cannot be retried in this session.';
        return false;
      }
      if (composing) {
        notice = 'Finish composing text before leaving, or continue editing.';
        return false;
      }
      if (dirty || baseline == null) {
        if (!await _beginSave(decision: decision, fromDecision: true)) {
          return false;
        }
      }
      return generation == documentGeneration &&
          !dirty &&
          !composing &&
          !unknown &&
          error == null;
    } finally {
      deciding = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    title.dispose();
    body.dispose();
    super.dispose();
  }
}
