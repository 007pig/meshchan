import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:meshctl/src/process_io.dart';

import 'support/openhop_frame_transport.dart';
import 'support/openhop_idle_probe.dart';
import 'support/openhop_peer_runner.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('config');
  try {
    final args = parser.parse(arguments);
    if (arguments.isEmpty || args.flag('help')) {
      stdout.writeln(
        'Development only: openhop_idle_probe.dart --config <absolute-file>\n'
        'One connection, initialization then finite passive observation; no queue/RF/heartbeat.',
      );
      return;
    }
    final path = args.option('config');
    if (path == null || !path.startsWith('/') || args.rest.isNotEmpty) {
      throw const FormatException();
    }
    final file = File(path);
    if (file.lengthSync() > 65536) throw const FormatException();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final seconds = json['observationSeconds'];
    if (seconds is! int || seconds < 1 || seconds > 120) {
      throw const FormatException();
    }
    final config = OpenHopPeerConfig(json, 'info');
    if (config.jwtReference == null) throw const FormatException();
    final jwt = readOpenHopSecret(config.jwtReference)!;
    final result = await runOpenHopIdleProbe(
      transport: OpenHopFrameTransport(
        baseUrl: config.baseUrl,
        companionName: config.companionName,
        jwt: jwt,
        connectTimeout: config.requestTimeout,
      ),
      duration: Duration(seconds: seconds),
      commandTimeout: config.requestTimeout,
      initializationTimeout: config.initializationTimeout,
      stopRequests: processStopRequests(),
    );
    stdout.writeln(jsonEncode(result));
    await stdout.flush();
    exitCode = result['exitCode'] as int;
  } on FormatException {
    stderr.writeln('Error: Invalid passive probe configuration.');
    exitCode = 64;
  } catch (_) {
    stderr.writeln(
      'Error: Passive probe failed; sensitive details suppressed.',
    );
    exitCode = 69;
  }
}
