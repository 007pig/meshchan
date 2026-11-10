# Hardware-free testing

The historical Phase 1 / 1A / Step 8 audit is retained below. Phase 1B.8 adds
datagram serial-byte acceptance shared by ordinary tests and a source/AOT
development probe, without changing product behavior.
Run commands from the repository root unless noted. Python 3 is a
development tool only; the distributed CLI does not require it.

## Historical behavior audit (1A.8)

Paths below are relative to each package's `test/` directory. The audit found no
missing unit/integration behavior group requiring another Dart test. Existing
assertions remain unchanged; the gaps were repeatable process and bundle checks.

| Layer | Existing tests and representative assertions | Remaining gap / Step 8 action |
| --- | --- | --- |
| Serial diagnostics | Core `serial_ports_test.dart`: platform guard before callback; exact selected path; partial-open recovery; metadata failure/disposal; private metadata omitted | No additional unit group needed. |
| Serial framing | Core `serial_framing_test.dart`: independent vectors; every two-part split/coalescing; 1..176 lengths; bounded noise; failure lock; owned buffers | No gap identified. Independent vectors retained. |
| Transport | Core `serial_transport_test.dart`: partial writes and total test-clock deadline; receive/send error races; stop gate; natural reader done before release; unconfirmed stop never frees | No gap identified. No new cleanup timeout. |
| Message codecs | Core `companion_messages_test.dart`: independent bytes, version/length gates, signed power/radio units, sensitive fields skipped | No gap identified. |
| Session | Core `meshcore_session_test.dart`: two ordered commands; early/late responses; send completion; timeout/cancel; shared awaited cleanup | No gap identified. |
| CLI | CLI `meshctl_test.dart`, `session_cli_test.dart`: zero side effects for invalid arguments/help; parsed JSON/NDJSON; exit codes; signal cancellation; sync/done/flush/queue failures; deduplication; privacy | No duplicate tests added. Negative assertions check no transport creation, enumeration, unexpected sends, or sensitive output. |
| Cross-layer wiring | CLI `session_serial_cli_test.dart`: real codec/transport/session/CLI, replacing only the native boundary; 16 info/watch × response stage × body arrival × blocked-output combinations | Retained as one parameterized group. Checks late input cannot revive failure, exact sends, cleanup order, final parsed output and no remaining timers. |
| Processes and artifacts | Existing CI covered help/version, invalid parameters, builds and Linux refusal; historical local checks covered example usage, broken pipe and relocation | `tool/smoke_cli.py` now shares all of these checks between local runs and CI; adds JSON enumeration refusal, strict watchdogs and complete-bundle asset checks. |

Session/CLI timing uses `fake_async` and controlled Futures/sinks. Transport write
deadlines use its existing injected test clock: virtual timers do not control a
normal Stopwatch or native I/O. Cross-zone stream completion in the integration
group retains its zero-duration event turn, without sleeping through a request
budget. Existing tests observe cleanup and asynchronous errors rather than
retrying until green. Keep separate `dart test` processes and native builds
serial because native-asset build state is shared within the workspace.

## Datagram cross-layer coverage audit (1B.8)

This audit extends the historical 1A.8 audit above. Its conclusion about no
missing behavior groups applied to 1A only, before datagram implementation.
The five shared scenarios live in
`apps/meshctl/test/support/datagram_acceptance_scenarios.dart`; ordinary tests
and the development source/AOT probe call the same always-active checks.

| Behavior | Existing tests | New 1B.8 evidence | Still to validate |
| --- | --- | --- | --- |
| Raw binary send and local acceptance | `datagram_cli_test.dart`; core codec/transport short-write tests | `raw_send`: independent complete serial vector, successful short write, ordered initialization/send, no queue reads, awaited cleanup | Real native TX and firmware acceptance |
| Bounded shared inbox | Core reception tests; CLI consumption/filter/final-entry tests | `bounded_listen`: three consumed items, ordinary/filtered/matching counts, split and coalesced serial input, last event before end, no extra read | Real shared inbox and device behavior |
| Diagnostic correlation and RTT | Core diagnostic codec/tasks; CLI exact match and early-PONG failure tests | `ping_round_trip`: fixed request-1 bytes, independent local slots, queued PONG, controlled microsecond RTT | Two-device LoRa round trip |
| Finite responder and return configuration | Core deduplication/tasks; CLI cumulative/zero-response tests | `responder_reply`: fixed independent PING, exact PONG bytes, local return slot/path, one confirmed response | Real peer receipt and explicit return route |
| Partial PONG, deadline and release | Core deadline/cleanup tests; existing 16 info/watch serial combinations | `partial_pong_timeout`: partial outer frame, response timeout, late tail, pending reader stop and done gates, one failure after real cleanup | Historical USB delivery cause and ready-state H10 |
| Source/AOT/process boundary | Existing shared smoke: help, rejection, broken pipe, product relocation | Same five scenarios in source and separate native development bundle; strict JSON report validation | Other hosts and observed CI for this change |

Existing algorithm/parameter/failure-priority matrices and every framing split
point remain in their original tests. This adds five representative wiring
scenarios, not another Cartesian product. All native connections are synthetic;
no scenario enumerates, selects, or opens hardware.

## Reproduce acceptance on the existing Mac SDK

The subshell stops at the first failure. It creates fresh output, prints its path,
and retains it for inspection; do not substitute an older bundle after a failed
build. No command here supplies a valid port or enumerates on macOS.

```bash
(
  set -eu
  export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
  MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
  "$MESHCHAN_DART" --version
  python3 --version
  "$MESHCHAN_DART" pub get --enforce-lockfile
  "$MESHCHAN_DART" format --output=none --set-exit-if-changed .
  "$MESHCHAN_DART" analyze --fatal-infos
  (cd packages/meshcore_link && "$MESHCHAN_DART" test)
  (cd apps/meshctl && "$MESHCHAN_DART" test)
  CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meshchan-1b8.XXXXXX")"
  printf 'Fresh build output: %s\n' "$CHECK_DIR"
  (cd apps/meshctl && "$MESHCHAN_DART" build cli \
    --target=bin/meshctl.dart --output="$CHECK_DIR/meshctl")
  (cd packages/meshcore_link && "$MESHCHAN_DART" build cli \
    --target=example/serial_transport_check.dart --output="$CHECK_DIR/observation")
  (cd apps/meshctl && "$MESHCHAN_DART" build cli \
    --target=tool/datagram_acceptance.dart --output="$CHECK_DIR/datagram-acceptance")
  python3 tool/smoke_cli.py \
    --dart "$MESHCHAN_DART" \
    --cli-bundle "$CHECK_DIR/meshctl/bundle" \
    --observation-bundle "$CHECK_DIR/observation/bundle" \
    --datagram-acceptance-bundle "$CHECK_DIR/datagram-acceptance/bundle"
  git diff --check
)
```

Use only the installed Homebrew Flutter SDK and its bundled Dart. The direct Dart
path avoids the Flutter wrapper's cache-stamp writes under a restricted sandbox;
it does not validate the Flutter CLI. No SDK upgrade or cache modification is
part of this procedure. Native build hooks still require a compiler/platform SDK.
`git diff --check` checks tracked patch whitespace, not every untracked file or
historical commit. See the [1B.8 dated execution record](development.md#1b8-software-validation-on-november-10-2026)
and the retained [1A.8 record](development.md#step-8-software-validation-on-november-9-2026).

## Shared smoke contract and CI

`python3 tool/smoke_cli.py --help` describes the four required paths. Paths are
resolved before execution, including paths containing spaces. The script locates
the checkout from its own file, fixes source working directories to the two
packages, and rejects missing/empty executables or native libraries. It does not
install dependencies, build artifacts, accept arbitrary commands, or contact
GitHub. Prepare all three bundles before calling it. Keep the product CLI
bundle separate from the observation and development acceptance bundles.

The retained process cases cover source/native no-argument help, help/version,
all four original command help option sets, datagram group/four leaf help,
group-without-operation help, 16 invalid argument cases per CLI entry,
source/native observation usage with absent/blank input, a native broken pipe,
and four relocated entry checks. Two additional process cases execute the fixed
datagram probe in source and AOT: 69 checks on macOS, 73 on Linux for the current
script. The script counts actual completed checks; its success line is not a
fixed historical count. No real hardware command is executed. The version
expectation comes from the existing `lib/src/version.dart` constant. Linux adds
four actual `ports` / `ports --json` source/native refusal cases: exit 69, empty stdout, the exact pinned backend safety
diagnostic, and no unhandled exception/application stack. macOS prints an
explicit Linux-only non-applicability notice and never runs `ports`.

Every child runs serially with closed stdin, captured/drained output, and a
60-second watchdog. A timeout fails the script and kills/reaps only the child's
new process group, including its build-hook descendants. The script never adds a
timeout to production cleanup. Usage failures require 64 and empty stdout;
source build-hook stderr may coexist with the required specific diagnostic.

The native broken-pipe case closes the OS pipe's read end **before** child
startup, connects stdout to the write end, and closes the parent's write copy.
It requires exit 74 and `Error: CLI output failed.` with no stack. There is no
sleep, shell pipeline, live watch, or simulated production dependency. Existing
sink tests separately prove session cleanup on output failure.

Relocation copies the **whole** CLI bundle into a temporary directory outside the
checkout, uses that directory as cwd, and checks version, info help, datagram ping
help, and missing port rejection. Executables and `lib/liblibserialport_plus.dylib` (macOS) or
`lib/liblibserialport_plus.so` (Linux) must be nonempty in both original bundles;
the relocated CLI assets are checked again. The separate development bundle's
asset is also checked. No library path is redirected to a
pub cache. Only the script-owned relocation copy is removed automatically.

CI retains one Ubuntu job, fixed Flutter/action versions, locked dependencies,
format/analyze, both full suites, and the two existing native builds. It builds a
third, separate development bundle with
`dart build cli --target=tool/datagram_acceptance.dart --output=build/datagram-acceptance`
from `apps/meshctl`, then passes it as `--datagram-acceptance-bundle` to this same
script after builds and has a 20-minute job limit for resource protection. Child
watchdogs also apply to Linux refusal and broken pipes. Failures are propagated;
there are no retries, skipped failed cases, or `continue-on-error`.

## Finite datagram CLI regression (1B.7)

`apps/meshctl/test/datagram_cli_test.dart` uses real codec/session/reception/tasks
and the existing fake transport/sink, with a narrow elapsed/nonce injection in
`runCli`. Production omits both seams. Table-driven pure validation asserts no
transport/enumeration/signal side effects. Wiring tests cover all four leaves,
post-consumption filtering and final-entry/read settlement, early PONG with
failed local send, nullable facts/microseconds, finite zero-response completion,
signal/output/core-failure races, cleanup pending/failure, and private-data
omission. The existing serial cross-layer matrix is retained unchanged.

After locked resolution, format, and analysis, run the focused CLI file before
the complete core and CLI suites; keep every test process/build serial:

```bash
(cd apps/meshctl && "$MESHCHAN_DART" test test/datagram_cli_test.dart)
```

This software validation does not select a port, run a wireless command, or
replace the separate 1B.8 serial-byte/AOT evidence or 1B.9 device acceptance.

## Shared datagram scenarios and development probe (1B.8)

Run just the shared scenarios or the development source entry from `apps/meshctl`:

```bash
"$MESHCHAN_DART" test --reporter expanded test/datagram_acceptance_test.dart
"$MESHCHAN_DART" run tool/datagram_acceptance.dart
```

The thin test and tool call the same five scenarios. Support imports no
`*_test.dart` or `package:test` code and uses checks that remain active in AOT.
Only `NativeSerialConnection` is replaced through the existing internal
`serialTransportForTest` seam. Every RX chunk enters the saved reader callback
with its outer serial header; every accepted TX prefix is checked against fixed
complete frames. The raw-send vector is independent of production encoders.
Queue scripts return datagrams only after complete `0x0A` commands. Splitting
and coalescing occur at a few representative boundaries; the exhaustive framing
matrix remains in the core tests.

Short-write retries use a per-frame `SerialWriteClock` origin and delays from
the same FakeAsync domain as task elapsed time. Initialization deliberately
advances that domain by three seconds before the next frame. Reader stop
acknowledgement and reader done are separate gates; final JSON/CLI completion
and port release must wait for both. The partial-PONG case locks the task failure
before cleanup, ignores the late tail/notice, and expects CLI 69 while the
acceptance scenario itself passes. One zero-duration external event turn settles
SDK cancellation Futures, followed by an explicit microtask barrier for the
raw runner's sequential cancellation continuation and completion checks. There
is no conditional pumping, real deadline sleep, or retry loop.

The probe has no hardware/argument/stdin mode. Its bounded JSON contains a fixed
probe ID, schema version, scenario IDs, pass flags, actual CLI exit codes, and
completed/passed/failed counts. Shared smoke parses JSON and validates types,
the exact unique five-ID set, all flags, expected CLI codes (including 69), and
counts. It runs source in the CLI package and AOT with a checkout-external cwd.
The AOT executable needs no source files at runtime and compiles no test runner.
Keep the entire product bundle for 1B.9; the development probe is not product
distribution content.

## Evidence limits

| Evidence | What it establishes | What it does not establish |
| --- | --- | --- |
| Dart unit tests | Asserted protocol, state and output behavior | Device compatibility or stability |
| Synthetic cross-layer cases | Production codec/transport/session/CLI wiring at a replaced native boundary | Actual USB driver, reader isolate or radio behavior |
| AOT synthetic probe | Independently compiled production Dart CLI/tasks/session/reception/serial framing execute all five shared scenarios | Production native constructor, FFI symbol loading, reader isolate, USB or LoRa I/O |
| Source/native process checks | Checked entry points, arguments, exit status and stdio | Handshake or native TX |
| Builds and nonempty assets | Host compilation and asset organization | Every native function loads/works or other platforms run |
| Complete bundle relocation | Checked entries execute outside the checkout on the same host | Clean-machine installation, native library loading, device I/O or hardware session AOT |
| Linux enumeration refusal | Unsafe enumeration remains blocked | Linux serial hardware support or loaded native library |
| Observed remote CI | Results for that event and commit | Uncommitted changes, future commits or hardware acceptance |

No 1A.8 or 1B.8 check opens or selects hardware. Historical incomplete 64-byte USB
response bodies remain an unresolved device/USB/driver investigation, not a
proven firmware, ZLP, or flush diagnosis. Synthetic split-body tests establish
waiting, timeout, cleanup and rejection of late results; passing them does not
repair USB delivery. No retry, reset, extra query, timeout/default-delay change,
signed release or LoRa round trip is included. Step 9 hardware acceptance remains
separate; see [hardware evidence](hardware-validation.md).
