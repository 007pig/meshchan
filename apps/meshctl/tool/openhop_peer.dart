import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:meshctl/src/cli_output.dart';
import 'package:meshctl/src/process_io.dart';

import 'support/openhop_frame_transport.dart';
import 'support/openhop_peer_runner.dart';

Future<void> main(List<String> arguments) async {
  final output = CliOutput(stdout, stderr);
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('config');
  try {
    final args = parser.parse(arguments);
    if (arguments.isEmpty || args.flag('help')) {
      output.out(
        'Development only. Usage: dart run tool/openhop_peer.dart --config <absolute-file> <info|send|listen|ping|respond>\n'
        'No retries. Consumes the selected Companion inbox. JWT reference required for WS.\n${parser.usage}',
      );
      await output.drain();
      return;
    }
    if (args.rest.length != 1 ||
        ![
          'info',
          'send',
          'listen',
          'ping',
          'respond',
        ].contains(args.rest.single) ||
        args.option('config') == null ||
        !args.option('config')!.startsWith('/')) {
      throw const FormatException(
        'Explicit absolute configuration and operation required.',
      );
    }
    final file = File(args.option('config')!);
    if (file.lengthSync() > 65536) {
      throw const FormatException('Configuration too large.');
    }
    final config = OpenHopPeerConfig(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      args.rest.single,
    );
    final jwt = readOpenHopSecret(config.jwtReference);
    final key = readOpenHopSecret(config.apiKeyReference);
    Map<String, Object?>? preflight;
    if (config.operation == 'info') {
      preflight = await openHopPreflight(config, jwt ?? key!, jwt != null);
      if (jwt == null) {
        output.out(
          jsonEncode({
            'tool': 'openhop_peer',
            'event': 'end',
            'rest': preflight,
            'webSocket': 'BLOCKED_JWT_REQUIRED',
            'exitCode': 69,
            'cleanup': {'state': 'succeeded'},
          }),
        );
        await output.drain();
        exitCode = 69;
        return;
      }
    }
    exitCode = await runOpenHopPeer(
      config,
      output: output,
      createTransport: () => OpenHopFrameTransport(
        baseUrl: config.baseUrl,
        companionName: config.companionName,
        jwt: jwt!,
        connectTimeout: config.requestTimeout,
      ),
      stopRequests: processStopRequests(),
      preflight: preflight,
    );
  } on FormatException {
    output.err(
      'Error: Invalid arguments, configuration, or secret reference. No raw values are logged.',
    );
    exitCode = 64;
  } on OpenHopTransportFailure catch (error) {
    output.out(
      jsonEncode({
        'tool': 'openhop_peer',
        'event': 'end',
        'failure': {'stage': error.stage, 'reason': error.reason},
        'exitCode': 69,
        'webSocketAttempted': false,
        'cleanup': {'state': 'succeeded'},
      }),
    );
    output.err('Error: openHop ${error.stage}/${error.reason}.');
    exitCode = 69;
  } catch (_) {
    output.err('Error: Peer preparation failed; sensitive details suppressed.');
    exitCode = 64;
  }
  await output.drain();
}
