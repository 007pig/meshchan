import 'dart:async';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';
import 'editor.dart';

/// Both native and Flutter exit requests share this application-owned decision.
/// Cancel is never cached. Shutdown retains the runtime's late-release semantics.
final class DraftQuitCoordinator {
  DraftQuitCoordinator(this.runtime, {this.afterShutdownIntent})
    : editor = DraftEditor(runtime);
  final AppRuntime runtime;
  final DraftEditor editor;
  final void Function()? afterShutdownIntent;
  LeavePrompt? prompt;
  Future<bool>? _attempt;
  bool _closing = false;

  Future<bool> requestQuit() =>
      _attempt ??= _quit().whenComplete(() => _attempt = null);
  Future<bool> _quit() async {
    if (_closing) return (await runtime.shutdown()).canExit;
    if (editor.deciding || editor.deleting || editor.confirming) return false;
    if (editor.deferDepartureForComposition()) return false;
    editor.setQuitting(true);
    DraftDecision? decision;
    var allowed = false;
    try {
      // Early startup has no document/context to wait for and owns no edits.
      if (runtime.snapshot.phase == RuntimePhase.ready) {
        decision = await runtime.beginDraftDecision(editor.documentGeneration);
      }
      if (editor.needsDecision) {
        final show = prompt;
        if (show == null || !await editor.leave(show, decision: decision)) {
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
      if (!_closing &&
          !allowed &&
          runtime.snapshot.phase == RuntimePhase.ready &&
          !runtime.snapshot.admissionPaused) {
        unawaited(editor.refresh());
      }
    }
  }
}
