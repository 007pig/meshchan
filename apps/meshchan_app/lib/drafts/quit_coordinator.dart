import 'dart:async';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';
import 'editor.dart';
import '../profiles/editor.dart';
import '../profiles/preview.dart';
import '../device/model.dart';

/// Both native and Flutter exit requests share this application-owned decision.
/// Cancel is never cached. Shutdown retains the runtime's late-release semantics.
final class DraftQuitCoordinator {
  DraftQuitCoordinator(this.runtime, {this.afterShutdownIntent})
    : editor = DraftEditor(runtime),
      preview = ParameterPreview(runtime),
      device = DeviceModel(runtime) {
    profiles = ProfilesEditor(
      runtime,
      invalidatePreview: preview.storageChanged,
    );
  }
  final AppRuntime runtime;
  final DraftEditor editor;
  final ParameterPreview preview;
  final DeviceModel device;
  late final ProfilesEditor profiles;
  bool auxiliaryActive = false;
  Future<bool> leaveCurrent(LeavePrompt show) async {
    if (device.composing || preview.composing) return false;
    return auxiliaryActive ? profiles.leave(show) : editor.leave(show);
  }

  void disposeEditors() {
    editor.dispose();
    profiles.dispose();
    preview.dispose();
    device.dispose();
  }

  final void Function()? afterShutdownIntent;
  LeavePrompt? prompt;
  Future<bool>? _attempt;
  bool _closing = false;

  Future<bool> requestQuit() =>
      _attempt ??= _quit().whenComplete(() => _attempt = null);
  Future<bool> _quit() async {
    if (_closing) return (await runtime.shutdown()).canExit;
    if (profiles.deciding ||
        profiles.deleting ||
        profiles.confirming ||
        profiles.restoring ||
        editor.deciding ||
        editor.deleting ||
        editor.confirming) {
      return false;
    }
    if (device.composing ||
        profiles.deferDepartureForComposition() ||
        preview.composing) {
      return false;
    }
    if (editor.deferDepartureForComposition()) return false;
    editor.setQuitting(true);
    profiles.setQuitting(true);
    DraftDecision? decision;
    var allowed = false;
    try {
      // Early startup has no document/context to wait for and owns no edits.
      if (runtime.snapshot.phase == RuntimePhase.ready) {
        decision = auxiliaryActive
            ? await runtime.beginDraftDecision(
                profiles.session,
                target: profiles.target,
                targetId: profiles.target == EditorTarget.profile
                    ? profiles.baseline?.id.value
                    : null,
              )
            : await runtime.beginDraftDecision(
                editor.documentGeneration,
                targetId: editor.baseline?.id,
              );
      }
      if (auxiliaryActive ? profiles.needsDecision : editor.needsDecision) {
        final show = prompt;
        if (show == null ||
            !(auxiliaryActive
                ? await profiles.leave(show, decision: decision)
                : await editor.leave(show, decision: decision))) {
          return false;
        }
      }
      _closing = true;
      final closing = runtime.shutdown(); // Save irreversible intent first.
      afterShutdownIntent?.call();
      allowed = (await closing).canExit;
      return allowed;
    } catch (_) {
      return false;
    } finally {
      if (!_closing && decision != null) {
        try {
          await runtime.endDraftDecision(decision);
        } catch (_) {
          // A terminal fault keeps admission frozen. Never reopen the owner.
        }
      }
      editor.setQuitting(_closing);
      profiles.setQuitting(_closing);
      if (!_closing &&
          !allowed &&
          runtime.snapshot.phase == RuntimePhase.ready &&
          !runtime.snapshot.admissionPaused) {
        unawaited(editor.refresh());
      }
    }
  }
}
