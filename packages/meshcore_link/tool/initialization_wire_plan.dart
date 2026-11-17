import 'dart:convert';
import 'dart:io';

import 'package:meshcore_link/meshcore_link.dart';

/// Pure encoding only. This entry never constructs a transport or opens a port.
void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: initialization_wire_plan');
    exitCode = 64;
    return;
  }
  stdout.writeln(
    jsonEncode({
      'formatVersion': 1,
      'appName': 'Meshchan',
      'appTargetVersion': meshCoreSessionAppTargetVersion,
      'deviceQuery': encodeSerialFrame(
        encodeDeviceQuery(appTargetVersion: meshCoreSessionAppTargetVersion),
      ),
      'appStart': encodeSerialFrame(encodeAppStart(appName: 'Meshchan')),
    }),
  );
}
