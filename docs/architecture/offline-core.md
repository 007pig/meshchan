# Offline core and persistence contract (1C.1)

## Status, source baseline, and scope

This document fixes the Phase 1 / 1C / Step 1 business and persistence contract
for implementation in subsequent steps. The source review on November 11, 2026,
used a clean `master` worktree at
`11367a1993d98f12218281841f6587d63fac7f87`. This was the actual local HEAD,
not a requested checkout or a reconstructed release baseline.

The [workspace manifest](../../pubspec.yaml) currently contains only
[`meshcore_link`](../../packages/meshcore_link/pubspec.yaml) and
[`meshctl`](../../apps/meshctl/pubspec.yaml), both at `0.1.0-dev.2`.
There is no `meshchan_core`, business database, or offline repository API at this
baseline. Existing finite operations, safe projections, and cleanup contracts
are available; the business objects and persistence behavior below are **decisions
for subsequent implementation**, not delivered capabilities or passing tests.
`0.1.0-dev.3` is the intended later 1C delivery target. Step 1 changes no version
and does not complete 1C.

The source of truth for current behavior is:

| Evidence | Relevant current contract |
| --- | --- |
| [Developer guide](../development.md), [testing guide](../testing.md), and [CLI guide](../cli.md) | Workspace/native build requirements, hardware-free validation boundaries, explicit port selection, finite commands, output and exit precedence. |
| [1B delivery record](../releases/phase-1b-dev2.md) | Dated software/native and selected Direct RF evidence with retained failures. Later development-tool fixes do not retroactively validate older bundles. The product is USB-only; relay, physical unplug, historical USB causes, and public redistribution remain outside the established evidence. |
| [Session contract](../protocol/companion-session.md) and [session implementation](../../packages/meshcore_link/lib/src/session/meshcore_session.dart) | Exclusive session ownership, command facts, one shared inbox, logical settlement before actual cleanup, and no automatic retry. |
| [Diagnostic contract](../protocol/diagnostic-tasks.md), [task implementation](../../packages/meshcore_link/lib/src/diagnostics/diagnostic_tasks.dart), and [result types](../../packages/meshcore_link/lib/src/diagnostics/diagnostic_results.dart) | Separate `done` and `cleanupDone`, frozen nullable send facts, finite results and counts. |
| [PING](../../packages/meshcore_link/lib/src/diagnostics/ping_task.dart), [responder](../../packages/meshcore_link/lib/src/diagnostics/responder_task.dart), and [exact matcher](../../packages/meshcore_link/lib/src/diagnostics/ping_pong.dart) | PONG observation can survive local failure; responder counts and last-send facts have different meanings. |
| [CLI options](../../apps/meshctl/lib/src/datagram_options.dart), [command runner](../../apps/meshctl/lib/src/datagram_command.dart), [diagnostic projection](../../apps/meshctl/lib/src/datagram_projection.dart), and [failure projection](../../apps/meshctl/lib/src/cli_display.dart) | Actual accepted fields/budgets, safe structural output, raw-operation composition, and cleanup/output ownership. |

1C covers local drafts, connection/diagnostic presets, two application settings,
redacted finite diagnostic history, recovery, bounded queries, and summary
export using Drift/SQLite. Flutter UI belongs to 1D. Article identity/signing,
long-content encoding and resumable chunk transfer, publishing, and decentralized
synchronization belong to later phases. A saved draft is not a published article.

## Package responsibilities and dependency direction

| Module | Responsibility |
| --- | --- |
| `meshcore_link` | Device protocol, transports, sessions, datagrams, reception, and existing finite diagnostic tasks. It has no dependency on `meshchan_core`, Drift, or business database writes. |
| Planned `meshchan_core` | Drafts, profiles, settings, typed diagnostic mapping and recording, persistence, queries, retention, and recovery rules. Its diagnostic adapter may depend one way on the [public `meshcore_link` API](../../packages/meshcore_link/lib/meshcore_link.dart). CLI and Flutter reuse that mapping/recording logic. |
| `meshctl` | Parse arguments, require the current explicit device selection, choose the data directory, compose business and device operations, report results, and own terminal output, signals, and process lifetime. |
| Future Flutter application | UI, platform directories and permissions, and calls to business interfaces. It supplies host resources and owns its application lifetime. |

Use one new business package. Do not introduce a generic ORM abstraction, event
sourcing, a plugin framework, or empty adapter packages. Drift is the selected
persistence approach; dependency compatibility and native packaging are assessed
in 1C.2 and later delivery checks, without pinning versions here.

The host supplies the database path/executor and the exclusive directory owner.
Core business code does not select a directory through cwd, import Flutter
Widgets or platform-directory plugins, or print terminal output. Opening storage,
editing drafts/profiles/settings, and querying history never construct a
transport, open a device, or consume its inbox. Pure Dart and hardware-free use
do not promise the absence of native build/runtime dependencies; even the current
communication dependency has native build hooks.

## Shared value and save conventions

These are logical fields, not Drift tables, SQL DDL, Dart classes, or physical
index definitions. `?` means nullable; absence is never silently replaced with
an observed value. Stored codes use explicit stable string mappings, even when
their spelling matches a current enum name. Do not store enum ordinals or derive
the storage vocabulary automatically from future enum renames.

Core generates each local `id`/`runId` as an opaque 128-bit random value encoded
as 32 lowercase hexadecimal digits, independently for each record. It checks
uniqueness on insertion; entropy/insertion failure is reported without a partial
save. This rule chooses no identifier dependency in Step 1. IDs are immutable,
local to business records, and separate from article hashes, author identity,
test endpoint labels, protocol request IDs, and the diagnostic nonce.

All business instants are UTC. Export uses RFC 3339 UTC strings with a `Z`
suffix and six fractional-second digits. Wall-clock timestamps describe local
registration/observation, not exact radio events. Clock adjustments are possible;
revision and lifecycle transitions do not rely on timestamp comparisons. Physical
time storage is a 1C.3 decision. Core RTT/elapsed `Duration` values are preserved
as integer microseconds in fields ending in `Us`; never recompute them from UTC
timestamps.

**Save success means the database transaction has committed.** An in-memory
update or admission to an asynchronous queue is insufficient. Related fields
commit together; failure preserves the previous complete business version.
Repository calls expose commit failure to the caller. Acceptance must reopen a
real database file after a normal commit/close; an in-memory test alone is
insufficient. Controlled process tests establish only their tested interruption
windows, not immunity to every power loss, hardware failure, or filesystem fault.

List queries use cursor pagination: default 50, allowed page size 1..200, no
unbounded list call. Draft/profile order is `updatedAt DESC, id DESC`; diagnostic
order is `preparedAt DESC, runId DESC`. Cursors carry both sort values so ties
are stable. Concurrent edits can move a record between pages; 1C does not promise
a snapshot across separate page calls. Invalid cursors/limits are invalid input.

## Draft

| Field | Logical type / nullability | Meaning, constraint, and generation/default |
| --- | --- | --- |
| `id` | Local ID, required | Core-generated immutable local record ID. |
| `title` | String, required | Defaults to empty; incomplete titles are allowed. Preserve supplied text. |
| `body` | String, required | Defaults to empty; preserve exact content, including Unicode, whitespace, and newline sequences. No automatic trim, normalization, newline replacement, or truncation. |
| `createdAt` | UTC instant, required | Core clock at creation; immutable. |
| `updatedAt` | UTC instant, required | Initially `createdAt`; core clock when a changed version is saved. |
| `revision` | Positive integer, required | Initially 1; increment once for each committed content change. |

1C imposes no application-level body byte cap tied to radio capacity. Storage
resource failures are reported, not handled by truncating text. A draft can be
larger than one datagram. `bodyUtf8ByteLength` is derived from encoding `body` as
UTF-8, rather than counting characters or Dart string code units. It excludes
future article encoding, signatures, and chunk overhead. If later cached, the
byte count must update in the same transaction as the body.

An update supplies the expected `revision`; a mismatch returns `conflict` and
preserves the saved version. Title, body, updated time, revision, and any cached
derived count change atomically. Saving unchanged title/body is a no-op and
keeps the revision/time. Revision identifies local modifications only; it makes
no collaborative-editing or network-merge promise. Delete is explicit hard
deletion by ID and expected revision; a missing record returns `not_found`.
There is no automatic draft retention limit, publication side effect, tombstone,
or undo/history service in 1C.

## ConnectionProfile

A profile is an offline preset for **one** existing operation: `send`, `listen`,
`ping`, or `respond`. This gives required/irrelevant fields the same meaning as
today's command options. Saving validates a complete preset for that operation,
except for the current explicit port and per-run content, which are supplied at
execution. Names need not be unique; selection uses ID.

| Field | Logical type / nullability | Meaning, constraint, and generation/default |
| --- | --- | --- |
| `id` | Local ID, required | Core-generated, immutable. |
| `name` | String, required | Nonblank display name; preserve nonblank text; reject whitespace-only input. |
| `operation` | Stable operation code, required | One of the four finite datagram operations; supplied explicitly. |
| `portHint` | String?, optional | Default null; if present, nonblank exact local path, preserved unchanged. Only a location hint. |
| `sendChannelIndex` | uint8? | Required for send/ping/respond; absent for listen. No default slot. |
| `receiveChannelIndex` | uint8? | Required for listen/ping/respond; absent for send. No default slot. |
| `routeDescriptor` | uint8? | Required for send/ping/respond; absent for listen. Local outgoing route for send/ping, local return route for responder. No inferred route. |
| `path` | Byte sequence? | Present with a route, defaults to empty there; otherwise absent. Exact encoded path validated by the existing route helper; no saved raw frame. |
| `localTestId`, `peerTestId` | uint32? each | Both required, distinct and nonzero for ping/respond; absent otherwise. Local test labels, not authenticated device identities. |
| `dataType` | uint16? | Required 1..65535 for send; optional 0..65535 filter for listen (null = all); absent for ping/respond, whose diagnostic type is fixed. |
| `requestTimeoutSeconds` | Integer, required | Default 5, range 1..86400; initialization and ready-state send/read budget (`--timeout`). |
| `initializationTimeoutSeconds` | Integer, required | Default 15, range 1..86400; total initialization budget. |
| `startupDelayMilliseconds` | Integer, required | Default 0, range 0..86399999; strictly less than initialization timeout in milliseconds. |
| `taskTimeoutSeconds` | Integer, required | Explicit 1..86400; no application-task default. Excludes actual cleanup/output. |
| `responseTimeoutSeconds` | Integer? | Explicit 1..86400 for ping only. |
| `listenDurationSeconds` | Integer? | Explicit 1..86400 for listen/respond only; finite window after ready. |
| `maxEntries` | Integer? | Default 128, range 1..4096 for listen/ping/respond; absent for send. Includes ordinary and filtered traffic. |
| `maxResponses` | Integer? | Default 1, range 1..4096 for respond only; counts attempts. |
| `updatedAt` | UTC instant, required | Core clock on creation or any changed preset save; unchanged save is a no-op. |

`routeDescriptor`/`path` describe the one route used by the selected local
operation. The PING peer's return path is configured independently on the
responder endpoint, not inferred or installed by this profile. Send `0xFF`
requires an empty Flood path; `0x00` is zero-hop Direct with an empty path;
other supported Direct descriptors require their exact path. Receive metadata
is not a return route. Use the current public
`maxChannelDataPayloadLengthForRoute` /
`maxDiagnosticContentLengthForRoute` validation and capacity rules from the
[datagram contract](../protocol/channel-datagrams.md); do not invent a new route
formula or communication ability.

Profiles do not contain raw payload/PING content, nonces, keys, credentials,
radio configuration writes, or product TCP/WebSocket settings. The development
openHop peer remains a separate acceptance tool, not a supported product
transport. FIFO capacity and reception batch defaults remain 8; responder cache
policy remains 128 records/two minutes. They are not new tunable preset fields.

Create/read/edit/delete never probe devices or modify radio configuration.
Profile edits are atomic replacements validated for their operation; changing
operation must also replace/clear incompatible fields. Deleting a missing ID
returns `not_found`. A profile delete clears `AppSettings.defaultProfileId` in
the same transaction if it references that profile. It never deletes diagnostic
history or changes a run's snapshot. Retain a run's historical profile ID as an
optional association even if the profile is later deleted; it is not a required
live reference and has no cascading delete.

Effective parameters follow this order:

1. Parameters explicitly supplied for this invocation.
2. The explicitly selected profile, or the default profile if none is selected.
3. Existing program defaults, only for fields that currently have defaults.

This profile selection applies to the four finite datagram operations; it does
not add preset behavior to other commands. The current device invocation still
**requires an explicit nonblank `--port`**. Neither
`portHint`, the default profile, environment/history lookup, nor a last-used
port may satisfy that requirement or authorize connection at startup. Forward
the explicit nonblank path unchanged. Selecting a profile for a different
operation is invalid input; it does not silently change the command. A missing
selected/default profile is an explicit reference error, not a fallback.

The CLI distinguishes explicitly parsed options from parser-inserted defaults
when merging. Core validates typed profiles and the fully merged effective
configuration without I/O; CLI owns lexical parsing and explicit-port
enforcement. Validate route/content capacity and all cross-field constraints
before transport construction. In particular, per-run send/ping still requires
exactly one content input (explicit empty is valid). Irrelevant explicit CLI
options stay invalid. Earlier applicable deadlines still win; task timeout may
be shorter than other budgets. No protocol parameters or timeout defaults change.

## AppSettings

One typed settings value exists per database. It is not an arbitrary key/value
framework and has no user-visible record ID.

| Field | Logical type / nullability | Meaning, constraint, and default |
| --- | --- | --- |
| `defaultProfileId` | Local profile ID? | Default null. A nonnull value must reference an existing profile when saved. Supplies parameter selection only; never starts a device task. |
| `diagnosticHistoryLimit` | Integer, required | Default 1000; allowed 1..100000 as an adjustable application policy, independent of protocol limits. |

Absent settings use the documented defaults. Wrong types, out-of-range values,
and invalid profile references are rejected without changing prior settings;
do not silently coerce or clamp them. A dangling persisted default reference
is reported as `not_found`, rather than choosing a different profile. Normal
profile deletion atomically clears it to null. Settings changes commit atomically;
reset explicitly restores defaults rather than deleting unrelated business data.
Changing the history limit schedules bounded eligible-history pruning as
described below; it never removes active runs or drafts. No theme, account,
notification, sync strategy, or future UI settings are introduced in 1C.

## DiagnosticRun

The initial scope is a single finite summary per existing `datagram
send/listen/ping/respond` invocation requested for recording. There is no packet
event table, persistent responder replay cache, or infinite log stream. The
future CLI entry is an explicit `--record` option; neither it nor profile/data
directory options exist in the current CLI. Step 1 leaves all current commands
unchanged.

| Field | Logical type / nullability | Meaning, constraint, and generation/default |
| --- | --- | --- |
| `runId` | Local ID, required | Core-generated before registration, separate from protocol nonce/request ID. |
| `operation` | Stable operation code, required | send/listen/ping/respond. |
| `appVersion` | String, required | Host-supplied actual application version at registration, not a future target or database version. |
| `profileId` | Local profile ID? | Optional historical association; default null. Never required to interpret the run. |
| `configuration` | Typed safe snapshot, required | Immutable effective configuration at registration, using the whitelist below; not a live profile lookup. |
| `preparedAt` | UTC instant, required | Core clock when registration is prepared for commit. Proves only that registration committed once save succeeds. |
| `logicalEndedAt` | UTC instant? | Default null. Set when the app observes a final logical result; not actual cleanup end or exact RF end. Never synthesized during recovery. |
| `recordState` | Stable code, required | Initially `prepared`; `settled` after final logical save; `recovered_archived` for a prior incomplete lifecycle archived under exclusive ownership. |
| `result` | Operation-specific safe facts? | Default null. Partial confirmed facts may exist; final reason/stage is saved only from logical settlement. Unknown fields remain null/absent as specified below. |
| `cleanup` | Typed cleanup summary, required | Initially unconfirmed. Independent core and host cleanup facts, failure summaries, and aggregate state; rules below. |
| `recoveredAt` | UTC instant? | Default null; first recovery observation, separate from task end. |
| `recoveryReason` | Stable code? | Default null; `interrupted` or `cleanup_unconfirmed` when recovery archives a residual record. |
| `diagnosticSummaryFormatVersion` | Positive integer, required | Initially 1; version of the persisted/exportable summary vocabulary. |

Only the recording coordinator changes lifecycle/result/cleanup facts. Historical
operation, version, configuration, and original timestamps are immutable. A
caller cannot edit a failed run into success. Final result fields become
immutable once committed; updates may only add independently settled cleanup or
recovery facts. Deletion/pruning is permitted only for the eligible terminal
records defined under retention. A missing requested run returns `not_found`.

### Configuration and result whitelist

The configuration snapshot stores applicable local send/receive slot numbers,
data type/filter (including null = all), route descriptor and **path byte count**,
command/init/startup/task/response/listen budgets with their named units,
max-entry/max-response limits, and send payload or PING content **byte length**.
It also records app target 3, the fixed diagnostic wire version/type when
applicable, and effective FIFO/reception-batch/cache policy values where used.
It contains enough information to interpret limits and outcomes; it cannot
replay the operation. The snapshot does not copy profile names, port paths,
exact path bytes, endpoint test IDs, content, or secrets. `profileId` is a local
association outside that snapshot and is omitted from default export.

The shared core mapper uses typed results, not stdout parsing or recursive
serialization. The current CLI projections are a reviewed starting whitelist,
not an instruction to persist the CLI envelope or whole session object.

| Scope | Facts to retain when known/applicable |
| --- | --- |
| Logical result | Stable task/operation reason and stage; primary failure classification separately from cleanup. Core `DiagnosticTaskReason` and `DiagnosticTaskStage` keep their existing meanings. Raw send/listen use their existing session/reception facts and the coordinator's finite operation reason; no invented core task enum is required. |
| Send / PING send / responder `lastSend` | `attempted`, `pendingAtTermination`, nullable `dispatched`, `localWriteCompleted`, `localOkObserved`, and `deviceAcceptanceConfirmed`. For a frozen command failure also retain that command's opcode and `matchingResponseObserved`, with the separately classified root session failure. For a send, that matching response is OK, not PONG. |
| PING only | `matchingPongObserved`, `exactContentValidated`, `roundTripSucceeded`, `firstMatchingPongElapsedUs`, `applicationRttUs`, `matchingPongDuplicates`. |
| Responder only | `listenStopReason`, `responseAttempts`, `localResponsesConfirmed`, `duplicates`, `conflicts`, `cacheCapacityRejections`, `returnCapacityRejections`, and `lastSend`. No synthetic PING round-trip fields. |
| Reception where available | Nullable reception summary with reason, `publishedEntries`, `dispatchedReads`, `completedReads`; separate `processedEntries`. Completed reads include success or failure. Do not turn missing reception into an invented observed empty reception. |
| Raw listen only | Its final `receptionReason`, `publishedEntries`, `processedEntries`, `matchingDatagrams`, `filteredDatagrams`, `ordinaryMessages`; bounded scalar counts only. No per-datagram event list. |
| Failure summaries | Controlled `domain`, `kind`, `stage`; optional session kind/stage, command/expected-response opcode, device error code and controlled error name. Preserve separate command-failure facts if a queued send failed because a different read/command failed first. |
| Cleanup | Core/task or raw-session state, host subscription cleanup state, aggregate state, and finite safe failure summaries/counts by scope. No exception messages or recursive objects. |

The adapter maps controlled codes explicitly from the existing types and
coordinator outcomes. Nullable facts preserve uncertainty. A present final
`DiagnosticSendFacts` has nonnull attempted/pending/acceptance booleans, but its
three confirmation booleans remain nullable as supplied. Before a final result
exists, missing send/observation/count fields are unknown, not false/zero.
The current raw-listen final projection uses zero counts if reception never
started; a saved final result may retain that actual final counter snapshot,
with a null reception reason. It must not be confused with a missing result.

`deviceAcceptanceConfirmed: false` means acceptance was not confirmed, not
proof that the device rejected the request or no RF emission occurred. A false
write-completion fact likewise does not prove that no bytes reached the device.
OK plus failed write is not confirmed acceptance. A matching PONG observed before
local failure keeps both observation/validation flags and its first elapsed
value; `roundTripSucceeded` is false and `applicationRttUs` is null. Successful
PING RTT is the core monotonic high-level round trip, including FIFO/host waits,
not airtime. Responder counts are cumulative; `lastSend` describes only its last
attempt. Zero-response normal responder completion proves no round trip.

The current task API has no public per-send progress stream. Step 1 does not
promise continuous partial-fact persistence or add listeners to obtain it. If a
coordinator already has confirmed typed facts before final settlement, it may
commit a bounded partial summary. Recovery preserves exactly those facts and
does not fill in missing observations or counts. Finalization uses the
authoritative frozen result and must not discard independently confirmed facts.

## Diagnostic recording and storage failures

Current `task.done` waits for logical settlement and freezes a result without
waiting for native release. At its terminal gate the task already calls
`session.close()` immediately. `task.cleanupDone` waits for that actual close
and task-owned subscription cancellations; native cleanup can remain pending
indefinitely. Raw send/listen are currently composed in `meshctl`, and their
final report is built after cleanup. Later recording must capture their logical
settlement through the existing session/reception APIs before awaiting cleanup;
it must not depend on waiting for that final CLI report.

The recording coordinator follows this order:

1. Parse and validate invocation syntax without device I/O; acquire directory
   ownership and open/recover storage. Load any selected profile/settings, merge
   parameters, and validate the effective configuration without device I/O.
   Commit the `prepared` run and its immutable safe snapshot **before starting
   the recorded device operation**. Register before transport construction so
   registration failure has no device effects.
2. Attach observers for both logical and cleanup outcomes before starting the
   existing task/session operation. Use its ownership and cancellation APIs;
   never add a transport listener, independent inbox reader, or retry loop.
3. On logical settlement, promptly commit `result`, `logicalEndedAt`, and
   `recordState = settled` in a short transaction. Do not wait for actual
   native cleanup to take this save opportunity.
4. Independently capture actual core and host cleanup settlement and commit
   their facts in another short transaction. A host registers its required
   cleanup scopes before starting. Aggregate cleanup is terminal only when all
   required scopes have settled; no required host scope means `not_required`.
5. Return/report separate logical result, cleanup result, and persistence result.
   A complete success report for a recorded command requires committed required
   saves as well as the existing cleanup/output success conditions.

For each cleanup scope use stable `unconfirmed`, `pending`, `not_required`,
`succeeded`, `failed`, or recovery-only `unconfirmed_after_exit` as applicable.
Task `notStarted` maps to unconfirmed, not successful release; task `notRequired`
maps only when actually confirmed unclaimed. Record pending only from actual
ownership/cleanup knowledge. The aggregate starts unconfirmed and remains pending
while any required live scope is unsettled, even if another scope has failed.
After all scopes settle, it is failed if any failed, not_required if all are
not_required, and otherwise succeeded. Recovery with unresolved scopes uses
unconfirmed_after_exit for the aggregate. Always retain observed failures by
scope, including alongside an unresolved scope. An actual task cleanup success
and a later CLI-subscription failure therefore remain separately interpretable.

Serialize writes per run through one coordinator and use field-specific,
idempotent transitions. Attach both observers immediately because cleanup may
settle before `done` is delivered. Buffer that cleanup fact if needed, commit
the logical snapshot first, then merge cleanup without replacing the row with
an older snapshot. Duplicate identical updates are no-ops; conflicting final
updates are `conflict`. A stored terminal scope never returns to pending, and
an old logical save cannot overwrite `cleanup = succeeded` with pending. Do not
implement this ordering as an event store. The host holds directory ownership
until device cleanup and outstanding recording work have settled and the
database is closed, including while native cleanup is pending.

If the initial registration cannot commit, do not start the recorded device
operation. After device work has occurred, a save failure leaves acquired typed
facts available in the in-process call result and reports persistence failure
explicitly. Continue necessary cancellation and every safe cleanup step;
storage failure cannot block that work or justify resending. Observing cleanup
must not depend on a successful result write. A known cleanup outcome may still
be saved by a later short update if storage permits, without asserting that an
unsaved logical outcome was persisted. The composite call reports which saves
committed; it never promises to reliably write a storage-failure record into
the same failed database or recover unsaved in-memory facts after process exit.

No transaction spans open/connect, a wireless wait, task lifetime, or native
cleanup. Registration, logical result, cleanup, and retention use short
transactions. Recording changes none of 1B's response association, deadlines,
cancellation, cleanup ownership, or no-retry behavior. A CLI exit code or a
single success flag cannot reconstruct these independent facts.

## Data directory, ownership, and restart recovery

The host chooses a persistent platform-appropriate default data directory and
will allow an explicit `--data-dir` for isolation. It must not derive storage
from cwd or place it inside source trees or executable bundles. Directory
resolution is implemented later, not in Step 1. Two test endpoints/processes use
separate data directories.

Exactly one active business process may own a data directory, and exactly one
coordinator within that process owns its database lifecycle. Every entry that
opens the business database and performs recovery, including history/export
and offline draft/settings commands, first acquires the **same exclusive
directory ownership**. Canonical directory identity must make equivalent paths
share that ownership boundary. Contention fails immediately as
`data_directory_busy` in the initial policy; no indefinite wait. Lockfile
existence alone is not proof of a live owner. An abandoned marker must not
permanently block recovery, and deleting a marker must not authorize a second
owner. The OS ownership mechanism/dependency is chosen and verified in 1C.3;
there is no lease, heartbeat, or cross-process notification protocol here.

Acquire ownership before opening/migrating/recovering; retain it through database
close and safe resource settlement. Failure to acquire ownership permits no
recovery or business database mutation. Never mark a live owner's runs as
interrupted. Read-only business queries follow the same ownership rule in 1C;
do not add a concurrent reader exception that also performs recovery.

Recovery runs once after a supported database opens under exclusive ownership,
in short atomic updates, before new work is admitted:

| Persisted residual | Recovery result |
| --- | --- |
| Registered, no final logical result (`prepared`) | Set `recordState = recovered_archived`, `recoveryReason = interrupted`, and `recoveredAt`. Execution result remains unconfirmed, even if exit occurred before actual start. Keep `logicalEndedAt` null; do not infer transmission. |
| Final logical result saved, cleanup not terminal | Preserve result and `logicalEndedAt`; archive with `recoveryReason = cleanup_unconfirmed` and `recoveredAt`. Mark only unresolved cleanup scopes `unconfirmed_after_exit`. This means last process release was not confirmed, not that cleanup failed. |
| Logical result and all required cleanup outcomes saved | Preserve the record, including actual cleanup failures; no recovery timestamp or invented interruption. |
| Some confirmed facts already saved | Preserve every such fact in either incomplete case. Unknown fields stay unknown. If cleanup was independently saved before an unsaved logical result, keep that actual cleanup outcome while archiving the unknown execution result. |
| Already `recovered_archived` | Preserve the first recovery timestamp/reason and facts; reopening is idempotent. |

For the first row, unresolved cleanup scopes also become
`unconfirmed_after_exit`; confirmed `succeeded`, `failed`, or `not_required`
scopes remain intact. Recovery does not set a core task enum to a new value,
invent an actual end time, or count a missing PONG as false. It never replays
requests, resends PING, restarts a responder, consumes inbox entries, or restores
a radio-send queue. `recoveredAt` records recovery observation only.

## Versions, migration, and errors

Keep these independent version domains:

| Name | Meaning and initial value |
| --- | --- |
| `databaseSchemaVersion` | Logical name for database structure metadata; the first real Drift database begins at 1 in 1C.3, with a saved schema snapshot. Physical representation is chosen there. |
| `diagnosticSummaryFormatVersion` | Version 1 for the safe summary fields, status vocabulary, and structured export envelope described here. Independent of table layout. |
| `cliOutputSchemaVersion` | Documentation name for the existing CLI wire-output version; its current JSON field remains `schemaVersion: 1`. This step does not rename/change CLI output. |

`appVersion` and the diagnostic wire protocol version are separate again. Do
not reuse one ambiguous `schemaVersion` for database, summary, and CLI contracts.
Explicit mappings freeze stored state/reason/error identifiers independently
of Dart enum ordering or spelling changes.

The database implementation owns migration execution under directory ownership.
The next real structural change increments `databaseSchemaVersion`, adds a
migration and schema snapshot, and verifies old records survive. Summary format
changes get their own compatibility handling without assuming the database
version identifies the summary. Step 1 creates no schema/migration files and
requires no artificial v1-to-v2 change without a business need.

Unsupported higher database versions and corrupt databases fail explicitly,
preserving the original files and associated SQLite files. Do not delete/rebuild
the database, silently downgrade it, or switch to memory storage. Opening and
migration errors are visible to the host; a failed startup never admits device
work that requires recording.

Business/storage calls use stable categories with safe structured details:

| Category | Meaning |
| --- | --- |
| `invalid_input` | Invalid typed value, combination, limit, or cursor. |
| `not_found` | Requested record or required profile reference does not exist. |
| `conflict` | Expected revision mismatch, conflicting final lifecycle write, or attempt to mutate protected active history. |
| `data_directory_busy` | Another owner, including another owner in the same process, holds the directory. |
| `storage_open_failed` | Directory/database/executor cannot be opened or initialized. |
| `storage_read_failed` | A query cannot complete. |
| `storage_write_failed` | Required mutation/commit cannot complete. |
| `unsupported_database_version` | Database structure version is newer than supported. |
| `database_corrupt` | Storage reports corruption or a stored business representation is invalid. |

Recognized version/corruption categories take precedence over a generic open/
read/write category. A valid representation with a missing referenced record
uses `not_found`; it is not silently repaired to a different selection. No raw
SQLite exception/stack is part of a default diagnostic summary or export.

CLI integration retains the [existing exit-code and primary-failure contract](../cli.md#new-machine-schema-and-exit-precedence):
64 input, 69 expected device/task/cleanup failure, 74 output failure without an
earlier primary cause, 130/143 effective cancellation, and 70 unexpected process
error after safe cleanup. An already committed non-canceled task failure keeps
priority over a later signal/output event; successful task results remain
successful facts even if cleanup, output, or persistence makes the command fail.
1C.8 assigns business/storage errors within that existing code system and tests
their priority, without one exit code per SQLite error. A required save failure
must be explicit and must prevent overall recorded-command success; it is never
reported as a wireless failure, nor allowed to erase an earlier primary failure.

## Privacy, retention, query, and export

Draft bodies are explicitly saved user content. Diagnostics use the separate
allowlists above. Never default to serializing entire sessions, responses,
exceptions, stack traces, or profile objects. Do not save raw radio/serial
frames, raw diagnostic payloads, ordinary chat bodies, channel keys, private
keys, openHop credentials, argv, full nonces/test IDs, device names/coordinates,
or public-key prefixes in diagnostic history. Profile port hints and exact route
paths are local configuration; a local database is not automatically a public
report. 1C does not provide encryption or key management.

History queries are bounded with the shared cursor policy and may filter by
operation, record state, and UTC registration range. Summary export is a bounded
JSON object with `diagnosticSummaryFormatVersion: 1`, `exportedAt`, and a `runs`
array in history order. Each run carries the safe lifecycle/result/configuration
fields, its summary version, local run ID, and recovery facts. Preserve meaningful
nulls. Export omits `profileId` and profile/local connection information, especially
port paths and exact route bytes. It includes no drafts or per-packet events.
Large exports require explicit successive bounded selections using the history
cursor; do not materialize an unlimited history in memory. The safe format is
versioned independently of DB rows and existing CLI output. It is neither a
database-file export nor a restorable backup/import format.

The default terminal-history limit is 1000, adjustable through the typed setting.
Eligible records are either (a) logically settled with every required cleanup
scope terminal (`succeeded`, `failed`, or `not_required`), or (b)
`recovered_archived`. Keep the newest eligible records by
`preparedAt DESC, runId DESC`; prune the oldest excess records in short bounded
transactions after terminal/recovery updates, after a limit change, and at the
next open until the policy is satisfied. The limit counts eligible records only;
total history may exceed it while runs are active or waiting for cleanup.
Partial failures during pruning are reported and can be retried on the next
open; they do not undo already committed diagnostic results. Pruning never
touches active/prepared runs, settled runs still awaiting live cleanup, drafts,
profiles, or settings. Explicit history deletion follows the same eligibility
guard. Drafts remain until explicitly deleted by their separate business API.

## Required acceptance scenarios for subsequent steps

The following are **requirements, not tests executed or passed in 1C.1**.
In-memory tests cover validation, mapping, atomic failure, ordering, and bounded
query behavior. Real-file reopen tests cover committed persistence and migration
compatibility. A small number of controlled child-process tests cover ownership
and interruption windows; they do not simulate every hardware crash. Device
operations use fake transport/session seams for this contract's acceptance,
with no port enumeration or RF activity required.

| Scenario | Expected observation | Later validation responsibility |
| --- | --- | --- |
| Offline draft with Chinese text, emoji, mixed newlines, and a body larger than one datagram | Create/edit with no transport; close and reopen a real file; exact title/body, local ID, revision and timestamps persist. Derived UTF-8 length counts bytes and exceeds radio capacity without blocking save. | Core draft API, 1C.4; real-file reopen. |
| Fail a draft update affecting related fields | Old title/body/time/revision and cached count, if any, remain together; no half update. Stale expected revision returns conflict. | Core transactions, 1C.4; controlled write failure and reopen. |
| Edit/delete a profile used by an old run | Old configuration snapshot/result remains unchanged and interpretable. Deletion clears the default setting atomically and never cascades into history. Missing explicit port still prevents any device task. | Core profiles/settings, 1C.5; CLI explicit-selection checks in 1C.8. |
| Exit after `prepared` commit but before task start | Recovery archives interruption with unknown execution and null `logicalEndedAt`; it claims neither start nor RF transmission. `recoveredAt` is separate. | Core recovery, 1C.6; real-file controlled child exit. |
| Exact PONG observed, then local task/send fails | Observation/content validation and first elapsed microseconds survive alongside failure and send facts; no successful application RTT is invented. | Shared mapper, 1C.6; existing typed-result/fake-transport behavior. |
| Logical PING round trip succeeds but cleanup fails | Saved round trip/RTT remain successful; actual cleanup failures are separate; composite caller/CLI does not report complete success. | Coordinator 1C.6 and CLI 1C.8; controlled cleanup Future. |
| Exit after logical save while cleanup is unconfirmed | Reopen preserves logical result/end time; only unresolved cleanup becomes unconfirmed after exit. Existing partial confirmations survive; recovery is idempotent. | Recovery 1C.6; real-file controlled child exit. |
| A save fails after device work | Typed facts remain available to the caller, persistence failure is explicit, all necessary cleanup still runs, and send count does not increase. Initial registration failure instead produces zero device starts. | Coordinator 1C.6 and CLI 1C.8; injected storage failure. |
| Second process targets the same data directory | It fails ownership promptly and cannot open/recover/rewrite the first process's active run. After actual owner exit, recovery can proceed; separate directories can operate independently. | Directory lifecycle 1C.3; controlled two-process test. |
| Export and retention with active history and drafts | Parsed versioned JSON contains only allowed fields, preserves nulls and distinguishes result/cleanup; no forbidden field/value leaks. Pruning bounds eligible terminal history while preserving drafts and active/waiting-cleanup records. | History/export 1C.7; mapping fixtures, bounded query and real-file checks. |
| Cleanup settles before logical callback; duplicate/stale writes arrive | Final scope facts do not regress; logical commit and later cleanup merge preserve both outcomes; conflicting final update fails explicitly. | Coordinator 1C.6; controlled Futures, no wall-clock sleep. |
| Settings, pagination, and unsupported/corrupt storage | Invalid setting/limit/cursor leaves prior values intact; tied timestamps paginate deterministically. Newer/corrupt database fails clearly with original files retained and no memory fallback. Later real migrations retain prior business data. | Core 1C.3–1C.7; in-memory checks plus real-file compatibility/failure cases. |

The existing [testing guide](../testing.md) remains the software/native regression
entry point. Later 1C delivery must also check native SQLite assets and complete
relocated bundles rather than inferring native compatibility from pure Dart
interfaces. Step 1 adds no tests, database, generated code, dependency resolution,
native build, hardware check, or new 1A/1B acceptance claim.

## Implementation handoff

| Step | Input and bounded responsibility |
| --- | --- |
| 1C.2 | Create `meshchan_core`, add the workspace member, choose compatible Drift/SQLite dependencies and a minimal interface skeleton from these four objects and error categories. Preserve the one-way link dependency and host-supplied storage resources. No domain expansion. |
| 1C.3 | Implement real schema 1/snapshot, directory/database connection lifecycle, one exclusive owner before open/recovery, unsupported/corrupt failure behavior, and the migration baseline. Select physical UTC representation and lock mechanism; verify real-file lifecycle and ownership. |
| 1C.4–1C.5 | Implement drafts, revision/atomic save rules, operation-specific profiles, and the two typed settings. Verify offline behavior, reopen, deletion/reference behavior, and merged validation. |
| 1C.6–1C.7 | Implement typed diagnostic mapping/registration, independent logical/cleanup saves, recovery, bounded history/retention, and safe versioned export. Verify failure/race/interruption scenarios above. |
| 1C.8–1C.9 | Implement CLI business entry points, explicit profile/port and data-directory composition, the proposed `--record` entry, and error/output mapping; complete regressions, native/relocated-bundle acceptance, and the intended dev.3 version delivery. |

This contract is the input to 1C.2. Interface spellings, database physical layout,
dependency versions, and the ownership primitive are implementation decisions
owned and validated by those named steps; they do not leave business semantics
open. Step 1 ends with document/link/whitespace review and does not start 1C.2.
