import 'dart:io';

import 'package:meshctl/meshctl.dart';

void main(List<String> arguments) {
  exitCode = runCli(arguments, output: stdout, error: stderr);
}
