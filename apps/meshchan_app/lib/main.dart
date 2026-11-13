import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'platform_probe.dart';
import 'probe_request.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final request = ProbeRequest.parse(arguments);
    runApp(MeshchanApp(request: request, probe: _probe));
  } on FormatException catch (error) {
    stdout.writeln(
      jsonEncode({
        'probe': 'meshchan.macos.1d2',
        'passed': false,
        'error': 'invalid_arguments',
      }),
    );
    if (arguments.contains('--probe-exit')) exit(64);
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(error.message))),
      ),
    );
  }
}

Future<Map<String, Object?>> _probe(ProbeRequest request) async {
  Map<String, Object?> result;
  try {
    final facts = await const MethodChannel('org.meshchan.host/platform')
        .invokeMapMethod<String, Object?>('directoryFacts');
    result = {
      ...await runPlatformProbe(request),
      'platformDirectories': facts,
      'dartHome': Platform.environment['HOME'],
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    };
  } catch (_) {
    result = {
      'probe': 'meshchan.macos.1d2',
      'passed': false,
      'error': 'platform_probe_failed',
    };
  }
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
  // Probe-only exit follows the worker's actual finalization report. Failure
  // does not imply cleanup. Product quit coordination belongs to 1D.9.
  if (request.exitWhenDone) exit(result['passed'] == true ? 0 : 1);
  return result;
}
