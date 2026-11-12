import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

import 'src/business_command.dart';
import 'src/business_storage.dart';
import 'src/stored_datagram_command.dart';
import 'src/cli_display.dart';
import 'src/cli_output.dart';
import 'src/datagram_options.dart';
import 'src/session_command.dart';
import 'src/version.dart';

export 'src/session_command.dart' show CliStopRequest;

/// Runs meshctl with injectable output, diagnostics, transport, and cancellation.
/// Unknown programming errors propagate to the process boundary after cleanup.
Future<int> runCli(
  List<String> arguments, {
  required StringSink output,
  required StringSink error,
  SerialPorts? serialPorts,
  CompanionTransport Function(String path)? createTransport,
  Stream<CliStopRequest>? stopRequests,
  Duration Function()? diagnosticElapsed,
  Uint8List Function()? diagnosticNonceFactory,
  Future<CoreStorage> Function(Directory directory)? openStorage,
  String Function(String? explicit)? selectDataDirectory,
}) async {
  final io = CliOutput(output, error);
  try {
    final code = await _run(
      arguments,
      io,
      serialPorts,
      createTransport,
      stopRequests,
      diagnosticElapsed,
      diagnosticNonceFactory,
      openStorage,
      selectDataDirectory,
    );
    await io.drain();
    return code == 0 && io.failed ? 74 : code;
  } finally {
    await io.drain();
  }
}

Future<int> _run(
  List<String> arguments,
  CliOutput io,
  SerialPorts? serialPorts,
  CompanionTransport Function(String)? createTransport,
  Stream<CliStopRequest>? stopRequests,
  Duration Function()? diagnosticElapsed,
  Uint8List Function()? diagnosticNonceFactory,
  Future<CoreStorage> Function(Directory directory)? openStorage,
  String Function(String? explicit)? selectDataDirectory,
) async {
  final parser = _helpParser()
    ..addOption(
      'data-dir',
      help: 'Persistent business data directory; relative explicit paths use caller cwd.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Show the application version.',
    );
  parser.addCommand('ports', _businessParser());
  parser.addCommand(
    'port-check',
    _businessParser()
      ..addOption('port', help: 'Exact serial port path to check.'),
  );
  parser.addCommand('info', _sessionParser());
  parser.addCommand(
    'watch',
    _sessionParser()..addOption(
      'duration',
      help: 'Observation seconds after ready (1..86400); default: unlimited.',
    ),
  );

  parser.addCommand('datagram', datagramParser());
  for (final group in offlineGroups) {
    parser.addCommand(group, offlineParser(group));
  }

  final ArgResults options;
  final ArgResults? command;
  try {
    options = parser.parse(_literalOptionValues(parser, arguments));
    command = options.command;
    final rest = <String>[];
    for (ArgResults? level = options; level != null; level = level.command) {
      rest.addAll(level.rest);
    }
    if (rest.isNotEmpty) {
      throw FormatException(
        'Unknown command or unexpected positional arguments: ${safeText(rest.join(' '))}',
      );
    }
  } on FormatException {
    return _usageError(
      io,
      'Invalid command syntax, unknown option or unexpected positional arguments.',
    );
  }

  if (options.flag('help')) {
    _writeHelp(io, parser);
    return 0;
  }
  if (command?.name == 'datagram' &&
      (command!.flag('help') || (command.command?.flag('help') ?? false))) {
    io.out(
      datagramHelp(
        parser.commands['datagram']!,
        command.flag('help') ? null : command.command?.name,
      ),
    );
    return 0;
  }
  if (offlineGroups.contains(command?.name) &&
      (command!.flag('help') || (command.command?.flag('help') ?? false))) {
    io.out(
      offlineHelp(
        command.name!,
        parser.commands[command.name]!,
        command.flag('help') ? null : command.command?.name,
      ),
    );
    return 0;
  }
  if (command?.flag('help') ?? false) {
    final name = command!.name!;
    io.out(
      'Usage: meshctl $name${name == 'ports' ? '' : ' --port <path>'} [options]\n\n${parser.commands[name]!.usage}',
    );
    if (name == 'port-check') {
      io.out(
        '\nOpening or closing a port may reset some boards.\nNo data is sent; MeshCore protocol support is not checked.',
      );
    } else if (name == 'info' || name == 'watch') {
      io.out(
        '\nSends two initialization commands (DEVICE_QUERY and APP_START).\nThese may change device session state; this is not passive observation.\nOpening/configuring a port may reset some boards. No retry or reconnect.\n--timeout is per initialization request; it does not bound cleanup or watch.\nStartup delay is diagnostic and is not an established USB delivery fix.',
      );
    }
    return 0;
  }
  if (options.flag('version')) {
    io.out('meshctl $meshctlVersion');
    return 0;
  }
  if (command == null) {
    _writeHelp(io, parser);
    return 0;
  }

  final name = command.name!;
  if (offlineGroups.contains(name) || name == 'datagram') {
    final leaf = command.command;
    if (leaf == null) {
      io.out(
        name == 'datagram'
            ? datagramHelp(parser.commands[name]!)
            : offlineHelp(name, parser.commands[name]!),
      );
      return 0;
    }
    final DatagramInput? datagram;
    final OfflineCommand? offline;
    final String directory;
    try {
      datagram = name == 'datagram' ? DatagramInput(leaf) : null;
      offline = datagram == null ? await prepareOffline(name, leaf) : null;
      directory =
          selectDataDirectory?.call(options.option('data-dir')) ??
          dataDirectoryPath(explicit: options.option('data-dir'));
    } on FormatException catch (e) {
      return _usageError(io, e.message);
    } on CoreException catch (e) {
      return _usageError(io, 'Invalid business input (${e.code.code}).');
    } on HostIoFailure catch (e) {
      io.err('Error: Host I/O failed (${e.source}).');
      if (leaf.flag('json')) {
        io.out(
          jsonEncode({
            'schemaVersion': 1,
            'command': name,
            'action': leaf.name,
            'operationSucceeded': false,
            'committed': false,
            'reason': 'host_io_failure',
            'exitCode': 74,
            'failure': {
              'domain': 'host',
              'source': e.source,
              'code': 'io_failure',
            },
            'maintenance': null,
            'storageClose': null,
            'additionalFailures': const [],
          }),
        );
      }
      return 74;
    }
    Future<CoreStorage> open() =>
        openStorage?.call(Directory(directory)) ??
        CoreStorage.open(dataDirectory: Directory(directory));
    if (offline != null) return runOffline(offline, io, open, stopRequests);
    return runStoredDatagram(
      datagram!,
      io,
      open,
      createTransport ?? (String path) => SerialTransport(portPath: path),
      stopRequests,
      elapsed: diagnosticElapsed,
      nonceFactory: diagnosticNonceFactory,
    );
  }
  if (options.wasParsed('data-dir')) {
    return _usageError(io, '--data-dir does not apply to this command.');
  }
  SessionOptions? sessionOptions;
  try {
    if (name == 'port-check' &&
        (command.option('port')?.trim().isEmpty ?? true)) {
      throw FormatException('$name requires a nonempty --port.');
    }
    if (name == 'info' || name == 'watch') {
      final request = _number(command, 'timeout', 1, 86400)!;
      final initialization = _number(command, 'init-timeout', 1, 86400)!;
      final startup = _number(command, 'startup-delay', 0, 86399999)!;
      if (startup >= initialization * 1000) {
        throw const FormatException(
          '--startup-delay must be less than --init-timeout in milliseconds.',
        );
      }
      final duration = name == 'watch'
          ? _number(command, 'duration', 1, 86400)
          : null;
      if (command.option('port')?.trim().isEmpty ?? true) {
        throw FormatException('$name requires a nonempty --port.');
      }
      sessionOptions = SessionOptions(
        command: name,
        port: command.option('port')!,
        json: command.flag('json'),
        verbose: command.flag('verbose'),
        requestTimeout: Duration(seconds: request),
        initializationTimeout: Duration(seconds: initialization),
        startupDelay: Duration(milliseconds: startup),
        duration: duration == null ? null : Duration(seconds: duration),
      );
    }
  } on FormatException catch (exception) {
    return _usageError(io, exception.message);
  }

  // Every side effect follows syntax, short circuits, and semantic validation.
  if (sessionOptions != null) {
    return runSessionCommand(
      sessionOptions,
      io,
      createTransport ?? (path) => SerialTransport(portPath: path),
      stopRequests,
    );
  }
  final ports = serialPorts ?? SerialPorts();
  final json = command.flag('json');
  try {
    switch (name) {
      case 'ports':
        final descriptions = [...ports.listPorts()]
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final port in descriptions) {
          if (port.warning != null) {
            io.err(
              'Warning: ${safeText(port.path)}: ${safeText(port.warning)}',
            );
          }
        }
        if (json) {
          io.out(
            jsonEncode({
              'schemaVersion': 1,
              'command': 'ports',
              'ports': [
                for (final port in descriptions)
                  {
                    'path': port.path,
                    'description': port.description,
                    'transport': port.transport,
                    'usbVid': port.usbVid,
                    'usbPid': port.usbPid,
                    if (port.warning != null) 'warning': port.warning,
                  },
              ],
            }),
          );
        } else {
          if (descriptions.isEmpty) io.out('No serial ports found.');
          for (final port in descriptions) {
            io.out(
              'Port: ${safeText(port.path)}\n'
              '  Description: ${safeText(port.description)}\n'
              '  Transport: ${safeText(port.transport)}\n'
              '  USB VID/PID: ${_usbId(port.usbVid)}/${_usbId(port.usbPid)}',
            );
          }
        }
      case 'port-check':
        final path = command.option('port')!;
        ports.checkPort(path);
        io.out(
          json
              ? jsonEncode({
                  'schemaVersion': 1,
                  'command': 'port-check',
                  'port': path,
                  'openedAndClosed': true,
                  'protocolChecked': false,
                })
              : 'Serial port opened and closed successfully: ${safeText(path)}\n'
                    'MeshCore protocol support has not been checked.',
        );
    }
  } on SerialPortFailure catch (failure) {
    io.err('Error: ${safeText(failure.message)}');
    return 69;
  }
  return 0;
}

int _usageError(CliOutput io, String message) {
  io.err('Error: ${safeText(message)}\nRun "meshctl --help" for usage.');
  return 64;
}

int? _number(ArgResults command, String name, int min, int max) {
  final text = command.option(name);
  if (text == null) return null;
  final number = RegExp(r'^[0-9]+$').hasMatch(text) ? int.tryParse(text) : null;
  if (number == null || number < min || number > max) {
    throw FormatException('--$name must be a decimal integer in $min..$max.');
  }
  return number;
}

ArgParser _helpParser() => ArgParser()
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Show usage information.',
  );

ArgParser _businessParser() => _helpParser()
  ..addFlag(
    'json',
    negatable: false,
    help: 'Write JSON (watch: NDJSON) to stdout.',
  );

ArgParser _sessionParser() => _businessParser()
  ..addOption('port', help: 'Exact, explicitly selected serial port path.')
  ..addFlag(
    'verbose',
    abbr: 'v',
    negatable: false,
    help: 'Write structural diagnostics to stderr.',
  )
  ..addOption(
    'timeout',
    defaultsTo: '5',
    help: 'Per-request initialization budget, seconds (1..86400).',
  )
  ..addOption(
    'init-timeout',
    defaultsTo: '15',
    help: 'Total initialization budget, seconds (1..86400).',
  )
  ..addOption(
    'startup-delay',
    defaultsTo: '0',
    help: 'Diagnostic startup delay, milliseconds (0..86399999); less than total budget.',
  );

void _writeHelp(CliOutput io, ArgParser parser) {
  io.out(
    'meshctl - Meshchan command-line diagnostics\n\n'
    'Usage: meshctl [options] <command>\n\n${parser.usage}\n\n'
    'Commands:\n'
    '  ports       List serial port paths and available metadata.\n'
    '  port-check  Open and close one explicitly specified port.\n'
    '  info        Initialize once, close, and print a device snapshot.\n'
    '  watch       Initialize once and observe session summaries.\n'
    '  datagram    Finite raw or diagnostic datagram operations.\n'
    '  draft       Create, view, revise, delete and page local drafts.\n'
    '  profile     Manage complete operation presets.\n'
    '  settings    View, set or reset two typed settings.\n'
    '  history     Query, inspect, delete, prune or export one summary page.\n\n'
    'info/watch send two initialization commands and may change device session state.\n'
    'Run "meshctl <command> --help" for command usage.',
  );
}

String _usbId(int? value) =>
    value == null ? '-' : value.toRadixString(16).padLeft(4, '0').toUpperCase();

// args' inline-value regex does not accept embedded line breaks. Convert only
// declared value options to its separate-token form, keeping value tokens opaque.
List<String> _literalOptionValues(ArgParser parser, List<String> arguments) {
  final names = <String>{};
  void collect(ArgParser p) {
    names.addAll(p.options.values.where((o) => !o.isFlag).map((o) => o.name));
    for (final child in p.commands.values) {
      collect(child);
    }
  }

  collect(parser);
  final result = <String>[];
  var valueNext = false, positional = false;
  for (final argument in arguments) {
    if (valueNext || positional) {
      result.add(argument);
      valueNext = false;
      continue;
    }
    if (argument == '--') positional = true;
    final equals = argument.indexOf('=');
    final name = argument.startsWith('--')
        ? argument.substring(2, equals < 0 ? argument.length : equals)
        : '';
    if (names.contains(name)) {
      if (equals >= 0) {
        result.add('--$name');
        result.add(argument.substring(equals + 1));
        continue;
      }
      valueNext = true;
    }
    result.add(argument);
  }
  return result;
}
