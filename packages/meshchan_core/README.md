# meshchan_core

Pure Dart offline business values and asynchronous persistence contracts. Import
`package:meshchan_core/meshchan_core.dart` for `Draft`, operation-specific
`ConnectionProfile` parameters, `AppSettings`, safe `DiagnosticRun` summaries,
bounded pagination, stable errors, and repository/history interfaces.

Phase 1 / 1C.2 provides types, interfaces, and dependency validation only. There
is no production database, repository implementation, save capability, recording
coordinator, diagnostic mapper, export, or CLI integration. Constructors perform
only local checks; complete profile/route/effective-parameter validation belongs
to later services. Values do not generate IDs, read directories, print content,
or access devices. Mutable input collections are copied and made unmodifiable.

The [1C.1 contract](../../docs/architecture/offline-core.md) fixes the business
semantics and [implementation handoff](../../docs/architecture/offline-core.md#implementation-handoff).
1C.3 supplies the real schema/snapshot, host-supplied executor/path lifecycle,
exclusive directory ownership, migration baseline, and storage-open failures.
Draft/profile/settings implementations follow in 1C.4–1C.5; recording/history
and CLI composition follow in 1C.6–1C.9. All packages remain `0.1.0-dev.2`.

Use the single workspace root lockfile. See the
[developer guide](../../docs/development.md#offline-core-package-and-dependency-baseline-1c2)
for resolved versions, licenses, SDK/native requirements, and actual validation.
After locked resolution at the root, run from this package:

```bash
dart run build_runner build
dart test
```

From the repository root, check generated consistency and the whole workspace:

```bash
git diff --exit-code -- packages/meshchan_core/test/support/dependency_probe_database.g.dart
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

Commit the generated test fixture with its source. Regeneration must preserve
its bytes. The default source set includes `test/`. The minimal `build.yaml`
disables managers because an empty database otherwise generates an unused
private manager field that fails analysis. Other generation options are default.
The only Drift database lives under `test/support`, accepts `QueryExecutor`, and
uses `NativeDatabase.memory()` in a test with awaited close in `finally`.
Its `schemaVersion = 1` belongs only to that empty in-memory fixture. It does not
define Meshchan's `databaseSchemaVersion`, create a business schema, or prove
file reopening, migration, locking, recovery, or product SQLite AOT distribution.
