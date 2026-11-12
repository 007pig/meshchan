# meshchan_core

Pure Dart offline business values, persistent drafts/profiles/settings, typed
effective-parameter resolution, finite diagnostic recording/recovery, bounded
history, guarded deletion, retention, safe summary export, and a controlled
production Drift/SQLite storage lifecycle. Import
`package:meshchan_core/meshchan_core.dart`. All packages remain `0.1.0-dev.2`.

1C.2 established immutable business values and interfaces. 1C.3 adds the real
schema 1, internal row codecs, directory ownership, file opening/closing, and a
migration baseline. 1C.4 implements draft CRUD, secure local IDs, revision
checks, and bounded cursor pagination through `CoreStorage.drafts`.
1C.5 implements `CoreStorage.profiles`, `CoreStorage.settings`, and
`CoreStorage.resolveParameters`. 1C.6 adds `CoreStorage.record`, explicit typed
whitelist projections, independent logical/cleanup saves, and exclusive startup
recovery. 1C.7 implements `CoreStorage.history` and independent maintenance
reports. CLI wiring (1C.8) remains unimplemented.
Opening storage never accesses devices; it archives incomplete
diagnostic records from the previous owner before returning a usable handle.
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
by core. The public handle exposes lifecycle/state, the three repositories, and typed
resolution and recording; it exports no arbitrary
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

## Profiles, settings, and effective parameters (1C.5)

This complete public-entry flow opens no device:

```dart
import 'dart:io';
import 'package:meshchan_core/meshchan_core.dart';

Future<EffectiveParameters> prepareSend(Directory hostDataDirectory) async {
  final storage = await CoreStorage.open(dataDirectory: hostDataDirectory);
  try {
    final profile = await storage.profiles.save(ProfileContent(
      name: 'Local send preset',
      portHint: '/local/location-hint',
      parameters: SendProfileParameters(
        budgets: const ProfileBudgets(taskTimeoutSeconds: 30),
        sendChannelIndex: 3,
        route: ProfileRoute(routeDescriptor: 0xff),
        dataType: 42,
      ),
    ));
    await storage.settings.save(AppSettings(
      defaultProfileId: profile.id,
      diagnosticHistoryLimit: 250,
    ));
    return await storage.resolveParameters(SendParameterRequest(
      // Omit profileId to select the current default; pass it to select explicitly.
      overrides: const SendOverrides(
        budgets: BudgetOverrides(requestTimeoutSeconds: 10),
        sendChannelIndex: 0,
      ),
      payload: [0x00, 0xff], // Explicit empty [] is also valid.
    ));
  } finally {
    await storage.close();
  }
}
```

The result is immutable in-memory execution input, including local route bytes,
test labels when applicable, and raw invocation content. It is **not a safe
history snapshot** and must not be serialized wholesale into runs/logs. 1C.6
will project allowed diagnostic fields before registration and lifecycle saves.
`portHint` is only saved text: neither it nor resolution authorizes a connection.
The future CLI must require the current explicit nonblank `--port` and forward
its exact path. Core does not accept an execution port or construct transports,
sessions, or tasks. Leaving the short resolution transaction keeps host directory
ownership until awaited close.

`profiles.save(content)` validates a complete preset before clock/entropy use,
then creates a secure random 16-byte ID encoded as 32 lowercase hex digits. Only
`ON CONFLICT(id) DO NOTHING RETURNING` retries (eight total attempts); other
constraints or commit failures fail immediately. The separate internal profile
ID seam does not consume draft test IDs. `save(content, id: existingId)` requires
an existing profile; it never creates/upserts the requested ID. Changed saves
replace the whole operation-specific JSON atomically, clearing irrelevant fields.
There is no revision protocol: concurrent valid saves serialize and may both
succeed. Typed canonical content comparison ignores JSON whitespace/key order
and compares path bytes deeply; an unchanged save performs no UPDATE or clock
read and retains updatedAt. Changed saves preserve observed UTC microseconds,
including equal or backward times. Duplicate names are valid. Name and port hint
are nonblank, preserve exact whitespace/Unicode/path spelling, and reject
unpaired UTF-16 surrogates without rejecting explicit U+FFFD.
Schema 1 also requires a name containing NUL to have at least one character
other than U+0020 space before its first NUL: SQLite's default `trim()` removes
only those spaces, and `length()` stops at NUL. Incompatible names fail with
`invalid_input` before SQL, clock, or ID generation on both create and update.
Compatible embedded NUL names remain exact, including tabs/newlines or Unicode
whitespace before NUL. This name-only constraint does not change Unicode
validation or impose a NUL restriction on port hints or draft text.

`profiles.read(id)`, `delete(id)`, and a supplied update ID return `not_found`
when missing. Deletion uses the enabled settings `ON DELETE SET NULL` FK in the
same transaction; only the matching default reference clears. History limit,
other profiles, drafts, historical profile IDs, and run snapshots survive.
`profiles.list(size: PageSize(...), after: cursor)` has the same non-snapshot,
50-default/1..200 page contract as drafts. It uses `profiles_updated`, descending
UTC microseconds/ID and a bound strict two-key row comparison, fetching at most
size + 1 and validating the probe too. Cursors remain usable after row deletion.

`settings.read()` returns null/1000 without inserting a row when absent.
`settings.save(AppSettings(...))` replaces both fields in one transaction and
checks a nonnull default against a valid profile in that transaction. Any profile
operation is allowed; matching the invocation happens during resolution.
History limits are 1..100000, without clamping. A missing referenced profile is
`not_found`, including a format-valid dangling stored default. An explicit null
save or `restoreDefaults()` repairs that reference without first reading it.
`restoreDefaults()` restores null/1000 in its settings transaction.
Settings reads and their profile validation share one short transaction.

Both successful settings mutations now request independent bounded history
maintenance after commit. A later pruning failure cannot imply that committed
settings rolled back; see the 1C.7 report contract below. Drafts are never pruned.

Request subtypes explicitly select `send`, `listen`, `ping`, or `respond` and
permit only applicable fields. `SendParameterRequest` accepts payload;
`PingParameterRequest` accepts content; both require current invocation bytes,
with missing distinct from empty. Bytes are opaque and may be non-UTF-8. The
other request types accept no content; ping/respond have no overridable dataType.
`EffectiveParameters` returns optional selected profileId, complete
`ProfileParameters`, and optional invocation `content` (send payload/PING content).

Selection and merging follow these rules:

- Explicit profile ID reads only that profile, bypassing unrelated settings,
  including corrupt/dangling defaults. Otherwise settings/default profile are
  read in one short consistent transaction. Missing references never fall back.
- Stored profiles pass strict types/JSON and complete semantic validation before
  checking operation or applying any override. Overrides cannot repair damage.
  A valid profile for a different requested operation is `invalid_input`.
- Each explicit override wins over its profile field, then actual program
  defaults (request 5 s, initialization 15 s, startup 0 ms, maxEntries 128,
  maxResponses 1). Budgets, endpoints, descriptor, and path merge independently.
  Channel/descriptor/startup zero remain explicit values.
- `ListenOverrides.dataType == null` inherits the filter;
  `DataTypeOverride(null)` explicitly clears it; `DataTypeOverride(0)` filters
  type zero. An omitted path inherits; an explicit empty path replaces it. With
  no inherited path, only the path itself defaults to empty. A changed descriptor
  does not automatically clear an inherited incompatible path.
- No defaults exist for task timeout, channels, descriptor, test endpoints,
  response timeout, listen duration, or invocation bytes. Final range and cross
  checks still apply after merging, including distinct nonzero uint32 endpoints
  and startup strictly below initialization. Earlier applicable deadlines win;
  task timeout need not exceed any other budget.

Full validation uses `meshcore_link`'s public pure route/capacity helpers, never
its private code or a copied formula. Flood requires empty path; zero-hop Direct
0x00/0x40/0x80 are preserved; reserved 0xC0 and mismatched paths fail. Iterable
path/content bytes are checked before any Uint8List conversion can truncate them.
Actual send bytes use raw capacity; PING uses diagnostic content capacity (Flood
165/131; 0x60 with 64 path bytes 107/73). Respond validates its local return route;
future incoming PING content is checked by the existing responder at reply time,
without promising every possible message fits. Saving profiles needs neither
content nor a device. Inputs are copied synchronously at request/route construction
and nested result collections are unmodifiable; later edits/deletion cannot
change the resolved snapshot.

All new operations enter the same StorageHandle once. Private helpers accept the
admitted database, avoiding nested admission after closing begins. The admitted
Future spans snapshot, pure merge/validation and result construction; no SQL
transaction extends into device execution. Mutation success includes actual
commit; controlled pre-commit failures immediately roll back on the same handle.
Bad caller input is `invalid_input`, missing records/references `not_found`,
stored type/JSON/semantic damage `database_corrupt`; real query failures use
`storage_read_failed` or, for any part of a mutation, `storage_write_failed`.
Entropy/clock failures use the write category even for TypeError/FormatException.
Default errors expose no local text, paths, test IDs, content, or SQL.

The normal workspace dependency is now core → `meshcore_link ^0.1.0-dev.2`,
with no reverse/CLI import. Offline repository/resolver calls perform **no device I/O**;
only explicit recording invokes the supplied transport factory. Existing
libserialport native build hooks can still run alongside SQLite hooks. Use the
installed native compiler and run shared hook/build gates sequentially.
1C.8 owns CLI presence checks (`wasParsed`, not parser defaults), text/hex lexical
conversion, explicit-port checks, data directory composition, and execution wiring.

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
on open; settings reads and default selection return the contracted `not_found`.

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
decoded as format 1. Decode happens on accessed rows, including bounded recovery
candidates; open does not audit the whole database. Production row readers check raw SQLite types
before Drift's default string/integer coercions. Internal work also maps native
failures to a safe read category, or an explicitly selected write category,
preserving recognized corruption and typed core errors. The codecs do not
implement full preset or route/capacity validation; profile repository and
resolver boundaries add that complete semantic validation after decoding.

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

## Finite diagnostic recording and startup recovery (1C.6)

[`example/record_diagnostic.dart`](example/record_diagnostic.dart) is a runnable
public-API example using a synthetic `CompanionTransport`. It never opens
hardware. Supply a host-selected local directory:

```bash
dart run example/record_diagnostic.dart /tmp/meshchan-example
```

The host opens (including automatic recovery), resolves and records:

```dart
final storage = await CoreStorage.open(dataDirectory: hostDataDirectory);
RecordedOperation? operation;
try {
  final parameters = await storage.resolveParameters(SendParameterRequest(
    overrides: SendOverrides(
      budgets: const BudgetOverrides(taskTimeoutSeconds: 5),
      sendChannelIndex: 3,
      dataType: 99,
      route: RouteOverrides(routeDescriptor: 0xff),
    ),
    payload: [0, 128, 255],
  ));
  operation = storage.record(
    parameters: parameters,
    appVersion: actualHostVersion,
    createTransport: createFreshUnusedTransport,
    subscriptions: [
      RecordingSubscription(
        stage: HostCleanupStage.signalSubscription,
        subscribe: (cancelOperation) => hostStopRequests.listen((_) {
          cancelOperation();
        }),
      ),
    ],
  );
  final registration = await operation.prepared;
  final logical = await operation.logical;
  final logicalSave = await operation.logicalSaved;
  // These remain observable while actual native release is still pending.
  final cleanup = await operation.cleanupDone;
  final cleanupSave = await operation.cleanupSaved;
  final result = await operation.done;
  // Inspect each save's state/error and result.coordinationFailure separately.
} finally {
  if (operation != null) {
    operation.cancel().ignore();
    await operation.done;
  }
  await storage.close();
}
```

The host supplies the actual app version and a new, unused transport. Real-device
composition still needs the current explicit port; portHint authorizes no
connection. The factory is synchronous and lazy. Core revalidates publicly
constructible EffectiveParameters, including actual bytes/capacity, and builds
session/task parameters matching the snapshot: app target 3, FIFO 8, reception
batch 8, diagnostic wire 1/type 65535, responder cache 128/120000000 microseconds.
It accepts no prestarted session/task.

Declare the complete subscription plan before registration. Each subscribe
callback runs after prepared commits and must immediately return its owned
subscription; it must not acquire an unreturned resource before throwing. Core
supports synchronous cancelOperation calls inside subscribe: operation cancellation
is immediate, while host cleanup waits for the registration pass to return or
throw before observing cancellation of every returned subscription. Empty slots
are not declared finished while subscription registration is still in progress. Core
installs no OS signal handlers. Every returned subscription is canceled
independently; two real same-category failures count twice. Raw send's event
subscription and raw listen's additional entries subscription belong to
hostSubscriptions. Task-internal subscriptions are already in task cleanup and
must not be declared again.

Prepared success includes real commit and proves no claim, startup or RF action.
Failure invokes no factory/connect/send/reception start; logical is null and
later saves are notAttempted. Secure 16-byte run IDs (32 lowercase hex digits)
are independent of protocol nonces. Only a targeted run_id collision retries,
at most eight attempts. Other constraints, I/O, commit, entropy and clock failures
do not retry. Factory failure after prepared becomes a controlled host failure
and follows normal settlement.

Logical contains frozen typed summary facts; logicalSaved independently reports
commit or a safe storage error. cleanupUpdates/saveUpdates expose cumulative
observations and completed attempts, including pending cleanup with known
failures. cleanupDone honestly retains unconfirmed release if a cleanup Future
unexpectedly rejects. cleanupSaved.finalCleanup is true only with terminal scopes;
a committed pending snapshot is not final. done.saves retains attempt outcomes.
RecordedResult.fullySuccessful requires completed logic, successful cleanup and
all required commits. Storage failure preserves process facts, continues cleanup,
and never becomes a wireless reason. Uncommitted facts cannot be recovered after
exit; saving an error into the same failing database is not guaranteed. No retry
loop is added.

Configuration is an explicit whitelist: channels, named-unit budgets, filters,
limits, routeDescriptor/pathByteCount and content byte lengths. Excluded are
names, ports, exact paths, endpoints, nonces, payloads, keys, frames, device
information, argv and exception text/stacks. Results use explicit stable enums,
direct typed evidence, real consumer counts and communication monotonic Durations
converted to microseconds. Null reception stays null; task default getters cannot
turn it into observed zeros. Completed reads include failures; publication does
not determine processed or matching counts.

A matching PONG followed by local write failure retains PONG/content validation
and first elapsed, with roundTripSucceeded false and applicationRttUs null.
Successful logical RTT stays successful when cleanup fails. A queued send's
command facts remain separate from a root failure in an earlier read. PONG does
not substitute for matching OK. Acceptance false is unconfirmed; write false
proves neither zero delivered bytes nor zero RF. Responder lastSend describes
only its last attempt, and zero responses establish no round trip. Raw listen
waits for normal trailing entries/onDone before freezing counts. Cancellation
or failure triggers session.close immediately, then settles accepted commands
and reception facts independently of native release. Existing single-inbox,
FIFO, deadline, association, ownership and no-retry semantics remain intact.
Before honoring raw cancellation, core checks an already committed session
failure, including when its asynchronous event has not arrived yet. That earlier
failure retains its reason/stage and typed root evidence. Cancellation that wins
first remains canceled; later notifications cannot rewrite frozen logical facts.

Short transactions read the latest row and update only their logical or cleanup
fields. Canonically equal final facts are no-ops, retaining the first committed
logicalEndedAt even with a different candidate observation time. Terminal scopes
cannot regress/change facts. Cumulative snapshots prevent callback inflation.
Archived rows reject late writes. A failed logical save does not poison the
per-run queue; cleanup can commit on the prepared row. No SQL transaction waits
for device work, native release or subscription cancellation.

One internal admission spans the entire operation, actual cleanup and saves.
Close rejects new recordings and waits for prior admissions; their private writers
continue on that connection after closing starts. Pending cleanup retains the
owner indefinitely. No timeout or GC fakes release. Hosts should still await
logical, cleanup and persistence before closing storage.

After SELECT 1, exclusive open scans prepared/settled candidates through the
state/time/ID index, at most 128 rows per short transaction. Every scanned row
advances a stable cursor, including unchanged settled rows:

| Prior committed state | Open behavior |
| --- | --- |
| prepared, including independently saved cleanup | Archive interrupted; keep partial/null result, null logicalEndedAt and real terminal cleanup. |
| settled with unresolved cleanup | Archive cleanup_unconfirmed; keep final result/time; only unresolved scopes become unconfirmed_after_exit. |
| settled with terminal cleanup, including failed | Preserve completely; no recovery timestamp. |
| recovered_archived | Preserve first recovery time/reason and all facts; do not scan/rewrite. |

Aggregate becomes unconfirmed_after_exit only with an unresolved scope. Recovery
invents no task failure, PONG false, zeros, logical end, confirmed release, replay
or inbox reads. Accessed damage is database_corrupt; higher summary format is
storage_read_failed; mutation/dependency failure retains storage_write_failed.
A failed batch rolls back itself; earlier batches remain committed and another
open continues idempotently. Failure returns no usable handle and follows existing
close/owner-release/quarantine rules. This is not cross-batch atomicity or a full
integrity audit.

The 1C.6 handoff is implemented by the 1C.7 history service below. Maintenance
does not undo committed facts. 1C.8 owns CLI presence/content,
explicit port/directory, recording entry, signal lifetime and output/exit mapping.
Current CLI behavior/output remains unchanged.

## Diagnostic history, retention, and safe export (1C.7)

`CoreStorage.history` is a stable, synchronous getter with no I/O. Its `read`,
`query`, `delete`, `exportSummary`, `maintain` and `waitForMaintenance` methods
use the same owner, connection and admission/close barrier as the other services.
There is no repository close, second connection or raw SQL/force API. History
operations never recover records again, resolve profiles or contact a device.
The hardware-free [public host example](example/inspect_history.dart) accepts a
host-selected directory, reads and continues a filtered page, exports a page,
checks independent maintenance and awaits close in `finally`. Empty storage is
valid; an optional deletion requires an explicitly selected run ID.

```dart
final history = storage.history;
final filter = HistoryQuery(
  operation: DiagnosticOperation.ping,
  recordState: DiagnosticRecordState.settled,
  preparedFromInclusive: DateTime.utc(2026, 11, 1),
  preparedUntilExclusive: DateTime.utc(2026, 12, 1),
);
final page = await history.query(filter: filter, size: PageSize(50));
if (page.nextCursor case final cursor?) {
  await history.query(filter: filter, size: PageSize(50), after: cursor);
}
final summary = await history.exportSummary(filter: filter, size: PageSize(50));
// summary.json is a complete JSON string. The host chooses its destination.
// Continue with the same filter and after: summary.nextCursor, when nonnull.
final maintenance = await history.maintain();
if (maintenance.state == HistoryMaintenanceState.failed) {
  // Display maintenance.error.code separately from any committed save.
}
```

All four optional filter fields combine with AND. Registration time is UTC
`preparedAt`, with an inclusive lower and exclusive upper bound; when both are
present, lower must precede upper. Filters do not use logical/recovery times or
deletion eligibility. All legal states, including prepared/pending, are readable.
Queries order by `prepared_at_us DESC, run_id DESC` with bound epoch microseconds,
four existing filter-specific indexes and a bound row-value seek, never OFFSET.
Default size is 50; 1..200 are allowed. The extra size+1 probe is strictly decoded
and validated too. Only an actual extra row produces a cursor from the last
returned item. Deleting/pruning the cursor row still permits continuation.
Independent pages share no snapshot and can reflect intervening state changes,
insertion or deletion. Missing reads/deletes are `not_found`; damaged accessed
storage is `database_corrupt`; a higher summary format is `storage_read_failed`.

Explicit deletion validates the current row in its short write transaction,
checks eligibility and the active pin, deletes exactly one row and awaits commit.
Eligible means `recovered_archived`, or `settled` with **both** core and
hostSubscriptions terminal (`succeeded`, `failed`, `not_required`). Real cleanup
failures and recovery's `unconfirmed_after_exit` are eligible under these rules.
Prepared with terminal cleanup and settled with either scope pending/unconfirmed
are ineligible. Known ineligible/pinned records fail with `conflict`. Failed
deletion rolls back the complete row and cannot change another business object.

A recording pins its committed run ID before prepared is exposed or device work
starts. The pin lasts through cumulative cleanup snapshots, pending save Futures
and the final save, including construction/failure paths. Intermediate terminal
snapshots do not release it. Pin release invalidates selection and requests
maintenance again. A pin adds a deletion constraint without changing rank: an
old pinned excess row is deferred, never replaced by deleting a newer retained
row. This is in-process protection, with no lease, heartbeat or database field.

Retention keeps the newest `diagnosticHistoryLimit` eligible records across all
operations (default 1000, allowed 1..100000). Missing settings use defaults;
damaged settings fail visibly and are never clamped. Maintenance reads stored
settings directly and needs no default-profile resolution. Total row count can
legitimately exceed the limit because of ineligible rows or pinned excess rows.
Triggers are successful exclusive recovery/open, eligible logical/cleanup
commits, final pin release, settings save/restoreDefaults commits, explicit
deletion and `maintain()`. Duplicate requests join one worker.

Each short transaction scans/validates at most **128** rows in index order and
deletes at most 128 excess rows. Cursor advancement covers every scanned row.
Only bounded rows and counters are retained in memory; eligibility requires
cleanup JSON, so total scanning is proportional to visited history, potentially
repeated after invalidation. LIMIT 128 is not an O(128) total-work claim.
Current settings are read in every batch. Settings/run mutations and explicit
deletions invalidate rank **inside their transaction before commit**; a rollback
can cause an extra scan but cannot expose committed changes with stale rank.
The next batch restarts from the newest row after invalidation or a changed
limit. Worker-owned deletes do not recursively request maintenance. No long
transaction or lock spans the whole history or waits for a device/pin.

`maintain()` actively requests and awaits the worker; `waitForMaintenance()`
waits for already requested work without retrying a failure. Both return
`HistoryMaintenanceReport` with `completed`, `deferred` or `failed`, committed
`deletedCount`, the last `historyLimit` (null if never read), `deferredCount` and
a safe `CoreException` on failure. `latestMaintenance` retains startup/automatic
results. `unacknowledgedFailure` retains the latest failure and
`unacknowledgedFailureCount` counts failed executions until the host explicitly
calls `acknowledgeMaintenanceFailures()`. Merely reading/waiting or a later
automatic success does not clear these fields. This is bounded in-memory state,
not a persistent event log; observe it before closing the handle.

A bad batch rolls back completely; earlier committed batches remain deleted and
are counted in the report. Failure ends the execution without automatic failure
spin; another explicit/external trigger or the next open retries. A deferred
execution ends without waiting for RF, and unpin triggers another check. Open
still fails on preflight/schema/recovery errors, but a subsequent retention
failure returns a usable handle with its independent report. Settings return
their committed `AppSettings`; `RecordingSave`, logical/cleanup facts and
`RecordedResult.fullySuccessful` retain their existing meaning. Maintenance
cannot cause a resend or turn committed work into a failed save.

Automatic work is registered synchronously before the triggering admission is
released. Closing refuses new external work while admitted recording/settings
continuations can still register required maintenance. Close awaits recording,
actual cleanup, saves and maintenance before native close and owner release.
Maintenance failure releases its admission and preserves its report; it does
not imply `closeUnconfirmed`. Actual native-close quarantine remains unchanged.

Each export call returns a `DiagnosticSummaryPage` (`json`, typed `nextCursor`)
using the same bounded filter/order/probe and one admission. The JSON root is:

```json
{"diagnosticSummaryFormatVersion":1,"exportedAt":"2026-11-12T09:30:00.000000Z","runs":[]}
```

Each run explicitly contains `runId`, `operation`, `appVersion`,
`diagnosticSummaryFormatVersion`, `configuration`, `preparedAt`, `logicalEndedAt`,
`recordState`, `result`, `cleanup`, `recoveredAt`, `recoveryReason`. Nested values
reuse the typed configuration/result/two-scope-cleanup allowlists, including
controlled failure codes, routeDescriptor/pathByteCount, byte lengths and integer
RTT/elapsed `...Us`. Every time has UTC Z and exactly six fractional digits.
Meaningful null/false/zero and partial/recovery facts remain unchanged, including
observed PONG plus local failure or logical success plus cleanup failure.
`profileId` is completely omitted. No profiles/names/ports/exact paths, test IDs,
nonces, content, credentials, raw frames, chat, device information, argv,
exception text or stacks are encoded. No whole-row serialization/blacklist is
used. JSON is returned only after the entire selection, clock and encoding
succeed; generation failures are safe `storage_read_failed`, distinct from bad
stored rows. The host must explicitly request further pages. This is a safe
summary selection, **not a database backup** or import/restore format.

Schema/snapshot 1, diagnostic summary format 1, CLI schema 1, dependencies and
package version remain unchanged. CLI flags, directories, explicit ports,
output destinations, maintenance error precedence and exit wiring belong to
1C.8; native SQLite product distribution and dev.3 acceptance remain later work.
