// Parse the real lockfile with the already locked YAML parser. No resolution.
import 'dart:convert';
import 'dart:io';

// Repository tooling reuses the already locked parser; no product dependency.
// ignore: depend_on_referenced_packages
import 'package:yaml/yaml.dart';

Map<String, Uri> packageUris(String root) {
  final config = File('$root/.dart_tool/package_config.json');
  final resolved = jsonDecode(config.readAsStringSync())['packages'] as List;
  final packages = <String, Uri>{};
  for (final package in resolved) {
    final uri = config.uri.resolve(package['rootUri'] as String);
    final directory = uri.path.endsWith('/')
        ? uri
        : uri.replace(path: '${uri.path}/');
    packages[package['name'] as String] = directory.resolve(
      package['packageUri'] as String? ?? '',
    );
  }
  return packages;
}

List<Map<String, Object>> resolveAssets(
  Iterable<Object?> entries,
  File manifest,
  Map<String, Uri> packages,
) {
  final assets = <Map<String, Object>>[];
  for (final entry in entries) {
    // Match Flutter's AssetsEntry.parseFromYamlSafe for both declaration forms.
    final asset = entry is String
        ? Uri.parse(entry)
        : Uri(pathSegments: ((entry as Map)['path'] as String).split('/'));
    var source = manifest.uri.resolveUri(asset);
    final segments = asset.pathSegments;
    final localExists = asset.path.endsWith('/')
        ? Directory.fromUri(source).existsSync()
        : File.fromUri(source).existsSync();
    final packageQualified =
        segments.length >= 2 && segments.first == 'packages' && !localExists;
    if (packageQualified) {
      final packageUri = packages[segments[1]];
      if (packageUri == null) {
        throw FormatException('Unknown Flutter asset package: $asset');
      }
      source = packageUri.resolveUri(Uri(pathSegments: segments.sublist(2)));
    }
    assets.add({
      'path': source.toFilePath(),
      'packageQualified': packageQualified,
      'transformed':
          entry is Map &&
          (entry['transformers'] as List? ?? const []).isNotEmpty,
    });
  }
  return assets;
}

Iterable<Object?> transformedAssets(YamlMap spec, {bool deferred = false}) {
  final flutter = spec['flutter'];
  final entries = <Object?>[
    ...(flutter?['assets'] as List? ?? const []),
    if (deferred)
      for (final component in flutter?['deferred-components'] ?? const [])
        ...(component['assets'] as List? ?? const []),
  ];
  return entries.where((entry) {
    if (entry is! Map || (entry['transformers'] as List? ?? const []).isEmpty) {
      return false;
    }
    final platforms = entry['platforms'] as List? ?? const [];
    final flavors = entry['flavors'] as List? ?? const [];
    return flavors.isEmpty &&
        (platforms.isEmpty || platforms.contains('macos'));
  });
}

void main(List<String> args) {
  final assetPlan = args.length == 2 && args[1] == '--asset-plan';
  if (args.length != 1 && !assetPlan) {
    throw ArgumentError(
      'Expected the workspace path and optional --asset-plan',
    );
  }
  final root = Directory(args.first).absolute.path;
  final lock = loadYaml(File('$root/pubspec.lock').readAsStringSync());
  final workspace = loadYaml(File('$root/pubspec.yaml').readAsStringSync());
  final packages = packageUris(root);
  final members = <String, Object?>{};
  final shaders = <Map<String, Object>>[];
  final transformed = <Map<String, Object>>[];
  for (final path in workspace['workspace']) {
    final manifest = File('$root/$path/pubspec.yaml');
    final spec = loadYaml(manifest.readAsStringSync()) as YamlMap;
    final resolved = resolveAssets(
      spec['flutter']?['shaders'] ?? const [],
      manifest,
      packages,
    );
    members[spec['name'] as String] = {
      'path': path,
      'spec': spec,
      'resolvedShaders': resolved,
    };
    shaders.addAll(resolved);
    if (assetPlan) {
      transformed.addAll(
        resolveAssets(
          transformedAssets(spec, deferred: spec['name'] == 'meshchan_app'),
          manifest,
          packages,
        ),
      );
    }
  }
  if (assetPlan) {
    for (final entry in packages.entries) {
      if (lock['packages'][entry.key]?['source'] != 'hosted') {
        continue;
      }
      final manifest = File.fromUri(entry.value.resolve('../pubspec.yaml'));
      if (manifest.existsSync()) {
        final spec = loadYaml(manifest.readAsStringSync()) as YamlMap;
        shaders.addAll(
          resolveAssets(
            spec['flutter']?['shaders'] ?? const [],
            manifest,
            packages,
          ),
        );
        transformed.addAll(
          resolveAssets(transformedAssets(spec), manifest, packages),
        );
      }
    }
    stdout.writeln(
      jsonEncode({'shaders': shaders, 'transformedAssets': transformed}),
    );
    return;
  }
  stdout.writeln(jsonEncode({'lock': lock, 'members': members}));
}
