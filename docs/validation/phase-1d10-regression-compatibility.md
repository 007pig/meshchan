# Phase 1D.10 — sequential regression and schema-1 compatibility

## Scope and source

This record covers macOS arm64 software/native regression, historical schema-1
interoperability and bounded mobile engineering checks. The product remains
macOS arm64 with explicitly selected USB. Mobile storage, a mobile product,
BLE transport and background reception are not implemented or supported.
Hardware/RF, beta acceptance and distribution are later steps.

The provisioned Android follow-up below now closes the chosen arm64
build/assets/load/public-refusal layers. Initial Android BLOCKED/NOT_RUN entries
retain their original inventory cut; they are superseded for this target by the
later NDK 30 / API 36 results, without a mobile product support claim.

The clean initial checkout was `master` at the actual PR #36 merge
`2b63f65a975ec1fc784132e7445f4a07c8e01538`, tree
`12965c14fe7be8d5a0985e844682f08443972abc`. The reviewed head
`a9525f8e03783cc1ec9bfc7b656566eedf272730` has the same tree; base was
`e007e87ddc6e5034d70e68100f35980e9a1ca2a3`. The 1D.8 merge is an ancestor.
GitHub was queried independently on November 15, 2026: PR #36 is closed and
merged with that actual merge SHA. CI run
[43739757756](https://github.com/007pig/meshchan/actions/runs/43739757756)
is completed/success. That historical remote run is separate from this local run.
The first GitHub CLI attempt was sandbox-network blocked and an alternate MCP
credential returned 401; the working GitHub account supplied the results above.

Work continues on `codex/phase-1d10-regression-compatibility`. No product source,
schema/summary/CLI JSON version, package/app version, Bundle ID, sandbox,
dependency or default directory is changed. New tooling records evidence and
prepares an isolated mobile probe; the compatibility checker now compares
recognized SQLite sidecar presence/hashes as well as the main database.

## Evidence and reproduction

The new owned external root is `/private/tmp/meshchan-1d10-20261115-01` (called
`E` below). Raw databases, complete bundles, logs, screenshots and xcresult stay
there. Each runner gate has `result.json`, `output.log`, and before/after source
manifests. `ledger.jsonl` records argv, absolute cwd, UTC times, exit code,
classification, log hash and command environment. `source-initial.json` and the
final source snapshot include all four members, Runner/XIB/entitlements,
generation inputs, tests, tools and CI. Dependency graph and package resolution
are additional build inputs. Product manifests inventory complete bundles,
including symlink targets, file modes, sizes and SHA-256 values.

The runner is deliberately separate from the three-member 1C candidate
validator. It stops on a failed command; it does not retry, skip assertions,
kill a process on a wrapper deadline or claim that exit alone proves cleanup.
A checkout-wide advisory lock prevents overlapping invocations of this runner;
other manually invoked native tools still require operator sequencing.
The interruption correction below retains that lock through confirmed exit of
the interrupted gate's owned process tree.

```sh
/opt/homebrew/bin/python3 tool/regression_1d10.py \
  --evidence /private/tmp/meshchan-1d10-NEW-RUN --init --software \
  --flutter /opt/homebrew/share/flutter/bin/flutter \
  --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
```

Use a new external directory for every complete run. Individual additional gates
use `--plan FILE`, a JSON array of `{name, argv, cwd}` records; cwd is absolute.
Gate names cannot be reused, including after failure. `--inventory BUNDLE`
records a full inventory; use distinct `--inventory-label Debug` and
`--inventory-label Release`, and `--snapshot final` to retain source bytes/diff.
This is a command ledger, not automatic acceptance of
all R01–R19; semantic receipts and manual GUI observations must also be reviewed.

The product source cut contains 271 unchanged four-member/root build inputs;
all 51 recorded gate source cuts match those hashes. The product cut manifest
SHA-256 is `37555fea20940034dc74bca1807ff58026dffea85d33c1521122e93c55062655`.
`source-initial-retention.json` explains retention of initial source bytes:
baseline Git archive plus the initial untracked runner reconstructed and checked
against every original pre-gate hash. `source-final/` retains final source and
`source-final.diff` retains the reviewable tracked patch; no initial user edits
were present. `resolved-build-inputs` adds generated compiler config/hook
inputs and outputs. `final-summary.json` associates results, source cuts,
product inventories and the resolved tooling failure. Product inputs remain at
the actual PR #36 merge. Tool/document changes were an uncommitted reviewable
working tree when that evidence was captured. Commit, push and PR publication
were subsequently authorized on November 16, 2026; publication preserves the
reviewed tooling and the unchanged product input hashes.

## Actual toolchain

| Input | This run |
| --- | --- |
| Host | macOS 27.2.1 (26B131), arm64 |
| Flutter | Existing `/opt/homebrew/share/flutter`, 3.50.0 stable; framework `ab2912035e160d9cad6306df307576da6128ebdb` |
| Bundled Dart | `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart`, 3.14.0 |
| Python | `/opt/homebrew/bin/python3`, 3.15.2; resolves to `/opt/homebrew/opt/python@3.15/bin/python3.15` |
| Xcode | 27.2 (27B52), `/Applications/Xcode.app/Contents/Developer` |
| Compiler | `/usr/bin/clang`, Apple Clang 21.0.0 (`clang-2100.4.1.1`) |
| Root dependencies | Root lock SHA-256 `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`; sqlite3 3.9.1, drift 2.35.4, libserialport_plus 1.0.5, material_ui 1.11.0 |

The launcher initially could not access its existing cache inside the shell
sandbox. Authorized normal SDK execution succeeded. No SDK installation,
upgrade, cache patch, quarantine/security change or global PATH change was made.
The runner selects Apple compiler tools and Python using a command-local PATH.
The final format check covered 213 tracked Dart files with zero changes.
The final Python count is 78, including six new evidence/path/identity safety
tests; their intentionally failed child (exit 7) verifies error propagation.
Existing CI unittest discovery includes these tests. No GUI/device/simulator
required CI job is introduced.


## Sequential local gates

`F` denotes the Flutter executable above, `D` its bundled Dart, `P` the verified
Python. Root cwd is the checkout unless specified. Exact expanded argv and
timestamps are in the corresponding gate result.

| Gate | Command / cwd | Actual result | Evidence under E |
| --- | --- | --- | --- |
| R01 | Toolchain, Git, four-member manifest, installed mobile inventory | PASS; explicit versions above | baseline/source/environment-inventory and inventory logs |
| R02 | `F pub get --enforce-lockfile`; `D pub deps --json` | PASS; lock unchanged | R02-pub, R02-graph |
| R03 | `D run build_runner build`, core | PASS | R03-generate |
| R04 | `D run tool/check_schema.dart`, core; tracked/diff checks on all five artifacts | PASS; schema 1; generated artifacts unchanged | R04-* |
| R05 | Tracked/new Dart format; `F analyze --no-pub --fatal-infos` | PASS; no issues | R05-* |
| R06 | `F test --no-pub --concurrency=1 --reporter expanded`, app | PASS; 250 tests | R06-app |
| R07 | Six `check_*_process.py --dart D --evidence-root E/process-*` | PASS; runtime, draft, profile, device, diagnostic, history | R07-*, process-* |
| R08 | `P -m unittest discover -s tool -p '*_test.py'` | PASS; first cut 76 tests; final tooling rerun 78 tests | R08-python |
| R09 | `D test --reporter expanded`, core | PASS; 362 tests | R09-core |
| R10 | Same, meshctl | PASS; 276 tests | R10-cli |
| R11 | Same, meshcore_link | PASS; 180 tests | R11-link |
| R12 | Three `D build cli --target=... --output=E/NAME` | PASS; cli, observation, acceptance | R12-*, cli/observation/acceptance |
| R13 | Shared `smoke_cli.py` source/AOT/whole-bundle relocation | PASS; 101 process checks | R13-smoke |
| R14 | Sequential macOS Debug/Release config-only + external Xcode builds | PASS; complete fresh bundles | R14-*, Derived |
| R15 | Disabled-owner XCTest; signatures/architecture | PASS; 22 tests, strict signatures | R15-* |
| R16 | Production runtime/relocation plus finite SQLite write/read | PASS; 3 persistence runs + 2 Quit cases + 2 SQLite probes | R16-* |
| R17 | Historical producer and actual app/CLI interoperability | PASS; four-table comparison, real GUI and normal close | R17-legacy, schema-compatibility, GUI evidence |
| R18 | Isolated mobile probe and BLE risk review | PASS for iOS build/load/refusal; Android build BLOCKED; sourced BLE review | Mobile sections below |
| R19 | Final source/lock/generated/bundle/whitespace consistency | PASS; final tooling and probe analysis, unchanged product inputs | Final manifests/checks |

The five generated artifacts remain tracked: production and dependency-probe
`database.g.dart`, frozen `drift_schema_v1.json`, generated `schema.dart` and
`schema_v1.dart`. No snapshot is overwritten to hide a mismatch. Process gates
and Dart/app suites run sequentially, preserving existing serial test settings
and intentional internal owner/contender concurrency. No hardware port
enumeration/open or RF is added to smoke.

## Native products and shutdown

Native build commands use the existing absolute `macos/Runner.xcworkspace`,
Runner scheme, external `E/Derived`, `platform=macOS,arch=arm64`, and
`-parallel-testing-enabled NO`. Each configuration first runs
`F build macos --debug/--release --no-pub --config-only` in the app member.
Build settings, test host and generated xctestrun are inspected before testing.
`MESHCHAN_TEST_HOST=disabled-owner-v1` must be active before engine/bootstrap.
XCTest/runtime cwd, fixtures and complete products are outside Documents.

Debug Runner is arm64; Release Runner and its native assets contain arm64 and
x86_64 slices. Runtime testing is arm64 only. No x86_64 runtime claim follows
from a binary slice. Signature checks use
`codesign --verify --deep --strict --all-architectures` on complete bundles.

| Complete product | Runner SHA-256 | Scope |
| --- | --- | --- |
| `Derived/Build/Products/Debug/Meshchan.app` | `2c4bfc6825feb50f1466e2ee2c58752ca6cb25b3b0a769c9e324ed9e2df24bde` | arm64 build and disabled-owner XCTest |
| `Derived/Build/Products/Release/Meshchan.app` | `2cf9acc3a227d234a3140fca99dcea4c6454af68bd0db2b8f65874eba1836c68` | universal contents; arm64 host/guest execution |

Complete inventories are `macos-product-manifests.json` and
`cli-product-manifests.json`; individual members are not substituted into older
bundles. Release framework hashes are sqlite3
`78592666674972ed235cb50387acf37905d9017d8dd6dc35d2b83b62a83fb60f`
and libserialport_plus
`24bffc854da92abdf501cff6102230b1b6737767c7202aadc48d66241ce7d6be`.
The xctestrun names `__TESTROOT__/Debug/Meshchan.app` under external
Derived/Build/Products and sets the disabled-owner environment variable;
`xctestrun.json` preserves that inspection. Build-for-testing precedes a
separate test-without-building command; xcresult has 22 tests, zero failures.
The ordinary runtime runs are separate from the disabled host.

For reproduction, use the app member as cwd for both Flutter config-only
commands and these Xcode commands, substituting absolute owned paths:

```sh
xcodebuild -workspace /ABS/APP/macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /ABS/E/Derived -parallel-testing-enabled NO build
# Repeat configuration/build sequentially for Release.
xcodebuild -workspace /ABS/APP/macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /ABS/E/Derived -parallel-testing-enabled NO build-for-testing
# Inspect the generated xctestrun host/environment before executing it.
xcodebuild -workspace /ABS/APP/macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /ABS/E/Derived -parallel-testing-enabled NO \
  -resultBundlePath /ABS/E/native.xcresult test-without-building
```


`check_macos_runtime.py` counts three persistence runs (write, independent read,
relocated read) plus separate quit-starting and quit-ready cases. Finite SQLite
write/read uses its own legal `--fixture=E/meshchan-1d2-sqlite --probe-exit`
contract. It is not used for the legacy database. Normal product Quit must
confirm released resources, worker exit and drained requests/ports, followed by
independent OS process absence and closed-file consumers.

## Historical schema-1 compatibility

The reused producer is production source from
`e237be5c2fb9e4fd1cf2f2c26717582f34a5e757` (dev.2), extracted using `git archive`.
Only the two existing development datagram harness files are overlaid; their
hashes are recorded. The old production CLI/core/version stay unchanged. This
is historical production source executed on this run's recorded toolchain,
not an original historical binary or a claim of identical database bytes.

The producer writes the real public-path Draft `legacy 中文😀\r\nbody`, legal Send
Profile, explicit default, history limit 1000 and terminal-cleanup dev.2 run.
The original fixture is copied only after the producer exits. Its immutable
source/hash and subsequent independently owned consumer copies are recorded.
Current AOT acceptance/CLI preserved every old row across all four tables,
added three current dev.3 runs and a Draft, and passed nonempty History/export
checks. Successful ordinary
opens perform recovery/maintenance, so whole-file hash equality is not a normal
compatibility requirement. Prepared/unresolved/over-limit cases stay in the
separate full recovery/retention suites, with their allowed changes.

Future/corrupt inputs are controlled test fixtures, not historical files. The
CLI must return exit 74 and the correct public category. Main DB and recognized
`-wal`, `-shm`, `-journal` files preserve bytes and presence on rejection.
Ownership marker/lock files are excluded from that SQLite-only comparison.
The full preflight suite separately covers committed future WAL, valid WAL,
rollback journals and malformed schema. The app runtime suite already covers
real future/corrupt inputs without replacing the original database. Future
summary rejection remains `storage_read_failed`, distinct from database version.

The original closed DB SHA-256 is
`9db2b432d54835f077e8200fc68aea659d7d81a81ad2d412123d2a25341bf3d3`.
`gui-source.json` records the absent producer PID before the independent host
copy. The host Release displayed the old Draft, Profile and default/1000
settings. Title-only Save produced revision 2. After normal Quit, current AOT
CLI `draft show --id ... --json` confirmed exact `legacy 中文😀\r\nbody`, 23
UTF-8 bytes, the same ID/createdAt and unchanged Profile/Settings/Run rows.
CLI `draft update --id ... --expected-revision 2 --title=Legacy title from CLI
--json` committed revision 3. Explicit Release reopen showed that title and
revision 3; final Discard/normal Quit retained the committed row and exact body.

| Identity / field | Original | After app | After CLI and final reopen |
| --- | --- | --- | --- |
| Draft ID | `9ebe35cfa43878fb8e6e9a510ee4f5c9` | Same | Same |
| createdAt (UTC) | `2026-11-15T17:43:46.620986Z` | Same | Same |
| Title | Empty | `Legacy title from app` | `Legacy title from CLI` |
| Revision | 1 | 2 | 3 |
| Body | `legacy 中文😀\r\nbody` | Exact original | Exact original |
| Profile ID / default | `0a2ea3ec08b9e7ec9b51496075fd87b4` | Unchanged | Unchanged |
| Old run ID / version | `2dc5ab1735ebaf02725274dacf32e652` / dev.2 | Unchanged | Unchanged |

The host GUI sessions are `gui-first` PID 62398 and `gui-second` PID 72084.
Both exited 0 with released owner, actual worker exit, zero pending requests
and receive ports, followed by OS PID absence. A public CLI contender while the
second app held ownership returned `data_directory_busy`, exit 69. No live DB
was copied or opened with SQL. `gui-business-comparison.json` and
`gui-cli-processes.json` bind public CLI results to closed-file comparisons.

Computer Use initially returned cgWindowNotFound/noWindowsAvailable, had one
long Finder query, and could not activate static navigation labels. Its
keyboard-navigation attempt inserted unsaved title text; it was discarded,
never saved, and independent comparison retained revision 3. This is a tooling
limit, not a demonstrated product navigation defect. No real IME claim is made.

Using the existing identity-checked VM skill/executor, the same complete Release
(SHA-256 below) and a separate original closed-fixture copy displayed History:
one settled Send, the exact run ID, dev.2 appVersion, summary version 1, saved
profile, completed logical result, succeeded core/subscription cleanup and
unobserved recovery. Original screenshots and AX facts are in `vm-history`;
normal Quit plus OS absence preceded collection, and all four old tables
remained identical. This guest run adds History display evidence; the app/CLI
revision chain above ran on the host.

Two further real guest Release launches (`vm-rejections`) used the controlled
future/corrupt copies. The UI displayed `unsupported_database_version` and
`database_corrupt`, respectively, with owner none and disabled business edits.
Both quit normally, confirming worker exit and zero requests/ports. Closed
collection preserved main DB and all recognized SQLite sidecar bytes/presence;
no replacement business database was initialized. These GUI cases supplement
the existing actual-worker and core preflight suites; they are not legacy crash
fixtures. A mistyped one-off collection argv failed before collection and was
corrected; the existing collector's live/closed safety behavior was unchanged.

## Bounded mobile checks

`tool/prepare_mobile_probe.py` creates a new external copy of the four-member
workspace and generates hosts there. It restores all original inputs after
`flutter create --platforms=android,ios --no-pub`; only the copied app gets a
direct sqlite3 3.9.1 dependency and the probe entrypoint. Product main stays
unchanged. Root lock enforcement and actual resolved graph comparison are
required before build. The real product still has only its macOS runner.

```sh
P tool/prepare_mobile_probe.py --destination E/mobile-workspace --flutter F
# In E/mobile-workspace:
F pub get --enforce-lockfile
D pub deps --json
# In the copied app, after checking installed tools and automatic install behavior:
F build ios --simulator --debug --no-pub --target lib/mobile_probe.dart
# From the product checkout, with a new external simulator evidence root:
P tool/run_mobile_simulator_probe.py \
  --app E/mobile-workspace/apps/meshchan_app/build/ios/iphonesimulator/Runner.app \
  --evidence E/mobile-runtime-NEW \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-18-5
```

The template uses only public core/link APIs and public sqlite3. It performs a
minimal in-memory SQLite create/insert/select/close, calls `CoreStorage.open`
with an absent owned business subdirectory, and expects `storage_open_failed`
without creating that directory. Public `SerialPorts.listPorts()` must reject
Android enumeration/iOS backend access before native hardware calls. It never
opens a port or requests Bluetooth. SQLite dependency success does not establish
business storage support.

| Target / SDK / ABI | Source and entrypoint | Build/assets | Dependency load | CoreStorage / serial guard | Runtime / capability |
| --- | --- | --- | --- | --- | --- |
| Android initial inventory, intended arm64 | Locked copied closure, mobile_probe.dart | BLOCKED before Gradle at the original inventory cut | NOT_RUN at that cut | NOT_RUN at that cut; source guard audited | Historical initial result; provisioned follow-up below |
| Android provisioned follow-up: compile/target SDK 36, min SDK 24; Android 16 / API 36 emulator, android_arm64 | Same 100 locked versions; isolated NDK 30 host overlay | PASS; Debug APK and arm64 serial/SQLite ELF assets | PASS; SQLite 3.54.1 create/insert/select/close | PASS; storage_open_failed with absent business directory; serial enumeration refused before native operation | PASS for finite probe only; business storage unsupported |
| iOS Simulator SDK 27.2, deployment target 15.0; iOS 18.5 runtime, ios_arm64 | Same locked copied closure | PASS; SQLite framework includes simulator arm64/x86_64; serial hook successfully emits no iOS asset | PASS; SQLite 3.54.1 create/insert/select/close | PASS; storage_open_failed before business directory creation; serial enumeration refused before native access | PASS for probe only; business storage unsupported |

Doctor reports missing iOS 27.2 runtime and CocoaPods, but separate simctl
inventory finds an available iOS 18.5 runtime. Missing current runtime does not
prove compile impossible. CocoaPods is only a blocker if the actual build path
requires it. A connected Android device is an inventory fact, not permission or
evidence of Bluetooth/USB serial testing. No toolchain, simulator runtime,
plugin or license is installed/accepted.

Locked package hooks are inspected through the actual package_config locations.
libserialport_plus 1.0.5 builds macOS/Linux/Android/Windows; iOS deliberately
emits no code asset so compile can succeed. Expected absent iOS serial assets
are not automatically a packaging defect. sqlite3 3.9.1 supplies target-specific
native assets. Build, inventory, target load and public API refusal are separate
assertions. The ownership ABI allowlist is unchanged and rejects mobile before
directory/POSIX ownership work; Android being Linux or iOS being Darwin does not
justify widening that allowlist.

The actual mobile closure comparison contains 100 packages (the machine
record is authoritative), with identical resolved versions and an
identical root lock. The probe-only direct sqlite3 edge, generated hosts and
entrypoint are recorded separately. `mobile-hook-report.json` retains hook
inputs/outputs for both simulator architectures. `mobile-product-manifest-final.json`
inventories the complete final app. SQLite's binary identifies IOSSIMULATOR;
its precompiled asset records SDK 26.5 (arm64 min OS 14.0, x86_64 min OS 12.0),
while the probe host was compiled with SDK 27.2 and deployment target 15.0.
Universal slices are build evidence, while runtime assertions are arm64 only.
The simulator app also passes strict all-architecture signature verification.
No Pods step was required for this hook-only dependency path.

The first runtime collector (`R18-ios-runtime`) is retained as FAIL/exit 1:
its 120-second report observation looked for host stdout files, but simctl
interprets those paths inside the guest filesystem and the Flutter print did
not supply a usable file receipt. The original simulator screenshot independently
shows the completed assertions. No product defect was inferred. The corrected
probe writes JSON into its own temporary sandbox; the runner locates that
sandbox with `get_app_container`, parses the receipt, verifies ios_arm64 and all
three assertions, then terminates only the finite probe UI and shuts down its
owned simulator. This termination is not a product normal-Quit claim.
`R18-ios-build-report` and `R18-ios-runtime-report` both pass on a fresh device
set; the prior failure and first build are preserved. The template's initial
ABI spelling assertion was also corrected to Dart's `ios_arm64` before the final
run; the original attempt timed out before reaching it.

The final receipt records SQLite 3.54.1, successful create/insert/select/close,
`storage_open_failed`, absent requested business directory, and serial guard
refusal before native enumeration. Its source IDs and capability UNSUPPORTED
are in `mobile-runtime-report/report.json`. Both task-owned simulator sets were
shut down. Android did not enter Gradle: the installed Flutter extension expects
NDK 28.2.13676358, which is absent. Build tools 35.0.0/36.0.0/36.1.0/37.0.0 and
platforms 35/36/36.1 are installed; command-line tools are absent and license
status is unknown. Installed JDK inventory includes 27.0.1 (java_home default)
and 25.0.5; no Gradle/JDK compatibility result is inferred. Minimum Android
rerun prerequisites are an operator-provisioned compatible JDK, command-line
tools/licenses and the required NDK; then build only an explicit arm64 target
from this isolated workspace. Android dependency load/API runtime were NOT_RUN in the initial run; the
provisioned follow-up below supersedes that limitation for its chosen target. iOS device/archive, full product mobile startup and real BLE remain
NOT_RUN/unsupported or not implemented as applicable.

## BLE integration risks, reviewed November 15, 2026

This is source-backed future design input, with no plugin selected, dependency
added, radio enabled, scan/pair/connect/write performed or background mode added.
Firmware references pin MeshCore commit
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`.

| Risk | Observed contract / design implication | Required future evidence |
| --- | --- | --- |
| Inner content versus carrier | CompanionTransport carries complete inner content, with subscribe-before-open, single subscription, pause/cancel requesting close and actual shared close. USB header/length framing is not BLE framing. BaseSerialInterface defines 176-byte maximum frames; this does not mandate 20-byte slicing. [Base interface](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h) | Selected backend/GATT boundary and negotiated MTU, including maximum-length frames and malformed input |
| ESP32 GATT and security | UART service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, RX `...0002...` WRITE, TX `...0003...` READ/NOTIFY, encrypted MITM permissions and PIN/bond authentication. Backend requests MAX_FRAME_SIZE MTU, queues frames, and spaces notifications by 60 ms. Local queue acceptance is not delivery. [ESP32 backend](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp) | Real device negotiated MTU/write response/notification size, encryption and queue pressure |
| nRF52 backend differences | Uses Bluefruit BLEUart and secured connection callbacks with stale-handle checks; write backpressure may retain a frame, partial writes are dropped. The underlying Bluefruit version/UUID/write behavior must be pinned before an adapter is specified. [nRF52 backend](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp) | Selected firmware build's Bluefruit closure, GATT discovery, frame boundary/overflow and disconnect behavior |
| Isolate notification ownership | BackgroundIsolateBinaryMessenger enables request/response, not unsolicited host messages. It alone does not establish EventChannel/BLE notifications in the existing worker. Future root/native subscription needs a typed bridge, generation checks, one owner and backpressure; plugin objects/subscriptions/handles cannot cross isolates. [Flutter 3.50 isolate documentation](https://docs.flutter.dev/perf/isolates#limited-plugin-messages-from-host-platform-to-flutter) | Actual plugin callbacks, open/cancel races, late notifications, disconnect and unsubscribe/close receipts |
| Android permissions | Permission requirements depend on target SDK and actual operation. API 31+ SCAN/CONNECT require runtime permission; ADVERTISE is considered only for an actual advertising requirement. No permission is added here. [Android permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions) | Real-device grant, denial, revocation and operation-specific behavior |
| iOS usage description | Bluetooth access needs NSBluetoothAlwaysUsageDescription; deployment targets before iOS 13 also need the older Peripheral key. [Apple key documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription) | Selected deployment target, actual Central authorization/lifecycle and denial/revocation |
| Suspension/system termination | Mobile inactive/background/OS kill does not provide macOS deferred Quit. Async close cannot be guaranteed at OS termination; background modes/state restoration need a separate product decision. [Apple background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html) | Real-device interruption, restart/recovery and explicit product policy |
| Readiness and evidence limits | Open/write accepted is not session ready or remote delivery. Keep single-use sessions, cancel/open race handling, generation rejection, bounded writes and actual close. Fake callbacks and SQLite simulator probes establish neither GATT nor radio behavior. | Authorized BLE device validation after choosing an adapter; no transport or background support claim now |

## Remaining scope and handoff

Step 9's actual Dvorak-layout GUI, conflict Reload GUI, live native-filename Quit,
complete Cut/Copy, remaining Full Screen/focus/accessibility combinations and
Replace/delegate-validation variants retain NOT_RUN unless explicitly updated
here. Its earlier GUI and Pinyin results retain their own product cuts. This
step does not infer fresh IME coverage from pasted Unicode or controlled tests.

1D.11 requires separately authorized host macOS USB/LoRa hardware acceptance,
failure/unplug/cancel/active-hardware Quit and beta observations. RF authorization
and finite budgets must be confirmed in that session; historical budgets are not
reused. Existing hardware skill and owned fixture/normal-exit collection rules
apply. No VM passthrough/SPICE hardware work is proposed. 1E owns installers,
notarization and distribution; neither mobile/BLE nor Intel runtime support is
added by this record.

The required software/native and old-file interoperability gates are complete,
with no unresolved product FAIL or critical BLOCKED result. The initial Android
build was BLOCKED by installed-toolchain prerequisites; the follow-up below
records the later provisioned Android build/runtime result. Historical desktop
variants remain as listed; this does not complete 1D.11 or the whole 1D phase.

## Android SDK follow-up, November 15, 2026

After the operator upgraded the SDK at the same root, a new owned evidence run
was created at `/private/tmp/meshchan-1d10-android-20261115-02`. The previous run,
summary, products and source snapshots are preserved. The checkout still uses
the same PR #36 product inputs and Flutter 3.50.0 / Dart 3.14.0; this follow-up
does not repeat or reattribute the earlier complete software/native results.

The new inventory confirms Emulator 37.2.13 (previously 36.6.11) and
platform-tools 37.0.1. Platforms 35/36/36.1, build tools
35.0.0/36.0.0/36.1.0/37.0.0 and the API 36 arm64 system image are present.
The SDK root still has no `cmdline-tools` or `ndk` directory. Flutter doctor
reports missing command-line tools and unknown license status. Existing license
files alone do not establish current toolchain readiness. The installed Flutter
extension still requires NDK 28.2.13676358.

| Follow-up gate | Actual result |
| --- | --- |
| A01 installed environment / doctor | PASS for inventory; Android capability remains blocked |
| A02 independent four-member probe preparation | PASS; new external workspace, unchanged product main |
| A03 locked resolution / A04 resolved graph | PASS; same root lock and all 100 resolved package versions |
| A05 Android arm64 Dart kernel | PASS; `kernel_snapshot_program`, Debug, `lib/mobile_probe.dart` |
| APK compilation/linking/packaging and native assets | BLOCKED before entry; required NDK/tools absent |
| Android dependency load / public API target runtime | NOT_RUN; no APK available |

The actual kernel command, from the copied app directory, was:

```sh
/opt/homebrew/share/flutter/bin/flutter assemble \
  --output=/private/tmp/meshchan-1d10-android-20261115-02/android-kernel \
  -dTargetPlatform=android-arm64 -dTargetFile=lib/mobile_probe.dart \
  -dBuildMode=debug \
  --build-inputs=/private/tmp/meshchan-1d10-android-20261115-02/android-kernel-inputs.txt \
  --build-outputs=/private/tmp/meshchan-1d10-android-20261115-02/android-kernel-outputs.txt \
  kernel_snapshot_program
```

This target compiles the Flutter/Dart entrypoint without Gradle, native-asset
hooks, an APK or device execution. Its successful `app.dill` and compiler inputs
are hashed in `android-kernel-manifest.json`; it is not a native-library or
business-storage support result. The installed Flutter Gradle provisioning code
can invoke sdkmanager to install a missing configured NDK, so a full APK build
was deliberately not entered while components remain absent. No SDK/NDK/JDK
installation, license acceptance or global setting change was performed.

The operator confirmed that they will provision the missing components and
notify the agent. Resume from an explicit arm64 APK build/native asset check,
then use an appropriate existing/owned Android runtime for the public SQLite
and controlled storage/serial refusal assertions. The new run's
`android-continuation-summary.json` and per-gate ledger record the exact state.

Real BLE connection testing is not a Step 10 acceptance requirement. The sourced
BLE risk matrix above is the required output. A later separately scoped BLE
adapter/plugin and root/native-to-worker bridge must exist before authorized
real-device scan/pair/connect/notification/write/close acceptance can establish
BLE support. Current 1D.11 host USB/LoRa/beta scope does not automatically add
BLE transport or radio authorization.

### Provisioned Android build and runtime

The operator subsequently completed installation. A06 doctor and A07
`sdkmanager --list_installed` now confirm command-line tools 23.0, NDK
30.0.16248370, all Android licenses accepted and Android Studio's existing JBR
25.0.4. The SDK also contains platform 37.2; this probe deliberately selects
compile/target SDK 36 and the existing Android 16 / API 36 arm64 system image.
No connected physical device was selected or modified.

Only the generated Android host in the owned workspace was changed to select
the already-installed NDK 30 rather than Flutter's template default
28.2.13676358. Probe `gradle.properties` sets `android.builder.sdkDownload=false`.
The exact patch and hashes are in `android-build-overlay.json`. SDK, NDK and
license installation were the operator's actions. The agent did not install
another NDK or change global Flutter/Java settings. The Gradle wrapper selected
9.5.0, AGP 9.3.1 and Kotlin 2.4.20 from the generated host; no command-line JVM
arguments, no-daemon flag or parallel gate execution was added.

| Gate | Actual result / evidence under the Android follow-up root |
| --- | --- |
| A06 doctor / A07 installed SDK | PASS; toolchain and licenses now available |
| A08 APK | PASS, exit 0; `flutter build apk --debug --no-pub --target-platform=android-arm64 --target lib/mobile_probe.dart`, copied app cwd; 130.0 seconds |
| APK inventory / ELF / signature | PASS; 146 APK members, only arm64-v8a libraries, verified Debug APK signature; `apk-inventory.json`, `android-native-elf.json`, `apk-signature.log` |
| Native hooks | PASS; sqlite3 3.9.1 and libserialport_plus 1.0.5 hook outputs report success, Android/arm64, NDK API 24 and actual NDK 30 compiler paths; `android-hooks/` |
| A09 first runtime collector | FAIL/exit 1 due to receipt path assumption; genuine probe assertions succeeded and were independently collected; failure retained |
| A10 corrected runtime | PASS/exit 0 on a fresh owned AVD; `android-runtime-receipt/report.json` and command ledger |
| Final tooling and analysis | PASS; Python 81 tests, including three Android target/receipt safety tests; copied probe analysis has no issues |

The Debug APK SHA-256 is
`5ac23b08295e4c4b74989167fe76fff4afa2367dd9f9b8436758567100cc2871`.
Its native content includes `liblibserialport_plus.so`, `libsqlite3.so`,
`libflutter.so` and Flutter's Vulkan validation library, all under
`lib/arm64-v8a/`. Complete ZIP member hashes, the NativeAssetsManifest and ELF
headers/Android notes are retained. Android package ID is the isolated
`org.meshchan.probe.meshchan_app`, not the macOS product ID. Its manifest contains
the Flutter Debug INTERNET permission and generated receiver permission, with
no Bluetooth permission.

`tool/run_android_mobile_probe.py` creates a new external AVD from an already
installed system image. Before installation it verifies APK identity, exact
AVD name, virtual-device status and arm64 ABI. Every adb call selects its
explicit emulator serial. It does not use the connected Pixel or grant runtime
permissions. It records target OS/API, launches the public dependency/API probe,
reads only that app's sandbox receipt, then stops the finite probe UI and the
owned emulator. Both AVD processes exited 0 and were reaped. Force-stop of the
probe UI is not a Meshchan product normal-Quit claim; the probe had already
reported SQLite close and the storage/serial assertions before that stop.

The first collector assumed `cache/meshchan-mobile-report.json`; the actual
Flutter Android `Directory.systemTemp` is `code_cache` in this configuration.
The genuine JSON and Flutter log were retained separately, then the collector
was corrected to discover exactly one receipt in the owned package's cache or
code_cache and reject unexpected/ambiguous paths. A09's failure and its closed
AVD are preserved; A10 used a fresh AVD and the same APK. This is a resolved
test-tooling issue, with no product source or dependency change.

The final parsed receipt records Android / android_arm64, SQLite 3.54.1, passed
create/insert/select/close, controlled `storage_open_failed`, absent requested
business directory and serial enumeration refusal before native enumeration.
Storage capability remains UNSUPPORTED. All 100 resolved package versions and
the root lock still match the original product baseline after building.

To reproduce on a new external workspace, use `prepare_mobile_probe.py`, enforce
the root lock, explicitly select an installed NDK in the generated host and
disable SDK auto-download before building. The current validated host delta is
`ndkVersion = "30.0.16248370"` in the copied `android/app/build.gradle.kts`.
Then run the APK command above and:

```sh
/opt/homebrew/bin/python3 tool/run_android_mobile_probe.py \
  --apk /ABS/PROBE/apps/meshchan_app/build/app/outputs/flutter-apk/app-debug.apk \
  --sdk /Users/xiaoyu/Library/Android/sdk \
  --java-home '/Users/xiaoyu/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  --evidence /private/tmp/meshchan-android-runtime-NEW
```

The runner requires installed build-tools 37.0.0 for APK identity inspection and
the default installed API 36 arm64 image; it never provisions missing tools.
Its optional system-image and emulator-port arguments are explicit. This closes
the Android build/assets/load/API-risk layers for this target. It does not
establish full product mobile startup, serial hardware, BLE, background work,
other Android ABIs or device models. Actual BLE connection remains outside
Step 10 as explained above.

## Mobile runner review corrections

Both review findings were reproduced before changing the runners. New
device-free tests exercise the actual main functions with controlled subprocess
and clock behavior, real owned temporary files and staged receipt publication.
The initial focused run executed nine tests and reported seven errors, including
the Android wait timeout and iOS JSONDecodeError paths. Raw before/after logs
are under `/private/tmp/meshchan-1d10-mobile-review-20261115-01`.

Android now retains its existing 60-second exit observation, then attempts
terminate and, if necessary, kill on only the exact Popen child, with bounded
10-second reaping waits after each signal. Failed adb cleanup, wait timeouts
and signal errors remain in `cleanup-errors.json`; successful forced reaping
does not turn those errors into PASS. `emulator-exit.json` records the actual
wait result, or null exit code and processReaped false when reaping cannot be
confirmed. An earlier probe failure remains the primary exception. No discovered
emulator, physical device or process group is signaled, and no product normal
Quit/cleanup claim is made from this finite-probe cleanup.

iOS now treats empty or incomplete JSON as not-yet-published and continues
polling within the original 120-second deadline. It does not extend that
deadline, relaunch the probe or retry a complete failed report. The regression
covers empty → partial → complete publication, deadline expiry with an
incomplete file and immediate rejection of a complete failed report.

All nine focused tests pass after correction. The complete Python tooling suite
passes 90 tests with the verified Homebrew Python 3.15.2. Existing unittest CI
discovery includes these regressions without another job. These are controlled
failure-path software results; no simulator/device runtime was rerun for this
review correction. Earlier native/mobile builds and target runs retain their
original tool/source cuts; product code, probe Dart code and dependencies are
unchanged.

## Additional mobile tooling review corrections

A subsequent review identified four more gaps, reproduced before their fixes:
the emulator process receipt was written outside its cleanup guard; cleanup
handled subprocess failures but missed OSError from launching commands or
recording their output; iOS acceptance checks used removable Python assertions;
and Flutter create left a generated counter test in the restored app copy.
New evidence is under `/private/tmp/meshchan-1d10-mobile-review2-20261115-01`.
The earlier evidence roots and counts retain their original source cuts.

The Android process receipt now runs inside the try/finally established
immediately after Popen returns. A failed receipt write still terminates and
reaps only the launched child. Android and iOS cleanup retain both OSError and
subprocess failures and continue remaining cleanup operations. Evidence-file
write failures are also handled after cleanup: available diagnostics are
written best-effort, and failures are retained in an ExceptionGroup or notes on
the original exception if the filesystem cannot accept the diagnostic files.
An evidence failure cannot replace an earlier probe failure with a passing
result or skip owned-child reaping/simulator shutdown.

iOS now uses explicit receipt validation that raises ValueError, including
exact Boolean types, expected OS/ABI, the dependency version and unsupported
storage capability. Empty/incomplete JSON keeps its bounded observation
behavior, while complete failed or invalid reports fail immediately. Neither
`-O` nor inherited `PYTHONOPTIMIZE` removes these checks.

Probe preparation now removes only newly generated non-host scaffolding from
the owned copy before restoring original inputs. Android/iOS hosts and Flutter
metadata remain; original product tests, including any original file named
widget_test.dart, are preserved. The real Flutter 3.50 run removed eight files:
the generated counter test, generated member lockfile and six IDE files.
`probe-source.json` lists their exact names. Analysis of the retained old counter
test reproduced creation_with_non_type for MyApp before correction.

| Check on corrected source | Actual result |
| --- | --- |
| Complete Python tooling suite | PASS; 104 tests, Python 3.15.2 |
| Lifecycle regressions with `python3 -O` | PASS; 21 tests |
| Failed-receipt regression with `PYTHONOPTIMIZE=1` | PASS; complete failed iOS receipt is rejected |
| Real fresh probe preparation and locked resolution | PASS; new external four-member workspace; root lock unchanged |
| Whole prepared workspace `flutter analyze --no-pub --fatal-infos` | PASS; no issues |
| Prepared app `flutter test --no-pub --concurrency=1 --reporter expanded` | PASS; 250 tests; generated counter test absent |
| Preparation preservation check | PASS; all 30 original app test/support files preserved exactly |

After preparation, the installed Flutter pub-get migration adds only Android
and iOS platform-directory exclusions to the copied app's analysis_options.
That SDK-produced metadata delta and the copied app's direct locked sqlite3
dependency are recorded in `preparation-invariants.json`; product main, other
original source files and the root lock retain their hashes. The counter test
is removed rather than excluded from analysis or discovery.

The additional cleanup tests inject process/command/diagnostic recording
failures and verify remaining cleanup, actual child wait calls, diagnostic
retention and primary-exception preservation. These are software fault tests;
this review adds no Android/iOS target-runtime, BLE or hardware result. Actual
target builds/runs above retain their original cuts. The fresh-copy Flutter
analysis and app suite specifically validate the corrected preparation path.

## Regression runner interruption correction

The subsequent P2 review was reproduced with actual Python child/grandchild
processes and independent runner invocations against a new temporary checkout
lock. Before correction, all four initial cases failed: a competing invocation
acquired the lock and executed while a SIGINT-ignoring grandchild was still
alive. The cases covered SIGINT, SIGTERM, a descendant in another session and a
stubborn descendant. The original subprocess.run path did not retain ownership
through descendant exit, and an interrupted result could remain RUNNING.
Evidence is `/private/tmp/meshchan-1d10-gate-interruption-20261115-01`;
`before.log` preserves those failures and the initial source snapshot preserves
the pre-correction runner. Earlier results retain their original source cuts.

The runner now launches each gate in its own session and tracks ancestry and
PID/start identities using OS process metadata, without reading unrelated
command lines or environments. Handled SIGINT/SIGTERM is deferred through
cleanup and recording, including repeated interrupts. Cleanup sends SIGTERM
only to groups containing an owned process, escalates to SIGKILL after a
five-second grace period, and waits for observed exit before releasing the
checkout lock. A grace deadline is not an exit assertion. The immediate Popen
child is reaped; absent or zombie descendants are recorded as exited and
non-mutating. The interrupted gate is FAIL with outcome interrupted, first
signal, signal count, actual child exit code, tree-exit facts and finish time.
The runner returns 130 for SIGINT or 143 for SIGTERM and does not execute later
gates. No forced termination is counted as product normal Quit or cleanup.

If process observation is unavailable before launch, the gate is BLOCKED and no
child starts. Observation/signaling errors during cleanup are retained; the
runner keeps the lock until OS observation confirms exit. It also settles a
signal first received during the final source-manifest query. This handling
covers ordinary gate/compiler/hook descendants, including observed detached
sessions; gates must not daemonize away before ancestry can be observed. It
does not claim protection against killing the controller with SIGKILL or host
failure. Manual commands outside this runner still require sequencing.

| Check on corrected source | Actual result |
| --- | --- |
| Focused real-process and fault regressions, T04-final-focused | PASS; 7 tests |
| Complete Python tooling suite, T05-final-python | PASS; 111 tests, Homebrew Python 3.15.2 |
| Focused regressions with python3 -O, T06-final-optimized | PASS; 7 tests |

The five real-process cases verify lock contention while a grandchild is
alive, repeated-signal deferral, OS-observed child/grandchild exit, the absence
of a later gate, FAIL/interrupted receipts, survival of an unrelated process,
and a fresh invocation acquiring the lock only after cleanup. The other two
tests cover unavailable initial observation and post-launch/transient cleanup
observation failure. Tests use only their own Python processes and private
temporary locks; existing unittest discovery includes them in CI. Per-gate
argv, cwd, environment, UTC times, exit codes, log hashes and source manifests
remain in the evidence root. The escalation case advances its test clock only
after the contender checks the held lock, so slow CI scheduling cannot turn it
into a spurious failure. Real OS signals, process exits and lock operations are
used throughout. This correction changes tooling and documentation
only; no Flutter/native/mobile target build, hardware or BLE runtime result is
added, and the four-member product inputs remain unchanged.

## Nonzero exit and receipt finalization corrections

The next review identified three remaining lifecycle gaps. All were reproduced
before correction in a new evidence root,
`/private/tmp/meshchan-1d10-runner-finalization-20261115-01`. The pre-fix focused
run executed ten tests and failed four assertions: nonzero parent exit with a
live helper, first interrupt during result publication, first interrupt during
ledger publication, and a log digest computed before manifest-triggered cleanup
emitted shutdown output. `before.log` retains the failures. The initial source
snapshot and `source-reproduction-tests` preserve the runner and exact tests
used for that reproduction. Prior counts and evidence remain historical cuts.

A nonzero child return code now requires the same owned-tree settlement as an
exception or interruption. The child exit code remains the actual value, such
as 7; successful forced cleanup does not turn the failed gate into PASS. The
checkout lock stays held through OS-observed descendant exit and child reaping.

Finalization now repeats when a deferred signal arrives during the source
manifest query, result write or ledger write. It settles the owned tree before
publishing the corrected FAIL/interrupted record, refreshes the source manifest
and computes the log hash after shutdown output has finished. Result and ledger
converge on the same record. The ledger reserves the current gate's final row,
verifies its previous bytes before replacement and preserves all earlier rows
exactly; a late interrupt does not append a duplicate or truncate another
writer's unexpected tail. Repeated finalization handles new signals rather than
retrying a failed product gate. A masked final check detects pending signals
and closes the deferred-handler window at the receipt commit boundary.

Receipt-recording errors also settle owned resources before propagating. The
runner attempts to retain a BLOCKED/recording_failed receipt, or attaches the
diagnostic write error to the original exception when evidence storage is
unavailable. Such an error is never converted into a passing gate.

| Check on corrected source | Actual result |
| --- | --- |
| T01-focused | PASS; 13 lifecycle/fault tests |
| T02-python | PASS; 117 tests, Homebrew Python 3.15.2 |
| T03-optimized | PASS; the same 13 tests with python3 -O |

The focused suite includes nine real-process scenarios and four controlled
fault tests. It checks lock exclusion until helper exit, later-gate suppression,
retention of a previous ledger row, identical final result/ledger values, and
exact hashes including helper shutdown output. It also covers a signal pending
at the final masked check, refusal to overwrite an unexpected ledger tail and
recording-error propagation after settlement. Only owned Python processes and
temporary checkout locks are involved; no devices or native builds are used.

These actual-process tests require `/bin/ps` access. The review's restricted
sandbox run reported seven observation-denial failures; that run is not a
passing suite and is separate from this root's complete permitted execution.
No assertions, tests or process observation were skipped to obtain the results
above. Existing CI unittest discovery includes the added regressions. Final
source manifests and `review-summary.json` bind this correction to the test
logs. Product inputs, the root lock and earlier mobile/native results retain
their original scope; no additional platform capability is claimed.

The final tracked-file whitespace and lockfile checks pass. The added runner,
tests and this record also pass an explicit whitespace/final-newline check.
T05-runner-whitespace retains a verification-command failure: git diff
--no-index --check returned 1 for the new file's presence, with no whitespace
diagnostics. T06-added-whitespace uses an explicit file-content check instead;
the original exit code and empty log remain recorded, without changing the
runner's failure handling or treating that command as a product failure.
