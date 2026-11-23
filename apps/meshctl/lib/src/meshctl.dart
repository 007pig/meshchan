import 'dart:io';

import 'process_io.dart';

// Compiling this library entry point records a package URI in the AOT snapshot.
Future<void> main(List<String> arguments) async {
  exitCode = await runProcessCli(arguments, output: stdout, error: stderr);
}
