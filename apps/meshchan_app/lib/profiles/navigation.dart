import 'package:flutter/foundation.dart';

import '../drafts/editor.dart';
import '../runtime/protocol.dart';
import 'editor.dart';
import 'preview.dart';

/// Shares auxiliary subpage navigation between the view and desktop Settings.
final class ProfilesNavigation extends ChangeNotifier {
  ProfilesNavigation(this.editor, this.preview)
    : page = editor.target == EditorTarget.settings ? 1 : 0;
  final ProfilesEditor editor;
  final ParameterPreview preview;
  int page;
  bool busy = false;

  Future<bool> open(int next, LeavePrompt prompt) async {
    if (busy ||
        editor.quitting ||
        editor.deciding ||
        editor.confirming ||
        editor.deferDepartureForComposition() ||
        preview.composing) {
      return false;
    }
    if (next == page) return true;
    busy = true;
    notifyListeners();
    try {
      if (next == 1) {
        if (!await editor.openSettings(prompt)) return false;
      } else {
        if (!await editor.leave(prompt)) return false;
        if (next == 0 &&
            editor.target != EditorTarget.profile &&
            !await editor.newProfile(prompt)) {
          return false;
        }
      }
      page = next;
      notifyListeners();
      if (next == 2) await preview.select(preview.profileId);
      return true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
