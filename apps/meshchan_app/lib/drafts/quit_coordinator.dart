import 'dart:async';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';
import 'editor.dart';
import '../profiles/editor.dart';
import '../profiles/preview.dart';
import '../device/model.dart';
import '../diagnostics/model.dart';
import '../history/model.dart';
import '../export/coordinator.dart';

/// Both native and Flutter exit requests share this application-owned decision.
/// Cancel is never cached. Shutdown retains the runtime's late-release semantics.
final class DraftQuitCoordinator {
  DraftQuitCoordinator(
    this.runtime, {
    this.afterShutdownIntent,
    ExportCoordinator? output,
  }) : editor = DraftEditor(runtime),
       preview = ParameterPreview(runtime),
       device = DeviceModel(runtime),
       history = HistoryModel(runtime),
       output = output ?? ExportCoordinator(runtime) {
    diagnostics = DiagnosticsModel(runtime, device);
    profiles = ProfilesEditor(
      runtime,
      invalidatePreview: () {
        preview.storageChanged();
        diagnostics.storageChanged();
      },
    );
  }
  final AppRuntime runtime;
  final DraftEditor editor;
  final ParameterPreview preview;
  final DeviceModel device;
  final HistoryModel history;
  final ExportCoordinator output;
  late final DiagnosticsModel diagnostics;
  late final ProfilesEditor profiles;
  bool auxiliaryActive = false;
  Future<bool> leaveCurrent(LeavePrompt show) async {
    if (history.composing ||
        history.confirming ||
        device.composing ||
        diagnostics.composing ||
        preview.composing) {
      return false;
    }
    return auxiliaryActive ? profiles.leave(show) : editor.leave(show);
  }

  void disposeEditors() {
    editor.dispose();
    profiles.dispose();
    preview.dispose();
    diagnostics.dispose();
    device.dispose();
    history.dispose();
    output.dispose();
  }

  final void Function()? afterShutdownIntent;
  LeavePrompt? prompt;
  Future<bool>? _attempt;
  bool _closing = false;

  Future<bool> requestQuit() {
    if (_attempt case final attempt?) return attempt;
    // Publish the shared attempt before _quit notifies listeners.
    final completion = Completer<bool>();
    final attempt = _attempt = completion.future;
    completion.complete(_quit().whenComplete(() => _attempt = null));
    return attempt;
  }

  Future<bool> _quit() async {
    if (_closing) {
      final result = await runtime.shutdown();
      await output.drain();
      return result.canExit && output.settled;
    }
    if (history.confirming ||
        profiles.deciding ||
        profiles.deleting ||
        profiles.confirming ||
        profiles.restoring ||
        editor.deciding ||
        editor.deleting ||
        editor.confirming) {
      return false;
    }
    if (history.composing ||
        device.composing ||
        diagnostics.composing ||
        profiles.deferDepartureForComposition() ||
        preview.composing) {
      return false;
    }
    if (editor.deferDepartureForComposition()) return false;
    // Composition/preflight veto has no export cancellation side effects.
    output.paused = true;
    history.setBlocked(true);
    output.cancel();
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
      // Close a pre-writer panel before any dirty-document modal. Accepted
      // summary/pre-IO remains owned until it actually settles.
      if (output.job?.writerAdmitted != true) await output.drain();
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
      output.stop();
      final closing = runtime.shutdown(); // Save irreversible intent first.
      afterShutdownIntent?.call();
      final result = await closing;
      await output.drain();
      allowed = result.canExit && output.settled;
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
      if (!_closing) output.paused = false;
      history.setBlocked(_closing);
      if (!_closing &&
          !allowed &&
          runtime.snapshot.phase == RuntimePhase.ready &&
          !runtime.snapshot.admissionPaused) {
        unawaited(editor.refresh());
      }
    }
  }
}
