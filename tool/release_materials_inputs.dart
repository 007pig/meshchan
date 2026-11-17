// Parse the real lockfile with the already locked YAML parser. No resolution.
import 'dart:convert';
import 'dart:io';

// Repository tooling reuses the already locked parser; no product dependency.
// ignore: depend_on_referenced_packages
import 'package:yaml/yaml.dart';

void main(List<String> args) {
  final root = Directory(args.single).absolute.path;
  final lock = loadYaml(File('$root/pubspec.lock').readAsStringSync());
  final workspace = loadYaml(File('$root/pubspec.yaml').readAsStringSync());
  final members = <String, Object?>{};
  for (final path in workspace['workspace']) {
    final spec = loadYaml(File('$root/$path/pubspec.yaml').readAsStringSync());
    members[spec['name'] as String] = {'path': path, 'spec': spec};
  }
  stdout.writeln(jsonEncode({'lock': lock, 'members': members}));
}
