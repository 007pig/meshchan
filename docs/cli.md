# Meshctl diagnostics

The CLI includes the 1A `ports`, `port-check`, `info`, and `watch` diagnostics
and the 1B.7 finite `datagram send/listen/ping/respond` commands. 1B.8 adds
[shared serial-byte source/AOT acceptance](testing.md#datagram-cross-layer-coverage-audit-1b8)
and [software evidence](development.md#1b8-software-validation-on-november-10-2026).
The application version is `0.1.0-dev.3`. Real-device Direct tests established
exact round trips in both directions, the binary boundary, and no-responder
timeout. H2 local acceptance and H7 active cancellation subsequently passed an
explicitly authorized B-command-15-second/A-5-second comparison, retaining all
earlier failures. Product defaults are unchanged. See the
[actual matrix](hardware-validation.md#direct-rf-matrix-on-november-10-2026)
and [local dev.2 candidate](releases/phase-1b-dev2.md).

From the repository root, use the existing Homebrew SDK on this Mac:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" pub get --enforce-lockfile
cd apps/meshctl
"$MESHCHAN_DART" run bin/meshctl.dart --help
"$MESHCHAN_DART" run bin/meshctl.dart info --help
"$MESHCHAN_DART" run bin/meshctl.dart watch --help
"$MESHCHAN_DART" run bin/meshctl.dart datagram --help
"$MESHCHAN_DART" run bin/meshctl.dart datagram ping --help
```

Build with `"$MESHCHAN_DART" build cli --target=bin/meshctl.dart --output=build/dist`.
Then `build/dist/bundle/bin/meshctl` is equivalent to the source invocation.
Distribute the entire bundle, including its native library. Source invocations
may emit native build-hook diagnostics before the application starts.

## Offline business commands and storage (1C.8)

The product CLI now imports `meshchan_core` through its public entry. These
commands and opt-in recording blocks extend CLI `schemaVersion: 1`. Database
schema/snapshot 1 and `diagnosticSummaryFormatVersion: 1` are independent and
unchanged. The current `0.1.0-dev.3` local candidate is described in the [1C delivery record](releases/phase-1c-dev3.md).

Put the global directory option before the command:

```text
meshctl --data-dir /absolute/path/to/data draft list --json
meshctl --data-dir /absolute/path/to/data datagram ping ... --record --json
```

An explicit path must be nonblank and contain no NUL. Its characters are
preserved; relative explicit paths resolve against the caller's cwd. Defaults
never depend on cwd, source location, executable location or the bundle:

| Host directory policy | Default |
| --- | --- |
| macOS | `$HOME/Library/Application Support/meshchan` |
| Linux | Absolute, nonblank `$XDG_DATA_HOME/meshchan`, otherwise `$HOME/.local/share/meshchan` |
| Windows | Absolute `%LOCALAPPDATA%\meshchan` |

Home/base must be usable and absolute; unavailable bases or other platforms
require `--data-dir`. These are directory policies, not new platform/native
support claims. Existing serial enumeration/Windows safety guards still apply.
Only macOS arm64 source/AOT business execution was validated for this step.

Each business invocation, including history reads/export and **all four datagram
operations without `--record`**, owns at most one `CoreStorage`. Open acquires
core's exclusive canonical directory ownership, preflights, recovers incomplete
runs and requests retention. Contention fails immediately; do not remove markers
or force-unlock. Reads can therefore cause recovery/retention writes. Every
acquired handle is closed and awaited on success, failure and cancellation.
Offline commands never construct transports, enumerate ports or consume inboxes.
Help/version and `ports`, `port-check`, `info`, `watch` bypass business storage.
`--data-dir` is inapplicable to these four legacy commands. All command layers
have `--help`. Syntax/unknown options/extra positionals precede help/version;
normal help/version precede body-file reads, directory policy, storage and devices.

### Drafts, profiles and settings

All leaves below support text and `--json`. Explicit options select IDs; arbitrary
positionals, unrelated options, `--all`, interactive editors and stdin bodies are
not supported.

| Command | Required/optional input |
| --- | --- |
| `draft create` | Optional `--title TEXT`; mutually exclusive `--body TEXT` / `--body-file FILE`; omitted title/body are empty |
| `draft show` | `--id ID` |
| `draft update` | `--id ID --expected-revision N`; at least one explicit title/body source; omitted fields retain saved text |
| `draft delete` | `--id ID --expected-revision N` |
| `draft list` | Page options below; list omits large bodies |
| `profile create` | `--name NAME --operation send|listen|ping|respond`, a complete operation preset, optional `--port-hint PATH` |
| `profile show`, `profile delete` | `--id ID` |
| `profile update` | `--id ID --name NAME --operation OP` and complete replacement preset |
| `profile list` | Page options below; list omits preset details |
| `settings show`, `settings reset` | No business options; reset calls `restoreDefaults()` directly |
| `settings set` | At least one of `--default-profile-id ID` / `--clear-default-profile`, or `--history-limit N`; profile selectors are mutually exclusive |

IDs are core `LocalId` values: exactly 32 lowercase hexadecimal digits. Revisions,
limits and counts use strict unsigned decimal spelling (no sign/space/hex/fraction).
Draft revisions must be positive. Changed updates increment once; unchanged
updates retain revision/time. Stale update/delete returns conflict, even for
unchanged content. The supplied expected revision is never replaced by a read.
Show/update/delete require an explicit `--id` for drafts and profiles; history
show/delete do too. Draft update/delete also require `--expected-revision`.
Omitting a required option returns input error 64 before reading a body file,
selecting a data directory, opening storage or starting any device work. Profile
update never creates a profile when its ID is omitted. Normal help/version
short circuits still work with these values omitted.
Explicit empty title/body clears that field. Titles/bodies are not trimmed,
normalized, truncated, split/rejoined or limited to a radio packet. UTF-8 file
reading is strict: one initial BOM is consumed as an encoding marker, other text,
Chinese/emoji, mixed CR/LF, whitespace and trailing newlines remain exact. Invalid
UTF-8 is input error 64; actual file open/read failure is host I/O error 74.
JSON normally escapes controls; text display escapes terminal controls without
changing stored text. Local draft/profile views deliberately show business
content and are not shareable diagnostic reports.

Profile fields use the datagram option names and lexical rules below. Complete
presets require task timeout and operation-specific channels, route, endpoints,
duration/response timeout. Fields with program defaults use 5/15/0 budgets, empty
path, 128 entries and one response where applicable. `profile update` replaces
all fields, including operation: omitted port hint and listen filter clear old
values. It does not merge a current device/profile snapshot. Profile operations
reject `--port`, `--record`, `--text`, payload/content and incompatible fields.
Names need not be unique. Core validates Unicode, nonblank names and schema-1
NUL compatibility; compatible embedded NUL is retained. Port hints are local
text only and are never probed. Deleting a default profile atomically clears the
reference in core and preserves historical diagnostic snapshots.

The two settings are `defaultProfileId` (initially null) and
`diagnosticHistoryLimit` (initially 1000, range 1..100000). Partial set reads and
preserves the omitted field, reporting any bad old state. An explicit profile
choice/clear together with an explicit limit saves the complete typed object
without first reading old settings. Reset likewise does not depend on an old
broken/dangling reference. Core validates a nonnull reference in the save
transaction. Empty/0/`null` are not clearing aliases. A committed settings save
and its triggered maintenance have independent outcomes.

```bash
# Test-only local examples; replace returned IDs explicitly.
meshctl --data-dir /tmp/meshchan-example-data draft create \
  --title 'Example draft' --body-file ./example-body.txt --json
meshctl --data-dir /tmp/meshchan-example-data draft show --id "$DRAFT_ID" --json
meshctl --data-dir /tmp/meshchan-example-data draft update \
  --id "$DRAFT_ID" --expected-revision 1 --body= --json
meshctl --data-dir /tmp/meshchan-example-data profile create \
  --name 'Example ping' --operation ping --send-channel 3 --receive-channel 2 \
  --route-descriptor 0 --local-id 1 --peer-id 2 --task-timeout 20 \
  --response-timeout 2 --port-hint /dev/EXAMPLE-ONLY --json
meshctl --data-dir /tmp/meshchan-example-data settings set \
  --default-profile-id "$PROFILE_ID" --history-limit 1000 --json
meshctl --data-dir /tmp/meshchan-example-data settings reset --json
```

Draft/profile list accepts `--limit N` (default 50, range 1..200), plus paired
`--after-updated-at UTC --after-id ID`. JSON has `items` and `nextCursor` (object
with `updatedAt`, `id`, or null). Cursor inputs use `YYYY-MM-DDTHH:mm:ss[.ffffff]Z`,
with valid calendar components and at most six fractional digits; offsets,
normalizing overflow dates and excess precision are rejected. Cursor output
always has exactly six fractional digits. A cursor row may have been deleted;
no lookup is required. Pages are separate selections, not a cross-call snapshot.

### Profiles on finite datagrams and opt-in recording

All four finite leaves always resolve parameters through the opened storage.
Priority is explicit invocation values, then explicit `--profile ID` or the
default profile, then program defaults. Presence comes from `wasParsed`, so
parser-inserted defaults do not override a preset. An explicit profile bypasses
unrelated default-reference reads. Missing, mismatched or corrupt selected/default
profiles fail without fallback, even if every explicit override was supplied.
Route descriptor/path merge independently: changing descriptor retains inherited
path until explicit `--path-hex=` clears it. Listen inherits its filter when
omitted; `--data-type 0` filters 0, and listen-only `--all-data-types` clears the
filter (mutually exclusive with `--data-type`).

Every invocation still needs an explicit nonblank `--port`; its original
characters reach the transport factory. Hints, environment, defaults and history
never authorize a port, and no enumeration supplies one. Send/ping also require
exactly one explicit content source, including explicit empty content. Full
merged route/capacity validation precedes transport construction. Task/session
budgets and no-retry semantics are unchanged. For example:

```bash
meshctl --data-dir /tmp/meshchan-example-data datagram ping \
  --profile "$PROFILE_ID" --port /dev/EXAMPLE-ONLY --text 'test content' \
  --record --json
meshctl --data-dir /tmp/meshchan-example-listen datagram listen \
  --port /dev/EXAMPLE-ONLY --receive-channel 2 --duration 5 --task-timeout 10 \
  --all-data-types --record --json
```

`--record` is non-negatable and admits exactly one `CoreStorage.record` operation
with the actual application version. Registration commits before any fresh
transport or subscription-plan factory runs. No-record operations use the old
runner and add no `DiagnosticRun`; recovery and maintenance at open still apply.
There is no second session/inbox consumer, replay, save-driven resend or retry.

**Recorded listen uses summary mode:** `datagram listen --record --json` emits
one final `event: "end"`, without per-datagram or failure stdout events. Immediate
safe logical diagnostics can appear on stderr while native cleanup is pending.
Unrecorded listen retains datagram/failure/end NDJSON. Send/ping/respond always
have one final JSON object. Normal no-record envelopes/fields/line counts are
unchanged when storage has no failure. Storage failures may add independent
status blocks, never a second terminal object.

Recorded JSON has the usual command/operation/reason/exitCode/failure/result,
but its opt-in `result` uses the core typed safe logical projection (including
nullable failure/reception/send command facts). `cleanup` has `aggregate`, `core`
and `hostSubscriptions`, each scope retaining state, failureCount and failures.
`recording` has `runId`, `registration`, `logical`, `cleanup`, `saves`,
`coordinationFailure` and core's `fullySuccessful`. Every save reports `phase`,
`state` (`notAttempted`, `committed`, `failed`), safe `error` and `finalCleanup`.
The three named saves describe the required phase outcomes; `saves` retains the
bounded coordinator attempts, including intermediate cleanup attempts. Failed
registration leaves logical null and later saves notAttempted. These are
persistence facts, independent of device results and actual cleanup.

### History and single-page safe export

| Command | Input and result |
| --- | --- |
| `history list` | One page of safe summaries, `items` and `nextCursor` |
| `history show --id ID` | Safe configuration/result, both cleanup scopes and independent recovery facts; unknowns stay null |
| `history delete --id ID` | One protected core deletion; prepared/active/unsettled records conflict; no force/clear-all |
| `history prune` | One explicit `maintain()` request; `prune` reports completed/deferred/failed, committed `deletedCount`, nullable `historyLimit`, `deferredCount` and safe error |
| `history export` | One `exportSummary()` selection, always raw core JSON on stdout |

List/export share `--operation send|listen|ping|respond`,
`--state prepared|settled|recovered_archived`, `--from UTC` inclusive and
`--until UTC` exclusive, `--limit N` (50 by default, 1..200), and paired
`--after-prepared-at UTC --after-run-id ID`. Filters combine with AND; both
bounds require from < until. Times refer to `preparedAt`. Ordering is preparedAt
DESC/runId DESC. Continuation never requires a live cursor row or collects all
pages. Recovery archives are not labeled wireless failures.

Export stdout is the core JSON object, without double encoding or added fields.
Its only root fields are `diagnosticSummaryFormatVersion`, `exportedAt`, `runs`.
It omits profileId, port/configuration names, exact route bytes, endpoint IDs,
content, nonces, device details, argv, exceptions and stacks. It preserves
six-digit UTC, integer microseconds and meaningful null/false/zero/partial facts.
It is a safe summary selection, **not a backup or import format**.

Export stderr contains one independently parseable JSON metadata line:

```json
{"schemaVersion":1,"command":"history","action":"export","event":"metadata","nextCursor":{"preparedAt":"2026-11-11T12:03:04.567891Z","runId":"00000000000000000000000000000001"},"operationSucceeded":true,"reason":"completed","exitCode":0,"failure":null,"maintenance":{},"storageClose":{"state":"closed","error":null},"hostCleanup":"succeeded","additionalFailures":[]}
```

The example abbreviates maintenance to `{}`; actual fields follow the lifecycle
contract below. No next page is `"nextCursor":null`. Other stderr diagnostics
start with fixed text; select the JSON line with `event == "metadata"`. Source
Dart build hooks can write their own stderr prefix before the application starts.
The metadata cursor is never inserted into stdout. Continue explicitly with the
same filters and both values:

```bash
meshctl --data-dir /tmp/meshchan-example-data history export --limit 50 \
  > example-summary.json 2> example-export-metadata.txt
meshctl --data-dir /tmp/meshchan-example-data history export --limit 50 \
  --after-prepared-at "$PREPARED_AT" --after-run-id "$RUN_ID" \
  > example-summary-next.json 2> example-export-next-metadata.txt
```

The complete page is generated before writing. Query/encoding failure emits no
invented empty runs. A generated summary remains usable if later maintenance or
close fails; metadata reports that failure. stdout writes are not atomic: output
failure can leave a partial object; the process fails and appends no replacement.

### Independent finalization, output and exit codes

Business JSON has `schemaVersion`, `command`, `action`, `operationSucceeded`,
`committed` (true for a returned mutation, false for a failed operation, null for
a successful query/prune/export), `reason`, `exitCode`, `failure`, operation data,
`maintenance`, `storageClose`, `hostCleanup`, `additionalFailures`. Draft/profile/settings use
`draft`, `profile`, `settings`; deletion uses `id`, `deleted`. Text exposes the
same facts with terminal-safe display. These explicit local projections are
separate from the diagnostic allowlists.

`maintenance` contains `latest`, `unacknowledgedFailure`, and
`unacknowledgedFailureCount`. Reports retain state/deletedCount/historyLimit/
deferredCount/error. A later successful pass does not clear an earlier sticky
failure. The CLI never acknowledges failures or requests an implicit retry.
Only explicit `history prune` requests maintenance. Deferred work is normal
protection, not a failure. `storageClose` reports actual `state` and safe `error`;
`closeUnconfirmed`/cleanupUnconfirmed never claim released ownership.

Offline commands latch signals and output failure too: work already admitted to
SQLite settles before close, preserving any committed result. Their
`hostCleanup` is `not_required`, `succeeded` or `failed` for the real signal
subscription; its safe cancellation failure is an additional host fact. A
synchronous pre-admission signal starts no storage operation.
After the storage barrier settles, a known maintenance/close failure selects
`storage_finalization_failure`/74 before signal-subscription cancellation starts,
unless an earlier cause is already latched. A later cancellation failure leaves
that primary intact and reports `hostCleanup: "failed"` plus its safe host error
in `additionalFailures`. Committed data and usable export JSON remain independent
of both failures.
For offline open/operation errors, `failure` describes a business error only when
that error selects the primary reason/code. If SIGINT, SIGTERM or output failure
is already effective, the later core error instead appears in
`additionalFailures` with its stable code/source, in both ordinary envelopes and
export metadata. A failed admitted operation still reports
`operationSucceeded: false` and `committed: false` in ordinary envelopes; moving
its error to the additional list does not change that fact. An export that fails
to generate has no summary JSON, regardless of which cause is primary.

The final barrier observes logical/actual core and host cleanup/all saves,
waits for already requested maintenance while open, retains the history object,
then awaits storage.close. Close covers post-done recording admission/unpin and
its final maintenance as well as the actual DB close. After close starts there
are no new repository/query/maintain/wait calls or reopened owner. Only retained
in-memory maintenance getters are read afterward. Queued output drains before
the unique final object and again afterward. A failed save/maintenance/close
never changes a successful logical/committed fact or the saved task reason.

| Primary condition | Process exit |
| --- | ---: |
| Syntax/lexical/business invalid_input or required reference not_found | 64 |
| conflict (including stale revision/protected delete), data_directory_busy | 69 |
| storage_open_failed/read_failed/write_failed, unsupported_database_version, database_corrupt | 74 |
| Body-file or output I/O; necessary save, independent maintenance or DB close failure without an earlier cause | 74 |
| Expected device/task/actual core or host cleanup failure | 69 |
| Effective external SIGINT / SIGTERM | 130 / 143 |
| Unexpected program/coordination error after safe cleanup, reported at process boundary | 70 |

Core errors expose `domain: "storage"`, controlled `source`, stable `code` and
`cleanupUnconfirmed`, never exception text. New final reasons are
`business_failure`, `host_io_failure`, `recording_save_failure`, `storage_finalization_failure`,
plus existing `completed`, `task_failure`, `cleanup_failure`, `sigint`, `sigterm`,
`output_failure`. An ordinary 74 is not automatically output_failure. Additional
failures retain their own source/domain and cannot erase an earlier primary.

Storage admission and registration follow observation order too. If SIGINT,
SIGTERM or output failure is already effective while open/resolution/prepared is
pending, a subsequently observed storage failure does not replace that reason or
exit code. It retains its stable code/source in additionalFailures; recording
also retains the failed registration/save block and its error. A failed prepared
transaction still has null logical result, later saves notAttempted and no device
start. Conversely, a storage or registration failure observed before a later
signal remains primary. The frozen non-canceled task/session rule below remains
an independent precedence guarantee.

Datagram signal ownership starts after syntax/independent lexical validation,
before storage open. SIGINT/SIGTERM and source errors remain observed during
open, parameter resolution, native cleanup, maintenance and the actual database
close. An admitted storage Future settles before close; a stop latched before
device admission prevents later transport construction or recording. The final
result then has null logical result (and null recording block in record mode),
without inventing a canceled device task.

The invocation owns the real process-signal source until storage finalization
completes, then awaits its actual cancellation Future. The runner/coordinator
owns a separate real forwarding observer. Its cleanup proves observer removal;
it does not claim that the invocation's process watches have been released.
Recorded output adds `signalCleanup: {state, error}` for that independent source
cleanup, with state `notRequired`, `succeeded` or `failed`. A source cancellation
failure prevents exit 0 and appears in additionalFailures without changing saved
core cleanup or fullySuccessful. Unrecorded successful output keeps its existing
envelope; source cancellation failure adds signalCleanup and participates in the
existing CLI cleanup aggregate. Pre-device storage/cancellation results also
include signalCleanup. No source cancellation is requested before the storage
barrier, including when storage close fails.

External intents are latched during synchronous subscription and all pending
cleanup phases; first signal/output intent stays authoritative unless earlier
frozen task/session evidence has priority. A final non-canceled task failure or
retained non-canceled session failure corrects provisional signal/output priority.
Sometimes the task's canceled result still contains the earlier session failure;
the CLI preserves that result and reports the session failure as primary. It
never infers SIGINT from canceled, rewrites a saved result, or waits for native
release before diagnosing logical failure. Later persistence/maintenance/close
failures remain additional facts after effective cancellation. Logical success
with real cleanup failure or required save failure cannot return 0.
`RecordedResult.fullySuccessful` alone excludes invocation signal cleanup, maintenance/DB close/output and
therefore cannot determine process success.

The existing final-flush limitation still applies: an object already written
with exitCode 0 cannot be revised if its flush later fails. The process returns
74 without a second terminal object; the actual process exit is authoritative.
No code awaits an indefinitely open stdout.done. The existing bounded output
queues and independent subscription cancellation Futures remain in use.


## Commands and options

```text
meshctl ports [--json]
meshctl port-check --port <path> [--json]
meshctl info --port <path> [options]
meshctl watch --port <path> [options]
meshctl --help
meshctl --version
```

`ports` lists sorted paths and limited metadata without opening candidate ports.
Existing platform guards remain: native enumeration is rejected on Linux,
Android, and Windows with the pinned serial dependency. Windows explicit-port
operations also retain the native handle safety guard. `port-check` performs
only the existing explicit single-port open/close diagnostic, without a handshake.
See the [platform and transport limits](protocol/serial-transport.md).

`info` performs one initialization and waits for connection cleanup before
printing one complete historical snapshot. Initialization or cleanup failure and
cancellation leave stdout empty. `sessionClosed: true` describes successful
cleanup, not a current connection. `watch` initializes once, prints one complete
ready snapshot, and observes session states and unassociated response summaries
until duration, signal, or failure. Silence is valid and does not prove a
disconnect. Notifications such as `0x83` cause no additional queries and are not
labeled as chat messages. There is no heartbeat, idle timeout, polling, retry,
automatic reconnect, or radio round-trip test.

**Both info and watch send DEVICE_QUERY and APP_START.** These two initialization
commands can change device session state; neither command is passive observation.
Opening/configuring a port can also reset some boards through driver behavior.
The session retains its fixed app target 3 and application name `Meshchan`.
The device's raw protocol code and firmware version text remain separate fields.

Put options after their subcommand:

| Option | Commands | Default and input policy |
| --- | --- | --- |
| `--port <path>` | port-check, info, watch | Required, explicitly selected path. Reject only missing/whitespace-only values; forward any nonblank path unchanged. No enumeration, history, environment lookup, or fallback selects it. |
| `--json` | All four | Off. One JSON object for ports, port-check, info; NDJSON for watch. |
| `--verbose`, `-v` | info, watch | Off. Structural diagnostics on stderr; no raw logging. |
| `--timeout <seconds>` | info, watch | 5; decimal integer 1..86400, per initialization request. |
| `--init-timeout <seconds>` | info, watch | 15; decimal integer 1..86400, covering open, delay, and both requests. Earlier request/total deadline wins. |
| `--startup-delay <milliseconds>` | info, watch | 0; decimal integer 0..86399999, strictly less than the selected total initialization budget in milliseconds. Explicit diagnostic setting. |
| `--duration <seconds>` | watch | Unlimited if omitted; decimal integer 1..86400, starting only after successful ready. |
| `--help`, `-h` | Top level and all commands | Help without diagnostics or session creation. |

Empty, signed, fractional, nonnumeric, and out-of-range time values are rejected.
These are CLI input limits, not radio protocol limits. Request/total budgets do
not limit cleanup or ready-state observation. No app-target, baud, or retry option
is exposed. Syntax and extra positionals are checked first, including with help
or version. Then top-level help, subcommand help, and version take precedence
in that order; only business execution requires a port or valid numeric values.
For example, `info --help` and `--version info` do not touch hardware, while
`--help --unknown` returns 64. No arguments show help. Help remains text with JSON.

## Structured output and privacy

Stdout contains results or watch events. Stderr contains warnings, errors,
stop notices, and optional structural diagnostics. `--json --verbose` preserves
the same stdout schema. JSON uses standard encoding; property order is not a
contract. Each successful non-watch result is one JSON object plus a newline.

Every result has `schemaVersion: 1` and `command`. `ports` has a `ports` array
sorted by `path`, with `path`, `description`, `transport`, `usbVid`, `usbPid`,
and optional `warning`. Missing metadata is null; USB IDs are integers.
Per-port warnings also appear on stderr. A truly empty array succeeds; global
enumeration failure returns 69 with empty stdout. `port-check` has `port`,
`openedAndClosed: true`, and `protocolChecked: false` only after success.

The info object has these fields:

| Group | Fields |
| --- | --- |
| Top level | `schemaVersion`, `command: "info"`, exact `port`, `initializationCompleted: true`, `sessionClosed: true`, `appTargetVersion: 3` |
| `device` | `protocolVersion`, `firmwareVersion`, `firmwareBuildDate`, `hardwareModel`, `maxContacts`, `maxChannels`, `repeatEnabled`, `pathHashMode` |
| `self` | `nodeName`, `advertType`, `txPowerDbm`, `maxTxPowerDbm`, `radioFrequencyKhz`, `radioBandwidthHz`, `radioSpreadingFactor`, `radioCodingRate`, `publicKeyPrefix` |

Optional device fields retain null; unknown codes retain their numbers. Frequency
is kHz and bandwidth is Hz. `publicKeyPrefix` is only the first eight reported
public-key bytes, encoded as 16 lowercase hex characters. It is not an
authenticated identity or a full fingerprint. Text info uses the same field
names (including units), with `-` for null.

Watch JSON is NDJSON: each completed line is an independently parseable object
with `schemaVersion: 1`, `command: "watch"`, and `event`. It never emits an open
array or human notices on stdout.

| `event` | Additional fields |
| --- | --- |
| `state` | `previous`, `state`, from the existing session event. |
| `ready` | Complete info projection above, but `command: "watch"`, `event: "ready"`, and `sessionClosed: false`. This is historical readiness at that moment, not final success. Exactly once. |
| `unassociated_response` | `opcode`, `contentLength`, `stage`, `deviceErrorCode`, `deviceErrorName`; unavailable error fields are null. No payload. |
| `failure` | `kind`, `stage`, `commandOpcode`, `expectedResponseOpcode`, `deviceErrorCode`, `deviceErrorName`; unavailable fields are null. One primary failure record and one stderr diagnosis, deduplicated across events, connect, and lastFailure. |
| `end` | `reason`, `exitCode`, `cleanup` (`succeeded` or `failed`), only after actual cleanup and CLI subscription cancellation. Exactly once if stdout remains writable. |

End reasons include `duration`, `sigint`, `sigterm`, `failure`, `output_failure`,
and `internal_error`. Text watch uses line-oriented state/summary records and
one ready projection, without a full-screen UI, colors, or payload dumps.

Explicit info/ready output includes requested device name/model/version text.
Diagnostics and failure/response records contain only approved structural fields;
causes and stacks are never recursively printed. No BLE PIN, coordinates,
private/channel key, full public key, raw frame, or message content is output.
Text mode escapes newline, carriage return, ESC, and other terminal controls in
untrusted display text and metadata. JSON preserves the original strings through
standard escaping. Actual OS paths and model values are not modified.

## Cancellation, cleanup, and output failure

SIGINT and, on supported systems, SIGTERM request the same awaited session close
used by duration and failures. Windows registers SIGINT only. The first primary
failure/signal wins; repeated signals coalesce. CLI timers stop immediately,
late ready callbacks cannot start observation or print success, and signal
subscriptions are canceled on every completed command path. Help/version and
invalid input never register process signals. The asynchronous entry sets
`exitCode` after cleanup and returns naturally, without `exit()`.

Logical session failure is diagnosed immediately, even if native cleanup is
still pending. Failed state does not imply released resources, and successful
close can leave a failed session in failed state. CLI cleanup waits for the
actual shared close Future, not a closed-state event or events.onDone. Additional
cleanup failure is reported without replacing a prior primary code or claiming
resource release. There is no forced shutdown deadline or pointer release.

| Exit code | Meaning |
| --- | --- |
| 0 | Successful diagnostic/info, or duration completed with successful cleanup/output. |
| 64 | Syntax, required port, or numeric usage error. |
| 69 | Expected serial/platform/session failure, including cleanup failure without an earlier primary failure. |
| 74 | Host/storage/file/output I/O or finalization failure without an earlier primary cause. |
| 130 | SIGINT was the first primary termination reason. |
| 143 | SIGTERM was the first primary termination reason. |
| 70 | Unexpected program error caught only at the process boundary; safe generic diagnostic. |

Actual IOSink.done errors are observed from the start; each queued record is
flushed serially and pending flushes are observed before normal return. Each
channel permits at most 128 active/pending records. Overflow, synchronous write,
asynchronous sink completion, and flush failure request session shutdown. A
broken channel discards its queue and receives no further writes; stderr failure
is not recursively logged to stderr. A broken stdout may have no complete final
line or end record. This bounds only the CLI's own queue, not OS/IOSink buffers.
Flush does not prove downstream processing, and a permanently blocked consumer
can keep flush and command completion pending.

The [historical intermittent 64-byte SELF_INFO body delay](hardware-validation.md#session-timeout-investigation-on-november-9-2026)
remains unresolved. It was reproduced independently outside Dart; this step adds
no repair query, retry, flush, name change, forced reset, or default startup delay.
A larger timeout or explicit delay does not establish a root-cause fix. Native
reader shutdown can also remain pending until exit evidence arrives.

## Manual hardware acceptance

Obtain explicit authorization for this task and select the exact port yourself.
Historical port selections do not grant new access. From `apps/meshctl`, after
building, the examples below use `meshctl` to mean `build/dist/bundle/bin/meshctl`
(or replace it with `"$MESHCHAN_DART" run bin/meshctl.dart`).

```bash
# Only after the user explicitly selects and authorizes this port for this task.
: "${MESHCHAN_PORT:?Set the explicitly authorized port yourself}"
meshctl info --port "$MESHCHAN_PORT"
meshctl info --port "$MESHCHAN_PORT" --json
meshctl watch --port "$MESHCHAN_PORT" --duration 5
meshctl watch --port "$MESHCHAN_PORT" --json --duration 5
```

Record initialized/failed stage, command and expected response codes, final exit
code, and actual cleanup result. Check Ctrl+C during initialization and ready
only under that authorization. Ready proves the existing two-command USB
initialization, not authenticated identity or LoRa. Software tests/builds alone
do not establish hardware acceptance. A separately authorized
[Step 7 CLI hardware follow-up](hardware-validation.md#step-7-authorized-cli-hardware-follow-up-on-november-9-2026)
passed source/bundle watch and ready-state signal cleanup; its initial info
attempts timed out. A later [native CLI timing comparison](hardware-validation.md#step-7-cli-timeout-comparison-on-november-9-2026)
obtained successful info snapshots and reproduced watch timeouts. Captured
timeouts had incomplete native input, without evidence of premature CLI close
or lost complete frames. This does not establish the lower-level delivery cause.
A subsequent [independent POSIX comparison](hardware-validation.md#step-7-independent-posix-comparison-on-november-9-2026)
reproduced the same header-only wait without Dart, libserialport_plus, or reader,
with an empty tty input queue and no bytes available to direct reads at the
deadline. It establishes that those components are not required for the stall;
the specific device/USB/driver cause is still unproven. Linux-host execution and
remote Actions remain unverified.

## Finite datagram commands (1B.7)

The nested commands below use a new transport/session for each invocation. They
keep the existing initialization order, app target 3, version, dependencies,
and the four older command schemas. Put business options after the leaf name:

```text
meshctl datagram send [options]
meshctl datagram listen [options]
meshctl datagram ping [options]
meshctl datagram respond [options]
meshctl datagram --help
meshctl datagram <operation> --help
```

`datagram` without an operation shows group help. Syntax and unexpected
positionals are checked along the entire command chain before any help/version
short circuit. Top-level help wins, followed by group help, leaf help, then
top-level version. Help remains text with `--json` and requires no business
options. Invalid syntax returns 64 even with help/version. Content-command
syntax errors use a generic safe summary rather than quoting parser input.
Independent lexical validation precedes signal registration. Storage-dependent
semantic validation runs while signals are owned, before transport construction.

| Operation | Behavior | `--json` stdout |
| --- | --- | --- |
| `send` | Initialize, send one raw payload, close | One final object, including expected failure/signal outcomes |
| `listen` | Initialize, consume one finite reception, summarize matching datagrams, close | NDJSON `datagram`, optional primary `failure`, and one final `end` |
| `ping` | Run `MeshchanPingTask` once; exact diagnostic PONG validation | One final object, including expected failure/signal outcomes |
| `respond` | Run `MeshchanResponderTask` for a finite window/attempt limit | One final summary object, including expected failure/signal outcomes |

Send success means **local write completed and device accepted**, without proof
of radio delivery. Raw type `0xFFFF` stays raw: the CLI never adds a diagnostic
header to `send`. Ping content excludes the diagnostic header; the task adds it
once and owns nonce generation and application RTT. Responder confirms local
PONG writes/OKs only; even normal completion with zero responses returns 0 and
establishes no wireless validation. Task start acceptance is not readiness.

### Inputs and budgets

These common options apply to all four new leaves:

| Option | Policy |
| --- | --- |
| `--port` | Required, nonblank exact path; forwarded unchanged, including leading/trailing whitespace in a nonblank value. No discovery or fallback. |
| `--json` | Off by default; output types above. |
| `--verbose`, `-v` | Off; safe structural stderr diagnostics, same stdout schema. |
| `--timeout` | Default 5 seconds; decimal 1..86400 for each initialization **and ready-state send/read** command. |
| `--init-timeout` | Default 15 seconds; decimal 1..86400 for the whole initialization. |
| `--startup-delay` | Default 0 milliseconds; decimal 0..86399999 and strictly less than init-timeout in milliseconds. |
| `--task-timeout` | Required decimal 1..86400 seconds, starting at business execution and covering connection and logical operations; excludes actual cleanup and output flush. |

Task timeout may be shorter than another budget. Earlier overall expiration
stops new work and starts cancellation/close; it does not force native release.
No production cleanup or output timeout is added. A pending close or blocked
flush can keep the process pending past the application budget. Old info/watch
timeout behavior remains as documented above.

| Option | send | listen | ping | respond |
| --- | --- | --- | --- | --- |
| `--send-channel` | Required | Rejected | Required | Required |
| `--receive-channel` | Rejected | Required | Required | Required |
| `--data-type` | Required 1..65535 | Optional filter 0..65535; omitted means all | Rejected; fixed diagnostic type | Rejected; fixed diagnostic type |
| `--route-descriptor` | Required | Rejected | Required | Required local return route |
| `--path-hex` | Default empty | Rejected | Default empty | Default empty |
| `--local-id`, `--peer-id` | Rejected | Rejected | Both required | Both required |
| `--payload-hex` or `--text` | Exactly one | Rejected | payload-hex rejected | Rejected |
| `--content-hex` or `--text` | content-hex rejected | Rejected | Exactly one | Rejected |
| `--response-timeout` | Rejected | Rejected | Required decimal 1..86400 seconds | Rejected |
| `--duration` | Rejected | Required decimal 1..86400 seconds after ready | Rejected | Required decimal 1..86400 seconds after ready |
| `--max-entries` | Rejected | Default 128 | Default 128 | Default 128 |
| `--max-responses` | Rejected | Rejected | Rejected | Default 1; counts attempts |

Protocol integers accept strict ASCII decimal or `0x`/`0X` prefixed hexadecimal:
channels and route descriptors are uint8 (0..255), IDs are distinct nonzero
uint32 (1..4294967295), and data types follow the table. Leading decimal zeros
still mean decimal. Signs, whitespace, fractions, underscores, and overflow are
rejected. Times/counts accept decimal only. Both max-entries and max-responses
are restricted to 1..4096 as a CLI resource policy. Session FIFO and reception
batch defaults remain 8; no tuning flags are exposed.

HEX bytes require even-length ASCII `0-9a-fA-F`, without prefixes, separators,
spaces, or half bytes. Explicit empty `--payload-hex=`, `--content-hex=`, or
`--text=` is valid; omitting both content options is invalid. Text is exact UTF-8,
with no Unicode normalization, truncation, newline, or NUL appended. Length
checks use encoded bytes, including multibyte characters.

Route/path validation and capacity use the existing core helpers before I/O.
For operator-confirmed configurations, send descriptor `0xFF` means Flood with
an empty path; `0x00` is zero-hop Direct with an empty path. Other Direct routes
require their exact encoded path length; reserved/oversize routes are rejected.
Raw capacity uses `maxChannelDataPayloadLengthForRoute`; diagnostic content uses
`maxDiagnosticContentLengthForRoute`. The latter is 131 bytes for Flood/zero-hop,
but smaller for longer paths. For example, valid descriptor `0x3F` with 63 path
bytes allows 108 raw bytes or 74 diagnostic content bytes. Respond validates its
local return configuration first, then leaves per-PING return-capacity rejection
and counting to the task. Receive route metadata cannot supply a return path.

### Consumption and cancellation

Listen only subscribes to one reception's entries and never responds. Its
matching channel/type filter runs **after shared inbox consumption**. Other
channels, ordinary chat, and other applications can be consumed and count toward
the same max-entries, including by ping/respond. Chat bodies are discarded by
the codec. A filter cannot protect other consumers' messages. Do not share an
active device inbox with another application expecting those entries.

Listen duration starts when reception is activated after ready; silence ends
normally. Duration/entry-limit success waits for both reception settlement and
entries delivery, including the last published item and read outcome. Failure,
overall timeout, signal, or output failure seals processing immediately and
closes without draining remaining buffered entries or creating a new reception.

Ping/respond exclusively own their session after task acceptance. Signals and
output failure call task cancellation; the CLI never independently closes or
reads their session. Logical task `done` is separate from `cleanupDone`.
A logical failure is diagnosed immediately when observable, while final output
waits for actual native cleanup and all CLI subscription cancellations. No ready
or per-response event is fabricated from start acceptance.

### New machine schema and exit precedence

All four leaves use explicit whitelist projection:

```text
schemaVersion: 1
command: "datagram"
operation: "send" | "listen" | "ping" | "respond"
reason: "completed" | "task_failure" | "sigint" | "sigterm" |
        "output_failure" | "cleanup_failure"
exitCode: integer
cleanup: {state: "notRequired" | "succeeded" | "failed",
          failureCount: integer, failures: [safe failure summaries]}
failure: null | safe failure summary
result: null | operation result
```

Unstarted/unclaimed operations can have null results and `notRequired` cleanup.
A final record never reports pending cleanup as success. Every actual cleanup
failure is counted separately, including CLI signal/observation subscription
cancellation errors. Cleanup failure does not replace an earlier primary cause.
Failures have `{domain, kind, stage, session}`: domain is `task`, `session`,
`cleanup`, or `cli`; kind/stage are controlled classifications or null. Session
is null or the existing `failureFields` whitelist: kind, stage, commandOpcode,
expectedResponseOpcode, deviceErrorCode, deviceErrorName. No recursive cause or
stack is serialized. A task's null failure object does not imply success.

| Result | Fields |
| --- | --- |
| send | `send` facts |
| ping | Core `reason`, `stage`, `send`, `matchingPongObserved`, `exactContentValidated`, `roundTripSucceeded`, `firstMatchingPongElapsedUs`, `applicationRttUs`, `matchingPongDuplicates`, `publishedEntries`, `processedEntries`, `reception` |
| respond | Core `reason`, `stage`, `listenStopReason`, `lastSend`, `responseAttempts`, `localResponsesConfirmed`, `duplicates`, `conflicts`, `cacheCapacityRejections`, `returnCapacityRejections`, `publishedEntries`, `processedEntries`, `reception` |

Send/lastSend facts are `attempted`, `pendingAtTermination`, nullable `dispatched`,
`localWriteCompleted`, `localOkObserved`, and `deviceAcceptanceConfirmed`.
Missing facts remain null. Responder `lastSend` describes only its last send;
responseAttempts/localResponsesConfirmed are the cumulative facts. Reception is
null or `{reason, publishedEntries, dispatchedReads, completedReads}`.
Core responder reason `completed` has a separate listenStopReason of
`durationElapsed`, `responseLimit`, or `entryLimit`.

All elapsed fields ending in `Us` are integer microseconds from core getters.
Application RTT exists only for a successful round trip. An early exact PONG
followed by local send failure retains firstMatchingPongElapsedUs and observation
flags while applicationRttUs is null. This metric includes host scheduling and
FIFO waits; it is not airtime. CLI reason remains separate from core result reason.

Listen emits independently parseable NDJSON lines, each with schemaVersion,
command, operation, and event:

- `datagram`: channelIndex, dataType, payloadLength, snrDb, routeMetadata,
  isDirect. No payload or invented RSSI.
- `failure`: one primary `failure` safe summary; may precede cleanup completion.
- `end`: the final envelope above, with result `{receptionReason,
  publishedEntries, processedEntries, matchingDatagrams, filteredDatagrams,
  ordinaryMessages}`. Without reception, reason is null and counts are zero.

Processed entries include ordinary messages and filtered datagrams. Published
entries can exceed processed entries on immediate termination. Output uses the
existing 128-record per-channel queue, without an unbounded event list.

Exit codes are 0 for the operation's normal finite success plus successful
cleanup/output; 64 for input errors before side effects; 69 for expected
session/task failure or cleanup failure without an earlier primary cause; 74 for
output failure without an earlier primary failure/signal; 130/143 for the first
effective SIGINT/SIGTERM; and 70 at the process boundary for unexpected errors
after safe cleanup. Windows still registers SIGINT only. A core non-canceled
failure already locked before a later signal/output callback keeps 69 even when
`done` is delivered later. A genuinely externally canceled task uses the first
CLI external cause. A core completed result remains completed even if a later
signal/output/cleanup problem changes CLI exit intent.

Expected failures and signals still produce one final finite JSON object (or
listen end). Usage errors leave stdout empty. Damaged output may have no final
record. Final records capture the exit intent before their own write/flush; a
subsequent output failure can change the process code. **The process exit code
is authoritative.** No second final object/end is appended to revise it. The
older info failure policy remains empty stdout.

Text output uses the same facts/units, escaping terminal controls with safeText.
Default and verbose output omit inline payload/content, full nonce/test IDs,
path bytes, channel keys, coordinates, ordinary chat, raw frames, argv, sessionInfo
object graphs, and recursive exceptions. Exact selected ports, if displayed,
are escaped for display without changing OS paths.

### Operator-supplied templates (not executed in this step)

The following are shell templates: the operator supplies and confirms every
variable, authorization, radio/channel configuration, route, and budget.
`meshctl` denotes the source entry or the executable from its complete bundle.
Two devices may use different local channel slots. Configure A's forward and
B's return routes independently; do not copy receive metadata or the remote slot.

Terminal B, start the finite responder first:

```bash
meshctl --data-dir /tmp/meshchan-example-b datagram respond --port "$B_PORT" --json \
  --send-channel "$B_SEND_SLOT" --receive-channel "$B_RECEIVE_SLOT" \
  --local-id "$B_TEST_ID" --peer-id "$A_TEST_ID" \
  --route-descriptor "$B_RETURN_DESCRIPTOR" --path-hex "$B_RETURN_PATH_HEX" \
  --timeout "$COMMAND_SECONDS" --init-timeout "$INIT_SECONDS" \
  --task-timeout "$B_TASK_SECONDS" --duration "$B_LISTEN_SECONDS" \
  --max-entries "$B_ENTRY_LIMIT" --max-responses "$B_ATTEMPT_LIMIT"
```

Terminal A, after B is ready for the operator's trial:

```bash
meshctl --data-dir /tmp/meshchan-example-a datagram ping --port "$A_PORT" --json \
  --send-channel "$A_SEND_SLOT" --receive-channel "$A_RECEIVE_SLOT" \
  --local-id "$A_TEST_ID" --peer-id "$B_TEST_ID" \
  --route-descriptor "$A_FORWARD_DESCRIPTOR" --path-hex "$A_FORWARD_PATH_HEX" \
  --content-hex "$TEST_CONTENT_HEX" --response-timeout "$PONG_SECONDS" \
  --timeout "$COMMAND_SECONDS" --init-timeout "$INIT_SECONDS" \
  --task-timeout "$A_TASK_SECONDS" --max-entries "$A_ENTRY_LIMIT"
```

The CLI has no readiness event; process start alone does not establish B is
listening. The operator must account for initialization and the finite window.
Use `--text "$TEST_TEXT"` instead of content-hex if desired, supplying exactly
one. Single-operation raw examples:

```bash
meshctl --data-dir /tmp/meshchan-example-raw datagram send --port "$PORT" --json --send-channel "$SEND_SLOT" \
  --data-type "$DATA_TYPE" --route-descriptor "$ROUTE_DESCRIPTOR" \
  --path-hex "$PATH_HEX" --payload-hex "$PAYLOAD_HEX" --task-timeout "$TASK_SECONDS"
meshctl --data-dir /tmp/meshchan-example-raw datagram listen --port "$PORT" --json --receive-channel "$RECEIVE_SLOT" \
  --duration "$LISTEN_SECONDS" --max-entries "$ENTRY_LIMIT" --task-timeout "$TASK_SECONDS"
```

This software integration does not perform real serial/LoRa acceptance or
complete 1B.9 device acceptance or delivery. The separate
[1B.8 synthetic checks](testing.md#datagram-cross-layer-coverage-audit-1b8)
replace only the native boundary. Historical hardware/USB findings above remain unchanged.


## openHop development peer (1B.9)

The product's connection options remain USB-only. The source-only
[openHop acceptance peer](openhop-acceptance.md) provides finite development
info/send/listen/ping/respond operations over the selected virtual Companion's
binary WS frame proxy. It is excluded from product bundles. Its local-write
projection means local WS submission, while product USB local-write facts retain
their existing meaning. Neither establishes RF completion. The two tools share
Meshchan diagnostic tasks; exact PONG evidence must come from actual reception
over the two Heltec radios. See the [dev.2 status](releases/phase-1b-dev2.md).
