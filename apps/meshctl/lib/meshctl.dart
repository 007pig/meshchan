import 'package:args/args.dart';

import 'src/version.dart';

/// Runs meshctl with injectable output and returns the process exit code.
int runCli(
  List<String> arguments, {
  required StringSink output,
  required StringSink error,
}) {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Show the application version.',
    );

  final ArgResults options;
  try {
    options = parser.parse(arguments);
    if (options.rest.isNotEmpty) {
      throw FormatException(
        'Positional arguments are not supported: ${options.rest.join(' ')}',
      );
    }
  } on FormatException catch (exception) {
    error
      ..writeln('Error: ${exception.message}')
      ..writeln('Run "meshctl --help" for usage.');
    return 64;
  }

  if (options.flag('version') && !options.flag('help')) {
    output.writeln('meshctl $meshctlVersion');
    return 0;
  }

  output
    ..writeln('meshctl - Meshchan command-line diagnostics')
    ..writeln()
    ..writeln('Usage: meshctl [options]')
    ..writeln()
    ..writeln(parser.usage);
  return 0;
}
