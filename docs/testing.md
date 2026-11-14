# Hardware-free testing

The historical Phase 1 / 1A / Step 8 audit is retained below. Phase 1B.8 adds
datagram serial-byte acceptance shared by ordinary tests and a source/AOT
development probe, without changing product behavior.
Run commands from the repository root unless noted. Use the latest installed
stable Python 3.15 or newer for local Python scripts, as described in the
[local toolchain selection](development.md#local-python-toolchain). Python is a
development tool only; the distributed CLI does not require it.

## macOS guest product GUI checks

Use the [VM guide](macos-vm-gui-testing.md#meshchan-product-ui-runner) and
[repository skill](../.agents/skills/macos-vm-gui-testing/SKILL.md) for actual
guest UI input. `apps/meshchan_app/tool/macos_vm/host.py` deploys complete signed
app bundles to owned guest fixtures and reuses the authorized guest executor.
`scenario.py` separates Device/Draft preedit capture, composing actions and
review-confirmed natural commits. Inspect each original image and focus JSON
before its commit; do not automate the visual approval flags.

These optional interactive tests require an unlocked configured VM and are not
ordinary CI entrypoints. They do not enumerate or open hardware by default.
Explicit metadata Refresh is part of the product UI scenario; actual port
selection/initialization is a separate, explicitly authorized step. A virtual
SPICE port is not sufficient evidence of a physical USB mapping. Normal quit
requires the application's resource-release/worker-exit receipt, followed by
independent inspection of an external owned copy of its closed fixture.

Run the skill's offline controller checks on macOS with:

```bash
/opt/homebrew/bin/python3 .agents/skills/macos-vm-gui-testing/scripts/check_tooling.py
```

An optional native-helper build directory also exercises their host-refusal
checks. The [VM product validation](validation/phase-1d6-vm-gui.md) records the
actual Debug/Release run and its hardware/isolation limits.

## Offline draft editor checks (1D.4)

The [app guide](../apps/meshchan_app/README.md#offline-drafts-1d4) describes explicit
Save/Command+S, exact text/composing, conflict inspection and unknown outcomes.
Use only owned fixture directories for normal GUI launches (`--data-dir=...`).
Do not use fixed fixture probes as evidence of product editor saving. Native
XCTest still requires its pre-engine disabled-owner TestAction configuration;
new editor initialization does not bypass that isolation.

Run sequentially with the existing Flutter SDK and Apple Clang; on the local Mac
use `/opt/homebrew/bin/python3` (verified 3.15.2) rather than Apple system Python:

```bash
(cd apps/meshchan_app && flutter test --no-pub)
python3 apps/meshchan_app/tool/check_draft_process.py --dart "$(command -v dart)"
python3 apps/meshchan_app/tool/check_runtime_process.py --dart "$(command -v dart)"
```

`draft_editor_test.dart` uses controlled completions for buffer/baseline races,
unknown writes and shared quit decisions. `draft_widget_test.dart` drives actual
buttons, dialogs, selection, composing values and keyboard shortcuts with an
injected AppRuntime. `draft_worker_test.dart` uses fixtureWrites false and the
real spawn/dispatcher/public-core/SQLite path for CRUD/revisions/no-op/cursors,
scoped paused Save and close drain. `check_draft_process.py` adds independent
owner/contender/reopen checks and a committed create response dropped at the
production dispatcher's send boundary. Its new process requires exactly one
record after safe close; the original unknown remains unknown. No private storage
hooks, SQL, CLI internals or device access are used. CI runs the product gate in
both software and macOS jobs, with shared native operations still sequential.

`draft_departure_regression_test.dart` uses the real fields, macOS mouse/key events
and modal dialogs with an injected runtime. It covers marked text before departure
or quit, pointer-down before the next text-input rebuild, Save/Command+S deferral,
per-document Undo/Redo isolation (including a pending throttled history push), and
unknown writes that finish while a navigation/quit dialog is open. The editor tests
also control both orderings of Discard versus unknown completion and require a
separate acknowledgment. Run this focused review regression set with:

```bash
(cd apps/meshchan_app && flutter test --no-pub test/draft_departure_regression_test.dart test/draft_editor_test.dart)
```

These are headless Widget/controller checks. They do not substitute for actual
macOS input-method or window/Command+Q acceptance of a newly built product.

Build Debug/Release and run existing runtime/relocation/probe/native regression
commands below as separate evidence. Actual GUI input/dirty navigation/quit is
also separate from callback or Widget tests. See the [1D.4 record](validation/phase-1d4-drafts.md)
for source manifests, observed results and remaining platform limitations.


## Application runtime (1D.3)

The app suite now includes actual `Isolate.spawn`/public-core/SQLite tests alongside
resource-free Widget fakes and controlled dispatcher/recording fakes. It checks
strict launch modes and pre-bootstrap native test isolation; one application owner
across rebuild/navigation; correlated reads and committed exact-text drafts;
synchronous device admission; early stop/operation-generation cancel; controls
while resolution/native cleanup is pending; all recording Future/stream errors;
logical-versus-release/save facts; sticky maintenance; stale/duplicate/reversed
events; worker fatal/exit/lost response; idempotent drain/close; and unknown release.
Future-schema/corrupt files retain their bytes after controlled open rejection.

`runtime_shutdown_test.dart` adds controlled real-isolate client regressions for
release after a shutdown deadline, release before a delayed exit, and onExit
before a late release report. Each keeps quit vetoed until both facts are known,
then requires automatic port disposal, a reconciled later quit outcome and exactly
one close request. Earlier unknown outcomes and failed requests stay immutable.
A ReceivePort-capturing entry closure exercises real SDK spawn rejection before
worker entry and requires owner none, no synthetic onExit, zero client ports and
permitted normal exit. Existing fatal-worker tests retain unknown ownership.

`runtime_timeout_test.dart` uses the production dispatcher with real public core
and SQLite, gated at open return, first settings read, or Hello delivery. After
startup/read timeout it requires ordinary admission to remain faulted, a contender
to remain busy, and the first shutdown to drain/close exactly once. A Hello later
than the shutdown observation deadline must still deliver that same intent and
allow authoritative late reconciliation. Healthy completion requires zero pending
requests/ports and exact draft continuity after reopening. Test failure cleanup
also uses dispatcher close and acknowledges confirmed release; it never kills an
owner or removes a lock to manufacture success.

`runtime_verification_test.dart` creates and reads a valid fixture through the
real runtime, truncates its database while keeping the closed receipt, then requires
failed read verification to preserve zero bytes and the exact receipt without
spawning a worker. The resulting resource-free shutdown must still permit exit.

`recording_worker_test.dart` builds real public core and fake `CompanionTransport`
inside a test-only worker entry, using the production dispatcher/gate/adapter/close.
It covers stop before resolution, cancel after record but before prepared, and an
actually opened simulated device with cleanup blocked by a Completer. Status,
cancel and quit receipt continue while cleanup is blocked. Release, final committed
save, core close and worker exit are separately asserted. Production has no fake
transport or arbitrary test-command protocol. No real port is enumerated/opened.

```bash
(cd apps/meshchan_app && flutter test --no-pub)
python3 apps/meshchan_app/tool/check_runtime_process.py --dart "$(command -v dart)"
python3 apps/meshchan_app/tool/check_macos_runtime.py \
  --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app
```

Use the verified local Python and command PATH in the [developer guide](development.md#application-runtime-checks-1d3).
The process gate writes a controlled exact-text draft through the formal bridge,
keeps the owner alive while another process must be busy, then closes and reopens
in a new process. The native gate uses the same compiled app entry to write/read
and normally quit, copies the whole app outside checkout, reruns from another cwd
and checks the relocated signature. Hardware enumeration is absent from both gates.
It also requests native quit before bootstrap and with a live ready owner. The
latter must return from AppKit's `terminateLater` loop after the actual shared
close, with confirmed worker exit and zero pending requests/client ports.

RunnerTests receives its disabled-owner configuration from TestAction before
Swift/Dart startup, not from `setUp`. Missing/invalid configuration blocks resource
startup. Widget tests inject `AppRuntime`; page dispose removes observers without
closing core. TestAction is independent of normal LaunchAction, so this isolation
does not disable ordinary released startup. CI retains `concurrency: 1`, adds real
runtime/process checks to `check`, and production runtime/relocation to `macos-app`.
The native tests exercise the production termination bridge with injected request,
reply and scheduling callbacks: pending system requests, success/false replies,
repeated requests and synchronous completions. They never request actual logout,
restart or shutdown. Dart bootstrap tests independently gate first rasterized frame
and native permission, including stop before/between them and permission failure.
If a newly signed host under Documents blocks in the OS privacy prompt before
entry, retain that failure and rerun with `-derivedDataPath` under `/private/tmp`;
do not change privacy settings. This does not bypass native-test isolation.
The [1D.3 record](validation/phase-1d3-runtime.md) distinguishes these results from
the legacy platform probe and from unexecuted hardware/distribution checks.

## Flutter macOS host (1D.2, historical scope)

The mixed workspace uses one root lockfile. Resolve with
`flutter pub get --enforce-lockfile`, analyze with
`flutter analyze --no-pub --fatal-infos`, and run
`(cd apps/meshchan_app && flutter test --no-pub)` in addition to the existing
sequential core/CLI/Python/native gates below. The installed Flutter-bundled
Dart also supports the existing enforced-lockfile CLI validator; it remains
CLI-only and must not be interpreted as Flutter acceptance.

App tests inject the platform boundary and storage handles. They check all three
navigation destinations, truthful unconnected states, no default probe/native
work, explicit-only startup, invalid arguments/fixtures before resource access,
independent maintenance failures, real awaited close failure, and receipt
invalidation after an unconfirmed read close. They never enumerate/open ports.
Real macOS fixture execution is separate and uses public `CoreStorage` in one
finite worker, including release comparisons without assertions. See the
[app commands](../apps/meshchan_app/README.md#explicit-finite-platform-verification)
and [platform results](validation/phase-1d2-platform.md).

The parser accepts the known Cocoa boolean pairs supplied by Xcode and XCTest
before validating developer options. Tests cover normal navigation with those
pairs, explicit probes mixed with them, and rejection of missing/invalid Cocoa
values, unknown options, and malformed/duplicate probe options. After building
debug, execute the native test host with:

```bash
(cd apps/meshchan_app && xcodebuild -workspace macos/Runner.xcworkspace \
  -scheme Runner -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/macos -parallel-testing-enabled NO test)
```

This checks that `RunnerTests` links and launches in `Meshchan.app` and finds its
Flutter view controller. It does not open storage or access hardware. The macOS
CI job runs this target as well as Flutter tests and app builds.

Build debug and release sequentially from `apps/meshchan_app` with
`flutter build macos --debug --no-pub` and `flutter build macos --release --no-pub`.
The normal app and explicit probe use the same `lib/main.dart` and `.app`.
Window launch/navigation, SQLite close/reopen, cross-process persistence, serial
asset packaging versus actual metadata invocation, complete-app relocation,
architecture/signature and directory access are separate evidence. No build or
fake test substitutes for those observations. Metadata enumeration is manually
opted in with `--enumerate-serial`; it is absent from tests and CI and grants no
device-open or RF evidence.

CI retains the Linux pure-Dart/CLI gate, adds Flutter software tests, and declares
a `macos-15` job for sequential debug/release builds and hardware-free release
SQLite write/read processes. The job prints its actual architecture. The
[runner image catalog](https://github.com/actions/runner-images#available-images)
currently assigns `macos-15` to arm64; configuration is not a remote run result.
Headless/WindowServer failures must remain runtime failures, not build passes.
Independent CI runners do not share native hook output; processes within each
worktree remain sequential. Local process watchdog termination on a stuck probe
is never recorded as confirmed cleanup.

## Offline business package baseline (1C.2)

`packages/meshchan_core/test/values_test.dart` imports the public business entry
and checks exact Chinese/emoji/mixed-newline UTF-8 lengths, content larger than a
radio packet, local ID representation, copied/unmodifiable paths and collections,
page/settings bounds and defaults, UTC/range checks, stable error codes, and
preservation of unknown diagnostic facts across independent cleanup scopes.
It does not implement fake CRUD repositories or test pure interface declarations.

`test/dependency_probe_test.dart` uses the internal empty Drift fixture under
`test/support`. Real `build_runner` output supplies its superclass. The test
injects `NativeDatabase.memory()`, executes `SELECT 1 AS value`, verifies a single
integer 1, and awaits close in `finally`, including assertion/query failures.
No fixture is exported from the public business API. Fixture schema version 1
does not define the production `databaseSchemaVersion`; no business table,
schema snapshot, migration, disk database, directory lock, or device is created.

After locked root dependency resolution, generate from the member directory:

```bash
(cd packages/meshchan_core && dart run build_runner build)
git diff --exit-code -- packages/meshchan_core/test/support/dependency_probe_database.g.dart
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
(cd packages/meshchan_core && dart test)
```

Check in the generated fixture and reject regeneration differences. The minimal
`build.yaml` only disables the empty manager's unused private field; the default
source set still includes `test/`. See the [dependency/toolchain record](development.md#offline-core-package-and-dependency-baseline-1c2).
Then run existing communication/CLI/Python regressions and native smoke gates
below sequentially. A cold sqlite3 hook cache needs access to its upstream
versioned native release; the default hook verifies the downloaded asset hash.
Do not substitute a manually downloaded system library to bypass a failed hook.

This probe establishes dependency/generator/native SQLite compatibility in the
tested environment. Existing CLI source/AOT smoke exercises existing serial and
synthetic datagram paths; it does not call SQLite. File reopen, production
migrations, ownership/recovery, and SQLite AOT distribution remain later work.
CI configuration is coverage intent, not an observed remote passing result.
The [November 11 local record](development.md#1c2-local-validation-on-november-11-2026)
reports 12 offline business/probe, 180 communication, 97 CLI, and 46 Python tests,
three fresh existing native builds, and 69 shared macOS smoke checks. It records
the initial sandbox network failures and the resolved empty-manager warning;
remote CI, hardware, real-file storage, and SQLite product AOT are not inferred.

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
  export PATH="/opt/homebrew/share/flutter/bin:/opt/homebrew/opt/python@3.15/bin:/usr/bin:$PATH"
  MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
  "$MESHCHAN_DART" --version
  python3 --version
  python3 -c 'import sys; assert sys.version_info >= (3, 15)'
  "$MESHCHAN_DART" pub get --enforce-lockfile
  "$MESHCHAN_DART" pub workspace list
  (cd packages/meshchan_core && "$MESHCHAN_DART" run build_runner build)
  (cd packages/meshchan_core && "$MESHCHAN_DART" run tool/check_schema.dart)
  git diff --exit-code -- packages/meshchan_core/lib/src/storage/database.g.dart \
    packages/meshchan_core/test/support/dependency_probe_database.g.dart \
    packages/meshchan_core/drift_schemas packages/meshchan_core/test/storage/generated
  "$MESHCHAN_DART" format --output=none --set-exit-if-changed .
  "$MESHCHAN_DART" analyze --fatal-infos
  python3 -m unittest discover -s tool -p '*_test.py'
  (cd packages/meshchan_core && "$MESHCHAN_DART" test)
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
format/analyze, the existing Python suite, and all three Dart member suites.
After resolution it generates the offline dependency fixture in its member
directory, verifies that the generated file is tracked, and rejects a diff
before analysis/tests. It retains the two existing native builds and builds a
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


## openHop development boundary tests (1B.9)

`apps/meshctl/test/openhop_peer_test.dart` adds 15 tests to the existing CLI suite.
They cover inert configuration/URI/secret-reference validation, restricted REST
selection and redaction, real SDK WS split/coalesced binary frames, an independent
complete TX vector, text/oversized input, authentication close, normal close,
partial EOF, redirect rejection, and cancellation with late successful connection
cleanup. Real loopback session/PING cases insert current-time notifications;
separate initialization/response timeout cases prove they do not replace the
response or renew its budget. Raw listening compares actual consumed bytes and
ends at the entry quota; responder cancellation releases the signal subscription
and WS connection. The existing diagnostic algorithm matrix is reused.

These use 127.0.0.1 ephemeral sockets, synthetic JWT strings, and event/Completer
coordination. Only the short notification injection/deadline checks use real VM
timers. A local sandbox must allow loopback binding; `fake_async` cannot advance
real sockets. No default test or CI reads real credentials, opens USB, or contacts
openHop. The current single CI job automatically includes these tests and still
builds exactly three bundles. No fourth peer AOT product or new platform is added.

The [finite tool/matrix guide](openhop-acceptance.md) describes separately
authorized hardware execution. The 1B.9 full gate passed 180 core and 72 CLI
tests, followed serially by three fresh builds and 69 shared macOS smoke checks.
Source and AOT each passed all five existing datagram synthetic scenarios.
These are software observations, not RF acceptance. See the
[dated execution record](development.md#1b9-software-validation-on-november-10-2026).


## Read-only channel audit follow-up

`test/channel_audit_test.dart` adds 11 CLI-suite tests for inert config/slot
validation, serialized metadata queries, empty/zero-key filtering, duplicate-key
ambiguity, private frame wiping, wrong-index/extended-key/write failures,
finite timeout, cancellation while actual cleanup remains pending, unsupported
capacity, and explicit A-only/B-only operation without false comparison claims.
The fixtures assert exact host opcode sequences and no consuming/RF writes.
The separate held-EOF openHop regression proves WS cleanup waits beyond the
outgoing sink close and retains its input subscription until EOF. The full CLI
suite passed 84 tests after this follow-up. These are later results, not a change
to the historical 72-test candidate gate above. See
[actual device attempts](hardware-validation.md#read-only-channel-audit-on-november-10-2026).

## Passive-window and finite RF driver follow-up

`openhop_idle_probe_test.dart` adds two bounded lifecycle tests. A real loopback
probe case checks actual session ready, a passive window, no queue/RF/heartbeat
writes, and actual cleanup. The peer config test additionally rejects an unknown
idle timeout without a sufficient explicit measured lower bound. The complete
CLI suite now passes **88 tests**; core remains the separately recorded 180-test
run because its implementation did not change. No actual deployment credential
or device is accessed by these tests.

The Python driver is validated without hardware against real retained structural
results: H6 rejects a different timeout cause, H2 rejects wrong length/type/slot,
and H7 requires an exact PONG plus a still-active A before SIGINT. Hardware
results remain separately retained and include failures; these predicate checks
are not additional RF trials. The [Direct matrix record](hardware-validation.md#direct-rf-matrix-on-november-10-2026)
contains all actual exits, cleanup, send/matching facts and known limits.

The November 11 authorized hardware comparison is separate from the above
software tests: H2/H7 now have passing records with B command 15 s/A 5 s, and
all preceding failures remain. The summary accounts for every retained trial,
checks the cumulative 15-attempt cap and the comparison's individual H2 <=1 and
H7 <=3 allocations, and records actual cumulative attempts 14. No new Dart test
run or native rebuild is inferred from these hardware/metadata changes. See
[the actual comparison](hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026).

## Review regressions on November 11, 2026

Three later CLI regressions first reproduced the reported defects, then passed:
closing a never-opened WS transport without installing a frames listener;
pausing public frame delivery while keeping receive EOF as the real resource
cleanup gate; and a real loopback raw-read timeout after one exact datagram.
The last case checks retained reception counts, opcode 0x0A failure evidence,
no invented send fact, and actual cleanup. It does not duplicate diagnostic
matching algorithms or contact a deployment. The complete CLI suite now passes
**91 tests**. The previous held-EOF, late-open cancellation and real loopback
cases remain in that suite.

Six stdlib Python tests in `tool/run_openhop_acceptance_test.py` cover actual
A/B operation and response-limit validation, full/follow-up derived allocations,
B limits read from the real referenced config, duplicate/implicit/oversized
limits, role/route mismatches, rejection before execution-directory creation,
and read-only legacy failure accounting. They generate synthetic plans in a
temporary directory and never read credentials, bind a socket, open USB or run
a device process. Run from the checkout root:

```bash
python3 -m unittest discover -s tool -p '*_test.py' -v
```

The existing CI job now includes this command before the Dart suites. No new
platform or dependency was added. These are local results; no new remote CI
execution is claimed. Recorded core/native-build/smoke results retain their
original dates because production inputs and native bytes did not change.

## Settlement and captured-build regressions on November 11, 2026

The later Python suite passes **17 tests** (11 added to the earlier six).
Synthetic process tests exercise failed cleanup, an unfinished sender,
unexpected orchestration errors, retained pending snapshots, repeated waits on
a failed cleanup, and metadata failure after process creation. They assert that
other started finite peers are awaited, partial case records and known sends
are saved before STOPPED, unknown sends remain null with reserved bounds, and no
extra process, resend or signal is introduced. No real child device process is
started by these tests.

Summary tests use synthetic candidate bytes and execution-plan captures. They
check captured-hash provenance, rejection of replaced bytes or mixed/missing
captures, preservation of an existing summary on rejection, blocked unknown
accounting, legacy stopped trials without results, and failure of cached PASS
records with unsuccessful cleanup. The unchanged CI discovery command includes
both Python test files automatically. Dart source did not change in this follow-up;
the prior 91-test CLI result is retained with its source hashes rather than
reported as a new execution. No hardware/API credential is used.

## Interrupted-run and input-schema regressions on November 11, 2026

The Python suite now passes **25 tests**, adding eight groups to the earlier
17. Interrupted-run regressions keep an existing completed case in results.json
and add unrepresented pending/completed process metadata or a later retry in
the same case. Summary generation must reject these incomplete totals. Matching
metadata is accepted and hashed; changed PID/argv/final/cleanup facts reject.

Channel regressions cover decimal leading zeros, explicit hexadecimal values,
preflight rejection of invalid uint8 values, and a complete synthetic H2 execution
with `--receive-channel=01` that must save PASS and one send after settlement.
Probe regressions pass the flat emitted report and legacy execution wrapper
through actual plan generation, including omission of the optional exact timeout.
Failed exit/status/cleanup, insufficient window, nonpassive activity and malformed
window values reject before creating plan output. The summary accepts both probe
shapes through the same validator.

The full CLI suite was also rerun with local loopback access: **91 passed**,
including the 16 socket cases blocked by the review environment. Format checked
56 files with zero changes; fatal-info analysis was clean. Real USB and the
openHop deployment were not accessed. Existing CI discovery includes all 25
Python tests; no remote CI result is claimed.

## Ledger, session-race and archive-provenance regressions on November 11, 2026

The Python suite passes **31 tests**, adding six groups to the earlier 25.
Unknown output-directory regressions cover execution-plan, results, STOPPED and
pending-process evidence alongside a completed registered run. Generation must
reject before replacing an existing summary. Synthetic archive tests regenerate
a sibling delivery directory and its checksum/native manifests while leaving the
verified tar.gz unchanged. Only original archived bytes and notices may be copied;
incompatible RF hashes, changed archive bytes and changed external native bindings
reject. Temporary extraction cleanup is verified. Fake native fixtures never run.

The complete CLI suite passes **92 tests**, including all loopback socket cases.
One added synchronous-transport test commits a raw send OK then immediately emits
an error before the awaiting continuation resumes. The final report must keep
completed write/OK/acceptance facts, record transport/session failure, exit 69,
complete cleanup and leave no frame listener. Format checked 56 files with zero
changes and fatal-info analysis was clean. These are local offline results;
hardware and remote CI were not run. Existing CI discovery includes the new
archive test file automatically. The [dated software record](development.md#ledger-raw-session-and-archive-provenance-fixes-on-november-11-2026)
links the logs and evidence checks.

The subsequent [Python 3.15 follow-up](development.md#python-315-toolchain-follow-up-on-november-11-2026)
reran all **31 Python and 92 CLI tests** with Python 3.15.2 selected, including
all local loopback cases. Format and fatal-info analysis also passed. New source,
summary and final-archive verification records include the actual interpreter;
future local scripts use the latest installed stable Python 3.15 or newer.

## Channel-audit final-query regressions on November 11, 2026

The complete local suite now passes **95 CLI tests**, including the loopback
tests blocked by the review sandbox. Three added synthetic audit cases cover
final channel reply followed by an immediate transport error for A-only and
A-then-B, and an error while final cleanup waits on a Completer. Before the fix,
both same-turn cases produced PASS. They now require FAIL/69, a retained read
summary, successful actual cleanup, no listener leak, no B open/comparison and
no secret-bearing output. The held-cleanup case also requires that the report
remain pending until release. Existing successful readback and signal cases
still pass. Python 3.15.2 ran all 31 Python tests successfully; format checked
56 files without changes and fatal-info analysis was clean. See the
[dated source/log record](development.md#channel-audit-final-query-failure-fix-on-november-11-2026).

## Protocol-input and evaluation-accounting regressions on November 11, 2026

The full local suite passes **97 CLI tests**, including every loopback case,
and **34 Python tests** under Python 3.15.2. Two new Dart cases deliver a valid
final channel reply then malformed SELF_INFO [0x05] over synchronous and
asynchronous underlying streams. Before the fix both passed; now they require
FAIL/69, protocolFailed, retained read summaries, real cleanup, no B open/key
comparison, wiped private frames and no extra queue/RF commands. Existing valid
notices, cancellation and transport-failure tests still pass.

Three new Python groups reject missing post-execution metadata in both CLI modes
before output/process creation, reject invalid byte counts/types/expected exits,
and inject an evaluator RuntimeError after a completed synthetic H2 send. The
last case must persist both settled records, one known application send and a
STOPPED record with only the exception type. Existing leading-zero success and
unknown-send/cleanup accounting tests remain. No hardware child process or real
credential is used. Fatal-info analysis and 56-file zero-change formatting pass;
see the [dated verification](development.md#protocol-input-and-evaluation-accounting-fixes-on-november-11-2026).

## Content and invocation-ledger regressions on November 11, 2026

The Python suite passes **41 tests** with seven groups added to the previous 34.
Plan regressions shorten every actual A/B initiating content option without
changing metadata, shorten H5 and its count together, and exercise UTF-8 byte
counts plus malformed hex. All inconsistent plans reject before device work.
Summary regressions retain contradictory zero/over/unknown totals, unknown send
facts with zero reserved bounds, multiple responder invocations and misleading
legacy read-only send fields. Counts must agree with all invocation facts;
rejection preserves an existing output. Captured H5 argv is independently checked
against the 131-byte boundary rather than accepting its cached contentBytes.

The test subprocesses use sys.executable. The suite was run through Homebrew
Python 3.15.2 with Apple Clang's PATH first; although bare python3 resolves to
/usr/bin/python3, all 35 observed Python children used the selected Homebrew
interpreter. Logs and hashes are in the
[dated follow-up](development.md#content-invocation-ledger-and-interpreter-fixes-on-november-11-2026).
Dart/core/native inputs did not change, so their prior complete gate retains its
original date rather than being presented as a new execution. No real device,
deployment, credential or RF send is used by these regressions.

## Runner cancellation and acceptance exits on November 11, 2026

The Python suite passes **46 tests** under 3.15.2, adding five groups. H4 rejects
a one-byte B content option even when its metadata is edited to match; direct
evaluation accepts zero and rejects one. Mocked driver tests interrupt the A
settlement wait with KeyboardInterrupt or two self-delivered SIGINTs. They require
both peers observed, unchanged send count, actual cleanup facts, saved results/
STOPPED, exit 130 and restoration of the original handler. Resuming the same wait
does not start a new process or reset its deadline.

Separate tests require exit 69 for a failed cleanly settled selected case and
for two synthetic cases where FAIL is followed by PASS. The latter confirms
continued authorized execution cannot reset the aggregate status. Existing
passing-case, failed/pending cleanup and evaluator-error tests still pass.
All 40 observed Python child calls use the selected 3.15.2 interpreter. Dart and
native inputs did not change, so their prior complete gate was not rerun. See the
[dated software record](development.md#runner-cancellation-exits-and-empty-content-fixes-on-november-11-2026).

## Production storage and ownership (1C.3)

Run the package's full suite after generation and `tool/check_schema.dart`.
`dart_test.yaml` serializes its test files because process fixtures invoke the
SDK's shared native-asset hooks. Keep communication/CLI tests and native builds
in separate sequential processes as before. Every storage test uses an independent
temporary directory; no user data directory, serial port, or radio is accessed.

| Group | Actual assertions |
| --- | --- |
| `test/storage/database_test.dart` | A real production file matches the generated schema-1 snapshot helper; all four business objects, four operation configurations/results, exact Unicode/whitespace/newlines, non-millisecond UTC timestamps, integer elapsed facts above 2^53, nullable/partial facts and independent cleanup survive commit/close/reopen. Settings start absent. |
| Constraints and transactions | Duplicate keys, invalid IDs, revision/type/history-limit/singleton checks and an actually enabled settings FK reject invalid SQL. Internal profile deletion clears the live default while preserving a run's historical ID. A failed second statement rolls back a draft's related fields and preserves them across reopen. These SQL fixtures do not implement repository APIs. |
| Initialization failure | The hook runs after the first CREATE inside the real creation transaction; injected failure leaves no user objects and user_version 0, closes resources, and permits reinitialization. |
| `test/storage/ownership_test.dart` | Opening/closing reservations, dot/parent/symlink aliases, competing recursive directory creation, same-process and different-isolate opens, independent-process busy with zero executor factories, and an independent third contender after rejected opens. A native close interceptor and admitted-query barrier prove ownership lasts through actual close; repeated close shares the Future. |
| Process exit and marker | Ready/release line handshakes establish live ownership. Normal release and explicit exit without close allow reopen. Stale/informational marker deletion cannot bypass the dedicated flock resource. Close failure and secondary open-cleanup failure retain busy ownership until fixture process exit, preserving primary errors and safe unconfirmed state. |
| `test/storage/preflight_test.dart` | Future version, non-SQLite input, alien version 0, missing table/index, and symlink/hard-link resources fail before production executor creation. Main and all recognized existing sidecars are compared for both bytes and presence on rejection. Ordinary empty version 0 can initialize. |
| Journal states | Rollback-mode files without sidecars, arbitrary sidecars beside invalid input, a real WAL carrying committed future user_version absent from the main header, and a real hot rollback journal left by an unclosed transaction. Rejection inspects isolated copies; supported WAL with committed data is accepted. No immutable/nolock shortcut is used. |
| Decoding/errors | Illegal IDs, wrong JSON field types/keys, missing required fields, mismatched operation, unknown codes and cleanup shapes map to corrupt. Raw BLOB/text and fractional-integer damage is rejected before Drift coercion, including aliases. Caller LocalId validation remains invalid_input; future summary rows have a separate unreadable-row path. Controlled permission/I/O errors remain open_failed with safe default text. |

Process fixtures use bounded ready/release/exit waits, drain stderr, collect exit
codes, and kill/reap only test children during failed-test teardown. They permit
only the exact SDK build-hook status text in stderr. Production locking and close
have no polling, timeout release, busy retry, or marker/PID liveness heuristic.
The abnormal-exit tests establish OS lock release and specific journal states;
they do not establish diagnostic business recovery or arbitrary power-loss safety.

`tool/check_schema.dart` rejects a formal table definition differing from its
saved version, even if build_runner succeeded. CI runs this guard, checks the
production/probe `.g.dart` and saved/generated schema files are tracked/unchanged,
and runs all file/ownership tests via `dart test`. Existing communication/CLI/
Python tests, three native bundle builds, and shared smoke remain configured.
This configuration is not itself evidence of a remote passing run. The local
[1C.3 validation record](development.md#1c3-local-validation-on-november-11-2026)
records the actual environment/results. Existing CLI bundles still do not call
business SQLite, so their source/AOT smoke is not product SQLite distribution
acceptance. Linux CI coverage intent is separate from macOS local lock evidence.

## Persistent draft repository (1C.4)

After locked dependency resolution, generation, and the schema guard, run:

```bash
(cd packages/meshchan_core && dart test --reporter expanded test/repositories)
(cd packages/meshchan_core && dart test --reporter expanded)
```

Keep the existing `concurrency: 1` and two-minute per-test timeout. The new
repository tests use independent temporary real databases and await handle
cleanup. They reuse existing storage fixtures, representation/error assertions,
and the native close barrier. No sleep, device operation, user directory, or
cross-page long transaction is used.

| Test group | Behavior verified |
| --- | --- |
| `draft_repository_public_test.dart` | Only the public package import opens a real file and obtains `storage.drafts`. Exact empty/large Unicode text, combining characters, explicit U+FFFD, mixed newlines/whitespace, generated ID shape, initial revision/time, byte length, complete CRUD/list, and committed update/delete survive close/reopen. |
| Time/text/version | Fixed clocks preserve non-millisecond UTC values, equal/backward updates, immutable ID/createdAt, title-only/body-only/both changes, and no-op without a clock read. Unpaired high/low UTF-16 surrogates in either field fail before writing. Positive expected revision, missing, stale identical content, explicit hard delete, and unrelated tables retain their contracted behavior. |
| Concurrency | A Completer pauses the first changed update's real transaction after reading. Another changed update with the same revision conflicts; a separately controlled stale delete also conflicts and cannot remove the new version. Complete versions survive reopen. |
| Pagination | Empty/default pages, sizes 1/50/200, adjacent microseconds, tied IDs, static full traversal without duplicates/omissions, exactly full terminal pages, last/empty cursors, and continuation after deleting the previous cursor row. The damaged extra probe row fails the whole page. |
| Continuation query plan | The real executor interceptor runs EXPLAIN QUERY PLAN on the actual generated SQL and bound arguments. Sizes 2/50, before and after deleting the cursor row, must use a composite range SEARCH on drafts_updated with both keys, without a full table/index scan or temporary sorting. Returned items also cross a tied timestamp boundary correctly. |
| ID/revision boundaries | A known ID collision retries without replacement; eight collisions exhaust safely. Entropy/clock StateError, UnsupportedError, TypeError, and FormatException remain safe write failures. Real trigger failures from a different table's primary key or CHECK do not retry IDs. Revision max-1 increments to max; changed overflow fails while no-op/read/delete still work. |
| Mutation failures | Each of create/update/delete writes to the real transaction before an injected constraint rejection, and separately reaches the commit interceptor before COMMIT is rejected. Drift's actual rollback is awaited/observed. The same open storage immediately reads the complete old version, completes a normal mutation, then closes/reopens and reads the durable result. Failed create leaves no new row. |
| Lifecycle | Read and commit barriers pause an admitted update while close starts. New read/list/create/update/delete calls fail; the accepted operation still completes or rolls back. Native close has not started before settlement and ownership remains busy. After actual close/reopen, the old repository remains rejected. The existing close-failure process fixture additionally checks draft read/write rejection in closeUnconfirmed. |
| Error boundary | Damaged raw field types and invalid stored revisions remain database_corrupt in read/list/update/delete. Ordinary read failures map to read or write according to the outer operation. Source failures cannot masquerade as corruption. Safe default text omits test content/raw causes, and a typed cleanupUnconfirmed error retains its flag. |

The existing CI full `meshchan_core` test command discovers both new files and
continues running values, dependency probe, schema, preflight, and ownership
regressions. No duplicate job or matrix is needed. The 1C.3 historical validation
record remains unchanged; actual 1C.4 local results and remote-CI limitations are
recorded separately in the developer guide. Existing native CLI smoke remains
hardware-free evidence for the current bundles, which do not yet use business
SQLite; it is not a SQLite product-distribution or power-loss guarantee.

## Profiles, settings, and effective parameters (1C.5)

Run the same member generation/schema guard and full core command; the existing
CI suite discovers these tests. Targeted local command:

```bash
(cd packages/meshchan_core && dart test --reporter expanded \
  test/repositories/profile_public_test.dart \
  test/repositories/profile_settings_test.dart \
  test/repositories/profile_validation_test.dart \
  test/repositories/parameter_resolver_test.dart)
```

No additional test framework or CI job was added. `profile_fixtures.dart` supplies
complete legal presets for success paths; older codec-only fixtures keep their
original structural scope. The existing real QueryInterceptor is minimally
parameterized by actual read table and additionally intercepts insert-on-conflict
settings writes. It still defaults to stored_drafts for previous tests. All
native hook/generation/test/build gates remain sequential.

| Test file/group | Evidence |
| --- | --- |
| `profile_public_test.dart` | Business work imports only the public entry; all four operation presets, duplicate names/exact Unicode, secure ID shape, settings/default resolution with binary bytes, listing/deletion/reset and actual file reopen. |
| `profile_validation_test.dart` | Parameterized lower/upper invalid bounds across all operations, inclusive legal boundaries, startup/init relationship, no task-budget ordering restriction, endpoint range/distinctness, send/listen dataType zero difference, exact helper-validated routes, no byte truncation, and unpaired surrogate rejection before clock/write. NUL-name regressions check the real SQLite schema predicate, reject incompatible create/update before transactions/queries/clock/ID, preserve compatible NUL text through update/reopen, and classify stored constraint violations as corrupt. |
| `profile_settings_test.dart`: save | Canonical deep no-op with reordered/indented stored JSON performs no UPDATE/time call; operation replacement clears irrelevant fields. UTC microseconds/equal/backward clocks, missing update target, independent draft ID seam, targeted collision retry/exhaustion, non-ID trigger failure without retry, and protected entropy/clock exceptions. Concurrent valid profile saves both succeed in order. |
| Settings/default references | Absent read does not insert; save/reset and 1..100000 limits; dangling references fail but explicit null/reset repair them. Delete clears only default reference while retaining a nondefault limit, drafts, and exact stored run/association. Controlled concurrent save/delete orders produce the contracted null or not_found outcomes. |
| Pagination/damage | Default/1/50/200 page sizes, tied timestamps, exact terminal pages, deleted cursor continuation and corrupt probe. EXPLAIN of actual intercepted SQL requires two-key profiles_updated SEARCH, rejecting full scan/temp sort. Raw type, JSON, operation, semantic route/budget and settings damage fail as database_corrupt at accessed boundaries. |
| Mutation atomicity | Create/update/delete/settings-save/reset each reject a real write and separately reject before actual COMMIT, observe rollback, immediately read complete old state on the same handle, then write normally and reopen. Deleting the default rolls both profile and reference back on failure. |
| Lifecycle/errors | Close barriers cover admitted profile mutation, settings read/save and resolver (closing between settings and profile SQL); accepted work finishes and new/old handles fail appropriately. Existing process closeUnconfirmed test now covers new repositories/resolution. SELECT failures in mutations use write fallback; read/list/settings/resolver use read fallback. |
| `parameter_resolver_test.dart`: selection | Explicit > default > no preset; explicit selection bypasses unrelated dangling/corrupt settings. Missing selected/default references and wrong operation cannot be bypassed by complete overrides. Complete invalid stored profiles fail before overrides. |
| Presence/merge | Per-field budgets/endpoints, zero channel/descriptor/startup, listen filter inherit/null/zero, inherited versus explicit empty paths, descriptor-only mismatch, final cross-field failure and every required diagnostic field without invented defaults. |
| Content/capacity | Missing versus explicit empty send/PING bytes, arbitrary binary, UTF-8 byte-count boundary, Flood and all legal zero-hop Direct forms, 0x60/64-byte path raw 107 versus diagnostic 73 and one-over-limit; Flood 165 versus 131. Respond resolves without unknown future content. |
| Snapshots/no side effects | Mutable path/payload are changed immediately after async call and while SQL waits; result remains copied/unmodifiable. Later operation edit/delete leaves the resolved result unchanged. Successful/failed resolution preserves all profile/settings/draft/run rows and consumes no ID/clock. |

See the separate [1C.5 validation record](development.md#1c5-local-validation-on-november-12-2026)
for observed command results/toolchain. Schema 1 and frozen artifacts are
unchanged. Retention selection/pruning/export (1C.7), diagnostic snapshot mapping,
registration/recovery/coordinator (1C.6), and CLI parsing/explicit-port/execution
wiring (1C.8) remain unimplemented. Current native CLI smoke has no business
SQLite execution path and does not establish SQLite product AOT distribution.
No device enumeration, transport/session/task construction, RF trial, arbitrary
power-loss test, or remote CI success is inferred from this coverage.

## Recording and startup recovery (1C.6)

Run `dart test test/recording` from packages/meshchan_core for the focused suite,
then the complete core suite (including repositories, ownership and subprocesses).
Recording tests use real SQLite files, public core/link operation paths and real
session/tasks with fake transport. Internal imports inspect rows, inject storage
failures and exercise protected transitions. No private link constructors,
alternate inbox consumer or real device is used.

| Test under meshchan_core/test/recording | Evidence |
| --- | --- |
| projection_test.dart | Four snapshots, byte/path lengths, units/policies, explicit enums, null versus false/zero, absent reception, RTT/aggregate semantics and contradictory facts. |
| recording_test.dart | Prepared barrier; zero factory on insert/commit/ID/clock failure; factory/host failure; queued send versus preceding read; early PONG then late write failure; success plus native/host cleanup failure; partial host cleanup while another Future hangs; raw send success/write/rejection/timeout/cancel, listen trailing/filter/ordinary counts, responder limits and sensitive-field exclusion. |
| run_store_test.dart | Equal facts/different times, conflict/archived guards, cumulative failures, eight-attempt collision limit; real write/SELECT/pre-COMMIT failures, same-handle rollback and subsequent writes; clock captured before blocked SQL while cleanup already starts. |
| recovery_test.dart | Recovery matrix, partial PONG/nulls, first-time idempotence; multiple batches/ties/unchanged complete rows; later batch rollback preserving prior commits; damaged JSON/semantics/newer format/read/write/clock categories; independent prepared/logical-committed process interruption windows. |

The controlled child in test/storage/process_peer.dart stops after the actual
registration commit with no transport, or uses the public recorder while native
close hangs after logical commit. New exclusive open archives only committed
evidence without replay. Existing ownership tests stay intact; no duplicate lock
matrix is added. Pending-cleanup tests begin storage.close, verify a contender
is busy, then release cleanup and inspect saved facts after reopen.

The synchronous-cancellation regressions in recording_test.dart cover raw send
and listen when the first subscribe callback cancels before returning, including
repeated cancellation and a second returned subscription. They verify exactly
one cancellation per source, persisted pending cleanup while another source is
blocked, retained failures, close/owner protection, and final facts after reopen.
Separate cases throw during later registration and verify all already returned
subscriptions are still canceled. Operation cancellation stays immediate; only
host cleanup settlement waits for the synchronous registration pass to finish.

The raw cancellation-precedence tests inject a transport error and immediately
cancel in the same turn, before session events or command continuations run.
Both send and listen are covered during initialization and ready-state work.
They assert the earlier failure's reason/stage and root evidence, frozen send or
reception facts, logical commit while native cleanup is blocked, and exact
summary preservation after cleanup/reopen. Reverse-order controls cancel first
and then inject an error, confirming the frozen canceled result stays unchanged.

Old codec fixtures intentionally contain structurally valid but business-invalid
records, including descriptor 0x12 with two path bytes. They still round trip on
the same handle. Reopen/isolation uses separate legal terminal fixtures with
0x02/two bytes. Explicit residual fixtures exercise recovery; production open has
no testing bypass. Fixture corrections preserve original structural coverage.

After locked pub get, run build_runner/check_schema, root format/fatal-info
analysis, full core/link/CLI, Python tests, the three native builds and shared
smoke sequentially, as in CI. The runnable public fake example adds no hardware
claim. Current CLI has no business SQLite execution: bundles/smoke do not establish
SQLite product AOT distribution. No arbitrary power-loss, real RF/hardware, Linux
or remote CI result is inferred. See the dated
[1C.6 local record](development.md#1c6-local-validation-on-november-12-2026).

## History, retention, and safe export (1C.7)

From packages/meshchan_core, `dart test test/history` runs the focused real-file
suite. It uses legal business fixtures, the existing fake transport/session
boundary and real SQLite transactions. No maintenance skip switch or raised
blanket retention limit is introduced. Existing profile/settings commit-failure
cases now await their preceding settings-triggered maintenance before arming the
next one-shot commit fault, so the fault still tests its intended transaction.

| Test file under test/history | Evidence |
| --- | --- |
| history_test.dart | No-I/O stable getter; public read/filter/real reopen; closed-handle rejection; operation/state shapes and actual executed SQL/arguments with EXPLAIN; composite seek/no temporary sorting; UTC microsecond half-open range; prepared-time semantics; 50/1/200 limits/ties/probe/end/empty/cursor deletion; eligibility matrix, failed cleanup/recovery, guarded atomic deletion and immediate rollback. Damaged JSON/SQL type/lifecycle/newer summary fail history/export/delete/maintenance, including a corrupt extra probe. |
| retention_test.dart | Global eligible rank and reversed insertion/time order, 128-row ties and hundreds of ineligible rows, default 1000 open/recovery and custom 1/100000 settings/reset triggers; per-batch limit changes, deletion of a counted retained row, new eligible record invalidation; later DELETE/pre-COMMIT failure preserves prior commits and immediately rolls back the bad batch; healthy retry; startup and sticky failures; dangling default versus corrupt settings; coalesced maintenance and close/owner barriers on success/failure. |
| recording_history_test.dart | Real terminal intermediate cleanup save before final save: concurrent delete conflicts, prune defers and keeps newer retained history; final save succeeds then unpin triggers pruning. Committed recording survives prune failure without resends, construction failure unpins, and admitted cleanup/save/automatic maintenance survive close while owner stays reserved. |
| export_test.dart | Parsed JSON exact root/run/nested field sets across four operations; real profile/port/draft/content/test-ID samples excluded; profileId still present in internal read; route/path-byte counts and payload lengths retained; pending/null/false/zero, PONG with local failure, logical success with cleanup failure and recovered unknown facts; zero/nonzero fixed six-digit UTC; bounded two-page continuation and filter. |

HistoryControl delegates to the actual executor, captures real SELECTs and bound
arguments, executes EXPLAIN on those exact statements, and intercepts actual
DELETE and pre-COMMIT paths. Cross-batch host actions run in the captured host
zone rather than accidentally inheriting Drift's already committed transaction
zone. Recording barriers distinguish the intermediate terminal read, concurrent
guarded delete read and final save read. No independent pin-set mirror is tested.
The old ownership/platform matrix and both 1C.6 cancellation regression groups
remain in the complete core run.

Use the existing CI sequence: locked pub get, build_runner, schema guard, root
format/fatal-info analysis, complete core/link/CLI tests, Python tests, three
native bundles and source/AOT smoke. Keep tests/builds sharing native assets
sequential. See the [dated local record](development.md#1c7-local-validation-on-november-12-2026)
for executed results and limits; CI configuration alone establishes no remote
pass. Current CLI bundles still do not execute business SQLite, so their smoke
is not SQLite product AOT distribution acceptance. No RF/hardware claim is made.

## Product business CLI coverage and source/AOT SQLite (1C.8)

The shared smoke now executes real product SQLite, in addition to its retained
legacy help/rejection/broken-pipe and five synthetic datagram scenarios. For
source, the freshly built product AOT bundle, and a relocated complete bundle,
it creates an isolated directory, commits an exact UTF-8 draft, reads it in a
second process, saves a profile/settings, reads settings again, queries empty
history and decodes the raw safe export envelope. It checks that the database
file exists at the explicit directory and does not appear in cwd. These gates
exercise the SQLite native asset at runtime; help-only serial smoke is no longer
the sole product bundle evidence. Retained dated 1C.2–1C.7 records above describe
their older bundles accurately and are not retroactively upgraded.

`business_cli_test.dart` exercises the real parser, platform directory policy,
zero opener/device side effects, strict UTF-8/BOM/newline input, true file
reopen, partial/no-op/stale revisions, bounded cursors, four complete profile
types/replacements, NUL name compatibility, default deletion and partial/full/
reset settings with damaged or dangling old values. `business_datagram_test.dart`
uses real SQLite and existing controllable transports to test presence/default
merges, empty/zero/clear semantics, exact current ports, post-merge capacity,
no-record history absence and legacy output, four recorded operations, actual
registration/logical/cleanup commit faults, early PONG/local write failure,
logical success/cleanup failure, cancellation during prepared and synchronous
subscribe, frozen session failures, output failure and pending actual cleanup.
The real host-subscription cancellation Future remains evidence of release.
Offline signal/output tests hold a real commit boundary, preserve committed data
and wait for close; process-signal cancellation tests prove both watches start
canceling even when one hangs and the other fails.

`business_history_test.dart` covers typed filters/cursors, deleted cursor rows,
recovery facts, guarded deletion, raw bounded export/metadata/output failures,
sticky startup failures, committed settings with failed retention, completed/deferred/failed prune reports, partially
committed prune batches, post-done unpin maintenance and actual DB-close barriers.
`business_process_test.dart` adds controlled owners in another process, independent
directories, normal close/reopen and actual native-close rejection/quarantine.
The test-only core history fixture accepts an explicit temporary directory;
production CLI continues to import only the core public barrel. Audited wrappers
delegate actual work and reject any new history I/O after close begins.

All datagram regression/acceptance `runCli` callers now use explicit temporary
directories through `test/support/isolated_cli.dart`. The shared source/AOT
acceptance probe therefore exercises real storage without touching user defaults.
Old nonbusiness session tests still prove storage is never opened. New finite
openHop plan generation also emits a separate absolute `--data-dir` per product
case under its new output directory; validation/summarization can still read
retained older argv. No RF matrix is executed by these tests or smoke.

Use the existing sequential reproduction procedure above, including locked pub,
core generation/schema checks, format/analyze and all three package suites. The
same `tool/smoke_cli.py` arguments now cover business SQLite automatically; build
a fresh **whole** product bundle before passing it to smoke. In this step's local
run the three new output paths are:

```text
build/phase-1c8/final/meshctl/bundle/
build/phase-1c8/final/observation/bundle/
build/phase-1c8/final/datagram-acceptance/bundle/
```

See the [dated actual command/results record](development.md#1c8-local-validation-on-november-12-2026)
for observed counts, toolchain and failures. Directory resolution branches are
unit-tested for macOS/Linux/Windows, but local native product execution here is
macOS arm64 only. Linux blocked enumeration remains unchanged and CI still uses
the same shared smoke; no remote passing CI result is inferred. Full dev.3
packaging, notices, clean-machine/other-platform distribution and remaining
hardware/RF work belong to 1C.9 or their original acceptance tracks.

### Datagram storage-phase signal regression

The [subsequent 1C.8 review fix](development.md#1c8-review-fix-signal-ownership-across-storage-phases)
adds `datagram_storage_signals_test.dart`. It gates a delegating real SQLite
opener, resolver and close Future, injecting SIGINT/SIGTERM through a broadcast
source in both recording modes. All 12 original reproductions fail on the old
wiring. The complete 26-case file also covers source errors, real cancellation
Futures, frozen device failures and signal/output ordering while closing.

`datagram_signal_process_test.dart` starts the controlled
`test/support/datagram_signal_process.dart` child. Eight cases use actual process
signals during open/close, acknowledge actual delivery before releasing the gate,
verify the directory is still busy, then require orderly 130/143 exit and reopen.
This checks the lazy production `processStopRequests` source as well as injected
streams. It uses no real port or RF and no sleeps to guess delivery order.

The real invocation source outlives the runner's forwarding observer and the
storage close barrier. Tests distinguish saved core cleanup from the new
`signalCleanup` output and verify that a pending/failed real source cancellation
is never hidden by a successful observer cancellation. Existing normal no-record
JSON remains unchanged. Updated pre-admission cancellation tests preserve null
logical facts when no device operation was admitted. Review-fix validation/logs
and fresh source/AOT bundle results are recorded in the linked development entry.

### Admission-failure precedence and native-asset suite serialization

`datagram_failure_priority_test.dart` adds 18 controlled cases. Real SQLite DDL
and registration transactions fail behind an explicit gate after SIGINT,
SIGTERM or sink failure has been observed; public parameter resolution fails
under the same ordering. Tests cover both recording modes, retain later core
code/source facts, assert zero transport/subscription-plan factories when
registration rolls back, and reopen the file to verify no diagnostic committed.
Reverse-order controls observe a resolution/registration failure before injecting
a signal during close and require that earlier failure to stay primary. No sleeps
or repeated device operations are used to force ordering.

`apps/meshctl/dart_test.yaml` sets `concurrency: 1`, matching the existing core
package policy. Both subprocess suites launch `dart run` children whose native
assets are bundled into the workspace's shared `.dart_tool/lib`; separate data
directories do not isolate that SDK state. The default package `dart test` now
runs files sequentially, preventing cross-suite bundling overlap without skips,
retries or altered native libraries. The owner/probe processes within the
ownership test still coexist intentionally, with each next launch starting only
after the previous child's startup/bundling readiness acknowledgment. Keep package
test commands and native builds sequential as before, and do not override CLI
suite concurrency when these source-process fixtures are included.
The [review-fix validation record](development.md#1c8-review-fix-observation-order-and-serialized-process-suites)
records both default-suite runs and fresh bundle/smoke results.

### Offline storage failure before signal cleanup

`business_history_test.dart` gates a real settings transaction, then fails the
resulting retention delete and the later signal-subscription cancellation. The
command must retain its committed settings and maintenance error, return
`storage_finalization_failure`/74, and report the host cleanup failure separately.
A control injects SIGTERM before the transaction settles and requires that earlier
143 result to remain primary. Both cases verify storage is closed before signal
cleanup starts, only one final object is written, and settings survive reopen.

`business_process_test.dart` extends the native-close rejection child with a
failing signal cancellation, for both draft creation and history export. It
requires 74 in the actual child exit and final metadata, preserves
`closeUnconfirmed` and quarantine until process exit, retains the host failure,
and confirms the committed draft can be read after the child exits. The export
remains the unchanged core summary envelope. These fixtures use no device or RF.
See the [offline finalization validation record](development.md#1c8-review-fix-offline-finalization-failure-priority)
for reproduction results, commands and logs.

### Required offline IDs and revisions

`business_cli_test.dart` covers missing IDs on every applicable draft/profile/
history action, missing draft mutation revisions, both fields omitted, and
missing fields together with an unreadable body file. Each case runs through
the real parser in text and JSON mode and requires exit 64 with no stdout,
directory-policy/opener/signal-subscription/device calls, port enumeration or
data-directory creation. Fixed errors must identify the option without echoing
secret-marked input. Help/version controls keep the existing short circuits.

`business_process_test.dart` exercises the product entry with a complete
profile-update preset but no ID, a draft show without an ID, and a draft delete
without a revision. Each must return 64 without creating its isolated data
directory or a database. This guards the public core API's intentional
`profiles.save(id: null)` create behavior from accidental CLI update admission.
The [required-option validation record](development.md#1c8-review-fix-required-offline-ids-and-revisions)
contains the before/after results, commands and logs.

### Offline primary and additional error fields

`offline_failure_priority_test.dart` covers ordinary JSON and export metadata
with SIGINT/SIGTERM/output failure observed before real SQLite creation failure,
draft transaction rollback or export read failure. Explicit gates control the
ordering. Each case requires the external reason/code, null primary failure and
the later stable storage error in additionalFailures. Failed operation/commit
facts stay false, no failed export invents a summary, acquired handles close
before signal-source cancellation, and files reopen with no partial data.

Six reverse-order controls inject the external intent while close is pending
after a real operation failure; the earlier storage error must remain primary.
Tests fail the output channel that does not carry the selected final envelope or
metadata, exercising real CliOutput sink failure without hiding the assertions.
Secret-marked source errors/body data must never appear in diagnostics. No
scheduling sleeps or device actions are used; reopen checks happen after cleanup.
See the [offline error-envelope validation record](development.md#1c8-review-fix-offline-primary-and-additional-failure-fields)
for the reproduction, commands and observed results.

## Final dev.3 delivery checks (1C.9)

The [dev.3 record](releases/phase-1c-dev3.md) binds the final software/native gate
and extracted archive to actual inputs. `tool/validate_dev_candidate.py` records
sequential enforced resolution, generation/schema/frozen artifacts, format,
fatal-info analysis, all Python and three Dart suites, three complete fresh
bundles and the existing shared smoke. CLI test-file concurrency stays 1.
`candidate_common_test.py` covers first-party classification, missing originals,
core input invalidation, required gates and exact recursive assets, safe archive
members/types/modes/bytes, and the extracted product's shared business gate.
Historical `revise_dev_candidate_test.py` regressions remain independent.

The development acceptance probe reuses existing fixed serial vectors for three
real runCli/core recordings: successful send, recorded listen, and later native
cleanup failure with preserved logical success and committed saves. All checks
use explicit runtime failures in AOT; VM smoke enables assertions. Closed probe
files are read/exported by the actual product in separate processes, including
same-host relocation and final archive extraction. They are synthetic fixtures,
not product RF-input evidence. Export checks retain null/false/zero, both cleanup
scopes and microsecond time while excluding sensitive fields.

`tool/check_schema_compatibility.py` generates a genuine schema-1 business file
with unchanged PR #25 dev.2 production source, preserves the closed original,
then checks old rows byte-for-byte after dev.3 recording/commit/reopen. It also
checks explicit future/corrupt-file rejection and preservation. Existing recovery,
retention and native ownership/process suites remain the detailed contract gate.
The controlled fixture is not a product import or backup facility.

The 1C.9 delivery-tool review adds `tool/delivery_environment_test.py`. It sends
an explicit environment to a real child, checks that compatibility passes its
prepared environment, exercises relative smoke evidence paths across different
child working directories, and collects exact original SDK notices from synthetic
SDK/Flutter-launcher/symlink layouts with distinct framework and SDK licenses.
Incomplete SDK layouts are rejected even when a framework LICENSE exists.
The [dated review follow-up](development.md#1c9-delivery-tool-environmentpath-review-follow-up-on-november-12-2026)
records 61 complete Python tests, a real compiler-environment compatibility run,
101 relative-evidence source/AOT smoke checks and actual installed-launcher
license collection, around unchanged product inputs and native bytes.

A subsequent schema-path review adds four delivery-tool regressions for escaped
read-only SQLite URIs (including `#`, `%`, `?`, Unicode and conflicting filenames),
missing-file/no-stray-file behavior, relative executable use across two real child
cwds and invalid executable rejection before build work. The
[dated schema-path follow-up](development.md#1c9-schema-path-review-follow-up-on-november-12-2026)
records **65 complete Python tests**, **9 targeted tests**, **8 relative-Dart
compatibility process checks** and **4 special-path database/native checks**.
The combined legacy-source build under a URI-significant cwd remains blocked by
the installed Dart native-hook launcher, with the failed attempt retained.

Root `analysis_options.yaml` excludes `build/**` so preserved candidate native
source fragments and legacy checkouts cannot pollute subsequent workspace gates.
The [retained-artifact analyzer follow-up](development.md#1c9-retained-artifact-analyzer-review-follow-up-on-november-12-2026)
reproduced the 28 artifact diagnostics, verified that a deliberate core-library
type error still fails root analysis, removed that temporary probe and reran
root fatal-info analysis successfully with every old material file retained.
Root format (707 files, zero changes), all 65 Python tests and whitespace checks
also passed. Original manifests retain their original analysis-config hashes.


### Actual 1D.4 desktop GUI acceptance

The [GUI follow-up](validation/phase-1d4-drafts.md#november-13-gui-follow-up-after-ide-permission-restart)
records actual Debug/Release Chinese Pinyin, keyboard/clipboard, explicit saves,
exact reopen, delete, dirty navigation and native quit decisions, plus a relocated
Release product chain. It supplements the earlier software/probe/native callback
results. Foreground the complete app by exact path with LaunchServices, explicit
owned `--data-dir` and `open -W`; do not use a default-library launch to diagnose
window visibility. Reused Bundle IDs and background/other-space windows can make
an app process insufficient for GUI access. Validate native accessibility/event/
capture access and app semantics without automatically modifying OS permissions.
The user explicitly authorized the follow-up's fixture-scoped native UI driver and
manually granted IntelliJ control access/restarted it. Ordinary CI retains its
hardware-free software/worker/process gates; this local interactive run does not
claim remote CI or a system logout/restart/shutdown matrix.

After normal Quit, check the OS process and the captured shutdown report; do not
query an exited application through Computer Use, which was observed to relaunch
it without arguments. Launch every new session explicitly with its fixture first.
The follow-up records one such default-directory opening as an isolation exception;
its GUI passes do not imply complete fixture isolation.

## Profile/settings and presence checks (1D.5)

Use the existing Flutter SDK and the local stable Python 3.15+ described above.
`profiles_test.dart` checks complete subtype mapping, A/B save state, raw lexical
failures, exact text, presence and content bytes, settings replacement, late
preview/unknown, shared quit, composition, scoped shortcuts and real worker
admission. `check_profile_process.py` uses fixtureWrites false with public core,
real SQLite, independent owner/contender/reopen processes, delayed create/final
update and committed reply loss. CI runs it in both jobs, sequentially with shared
native hooks. It neither imports private storage hooks nor opens serial hardware.

```bash
(cd apps/meshchan_app && flutter test --no-pub)
python3 apps/meshchan_app/tool/check_profile_process.py --dart "$(command -v dart)"
```

On this Mac, use command-local Apple Clang PATH and explicitly invoke
`/opt/homebrew/bin/python3`; its children use `sys.executable`. Protocol integers
use decimal or 0x/0X hex; budgets/durations/limits use decimal; paths/Hex content
use even-length ASCII hex without separators/prefix. No trim, fallback or clamp.
Preview is explicit and offline; missing required fields must fail through core.

All GUI/Debug/Release/process validation must use a new owned `--data-dir`.
Before native UI reads, verify the live PID and its exact fixture argv. After
Quit, inspect only OS process state and existing logs; do not ask Computer Use
to read a closed app (it may relaunch without arguments). Restart explicitly
with fixture arguments for each new round. XCTest retains disabled-owner isolation
before engine/bootstrap and does not inherit ordinary Launch arguments. Platform
GUI, IME, Undo and dirty quit are separate from software callbacks; record NOT_RUN
or BLOCKED where actual input cannot be verified. See the
[1D.5 evidence](validation/phase-1d5-profiles-settings.md).

## Native GUI preflight: storage location and Pinyin/ABC

Follow the [reusable macOS GUI setup](development.md#reusable-macos-gui-fixture-and-input-setup).
Use an owned `/private/tmp` fixture and complete copied app, with stdout/stderr
also outside Documents, launched from an unprotected cwd with explicit `--data-dir`. A repository `build/` directory inside
Documents is still protected Documents access and caused repeated permission
dialogs during 1D.5 testing. Avoid those paths for routine GUI runs; keep receipts
and evidence in ignored build output, and do not change product defaults or macOS
security settings. Copy/move fixture data only after confirmed normal owner close.
Native XCTest needs the same external host/products/cwd/log setup, in addition
to disabled-owner isolation. Preflight `TARGET_BUILD_DIR`, `TEST_HOST` and the
generated `.xctestrun` before running the test host. A copied product GUI does
not relocate a separate checkout-local XCTest host. Canonicalize `/tmp` and
`/private/tmp` when checking the owned directory boundary.

On the current Mac **Command+Space switches input sources**; **Control+Space
opens Raycast**. Caps Lock is additionally user-configured to toggle Pinyin/ABC.
Use the personal `$macos-pinyin-input` skill for the full reusable procedure.
After any launcher overlay, dismiss it without running a result and recheck the
actual keyboard-focus owner as well as the foreground PID. Input-source
selection does not establish Chinese composition: check actual underlined preedit
and candidates in the focused fixture field, and press Caps Lock once if needed
under that existing configuration. Plain Latin text and pasted Chinese are not
Pinyin acceptance. Do not assume the shortcut on other machines or change their
configuration. Restore the user's latest intended mode, including steering made
while a test is running. Record the source/mode, actions, screenshots, and exact
independent committed read after normal close.

## Finite device checks (1D.6)

Run the app suite sequentially (`dart_test.yaml` retains `concurrency:1`) and the
new process gate, in addition to the existing runtime/Draft/Profile gates:

```bash
(cd apps/meshchan_app && flutter test --no-pub)
python3 apps/meshchan_app/tool/check_device_process.py --dart "$(command -v dart)"
```

On this Mac use `/opt/homebrew/bin/python3` (verified stable 3.15+), bundled Dart
and the existing Flutter SDK. `device_check_test.dart` combines the actual public
session with an app-owned public `CompanionTransport`; the entire enumerator is
injected, never just fake paths passed to native metadata handles. Tests cover
separate information/cleanup results, constructor ownership, observer cleanup,
initialization pair/no inbox, stage cancellation and timeout/no retry.
`device_dispatcher_test.dart` checks authoritative raw admission, metadata errors,
stop before resource construction and stale leases. `device_worker_test.dart`
and `device_quit_test.dart` use the production dispatcher/controller, a real
isolate, SQLite, blocked cleanup, delayed/lost ack, scoped cancellation, final
save/Continue and coalesced Quit. `check_device_process.py` adds independent
contender/reopen processes and a quarantined fault child. Explicit fault-child
process exit is reclamation, never evidence of normal release. No test entry
performs native serial enumeration/open by default.

GUI evidence must use the complete external owned app/fixture/cwd/log/driver and
native XCTest setup described above. Actual Refresh is an explicit metadata-only
action. Never select/open an enumerated path on the user's behalf. Actual USB
Check needs an exact path explicitly selected in the current task/app session;
no hint, historical path or unique result grants that permission. Mark USB
NOT_RUN when no such selection/hardware exists. Ready/info proves initialization,
not authentication, radio TX/RX or a round trip. See the
[1D.6 evidence](validation/phase-1d6-device-check.md) for tested layers and limits.

The unlocked 1D.6 follow-up adds a focused **macOS mouse** regression for all
Device inputs: use the EditableText descendant of the actual TextField, a valid
selection/composing range and PointerDeviceKind.mouse. A touch-only or unfocused
controller test misses default desktop outside-tap behavior. Actual Debug and
Release then verified underlined Pinyin/candidates, physical menu/navigation/
Cmd+Q deferral and natural exact commit. Final app count is 159; final-source
isolated native count is 11. Native automation must not redundantly raise or
reactivate a window during a live preedit assertion. Preserve failed preflights
and distinguish actual USB info success from a safely cleaned initialization
failure; the 1D.6 record documents both outcomes on the explicitly selected port.
