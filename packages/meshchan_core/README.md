# meshchan_core

Pure Dart offline business values, persistent drafts, repository/history
contracts, and a controlled production Drift/SQLite storage lifecycle. Import
`package:meshchan_core/meshchan_core.dart`. All packages remain `0.1.0-dev.2`.

1C.2 established immutable business values and interfaces. 1C.3 adds the real
schema 1, internal row codecs, directory ownership, file opening/closing, and a
migration baseline. 1C.4 implements draft CRUD, secure local IDs, revision
checks, and bounded cursor pagination through `CoreStorage.drafts`.
Profile/settings repositories, the communication-result mapper, recorder,
business recovery, history query/retention/export service, and CLI wiring remain
unimplemented.
Opening storage never accesses devices or changes diagnostic business records.
The [1C.1 contract](../../docs/architecture/offline-core.md) remains authoritative.

## Host lifecycle

The host chooses a data directory explicitly and awaits:

```dart
final storage = await CoreStorage.open(dataDirectory: hostDataDirectory);
try {
  final draft = await storage.drafts.create(const DraftContent());
  // Use the returned revision for the next mutation.
  await storage.drafts.delete(draft.id, expectedRevision: draft.revision);
} finally {
  await storage.close();
}
```

`hostDataDirectory` is a host-supplied `dart:io` Directory, not a default chosen
by core. The public handle exposes lifecycle/state and drafts; it exports no arbitrary
SQL executor or lock bypass. The internal `StorageHandle.useDatabase` admits work
only while open and tracks each returned Future through all queries/transactions.
Later package services must use that seam and must not retain its database.

Core creates the native executor on the calling isolate **after** ownership and
preflight. No background SQL isolate or read pool is created. Core closes every
executor it creates or accepts through internal test hooks. Open waits for schema
initialization, enabled/verified foreign keys, and real queries. Concurrent close
calls share one Future, stop new admission, await admitted work and actual native
close, then release ownership. A close failure returns `storage_write_failed`,
sets `closeUnconfirmed`, and retains the owner/resources. Repeating close returns
the same failure; there is no forced release or timeout. Earlier committed data
is not declared lost. An open failure preserves its primary category and adds
`CoreException.cleanupUnconfirmed` if resource release cannot be confirmed.
Unconfirmed resources remain quarantined until process exit.

## Persistent drafts (1C.4)

Only the public package import is needed for the complete business flow:

```dart
import 'dart:io';
import 'package:meshchan_core/meshchan_core.dart';

Future<void> editDraft(Directory hostDataDirectory) async {
  final storage = await CoreStorage.open(dataDirectory: hostDataDirectory);
  try {
    final drafts = storage.drafts;
    final created = await drafts.create(
      const DraftContent(title: 'Local note', body: 'First version'),
    );
    final current = await drafts.read(created.id);
    final saved = await drafts.update(
      current.id,
      const DraftContent(title: 'Local note', body: 'Revised version'),
      expectedRevision: current.revision,
    );
    final page = await drafts.list(size: PageSize(50));
    if (page.nextCursor != null) {
      await drafts.list(size: PageSize(50), after: page.nextCursor);
    }
    await drafts.delete(saved.id, expectedRevision: saved.revision);
  } finally {
    await storage.close();
  }
}
```

Concurrent edits can make an expected revision stale. The caller must handle
`CoreException` with code `conflict`, for example by reading the latest version
and letting the user resolve the edit; core never retries with a newer revision.
Missing reads/updates/deletes are `not_found`, including a repeated hard delete.
Expected revisions must be positive. Each mutation completes only after its
short transaction commits. A rejected write or commit rolls back the complete
version and fails the call; there is no asynchronous save queue or memory cache.

Creation uses `Random.secure()` to generate 16 bytes, encoding each as two
lowercase hexadecimal digits (32 total). SQLite enforces uniqueness. Only an
`id` conflict retries, for at most **8 total attempts**; exhaustion, unavailable
entropy, or a failed ID/clock source is `storage_write_failed`. Other constraints
and commit errors never trigger ID retries. Changed updates increment revision
once. At **9223372036854775807**, a changed update cannot generate another version
and fails as `storage_write_failed`; reads, no-ops, and version-matched deletes
still work. Initial revision is 1.

Titles and bodies preserve empty text, Unicode, whitespace, and mixed newline
sequences without normalization, trimming, or a radio-sized byte cap. The input
boundary rejects unpaired UTF-16 surrogates as `invalid_input` before writing,
rather than accepting UTF-8 replacement. Valid emoji, combining characters, and
explicit U+FFFD remain exact. `bodyUtf8ByteLength` remains the derived getter.
Core takes one clock reading at creation (`createdAt == updatedAt`), and a new
reading only for changed content. Times convert to UTC and retain integer
microseconds; equal or backward clock readings are saved as observed. ID and
createdAt never change. Exact title/body comparison determines no-op, **after**
the expected revision check; stale identical text still conflicts.

Lists default to 50 items, with page sizes 1..200. SQL orders by
`updated_at_us DESC, id DESC` using `drafts_updated`, applies the bound row-value
comparison `(updated_at_us, id) < (?, ?)` to seek directly from the two-key
cursor, and fetches at most size + 1 rows. When more rows exist, `nextCursor`
uses the last item actually returned; empty, terminal, and exactly full terminal pages
have no cursor. Deleting the cursor's row does not invalidate continuation.
Separate calls share no snapshot: concurrent edits can move records between
pages. All fetched rows, including the extra probe row, undergo strict decoding;
damaged storage fails as `database_corrupt` instead of skipping records.

The getter returns the same repository instance without SQL. Each method enters
the owning `StorageHandle.useDatabase` once, spanning validation, queries,
transactions/commit, decoding, and result construction. Mutations use the write
failure category; read/list use the read category. Business errors, recognized
corruption, and `cleanupUnconfirmed` retain their existing semantics. Default
errors contain no draft text, paths, SQL, or raw native causes; normal calls log
nothing. Close stops new admission and drains accepted operations before actual
connection close and ownership release. Old repositories fail in closing,
closed, or closeUnconfirmed states; opening another storage never revives them.
There is no second connection, repository close, or ownership mechanism.

## Directory and file boundary

Supported production ABIs are macOS and Linux, arm64/x64, on cooperating local
filesystems. Actual local evidence is macOS arm64; Linux CI is configured but a
remote result must be observed separately. Each isolate may call open; handles
stay on their opening isolate. There is no unsupported cross-isolate loophole.
Recursive creation and filesystem resolution precede a synchronous reservation
keyed by directory device/inode, without lowercasing paths. This covers relative,
absolute, dot/parent, case aliases on case-insensitive filesystems, and supported
symlink directory aliases, including directories created during open.

Stable names in the resolved directory:

| File | Role |
| --- | --- |
| `meshchan.sqlite` | Production SQLite database; standard `-wal`, `-shm`, and `-journal` sidecars are recognized. |
| `.meshchan.owner.lock` | Persistent dedicated ownership inode. Never delete, replace, or truncate it as stale-lock cleanup. |
| `.meshchan.owner.json` | Informational PID/open-time marker only; may remain after normal/abnormal exit. Its deletion or stale PID does not confer ownership. |

An independent close-on-exec, no-follow descriptor takes `flock(LOCK_EX|LOCK_NB)`.
Independent opens conflict within one process, across isolates, and across
processes. Closing a failed contender's descriptor does not release the owner's
lock. The isolate-local reservation additionally covers opening/closing and
ambiguous failures; it is not the cross-isolate arbitration mechanism. See
[Apple flock](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html),
[Linux flock](https://man7.org/linux/man-pages/man2/flock.2.html), and the contrasting
[Dart record-lock semantics](https://api.dart.dev/dart-io/RandomAccessFile/lock.html).
Native `open` uses Dart's `VarArgs` ABI for its mode argument. The small adapter
reads verified native stat prefixes for device/inode/link count, rejecting
symlink and multi-link database, sidecar, lock, or marker files. It uses the
Darwin stat64 and Linux x64/asm-generic arm64 stat layouts; other ABIs fail safely.

These are advisory cooperative locks, not a security boundary against external
SQLite clients or programs replacing directories/files/lock inodes. Network
filesystems and such replacement are unsupported. The OS releases ownership on
abnormal process exit; this proves lock release, not diagnostic business recovery.

## Representation and opening policy

[`schema.drift`](lib/src/storage/schema.drift) defines four tables. IDs are checked
32 lowercase hex digits; draft revision is a positive integer. Draft/profile
indexes order by `(updated_at_us DESC, id DESC)`. History indexes cover unfiltered,
operation, state, and operation+state queries with `(prepared_at_us DESC, run_id
DESC)` tails. No body byte-count cache, per-event table, or full-text index exists.

UTC Unix **microseconds** are explicit checked INTEGER columns, restored with
`DateTime.fromMicrosecondsSinceEpoch(..., isUtc: true)`. Clock ordering is not a
constraint. Integer elapsed `...Us` facts remain separate. The singleton settings
key is internal, with only the two contracted settings and limit 1..100000; no
settings row is inserted at creation. The settings FK is enabled and verified:
profile deletion atomically sets the default to null. A historical run's profile
ID has no FK and survives deletion. Existing dangling references are not repaired
on open; the later settings service must return the contracted `not_found`.

`codec.dart` explicitly encodes operation-specific profile parameters and safe
diagnostic configuration/result/cleanup JSON. Each nested object requires exact
keys/types and explicit stable codes, including nullable keys. No recursive
object serialization, enum ordinal/name, raw result/exception, port, exact route,
endpoint ID, or content enters diagnostic JSON. Exact route bytes/test IDs and
port hints remain local profile fields; draft text is preserved verbatim.
Logical/cleanup scopes and null/partial results remain independent. Malformed
stored representations (including model `invalid_input` during decode) become
`database_corrupt`. A summary format above 1 is explicitly unreadable as
`storage_read_failed`, separate from `unsupported_database_version`. It is never
decoded as format 1. Decode happens on row access, not a whole-database startup
scan. Production table row readers, including aliases, check raw SQLite types
before Drift's default string/integer coercions. Internal work also maps native
failures to a safe read category, or an explicitly selected write category,
preserving recognized corruption and typed core errors. The codecs do not
implement full preset or route/capacity validation.

Preflight runs before the production executor factory or Drift migration. A
missing file or an existing version-0 file with no user objects can initialize.
Version 0 with alien objects, or version 1 missing expected table column types,
nullability, primary keys, query indexes/directions, or FK shape, is corrupt.
Extra user objects are rejected. This is minimum structure recognition, not a
full integrity scan or an audit of every CHECK expression/row. A higher version
is unsupported; recognized SQLite corruption/NOTADB is corrupt; other path,
permission, native-loading, and I/O failures are `storage_open_failed`, not busy.
Default errors contain no path, native message, content, or stack.

Rollback journal `DELETE` plus `synchronous=FULL` is selected for the one-owner
connection. Before accepting an existing file, ordinary rollback-mode databases
without sidecars are inspected through a true read-only connection. Existing
sidecars **or a WAL-mode header** trigger a temporary copy of the main file and
all existing recognized sidecars. The isolated connection may replay WAL or
recover a hot journal; it never checkpoints, deletes, or repairs originals.
Committed versions in WAL are therefore visible. Rejected originals retain main
and sidecar bytes/existence. Sidecars are not automatically corruption. If
inspection/copy/cleanup cannot safely complete, open fails conservatively. There
is no immutable/nolock shortcut. An orphan sidecar without a main file is an
open failure, preserved unchanged. Accepted databases may undergo SQLite's
normal recovery/journal handling; journal selection happens only after preflight.

## Schema baseline and reproducibility

`databaseSchemaVersion = 1` equals Drift's production `schemaVersion`. It is
independent of `diagnosticSummaryFormatVersion = 1`, CLI `schemaVersion: 1`, app
versions, and the wire version. The empty dependency probe's version is unrelated.
Initial DDL and user_version commit in one transaction. The migration entry
rejects unidentified predecessors; there is no artificial v2 migration.

After root `dart pub get --enforce-lockfile`, run from this package:

```bash
dart run build_runner build
dart run tool/check_schema.dart
dart test
```

The saved production snapshot is
[`drift_schemas/drift_schema_v1.json`](drift_schemas/drift_schema_v1.json), with
used generated verification helpers in `test/storage/generated/`. Initial
creation used the locked Drift tools, separately from build_runner:

```bash
dart run drift_dev schema dump lib/src/storage/database.dart drift_schemas/drift_schema_v1.json
dart run drift_dev schema generate drift_schemas test/storage/generated
```

`check_schema.dart` exports to isolation, compares the current definition against
the saved version, regenerates helpers into isolation, and rejects any difference
or missing file. It never overwrites the committed snapshot to pass a check.
Future real structure changes must increment the version, add short transactional
migrations and a **new** snapshot, regenerate helpers, and test old-data survival.
Preserve existing snapshots. Keep generated `.g.dart`, snapshots, and used helpers
in version control. Managers remain disabled because the empty probe otherwise
emits an unused field; explicit production transactions need no managers.

See [development](../../docs/development.md#production-storage-and-migration-baseline-1c3)
and [testing](../../docs/testing.md#production-storage-and-ownership-1c3) for the
actual toolchain, commands, observed results, and remaining product-AOT boundary.
