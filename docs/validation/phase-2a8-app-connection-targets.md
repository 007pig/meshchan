# Phase 2A Step 8 App connection targets

## Source and toolchain

The November 26, 2026 starting checkout was a clean `master` at
`9d2f1286dff17e0e5ef35e4812708902c5980348`, matching local `origin/master`.
That is the merge of [PR #58](https://github.com/007pig/meshchan/pull/58),
whose Step 7 head is `62c417eb845bae9d3407383c0fcf01052fdd0b80`. Step 8 uses
the existing public target and transport factory on the local
`codex/phase-2a8-app-connection-targets` branch. The verified source snapshot
is `b25ea98c0b9872c44078397201499a2fd8926621`. Its parent `1e9442c8021fa4fe765e1f0a1252c0548ba3c7dc`
contains the App runtime and probe template changes. The earlier CLI tests
and builds are recorded with Step 7.
[Step 7 validation](phase-2a7-cli-connection-targets.md)

The installed `/opt/homebrew/share/flutter/bin/flutter` reported Flutter
3.50.0 stable (framework `ab2912035e`, engine revision `371f77202a`). The
bundled Dart SDK at `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart`
reported 3.14.0 stable on `macos_arm64`. Xcode was 27.2 (`27B52`). The native
commands put `/usr/bin` first for Apple Clang 21.0.0 (`clang-2100.4.1.1`).
`/opt/homebrew/bin/python3` reported 3.15.2 and `sys.executable` was
`/opt/homebrew/opt/python@3.15/bin/python3.15`.

## Connection path and lifecycle

- Device Check and recorded Ping/Responder each construct a `UsbSerialTarget`
  from the exact explicit selection. The controller carries it in the typed
  Start request within the existing isolate envelope. The worker composes
  separate Check and Diagnostic `CompanionTransportFactory` defaults with
  `appCompletionQueries: true`. Each actual creation returns a fresh, unopened
  transport. Startup opens storage. Refresh lists metadata under the existing
  gate without invoking either factory.
  [Device model](../../apps/meshchan_app/lib/device/model.dart) ·
  [Diagnostics model](../../apps/meshchan_app/lib/diagnostics/model.dart) ·
  [Controller](../../apps/meshchan_app/lib/runtime/controller.dart) ·
  [Requests](../../apps/meshchan_app/lib/runtime/protocol.dart)
- The worker checks envelope generation and request ID first. Check then
  checks whether admission is stopped, validates the Check ID, USB target,
  and options, and acquires a lease. Diagnostic validates the attempt ID,
  USB target, and Ping/Responder operation before `_beginRecording` checks
  whether admission is stopped and acquires a lease. A valid TCP or BLE
  value receives `invalidState` at the applicable input validation boundary.
  The rejection takes no lease and calls neither the enumerator nor the
  factory, parameter resolver, or recorder. The Diagnostic controller
  checks its pending Start latch before its input preflight.
  [Dispatcher](../../apps/meshchan_app/lib/runtime/worker.dart)
- Check installs its settlement barrier before the event-loop checkpoint
  preceding construction. Once the factory returns, the runner holds the
  transport until the session takes ownership. If session construction
  throws, the runner awaits the unowned transport's actual close. An
  initialization snapshot can expose timestamped information while cleanups
  are pending. A later cleanup failure retains that information and has
  its own evidence. Session close and observer cancellation must settle
  before Check calculates release. Check performs finite initialization only.
  [Check runner](../../apps/meshchan_app/lib/runtime/device_check.dart)
- The Diagnostic lease and settlement barrier precede queued parameter
  resolution. The worker gives the recorder a zero-argument closure that
  captures the target. Core commits registration and checks cancellation
  before calling it. Logical completion, logical save, actual cleanup,
  cleanup save, and adapter observation remain independent. Cancel is
  attempt-scoped. An ACK leaves actual cleanup pending until observed, and
  unconfirmed release quarantines the gate. Normal Quit waits for admitted
  work, affirmative release, the release acknowledgment exchange, and
  actual exit of a spawned worker.
  [Core recording](../../packages/meshchan_core/lib/src/recording/recording.dart) ·
  [Recording adapter](../../apps/meshchan_app/lib/runtime/recording_adapter.dart) ·
  [Quit contract](../architecture/flutter-host.md#normal-quit-and-desktop-behavior)
- The check snapshot and device information display `portPath` verbatim.
  The diagnostic model associates the original path with the local attempt
  ID across selection changes and missing or delayed ACKs. A preset's
  `portHint` supplies no target. Effective parameters, the database schema,
  safe faults, and Operation, History, and export projections keep their
  existing field boundaries.
  [Device projections](../../apps/meshchan_app/lib/runtime/device_protocol.dart) ·
  [Diagnostic input context](../../apps/meshchan_app/lib/diagnostics/model.dart)

## Regression evidence

- The real-worker integration starts from Device and Diagnostics models and
  observes `UsbSerialTarget` values at the injected factories for Check,
  Ping, and Responder. The paths contain surrounding spaces and a legal tab.
  It changes selection after Start, tests a different profile hint, runs a
  successful Ping and zero-response Responder, and reopens the SQLite
  directory for History and safe export. Model tests cover blank and NUL
  selections and recovery. With a pending Start acknowledgment, the model
  withholds the old result while admission is unknown. When the Start future
  reports `requestUnknown`, either an observed new result or a retained old
  result still maps to its own path.
  [Isolate test](../../apps/meshchan_app/test/diagnostic_worker_test.dart) ·
  [Device model tests](../../apps/meshchan_app/test/device_widget_test.dart) ·
  [Diagnostics model tests](../../apps/meshchan_app/test/diagnostics_test.dart)
- Raw requests cover both unsupported target types, stale envelopes,
  stopped and busy ordering, and reuse of unadmitted operation IDs.
  Ready-worker rejections leave the gate free at the same generation with
  zero enumeration, factory, resolution, and recording calls and zero runs.
  Check tests cover the pre-construction cancellation checkpoint, fresh
  transports, factory and session construction faults, open/initialization
  cancellation, and pending and failed session and observer cleanup.
  [Admission tests](../../apps/meshchan_app/test/diagnostic_admission_test.dart) ·
  [Check runner tests](../../apps/meshchan_app/test/device_check_test.dart) ·
  [Check dispatcher tests](../../apps/meshchan_app/test/device_dispatcher_test.dart)
- The recording admission test arms a one-shot hook after the real SQLite
  registration commit. Each factory entry records the commit fact, the
  exact USB target, and an open count of zero. Both attempts create, open,
  and close one separate transport. Resolution and registration failure,
  cancellation during resolution or commit, and cancellation in the same
  stack that returns from `record()` each leave the transport factory and
  subscription plan uncalled. Quit regressions retain admitted offline work,
  independent cleanup, scoped cancel, and the release and exit barrier.
  [Recording admission](../../apps/meshchan_app/test/diagnostic_admission_test.dart) ·
  [Device Quit](../../apps/meshchan_app/test/device_quit_test.dart) ·
  [Diagnostic Quit](../../apps/meshchan_app/test/diagnostic_quit_test.dart)

## Validation commands

Run from the repository root unless a subshell changes directories. Native
tests, process checks, and builds run serially. `meshchan_evidence` is a new
external directory for the current run.

```sh
meshchan_flutter=/opt/homebrew/share/flutter/bin/flutter
meshchan_dart=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
meshchan_python=/opt/homebrew/bin/python3
meshchan_base=9d2f1286dff17e0e5ef35e4812708902c5980348
meshchan_evidence=$(mktemp -d /private/tmp/meshchan-2a8-validation.XXXXXX)
export PATH="/usr/bin:$PATH"

"$meshchan_flutter" --version
"$meshchan_dart" --version
"$meshchan_python" --version
"$meshchan_flutter" pub get --enforce-lockfile
"$meshchan_python" tool/check_product_version.py --expected-version 0.1.0-rc.1 --app-build 10
{ git diff --name-only "$meshchan_base" -- '*.dart'; git ls-files --others --exclude-standard -- '*.dart'; } |
  sort -u | xargs "$meshchan_dart" format --output=none --set-exit-if-changed
"$meshchan_flutter" analyze --no-pub --fatal-infos

(cd apps/meshchan_app && "$meshchan_flutter" test --no-pub --concurrency=1 --reporter expanded \
  test/device_check_test.dart test/device_dispatcher_test.dart test/device_worker_test.dart \
  test/device_widget_test.dart test/device_quit_test.dart test/diagnostic_admission_test.dart \
  test/diagnostic_worker_test.dart test/diagnostics_test.dart test/diagnostic_quit_test.dart \
  test/recording_adapter_test.dart test/recording_worker_test.dart test/runtime_shutdown_test.dart \
  test/runtime_timeout_test.dart test/export_test.dart test/usb_initialization_transport_test.dart)
(cd apps/meshchan_app && "$meshchan_flutter" test --no-pub --concurrency=1 --reporter expanded)
(cd packages/meshcore_link && "$meshchan_dart" test --reporter expanded)

for meshchan_check in runtime device diagnostic history; do
  "$meshchan_python" "apps/meshchan_app/tool/check_${meshchan_check}_process.py" \
    --dart "$meshchan_dart" --evidence-root "$meshchan_evidence/$meshchan_check"
done

(cd apps/meshchan_app && "$meshchan_flutter" build macos --debug --no-pub)
(cd apps/meshchan_app && "$meshchan_flutter" build macos --release --no-pub)
meshchan_products=apps/meshchan_app/build/macos/Build/Products
for meshchan_configuration in Debug Release; do
  meshchan_bundle="$meshchan_products/$meshchan_configuration/Meshchan.app"
  /usr/bin/codesign --verify --deep --strict --all-architectures "$meshchan_bundle"
  /usr/bin/codesign --display --verbose=2 "$meshchan_bundle"
done
"$meshchan_python" apps/meshchan_app/tool/check_macos_runtime.py \
  --app "$meshchan_products/Release/Meshchan.app" \
  --expected-version 0.1.0-rc.1 --app-build 10 --evidence "$meshchan_evidence/macos-runtime"
```

## Local results

The App, link, and native command logs and the process fixtures are retained
under `/private/tmp/meshchan-2a8-validation.G2ce9S`.

| Check | Observed result and evidence |
| --- | --- |
| Locked resolution, source version, and analysis | `flutter pub get --enforce-lockfile` passed after the installed Flutter launcher received access to write its normal cache stamps. Source version verification reported App `0.1.0-rc.1+10`. `workspace-analysis.log` reports no issues with fatal infos. Root `pubspec.lock` SHA-256 is `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`, matching the baseline. |
| App formatting and targeted tests | All 21 affected `.dart` files passed format with zero changes. All 135 tests in the 15 listed suites passed in `app-targeted.log`. The first run recorded 128 passes and seven failures in the newly added dispatcher test harness. Its synchronous snapshot stream allowed reentrant delivery. After changing the harness to deliver snapshots asynchronously, all 14 diagnostic admission tests passed in `admission-after-harness-fix.log`. `app-targeted-initial.log` retains the first run. |
| Full App and link suites | All 282 App tests passed in `app-full.log`. All 264 link tests passed in `link-full.log`. |
| Runtime process | Passed. The contending process saw `data_directory_busy`. After normal release, a separate process reopened the directory, checked exact stored text, and observed release and exit with zero pending requests or receive ports. See `runtime-process.log` and `runtime/`. |
| Device process | Passed all four reported checks: blocked cleanup, delayed ACK cancellation, owner contention, and independent reopen. The separate fault case confirmed quarantine and failed normal release. See `device-process.log` and `device/`. |
| Diagnostic process | Passed all five modes: normal, resolve, stop, prepared, and fault. The checker compares history with independent reopen for the four normally released cases and checks the fault's release failure separately. See `diagnostic-process.log` and `diagnostic/`. |
| History process | Passed all three scenarios: normal History and export with independent SQLite reopen, recovery after a process exit during preparation, and recovery after a process exit following logical completion. Both recovery cases are checked twice for stable archival. See `history-process.log` and `history/`. |
| macOS Debug and Release | Both `Meshchan.app` bundles built. Both passed deep, strict verification for all architectures and reported `Signature=adhoc` under the `local-adhoc` policy. See `macos-debug.log`, `macos-release.log`, and `macos-signature-*.log`. |
| Complete Release AOT runtime | Passed three production runs at `0.1.0-rc.1+10`: write, read, and read after whole-App relocation. All observed affirmative release, actual worker exit, and zero receive ports and pending requests. The relocated signature verified. Both additional Quit cases passed: resource-free startup before spawning and ready Quit with an actual worker exit. See `macos-runtime.log` and `macos-runtime/`, including `runtime-processes.json`, `signature.json`, `startup-quit.json`, and `ready-quit.json`. |

The fault children are reclaimed by the fixture process. Their receipts keep
failed normal release and resource reclamation as separate facts. This run
covers App and worker software, isolated SQLite, and local macOS builds.
Physical USB, BLE, TCP and RF acceptance, interactive VM GUI and XCTest, DMG
and release distribution, and remote CI fall outside this validation. The
standalone CLI and core suites and Draft/Profile process matrices were outside
the changed App device boundary. The Step 3 and Step 4 probe hardware records
retain their original coverage and outcomes.

## BLE probe software validation

The cooperation harness wraps its private attempt token in a `UsbSerialTarget`
at the Check boundary. The injected worker factory reads `portPath` to create
the existing bridge proxy. The bridge still associates the Check snapshot
with the private token and keeps token/generation validation and release ACKs.
The root isolate retains physical BLE ownership. This software exercise uses
the fake bridge and applies to the probe harness. Production App admission is
USB-only. [Probe README](../../tool/ble_probe/README.md#worker-cooperation)

The probe was generated in `/private/tmp/meshchan-2a8-probe.Rk2Ehj/probe`.
Its [generator](../../tool/prepare_ble_probe.py) pinned runtime and package
source to `b25ea98c0b9872c44078397201499a2fd8926621`. The first attempt stopped
when Flutter could not write its SDK cache stamps. Preparation completed in
a fresh destination with authorized cache access, using the existing pinned
Darwin 6.2.1 archive and a private copy of the retained offline Pub cache.
The product and probe dependency locks were enforced. The generated host's
native hook cache used existing hash-verified SQLite binaries.

The retained `probe/evidence/probe-source.json` has SHA-256
`cbd48c72d74988d171641a809f5614cbf129a693b5bd4922433d34ca1858780a`.
Its `gitSnapshotCommit` identifies the Step 8 snapshot. The provenance check
compared the seven runtime files, 23 link source files, and 36 core source
files and their vendored bytes with their Git blobs. The receipt also records
25 template input hashes, package source and vendor hashes, the root and
probe lock hashes, and the patched native source hashes. The generator's
SHA-256 is `5f73235f9a9785d6a3a013a6b035969a53378e11595c6bc2713c3a1198c253ff`.
See `logs/receipt-verification.log` under the probe parent. The four changed
Dart template inputs have these SHA-256 values.

| Template relative to `tool/ble_probe` | SHA-256 |
| --- | --- |
| `lib/src/cooperation.dart.txt` | `a59b2bdce8b85baf4b7c7cd85be8e0ffca79318de49d7a93f17f4d15533a2fc3` |
| `lib/src/worker_proxy.dart.txt` | `7c5010dc37d2be26bb662f478ec866c9d7e352dcdb0cff68b49e5d8e8b37804b` |
| `test/worker_bridge_test.dart.txt` | `6600ac92ce269b369ba685a4cbb2fa62fb23eb623f7789231f27251b4385371a` |
| `tool/cooperation_test_fixture.dart.txt` | `e222a72efdc346c9e5423aa070226c71728bb9843a215fe2a6e84b5fb09e911a` |

The preparation and serial validation commands used the installed tools
defined above and the retained local inputs.

```sh
meshchan_probe_source=b25ea98c0b9872c44078397201499a2fd8926621
meshchan_probe_parent=$(mktemp -d /private/tmp/meshchan-2a8-probe.XXXXXX)
meshchan_probe_root="$meshchan_probe_parent/probe"
cp -cR /private/tmp/meshchan-ble2a4-pub-lock-mc5afvsn/pub-cache "$meshchan_probe_parent/pub-cache"
env PUB_CACHE="$meshchan_probe_parent/pub-cache" PATH="/usr/bin:$PATH" \
  "$meshchan_python" tool/prepare_ble_probe.py \
  --destination "$meshchan_probe_root" --flutter "$meshchan_flutter" \
  --source "$meshchan_probe_source" \
  --darwin-archive /private/tmp/meshchan-ble2a3-darwin-6.2.1.tar.gz --offline

meshchan_sqlite_cache="$meshchan_probe_root/host/.dart_tool/hooks_runner/shared/sqlite3/build"
mkdir -p "$meshchan_sqlite_cache"
cp -cR /private/tmp/meshchan-ble2a4-final/host/.dart_tool/hooks_runner/shared/sqlite3/build/download-{38c4a60b,6de79c73} \
  "$meshchan_sqlite_cache/"

(cd "$meshchan_probe_root/host" && export PUB_CACHE="$meshchan_probe_parent/pub-cache" &&
  "$meshchan_dart" format --output=none --set-exit-if-changed lib test tool &&
  PATH="/usr/bin:$PATH" "$meshchan_dart" analyze --fatal-infos &&
  PATH="/usr/bin:$PATH" "$meshchan_flutter" test --no-pub --concurrency=1 --reporter expanded &&
  env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
    "$meshchan_dart" --disable-analytics run tool/check_worker_cooperation.dart)
```

The generated host passed format for 27 Dart files with zero changes,
analysis with fatal infos, and all 56 Flutter tests. The logs are
`format.log`, `analyze.log`, and `flutter-test.log` under the probe parent's
`logs/` directory.

All six cooperation process scenarios passed in `logs/worker-cooperation.log`.
Storage drain confirmed exclusive ownership, draft persistence, independent
SQLite reopen, bridge close, release, and worker exit. A withheld ACK allowed
exit after reconciliation. A withheld release quarantined the device and
vetoed exit. Worker loss during open, write, and close each observed one
root-side transport close and a worker exit while normal Quit remained
unconfirmed. This run exercised the existing generator and seven-file runtime
snapshot list end to end.

## Patch review

`git diff --check` passed. The four affected Markdown documents passed
whitespace checks and validation of 174 local links and 57 heading fragments.
The call-site audit included `.dart.txt` templates. The App's Start requests
and parameterized factories use typed targets. Port display strings and the zero-argument
recording seam retain their responsibilities. The patch scope is App models,
runtime, fixtures and tests, probe templates, and this handoff documentation.

## Step 9 and later handoff

Step 9 covers integrated 2A regression and build verification across the
migrated App and CLI entry points. Step 10 records the 2A delivery. In 2B
and 2C, add each production adapter together with the corresponding App
admission rules, local display projection, and host ownership path. Phase 2D
covers saved connection configuration and migration.
[Phase handoffs](../architecture/companion-connections.md#phase-and-step-handoffs)
