import 'package:flutter/services.dart';

import 'commands.dart';

/// One inbound platform dispatcher, including the original termination request.
final class HostPlatformDispatch {
  const HostPlatformDispatch(this.canQuit, {this.commands});
  final Future<bool> Function() canQuit;
  final DesktopCommands? commands;

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'requestQuit') return canQuit();
    if (call.method == 'desktopCommand' && call.arguments is String) {
      return commands?.invoke(call.arguments as String) ?? false;
    }
    if (call.method == 'nativeSheetChanged' &&
        commands != null &&
        call.arguments is Map) {
      final args = call.arguments as Map;
      if (args['job'] is int &&
          (args['job'] as int) > 0 &&
          args['active'] is bool) {
        commands!.sheetChanged(args['job'] as int, args['active'] as bool);
        return true;
      }
      return false;
    }
    throw MissingPluginException();
  }
}
