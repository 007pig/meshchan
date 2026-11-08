import 'package:args/args.dart';
import 'package:meshcore_link/meshcore_link.dart';

import 'src/version.dart';

/// Runs meshctl with injectable output and diagnostics, returning an exit code.
int runCli(
  List<String> arguments, {
  required StringSink output,
  required StringSink error,
  SerialPorts? serialPorts,
}) {
  final parser = _helpParser()
    ..addFlag(
      'version',
      negatable: false,
      help: 'Show the application version.',
    );
  parser.addCommand('ports', _helpParser());
  parser.addCommand(
    'port-check',
    _helpParser()..addOption('port', help: 'Exact serial port path to check.'),
  );

  final ArgResults options;
  final ArgResults? command;
  try {
    options = parser.parse(arguments);
    command = options.command;
    final rest = [...options.rest, ...?command?.rest];
    if (rest.isNotEmpty) {
      throw FormatException(
        'Unknown command or unexpected positional arguments: ${rest.join(' ')}',
      );
    }
    if (!options.flag('help') &&
        !(command?.flag('help') ?? false) &&
        command?.name == 'port-check' &&
        (command!.option('port')?.trim().isEmpty ?? true)) {
      throw const FormatException('port-check requires a nonempty --port.');
    }
  } on FormatException catch (exception) {
    error
      ..writeln('Error: ${exception.message}')
      ..writeln('Run "meshctl --help" for usage.');
    return 64;
  }

  if (options.flag('help')) {
    _writeHelp(output, parser);
    return 0;
  }
  if (command?.flag('help') ?? false) {
    final name = command!.name!;
    output
      ..writeln(
        'Usage: meshctl $name [options]'
        '${name == 'port-check' ? ' --port <path>' : ''}',
      )
      ..writeln()
      ..writeln(parser.commands[name]!.usage);
    if (name == 'port-check') {
      output
        ..writeln()
        ..writeln('Opening or closing a port may reset some boards.')
        ..writeln('No data is sent; MeshCore protocol support is not checked.');
    }
    return 0;
  }
  if (options.flag('version')) {
    output.writeln('meshctl $meshctlVersion');
    return 0;
  }
  if (command == null) {
    _writeHelp(output, parser);
    return 0;
  }

  // Instantiate diagnostics only after help, version, and argument validation.
  final ports = serialPorts ?? SerialPorts();
  try {
    switch (command.name) {
      case 'ports':
        final descriptions = [...ports.listPorts()]
          ..sort((a, b) => a.path.compareTo(b.path));
        if (descriptions.isEmpty) {
          output.writeln('No serial ports found.');
        }
        for (final port in descriptions) {
          output
            ..writeln('Port: ${port.path}')
            ..writeln('  Description: ${port.description ?? '-'}')
            ..writeln('  Transport: ${port.transport ?? '-'}')
            ..writeln(
              '  USB VID/PID: ${_usbId(port.usbVid)}/${_usbId(port.usbPid)}',
            );
          if (port.warning != null) {
            error.writeln('Warning: ${port.path}: ${port.warning}');
          }
        }
      case 'port-check':
        final path = command.option('port')!;
        ports.checkPort(path);
        output
          ..writeln('Serial port opened and closed successfully: $path')
          ..writeln('MeshCore protocol support has not been checked.');
    }
  } on SerialPortFailure catch (failure) {
    error.writeln('Error: ${failure.message}');
    return 69;
  }
  return 0;
}

ArgParser _helpParser() => ArgParser()
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Show usage information.',
  );

void _writeHelp(StringSink output, ArgParser parser) {
  output
    ..writeln('meshctl - Meshchan command-line diagnostics')
    ..writeln()
    ..writeln('Usage: meshctl [options] <command>')
    ..writeln()
    ..writeln(parser.usage)
    ..writeln()
    ..writeln('Commands:')
    ..writeln('  ports       List serial port paths and available metadata.')
    ..writeln('  port-check  Open and close one explicitly specified port.')
    ..writeln()
    ..writeln('Run "meshctl <command> --help" for command usage.');
}

String _usbId(int? value) =>
    value == null ? '-' : value.toRadixString(16).padLeft(4, '0').toUpperCase();
