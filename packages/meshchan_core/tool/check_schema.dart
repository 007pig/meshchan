import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart' show databaseSchemaVersion;

/// Regenerate into isolation and compare; never overwrite a published snapshot.
Future<void> main() async {
  final temp = Directory.systemTemp.createTempSync('meshchan-schema-check-');
  try {
    Future<void> run(List<String> args) async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'drift_dev',
        ...args,
      ]);
      if (result.exitCode != 0) {
        stderr.write(result.stderr);
        throw StateError('Schema generator failed.');
      }
    }

    void same(File actual, File expected) {
      if (!expected.existsSync() ||
          base64Encode(actual.readAsBytesSync()) !=
              base64Encode(expected.readAsBytesSync())) {
        throw StateError(
          'Committed schema artifacts differ. Add a real version and migration for a structural change; do not overwrite released snapshots.',
        );
      }
    }

    final snapshot = 'drift_schema_v$databaseSchemaVersion.json';
    await run([
      'schema',
      'dump',
      'lib/src/storage/database.dart',
      '${temp.path}/$snapshot',
    ]);
    same(File('${temp.path}/$snapshot'), File('drift_schemas/$snapshot'));
    await run([
      'schema',
      'generate',
      'drift_schemas',
      '${temp.path}/generated',
    ]);
    final generated = Directory('${temp.path}/generated')
        .listSync()
        .whereType<File>()
        .toList();
    final committed = Directory('test/storage/generated')
        .listSync()
        .whereType<File>()
        .toList();
    if (generated.length != committed.length) {
      throw StateError('Schema helper file set differs.');
    }
    for (final file in generated) {
      same(file, File('test/storage/generated/${file.uri.pathSegments.last}'));
    }
    stdout.writeln(
      'Production schema $databaseSchemaVersion and generated helpers match.',
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}
