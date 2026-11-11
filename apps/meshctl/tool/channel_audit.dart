import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/src/cli_output.dart';
import 'package:meshctl/src/process_io.dart';

import 'support/channel_audit.dart';
import 'support/openhop_frame_transport.dart';
import 'support/openhop_peer_runner.dart';

/// Explicit local configuration; validation is complete before either factory.
final class ChannelAuditConfig {
  ChannelAuditConfig(Map<String, dynamic> json) {
    aPort = json['aPort'] as String;
    if (aPort.trim().isEmpty || !aPort.startsWith('/dev/')) {
      throw const FormatException('An exact explicit device path is required.');
    }
    aSlots = _slots(json['aSlots']);
    bSlots = _slots(json['bSlots']);
    final requested = json['endpoints'] ?? ['A', 'B'];
    if (requested is! List ||
        !((requested.length == 1 && ['A', 'B'].contains(requested.single)) ||
            (requested.length == 2 &&
                requested[0] == 'A' &&
                requested[1] == 'B'))) {
      throw const FormatException('Select A, B, or A then B explicitly.');
    }
    endpoints = List<String>.unmodifiable(requested.cast<String>());
    // Reuse endpoint, secret-reference and finite session validation without I/O.
    peer = OpenHopPeerConfig(json, 'info');
    if (peer.jwtReference == null) {
      throw const FormatException('JWT reference required.');
    }
    if (peer.taskTimeout > const Duration(seconds: 180) ||
        peer.initializationTimeout > peer.taskTimeout ||
        peer.startupDelay != Duration.zero) {
      throw const FormatException(
        'Invalid audit budgets; startup delay must be zero.',
      );
    }
  }
  late final String aPort;
  late final List<int>? aSlots, bSlots;
  late final List<String> endpoints;
  late final OpenHopPeerConfig peer;
  static List<int>? _slots(dynamic value) {
    if (value == 'allReported') return null;
    if (value is! List ||
        value.isEmpty ||
        value.length > 40 ||
        value.any((s) => s is! int || s < 0 || s > 39) ||
        value.toSet().length != value.length) {
      throw const FormatException(
        'Use explicit unique slots or allReported, at most 40.',
      );
    }
    return List<int>.unmodifiable(value.cast<int>());
  }
}

Future<void> main(List<String> arguments) async {
  final output = CliOutput(stdout, stderr);
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('config');
  try {
    final args = parser.parse(arguments);
    if (arguments.isEmpty || args.flag('help')) {
      output.out(
        'Development only. Usage: dart run tool/channel_audit.dart --config <absolute-file>\n'
        'One USB A and one selected WS B connection. Initialization and bounded GET_CHANNEL only.\n'
        'No RF sends, queue reads, channel writes, retries, names, keys, or fingerprints in output.\n${parser.usage}',
      );
      await output.drain();
      return;
    }
    final path = args.option('config');
    if (args.rest.isNotEmpty || path == null || !path.startsWith('/')) {
      throw const FormatException('Explicit absolute configuration required.');
    }
    final file = File(path);
    if (file.lengthSync() > 65536) {
      throw const FormatException('Configuration too large.');
    }
    final config = ChannelAuditConfig(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    final jwt = readOpenHopSecret(config.peer.jwtReference)!;
    final b = OpenHopFrameTransport(
      baseUrl: config.peer.baseUrl,
      companionName: config.peer.companionName,
      jwt: jwt,
      connectTimeout: config.peer.requestTimeout,
    );
    final runner = ChannelAuditRunner(
      createA: () => SerialTransport(portPath: config.aPort),
      createB: () => b,
      aSlots: config.aSlots,
      bSlots: config.bSlots,
      commandTimeout: config.peer.requestTimeout,
      initializationTimeout: config.peer.initializationTimeout,
      endpointTimeout: config.peer.taskTimeout,
      requestedEndpoints: config.endpoints,
    );
    final signals = processStopRequests().listen(
      (signal) => runner.cancel(signal.name),
    );
    output.onFailure = () => runner.cancel('outputFailure');
    try {
      final result = await runner.run();
      output.out(jsonEncode(result));
      await output.drain();
      exitCode = output.failed ? 74 : result['exitCode'] as int;
    } finally {
      output.onFailure = null;
      await signals.cancel();
    }
  } on FormatException {
    output.err(
      'Error: Invalid audit arguments, configuration, or credential reference.',
    );
    exitCode = 64;
  } catch (_) {
    output.err(
      'Error: Channel audit failed; raw errors and sensitive data suppressed.',
    );
    exitCode = 69;
  }
  await output.drain();
}
