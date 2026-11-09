import 'dart:io';

import 'package:meshctl/src/process_io.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runProcessCli(arguments, output: stdout, error: stderr);
}
