import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';
import 'parameter_form.dart';

enum ContentMode { notProvided, text, hex }

class ParameterPreview extends ChangeNotifier {
  ParameterPreview(this.runtime) {
    content.addListener(invalidate);
    for (final c in form.inputs.values) {
      c.addListener(invalidate);
    }
  }
  final AppRuntime runtime;
  final form = ParameterForm(DiagnosticOperation.send, overrides: true);
  final content = TextEditingController();
  ContentMode mode = ContentMode.notProvided;
  String? profileId, error, selectionError, notice;
  ConnectionProfile? inherited;
  EffectiveParameters? result;
  int _generation = 0, _selection = 0, fieldGeneration = 0;
  bool pending = false, _disposed = false;
  bool get composing =>
      form.composing ||
      (content.value.isComposingRangeValid &&
          !content.value.composing.isCollapsed);
  void notify() {
    if (!_disposed) notifyListeners();
  }

  void invalidate() {
    _generation++;
    result = null;
    error = null;
    notice = null;
    notify();
  }

  bool deferChangeForComposition() {
    if (!composing) return false;
    notice = 'Finish composing text before changing this choice.';
    notify();
    return true;
  }

  void storageChanged() {
    invalidate();
    inherited = null;
    _selection++;
  }

  Future<void> select(String? id) async {
    if (deferChangeForComposition()) return;
    profileId = id;
    inherited = null;
    selectionError = null;
    invalidate();
    final generation = ++_selection;
    try {
      // Explicit selection never depends on a settings read.
      final selected =
          id ?? (await runtime.readSettings()).defaultProfileId?.value;
      final p = selected == null ? null : await runtime.readProfile(selected);
      if (generation == _selection && !_disposed) inherited = p;
    } catch (e) {
      if (generation == _selection) selectionError = RuntimeFault.from(e).code;
    }
    notify();
  }

  List<int>? get bytes => switch (mode) {
    ContentMode.notProvided => null,
    ContentMode.text => textBytes(content.text),
    ContentMode.hex => parseHex(content.text),
  };
  Future<void> preview() async {
    if (pending || deferChangeForComposition()) return;
    final generation = ++_generation;
    result = null;
    error = null;
    pending = true;
    notify();
    try {
      final value = await runtime.resolveParameters(
        form.request(
          profileId: profileId,
          content:
              form.operation == DiagnosticOperation.send ||
                  form.operation == DiagnosticOperation.ping
              ? bytes
              : null,
        ),
      );
      if (generation == _generation && !_disposed) result = value;
    } catch (e) {
      if (generation == _generation) {
        error = e is FormatException
            ? 'invalid_input: check numeric/hex syntax'
            : RuntimeFault.from(e).code;
      }
    } finally {
      pending = false;
      notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    content.dispose();
    form.dispose();
    super.dispose();
  }
}

List<int> textBytes(String text) {
  final bytes = utf8.encode(text);
  if (utf8.decode(bytes) != text) {
    throw const FormatException('Text must contain valid Unicode.');
  }
  return bytes;
}
