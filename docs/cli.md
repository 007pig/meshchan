# Meshctl diagnostics

Phase 1 / 1A / Step 7 connects the existing single-use `MeshCoreSession` to
`info` and `watch`. The application version remains `0.1.0-dev.1`.

From the repository root, use the existing Homebrew SDK on this Mac:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" pub get --enforce-lockfile
cd apps/meshctl
"$MESHCHAN_DART" run bin/meshctl.dart --help
"$MESHCHAN_DART" run bin/meshctl.dart info --help
"$MESHCHAN_DART" run bin/meshctl.dart watch --help
```

Build with `"$MESHCHAN_DART" build cli --target=bin/meshctl.dart --output=build/dist`.
Then `build/dist/bundle/bin/meshctl` is equivalent to the source invocation.
Distribute the entire bundle, including its native library. Source invocations
may emit native build-hook diagnostics before the application starts.

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
| 74 | Output failure without an earlier primary failure or signal. |
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
