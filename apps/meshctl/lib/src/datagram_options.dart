import 'dart:convert';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:meshcore_link/meshcore_link.dart';

ArgParser datagramParser() {
  final group = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show group usage.');
  for (final operation in ['send', 'listen', 'ping', 'respond']) {
    final sends = operation != 'listen';
    final diagnostic = operation == 'ping' || operation == 'respond';
    final receives = operation != 'send';
    final leaf = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Show operation usage.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Write ${operation == 'listen' ? 'NDJSON events and end' : 'one final JSON object'}.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Write safe structural diagnostics to stderr.',
      )
      ..addOption(
        'port',
        help: 'Required exact, explicitly selected serial port path.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5',
        help:
            'Per-command initialization/send/read budget, seconds (1..86400).',
      )
      ..addOption(
        'init-timeout',
        defaultsTo: '15',
        help: 'Total initialization budget, seconds (1..86400).',
      )
      ..addOption(
        'startup-delay',
        defaultsTo: '0',
        help: 'Startup delay, milliseconds (0..86399999); less than init-timeout.',
      )
      ..addOption(
        'task-timeout',
        help: 'Required overall application budget, seconds (1..86400); excludes cleanup/output.',
      );
    if (sends) {
      leaf
        ..addOption('send-channel', help: 'Required local send slot, uint8.')
        ..addOption(
          'route-descriptor',
          help: 'Required send route uint8; 0xFF Flood, 0x00 zero-hop Direct.',
        )
        ..addOption(
          'path-hex',
          defaultsTo: '',
          help: 'Exact route bytes as even-length ASCII HEX; default: empty.',
        );
    }
    if (receives) {
      leaf
        ..addOption(
          'receive-channel',
          help: 'Required local receive slot, uint8.',
        )
        ..addOption(
          'max-entries',
          defaultsTo: '128',
          help: 'Total published entries (1..4096), including filtered traffic and chat.',
        );
    }
    if (diagnostic) {
      leaf
        ..addOption(
          'local-id',
          help: 'Required nonzero uint32 local test label.',
        )
        ..addOption(
          'peer-id',
          help: 'Required distinct nonzero uint32 peer test label.',
        );
    } else {
      leaf.addOption(
        'data-type',
        help: operation == 'send'
            ? 'Required raw data type (1..65535).'
            : 'Optional data type filter (0..65535); default: all.',
      );
    }
    if (operation == 'send' || operation == 'ping') {
      leaf
        ..addOption(
          operation == 'send' ? 'payload-hex' : 'content-hex',
          help: 'Even-length ASCII HEX; exactly one of this option or --text (empty allowed).',
        )
        ..addOption(
          'text',
          help: 'Exact UTF-8 content; no normalization or terminator (empty allowed).',
        );
    }
    if (operation == 'ping') {
      leaf.addOption(
        'response-timeout',
        help: 'Required PONG wait budget, seconds (1..86400).',
      );
    }
    if (operation == 'listen' || operation == 'respond') {
      leaf.addOption(
        'duration',
        help:
            'Required finite listening window after ready, seconds (1..86400).',
      );
    }
    if (operation == 'respond') {
      leaf.addOption(
        'max-responses',
        defaultsTo: '1',
        help: 'Response attempt limit (1..4096).',
      );
    }
    group.addCommand(operation, leaf);
  }
  return group;
}

String datagramHelp(ArgParser group, [String? operation]) => operation == null
    ? 'Usage: meshctl datagram <operation> [options]\n\n${group.usage}\n\n'
          'Operations:\n  send     Send one raw datagram; confirm device acceptance.\n'
          '  listen   Consume the shared inbox for a finite window.\n'
          '  ping     Run one exact diagnostic PING/PONG round trip.\n'
          '  respond  Run a finite diagnostic responder.\n\n'
          'Put business options after the operation. Run "meshctl datagram <operation> --help".'
    : 'Usage: meshctl datagram $operation [options]\n\n${group.commands[operation]!.usage}\n\n'
          'Initializes with DEVICE_QUERY then APP_START; opening may reset boards. No retry.\n'
          'Protocol integers accept strict decimal or 0x/0X HEX; times/counts are decimal only.\n'
          'Route/path validity and the full encoded byte budget are checked before I/O.\n'
          'Cleanup and output may remain pending beyond --task-timeout.\n'
          '${operation == 'send' ? 'Success means local write and device acceptance, not remote delivery.' : 'Consumes the shared inbox, including ordinary chat and other applications.\nFiltering occurs after consumption; all entries consume max-entries. Chat bodies are discarded.'}';

/// Pure validation. Do not use task construction/start as a configuration probe.
final class DatagramOptions {
  DatagramOptions(ArgResults args)
    : operation = args.name!,
      json = args.flag('json'),
      verbose = args.flag('verbose') {
    port = args.option('port') ?? '';
    if (port.trim().isEmpty) {
      throw const FormatException('--port must be nonempty.');
    }
    requestTimeout = Duration(seconds: _integer(args, 'timeout', 1, 86400)!);
    initializationTimeout = Duration(
      seconds: _integer(args, 'init-timeout', 1, 86400)!,
    );
    startupDelay = Duration(
      milliseconds: _integer(args, 'startup-delay', 0, 86399999)!,
    );
    if (startupDelay >= initializationTimeout) {
      throw const FormatException(
        '--startup-delay must be less than --init-timeout in milliseconds.',
      );
    }
    taskTimeout = Duration(seconds: _integer(args, 'task-timeout', 1, 86400)!);
    if (operation != 'listen') {
      sendChannel = _integer(args, 'send-channel', 0, 255, protocol: true);
      routeDescriptor = _integer(
        args,
        'route-descriptor',
        0,
        255,
        protocol: true,
      );
      path = _hex(args.option('path-hex')!, 'path-hex');
    }
    if (operation != 'send') {
      receiveChannel = _integer(
        args,
        'receive-channel',
        0,
        255,
        protocol: true,
      );
      maxEntries = _integer(args, 'max-entries', 1, 4096)!;
    }
    if (operation == 'ping' || operation == 'respond') {
      localId = _integer(args, 'local-id', 1, 0xffffffff, protocol: true);
      peerId = _integer(args, 'peer-id', 1, 0xffffffff, protocol: true);
      if (localId == peerId) {
        throw const FormatException('--local-id and --peer-id must differ.');
      }
    } else {
      dataType = _integer(
        args,
        'data-type',
        operation == 'send' ? 1 : 0,
        65535,
        protocol: true,
        required: operation == 'send',
      );
    }
    if (operation == 'send' || operation == 'ping') {
      final name = operation == 'send' ? 'payload-hex' : 'content-hex';
      if (args.wasParsed(name) == args.wasParsed('text')) {
        throw FormatException('Provide exactly one of --$name or --text.');
      }
      bytes = args.wasParsed(name)
          ? _hex(args.option(name)!, name)
          : Uint8List.fromList(utf8.encode(args.option('text')!));
    }
    if (operation == 'ping') {
      responseTimeout = Duration(
        seconds: _integer(args, 'response-timeout', 1, 86400)!,
      );
    }
    if (operation == 'listen' || operation == 'respond') {
      duration = Duration(seconds: _integer(args, 'duration', 1, 86400)!);
    }
    if (operation == 'respond') {
      maxResponses = _integer(args, 'max-responses', 1, 4096)!;
    }
    if (operation != 'listen') {
      final int capacity;
      try {
        capacity = operation == 'send'
            ? maxChannelDataPayloadLengthForRoute(
                routeDescriptor: routeDescriptor!,
                path: path,
              )
            : maxDiagnosticContentLengthForRoute(
                routeDescriptor: routeDescriptor!,
                path: path,
              );
      } on ArgumentError {
        throw const FormatException(
          '--route-descriptor and --path-hex must describe a valid send route.',
        );
      }
      if (bytes.length > capacity) {
        throw FormatException(
          '${operation == 'send' ? 'Payload' : 'Content'} exceeds --route-descriptor/--path-hex byte capacity ($capacity).',
        );
      }
    }
  }

  final String operation;
  final bool json;
  final bool verbose;
  late final String port;
  late final Duration requestTimeout,
      initializationTimeout,
      startupDelay,
      taskTimeout;
  int? sendChannel, receiveChannel, dataType, routeDescriptor, localId, peerId;
  int maxEntries = 128, maxResponses = 1;
  Uint8List path = Uint8List(0), bytes = Uint8List(0);
  Duration? responseTimeout, duration;

  DiagnosticTaskOptions taskOptions() => DiagnosticTaskOptions(
    sendChannelIndex: sendChannel!,
    receiveChannelIndex: receiveChannel!,
    localTestId: localId!,
    peerTestId: peerId!,
    routeDescriptor: routeDescriptor!,
    path: path,
    taskTimeout: taskTimeout,
    maxEntries: maxEntries,
  );
}

int? _integer(
  ArgResults args,
  String name,
  int min,
  int max, {
  bool protocol = false,
  bool required = true,
}) {
  final value = args.option(name);
  if (value == null && !required) return null;
  final decimal = value != null && RegExp(r'^[0-9]+$').hasMatch(value);
  final hex =
      protocol &&
      value != null &&
      RegExp(r'^0[xX][0-9a-fA-F]+$').hasMatch(value);
  final number = decimal
      ? int.tryParse(value)
      : hex
      ? int.tryParse(value.substring(2), radix: 16)
      : null;
  if (number == null || number < min || number > max) {
    throw FormatException(
      '--$name must be a ${protocol ? 'decimal or 0x-prefixed hexadecimal' : 'decimal'} integer in $min..$max.',
    );
  }
  return number;
}

Uint8List _hex(String value, String name) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw FormatException(
      '--$name must contain an even number of ASCII HEX digits without separators or prefix.',
    );
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}
