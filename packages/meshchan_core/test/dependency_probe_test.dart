import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'support/dependency_probe_database.dart';

void main() {
  test(
    'generated empty database executes a real in-memory SQLite query',
    () async {
      final database = DependencyProbeDatabase(NativeDatabase.memory());
      try {
        final rows = await database.customSelect('SELECT 1 AS value').get();
        expect(rows, hasLength(1));
        expect(rows.single.read<int>('value'), 1);
      } finally {
        await database.close();
      }
    },
  );
}
