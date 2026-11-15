import 'package:flutter/foundation.dart';

/// Main-window command boundary. Native enablement is advisory; callbacks read
/// the current route, session and admission again. It owns no business resource.
final class DesktopCommands extends ChangeNotifier {
  Future<bool> Function(String command)? dispatch;
  bool Function()? saveEnabled, settingsEnabled, cancelDialogEnabled;
  bool get canCancelDialog =>
      !sheetActive && (cancelDialogEnabled?.call() ?? false);
  int _sheetGeneration = 0;
  bool sheetActive = false;

  bool get canSave => !sheetActive && (saveEnabled?.call() ?? false);
  bool get canOpenSettings =>
      !sheetActive && (settingsEnabled?.call() ?? false);

  void sheetChanged(int job, bool active) {
    if (job < _sheetGeneration || (job == _sheetGeneration && active)) return;
    _sheetGeneration = job;
    sheetActive = active;
    refresh();
  }

  Future<bool> invoke(String command) async {
    if (sheetActive) return false;
    return await dispatch?.call(command) ?? false;
  }

  void refresh() => notifyListeners();
}
