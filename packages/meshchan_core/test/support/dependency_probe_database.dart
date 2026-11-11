import 'package:drift/drift.dart';

part 'dependency_probe_database.g.dart';

/// Empty, test-only dependency probe; never a production business database.
@DriftDatabase(tables: [])
class DependencyProbeDatabase extends _$DependencyProbeDatabase {
  DependencyProbeDatabase(super.executor);

  /// Version of this in-memory fixture only, not databaseSchemaVersion.
  @override
  int get schemaVersion => 1;
}
