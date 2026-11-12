# Developer Guide

## Project language and workspace

Use American English for project documentation, code comments, CLI output, and configuration text. Keep identifiers in English.

The root `pubspec.yaml` lists `packages/meshcore_link`, `packages/meshchan_core`, and `apps/meshctl`. All three members use `resolution: workspace`; all packages use `publish_to: none` and `sdk: ^3.13.0`. Keep the single root `pubspec.lock`. Do not create member lockfiles or add Flutter SDK dependencies. The CLI resolves `meshcore_link` and `meshchan_core` to local workspace members without overrides. Check membership with `dart pub workspace list` (which also displays the root package).

The root provides `lints`; the CLI uses `args` and directly declares `test` and `fake_async` for tests; the communication core uses `libserialport_plus` and directly declares `test` and `fake_async` as development dependencies. The offline business package declares `drift`/`sqlite3` and the workspace
`meshcore_link` dependency for pure route/capacity validation, plus `drift_dev`, `build_runner`, and `test` for development. No Flutter engine or platform project is involved.

The [offline core and persistence contract (1C.1)](architecture/offline-core.md)
defines the `meshchan_core` boundary, local business objects, diagnostic
recording/recovery rules, and acceptance requirements for subsequent 1C steps.
1C.2 added the package, values/interfaces, and dependency probe described below.
The later [1C.3 implementation](#production-storage-and-migration-baseline-1c3)
adds production storage; [1C.4](#persistent-draft-repository-1c4) adds draft CRUD
and pagination. [1C.5](#profiles-settings-and-typed-resolution-1c5) adds persistent
profiles/settings and core typed parameter resolution. [1C.6](#diagnostic-recording-lifecycle-coordination-and-recovery-1c6) adds recording/recovery,
[1C.7](#bounded-diagnostic-history-and-safe-export-1c7) adds bounded history/retention/export,
and [1C.8](#business-cli-entry-points-and-recording-integration-1c8) wires these into the product CLI.
The [1C.9 delivery record](releases/phase-1c-dev3.md) describes the completed local
dev.3 candidate and separately open CI, clean-environment, and public-distribution
checks; dated implementation and validation sections below remain historical.

The [Flutter host contract (1D.1)](architecture/flutter-host.md) now fixes the
macOS arm64 + USB UI scope, worker/owner lifecycle, data-directory compatibility
target, and later acceptance responsibilities. The workspace above is still the
current Dart-only workspace. Flutter membership and platform files belong to
1D.2, with the worker in 1D.3; this documentation step does not add Flutter SDK
dependencies or change existing commands. Future integration uses the existing
SDK below and must validate native assets, Sandbox/directory access, and lifecycle
behavior rather than inferring them from CLI results.

## SDK and native toolchain baseline

Actual local checks on November 8, 2026, reported:

| Component | Observed value |
| --- | --- |
| OS and architecture | macOS 27.2 (26B123), arm64 (`sw_vers`, `uname -m`) |
| Flutter | 3.47.9, stable, revision `c197ca5199e9ee5661e865596c9c07294dfab51c` |
| Dart | 3.13.7, stable, bundled with Flutter, `macos_arm64` |
| Serial package | `libserialport_plus` 1.0.5, latest compatible stable version resolved by pub |
| Developer directory | `/Applications/Xcode.app/Contents/Developer` |
| Initial PATH compiler | Homebrew Clang 18.1.8 |
| Compiler used successfully | Apple Clang 21.0.0 (`clang-2100.4.1.1`) |

Use the Homebrew-managed SDK at `/opt/homebrew/share/flutter`; do not install a second SDK, FVM, mise, asdf, or Melos. Set PATH only for the current terminal session and inspect actual versions:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"
flutter --version --machine
dart --version
xcode-select -p
clang --version
/usr/bin/clang --version
xcrun --sdk macosx --show-sdk-path
```

The actual Dart version output was:

```text
Dart SDK version: 3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "macos_arm64"
```

Unlike Step 1, this step requires a working C/Objective-C toolchain and macOS SDK. The dependency's build hook compiles bundled sources and links IOKit, CoreFoundation, and the system C library. A working Xcode Command Line Tools installation or Xcode can supply the native tools; a full iOS setup is not required by Meshchan. The local validation used the existing Xcode installation.

The first native build selected Homebrew Clang 18 and failed with `ld: library 'System' not found`. Preferring the already-installed Apple compiler resolved this without installing packages, editing SDK files, changing permissions, modifying the pub cache, or installing system libserialport. Use this session PATH for the native commands below on this machine:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
clang --version
```

If SDK cache initialization or pub downloads are restricted by the execution environment, request the appropriate execution access. Do not use sudo or change global configuration to bypass restrictions. Even source help/version invocations can run build hooks before CLI argument handling; avoiding hardware access does not remove native build requirements.

## Local Python toolchain

Use the latest installed stable **Python 3.15 or newer** for subsequent local
project scripts and tests. On November 11, 2026, `/opt/homebrew/bin/python3`
reported **Python 3.15.2** and `sys.executable` resolved to
`/opt/homebrew/opt/python@3.15/bin/python3.15`. Use `python3`, never `python`.
Do not install or upgrade another interpreter automatically. A later installed
stable version may replace this selection after checking its actual version.
The persistent [agent guidance](../AGENTS.md) records this local policy.

Preferring Apple Clang by putting `/usr/bin` first can also select its older
Python 3.9. Call `/opt/homebrew/bin/python3` explicitly when keeping that compiler
PATH, or insert only the selected Python directory ahead of `/usr/bin`:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/opt/homebrew/opt/python@3.15/bin:/usr/bin:$PATH"
python3 --version
python3 -c 'import sys; assert sys.version_info >= (3, 15); print(sys.executable)'
clang --version
python3 -m unittest discover -s tool -p '*_test.py' -v
```

This keeps the installed Apple compiler selected and uses the requested Python
without changing system settings. Record the actual interpreter path and version
with new software/provenance checks. Earlier Python 3.9 records retain their
original dates and facts; rerunning with 3.15 produces a separate record.

When Python tests or tools launch another Python script, use `sys.executable`
for the child. A bare `python3` in subprocess arguments independently resolves
PATH and can undo an explicit parent-interpreter selection. New provenance
checks should retain the parent and child executable paths.

## Dependencies and licenses

The [published package](https://pub.dev/packages/libserialport_plus) and its [changelog](https://pub.dev/packages/libserialport_plus/changelog) were checked on November 8, 2026. Pub selected 1.0.5 with Dart 3.13.7. Version 1.0.0 removed the Flutter SDK/plugin dependency and introduced Dart native asset build hooks. The installed 1.0.5 archive's `hook/build.dart`, `lib/src/serial_port.dart`, `serial_port_info.dart`, and exception implementation were reviewed. `open()` returns `void` and defaults to read/write; `isOpen()` is a method. The Dart metadata API does not require an explicit `open()`, but native internals on some platforms open ports, so platform guards are required.

The [build hook](https://github.com/jakobkordez/libserialport_plus/blob/main/hook/build.dart) compiles the package's bundled C sources; Meshchan does not fetch submodules, write FFI bindings, or locate external serial libraries. The Linux backend uses `/sys` but also opens `serial8250` candidates to probe them, so Meshchan blocks native enumeration before calling it. Android compiles the same backend and is guarded as well. The Windows metadata initialization opens USB serial ports to wake devices, so Windows enumeration is blocked too. The hook uses standard C headers and a C compiler, with no libudev link dependency. No extra Ubuntu packages were added to CI without an observed need; the remote build still needs verification.

Windows native handle creation is also blocked before any constructor or open call: the pinned wrapper allocates a four-byte `Int` for `isOpen()`, but the native implementation writes an eight-byte `HANDLE` on 64-bit Windows. Windows `port-check` therefore returns an expected platform failure instead of invoking that unsafe API. These guards must be reviewed against an upstream fix before enabling those operations; successful compilation alone is insufficient.

License checks used the installed 1.0.5 archive, not just pub metadata:

| Source | License evidence |
| --- | --- |
| Dart wrapper | Package-root `LICENSE`: MIT, copyright 2026 Jakob Kordež. |
| Bundled `src/libserialport` C library | `README` states LGPL3+; source headers specify LGPL version 3 or later; `COPYING` contains LGPL version 3. |

These are separate licenses. The wrapper's MIT license does not relicense the native C library. This step records the dependency license findings and leaves Meshchan's license choice unchanged.

## Install, format, analyze, and test

From the repository root, using the session PATH above:

```bash
dart pub get
dart pub get --enforce-lockfile
dart pub workspace list
(cd packages/meshchan_core && dart run build_runner build)
git diff --exit-code -- packages/meshchan_core/test/support/dependency_probe_database.g.dart
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
python3 -m unittest discover -s tool -p '*_test.py'
(cd packages/meshchan_core && dart test)
(cd packages/meshcore_link && dart test)
(cd apps/meshctl && dart test)
```

For a clone with an unchanged lockfile, start with `dart pub get --enforce-lockfile`. After intentional dependency changes, let pub resolve and update the root lockfile, review the diff, then enforce it. Do not perform unrelated workspace upgrades. Format only files involved in a change when fixing formatting.

Root analysis excludes `build/**`, which holds retained candidates, copied native
source materials and legacy validation checkouts. These preserved artifacts are
not workspace source packages. Member libraries, generated library code, tests
and development tools remain covered by the normal root analysis command.

Tests inject a small serial service, handle adapter, or native operation callbacks and never enumerate or open actual hardware. CLI tests check output, warnings, exit codes, exact-path forwarding, and that help/version/invalid arguments do not invoke diagnostics. Core tests check metadata failures, close/dispose behavior, open/state/close/dispose failures, and primary-error preservation. Regressions also cover false open-state reports, partial acquisition before an open failure, already-closed recovery, and USB serial numbers embedded in full or truncated Linux descriptions. Platform tests verify that blocked backends never execute their native callbacks. Invalid UTF-8 decoding tests retain the affected path, continue other records, and dispose every metadata handle; errors outside that decoding boundary still propagate. Build hooks compiling native assets are expected during tests.

## Offline core package and dependency baseline (1C.2)

The public entry is `package:meshchan_core/meshchan_core.dart`; see the
[package README](../packages/meshchan_core/README.md). Immutable values cover
draft content/revision metadata, operation-specific profile parameters, the two
settings, and safe diagnostic configuration/result/cleanup/recovery snapshots.
IDs accept only 32 lowercase hexadecimal digits. UTC instants, explicit stable
codes, named microsecond fields, bounded page sizes/cursors, and independent
nullable facts follow the [1C.1 contract](architecture/offline-core.md).
`DraftRepository`, `ProfileRepository`, `SettingsRepository`, and read-only
`DiagnosticHistory` describe asynchronous committed-save/query contracts.
These were initially interfaces in 1C.2; drafts are implemented in 1C.4 and
profiles/settings/core resolution in 1C.5. Profile constructors remain typed input
values with partial local checks; complete operation/route/capacity validation
runs at the repository and resolver boundaries. Neither communication nor CLI
code depends on this package. Core now depends on the workspace `meshcore_link`
public pure helpers, preserving that direction.

Dependency selection on November 11, 2026, used the official
[pure Dart setup](https://drift.simonbinder.eu/setup/),
[native backend](https://drift.simonbinder.eu/platforms/vm/),
[testing](https://drift.simonbinder.eu/testing/),
[empty database annotation API](https://pub.dev/documentation/drift/latest/drift/DriftDatabase-class.html),
[Pub workspaces](https://dart.dev/tools/pub/workspaces), and
[pub get](https://dart.dev/tools/pub/cmd/pub-get) documentation, then actual
resolution on the installed SDK. Manifests use compatible caret constraints;
the single root lockfile fixes these direct package dependencies:

| Role | Resolved version | License evidence in installed archive |
| --- | --- | --- |
| `drift` | 2.35.4 | MIT, root `LICENSE` |
| `sqlite3` | 3.9.1 | MIT Dart wrapper, root `LICENSE`; default SQLite itself is [public domain](https://sqlite.org/copyright.html) |
| `drift_dev` | 2.35.3 | MIT, root `LICENSE` |
| `build_runner` | 2.17.1 | BSD-3-Clause, root `LICENSE` |
| `test` | 1.33.0 (already locked) | BSD-3-Clause, root `LICENSE` |

Normal `pub get` added 21 packages and changed no preexisting locked version.
New MIT transitive dependency: `sqlparser` 0.45.1. New BSD-2-Clause dependency:
`recase` 4.1.0. New BSD-3-Clause dependencies: `build` 5.0.0, `build_config`
1.4.0, `build_daemon` 4.1.7, `built_collection` 5.1.2, `built_value` 8.13.0,
`charcode` 1.4.0, `checked_yaml` 2.0.4, `dart_style` 3.1.14, `fixnum` 1.1.1,
`graphs` 2.3.2, `json_annotation` 4.12.0, `pubspec_parse` 1.7.0, `source_gen`
4.3.1, `stream_transform` 2.1.2, and `yaml_edit` 2.2.4. These classifications
were checked against installed root license texts. `json_annotation` is a
generator dependency; no model/JSON generator was added to business code.
Existing analyzer 14.7.0, native hook/toolchain packages, test packages, and
`libserialport_plus` 1.0.5 remain locked. No override or full upgrade was used.
This records dependency findings without choosing Meshchan's license or
completing redistribution work.

The selected sqlite3 package's default hook downloads its own versioned native
asset and verifies its expected hash. Let that hook manage the asset; do not
redirect it to a system library or manually install a SQLite dylib. Network
access to the upstream GitHub release is needed on a cold hook cache. Existing
serial build hooks still require the installed compiler/platform SDK. Keep
independent test processes, code generation, and native builds sequential.

Run code generation **from `packages/meshchan_core`** with
`dart run build_runner build`, after locked root resolution. The tracked
`test/support/dependency_probe_database.g.dart` is generated, never hand-edited.
The minimal `build.yaml` preserves the default source set (including `test/`)
and disables managers: the selected generator's default empty manager contained
an unused private `_db` field, which failed analysis. This is not a production
schema choice. After generation, use the root `git diff --exit-code` command
above to reject stale tracked output; CI also verifies that the file is tracked.
When initially adding the fixture, compare hashes across two successive builds.

The empty test-only database receives a `QueryExecutor`; its test supplies
`NativeDatabase.memory()`, executes `SELECT 1 AS value`, checks one integer row,
and awaits close in `finally`. The fixture's version 1 is only an in-memory test
version. No product `databaseSchemaVersion`, tables, migration/snapshot, file
factory, default directory, or lock is introduced. It is not evidence of
restart persistence or SQLite product AOT/relocation compatibility.

1C.3 starts from these public types and repository declarations and the proven
executor/generator seam. It must implement real schema 1 and its snapshot,
directory identity/exclusive ownership, host-supplied path/executor lifecycle,
supported/corrupt/newer-version failures, and the migration baseline. Repositories
remain for 1C.4–1C.5; mapping/coordinated writes/recovery/history/export and CLI
composition remain for 1C.6–1C.9. Package and application versions stay
`0.1.0-dev.2`. No device operation is required by this step.

### 1C.2 local validation on November 11, 2026

The worktree started clean on `master` at
`3e9eb0a6f5aa851be289290149e393bc54ac06ca`, the merged 1C.1 reference.
No existing partial business package or later implementation was present.
Checks used macOS **27.2.1 (26B131), arm64**, and the existing SDK's direct
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart`: **3.13.7 stable**.
Flutter cache metadata reports **3.47.9 stable**, revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`; no fresh Flutter CLI result is
claimed. The process-only PATH preferred the existing **Apple Clang 21.0.0**
(`clang-2100.4.1.1`). Python ran through `/opt/homebrew/bin/python3`, **3.15.2**,
with `sys.executable` = `/opt/homebrew/opt/python@3.15/bin/python3.15`.
No SDK/global configuration or upstream package source was changed.

| Check | Actual local result |
| --- | --- |
| Normal `dart pub get`, root lockfile review, then `dart pub get --enforce-lockfile` | Passed; 21 additions, no existing locked version changes. The initial sandboxed get could not reach pub.dev; the authorized network-enabled get succeeded. |
| `dart pub workspace list` and member lockfile checks | Passed; three members plus the root package displayed, with no member lockfile. |
| Member-directory `dart run build_runner build` | Passed with the minimal manager option; successive builds preserved the generated fixture's SHA-256 `7162ad177089ef3bbd6a7e19cd4bca59214e21b002d35b17e7bb0b6f08e977a7`. |
| Root format check and `dart analyze --fatal-infos` | Passed; 71 Dart files, zero formatting changes, no analysis issues. Initial empty-manager warning and super-parameter lint were fixed through generator configuration/source, without editing generated output or suppressing analysis. |
| `meshchan_core` full suite | **12 passed**, including the real in-memory SQLite query. The first sandboxed test could not reach GitHub for the default hook asset; the authorized network-enabled rerun passed with awaited database close. |
| `meshcore_link` full suite | **180 passed**. |
| `meshctl` full suite | **97 passed**, including local loopback sockets with the required execution access. |
| Python discovery, `python3 -m unittest discover -s tool -p '*_test.py' -v` | **46 passed**, using the explicit Homebrew interpreter above. |
| Three existing native bundle targets, sequential fresh output | Passed: product CLI, serial observation example, and development datagram acceptance. Output: `/private/tmp/meshchan-1c2.j73InL/{meshctl,observation,datagram-acceptance}`. Each build copied the existing serial native asset. |
| Shared `tool/smoke_cli.py` with those three bundles and the direct Dart SDK | **69 macOS process checks passed**, including broken pipe, complete CLI bundle relocation, and all five source/AOT synthetic datagram scenarios. Linux enumeration refusal was not applicable on this host. |
| Final patch/new-file review | Tracked and new-file whitespace, conflict markers, generated-file presence, local documentation targets/anchors, and unique root lockfile checked. Existing CLI/communication sources and versions are unchanged. |

Existing-suite, Python, native-build, and smoke logs remain in the ignored
`build/1c2-validation/` directory. The generated fixture is delivered as a new
source file, not an ignored build artifact; initial-addition reproducibility was
checked by hashes rather than pretending an untracked file appears in a tracked
`git diff`. CI verifies tracked generation after the files are committed.

The CI workflow now generates/checks the fixture after dependency resolution and
tests the new member before the retained CLI/communication/native gates. No
remote Actions result for these working-tree changes was dispatched or observed.
No real port enumeration/open, hardware command, deployment connection, or RF
operation was run. These CLI builds and smoke cases do not call SQLite and do
not validate its product AOT distribution. Real-file restart persistence,
migrations, directory ownership, and recovery remain unimplemented.

## Serial framing (Step 3)

Step 3 introduced serial framing and its software tests. Step 4 connects that unchanged codec to a native serial transport; Step 5 adds a separate in-memory Companion message codec. Step 6 adds [session initialization](protocol/companion-session.md), with software-only acceptance and hardware validation pending. See [Serial transport](protocol/serial-transport.md) for its separate stream and resource contracts.

The public core API exposes `encodeSerialFrame`, `SerialFrameDecoder`, decode result/error types, and `maxSerialFrameContentLength`. The codec imports only `dart:typed_data` and does not invoke diagnostics or native serial operations. See the [fixed protocol baseline, policies, and in-memory examples](protocol/serial-framing.md). The existing core `dart test` command automatically includes these tests; CI configuration does not need to change.

The new framing tests cover independent fixed vectors, every two-part split of a short stream, bytewise input, empty chunks, coalesced frames and pending tails, full 16-bit length validation, noise budgets, failure locking, finish/reset, independent instances, offset views, and byte ownership. Existing native safety and CLI tests remain in place.

### Software validation on November 8, 2026

The starting worktree was clean on `master` at `5e5864a9114ebbc5a496921a3560cbc8b025ff2c`. Local ancestry confirms that Step 2 commit `1f65198aa7fef29692271e29ed2e6aa0022fcf1a` is included through the PR #1 merge. Both fixed MeshCore source links were checked online at commit `81dbae592ffad40b4212bc0b37e82b38da08f4bc`.

The standard `flutter --version --machine` and `dart --version` wrappers failed because the sandbox denied writes to `/opt/homebrew/share/flutter/bin/cache/engine.stamp.tmp.*` and `engine.realm`. The existing SDK's `bin/cache/flutter.version.json` reports Flutter 3.47.9 stable, revision `c197ca5199e9ee5661e865596c9c07294dfab51c`; a fresh Flutter CLI version result was unavailable. Direct execution of that SDK's bundled Dart reported 3.13.7 stable on `macos_arm64`. No SDK or global configuration changes were made, and no alternate SDK was installed.

Checks used the same bundled Dart binary directly, with the existing Apple compiler preferred for this process:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" --version
"$MESHCHAN_DART" pub get --enforce-lockfile
"$MESHCHAN_DART" format --output=none --set-exit-if-changed .
"$MESHCHAN_DART" analyze --fatal-infos
(cd packages/meshcore_link && "$MESHCHAN_DART" test test/serial_framing_test.dart)
(cd packages/meshcore_link && "$MESHCHAN_DART" test)
(cd apps/meshctl && "$MESHCHAN_DART" test)
```

Locked dependency resolution passed without lockfile changes. Formatting checked 9 Dart files with no changes, analysis reported no issues, all 11 new framing tests passed, the complete core suite passed 21 tests (including 10 existing diagnostics tests), and the CLI suite passed all 10 existing tests.

From `apps/meshctl`, source `dart run bin/meshctl.dart --help`, `--version`, `ports --help`, and `port-check --help` all exited `0`, using `"$MESHCHAN_DART"` in place of `dart`. The native bundle regression passed with the same binary for `dart build cli --target=bin/meshctl.dart --output=build/dist`. The resulting `build/dist/bundle/bin/meshctl --help` and `--version` both exited `0`; the application version remains `0.1.0-dev.1`. The executable and `lib/liblibserialport_plus.dylib` are included in the ignored bundle directory.

This validation uses no real enumeration, `port-check`, serial reads/writes, or device protocol commands. Step 2's [hardware validation record](hardware-validation.md) is preserved as historical evidence. No remote GitHub Actions run was dispatched or observed for Step 3; Linux and other-platform execution remain unverified.

## Serial transport (Step 4)

`CompanionTransport` and `SerialTransport` add one explicit-port connection attempt, complete-content reception, and nonblocking framed writes. No CLI subcommand was added; `port-check` still performs only the original diagnostic without a reader or new settings. The [transport contract](protocol/serial-transport.md) records the installed reader source review, configuration limits, pause/cancel behavior, monotonic deadline, and stop-before-release order.

Transport tests use injected connections and a matching monotonic time/delay seam, with the real codec. No runtime or test dependency was added. Run the focused tests and compile the opt-in example without opening hardware:

```bash
(cd packages/meshcore_link && dart test test/serial_transport_test.dart)
(cd packages/meshcore_link && dart build cli --target=example/serial_transport_check.dart --output=build/serial-transport-check)
```

The example build exercises the new adapter's AOT path and native asset packaging, which the diagnostic CLI alone does not cover. CI includes this build in its existing fixed-SDK job; it does not execute the example against hardware. Existing dated Step 2/3 results remain historical.

### Software validation on November 9, 2026

The starting worktree was clean on `master` at `ec2a98a5a95d596312ecf2b26d67d1d24884ee08`, the PR #2 merge commit. Local ancestry includes its framing head `24b3e76d8af0c59df3029e3f40ce9156d04f4e8a`; the PR page also showed merged status when checked. No checkout, fetch, merge, commit, or push was performed during the initial software validation.

Both SDK wrappers were attempted and failed because the sandbox denied writes to SDK cache engine stamps and `engine.realm`. The same installed SDK's direct `bin/cache/dart-sdk/bin/dart --version` succeeded and reported Dart 3.13.7 stable (`macos_arm64`). Existing `flutter.version.json` reports Flutter 3.47.9 stable, revision `c197ca5199e9ee5661e865596c9c07294dfab51c`; that is metadata, not a fresh successful Flutter CLI result. The host reported macOS 27.2 (26B123), arm64. Apple Clang 21.0.0 was selected with process-only PATH `/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`. No SDK, global configuration, permissions, or pub-cache sources were modified.

The root lockfile and resolved package configuration still select `libserialport_plus` 1.0.5. Its actual installed reader, port, configuration, enums, error helpers, build hook, and relevant native flow-control setters were inspected read-only. The fixed Companion initialization source was also checked online at `81dbae592ffad40b4212bc0b37e82b38da08f4bc`. No dependency, lockfile, application version, or license change was needed.

All Dart commands below used `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` with the process PATH above:

| Check | Actual result |
| --- | --- |
| `dart pub get --enforce-lockfile` | Passed; root lockfile unchanged. |
| `dart format --output=none --set-exit-if-changed .` | Passed; 14 Dart files, zero changes after formatting the edited files. |
| `dart analyze --fatal-infos` | Passed; no issues after correcting initial style findings. |
| Focused `test/serial_transport_test.dart` | Passed; 14 behavior groups using the real codec and injected native boundary/time. |
| Complete core suite | Passed; 35 tests, including all 21 existing diagnostics/codec tests. |
| Complete CLI suite | Passed; all 10 existing tests. |
| Source CLI help, version, `ports --help`, `port-check --help` | Passed; each exit 0, application version `0.1.0-dev.1`. |
| Existing CLI native bundle build, bundle help/version | Passed; each exit 0. |
| `dart build cli --help` and example native bundle build | Passed with the documented target/output syntax; no port supplied. |
| Source and bundled example usage branches | No arguments and a whitespace-only argument each exited 64 with usage, no stdout, and no transport construction/open. |
| Native assets | Both bundles include a Mach-O arm64 executable and `lib/liblibserialport_plus.dylib`; outputs remain ignored. |

Build hooks ran during the initial software checks; this is native compilation rather than hardware access. During that initial validation, no real `ports`, `port-check`, transport open/configuration/read/write, or example with a selected port was run. Reader/configuration hardware behavior, native TX, disconnect handling, MeshCore compatibility, and LoRa operation were unverified at that point. No remote Actions run was dispatched or inspected for Step 4; the CI change preserves the fixed SDK and existing Linux enumeration refusal.

### Authorized read-only hardware follow-up on November 9, 2026

After the software checks, the user requested hardware testing, authorized enumeration, and explicitly selected `/dev/cu.usbmodem211101` for configuration and three seconds of observation without sending data. The source example initially returned I/O failures; the diagnostic CLI reported `Resource busy (code: 16)`. After the user confirmed release of the port, the same source example passed: local open/configuration succeeded, two complete content frames of 50 and 47 bytes arrived, and awaited reader stop/port close/dispose completed with exit 0. Only lengths and counts were printed. The same direct Dart 3.13.7 and locked serial library were used, with tool-approved device execution access.

This is limited local evidence for configuration, reception, framing integration, and normal shutdown on the selected port. Native TX, forced disconnects, the bundled example's hardware path, device identity, command processing, and LoRa remain unverified. Full commands and the failed attempts are preserved in the [hardware follow-up record](hardware-validation.md#authorized-read-only-follow-up-on-november-9-2026).

### Review follow-up: receive failures during partial writes

On November 9, 2026, review found that a receive failure during a partial-write
retry caused the in-flight send to throw a cancellation `StateError`, losing the
classified terminal reason already delivered to the receive stream. Four new
regression tests reproduced this against the previous code for native read error,
clean unexpected EOF, invalid framing, and truncated EOF.

The send loop now propagates the recorded terminal failure when shutdown
interrupts a retry, retaining the same object, kind, cause, and cleanup details.
It still rejects intentional close/cancel/pause without a terminal failure with
`StateError`. The tests cover retry resumption both during and after cleanup,
with successful cleanup and with a close error, and check that no additional
write or duplicate disposal occurs. Intentional subscription cancellation and
pause are also covered while a send is in flight.

Using the same direct bundled Dart 3.13.7, locked dependency resolution,
formatting, and fatal-info analysis passed. The focused transport suite passed
18 tests, the complete core suite passed 39, and the CLI suite passed 10. The
serial observation example's AOT bundle rebuilt successfully without a port.
The root lockfile is unchanged. No hardware operation was performed during this
review follow-up; the earlier authorized hardware record remains separate.

## Companion command and response codecs (Step 5)

The public core exports `encodeAppStart`, `encodeDeviceQuery`, and
`decodeCompanionResponse`, plus the sealed `CompanionResponse` family and
`CompanionProtocolException` / `CompanionProtocolExceptionKind`. Implementation
is in `packages/meshcore_link/lib/src/protocol/companion_messages.dart`; focused
tests are in `packages/meshcore_link/test/companion_messages_test.dart`.

These synchronous functions operate only on complete inner content. They do not
add or decode serial headers, call a transport, or perform I/O. The
[protocol note](protocol/companion-initialization.md) records the checked field
table, fixed source commits, version/length gates, display UTF-8 replacement,
NUL handling, byte ownership, and privacy policies. SELF_INFO uses the full
58-byte prefix. DEVICE_INFO supports basic fields from protocol 3, repeat from
9, and path-hash mode from 10; earlier layouts fail explicitly. Future versions
use only the known prefix under a documented compatibility assumption. Device
errors return data; unhandled messages imply neither failure nor startup success.

### Software validation on November 9, 2026

The starting worktree was clean on `master` at
`6923925cc0b6f6a4c1c93b949ea6ee509df02213`, the PR #3 merge commit. The actual tree
contains the Step 4 transport interface, native adapter, framing integration,
lifecycle tests, read-only example, and existing CLI diagnostics. No checkout,
merge, pull, rebase, commit, push, or remote Actions dispatch was performed.

The fixed MeshCore firmware and header at
`81dbae592ffad40b4212bc0b37e82b38da08f4bc` and official Python reader at
`c5ffc383730db311ac91b5ef5067e2808584ef92` were re-read online. Their command
branches, response layout, error codes, and version gates agree with the field
table. The implementation was independently written; no upstream code was copied.

Both `/opt/homebrew/share/flutter/bin/flutter --version --machine` and
`/opt/homebrew/share/flutter/bin/dart --version` failed because the sandbox denied
SDK-cache writes to `engine.stamp.tmp.*` and `engine.realm`. The same SDK's direct
binary reported Dart 3.13.7 stable, `macos_arm64`. Existing
`/opt/homebrew/share/flutter/bin/cache/flutter.version.json` reports Flutter 3.47.9
stable, revision `c197ca5199e9ee5661e865596c9c07294dfab51c`; this is metadata, not
a fresh successful Flutter CLI result. The current process preferred the existing
Apple Clang 21.0.0 through PATH. No SDK, permissions, global configuration,
dependency versions, pub-cache sources, application version, or license changed.

Commands ran from the repository root or the indicated member directory with:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" --version
"$MESHCHAN_DART" pub get --enforce-lockfile
"$MESHCHAN_DART" format --output=none --set-exit-if-changed .
"$MESHCHAN_DART" analyze --fatal-infos
(cd packages/meshcore_link && "$MESHCHAN_DART" test test/companion_messages_test.dart)
(cd packages/meshcore_link && "$MESHCHAN_DART" test)
(cd apps/meshctl && "$MESHCHAN_DART" test)
git diff --check
```

| Check | Actual local result |
| --- | --- |
| Locked dependency resolution | Passed; root lockfile unchanged. |
| Formatting and fatal-info analysis | Passed; 16 Dart files, zero formatting changes after formatting only the task files; no analyzer issues. |
| Focused Companion tests | Passed; 12 behavior groups. |
| Complete core suite | Passed; 51 tests, including the 39 existing tests. |
| Complete CLI suite | Passed; 10 tests. |
| Source CLI help, version, `ports --help`, `port-check --help` | Passed; all exit 0, application version remains `0.1.0-dev.1`. |
| CLI AOT bundle build and bundle help/version | Passed with `dart build cli --target=bin/meshctl.dart --output=build/dist`; all exit 0. |
| Read-only example AOT bundle build | Passed with the unchanged CI command: `dart build cli --target=example/serial_transport_check.dart --output=build/serial-transport-check`. |
| Source and bundled example usage-only checks | Passed; no arguments and a whitespace-only argument each returned 64, no stdout, the expected usage diagnostic, and no stack trace. No valid port was supplied. |
| Diff and scope checks | Passed; no whitespace errors. Framing/transport implementations, CLI, example, dependencies, lockfile, CI, and historical hardware records are unchanged. |

An initial attempt started the two member test commands concurrently. The core
command exited 1 before tests because `install_name_tool` could not rename the
shared `.dart_tool/lib/liblibserialport_plus.dylib`; CLI tests passed. Both use
the same workspace native-asset output. Subsequent focused tests, complete test
suites, and builds were run serially and passed without SDK, dependency, or
native-source workarounds. The initial failure is not counted as a passing run.

New tests cover independent command vectors, UTF-8 byte limits, reserved bytes,
signed TX power, little-endian radio fields, variable-length names, version and
length boundaries, unsupported and future layouts, known/unknown device errors,
unhandled responses, field-local NUL handling, malformed text replacement,
privacy summaries, offset views, retained-key ownership, and framing composition.
All fixtures are synthetic; no native handle or transport is constructed by the
new tests.

During the initial software validation, no real `ports`, `port-check`, valid-port
example, serial initialization command, or radio operation was run.
Step 2/4 hardware observations remain historical;
their passive frame reception does not establish APP_START or DEVICE_QUERY
success. Session management and real initialization remain unimplemented and
unverified. CI remains pinned and unchanged, including the Linux enumeration
refusal check. No Linux-host or remote Actions run was performed or observed;
the Linux-specific `ports` check was not run on this macOS host.

### Authorized hardware follow-up on November 9, 2026

The user subsequently requested real USB testing on `/dev/cu.usbmodem211101`.
A temporary ignored probe used the existing transport and the public codec APIs,
with an explicit test target version of 3, one DEVICE_QUERY, and one APP_START.
It added no product session API or CLI command and left the read-only example
unchanged. The probe was removed after validation.

The restricted attempt failed with `Operation not permitted`; device-access
execution then failed with `Resource busy`. Read-only `lsof` inspection found
Brave holding the port. After the user confirmed release, the same probe passed
at 10:02:52..10:02:54 UTC with exit 0: DEVICE_INFO parsed at 82 bytes with reported
protocol code 14, SELF_INFO parsed at 64 bytes, two frames total, zero parser
failures, and successful awaited cleanup. Only structural summaries were logged.
The direct bundled Dart 3.13.7 and pinned serial dependency were unchanged.

This validates the observed USB command/response path on that port, not full
protocol-14 functionality, authenticated identity, an implemented session layer,
or LoRa communication. See the [separate hardware record](hardware-validation.md#step-5-authorized-command-probe-on-november-9-2026)
for the failed attempts, successful output, authorization, and limits. No new
hardware test was added to CI, and no remote Actions run was performed.

## Companion session (Step 6)

`MeshCoreSession` adds one callable initialization attempt over an unused,
exclusively owned `CompanionTransport`. It reuses the existing codec and inner
content contract without changing serial framing, the native adapter, CLI, or
read-only example. See the [session contract and minimal example](protocol/companion-session.md)
for states, ownership, type-based matching, privacy, deadlines, and the difference
between logical termination and resource release.

The public result combines the existing DEVICE_INFO and SELF_INFO models with
the application's declared target. The session sends DEVICE_QUERY with named
policy target 3, then APP_START; both sends and both expected responses must
succeed before ready. Request and total budgets default to 5 and 15 seconds;
startup delay defaults to zero. One long-lived receive subscription and one
pending slot handle early responses without parallel sends. Terminal state and
local tokens invalidate old callbacks. New transport/session instances are
required for retry. There is no generic command API, automatic retry, reconnect,
polling, or new CLI subcommand.

### Software validation on November 9, 2026

The starting worktree was clean on `master` at
`ec6477ddba4347f9d74945b182c08aec530b2bba`. Local ancestry includes Step 5 head
`60d08a4ff92f138b32509ad3d2734308f96615b1`; the [PR #4 page](https://github.com/007pig/meshchan/pull/4)
also showed merged status. The actual interfaces, protocol and transport tests,
read-only example, manifests, root lockfile, existing CI, and applicable guidance
were inspected before implementation. No checkout, pull, merge, reset, rebase,
commit, push, PR creation, or version/license change was performed.

Both Homebrew SDK wrappers were attempted. Flutter's version command and Dart's
wrapper failed because SDK-cache writes to `engine.stamp.tmp.*` and `engine.realm`
were denied. The **same SDK's existing direct binary** succeeded:

```text
Dart SDK version: 3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "macos_arm64"
```

No fresh successful Flutter version-command result is claimed. All successful
Dart checks used `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` with
process-only PATH `/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`. The installed
Apple Clang reported 21.0.0 (`clang-2100.4.1.1`). No SDK, global PATH, permissions,
or pub-cache source was modified, and no alternative SDK was installed.

The core now directly declares `fake_async: ^1.3.3` in dev_dependencies, alongside
the existing test dependency. Normal `dart pub add --dev fake_async` resolved
stable 1.3.3 and its `clock` 1.1.3 transitive dependency. An initial restricted
network attempt failed with a socket error; the same pub command succeeded with
approved network access. Only these two additions changed the root lockfile;
existing versions, including `libserialport_plus` 1.0.5, did not change. Locked pub
resolution passed before and after adding the dependency. No member lockfile or
production dependency was added. Dart asynchronous documentation and fake_async
documentation were checked online; the established wire baseline was retained.

All package tests and native builds below ran **serially** in the same workspace:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" --version
"$MESHCHAN_DART" pub get --enforce-lockfile
"$MESHCHAN_DART" format --output=none --set-exit-if-changed .
"$MESHCHAN_DART" analyze --fatal-infos
(cd packages/meshcore_link && "$MESHCHAN_DART" test test/meshcore_session_test.dart)
(cd packages/meshcore_link && "$MESHCHAN_DART" test)
(cd apps/meshctl && "$MESHCHAN_DART" test)
git diff --check
```

| Check | Actual local result |
| --- | --- |
| Locked dependency resolution | Passed with the reviewed additions above. |
| Formatting and fatal-info analysis | Passed; 19 Dart files checked with zero formatting changes after formatting task files; no analyzer issues. |
| Focused session tests | Passed; 16 behavior groups using real decoding, synthetic content, a small fake transport, and virtual time. |
| Complete core suite | Passed; 67 tests, including the 51 existing tests. |
| Complete CLI suite | Passed; 10 tests. |
| Source CLI help/version and both subcommand help invocations | Passed; all exit 0, version remains `0.1.0-dev.1`. |
| Existing CLI native bundle build and bundle help/version | Passed; `dart build cli --target=bin/meshctl.dart --output=build/dist`, all exit 0. |
| Existing read-only example native build | Passed; unchanged CI command `dart build cli --target=example/serial_transport_check.dart --output=build/serial-transport-check`. |
| Source/bundled example usage-only checks | Passed; no arguments and one whitespace-only argument each returned 64, with no stdout, the expected usage diagnostic, and no stack trace. Four process checks; no valid port supplied. |
| Documented minimal example | Passed focused fatal-info analysis as an ignored temporary file inside the core package; the temporary file was removed. It was not executed. |
| Diff and scope checks | Passed; no whitespace errors, no changes to the codec implementation, framing, transport, native adapter, CLI, read-only example, or CI. |

The first analysis pass reported style issues, which were fixed in task files.
The first focused test run had four cleanup-completion assertions fail because
the fake's cancellation returned the SDK's shared preexisting completed Future,
outside the virtual-time zone. Returning a zone-local Future from the fake's
cancel callback corrected the fixture; the subsequent focused and full suites
passed. An initial doc-example analysis from the root package reported a missing
direct package dependency; analyzing it in the intended core package passed.
These initial checks are not counted as passes.

The 16 groups cover ordered inner-content commands and target/report-version
separation; wrong-type, early, duplicate, OK, push and unknown messages; responses
during send and delayed send failure; per-request and combined total deadlines;
late open/send results; device errors and protocol causes; sync/async transport
faults, EOF and duplicate fault reporting; active/idle close; pending/failed
cleanup, preserved primary failure and subscription cancellation failure;
independent asynchronous observers; single-use attempts and independent instances;
local argument validation and redacted summaries. Tests also check timer removal
and that an old request timer cannot terminate the next step. Automatic cleanup
errors are observed even before an explicit close error handler is attached.

The existing CLI and read-only example do not call the session, so their builds
can tree-shake it away. Those successes are existing-artifact regressions, not
evidence of session AOT execution. Session behavior was verified by the actual
session tests. Session AOT execution and hardware validation remain pending.
No real enumeration, valid-port example, port check, device initialization, or
LoRa operation ran. The Step 5 temporary probe remains historical evidence only.
No Linux-host execution or remote Actions result for Step 6 was run or observed.
The fixed CI SDK and Linux enumeration-refusal check remain unchanged; platform
guard unit tests ran, but the Linux process check was not run on this macOS host.

### Authorized session hardware follow-up on November 9, 2026

After the software acceptance above, the user explicitly authorized real sessions
on `/dev/cu.usbmodem211101`, identifying it as a dedicated test device and allowing
configuration adjustments as needed. The follow-up used the same direct Homebrew
Dart 3.13.7 and pinned `libserialport_plus` 1.0.5. A temporary ignored, guarded
hardware harness called the actual public `MeshCoreSession` with a thin tracing
transport delegating to `SerialTransport`. It did not duplicate initialization,
change the protocol policy, add a CLI command, or modify the read-only example.

All attempts used 115200/8N1, app target 3, request timeout 5 seconds, total timeout
15 seconds, and `Meshchan` as the application name. Only the caller-supplied
startup delay changed. Each attempt used a fresh transport and session, and each
awaited close before the next attempt. These were separate manual acceptance
attempts, not an automatic retry feature.

| Attempt (UTC) | Actual result |
| --- | --- |
| Source, delay 0, 10:54:29..10:54:34 | Exit 69; DEVICE_QUERY locally sent once, three unassociated frames received, requestTimeout waiting for DEVICE_INFO. APP_START was not sent, ready was not reached, and awaited close succeeded. |
| Source, delay 1 second, 10:55:15..10:55:22 | Exit 69; 82-byte DEVICE_INFO parsed, APP_START locally sent once, requestTimeout waiting for SELF_INFO. No ready/info publication; awaited close succeeded. |
| Source, delay 3 seconds, 10:56:48..10:56:51 | Exit 0; one DEVICE_QUERY and one APP_START, 82-byte DEVICE_INFO with raw protocol code 14 and 64-byte SELF_INFO. Connect reached ready after 3331 ms including startup delay. Complete expected state sequence and awaited cleanup passed. |
| Compiled AOT harness, delay 3 seconds, 10:57:44..10:57:47 | Exit 0; reopened the same port with a fresh session, received both expected responses plus two unassociated pushes, reached ready after 3378 ms including delay, then closed successfully. |

Successful state sequences were opening, initializing, ready, closing, closed.
Each successful run observed one open, two sends, and one delegated transport
close. Concurrent/repeated close calls shared the same Future. In the AOT run,
`0x88` (148 bytes) and `0x80` (33 bytes) arrived during startup and were summarized
without completing initialization or causing extra commands. Both failed runs
stayed failed after cleanup, correctly preserving their timeout reason.

The temporary harness passed fatal-info analysis and a no-argument guard check
with exit 64 before device access. It was then built with:

```bash
# From packages/meshcore_link, using the same process PATH and MESHCHAN_DART.
"$MESHCHAN_DART" build cli --target=.dart_tool/step6_hardware_session.dart \
  --output=build/step6-hardware-session
```

The compiled harness's no-argument guard also returned 64 without device access.
Unlike the existing CLI/read-only example build, this AOT executable directly
instantiated and ran `MeshCoreSession` on hardware. Its source was removed after
validation; its bundle remains an ignored local build artifact, not a product or
published tool. No production code, dependency, SDK, or default setting changed
during this follow-up. The hardware record includes the exact historical commands
and the initial harness-summary correction.

These results add limited source and AOT session evidence on this selected macOS
device. They do not isolate the cause of the short-delay failures or establish
long-term reliability. Three seconds is the explicit setting used in the two
successful runs, not a changed default or universal firmware requirement. No
firmware, radio, identity, time, contact/channel, DTR/RTS, flush, or reset command
was issued. LoRa, forced disconnects, cleanup hangs/failures on real hardware,
other platforms, and remote Actions remain unverified.

### Session timeout investigation on November 9, 2026

The user authorized further investigation of zero- and one-second initialization
failures. Native-boundary tracing confirmed correct outgoing framed commands and
both successful and stalled receive cases. A separate Python 3 standard-library
POSIX control reproduced a header declaring 64 bytes with no body for five
seconds, without any Dart session, reader, transport, or libserialport. An
explicitly diagnostic follow-up query released the missing body. This locates
the captured SELF_INFO timeout before complete bytes reach the client parser.

The user-authorized configuration experiment temporarily changed only the node
name length. With SELF_INFO at 65 bytes, the unchanged existing AOT session
harness passed twice at delay zero and twice at delay one second. The exact
original name was restored and verified without printing or saving it. A fixed
POSIX comparison then observed immediate responses in 3/3 trials at 63 bytes,
2/3 at 64 bytes, and 3/3 at 65 bytes; the stalled 64-byte body was released by a
diagnostic query. Original-name restoration reproduced another 64-byte stall,
and restoration was again verified. Original-configuration native-traced AOT
sessions also passed at both zero and one second, demonstrating intermittency.

No client defect was demonstrated, so production code and defaults were not
changed. A USB short-packet/ZLP or output-flush issue is consistent with the
64-byte correlation, but firmware versus host-driver responsibility remains
unresolved without USB-side or cross-host evidence. The historical first
DEVICE_QUERY timeout lacked a native trace and was not individually explained by
these SELF_INFO captures. See the [detailed evidence and limitations](hardware-validation.md#session-timeout-investigation-on-november-9-2026).
Increasing startup delay is not an established fix; diagnostic release queries
and temporary name changes were not added to the session.

One new integration test in `test/serial_transport_test.dart` combines the actual
session, transport, framing, and Companion decoder with the existing synthetic
native boundary. It covers a standalone header followed by either a timely
64-byte body or no body until after the request deadline. It checks no premature
ready/info, timeout classification, no extra query/retry, late-body isolation, and
one cleanup. Timeouts use the existing direct `fake_async` test dependency.

The following checks ran serially using the same existing direct Dart 3.13.7
entry and process-only PATH recorded above:

| Check | Actual result |
| --- | --- |
| Locked pub resolution | Passed; no further manifest or lockfile change. |
| Formatting and fatal-info analysis | Passed; 19 Dart files, no formatting changes after formatting the edited test, no analyzer issues. |
| Focused transport tests | Passed; 19 tests, including the new integration group. |
| Focused session tests | Passed; 16 groups. |
| Complete core suite | Passed; 68 tests. |
| Complete CLI suite | Passed; 10 tests. |
| Temporary native-trace source and AOT build | Passed analysis after correcting style issues in the temporary harness; AOT hardware runs and their successful/failed outcomes are recorded separately. |
| Diff and scope check | Passed; no production code, dependency, CLI, existing example, or CI change in this investigation. |

Existing CLI/example builds were not repeated because production code did not
change. The earlier AOT session harness was reused unchanged for the controlled
0/1-second tests; the native-traced diagnostic harness was built separately.
Temporary diagnostic sources were removed. No capture of private device fields,
firmware flashing, SDK/cache patch, extra production API, or remote Actions run
was added. The selected device retains its original name and radio settings.

## Source CLI behavior

Step 7 adds `info` and `watch` over the existing session. The [CLI guide](cli.md)
is the current command, option, structured output, cancellation, and exit-code
contract. The diagnostic/platform notes below still apply to ports/port-check.

From `apps/meshctl`:

```bash
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart ports --help
dart run bin/meshctl.dart port-check --help
dart run bin/meshctl.dart info --help
dart run bin/meshctl.dart watch --help
```

No arguments and `-h` also display help. Top-level help takes precedence over version. Subcommand help does not require `--port` or call diagnostics. Invalid syntax and extra positional arguments are rejected before any serial operation. The version is the constant in `apps/meshctl/lib/src/version.dart`, independent of the working directory; keep it consistent with the CLI pubspec and its behavior test. It remains `0.1.0-dev.1` for this step.

On enabled backends, `ports` returns exact paths sorted lexicographically, keeping distinct paths even when metadata matches. It prints descriptions, library-reported transport, and optional USB VID/PID; unknown values appear as `-`, not fabricated zeroes. It never opens ports or sends probes; backends with implicit opens are rejected before native enumeration. Native objects used for metadata are explicitly disposed. Per-port metadata failures, including invalid UTF-8 from the native info getter, retain their paths and produce stderr warnings; a total enumeration/native load failure returns `69`. Decoding warnings include the reason without printing the malformed source bytes or a stack trace. A genuinely empty result prints `No serial ports found.` and returns `0`. The adapter retains only the displayed metadata; it does not expose or log the upstream info object's USB serial number or Bluetooth address. Known USB serial numbers are removed from descriptions as well, including full or truncated Linux-style suffixes in metadata projection tests. System port paths remain unchanged.

| Platform | Native `ports` | Native `port-check` |
| --- | --- | --- |
| macOS | Locally validated without opening ports. | Selected-port open/close locally validated. |
| Linux / Android | Blocked with `69` before native enumeration. | Explicit-port operation remains unverified. |
| Windows | Blocked with `69` before native enumeration. | Blocked with `69` before native handle creation. |

Help, version, and argument validation remain available without invoking native diagnostics on these platforms. Source invocations can still require the dependency's build environment.

| Exit code | Meaning |
| --- | --- |
| `0` | Success, including an empty enumeration. |
| `64` | Argument error, unknown option/command, extra positional argument, or missing/blank `--port`. |
| `69` | Expected serial, platform, session, or cleanup failure. |
| `74` | Host/storage/file/output I/O or finalization failure without an earlier primary cause. |
| `130` / `143` | SIGINT / SIGTERM cancellation after awaited cleanup. |
| `70` | Unexpected program error at the process boundary. |

Normal results go to stdout; errors and warnings go to stderr. Expected diagnostic errors retain available safe native details without a stack trace or an assumption that the port is busy; session failures use only structural fields. Unexpected programming errors propagate from `runCli` and are handled at the process boundary with exit 70. A source build-hook failure can terminate Dart before the application runs and is not governed by the application's exit-code contract.

Verify argument-error process codes on macOS or Linux:

```bash
dart run bin/meshctl.dart unknown-command
echo $?  # Expected: 64.
dart run bin/meshctl.dart port-check
echo $?  # Expected: 64.
```

## Native bundle and relocation

[Dart CLI builds](https://dart.dev/tools/dart-build) run native asset hooks and bundle their output. From `apps/meshctl`:

```bash
dart build cli --help
dart build cli --target=bin/meshctl.dart --output=build/dist
build/dist/bundle/bin/meshctl --help
build/dist/bundle/bin/meshctl --version
build/dist/bundle/bin/meshctl ports
```

The verified macOS arm64 output is:

```text
apps/meshctl/build/dist/bundle/
├── bin/meshctl
└── lib/liblibserialport_plus.dylib
```

Both files were confirmed as Mach-O arm64. The dynamic library links to macOS system libraries/frameworks; it does not require a development pub-cache path. Build output stays ignored by Git. Copy the whole bundle, then run from outside the repository:

```bash
# Run from apps/meshctl, after building.
MESHCHAN_BUNDLE_TEST_DIR="$(mktemp -d /private/tmp/meshchan-bundle.XXXXXX)"
cp -R build/dist/bundle "$MESHCHAN_BUNDLE_TEST_DIR/bundle"
cd "$MESHCHAN_BUNDLE_TEST_DIR"
./bundle/bin/meshctl --version
./bundle/bin/meshctl ports
```

The successful relocation check above was performed on macOS. On Linux, use a temporary directory such as `/tmp` and expect `ports` to return `69` because enumeration is blocked; this does not verify native enumeration or runtime native library loading there. Never copy only the executable or set a dynamic library path to a developer's pub cache. Local directory relocation is not clean-machine or cross-platform verification. An additional local macOS check removed the library from a separate temporary copy and confirmed that `ports` failed with `69`, empty stdout, and a native-load diagnostic without a stack trace.

## Explicit device checks and protocol boundary

On November 8, 2026, the user explicitly selected `/dev/cu.usbmodem211101`. Two source CLI checks, separated by a stabilization interval, and one bundle check with approved device access all returned `0`. The first bundle attempt in the restricted sandbox reported `Operation not permitted`; rerunning with the same execution access as the successful source checks passed. See the [validation record and hardware checklist](hardware-validation.md) for the exact commands and limits. Select a target explicitly before each new device test.

`port-check` performs one read/write open, state check, close, closed-state check, and disposal. It does not enumerate candidates, retry opening, read/write data, flush input, or configure baud rate, flow control, DTR/RTS, reset, or bootloader state. Cleanup still runs after failures; cleanup errors are appended to an expected primary error, and failure is never reported as success.

The pinned wrapper's `isOpen()` reports a valid POSIX descriptor `0` as closed. The check still reports that validation failure, but successful-open ownership is retained so `close()` runs before disposal and detaches the wrapper's finalizer. The bundled POSIX `sp_open()` can also acquire a descriptor before a lock/exclusivity failure. The native adapter attempts `close()` once on an open failure without relying on `isOpen()`. For its valid, undisposed native object, it tolerates only `SP_ERR_ARG` (`-1`) from this recovery close, which indicates no open handle, including when upstream already closed it. Other cleanup errors remain attached to the primary error. No new FFI or dependency patch is used.

Opening/closing can trigger board resets through driver or control-line behavior; this is not guaranteed to be side-effect-free. See [Espressif's control-line guidance](https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/boot-mode-selection.html). Do not toggle lines to test reset behavior.

Successful open/close does not identify a MeshCore device or establish protocol support, firmware identity, a session, or LoRa communication. Step 3 added in-memory framing; Step 4 adds the reader/writer adapter described above. Step 5 provides the codecs. Step 6 adds callable session initialization over a supplied transport; its hardware validation remains pending. Reconnection, radio tests, database, and UI remain unimplemented.

## CI and SDK updates

The existing single `ubuntu-latest` job remains pinned to Flutter `3.47.9` stable via `subosito/flutter-action@v2.23.0`, using its bundled Dart and read-only repository permissions. It runs locked dependency resolution, formatting, analysis, both full test suites, and sequential native builds for the product CLI, read-only observation example, and separate 1B.8 development datagram probe. The [shared smoke script](testing.md#shared-smoke-contract-and-ci) checks source/AOT entries, arguments, broken pipes, complete product-bundle relocation, native assets, and both executions of the five synthetic datagram scenarios. On Linux it also invokes real source and bundle `ports` commands and strictly requires exit `69`, empty stdout, the exact Linux safety diagnostic, and no stack trace. Any different failure or a successful enumeration fails smoke. It never runs a valid `port-check` and does not ignore native build failures. No platform matrix or release workflow was added.

This is an intentional restriction of the earlier Ubuntu enumeration acceptance check: with the pinned backend, successful enumeration would violate the no-open requirement. Ubuntu CI validates native compilation/packaging and the refusal to enumerate, not successful native enumeration or runtime native library loading. Actual enumeration remains locally validated on macOS. No fake enumeration or ignored failure is used in CI.

CI configuration was updated; no remote workflow was run for these changes. Ubuntu results remain unverified. Local macOS success does not establish Linux, Windows, mobile, or clean-machine support.

After a Homebrew SDK change, record the actual versions/channel, run every applicable check above, and review lockfile changes. Update the fixed CI baseline and this guide together only when the local SDK actually changed and compatibility checks pass. Do not upgrade Flutter, switch channels, or reinstall Homebrew packages as part of routine project validation.

See the [Validation Record](hardware-validation.md) for dated results and remaining hardware work.

## Diagnostic session CLI (Step 7)

Step 7 adds asynchronous `info` and `watch` commands over the unchanged public
session, with explicit-port validation, text/JSON output, signal cancellation,
and shared awaited cleanup. See [CLI usage and schema](cli.md). No core production
code, read-only example behavior, platform guard, protocol target, timeout default,
or application version changed. `apps/meshctl` now directly declares
`fake_async: ^1.3.3`; normal `dart pub get` retained the existing resolved 1.3.3
and produced no root lockfile difference. There are no new production dependencies.

### Software validation on November 9, 2026

The initial worktree was clean on `master` at
`e27c024850ea80c8b3537f9c6aaf41895cbd812e`, the Step 6 merge. Applicable ancestor
and repository agent guidance was checked; no additional on-disk AGENTS.md was
found. No checkout, pull, merge, reset, rebase, commit, push, PR, or release was
performed. Hardware authorization from earlier records was not reused.

Both `/opt/homebrew/share/flutter/bin/flutter --version --machine` and that SDK's
`bin/dart --version` wrapper failed because the sandbox denied cache engine-stamp
and `engine.realm` writes. Direct execution of the same installed SDK's
`bin/cache/dart-sdk/bin/dart --version` reported Dart 3.13.7 stable on macos_arm64.
The installed `flutter.version.json` reports Flutter 3.47.9 stable, revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`; this is metadata, not successful fresh
Flutter CLI validation. Actual host checks reported macOS 27.2 (26B123), arm64,
and Apple Clang 21.0.0 (`clang-2100.4.1.1`). No SDK or dependency source was
patched, and no global PATH or permission changes were made.

Commands used the process-only PATH and direct Dart below. Package tests and
native builds ran serially to avoid the recorded shared-native-asset conflict.
Only task Dart files were formatted before the read-only workspace format check.

```bash
# From the repository root.
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" --version
"$MESHCHAN_DART" pub get
"$MESHCHAN_DART" pub get --enforce-lockfile
"$MESHCHAN_DART" format --output=none --set-exit-if-changed .
"$MESHCHAN_DART" analyze --fatal-infos
(cd packages/meshcore_link && "$MESHCHAN_DART" test)
(cd apps/meshctl && "$MESHCHAN_DART" test)
(cd apps/meshctl && "$MESHCHAN_DART" build cli --target=bin/meshctl.dart --output=build/dist)
(cd packages/meshcore_link && "$MESHCHAN_DART" build cli --target=example/serial_transport_check.dart --output=build/serial-transport-check)
git diff --check
```

| Check | Actual result |
| --- | --- |
| Normal and enforced locked pub resolution | Passed; no lockfile change or unrelated package upgrade. |
| Workspace format and fatal-info analysis | Passed; 24 Dart files, no pending formatting changes, no analyzer issues. |
| Complete core suite | Passed; 68 tests. Core implementation and tests are unchanged. |
| Complete CLI suite | Passed; 26 tests: the original 10 migrated to awaited Futures plus 16 focused behavior groups. |
| Source help/version and command help | Passed; no arguments, top-level help/version, and all four subcommand help paths returned 0 (7 process checks). |
| Final rebuilt CLI bundle help/version | Passed; the same 7 process checks returned 0 with empty stderr, version `0.1.0-dev.1`. |
| Source/bundle usage rejection | Passed; 14 strict subprocess assertions from the added CI check, substituting only the local direct Dart path. Missing info/watch ports, empty info port, and invalid time inputs without a selected port returned 64, empty stdout, a usage diagnostic, and no stack trace. No valid port was supplied. |
| CLI native bundle | Passed; fresh `dart build cli`, including executable and `lib/liblibserialport_plus.dylib`. Rebuilt after the final production change. |
| Read-only example native bundle | Passed with the unchanged CI build command; includes its native dylib. |
| Source/bundled read-only example usage | Passed; no arguments and one whitespace-only argument each returned 64, empty stdout, expected usage diagnostic, and no stack (4 process checks). |
| Complete CLI bundle relocation | Passed; copied the entire final bundle to a fresh `/private/tmp` directory. Help/version/info-help/watch-help returned 0, with no stderr (4 process checks); the temporary copy was removed. |
| CI syntax | Passed; parsed the workflow YAML and checked all 11 run blocks with `bash -n`, plus both embedded Python blocks. SDK/action pins, permissions, single Ubuntu job, and exact Linux enumeration refusal assertion remain unchanged. |
| Diff/scope | Passed; no whitespace errors, no core/example behavior change, no version or license change. |

The process smoke run totals 36 hardware-free assertions (14 help/version,
14 usage errors, 4 example guards, 4 relocation checks). Source native build-hook
progress on stderr is outside the application schema. Early incremental checks
reported type/style issues and a virtual-time completion mismatch; those failed
iterations were corrected and are not counted as passing runs.

The new tests use real `MeshCoreSession` and decoding with a small independent
fake transport and synthetic DEVICE_INFO/SELF_INFO. They cover side-effect-free
validation and help/version priority, unchanged path forwarding, JSON nulls and
key prefix, exactly two sends, close-before-info output, early watch events,
deduplicated failures, pending/failed cleanup, ready-relative duration, signal
races including queued initialization advancement, output-failure priority,
asynchronous IOSink.done/flush failures, bounded queue overflow, safe text and
secret sentinels, invocation isolation, and lazy supported-signal registration
and cancellation. The process boundary also verifies safe exit 70 for an injected
programming error. All timers/fake Futures are created inside virtual-time zones;
no seconds-long test sleeps, native handles, real enumeration, device access, or
OS signals are used. Broadcast observer cancellation removes the observer
synchronously and observes its empty completion; native cleanup and signal-source
cancellation are awaited. A later cleanup error retains an existing primary
failure/signal code and receives a safe supplemental diagnostic.

No real `ports`, `port-check`, valid-port info/watch, or valid-port example was
executed. Historical hardware results remain historical. Step 7 hardware,
Linux-host process behavior, other operating systems, and remote GitHub Actions
were not run or observed. The historical intermittent USB SELF_INFO body delay
and potentially pending native cleanup remain unresolved; no retry, repair
query, reset, flush, name change, or default startup delay was introduced.
Step 8, LoRa round trips, reconnect, database, and UI work were not started.

### Authorized CLI hardware follow-up on November 9, 2026

The user subsequently authorized `/dev/cu.usbmodem211101` for actual Step 7 CLI
tests. The current CLI bundle was rebuilt successfully with the same direct
Dart 3.13.7/Apple compiler and reported `0.1.0-dev.1`. Six source/native command
invocations ran serially with unchanged defaults (5-second request budget,
15-second total budget, zero startup delay). Source and native 5-second JSON
watch runs passed, as did native ready-state SIGINT/SIGTERM cleanup with expected
exit codes 130/143. All four watch runs produced one ready, the complete normal
state sequence, parseable NDJSON, and one end with cleanup succeeded.

Both info attempts failed initialization: source timed out on `0x16` / expected
`0x0D`; native timed out on `0x01` / expected `0x05`. Each returned 69 with empty
stdout, one primary diagnostic, awaited cleanup, and no cleanup failure; later
sessions reopened the same port. These are failed initialization results, not
successful info hardware acceptance or proof of the historical delayed-body
mechanism. No retries, extra commands, timeout/delay changes, forced kill,
configuration changes, or production fixes were added.

The [hardware record](hardware-validation.md#step-7-authorized-cli-hardware-follow-up-on-november-9-2026)
contains the six actual outcomes, UTC times, and limits. Device display data was
validated only in memory; only structural summaries were retained. Software test
counts above are the earlier software runs and were not rerun for documentation
changes. No core/protocol/CLI source, dependency, lockfile, or version changed in
this follow-up. Remote Actions, other-platform behavior, and LoRa remain
unverified. No commit, push, PR, release, or Step 8 work was performed.

### CLI timeout comparison on November 9, 2026

The user requested investigation of the apparent info/watch difference on the
same explicitly selected `/dev/cu.usbmodem211101`, with a minimal fix only if a
client defect was demonstrated. The worktree stayed on `master` at `e27c024`,
retaining the existing uncommitted Step 7 implementation. No production file,
dependency, lockfile, version, app target, timeout, or startup-delay default was
changed. All hardware attempts used the actual CLI/session/serial code with the
same 5/15-second budgets and zero startup delay; watch's post-ready observation
window was one second for these comparisons.

The fixed hardware experiment had 12 cases: unmodified AOT watch/info/info/watch,
then traced info/watch/watch/info with memory sinks, then the same order with
real IOSinks. The unmodified cases all succeeded, including two consecutive info
snapshots. The traced cases had four successes and four timeouts. In total, info
and watch each succeeded four times and failed twice; these small descriptive
counts are not reliability estimates. Cases were not added until one passed.

An ignored temporary AOT probe used the existing internal native connection seam,
delegating every operation to the real connection and recording only structural
monotonic events in memory until close. The product's codec, initialization, and
transport algorithm were unchanged. The probe passed focused fatal-info analysis,
a native build, and source/bundle no-argument exit-64 guards before device access.
No second receive subscription, payload capture, extra query, retry, forced kill,
serial flush, or device configuration change was used.

The four captured timeouts had incomplete frames at the native receive callback:
three had only a 3-byte header for a 64-byte SELF_INFO body; one had 21 of the
85 total DEVICE_INFO bytes, also missing a 64-byte suffix. Every complete native
frame matched transport delivery, every started send completed once with full
native byte acceptance, and cleanup began 5.001..5.003 seconds after the pending
request. Successful traced info closed only after full SELF_INFO delivery.
All processes completed cleanup naturally; all traced native releases followed
reader stop/done before port close/dispose. No CLI initialization defect was
demonstrated, so no production fix or timing workaround was added. Responsibility
for missing bytes below that callback remains unresolved; a specific firmware,
USB/driver, native-library, or reader-side cause was not proven.

See the [full fixed outcomes and timing evidence](hardware-validation.md#step-7-cli-timeout-comparison-on-november-9-2026).
The earlier failed info attempts remain failures. Native info hardware success is
now observed in separate runs with unchanged defaults; source info was not rerun
in this AOT comparison. Device text and bytes were inspected only in memory and
were not retained as captures. The temporary probe source was removed from the
package; its ignored build output remains a local diagnostic artifact.

The only new code is `apps/meshctl/test/session_serial_cli_test.dart`: one focused
group with 16 virtual-time combinations of command, partial response stage,
timely/absent suffix, and ordinary/blocked output. It replaces only the native
connection and exercises the real CLI, session, transport, and decoder. It checks
both observed partial-frame shapes, no early close/ready/info, success just before
the deadline, correct timeout metadata, late-byte rejection, no extra sends,
reader-before-port cleanup, ready-relative duration, and timer removal. It uses
synthetic fixtures and the CLI's existing direct fake_async dependency.

Actual software checks used the same direct SDK Dart 3.13.7 and process-only Apple
compiler PATH recorded above. Core and CLI tests ran serially. The focused group
passed all 16 combinations; full core passed 68 tests, full CLI passed 27 tests,
root formatting checked 25 Dart files with no changes, fatal-info analysis found
no issues, locked pub resolution and `git diff --check` passed. No unrelated
package upgrade occurred. No commit, push, PR, release, Step 8, LoRa, other-platform,
or remote Actions run was performed.

### Independent POSIX control on November 9, 2026

The user authorized a standard-library POSIX comparison on the same selected
`/dev/cu.usbmodem211101`, keeping the existing deadlines and device configuration
and prohibiting retries, release queries, or flushes. This follow-up changed only
validation documentation. The existing Step 7 code, app target 3, Meshchan name,
5-second request/15-second total budgets, zero startup delay, dependencies,
lockfile, and application version stayed unchanged.

A temporary Dart encode-only helper generated the normal two outgoing frames
using the existing public codec/framing API. It passed focused fatal-info analysis
and performed no device I/O. The independent Python 3.15.2 process then used
os.open/os.write/os.read/select/termios/fcntl only: no Dart, libserialport_plus,
FFI, reader, or pyserial. Its separate frame counter retained only structural
prefix bytes and lengths. It passed three self-test groups (including all 154
two-part splits of the synthetic expected frame sizes), Python syntax checks,
and missing/wrong-port exit-64 guards before hardware execution.

All six POSIX opens applied and verified the same raw 115200/8N1 host tty profile
as the existing native transport, using TCSANOW without flush/drain or explicit
RTS/DTR output changes. Newly opened descriptors reported the OS's 9600/HUPCL-on/
CLOCAL-off/VMIN-1 initial profile; the control applied the existing baseline on
each open instead of assuming a preceding descriptor's settings persisted. This
was host serial setup, not a stored device/radio configuration change. flock and
TIOCEXCL ownership were released before closing, and all processes returned
naturally without a forced timeout or kill.

The fixed experiment used three POSIX/native/native/POSIX blocks (12 serial
attempts), with the unchanged native AOT info trace as the other path. Every
attempt had exactly one accepted 5-byte write and one accepted 19-byte write.
POSIX had three successes and three APP_START/SELF_INFO timeouts; native had four
successes and two timeouts with the same header-only shape. These are finite
case counts, not reliability/performance statistics, and no attempts were added
until a desired result occurred.

In each POSIX failure, after complete DEVICE_INFO and the one APP_START write,
the sum of nonempty os.read results was exactly three bytes: a header declaring
64 bytes of content. At the original request deadline FIONREAD was zero, select
was not readable, one immediate nonblocking read returned zero bytes, and the
tty queue was still empty at close. No grace period, extra command, or flush
was used to expose or rescue late data. The reader/wrapper therefore are not
required to reproduce this symptom: the missing content was not returned to
this independent client and discarded afterward. No client defect or justified
production fix was identified. Device generation, USB delivery, and driver-private
buffering/loss remain distinct unresolved possibilities. The earlier native
DEVICE_INFO 21/85-byte case was not independently reproduced in this round.

See the [complete POSIX/native outcomes and OS-queue observations](hardware-validation.md#step-7-independent-posix-comparison-on-november-9-2026).
All raw receive content and device fields stayed out of logs/captures; only
structural records were retained outside the repository. The encode-only Dart
helper was removed from the package. No new production API, package, runtime
policy, or default test dependency was introduced. Prior core 68/CLI 27 results
were not rerun for documentation-only changes; fresh control self-tests, Python
syntax checks, workspace format (25 Dart files), fatal-info analysis, and
`git diff --check` passed. No commit, push, PR, release, Step 8, LoRa, other-platform,
or remote Actions work was performed.

## Step 8 software validation on November 9, 2026

Started on clean `master` at `7847e74a2cdf94b872be296227c6a26326cbb353`, the
Step 7 PR #6 merge. The [testing guide](testing.md) records the behavior audit,
shared smoke contract, exact acceptance commands and evidence limits. No missing
unit/integration group was identified: zero Dart tests were added, deleted or
weakened. The 16 synthetic split-body CLI combinations remain in their existing
parameterized group. Product source, application version, dependencies, lockfile,
platform guards, reader ownership and cleanup budgets are unchanged.

Actual host: macOS 27.2 (26B123), arm64; Python 3.15.2; Apple Clang 21.0.0.
`/opt/homebrew/share/flutter/bin/flutter --version --machine` failed because the
sandbox denied cache stamp/realm writes. This was not a successful Flutter CLI
check. The same SDK's installed
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --version` succeeded and
reported Dart 3.13.7 stable (`macos_arm64`, October 22, 2026). All Dart checks used
that executable with `/usr/bin` ahead of Homebrew compilers in the process PATH;
no alternate SDK, upgrade, cache edit or permission change was performed.

| Local check | Observed result |
| --- | --- |
| `pub get --enforce-lockfile` | Passed; lockfile unchanged. |
| Root format check and `analyze --fatal-infos` | Passed before and after edits; 25 Dart files, zero formatting changes, no analysis issues. |
| Full core / CLI suites, serial execution | Baseline: 68 / 27 passed. After edits: 68 / 27 passed again. No retries or randomized-order runs. |
| `dart build cli --help` and fresh CLI/example builds | Confirmed installed flags/layout; both builds passed serially. |
| Shared smoke | 46 macOS process checks passed, then passed again after tightening help validation, invoking the script from outside the checkout. |
| Real native stdout pipe with read end already closed | Exit 74, safe output-failure diagnostic, no unhandled exception or stack, in both smoke runs. |
| Whole CLI bundle copied outside checkout | Version, info help and missing-port exit 64 passed from the temporary cwd, including a path with spaces; copy removed automatically. Both original bundles and relocated CLI contained nonempty executable/native library assets. |
| Script validation | `--help`, Python syntax, missing arguments, invalid Dart path, missing bundle and empty bundle rejection passed. |
| `git diff --check` | Passed for the tracked patch; new Python/Markdown files were separately reviewed for whitespace. |
| Linux enumeration refusal | Not applicable on this macOS host; not executed or simulated. CI will run real source/native `ports` and `ports --json`, requiring 69 and the exact guard diagnostic. |

Fresh build output is retained for inspection at
`/private/var/folders/g2/3ydgbl6n0xn9cv4h_sqv70qc0000gn/T/meshchan-step8.HVaxrh/`,
with `meshctl/bundle/` and `observation/bundle/`. No old build was substituted;
user build directories were not removed. An intermediate tooling edit initially
used a package cwd for a root-relative script path and failed with
`FileNotFoundError`; it was corrected from the root before smoke execution. This
was an editing-command error, not a product/test failure or a successful check.

CI now calls the shared script after both builds, with 60-second child watchdogs
and a 20-minute job timeout. It retains the existing single Ubuntu runner,
Flutter 3.47.9, action pins, triggers and read-only permissions. No workflow was
triggered, rerun or changed remotely. There is no remote run for these uncommitted
Step 8 changes, and local success does not establish a Linux result.

For historical context, read-only GitHub API checks during this task confirmed
both Step 7 runs below as `completed / success`, each reporting head
`b4ec6d15213b503bf51890b4f852ad2342eaefe8`:

- [Push run 42679410025](https://github.com/007pig/meshchan/actions/runs/42679410025), event `push`.
- [PR run 42679506860](https://github.com/007pig/meshchan/actions/runs/42679506860), event `pull_request`.
  [Job 129369919414](https://github.com/007pig/meshchan/actions/runs/42679506860/job/129369919414)
  reported analysis, both suites, native builds, usage checks and Linux refusal
  successful. Its PR checkout context may differ from the push checkout; the
  reported head SHA is not a claim that both checked out the same Git ref.

These observed Step 7 results supersede earlier historical statements that
remote results had not yet been observed. They do not validate Step 8 changes.
No commit, push, PR, release, real port enumeration/open, device info/watch,
LoRa exchange or Step 9 acceptance was performed. The intermittent missing
64-byte USB body remains unresolved and unattributed; passing synthetic tests
and same-host AOT entry checks does not establish a hardware fix, actual native
library loading, successful native session I/O or clean-machine compatibility.


## Step 9 build and delivery on November 9, 2026

The task began on clean `master` at `e1e16e28c2d99be197a9ed18a1df269f522e5c40`,
the Step 8 merge, with ancestor `20441a0ef78f96d9d805b520f6d9eeb90ce5ec5c` verified
locally. No product/compilation input, lockfile, dependency, version, CI or license
changed. Only README and validation/delivery documentation were edited afterward.
Build provenance is that clean commit, with the uncommitted delivery documentation
recorded separately, rather than a worktree binary attributed to an older commit.

Both Homebrew SDK wrappers were attempted and denied SDK cache-stamp/realm writes.
The same SDK's direct Dart version command succeeded: 3.13.7 stable, macos_arm64.
Flutter 3.47.9 stable, revision `c197ca5199e9ee5661e865596c9c07294dfab51c`, is
existing flutter.version.json metadata, not a new successful CLI result.
Host: macOS 27.2 (26B123), arm64; Apple Clang 21.0.0 (`clang-2100.4.1.1`), selected
through current-process PATH; Python 3.15.2. No SDK or pub-cache source was edited.
Root lockfile SHA-256 remained
`9d31c319b24e72356feed7168a457671dd49cd356513f6ab77414edc473e504c`.
libserialport_plus remained 1.0.5.

The [existing software procedure](testing.md) ran once sequentially on the actual
candidate: locked resolution passed, formatting checked 25 files with no changes,
fatal-info analysis passed, core 68 tests and CLI 27 tests passed, and both new
native bundles built. CLI build started at `2026-11-09T20:39:00Z` in a fresh
outside-checkout output directory; observation build followed it. Shared smoke
passed all 46 macOS cases. No new unit tests were needed for documentation-only
delivery. Whitespace and final sensitive-content/untracked-file reviews passed.

Existing remote CI was rechecked read-only for these specific Step 8 results:

| Run | Event | Reported head SHA | Observed result |
| --- | --- | --- | --- |
| [42684752517](https://github.com/007pig/meshchan/actions/runs/42684752517) | push | `20441a0ef78f96d9d805b520f6d9eeb90ce5ec5c` | completed / success |
| [42684795613](https://github.com/007pig/meshchan/actions/runs/42684795613) | pull_request | `20441a0ef78f96d9d805b520f6d9eeb90ce5ec5c` | completed / success |

The PR event may use a merge-test checkout; no actual checkout SHA is inferred.
These are existing commit/event results, separate from this fresh local gate and
hardware evidence. No workflow was dispatched, rerun, pushed or changed.

The complete CLI bundle was copied outside the checkout before native hardware
acceptance. The [fixed matrix](hardware-validation.md#step-9-device-acceptance-on-november-9-2026)
passed H2–H7, H1/H8/H9; H10 was not authorized/run. Every process returned naturally
with confirmed cleanup; no retry, forced termination or manual intervention was
needed. No initialization timeout occurred; historical USB faults remain unresolved.

The [local delivery](releases/phase-1a-dev1.md) includes the complete CLI bundle,
README, manifest with compilation-input hashes, acceptance snapshot, original
third-party licenses/notices, member checksums and tar.gz plus its SHA-256 sidecar.
Actual fresh archive extraction passed checksums, layout, execute mode, version,
info help and missing-port exit 64. Extracted executable and dylib hashes matched
the hardware-tested copy. Both arm64 files have verified ad-hoc signatures; no
Developer ID signature/notarization is claimed. The candidate is limited to local
development pending project/native/runtime license materials and distribution
review. No clean-machine, other-platform hardware, disconnect or LoRa acceptance
was inferred. No commit, push, tag, PR, Release, new feature or external notification
was performed.


### H10 follow-up and revised delivery

After the initial archive validation, the user authorized assisted unplug/replug.
Two native watch startups (the second separately authorized after the first
cleaned timeout and confirmation that the device stayed connected) each timed
out waiting for DEVICE_INFO, before ready. Both naturally exited 69 with end
failure / 69 / cleanup succeeded; no signal, force, stack, unconfirmed resource
or pending process occurred. Physical unplug/replug and recovery info were not
executed, since the prerequisite was unmet. See the [dated follow-up](hardware-validation.md#step-9-h10-follow-up-on-november-9-2026).

No binary, compilation input, version, dependency or toolchain changed. The prior
software gate and H2–H7 matrix remain dated evidence; no repeat full software suite
or hardware matrix was needed for this documentation update. A new local archive
with the `-h10-followup` suffix includes the revised acceptance and manifest,
with recommendation development-with-known-limitations. Its actual fresh
extraction again passed all 38 member checksums, mode/layout checks, version/help,
missing-port exit 64 and exact native asset hash comparison. The initial archive
is retained as an earlier snapshot; its absence of timeouts is not the current
combined conclusion. No raw hardware output or device identifiers were added to
the repository or archive. Public redistribution blockers remain unchanged.


### Post-replug checks and final info success

The user then performed one USB unplug/replug outside a live session, requested
metadata enumeration, and explicitly selected the current path again. R1 native
info failed at APP_START/SELF_INFO with requestTimeout (5.225721 s, exit 69);
R2 was separately requested and passed (0.256838 s, exit 0, one complete closed
snapshot). Both naturally completed cleanup without signals or forced termination.
The exact commands, timeline and changed conditions are in the [post-replug record](hardware-validation.md#step-9-post-replug-follow-up-on-november-9-2026).
No causal waiting/boot-delay fix is established, and H10 ready-state disconnect
detection remains NOT_RUN. Recommendation remains development-with-known-limitations.

The final `-replug-followup` archive updates only documentation/manifest evidence;
its unchanged binaries retain the original build and software-gate provenance.
Its fresh extraction passed all 38 checksummed files, layout and execution mode,
version/help/missing-port checks and exact binary/native hash comparison. Earlier
archives were preserved. No source, dependency, version, CI, signing, firmware or
configuration change, automatic retry or remote publication was performed.


### H10 startup attempt 3

After R2 info passed, the user requested one more H10 watch on the same confirmed
port. With unchanged native hashes and defaults, it timed out waiting for
DEVICE_INFO before ready (5.583720 s, exit 69, one failure end, cleanup succeeded).
It naturally returned with no signal, force, stack or pending process. No unplug
instruction was given, and no new physical action was reported. See the [dated
attempt](hardware-validation.md#step-9-h10-third-startup-on-november-9-2026).
The latest `-h10-attempt3` archive updates documentation/manifest only; its fresh
extraction again passed all 38 member checksums, modes/layout, version/help,
missing-port rejection and original native hash comparison. Earlier archives and
all failed/successful observations remain intact. Software/build inputs and the
original software gate are unchanged. Recommendation remains development with
known limitations; H10 disconnect/recovery is still unexecuted. No remote or
product change was performed.

## 1B.7 software validation on November 10, 2026

The starting worktree was clean on `master` at
`7443d7466e482e2b9191108e2bc196a6e40e6512`. Local ancestry includes PR #14's
`eebffe94ddc18d44603e78e63d9c68767a18ade3`; the public PR page was rechecked and
showed merged status (the prompt's earlier open status was historical). No remote
PR was merged or published by this work. Changes are local and reviewable.
The application remains `0.1.0-dev.1`, MeshCore remains pinned to
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`, and core protocol/tasks, native
serial, dependencies/lockfile, and CI platforms remain unchanged.

The installed Flutter wrapper was attempted and denied writes to
`bin/cache/engine.stamp.tmp.*` and `engine.realm` under the sandbox. Existing SDK
metadata reports Flutter 3.47.9 stable at
`c197ca5199e9ee5661e865596c9c07294dfab51c`; this is not a fresh successful
Flutter CLI version check. Direct execution of the same SDK's
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --version` reported
Dart 3.13.7 stable on `macos_arm64`. Apple Clang 21.0.0
(`clang-2100.4.1.1`), the existing Xcode developer directory, and macOS 27.2 SDK
were observed. All native commands used process-only PATH
`/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`. No alternate SDK, upgrade,
channel switch, permission/cache modification, or global configuration change
was used.

All Dart commands used that direct bundled binary. Test processes and native
builds ran sequentially, following [the testing procedure](testing.md):

| Check | Actual result |
| --- | --- |
| Root `dart pub get --enforce-lockfile` | Passed; lockfile unchanged. |
| `dart format --output=none --set-exit-if-changed .` | Passed; 43 Dart files, zero changes. |
| `dart analyze --fatal-infos` | Passed; no issues. |
| CLI `dart test --reporter expanded test/datagram_cli_test.dart` | Passed; 25 focused groups using the real session/reception/tasks and existing fake native boundary/output facilities. |
| Complete core `dart test --reporter expanded` | Passed; 180 tests. |
| Complete CLI `dart test --reporter expanded` | Passed; 52 tests, retaining the existing serial cross-layer matrix. |
| CLI `dart build cli --target=bin/meshctl.dart --output=/tmp/meshchan-1b7.Xi6p87/final-meshctl` | Passed; fresh final native bundle after the listen failure-event review. |
| Core `dart build cli --target=example/serial_transport_check.dart --output=/tmp/meshchan-1b7.Xi6p87/observation` | Passed after the initial CLI build; fresh native bundle (core sources unchanged during the CLI review). |
| Shared `tool/smoke_cli.py` with those two bundles and the bundled Dart | Passed; 67 macOS process cases, both native assets, broken pipe, and complete-bundle relocation. Linux-only enumeration refusal was not applicable on this host. |
| `git diff --check`, changed/new UTF-8/LF/final-newline checks, documentation relative links/anchors | Passed. |

The focused tests cover pure validation before factories/signals, explicit empty
and UTF-8 inputs, route-dependent full-frame boundaries, all four real command
paths, one-object/NDJSON projections, final-entry/read settlement, early PONG
with failed local send, nullable microsecond RTT, responder zero/cumulative
response facts, task/command deadlines, pre-start cancellation, locked failure
versus external stop, completed-core/pending-cleanup races, cleanup errors,
output cancellation/final-flush authority, privacy, and late callbacks.

No actual port enumeration/open, device command, radio traffic, or LoRa trial
was performed. Native builds and synthetic tests do not establish device
compatibility or diagnostic AOT execution against hardware. No remote CI run
was dispatched or observed. The previous USB evidence remains unresolved;
1B.8/1B.9 delivery and explicitly authorized two-device acceptance remain separate.

## 1B.8 software validation on November 10, 2026

Started from a clean `master` worktree at
`8eaefeaf3683c6a2cd93143d74ae96f68ff9d57b`, the PR #15 merge, with
`1a5b20816e44d9f0264f372d64d26726641b217d` confirmed as an ancestor.
`gh pr view 15 --repo 007pig/meshchan --json number,state,mergedAt,headRefOid,mergeCommit,url` could not connect to the
GitHub API. The [public PR page](https://github.com/007pig/meshchan/pull/15)
was then read successfully and showed merged status and merge `8eaefea`.
No remote merge, reset, workflow dispatch, commit, push, or publication was
performed. Changes remain local and reviewable on the existing branch.

Actual host: macOS **27.2.1 (26B131), arm64**. The installed SDK metadata
(`bin/cache/flutter.version.json`) reports Flutter 3.47.9 stable at
`c197ca5199e9ee5661e865596c9c07294dfab51c`, with bundled Dart 3.13.7.
This metadata is distinct from a successful version command: the attempted
`/opt/homebrew/share/flutter/bin/flutter --version --machine` failed on denied
`engine.stamp.tmp.*` / `engine.realm` cache writes. No permission/cache change,
second SDK, upgrade, or channel switch was used. The direct bundled
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --version` succeeded:
Dart 3.13.7 stable, `macos_arm64`, October 22, 2026.
Apple Clang 21.0.0 (`clang-2100.4.1.1`) and macOS SDK 27.2 were observed.
The default shell initially selected Homebrew Clang 18.1.8 and Python 3.15.2;
the final gate used process PATH
`/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`, selecting Apple Clang and
**Python 3.9.6** for smoke. Nothing changed the system configuration.

The [1B.8 coverage audit](testing.md#datagram-cross-layer-coverage-audit-1b8)
documents five shared scenarios. Only the final `NativeSerialConnection`
boundary is synthetic: `runCli`, adapters, tasks, session/reception, codec,
`SerialTransport`, asynchronous streams and serial framing execute normally.
The test and development tool share always-active checks and independent fixed
serial byte vectors. The tool imports no test runner and has no hardware mode.

Initial focused runs exposed a support-code settlement error, reporting
`CLI did not settle after cleanup and one event turn` on raw runners even after
`stop, stop.ack, reader.done, stopped, close, dispose`. Investigation identified
the SDK shared cancellation Future crossing the virtual zone during sequential
transport/event/signal cleanup. The final support supplies a controlled
cancellation Future, one zero-duration external event turn, and one explicit
microtask barrier before checking completion. An intermediate controller-close
ordering experiment also failed the explicit stop-stream completion check and
was corrected. No conditional pump, retry-until-pass, real deadline sleep,
production timeout, or production-code fix was introduced. Final focused tests
and the full suite below passed with the corrected support.

The final commands used the direct Dart above and ran each test process, native
build, and smoke child sequentially, following the
[complete reproduction commands](testing.md#reproduce-acceptance-on-the-existing-mac-sdk):

| Check | Actual result |
| --- | --- |
| Root `dart pub get --enforce-lockfile` | Passed; root lockfile unchanged. |
| Root `dart format --output=none --set-exit-if-changed .` | Passed; 46 Dart files, zero changes. |
| Root `dart analyze --fatal-infos` | Passed; no issues. |
| CLI `dart test --reporter expanded test/datagram_acceptance_test.dart` | Passed; five shared serial-byte scenarios. |
| Core `dart test --reporter expanded` | Passed; 180 tests. |
| CLI `dart test --reporter expanded` | Passed; 57 tests, including the five new scenarios and unchanged original 16 info/watch combinations. |
| CLI `dart build cli --target=bin/meshctl.dart --output=/private/tmp/meshchan-1b8.OCTKCs/meshctl` | Passed; fresh complete product bundle. |
| Core `dart build cli --target=example/serial_transport_check.dart --output=/private/tmp/meshchan-1b8.OCTKCs/observation` | Passed; fresh separate read-only observation bundle. |
| CLI `dart build cli --target=tool/datagram_acceptance.dart --output=/private/tmp/meshchan-1b8.OCTKCs/datagram-acceptance` | Passed; fresh separate development bundle. |
| `python3 tool/smoke_cli.py --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --cli-bundle /private/tmp/meshchan-1b8.OCTKCs/meshctl/bundle --observation-bundle /private/tmp/meshchan-1b8.OCTKCs/observation/bundle --datagram-acceptance-bundle /private/tmp/meshchan-1b8.OCTKCs/datagram-acceptance/bundle` | Passed; **69** actual macOS process checks, including broken pipe, whole-product-bundle relocation, three bundles' nonempty native assets, source probe and AOT probe outside checkout. |
| Both probe reports, parsed and type-checked by shared smoke | Passed; exact five unique IDs, completed/passed/failed = 5/5/0; actual CLI exits 0/0/0/0/69. The expected timeout is a passing acceptance scenario. |
| Smoke report validator checks using Python standard library | One valid report accepted; 15 malformed reports rejected, including empty/missing/duplicate IDs, bad types/counts and wrong CLI exit. Python syntax passed. |
| `git diff --check`; changed/new UTF-8, LF, final newline, relative document links/anchors | Passed after completing the dated record and its linked anchor. |
| Linux enumeration checks | NOT_APPLICABLE on this macOS host; not run or simulated. |
| Remote Ubuntu CI for these changes | **NOT_RUN**; no corresponding run was dispatched or observed. The existing job is configured to build the third bundle and call the same smoke script. |
| Real USB/serial, two-device LoRa, device compatibility/stability, signing/release | **NOT_RUN**; outside this software step. |

Retained fresh output (not an old candidate) is
`/private/tmp/meshchan-1b8.OCTKCs/`:

- Product: `meshctl/bundle/`, with `bin/meshctl` and
  `lib/liblibserialport_plus.dylib`. Deliver or move the **entire bundle**.
- Development acceptance: `datagram-acceptance/bundle/`, with
  `bin/datagram_acceptance` and its native asset; keep it out of product content.
- Observation: `observation/bundle/`, with `bin/serial_transport_check` and its
  native asset. The observation example remains read-only.
- Execution logs: `core-tests.log`, `cli-tests.log`, `meshctl-build.log`,
  `observation-build.log`, `datagram-acceptance-build.log`, and `smoke.log`.
  Observed development failure excerpts and their resolutions are retained in
  `development-failures.log`.

The final review found no production source changes. Public exports, CLI
parameters/schemaVersion 1/exit precedence/defaults, app target 3, queue bounds,
ownership/cleanup contracts, dependencies and root lockfile are unchanged.
Application version remains `0.1.0-dev.1`; MeshCore remains pinned to
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`. The planned `0.1.0-dev.2` is not
enabled. The only executable/configuration changes are development acceptance
support, its thin test/tool entries, shared smoke, and the existing CI job.

Dart test success establishes the asserted software behavior. AOT probe success
adds independently compiled execution of production Dart business logic with a
replaced native boundary. Product relocation establishes only the checked
entries on this same host outside the checkout. Native build/assets establish
neither every FFI symbol loading nor reader-isolate execution or hardware I/O.
Synthetic platform injection does not enable protected native capabilities in
Linux. These results are no new device or LoRa evidence and do not repair the
historical intermittent USB partial-body problem. H10 ready-state unplug and a
complete recovery cycle remain open. 1B.9 still needs explicit device/firmware,
channel/radio, forward/return routes, peer labels, binary content and measured
budgets before authorized device trials and final candidate handling.


## 1B.9 software validation on November 10, 2026

Started with clean `master` at `40ab5bcd5638751f4b2362b05792e0de74c92f62`;
PR #16 head `bbe2efbd34aa52d3d25bf7c5106e17ae1609cc32` is an ancestor.
No reset, merge, remote publication or user-edit removal occurred. Updated
workspace package versions, CLI version constant/assertion and core constraint
to `0.1.0-dev.2`; `publish_to: none`, external constraints and the single root
lockfile remain unchanged. Historical dev.1 evidence was not rewritten.

Added a tool-local WS transport, finite source peer, 15 focused CLI-suite
boundary tests, configuration templates, an offline matrix generator and a
local archive/extraction verifier. The peer uses Dart HttpClient/WebSocket and
existing args/core/projections. No production state machine or USB defaults
changed; no production defect fix, new transport export or product flag was added.

Actual host: macOS **27.2.1 (26B131)**, arm64; Apple Clang 21.0.0. Direct bundled
Dart **3.13.7** at `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart`.
Flutter cache metadata says **3.47.9 stable**, revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`; the Flutter wrapper was not run.
Python3 used for this gate was **3.9.6** through the Apple-first process PATH;
the normal terminal's Python3 reported 3.15.2. No SDK/cache/global toolchain
change or second SDK installation occurred.

The full gate ran serially in the fresh ignored directory
`build/phase-1b9/20261110T193252Z/` with process PATH prefix
`/opt/homebrew/share/flutter/bin:/usr/bin`. Actual argv, cwd, UTC start/end and
exit code are in `software-gate.json`; each step has a separate retained log.

| Check | Actual result |
| --- | --- |
| `dart pub get --enforce-lockfile` | PASS; lock SHA-256 `9d31c319b24e72356feed7168a457671dd49cd356513f6ab77414edc473e504c`, unchanged. |
| `dart format --output=none --set-exit-if-changed .` | PASS; 50 Dart files, zero changes. |
| `dart analyze --fatal-infos` | PASS; no issues. |
| Full core tests, then full CLI tests | PASS; 180 / 72, including 15 new openHop boundary tests. |
| Three fresh native builds | PASS; product bin/meshctl.dart, observation example, and existing development datagram_acceptance.dart, sequentially. |
| Shared `tool/smoke_cli.py` with all three fresh bundles | PASS; 69 macOS process checks, native assets, broken pipe, complete product relocation, five synthetic source scenarios and the same five AOT scenarios outside checkout. |
| Offline plan generator | PASS; 14 fresh distinct nonzero IDs, a 131-byte two-route Direct boundary plan, missing prerequisites rejected before output; no network/device access. |
| Final text/relative document links/anchors, whitespace | PASS; performed after the final dated records. |
| New remote CI execution | NOT_RUN; the unchanged existing job includes the new tests, no real credentials/devices. Historical merge CI is not a result for these changes. |

Early focused development runs are not hidden: sandbox loopback bind was denied,
so tests were rerun with loopback execution access. An unused single-subscription
fixture controller made initial focused teardown wait; changing that test-only
controller to broadcast fixed it. The focused 15-test run and subsequent full
gate passed. Native tests/builds were not run concurrently. The full gate has
no hardware/API access; real H0 was a separately authorized later operation.

The whole fresh product bundle was copied to the build's `delivery/<build-id>/`
before H0, and executable/dylib hashes were recorded first. The hardware record
retains A info PASS, B source preparation failure before networking (wrong PATH),
and the subsequently prepared original single WS check PASS. Both sessions
closed successfully. No RF datagram was sent. Additional user-authorized
management reads found actual Repeater/Core versions and a two-radio Fabric;
see [hardware record](hardware-validation.md#1b9-usb-and-openhop-acceptance-on-november-10-2026).

[The local delivery record](releases/phase-1b-dev2.md) and
[peer/matrix guide](openhop-acceptance.md) specify the exact finite next steps.
`tool/package_dev_candidate.py` packages the complete tested candidate, original
notices, compilation-input provenance and an honest acceptance snapshot. It
checks the final archive by fresh outside-checkout extraction, all ordinary-file
checksums, layout, execute mode, tested native hashes and four no-device
invocations. Results are retained in the build's external
`archive-verification.json`; a final tar.gz and whole-archive SHA-256 sidecar
remain under `delivery/`. Only documentation/package metadata changed after H0;
product bytes remain identical. Public distribution, relay/Direct RF, active RF
cancellation and physical disconnect are not inferred from archive integrity.

The final archive verifier ran with the already-installed normal-path Python3
3.15.2 (its `tarfile` data extraction filter is available there). It verified
32 ordinary files and four extracted process checks at
`2026-11-10T19:47:00.186398Z`. SHA-256:
`4d6b0eeb06e119120e51eb197d5a0ffcf77b1a057c6a978050a42d78533e0333`.
The extraction directory is recorded in the external verification JSON and the
release record; the persistent archive/candidate remain under the ignored build
directory. Original dependency materials are retained for 23 external resolved
production-graph packages, plus native COPYING/README and Dart SDK LICENSE.


### Later finite read-only channel audit and WS cleanup follow-up

The user's later request added `tool/channel_audit.dart`, its tool-local support,
a configuration template and 11 tests. No product state machine, version,
dependency, lockfile, USB default, or candidate binary changed. The tool owns no
inbox reader and allowlists only initialization plus GET_CHANNEL; key/frame
buffers are cleared and reports omit names/keys/fingerprints. Explicit single
endpoint mode allows a bounded independent metadata check without silently
retrying another endpoint.

The full CLI suite passed 81 tests initially, then 83 after adding explicit
single-endpoint coverage. Real execution retained two A initialization timeouts,
then obtained eight matching A/B 16-byte key representations. Investigating the
observed report/process-exit gap found a development WS cleanup defect: sink
close completion did not establish receive EOF. The adapter now waits for EOF,
with a held-EOF regression; all **84 CLI tests** then passed, fatal-info analysis
reported no issues and format checked **53 Dart files** with zero changes.
The new source path and affected WS lifecycle tests are part of the ordinary CI
suite, with no real credentials/devices in tests.

A subsequent B-only invocation validated the fixed cleanup path and natural
process exit approximately 14 ms after report output. This is a development
transport fix, not a production USB fix or RF acceptance. The full core suite
and three native bundles were not needlessly rebuilt for these source-tool-only
changes; the previously delivered product/archive hashes are unchanged.
Complete plans, source hashes, test logs and every real result remain in
`build/phase-1b9/20261110T193252Z/hardware/channel-audit-20261110T200255Z/`.
See [the actual audit record](hardware-validation.md#read-only-channel-audit-on-november-10-2026).

### Later passive-window and Direct RF follow-up

A source-only finite passive probe now reuses the existing session/watch runner
with an initialization-only opcode allowlist. Two pure lifecycle tests and a
real loopback probe check verify actual ready/window/cleanup, no consuming or
RF commands, cancellation, and structural output. Unknown exact idle-timeout
configs require an explicitly measured lower bound covering the task budget.
With this coverage the full CLI suite passed **88 tests**; fatal-info analysis
passed. The actual test log is under
`build/phase-1b9/20261110T193252Z/hardware/rf-matrix-20261110T202035Z/cli-tests.log`.
These are later source-tool results, separate from the original 180/72 gate.
Product compilation inputs, lockfile and both tested native hashes are unchanged;
the original three fresh bundles and 69-check source/AOT smoke remain applicable.

The finite plan generator and RF driver default to no device/network I/O. Their
explicit execution mode records command plans, per-attempt source/native hashes,
actual UTC/process/cleanup facts, and never retries application sends. Offline
predicates reject false H2/H6/H7 passes. Python syntax and plan-only validation
are checked separately. The [actual matrix](hardware-validation.md#direct-rf-matrix-on-november-10-2026)
retains client evictions, manual client release, 95-second passive window,
bidirectional exact PONGs, H2/H7 failures and the limited H2 follow-up.

`tool/summarize_openhop_acceptance.py --directory <absolute-evidence-directory>`
consolidates every retained trial without contacting devices. It checks total
application attempts against the separately recorded authorization and keeps
earlier failures alongside latest results. `tool/revise_dev_candidate.py` checks
the original verified archive, complete member manifest, unchanged production
compilation inputs and tested native hashes, then copies the full bundle into
a distinct acceptance-metadata revision. It preserves the old archive, licenses,
source snapshot and hashes. It produces a new tar.gz/sidecar and checks that
final archive through fresh outside-checkout extraction, member checksums,
layout/modes, unchanged notices/native files, and version/help/missing-argument
invocations. It does not rebuild or imply new product/CI/hardware results.

The acceptance-metadata revision completed at `2026-11-10T20:54:23.032188Z`.
`archive-verification-rf-20261110T205422Z.json` records actual extraction of the
final archive to a fresh `/private/tmp` directory, 32 checksummed ordinary files,
27 unchanged notice/license files, full native modes/hashes, and four successful
no-device process checks (0/0/64/64 as planned). New archive SHA-256:
`600268d2df82591e2cc308a69f89701c96636f4ceec855575caaca2afaf47176`.
The original archive remains unchanged. See the
[revision paths and limits](releases/phase-1b-dev2.md#rf-acceptance-metadata-archive-actually-verified).
Final formatting checked 56 Dart files with zero changes.

### Authorized command-budget comparison on November 11, 2026

The explicit user approval was recorded before any new hardware operation:
B command 15 seconds, A 5 seconds, total ceiling 15. Product source inputs and
both native hashes were checked unchanged; an expired JWT was detected locally
and replaced via the existing repository-external 0600 reference. No credential
or authentication response entered repository files or reports.

H7 passed exact-PONG-gated SIGINT with actual A/B exits 130/0 and cleanup. H2
initially failed three initialization-only starts; after H7, another finite
startup used its still-unused single-send allocation, retaining one further
initialization failure before a pass. The comparison added three application
attempts, cumulative 14/15. Every latest basic case now has a passing record,
with original failures preserved. See [all facts and limits](hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026).

Only the Python summary helper and current documentation changed during this
follow-up. Its explicit trial inventory includes the additional H2 startup, and
it checks cumulative and per-case comparison allocations (H2 <=1, H7 <=3).
The prior summary was retained before regeneration. No Dart source, production
compilation input, dependency or lockfile changed, so the recorded 180 core,
88 later CLI and 69 original smoke results were not needlessly rerun or relabeled
as new results. Python syntax, actual summary/allocation facts, current text/links,
and final archive extraction are verified for this revision.

The November 11 comparison archive passed actual final-tar.gz extraction at
`2026-11-11T05:23:11.901971Z`; the new external record is
`archive-verification-rf-20261111T052311Z.json`. Its archive SHA-256 is
`ac278ca7b2cde0fad2f618c8efe603d2ea89b2fc804961599e28a0de9d8093d7`.
It verified 32 ordinary-file checksums, 27 original notice/license files, exact
layout, native 0755 modes and original tested hashes, plus four extracted
no-device checks with expected exits 0/0/64/64. Both prior archives were checked
unchanged. See the [exact comparison artifact paths](releases/phase-1b-dev2.md#comparison-archive-actually-extracted-on-november-11).

### Development-tool review fixes on November 11, 2026

Three review findings were reproduced and fixed without changing product/core
code or USB defaults. Raw listen failures now retain reception counts and never
project a consuming-read failure as an RF send. WS close still awaits socket
receive EOF and the owned subscription, while closing public frame delivery
without waiting for an absent/paused consumer. The finite Python runner checks
the actual A/B operations and B config before process startup, requires explicit
responder limits (H3/H4/H5=1, H7=2), rejects duplicate/unsupported options and
non-Direct routes, and derives its allocation from those checked commands.
Its send counter also excludes legacy read-only results with a misleading send
field. This is a development matrix validator, not a new product transport API.

All three new Dart regressions first failed against the old behavior. After the
fixes, the full CLI suite passed **91**, six new Python tests passed, format
checked **56 files with zero changes**, and fatal-info analysis found no issues.
The test processes ran serially. Python tests are integrated into the existing
CI job; remote CI was not run. Logs, exact argv, UTC times, exit codes and source
hashes are retained in:

```text
build/phase-1b9/20261110T193252Z/review-fixes-20261111T054035Z/
  software-followup.json
  checks.json
  format.log
  analyze.log
  cli-tests.log
  python-plan-tests.log
  retained-evidence-verification.json
```

Four actual retained plans passed the stronger offline validation. Recounting
every recorded invocation with the fixed counter still yields **14** application
attempts, and the RF summary's bytes remain unchanged. All three prior archives
were checked against their recorded hashes and preserved. No device/deployment
connection, queue consumption or RF send occurred during this follow-up.
Production compilation inputs and native hashes remain those of the original
fresh builds; core tests/native builds/smoke were not unnecessarily repeated.

`tool/revise_dev_candidate.py` accepts `--software-followup <absolute-record>`
for a metadata revision. It verifies that record's passing checks, build ID and
source hashes before copying the bundle, so the new archive can distinguish
91/6 local software results from the earlier 88-test source snapshot. It does
not relabel the fixed helper source as the source used for previous RF trials;
those retain their original execution-plan hashes. The complete product bundle
still excludes source-only tools and tests.

### Settlement and native-evidence fixes on November 11, 2026

A second source-only review identified two remaining Python defects. The runner
now settles every already-started finite peer in a finally path, including after
cleanup failure or unexpected orchestration errors. It records the failed or
blocked case before STOPPED, retaining all per-process observations and known
application sends. A timed-out process remains pending with its PID, not falsely
closed. Missing sender facts produce a null actual total, a known lower bound
and a reserved upper bound; they are never silently counted as zero. No new
connection, resend, signal or forced kill is added. A post-spawn metadata-write
failure also returns the process to its owner before raising the stop condition.

The summary now binds native hashes to every retained execution-plan capture,
checks agreement across trials, and verifies current candidate bytes against
those captures. Changed bytes, missing/mixed captures and unrepresented legacy
STOPPED trials reject summary generation before replacing an existing report.
Pending accounting remains BLOCKED; failed cleanup cannot retain a cached PASS.
`--candidate` selects the bundle to verify and `--output` allows a separate
validated report while preserving the historical summary. No candidate is run.

The complete Python suite passed **17 tests** locally. No Dart source changed;
the preceding 91-test CLI gate and its checked source hashes remain earlier
software evidence, not a new run. Core/native bundles/smoke were not repeated.
No remote CI was triggered. New logs, source hashes and validation records:

```text
build/phase-1b9/20261110T193252Z/review-evidence-fixes-20261111T061833Z/
  software-followup.json
  python-tests-final.log
  bound-summary.log
  rf-summary-verified.json
  retained-evidence-verification.json
```

Actual retained data validated against **five** captured native execution plans.
The independent output retains 11 trials, four failed trials and exactly **14/15**
application sends; latest case outcomes/exits/RTTs are unchanged. The original
RF summary and all four previous archives were checked unchanged. The new
summary adds provenance and accounting fields without rewriting the old device
records. This verification neither reconnects hardware nor retrospectively
claims a live run of the later fixed source.

### Interrupted-run/configuration review fixes on November 11, 2026

Three Python-only defects were reproduced and fixed. Summary generation now
reconciles every per-case process metadata file even when results.json already
exists: an unrepresented later process/retry or conflicting identity/final facts
rejects generation before output is overwritten. Captured process-file hashes
are included in the native-evidence provenance. Unknown extra invocations are
never silently treated as zero sends.

The runner parses the receive channel before launching processes, using the
same ASCII decimal (including leading zeros) and 0x/0X uint8 syntax as the Dart
CLI. Case evaluation uses that validated number and cannot fail on Python's
base-zero handling after a hardware case has already finished.

The plan generator accepts the flat JSON emitted by openhop_idle_probe.dart and
retains support for legacy execution wrappers. Both readers share a validator
for successful exit/status, actual cleanup and a sufficient passive window;
nonpassive activity and contradictory initialization facts reject. An omitted
idleTimeoutSeconds is preserved as null in generated configs when an observed
window is supplied. No wrapper has to be invented around probe stdout.

The complete local gate passed 25 Python tests, 91 CLI tests (all loopback cases
executed), 56-file format with zero changes and fatal-info analysis. Core code,
production compilation inputs and native files were unchanged; no additional
native bundles/core tests were required. No new hardware/API connection, queue
consumption, signal or RF application send occurred. Logs and source hashes:

```text
build/phase-1b9/20261110T193252Z/review-config-fixes-20261111T065713Z/
  software-followup.json
  checks.json
  regressions-before.log
  python-tests.log
  cli-tests.log
  format.log
  analyze.log
  bound-summary.log
  flat-probe-plan.log
  rf-summary-verified.json
  retained-evidence-verification.json
```

The actual retained data reconciled **23 process metadata files** against all
11 trial records and five native execution captures. Four failed trials, latest
case exits/RTTs/outcomes and 14/15 application sends are unchanged. The saved
flat stdout from the actual earlier 95-second probe successfully generated an
offline plan; that plan was not executed. The original RF summary and all five
existing product archives were checked unchanged. Product packages exclude these
development scripts, so the existing archive remains its original dated snapshot;
this later software record is separate and does not imply new RF acceptance.

### Ledger, raw-session and archive-provenance fixes on November 11, 2026

Three further review defects were reproduced and corrected. The summary scans
the complete evidence tree and rejects execution/process files outside its
registered trial directories before publishing totals. Unknown output names
cannot silently drop an unfinished sender or restore sending allowance. The
existing registered process reconciliation and native-capture checks remain.

The development raw runner reconciles recorded non-cancellation session failure
after cleanup. A synchronous OK-then-transport-error reproduction previously
exited 0; it now exits 69 with session_failure, while preserving the completed
local write, OK and acceptance facts. Diagnostic task terminal gates are unchanged.
No production USB/session/core implementation was modified.

The archive reviser reads the original tar.gz once, verifies its external hash,
then validates and copies only a fresh extraction. Original member checksums,
complete layout, native hashes against testedNativeHashesVerified and executable
permission must agree. Tests regenerate a sibling directory with different
native bytes and matching regenerated manifests: original archived bytes still
win, and incompatible RF evidence rejects before native execution. Extraction
rejects links and unsafe paths before using the SDK tar data filter.
Source-extraction cleanup is checked. The follow-up initially ran under the
older PATH-selected Python 3.9; the later Python 3.15 record supersedes that
interpreter choice for future work.

The sequential local follow-up passed **31 Python tests, all 92 CLI tests**,
fatal-info analysis and a 56-file zero-change format check. Loopback socket tests
ran successfully. Core/product compilation inputs and both native hashes remain
unchanged; the prior core/native/smoke records retain their original dates. No new
hardware/API connection, consuming read, signal or RF send occurred. Logs, hashes
and independent retained-evidence checks are in:

```text
build/phase-1b9/20261110T193252Z/review-ledger-provenance-20261111T092140Z/
  software-followup.json
  checks.json
  python-regressions-before.log
  raw-regression-before.log
  raw-regression-after.log
  python-tests.log
  cli-tests.log
  format.log
  analyze.log
  rf-summary-verified.json
  original-archive-source-verification.json
  retained-evidence-verification.json
  archive-revision.log
```

Actual retained evidence still reconciles 23 process files, five native execution
captures, 11 trials, four failed trials and **14/15** application sends. Latest
outcomes/exits/RTTs, original RF-summary bytes and all five prior archives are
unchanged. The new complete metadata archive was verified from a fresh final
extraction; see the [release record](releases/phase-1b-dev2.md#ledger-session-and-original-archive-review-revision).
Earlier RF trials retain their actual earlier source hashes.

### Python 3.15 toolchain follow-up on November 11, 2026

At the user's request, subsequent local Python work uses the latest installed
stable version at or above 3.15. The verified entry `/opt/homebrew/bin/python3`
reported 3.15.2. Adding only `/opt/homebrew/opt/python@3.15/bin` before `/usr/bin`
keeps `/usr/bin/clang` selected and avoids the older system Python. No interpreter
was installed/upgraded and no global setting changed. The project agent guidance,
README and test instructions now preserve this selection policy; historical
Python 3.9 records remain historical.

The full sequential follow-up reran with that PATH and passed **31 Python tests,
92 CLI tests**, fatal-info analysis, 56-file zero-change formatting and the
retained-evidence summary. The actual Python path/full version is saved both in
python-toolchain.json and software-followup.json. Logs and hashes:

```text
build/phase-1b9/20261110T193252Z/review-python315-20261111T092825Z/
  python-toolchain.json
  software-followup.json
  checks.json
  original-archive-source-verification.json
  retained-evidence-verification.json
  rf-summary-verified.json
  archive-revision.log
  final-verification.json
```

The archive reviser also ran under Python 3.15.2, using the normal tar data
filter after its explicit member validation. It copied from the verified
original archive and actually extracted the final new archive outside the
checkout. All 32 file checksums, exact layout, native hashes/0755 modes, 27
unchanged notices/licenses and four no-device exits 0/0/64/64 passed. The six
earlier archives and original RF-summary bytes were preserved. Native/product
inputs and historical 14/15 application sends remain unchanged; no new hardware
run occurred. See the [new archive record](releases/phase-1b-dev2.md#python-315-verified-archive-follow-up).

### Channel-audit final-query failure fix on November 11, 2026

A source-only audit race was reproduced in A-only and A-then-B runs. After the
last 0x12 reply completed its query, an immediately observed transport error
could remain queued in the adapter's asynchronous frame stream. The query
continuation could close a still-ready session before it consumed that error,
yielding a false PASS and allowing B to open.

The adapter now retains its first non-cancellation failure independently of the
pending query and forwarded session event. Further queries reject that failure;
the runner checks it after each reply and again after actual cleanup before
declaring endpoint success. Completed channel summaries remain available, but
the endpoint/audit fails with exit 69 and B is not opened. Normal close does not
create a failure, existing cancellation reasons remain, and no raw error/key is
retained in the report. No production session/USB/core behavior changed.

Three new tests cover the same-turn final-reply/error in A-only and A-then-B
modes, plus a transport error during final cleanup held behind an explicit
Completer. They verify actual cleanup waiting, no B connection/comparison,
retained read summaries, private-frame wiping, no extra command/queue/RF send,
and sanitized reporting. The sequential local gate used Python 3.15.2 and passed
**95 CLI tests**, including all loopback cases, **31 Python tests**, fatal-info
analysis and 56-file zero-change formatting. Records:

```text
build/phase-1b9/20261110T193252Z/review-channel-boundary-20261111T094435Z/
  regressions-before.log
  channel-tests-after.log
  python-toolchain.json
  software-followup.json
  checks.json
  cli-tests.log
  python-tests.log
  rf-summary-verified.json
  final-verification.json
```

The source-only audit is excluded from the product bundle. Existing native
files, product inputs, archives and original RF records remain unchanged; the
current archive retains its earlier dated software snapshot. The separate
summary still reconciles 23 process files, five native captures, 11 trials,
four failed trials and 14/15 application sends. No real USB/openHop connection,
queue read, signal or RF send occurred. The corrected audit was tested offline
only; historical channel/LoRa observations are not relabeled as a run of it.

### Protocol-input and evaluation-accounting fixes on November 11, 2026

Two subsequent review defects were reproduced offline. The channel adapter
previously retained stream errors but could lose a malformed known Companion
frame behind the same final-query continuation. Both synchronous and asynchronous
underlying streams produced PASS after a final channel reply followed by [0x05].
The adapter now uses the existing Companion decoder at receipt, before forwarding
valid frames or discarding input during cleanup. Protocol faults are retained
as protocolFailed and reconciled by the existing endpoint failure gate. Private
channel lengths are also checked before wiping during cleanup. No protocol
decoder or production session/USB/core implementation was changed.

The finite runner now validates every evaluation metadata field used after
execution: contentBytes must be an integer in 0..165 and expected A/B exits must
be explicit and match each case, including null B for H6. Missing values, booleans
and invalid ranges/exits reject before output creation or process startup.
Unexpected evaluator exceptions after settlement are recorded separately as
evaluationFailure; invocation records and completed send counts are persisted
in results/STOPPED before stopping. Raw exception messages are omitted, and no
new signal, retry, force-kill or sending allowance is introduced.

The full sequential local gate used Python 3.15.2 and passed **97 CLI tests**
(all loopback cases executed), **34 Python tests**, fatal-info analysis and a
56-file zero-change format check. Two added Dart cases cover malformed final
input with both stream delivery modes. Three added Python groups cover missing
metadata in validation/execution modes, invalid types/ranges/exits, and an
evaluator error after a simulated completed H2 send. That last case retains
both endpoint records, exactly one send and STOPPED. Logs and hashes:

```text
build/phase-1b9/20261110T193252Z/review-protocol-evaluation-20261111T100144Z/
  dart-regressions-before.log
  python-regressions-before.log
  channel-tests-after.log
  python-tests-after.log
  python-toolchain.json
  software-followup.json
  checks.json
  cli-tests.log
  python-tests.log
  rf-summary-verified.json
  final-verification.json
```

No hardware/API connection, consuming read, signal or RF send occurred. Product
compilation inputs, native hashes, seven existing archives and original RF
records remain unchanged. The separately checked summary still reconciles
23 process files, five native captures, 11 trials, four failed trials and 14/15
application sends. Current tool source was tested offline only. The product
archive remains its earlier dated snapshot; no product rebuild or repackaging
is inferred from this source-only follow-up.

### Content, invocation-ledger and interpreter fixes on November 11, 2026

Three review findings were corrected in Python development tooling. Plan byte
counts now match the actual initiating A argv or B config content option.
Exact even-length ASCII hex and UTF-8 text use their actual byte counts; a
missing/ambiguous source or mismatch rejects before execution. The fixed Direct
H5 requires 131 bytes even if both contentBytes and the command are shortened.
Validated counts are captured in the plan. Summary generation independently
checks H5 against retained A invocation argv and its explicit Direct/empty route;
current mutable configuration is not substituted for historical command evidence.

Case counters are checked against a fresh calculation over every retained
invocation, reusing the runner's accounting and fixed case allocations. Completed
sends, responder attempts, initialization-only failures and read-only legacy
reports retain their separate meanings. Unknown send facts retain null actual
counts and reserved per-invocation bounds. Stale actual/known/upper/knownness
fields reject before replacing a summary; they cannot restore sending allowance.

All three Python subprocess invocations in the plan tests now use sys.executable.
The full **41-test Python suite** passed under Python 3.15.2 with the documented
Apple-compiler-first PATH, where an independent python3 lookup selects
/usr/bin/python3. Instrumentation observed **35 Python child invocations**, all
using the same resolved Homebrew 3.15.2 executable as the parent. No system Python
child was started. Persistent agent guidance now also requires this selection.

Seven new regression groups cover all A/B initiating content roles, a shortened
H5 with edited metadata, UTF-8 byte counts/exact hex, contradictory cached totals,
unknown sends disguised as zero, repeated responders/legacy read-only reports,
and retained H5 arguments. Records and source hashes:

```text
build/phase-1b9/20261110T193252Z/review-content-ledger-20261111T102001Z/
  regressions-before.log
  python-tests-after.log
  python-tests.log
  python-toolchain.json
  python-child-interpreters.json
  software-followup.json
  checks.json
  rf-summary-verified.json
  bound-summary.log
  final-verification.json
```

The new summary verifies the actual 131-byte H5 initiator and recomputes 14/15
sends from 23 process files and 11 trials in five captured executions. Four failed
trials and latest outcomes/exits/RTTs remain unchanged. Original RF records and
seven existing archives are preserved. Product/Dart/core/native inputs did not
change; the prior 97-CLI-test/format/analysis gate remains earlier dated evidence
and was not rerun for these Python-only changes. No new hardware/API access,
queue read, signal, RF send, native build or archive revision occurred.

### Runner cancellation, exits and empty-content fixes on November 11, 2026

Three runner defects were reproduced and fixed. A SIGINT while finally was
waiting for finite peers could escape before the other peer and case accounting
were saved. A cleanly settled case with failed acceptance could leave the runner
exit at zero. H4 accepted a one-byte initiating content option if contentBytes
was changed with it, omitting the matrix's empty-content boundary.

The finite execution loop is now a separate helper under a temporary deferred
SIGINT handler. It latches requests through orchestration, settlement and evidence
persistence, refuses new peer starts after cancellation, and restores the prior
handler on exit. A programmatically interrupted wait resumes observing the same
peer under the unchanged original deadline, then observes later peers. Interrupts
are separate from actual cleanup failures. The interrupted result retains all
invocations and application-send facts, writes results/STOPPED before output,
and exits 130 without new child signals, retries, connections, forced termination
or increased time budgets. Unknown cleanup/send facts remain pending/BLOCKED.

Ordinary cleanly settled acceptance failures may still allow later independent
authorized cases to run, but the final aggregate exit is 69 if any selected case
failed or remained blocked. A later pass cannot reset it to zero. Expected peer
69/130 exits that satisfy H6/H7 still count as passing acceptance, distinct from
driver cancellation. H4 actual content and metadata must now be zero before
execution, and its evaluator also enforces that boundary.

The Python-only follow-up passes **46 tests** using 3.15.2. Five new groups cover
H4 plan/evaluation boundaries, KeyboardInterrupt while settling the receiver,
two real SIGINT deliveries in the same synthetic wait, previous-handler
restoration, a cleanly settled failed single case, and a later pass after an
earlier failure. Both peer records and the one completed H2 send persist before
exit 130; no new peer starts. Instrumentation records 40 Python children, all
using the selected Homebrew 3.15.2 interpreter despite /usr/bin/python3 on the
compiler-first PATH. These tests use mocked peers and self-delivered signals,
not hardware or a live deployment. Logs and source hashes:

```text
build/phase-1b9/20261110T193252Z/review-cancellation-exits-20261111T103839Z/
  regressions-before.log
  python-tests-after.log
  python-tests.log
  python-toolchain.json
  python-child-interpreters.json
  software-followup.json
  checks.json
  rf-summary-verified.json
  final-verification.json
```

The original 11 hardware trials, four failed trials, 23 process records, five
native captures and 14/15 application attempts remain unchanged. Product/Dart/
core/native inputs and seven archives are unchanged; their earlier gates retain
their original dates. This follow-up performs no hardware/API connection, shared
queue read, RF send, native build or archive revision.

## Production storage and migration baseline (1C.3)

This implementation starts from clean local `master`
`40d5bd47f9a119db0652f291fbe7b5ceea214a80`. GitHub reported PR #19 merged at
2026-11-11 20:09:35 UTC into that commit; prerequisite
`c207dfb6acd8c5ec8c101a9eea0d32e72008d3c1` is an ancestor. The initial `gh` request
was blocked by sandbox networking; the authorized network-enabled read confirmed
the merged state. No prerequisite PR was merged by this step, and no history or
preexisting user changes were rewritten.

The [package README](../packages/meshchan_core/README.md) describes the public
`CoreStorage.open(dataDirectory: Directory(...))` lifecycle, stable file names,
lock/marker distinction, connection responsibility, error/sidecar policy, and
schema/codec choices. The host must supply the directory; there is no cwd/default
platform-directory lookup or CLI parsing. The production native connection lives
on the opening isolate and is created after ownership and preflight. Other
isolates may call the same open entry and compete through OS flock; they do not
share handles. No SQL worker is started for a rejected contender.

The small native adapter uses libc `open`/`flock`/`close`, errno, and verified stat
prefixes on macOS/Linux arm64/x64. Dart's process-associated
[RandomAccessFile.lock](https://api.dart.dev/dart-io/RandomAccessFile/lock.html)
was deliberately not used for directory ownership. See
[Apple flock](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html),
[Linux flock](https://man7.org/linux/man-pages/man2/flock.2.html), and
[Dart VarArgs](https://api.dart.dev/dart-ffi/VarArgs-class.html).
Darwin layout/flags were checked in the installed macOS SDK `sys/stat.h` and
`sys/fcntl.h`; Linux prefixes were checked against the upstream
[x64](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/stat.h)
and [asm-generic arm64](https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/stat.h)
headers. The adapter implements ABI calls, without copying upstream implementation
code. Network filesystems, hostile inode/directory replacement, and noncooperating
external SQLite clients are outside the boundary. Application code never removes
the dedicated ownership resource as stale cleanup.

`ffi ^2.2.0` and `path ^1.9.1` are now direct dependencies for native allocation/
UTF-8 and safe path composition. Both were already transitively locked at those
versions; they are now declared by the member before direct imports. **No root
lockfile version/content change** was needed. Their installed LICENSE texts are BSD-3-Clause. Drift
2.35.4, sqlite3 3.9.1, drift_dev 2.35.3, build_runner 2.17.1, and test 1.33.0
remain unchanged. There is no `meshcore_link` dependency, extra ORM, native lock
package, SDK installation, or package version bump.

### Generation and future structural changes

From the repository root, get locked dependencies, then run the two distinct
production-generation checks from the member:

```bash
dart pub get --enforce-lockfile
(cd packages/meshchan_core && dart run build_runner build)
(cd packages/meshchan_core && dart run tool/check_schema.dart)
git diff --exit-code -- packages/meshchan_core/lib/src/storage/database.g.dart \
  packages/meshchan_core/test/support/dependency_probe_database.g.dart \
  packages/meshchan_core/drift_schemas packages/meshchan_core/test/storage/generated
```

`build_runner` supplies the production and empty probe `.g.dart` files.
`check_schema.dart` separately exports the current production definition into a
temporary directory, compares the saved JSON snapshot byte-for-byte, generates
verification helpers there, and compares their complete file set/bytes. It
cannot silently replace a committed snapshot. CI additionally requires the
artifacts to be tracked. The real schema is
`lib/src/storage/schema.drift`, database entry `lib/src/storage/database.dart`,
snapshot `drift_schemas/drift_schema_v1.json`, helpers
`test/storage/generated/{schema.dart,schema_v1.dart}`. The probe is not a migration
history entry. `generate_manager: false` still prevents its unused manager field.

The initial snapshot/helper commands (run from `packages/meshchan_core`) were:

```bash
dart run drift_dev schema dump lib/src/storage/database.dart drift_schemas/drift_schema_v1.json
dart run drift_dev schema generate drift_schemas test/storage/generated
```

The production constant equals Drift's schemaVersion 1. Initial creation runs
DDL and user_version in one short transaction; failure after the first real
CREATE rolls both back. A future real change increments this constant, implements
transactional upgrade steps in `CoreDatabase.migration`, adds a new versioned
snapshot, regenerates helpers, and validates old records. Existing released
snapshots must remain unchanged. No production v2 was invented for tests.
Diagnostic summary format, CLI output version, app version, and wire version
remain separate. Newer summary rows fail explicitly as `storage_read_failed`;
newer database structures fail as `unsupported_database_version` before Drift.

### Handoff to 1C.4

This is the preserved 1C.3 handoff. Its draft work is now implemented in
[1C.4](#persistent-draft-repository-1c4); profiles/settings and core resolution are now implemented in
[1C.5](#profiles-settings-and-typed-resolution-1c5). Diagnostic services remain pending.

Use `storage/storage.dart`'s owned `StorageHandle.useDatabase` for the complete
Future of each short transaction, `database.dart`/`schema.drift` for SQL, and
`codec.dart` for exact typed row conversions. Do not retain a database from the
callback or create another production connection. For writes, select
`failureCode: CoreErrorCode.storageWriteFailed`; reads default to the safe read
category. Typed core errors and recognized corruption retain priority. Table
readers check raw SQLite types before Drift's string/integer coercions, including
when a table is aliased. Close drains admitted work,
then awaits the executor, then releases the real lock/reservation. Unconfirmed
close remains owned/quarantined and reports `storage_write_failed`; an open
failure keeps its first category plus `cleanupUnconfirmed` if necessary.

At the 1C.3 handoff, draft ID generation, commit-error mapping, CRUD,
revision/no-op behavior, and bounded queries were still pending, as were
profile/settings implementations. Those services are now complete in 1C.4–1C.5;
the FK is used by the profile deletion service.
Communication mapping, recording/recovery, history pruning/export, CLI directory
selection and flags, and SQLite product AOT distribution remain later work.
No database open performs diagnostic recovery or retention.

### 1C.3 local validation on November 11, 2026

The final local environment was macOS **27.2.1 (26B131), arm64**, using
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` **3.13.7 stable**.
Installed Flutter metadata reports **3.47.9 stable**, revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`; the Flutter wrapper's initial version
attempt was denied cache-stamp writes by the sandbox, so subsequent commands used
the documented direct Dart entry. No SDK/cache/upstream source was modified to
work around it. Native commands selected `/usr/bin/clang`, Apple Clang **21.0.0**
(`clang-2100.4.1.1`). Python entry `/opt/homebrew/bin/python3` reported **3.15.2**,
with `sys.executable` `/opt/homebrew/opt/python@3.15/bin/python3.15`. No global PATH,
interpreter, SDK, channel, or package version was changed.

Observed final checks:

| Check | Result |
| --- | --- |
| Root `dart pub get --enforce-lockfile` | Passed; root lockfile unchanged, no member lockfiles. |
| Member build_runner | Production and probe generated successfully; a repeat retained identical SHA-256 hashes for both `.g.dart` files, the snapshot, and both used schema helpers. |
| Separate schema export/helper guard | Passed. A temporary unversioned table-default change was deliberately rejected; the source was restored byte-for-byte and the normal check passed again. The snapshot itself was not rewritten by the guard. |
| Workspace formatting / fatal-info analysis | 86 Dart files, zero format changes; no analyzer issues. |
| Complete meshchan_core suite | **43 passed**, including the original 12 value/probe tests and 31 new file/schema/ownership/error cases. |
| Complete meshcore_link suite | **180 passed**. |
| Complete meshctl suite | **97 passed** after enabling local loopback sockets. The initial sandbox run failed its 127.0.0.1 server binds with Operation not permitted; that failed log is retained separately. No hardware or external peer was used. |
| Python development-tool suite | **46 passed** under the explicitly selected Python 3.15.2. |
| Existing native build gates | Three fresh bundles passed sequentially: product CLI, serial observation usage fixture, and synthetic datagram acceptance fixture. |
| Shared source/AOT smoke | **69 passed on macOS**, including broken pipe, complete-bundle relocation, and five synthetic datagram scenarios in source/AOT. |
| Final patch / new-file review | Tracked patch whitespace passed; all 18 new files, including production generated code, snapshot, helpers and tests, were enumerated and checked for whitespace/conflict markers. No temporary database/native cache was added. |

The process tests observed macOS same-isolate and different-isolate exclusion,
independent-process contention after losing attempts, normal/abnormal exit,
marker deletion/staleness, and busy ownership while a real executor close was
blocked or failed. Path tests included relative, absolute, dot/parent, directory
symlink and case aliases when the actual filesystem recognized them; database,
sidecar and lock symlinks/hard links were rejected. The real hot-journal fixture
checks its journal magic; the WAL fixture checks that main-header user_version
is still zero while the committed future version is correctly rejected from WAL.
Rejected main/sidecar bytes and existence were unchanged.

Early checks exposed and corrected the Darwin arm64 variadic `open` binding
(mode must be passed through Dart `VarArgs`), Drift's default raw-row coercions,
and the SQL LIKE underscore wildcard in internal-object recognition. Final tests
cover restrictive lock-file mode, BLOB/text and fractional-integer damage before
coercion (including aliases), and a nonreserved `sqliteX...` user table at version
zero. These are final passing fixes, not exceptions to the contract.

Current logs and generated hashes are retained locally under:

```text
build/phase-1c3/local-20261111/
  pub-get.log
  python-toolchain.log
  codegen-reproducibility.log
  generated-before.sha256
  generated-after.sha256
  schema-negative-control.log
  schema-check-final.log
  format.log
  analyze.log
  meshchan-core-tests-final.log
  meshcore-link-tests.log
  meshctl-tests.log
  meshctl-tests-network-enabled.log
  python-tests.log
  build-meshctl.log
  build-observation.log
  build-datagram-acceptance.log
  smoke.log
```

The CI workflow now verifies production/probe generation, saved schema/helper
consistency, tracked artifacts and the complete file/ownership suite while
preserving previous regressions/native gates. At the time of this local
validation, the changes were uncommitted/unpushed and no remote CI result had
been observed. Linux
locking/path/journal tests are configured for CI but were not run on this Mac.
Existing CLI bundles have no business SQLite wiring: their passing native smoke
is not SQLite product AOT packaging, a real historical upgrade, diagnostic
recovery, hardware/RF acceptance, or completion of any later 1C step.

## Persistent draft repository (1C.4)

Implementation started from clean `master` at
`950b59f43a460c9257755c10b2100dd1af649c8d`, containing merged PR #20 and its 1C.3
storage prerequisites. No checkout/reset, history rewrite, or dependency/version
change was needed. Production schema 1, the saved snapshot, generated helpers,
root lockfile, ownership/preflight policy, and connection close ordering remain
unchanged.

The public `CoreStorage.drafts` getter returns one lifecycle-bound
`DraftRepository`. The [package example](../packages/meshchan_core/README.md#persistent-drafts-1c4)
demonstrates host-supplied directory, create/read/update/list/delete, returned
revisions, caller conflict handling, and awaited close in `finally`. No CLI or
platform directory selection is introduced. This section records the draft
implementation; current profile/settings/resolver behavior is described below.

`lib/src/repositories/draft_repository.dart` contains the concrete implementation.
Every call has one outer `StorageHandle.useDatabase` callback. Short mutations
read/compare/write inside the same Drift transaction, and the Future includes
actual commit; private reads take the admitted database instead of reentering
admission. This lets close reject new work while draining accepted operations.
There is no connection, cache, queue, or close method owned by the repository.
Strict `storedDrafts` readers and `encodeDraft`/`decodeDraft` remain the storage
boundary, including during list decoding. Read/list select the read fallback;
create/update/delete explicitly select the write fallback, preserving business
errors, corruption, and existing unconfirmed-cleanup facts.

Production IDs use `Random.secure()`: 16 bytes, each padded to two lowercase hex
digits. `INSERT ... ON CONFLICT(id) DO NOTHING RETURNING ...` checks actual
insertion; only that conflict retries, at most eight total attempts in the same
transaction. No exception-code heuristic, pre-insert lookup, replacement, or
broad ignore is used. Other constraints, I/O, or commit failures exit immediately.
Clock/ID failures are converted to a safe write error before the generic storage
boundary could mistake a source's TypeError/FormatException for row corruption.
Internal `StorageHooks.draftId` and `clock` supply deterministic test inputs;
these hooks and the implementation are not exported by the public package.

Creation reads the clock once, converts to UTC, preserves microseconds, and sets
revision 1 with equal creation/update times. Changed updates preserve ID and
createdAt, compare revisions before exact title/body no-op detection, and add
one revision only after checking the signed 64-bit maximum. A changed save at
9223372036854775807 fails with `storage_write_failed` because another version
cannot be generated; no-op/read/delete still work. Equal/backward clock readings
are not clamped. UTF-16 surrogate validation at the input boundary prevents
lossy UTF-8 replacement. Valid Unicode, explicit U+FFFD, empty text, whitespace,
and mixed newlines are preserved; there is no radio-sized body cap or cached
byte count.

Lists use `drafts_updated` order `updated_at_us DESC, id DESC` with the bound
row-value comparison `(updated_at_us, id) < (?, ?)` and SQL limit size + 1. This
preserves the strict two-key cursor semantics while allowing a direct composite
index seek instead of rescanning earlier entries or sorting an OR result. The
next cursor is the last returned item only when the probe proves more rows exist. Deleted
cursor rows remain valid sort values. Separate calls share no snapshot. Even
the probe row is strictly decoded before returning a page.

### Handoff to 1C.5

This is the 1C.4 seam, now implemented by
[1C.5](#profiles-settings-and-typed-resolution-1c5). Profile/settings repositories
reuse `StorageHandle.useDatabase`, strict table readers/codecs, short
transactions, and the actual executor interceptor/Completer tests. The small ID
and protected clock helpers now live in internal `repositories/write_support.dart`;
Unicode checking is shared through `validation.dart`. Draft semantics remain
unchanged, with a separate internal profile ID source. Core profile selection,
per-field merge, and final effective-parameter validation are complete in 1C.5.
CLI parsing/presence/explicit-port checks and execution wiring belong to 1C.8.
The earlier description of merging as general later work did not move core
resolution beyond 1C.5. No second connection or owner is introduced.

### 1C.4 local validation on November 11, 2026

Actual environment: macOS **27.2.1 (26B131), arm64**;
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` **3.13.7 stable**.
The installed Flutter metadata reports **3.47.9 stable**, framework revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`. Native commands used a process-local
Apple-compiler-first PATH and `/usr/bin/clang` **21.0.0** (`clang-2100.4.1.1`),
with the installed Xcode/macOS SDK. Python was explicitly verified before project
execution: `/opt/homebrew/bin/python3` **3.15.2**, resolving `sys.executable` to
`/opt/homebrew/opt/python@3.15/bin/python3.15`. No SDK, interpreter, channel,
global configuration, dependency, or package version was installed or changed.

| Check | Observed result |
| --- | --- |
| Root `dart pub get --enforce-lockfile` | Passed; single root lockfile unchanged. |
| Member `dart run build_runner build` | Passed; production/probe generated sources unchanged. |
| Member `dart run tool/check_schema.dart` | Passed; formal schema 1, saved snapshot, and generated helper set/bytes match. |
| Root `dart format --output=none --set-exit-if-changed .` | Passed; 89 Dart files, zero changes. |
| Root `dart analyze --fatal-infos` | Passed; no issues. |
| New repository tests | **33 passed**, including public-only CRUD and both failure stages for create/update/delete. |
| Full `meshchan_core` | **76 passed**; all prior 43 value/probe/storage/preflight/ownership cases retained, with closeUnconfirmed draft rejection added to the existing process case. |
| Full `meshcore_link` | **180 passed**. |
| Full `meshctl` | **97 passed** with local loopback permitted. The initial sandbox attempt failed its 127.0.0.1 server binds with Operation not permitted; that separate failed log is retained. No device or external peer was used. |
| Python development tools | **46 passed** under the verified Python 3.15.2. |
| Native build gates | Three fresh bundles passed sequentially: product CLI, serial observation fixture, and development datagram acceptance fixture. |
| Shared source/AOT smoke | **69 passed on macOS**, including native assets, broken pipe, complete-bundle relocation, and five synthetic scenarios in both source and AOT. |
| Final diff/artifact review | Patch whitespace, new-file whitespace, conflict-marker scan, generated/schema/lockfile equality, and changed-file review passed. |
| Remote CI / Linux | **NOT_RUN** for this local change; no push/dispatch or remote result was observed. The existing CI full-suite command discovers the new tests without a workflow change. |

Logs, generated-artifact hashes, actual toolchain output, and fresh bundles are
retained locally in ignored `build/phase-1c4/local-20261111/`:

```text
pub-get.log
codegen.log
schema-check.log
generated-diff.log
generated.sha256
format.log
analyze.log
draft-tests.log
meshchan-core-tests.log
meshcore-link-tests.log
meshctl-tests.log
meshctl-tests-network-enabled.log
python-tests.log
python-toolchain.json
toolchain.log
build-meshctl.log
build-observation.log
build-datagram-acceptance.log
smoke.log
final-review.log
```

The committed schema artifacts and root lockfile compare unchanged to the actual
starting HEAD. These repository tests exercise controlled SQLite transaction
failures and normal reopen durability, not arbitrary power-loss safety. The
current CLI still has no business SQLite wiring; passing its native bundles and
smoke does not establish SQLite product AOT distribution. No hardware/RF check,
release/tag, 1C.5 implementation, or diagnostic business recovery was performed.

### 1C.4 pagination review follow-up on November 11, 2026

The review identified a real cursor-query planning defect. On the actual
SQLite **3.54.1**, a regression using the repository's generated SQL and bound
arguments reproduced `SCAN stored_drafts USING INDEX drafts_updated` at page
size 50. At size 2, the OR predicate instead produced `MULTI-INDEX OR` followed
by `USE TEMP B-TREE FOR ORDER BY`. Neither plan directly traversed the composite
index from the cursor in the required order; LIMIT alone did not bound the
preceding index work.

The continuation now uses `(updated_at_us, id) < (?, ?)` with generated column
expressions and Drift-bound integer/string variables. The small private
`_BeforeDraftCursor` expression supplies row-value syntax absent from the locked
Drift query builder. Strict table readers, the one-admission operation boundary,
ordering, page limit, and cursor semantics remain intact.

The new test explains the actual intercepted SELECT rather than a handwritten
copy. For sizes 2 and 50, with both a live and deleted cursor row, it requires
`SEARCH` through `drafts_updated` with the two-column range, rejects a table/index
scan and temporary sort, and checks returned records across a timestamp tie.
The test failed before the fix and passed afterward. No performance benchmark or
large stress fixture was added.

Follow-up validation used the installed
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` **3.13.7 stable** on
macOS arm64. The targeted query-plan regression passed, repository tests passed
**34/34**, the complete offline-core suite passed **77/77**, root formatting
reported **89 files, zero changes**, and root fatal-info analysis reported no
issues. The schema guard passed; schema 1, generated artifacts, root lockfile,
and dependency/version manifests remain unchanged. Existing communication/CLI,
Python, native bundle and smoke checks were not repeated for this confined
query/test/documentation fix; their preceding dated results remain above.
No remote CI result was observed.

The before-fix failing plan, after-fix result, complete tests, formatting,
analysis, schema guard, and final review logs are retained under ignored
`build/phase-1c4/pagination-review-20261111/`. This follow-up preserves all existing
uncommitted 1C.4 work and does not implement 1C.5.

## Profiles, settings, and typed resolution (1C.5)

Implementation started from clean `master` at
`4dd0a2a756a1457d644d376786dcbf2af4b3dcd2`, containing PRs #18–#21 and the
1C.4 cursor-query follow-up. No checkout/reset or history rewrite was used.

The [public API example](../packages/meshchan_core/README.md#profiles-settings-and-effective-parameters-1c5)
shows host directory → open → complete profile save → default setting → typed
invocation overrides/content → resolve → awaited close in finally. New entry
points are `CoreStorage.profiles`, `.settings`, and `.resolveParameters(request)`.
`EffectiveParameterRequest` has send/listen/ping/respond subtypes, each with its
own override vocabulary. Results contain the selected optional profile ID,
complete immutable typed parameters, and invocation bytes where applicable.
Port hints do not authorize execution, and results are not safe diagnostic
snapshots. The example performs no device I/O.

Implementation files relative to the core package:

| File | Responsibility |
| --- | --- |
| `lib/src/models/effective_parameters.dart` | Operation-specific requests/overrides and immutable result; nullable override fields preserve absence, and `DataTypeOverride(null)` explicitly clears a listen filter. Paths and invocation bytes are copied synchronously. |
| `lib/src/profile_validation.dart` | Full ranges/cross-field checks and public link helper calls; no device/session/task construction. Checks bytes before Uint8List conversion. |
| `lib/src/repositories/profile_repository.dart` | Complete profile read/create/replace/no-op/delete and bounded two-key cursor list; strict decoded semantics include probe rows. |
| `lib/src/repositories/settings_repository.dart` | Default read without insertion, atomic full save/reference checks, and explicit reset. |
| `lib/src/parameter_resolver.dart` | Consistent selection snapshot, field-by-field merge and full validation/content capacity; no writes, IDs, clock, drafts, history lookup, or device access. |
| `lib/src/repositories/write_support.dart`, `validation.dart` | Small shared secure-ID/protected-dependency and exact Unicode checks, preserving draft behavior. |

Each operation enters one `StorageHandle.useDatabase`; database-taking internal
helpers avoid nested public repository admission. Selection uses a short
transaction for settings/profile consistency. An explicit profile bypasses
settings entirely; selected damage is detected before overrides, then operation
mismatch fails. Pure merge/validation remains within the admitted Future after
the SQL transaction ends, so close still drains the whole operation.

Per-field priority is explicit invocation > profile > existing defaults. Only
request 5 s, initialization 15 s, startup 0 ms, maxEntries 128, and maxResponses 1
have program defaults. Descriptor/path, endpoints and budgets merge independently;
zero and explicit empty path/content are meaningful. A descriptor-only override
can fail against an inherited path. Listen filter absence inherits; explicit
null clears; numeric zero is a valid filter. Full validation applies to both
complete preset saves and merged results, with actual content capacity checked
only on send/PING resolution. Respond validates the local return route, leaving
unknown incoming content capacity to the existing responder at response time.
Earlier applicable deadlines still win without a task-budget ordering rule.

Profile creation uses secure 16-byte random IDs and targeted ID-only insertion
retry (eight attempts). Changed saves atomically replace all typed content;
canonical codec comparison ignores stored JSON formatting and deeply compares
path bytes for no-op. No-op performs no UPDATE/time call. Supplied missing IDs
never upsert. Equal/backward UTC microsecond clocks are preserved. Concurrent
valid saves can both succeed in transaction order; there is no profile revision.
Deletion relies on the enabled FK to clear only the default reference, preserving
history limit, unrelated data and historical run associations/snapshots.

Settings read/default validation share a transaction. Null/1000 is returned
without an initial row. Save validates a referenced profile before committing
both fields; missing references fail as not_found without changing settings.
Explicit null save/reset bypass old dangling references. Limits are 1..100000.
Every mutation awaits commit. Write/controlled pre-commit failures roll back
immediately and the same open handle can continue. Reads/resolution use read
fallback; every part of a mutation uses write fallback. Input/merge errors are
invalid_input, stored semantic/type/JSON damage database_corrupt, and missing
references not_found. Protected ID/clock failures cannot masquerade as damaged
rows. Normal errors contain no local text, paths, route/test IDs, content or SQL.

The one manifest addition is the normal workspace dependency
`meshcore_link: ^0.1.0-dev.2`. Normal pub resolution followed by enforced resolution
left the single root lockfile unchanged: this workspace member and its native
serial dependency were already resolved. No package/SDK/communication/storage
version, schema, snapshot, table, column, FK, or index changed. Offline means no
device I/O; core validation can now invoke existing libserialport native build
hooks, requiring the same Apple compiler/platform SDK. Shared hook tests/builds
are run sequentially. Existing CI already generates/guards schema and runs the
full core suite, discovering new tests without duplicate jobs.

### Handoff to 1C.6

Use `CoreStorage.resolveParameters` as validated execution input and map only
allowed fields into a safe diagnostic configuration snapshot. Never persist its
whole result: it contains local route/test labels and raw invocation content.
1C.6 owns registration, typed communication-result mapping, independent logical
and actual cleanup saves, recovery, and lifecycle coordination using the same
owned handle. No device transaction may span an SQL transaction.

1C.7 owns bounded history query, eligibility/deletion guards, actual bounded
pruning and safe export. Only diagnosticHistoryLimit is persisted here. Pruning
must trigger after a settings limit commit, terminal/recovery updates, and open;
a pruning failure must be reported separately from the already committed save.
There is no retention scheduler/callback or deletion of runs/drafts in 1C.5.

1C.8 owns CLI parser presence (only truly supplied options become overrides),
text/hex lexical conversion and exactly-one-content checks, explicit nonblank
port with exact path forwarding, host data directory selection and execution
wiring. Current meshctl remains unconnected to business SQLite. This work stops
at 1C.5; no coordinator, recovery, history API, CLI flags, UI, or version bump is
included.

### 1C.5 local validation on November 12, 2026

Actual environment: macOS **27.2.1 (26B131), arm64**, using the installed
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` **3.13.7 stable**.
Installed Flutter metadata reports **3.47.9 stable**, framework revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`; this is metadata, not a fresh Flutter
wrapper result. Native commands use process-local Apple-compiler-first PATH
`/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`, selecting `/usr/bin/clang`
**21.0.0** (`clang-2100.4.1.1`) and the installed Xcode/macOS 27.2 SDK.
Before project scripts/tests, `/opt/homebrew/bin/python3` was verified as
**3.15.2**, resolving `sys.executable` to
`/opt/homebrew/opt/python@3.15/bin/python3.15`. No SDK, interpreter, channel,
global PATH/configuration, or dependency version was installed/upgraded.

| Check | Observed result |
| --- | --- |
| Root normal `dart pub get`, then `dart pub get --enforce-lockfile` | Passed; only the core manifest adds the existing workspace link member. The unique root lockfile is byte-for-byte unchanged, with no member lockfiles. Workspace list shows all three members plus root. |
| Core `dart run build_runner build` | Passed; tracked production/probe generated files unchanged. |
| Core `dart run tool/check_schema.dart` | Passed; production schema 1, frozen JSON snapshot and complete generated verification helper set/bytes match. |
| Root `dart format --output=none --set-exit-if-changed .` | Passed; **100 Dart files, zero changes**. |
| Root `dart analyze --fatal-infos` | Passed; no issues. |
| All repository tests (`dart test --reporter expanded test/repositories`) | **191 passed**, including **157 new** profile/settings/resolver/validation tests and all 34 existing draft tests. |
| Complete meshchan_core | **234 passed**, including all previous 77 value/probe/codec/file/preflight/ownership/close cases. |
| Complete meshcore_link | **180 passed**. |
| Complete meshctl | **97 passed** with local loopback allowed. The initial sandboxed run had 16 fixture bind failures (`127.0.0.1`, Operation not permitted); that log is retained separately. No external peer or device was used. |
| Python development-tool suite | **46 passed**, using the verified Python entry above. |
| Native build gates | Three fresh sequential bundles passed: product meshctl, serial observation fixture, and development datagram acceptance fixture. Existing native assets were copied by the standard build hooks. |
| Shared source/AOT smoke | **69 passed on macOS**, including native assets, broken pipe, complete-bundle relocation and five synthetic datagram scenarios in source/AOT. |
| Final diff/artifact review | Tracked patch and all new files checked for whitespace/conflict markers/final newlines; schema/generated/snapshot/root-lockfile comparisons unchanged. No database/cache/bundle artifacts added to version control. |
| Remote CI / Linux / hardware | **NOT_RUN** for these changes: no push/dispatch or observed remote CI result; this host is macOS. No real-device/RF test or SQLite product AOT-distribution claim. Existing CI is unchanged and naturally discovers the new core tests. |

Tests exposed and corrected test setup issues (an omitted Drift extension import,
a nested test registration, and a legal 0x3F/63-byte Direct route mislabeled as
invalid). The corrected route rejection fixture has a mismatched path; production
continues to delegate route interpretation to link helpers. Initial analyzer-only
unused/unnecessary imports were removed. Final results above are the passing
runs, not exceptions to the validation contract.

Logs, actual toolchain output, schema/generated hashes and fresh bundles are
retained locally under ignored `build/phase-1c5/local-20261112/`:

```text
pub-get.log
pub-get-enforced.log
workspace.log
toolchain.log
python-toolchain.json
codegen.log
schema-check.log
generated.sha256
format.log
analyze.log
repository-tests.log
meshchan-core-tests.log
meshcore-link-tests.log
meshctl-tests.log
meshctl-tests-network-enabled.log
python-tests.log
build-meshctl.log
build-observation.log
build-datagram-acceptance.log
smoke.log
final-review.log
meshctl/bundle/
observation/bundle/
datagram-acceptance/bundle/
```

Real SQLite failure tests reject writes and COMMIT before commit takes effect;
they verify immediate rollback and normal reopen, not every power-loss window.
The CLI still has no business SQLite wiring, so its bundle/smoke pass does not
establish complete SQLite product AOT packaging. 1C.6–1C.8 remain scoped by the
handoff above; no recording/recovery/pruning/export or CLI business flow was
started in this step.

### 1C.5 NUL-name review follow-up on November 12, 2026

The review reproduced a real validation/category mismatch: names beginning with
NUL, or only U+0020 spaces before NUL, passed complete input validation but failed
schema 1's `CHECK (length(trim(name)) > 0)` as storage_write_failed. SQLite's
default trim removes only U+0020 spaces, and length stops at the first NUL.

The profile-specific validator now rejects exactly these incompatible names as
invalid_input before beginning a transaction, querying, or calling clock/ID
sources. It does not rewrite accepted names. A non-U+0020 character before NUL
still satisfies the SQLite constraint, including tab/newline or Unicode
whitespace; compatible embedded NUL names remain exact. The shared Unicode
validator still accepts NUL as valid Unicode, and port hints/drafts gain no NUL
restriction. A stored name violating this constraint is database_corrupt on
read/list/update/resolution through the existing stored-validation boundary.

Three real-file regressions cover six rejected name forms for both create and
update, unchanged existing content, and zero transaction/query/clock/ID use by
rejected saves. The test checks the real SQLite name predicate with bound input.
Six compatible name forms and NUL-containing port hints survive create, update,
list and reopen. A deliberately constraint-violating stored fixture verifies
corruption classification. Before the fix, two regressions failed with the
reported behavior; after the fix all three passed.

Validation used the same installed macOS 27.2.1 arm64, bundled Dart 3.13.7,
Apple Clang 21.0.0 and process-local compiler PATH as the record above. The
Homebrew Python entry `/opt/homebrew/bin/python3` was reverified as 3.15.2 before
any project script use. Full meshchan_core tests passed **237/237**, root format
reported **100 files, zero changes**, fatal-info analysis found no issues, and
the schema guard passed. Schema 1, frozen/generated artifacts, dependencies,
root lockfile and versions remain unchanged. Prior uncommitted 1C.5 work was
preserved. No remote CI result was observed. Communication/CLI, Python suites,
native builds and smoke were not repeated for this profile-only validation fix;
their earlier dated results remain above. No hardware or later-step work ran.

Before/after regression logs, full core tests, formatting, analysis, schema guard
and final review are retained in ignored
`build/phase-1c5/nul-review-20261112/`.

## Diagnostic recording, lifecycle coordination and recovery (1C.6)

This step starts from clean master `93d933bc74959da8242a3c2432ec412cb9247f15`,
which merges PR #22 and includes its reviewed head
`0bad2980706fc9a9a47c55596e78e232031703e7`. The preceding 1C.5 handoff and dated
validation records above remain historical evidence. Recording and startup
recovery are now implemented; this step stops before 1C.7.

The public `CoreStorage.record` entry accepts EffectiveParameters, the host's
actual appVersion, a synchronous factory for a fresh unused public
CompanionTransport, and an immutable subscription responsibility plan. It
revalidates execution values through the same validation as the resolver. The
[runnable synthetic example](../packages/meshchan_core/example/record_diagnostic.dart)
and [API guide](../packages/meshchan_core/README.md#finite-diagnostic-recording-and-startup-recovery-1c6)
show open/recovery, resolve, recording, separate observations, cancellation and
finally-close without a real device. No CLI flags or execution wiring changed.

| File under meshchan_core/lib/src | Responsibility |
| --- | --- |
| recording/projection.dart | Explicit configuration/result whitelist and exhaustive enum mapping. Reads only direct typed evidence, never cause chains/sessionInfo. |
| recording/validation.dart | Stored/caller semantic distinction, lifecycle consistency, counts/budgets, final facts and two-scope cleanup aggregation. |
| recording/run_store.dart | Targeted run_id collision handling, canonical idempotence, field-specific transactions and a nonpoisoning per-run queue. |
| recording/raw_operation.dart | Finite raw send/listen, normal trailing-event consumption, immediate terminal close and logical facts before native release. |
| recording/recording.dart | Public handles/results, task ownership, complete subscription plan, independent cleanup observers and save outcomes. |
| recording/recovery.dart | Startup-only recovery, 128-row short transactions, stable state/time/ID cursors and preserved prior facts. |
| storage/storage.dart | One existing owner/connection; full recording admission survives closing; owner release only after actual database close. |

Prepared commits before the transport factory; entropy/clock and commit failure
permit no device start. Logical observation time is captured before enqueueing;
frozen facts commit independently of cleanup. Equal facts retain the first
stored time. Cleanup can commit when logical save failed and the row remains
prepared. Cumulative scope snapshots preserve two same-category source failures
without duplicating callbacks. A failed write does not poison the queue or
trigger resend. Native close and subscription cancellation start before database
writes and cannot be held behind them.

PING/responder reuse existing tasks, observing done and cleanupDone before start;
only task.cancel controls an accepted task. Raw send/listen use public
session/reception APIs with one inbox consumer. Normal listen waits for trailing
entries/onDone; abnormal termination closes immediately and settles commands
without waiting for native cleanup. Internal task subscriptions stay in core;
raw/host subscription cleanup stays in hostSubscriptions. Failed subscription
creation cleans every returned resource; an unclaimed task remains not_required.
Rejected cleanup observations retain unconfirmed release.

PONG before local failure remains observed/exact with its first monotonic
microsecond elapsed time; roundTripSucceeded is false and application RTT null.
Successful logical RTT stays successful after cleanup failure. Send matching
response means OK, not PONG. A queued send and a preceding failed read retain
distinct command/root evidence. Missing reception stays null; publication and
processing remain distinct. Zero responder responses establish no round trip.
Sensitive content, nonce, exact path, endpoint labels, ports, device metadata,
exception text/stacks never enter run JSON. Historical profile ID requires no
active profile lookup.

Open runs recovery after SELECT 1, before returning a handle. Prepared rows
archive interrupted, retaining partial/null results and null logical end.
Settled rows with unresolved cleanup archive cleanup_unconfirmed, preserving
final result/time and changing only unresolved scopes to unconfirmed_after_exit.
Terminal cleanup, including actual failed cleanup, survives; fully settled rows
remain unchanged. Archived rows are not scanned/rewritten. No task reason,
PONG false, zeros, logical end, release confirmation or RF replay is inferred.
Batches are individually atomic; a failed later batch leaves earlier commits
for idempotent continuation. Accessed damage is database_corrupt; higher summary
format remains storage_read_failed. Mutation/commit/dependency failures retain
storage_write_failed through open's close/release/quarantine path.

### Handoff to 1C.7

DiagnosticHistory is still an unwired read/query contract in repositories.dart.
Implement bounded history access, terminal deletion eligibility, real bounded
history-limit pruning and safe export next. Use the strict decoder plus
validateStoredRun and protect recovered facts. Eligible settled rows require
both scopes terminal; recovered_archived is independently eligible. Pending
live rows stay protected. Connect pruning after successful exclusive recovery
and open, terminal logical/cleanup commits and settings-limit commits. Report
pruning failure separately from committed saves. No placeholder scheduler,
public replacement CRUD, event table or schema v2 is installed.

1C.8 subsequently owns CLI wasParsed presence, content lexical conversion,
explicit nonblank port with exact forwarding, host directory, recording entry,
signal subscriptions and output/exit precedence. Current CLI remains unconnected
to business SQLite. This step includes no 1C.7 or 1C.8 implementation.

### 1C.6 local validation on November 12, 2026

Validation ran on macOS 27.2.1 arm64 with the existing Homebrew Flutter 3.47.9
stable cache and its bundled Dart 3.13.7. Commands invoked
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` directly: the Flutter
wrapper attempted an SDK-cache stamp refresh outside the sandbox's writable
roots, so the installed bundled executable was used without updating the SDK.
Native commands used process-local Apple-compiler-first PATH and
`/usr/bin/clang` 21.0.0 (`clang-2100.4.1.1`) with the installed Xcode macOS SDK.
No SDK/channel, interpreter, global PATH or global setting was changed.

Before project Python scripts, `/opt/homebrew/bin/python3` was verified as stable
3.15.2. Its actual sys.executable was
`/opt/homebrew/opt/python@3.15/bin/python3.15`, resolving to
`/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15`.
The exact interpreter/version/platform output is in python-toolchain.json;
Flutter cache, Dart, compiler and SDK evidence is in toolchain.json.

| Gate | Observed result |
| --- | --- |
| Root dart pub get --enforce-lockfile | Passed; root lockfile and manifests unchanged. |
| build_runner build | Passed; tracked production/probe generated artifacts unchanged. |
| check_schema.dart | Passed; production schema 1 and frozen/generated helpers match. |
| Root format check | Passed, 112 files, zero changes. |
| dart analyze --fatal-infos | Passed, no issues. |
| Full meshchan_core dart test | **304 passed**, including **66 new** recording/projection/write/recovery tests and all prior repository/resolver/NUL-name/ownership regressions. The additional legal-business reopen test preserves separate structural codec coverage. |
| meshcore_link dart test | **180 passed**; communication implementation unchanged. |
| meshctl dart test | Initial sandbox run: 81 passed, 16 failed because loopback bind returned Operation not permitted. Rerun with loopback permission: **97 passed**. Both logs retained. |
| Python unittest discovery | **46 passed** using the verified 3.15.2 interpreter. |
| Native CLI, serial observation and datagram-acceptance bundles | All three fresh builds passed sequentially with existing targets and isolated ignored output directories. |
| Shared source/AOT smoke | **69 passed** on macOS, including five synthetic datagram cases in source/AOT, native assets, broken pipe and bundle relocation. |
| Public fake recording example | Passed: registration/logical/final-cleanup commits, actual cleanup succeeded and fullySuccessful true; no real device. |
| Final diff/new-file review | Passed: tracked and new-file whitespace, conflict/unmerged markers, sole root lockfile and unchanged schema/snapshot/generated/dependency/version/CLI/link/CI boundaries. |
| Remote CI, Linux, real RF/hardware | **NOT_RUN**: no push/dispatch or observed remote CI result; this host is macOS and no device was authorized/used. |

Initial full-core runs identified old structurally valid fixtures that cannot
be used as business-recovery examples. Their descriptor 0x12/two-byte route was
preserved in structural tests; legal terminal reopen fixtures now use 0x02/two
bytes. Original codec/null/large-integer coverage remains. The final full suite
also explicitly verifies cleanup arriving before logical done, and real cleanup
observation while a logical SQL write is blocked. Final formatting resolved only
missing control-flow braces in new code/tests; the analyzer is clean.

Logs, exact toolchain records, generated hashes, final review and fresh bundles
are retained locally under ignored `build/phase-1c6/local-20261112/`, including:

```text
pub-get.log
codegen.log
schema-check.log
format.log
analyze.log
recording-tests.log
cleanup-observation-test.log
fixture-regression.log
meshchan-core-tests.log
meshcore-link-tests.log
meshctl-tests.log
meshctl-tests-network-enabled.log
python-tests.log
example.log
build-meshctl.log
build-observation.log
build-datagram-acceptance.log
smoke.log
toolchain.json
python-toolchain.json
generated.sha256
final-review.json
meshctl/bundle/
observation/bundle/
datagram-acceptance/bundle/
```

Focused recording-tests.log records the earlier 62-test run; the final 66-test
set is included in the 304-test full-core result. Controlled write/COMMIT faults
are injected before commit takes effect, with immediate same-handle rollback and
later successful work verified. Child exits establish only the two tested
interruption windows, not every power-loss failure. Bounded recovery commits
batches individually. CLI bundles/smoke still have no business SQLite execution
path and do not establish complete SQLite product AOT distribution. Schema 1,
summary format 1, CLI schema 1, app/package versions, dependencies, frozen snapshots
and CI remain unchanged. The existing CI full-suite/generation/schema gates
naturally discover the new tests; no redundant job or remote success is claimed.
No 1C.7 history/deletion/pruning/export or 1C.8 CLI wiring was started.

### 1C.6 synchronous-cancellation review follow-up on November 12, 2026

The review reproduced a host-subscription leak in raw send/listen. A subscribe
callback could call cancelOperation synchronously before returning its
subscription. Raw cancellation immediately called host cleanup, which marked
empty registration slots finished and not_required. Subscriptions returned
subsequently were never canceled because the host stop pass had already run.

The coordinator now keeps operation cancellation immediate and defers only host
cleanup while the synchronous subscription-registration pass is in progress.
A finally boundary ends registration and starts any requested host cleanup,
including when a later subscribe callback throws. Only then can empty slots be
classified as having no work. Every returned subscription is canceled and
observed independently through the existing cleanup path. No public API, SQL
schema, persisted vocabulary, device behavior or retry policy changed.

Six real-file regressions cover send/listen, two returned subscriptions, repeated
synchronous cancellation, a cancellation failure while another source remains
blocked, and later subscription-construction failure. Before the fix all six
failed with zero actual cancellation calls; afterward all six passed. The
blocked-source cases also check persisted pending scope/aggregate, exactly one
cancellation per source, retained failure count, close waiting and owner
contention, then terminal cleanup after releasing the barrier and reopening.

Validation used the existing bundled
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` 3.13.7 and the
process-local Apple compiler PATH; `/usr/bin/clang` was reverified as 21.0.0
(`clang-2100.4.1.1`). The six focused regressions passed, the full meshchan_core
suite passed **310/310**, root format checked **112 files with zero changes**,
and fatal-info analysis reported no issues. Tracked diff and the affected new
source/test files passed whitespace checks. Schema, generated artifacts,
dependencies, versions, communication/CLI implementations and CI are unchanged.
No Python scripts were invoked. Generator/schema, link/CLI/Python suites,
native bundles and smoke were not repeated for this core-only lifecycle fix;
their preceding dated results remain above. No remote CI or hardware run was
performed. Reproduction, corrected regressions, full suite, format, analysis
and verified Dart/compiler logs are retained under ignored
`build/phase-1c6/synchronous-cancel-review-20261112/`.

### 1C.6 raw cancellation-precedence review follow-up on November 12, 2026

The review reproduced loss of an earlier primary failure in raw send/listen.
Transport error delivery synchronously commits session.lastFailure and invalidates
accepted commands, but public session events and command continuations run later.
Calling recording.cancel in that same turn previously froze a canceled result
with no primary failure, preventing the asynchronous failure observer from
retaining the already committed session evidence.

Raw cancellation now checks session.lastFailure before honoring cancellation,
using the existing stage-specific failure path when evidence is already present.
The terminal guard still protects frozen results. It does not add a deadline
check, alter timeout precedence, walk causes, wait for storage/cleanup, or retry
device work. Failure reason/stage and typed root/command/reception facts remain
independent of actual cleanup and persistence results.

Six real-file regressions cover both raw operations: earlier transport failure
during initialization, earlier failure during ready-state work, and the reverse
ordering where cancellation precedes the error. Before the fix, all four
failure-first cases reproduced an incorrect canceled reason while both reverse
controls passed. Afterward all six passed. Tests block actual native close,
verify logical commit is independently observable, inspect typed session and
command/reception facts, and compare saved summaries after cleanup and reopen.

Validation used the verified bundled
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` 3.13.7 with the
process-local Apple compiler PATH; `/usr/bin/clang` was reverified as 21.0.0
(`clang-2100.4.1.1`). All six targeted regressions passed, the complete
meshchan_core suite passed **316/316**, root formatting checked **112 files with
zero changes**, and fatal-info analysis found no issues. Tracked and affected
new-file whitespace checks passed, with no unmerged paths. The preceding
synchronous-subscription cancellation fix remains covered by the complete suite.
Schema, generated artifacts, dependencies, versions, communication/CLI sources
and CI remain unchanged. No Python scripts were invoked. Generator/schema,
link/CLI/Python suites, native bundles and smoke were not repeated for this
localized core fix; earlier dated results remain above. Remote CI and hardware
were not run. Before/after regressions, full tests, format, analysis and actual
Dart/compiler version logs are retained under ignored
`build/phase-1c6/session-failure-cancel-review-20261112/`.

## Bounded diagnostic history and safe export (1C.7)

Implemented from clean `master` at
`27de0edf232cf7b0c7280d80482e32b94909daec` (PR #23 merge). The reviewed
`d1e5e281087630c93b62ed0b5c47c1733e80459c` head is its second parent and an
ancestor of this baseline. No reset, checkout, history rewrite or dependency
upgrade was required. The earlier 1C.6 validation records above remain historical.

The public barrel exposes `CoreStorage.history`, `DiagnosticHistory`,
`DiagnosticSummaryPage`, `HistoryMaintenanceState` and
`HistoryMaintenanceReport`. See the [complete history contract and host usage](../packages/meshchan_core/README.md#diagnostic-history-retention-and-safe-export-1c7)
and the [hardware-free example](../packages/meshchan_core/example/inspect_history.dart).
The example accepts a host directory, queries/continues a filter, exports one
page, observes maintenance independently and finally closes. It does not choose
an application data directory, change product CLI parsing or delete an implicit
selection.

| Implementation | Responsibility |
| --- | --- |
| history/history_repository.dart | One admission per read/query/delete/export or maintenance request/wait; safe export-generation classification. |
| history/history_store.dart | Bound SQL for present filters and `(prepared_at_us, run_id)` seek; strict whole-page/probe validation; shared persistent eligibility; 128-row pruning transactions. |
| storage/storage.dart | Stable getter, per-run pins, precommit selection revision, coalesced worker, startup/sticky reports and maintenance admission within the existing close barrier. |
| recording/recording.dart and run_store.dart | Pin before exposing prepared/device work; invalidate rank inside logical/cleanup transactions; register postcommit maintenance separately from save results; unpin only after every save settles. |
| repositories/settings_repository.dart | Keep committed AppSettings results; invalidate inside save/reset transactions and register maintenance after commit. |
| storage/codec.dart | Explicit export envelope/run allowlist sharing existing nested typed allowlists; fixed six-digit UTC encoding without changing stored JSON. |

Queries combine optional operation, recordState, inclusive UTC prepared-from and
exclusive UTC prepared-until. Default 50/max 200, strict size+1 probe, all valid
states, epoch microseconds, descending timestamp/ID ties, cursor-row deletion
and independent-page snapshot limits match the architecture contract. Actual
executed SQL/arguments are used for EXPLAIN tests of all four existing indexes;
continuations require composite SEARCH and no temporary sorting. Unranged first
pages may use an ordered index SCAN. No OFFSET or caller SQL is used.

Eligibility is validated recovered_archived, or settled with both scopes
terminal, including failed cleanup. Pins are separate deletion guards and do not
alter eligible rank. Retention counts all operations together. Every batch reads
current stored settings without resolving a default profile, validates every
visited row and advances past ineligible/pinned rows. Short transactions retain
at most 128 rows and delete at most 128 IDs. Cleanup JSON has no eligibility
index: scans may visit all history and repeat after invalidation. There is no
O(128) total-work or cross-history atomicity claim.

External mutations invalidate selection before their transaction commits; a
rollback can cause a harmless rescan. Each following transaction restarts counting
if the revision/limit changed. Worker deletes do not invalidate themselves or
trigger another worker. This protects against increased/decreased limits,
explicit deletion of a counted retained row, new eligible records and unpin
before the old cursor. Old pinned excess rows are deferred without deleting
newer policy-retained rows. Unpin requests another check. Healthy work continues
through all batches; protected-only work ends deferred, and a failed batch ends
the execution without a failure loop. Earlier committed deletions remain and
only they contribute to deletedCount on failure. Another trigger/open retries.

Triggers cover recovery/open, eligible logical/cleanup commits, final pin
release, settings save/reset, explicit delete and maintain. Repeated requests
join the running worker. `waitForMaintenance()` observes already requested work;
`maintain()` requests a check. `latestMaintenance` includes startup. Later success
does not clear `unacknowledgedFailure`/`unacknowledgedFailureCount`; the host must
explicitly acknowledge after handling them. The bounded failure state is local
to the handle, without a persistent queue/log. Limits are nullable in a failure
report only when no valid settings limit was obtained.

Main transactions and maintenance remain independent. A prune failure cannot
change a committed AppSettings/RecordingSave, task reason, cleanup facts,
coordination failure, fullySuccessful or sends. Open still rejects failed
preflight/schema/recovery, but returns a usable handle if only subsequent
retention failed. All automatic maintenance is synchronously admitted before its
source admission ends, even if close has begun. Close waits for admitted
recording, actual cleanup, saves and maintenance, then closes the same connection
and releases the same owner. Maintenance errors release their count and do not
become native closeUnconfirmed; actual native-close quarantine is unchanged.

Export returns one complete JSON string plus a typed continuation. The root is
`diagnosticSummaryFormatVersion: 1`, a once-observed `exportedAt` and `runs`.
Per-run fields are explicitly constructed; profileId is omitted entirely.
Configuration/result/two-scope cleanup retain byte lengths, route descriptor and
path length, safe error codes, integer microsecond RTT/elapsed and meaningful
null/false/zero. Every time uses UTC Z and exactly six fractional digits. No
profiles/ports/exact routes/content/test IDs/nonces/device details/argv/raw
exceptions or stacks are exported. Unknown stored formats retain storage_read_failed;
corruption remains database_corrupt; export-generation exceptions are safe
storage_read_failed. Continue explicitly using nextCursor and the same filter.
It is a summary selection, not a backup or import format.

### Handoff to 1C.8

Use `lib/meshchan_core.dart` and the core README/example as the concrete API.
Host CLI work must supply its data directory, preserve profile presence and
explicit content conversion, authorize and forward the current explicit port,
resolve parameters, record through CoreStorage.record, and keep signal/host
subscriptions alive until their real cleanup completes. Wire history filters and
both cursor values to history.query/exportSummary, explicit selected IDs to
delete, and let the host handle JSON output/storage failures. Observe startup,
automatic and explicit maintenance reports plus unacknowledged failures
independently of committed settings/recording outcomes before closing. CLI
output/exit precedence belongs there; this step adds no flags, CLI envelope,
exit codes, release or dev.3 delivery. Database schema/snapshot 1, diagnostic
summary format 1, CLI schema 1, package versions and dependencies are unchanged.

### 1C.7 local validation on November 12, 2026

Actual baseline/host: clean master at PR #23 merge
`27de0edf232cf7b0c7280d80482e32b94909daec`, macOS **27.2.1 (26B131)** arm64.
The installed `/opt/homebrew/share/flutter` cache records Flutter **3.47.9**
stable, revision `c197ca5199e9ee5661e865596c9c07294dfab51c`; direct bundled
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --version` reported
**Dart 3.13.7**. Commands used that installed Dart and an Apple-compiler-first
process-local PATH. `/usr/bin/clang` reported Apple Clang **21.0.0**
(`clang-2100.4.1.1`). Before project Python scripts, the explicit
`/opt/homebrew/bin/python3` entry was verified as stable **3.15.2**, with actual
`sys.executable` `/opt/homebrew/opt/python@3.15/bin/python3.15`. No SDK/channel,
interpreter, global PATH/settings, dependencies or package versions were changed.

| Check | Observed result |
| --- | --- |
| Root dart pub get --enforce-lockfile | Passed; root lockfile and manifests unchanged. |
| Core dart run build_runner build | Passed; production/probe generated files unchanged. |
| Core dart run tool/check_schema.dart | Passed; formal schema 1, frozen snapshot and generated verification helpers match. |
| Root dart format --output=none --set-exit-if-changed . | Passed; **120 files, zero changes**. |
| Root dart analyze --fatal-infos | Passed; no issues. |
| Focused dart test test/history | **46 passed**, using actual query plans, strict bad probes, rollback, retention, export and real recording save/pin barriers. |
| Complete meshchan_core dart test | **362 passed**, retaining repository/resolver/recording/recovery, NUL-name, synchronous-subscribe cancellation, prior-failure precedence and owner/process regressions. |
| Complete meshcore_link dart test | **180 passed**; communication implementation unchanged. |
| Complete meshctl dart test | Initial sandbox run: 81 passed and 16 local-loopback bind failures (Operation not permitted). Rerun with loopback permission: **97 passed**. Both logs retained. |
| Python unittest discover -s tool -p '*_test.py' | **46 passed** using the verified Homebrew 3.15.2 entry. |
| Existing native build gates | Three fresh bundles passed sequentially: product CLI, serial observation and development datagram acceptance. |
| Shared source/AOT smoke | **69 passed on macOS**; native assets, complete-bundle relocation, broken pipe and five synthetic datagram scenarios in source/AOT. |
| Final frozen-artifact/patch review | Schema/generated/snapshot/lock/manifests unchanged; whitespace, new files and conflict markers checked. |
| Remote CI | **NOT_RUN**; no corresponding remote run was dispatched or observed. Existing CI already includes generation/schema/full core coverage and needed no duplicate job. |

Final logs, actual toolchains, frozen hashes and fresh bundles are under the
ignored local directory `build/phase-1c7/`:

```text
pub-get.log
build-runner.log
schema-check.log
format.log
analyze.log
history-all-third.log
core-tests.log
link-tests.log
cli-tests.log
cli-tests-loopback.log
python-tests.log
python-toolchain.json
dart-toolchain.log
flutter-cache-toolchain.json
clang-toolchain.log
host-toolchain.log
frozen-artifacts.diff
frozen-artifact-hashes.log
cli-build.log
observation-build.log
datagram-acceptance-build.log
smoke.log
meshctl/bundle/
observation/bundle/
datagram-acceptance/bundle/
```

Development iterations also retained their earlier logs. The final targeted
barriers run host actions outside Drift transaction zones and distinguish the
concurrent delete read from the final recording save read; an obsolete targeted
run blocked on the earlier test barrier was stopped before final validation.
These are synthetic software/real-file results, not hardware/RF or arbitrary
power-loss acceptance. Existing CLI bundles still do not execute business
SQLite, so their smoke is not SQLite product AOT distribution acceptance. Linux
and other-platform native acceptance were not run on this Mac. No 1C.8 CLI work,
release or dev.3 delivery was started.

## Business CLI entry points and recording integration (1C.8)

Implemented from clean `master` at `8f2165eceae7f9aeab26b552b55f60f9e47defc0`.
GitHub PR #24 was rechecked as merged on November 12, 2026; its head remains
`17cf7f78aae537e05c3c99d4c45a4c803ba132e6`, and its merge commit is this baseline.
No reset, checkout, history rewrite, merge, tag, release or upload was performed.
The dated 1C.7 and earlier records above remain historical.

The CLI adds one local workspace dependency, `meshchan_core: ^0.1.0-dev.2`.
Locked pub resolution succeeds without any lockfile or third-party/SDK/native
version change. Production CLI imports only the public core barrel; no private
SQL, codec, RawOperation or RunStore is used there. Link remains independent of
business/CLI/database code. Database schema/snapshot 1, safe-summary format 1,
CLI schemaVersion 1 and all package versions remain unchanged. New commands and
opt-in recording blocks extend the existing CLI schema-1 contract explicitly.

| Implementation | Responsibility |
| --- | --- |
| `business_storage.dart` | Host platform directory policy; stable core error mapping; one awaited wait/close barrier and post-close memory-only sticky/latest maintenance reads |
| `business_input.dart` | Strict decimal/LocalId input, calendar-checked UTC with up to six fractional digits, reusable typed two-field cursors |
| `business_command.dart` | Offline parser/validation and public repository calls; exact strict UTF-8 file input, partial draft/settings merge, full profile/settings replacement, one final business envelope/raw export |
| `business_projection.dart` | Explicit local draft/profile/settings projections and separate safe typed diagnostic/cleanup/save allowlists |
| `datagram_options.dart` | Presence-aware lexical requests, profile parameter declarations and pure effective-to-legacy-runner adaptation |
| `datagram_command.dart` | Retained no-record device runner; final object deferred until storage finalization, legacy success envelope unchanged |
| `recorded_datagram_command.dart` | One public recording coordinator; early host intent latch, all terminal observations/bounded save attempts, real signal ownership and pending cleanup, independent final facts |
| `meshctl.dart` | Complete syntax/help/version ordering, safe parser errors, multiline inline option values, one opener/policy seam and business dispatch |
| `process_io.dart` | Start every owned signal-watch cancellation independently and observe all Futures |

See the [CLI guide](cli.md#offline-business-commands-and-storage-1c8) for complete
commands, copyable isolated examples, schemas, cursor/export metadata and exit
mapping. Defaults use the specified absolute macOS/Linux/Windows base policy;
relative paths are explicit only. Every finite datagram resolves default/explicit
presets, with exact port and per-run content required before opening storage.
Actual complete route/capacity validation precedes any transport factory.
Only `--record` inserts a diagnostic run. Recorded listen emits one final end;
no-record listen retains per-entry NDJSON and uses the previous runner.

Recording registration commits before device/subscription-plan construction.
The datagram invocation owns its process-signal source before storage open and
through resolution, execution, maintenance and actual DB close. The coordinator
owns a real forwarding observer; invocation-source cancellation is awaited after
the storage barrier and reported separately as signalCleanup. Pending or failed
source cancellation never becomes successful saved core cleanup. A latched stop
before device admission skips transport/recording while still closing any
returned handle. No task-owned subscription/session is consumed or closed twice.
Final typed non-canceled task/session evidence corrects provisional external
priority without rewriting core's saved canceled result. All necessary cleanup
and saves settle without a retry or artificial release deadline.

After op.done the handle still drains its recording admission, unpin and final
maintenance. The CLI waits while open, closes once, then reads only retained
history memory getters. Latest success never clears an earlier sticky failure.
Settings/recording commits, logical outcome, two cleanup scopes, maintenance,
DB close and output remain independent; otherwise independent storage/host I/O
failure returns 74. Safe unexpected errors still reach the existing process
boundary as 70 after cleanup. Safe summary export uses core's original JSON
string and an independent stderr metadata line, even when later close fails.

Offline commands also latch cancellation/output failure before admission or
while a real commit/close is pending. Already admitted SQLite work settles;
committed data is preserved, actual close and signal cancellation are awaited,
and their independent failures remain visible.

The existing datagram virtual-clock/acceptance callers use a real isolated
SQLite directory per invocation. New CLI tests use real files, exact parser
paths, controlled SQL/native/save/cleanup barriers and small delegated audit
wrappers. A test-only core history Fixture can take an explicit temporary
directory, allowing the controlled process tests to reuse its real executor/fault
seams without adding production bypasses or another dependency. The finite RF
plan generator now emits isolated directories for future product datagram argv;
validation/summarization retain legacy-argv support. No RF plan was executed.

### Handoff to 1C.9

- Keep the package/version boundary explicit: prepare the intended dev.3 version
  delivery only in 1C.9, with reviewed version constants/manifests and release
  materials. No version bump or release artifacts were produced here.
- Package the whole CLI bundle with serial **and SQLite** native assets. Preserve
  the new real business smoke when preparing notices, dependency/license/native
  asset inventories, integrity manifests and archives.
- Complete clean-machine/relocation and supported OS/architecture distribution
  matrices. Same-host macOS source/AOT/relocated SQLite execution does not prove
  Linux/Windows lock/native/product behavior or arbitrary moved-machine support.
- Observe remote CI for the final change and preserve failed/blocked runs. The
  existing job already runs generation/schema/all suites and the updated smoke;
  no redundant CI workflow was added.
- Continue outstanding RF/USB unplug/relay and historical delivery investigations
  on their authorized tracks. Synthetic transports/loopback and SQLite process
  tests establish software facts only. No new radio configuration writes,
  Flutter UI, backup/import, replay, event store, unbounded export or retry was added.

### 1C.8 local validation on November 12, 2026

Actual host: macOS **27.2.1 (26B131)** arm64. The installed Flutter cache records
**3.47.9 stable**, revision `c197ca5199e9ee5661e865596c9c07294dfab51c`;
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --version` reports
**Dart 3.13.7**. Apple Clang is **21.0.0**, `clang-2100.4.1.1`. Before project
Python execution, `/opt/homebrew/bin/python3` was verified as stable **3.15.2**;
actual `sys.executable` is `/opt/homebrew/opt/python@3.15/bin/python3.15`.
Dart/native runs used an Apple-compiler-first process-local PATH
`/usr/bin:/bin:/opt/homebrew/bin:$PATH` and the explicit installed Dart path.
Python scripts used the explicit Homebrew entry; subprocess tooling continues to
use `sys.executable`. No SDK/channel/interpreter/global PATH upgrade or native
system-library substitution was made.

| Actual command/check | Observed result |
| --- | --- |
| Root `dart pub get --enforce-lockfile` | Passed; only the necessary CLI workspace dependency declaration changed, lockfile unchanged |
| Core `dart run build_runner build` | Passed, including the final run after host-example edits; generated artifacts unchanged |
| Core `dart run tool/check_schema.dart` | Passed; production schema 1, frozen snapshot and generated helpers match |
| Root `dart format --output=none --set-exit-if-changed .` | Passed; **132 files, zero changes** |
| Root `dart analyze --fatal-infos` | Passed; no issues |
| Complete `packages/meshchan_core` `dart test` | **362 passed** |
| Complete `packages/meshcore_link` `dart test` | **180 passed** |
| Complete final `apps/meshctl` `dart test` with local loopback access | **166 passed**, including **69 added** business/directory/recording/history/process/cancellation cases and all 97 prior regressions |
| `/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'` | **49 passed**, including three new generated-directory/legacy-argv/invalid-base cases |
| Fresh final product CLI `dart build cli` | Passed; copies serial and SQLite build assets through their normal hooks |
| Fresh final serial observation `dart build cli` | Passed; serial asset retained |
| Fresh final development datagram acceptance `dart build cli` | Passed; serial and SQLite assets retained; synthetic scenarios use isolated storage |
| Updated shared source/AOT smoke | **90 process checks passed on macOS**; seven actual business SQLite checks each in source, product AOT and relocated complete product bundle, plus retained legacy/synthetic gates |
| Frozen/dependency/new-file/whitespace review | Schema, snapshot, generated files, lockfile and package versions unchanged; only one dependency declaration added; `git diff --check` passed |
| Remote CI / RF / clean-machine / other-platform native acceptance | **NOT_RUN**; these local results do not establish them |

Commands used the repository root unless a member directory is shown. The final
build/smoke commands were executed sequentially:

```bash
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
(cd apps/meshctl && "$MESHCHAN_DART" build cli \
  --target=bin/meshctl.dart --output=../../build/phase-1c8/final/meshctl)
(cd packages/meshcore_link && "$MESHCHAN_DART" build cli \
  --target=example/serial_transport_check.dart \
  --output=../../build/phase-1c8/final/observation)
(cd apps/meshctl && "$MESHCHAN_DART" build cli \
  --target=tool/datagram_acceptance.dart \
  --output=../../build/phase-1c8/final/datagram-acceptance)
/opt/homebrew/bin/python3 tool/smoke_cli.py --dart "$MESHCHAN_DART" \
  --cli-bundle build/phase-1c8/final/meshctl/bundle \
  --observation-bundle build/phase-1c8/final/observation/bundle \
  --datagram-acceptance-bundle build/phase-1c8/final/datagram-acceptance/bundle
```

The smoke committed actual `meshchan.sqlite` files and loaded SQLite through the
new product bundle. A second process read exact Chinese/emoji/CR/LF draft content
and settings from the same directory. Empty history export decoded as the core
object. The complete bundle was also copied outside the checkout and exercised
from a different cwd. Databases were at explicit isolated paths, not in cwd or
bundles. Product assets are `bin/meshctl`, `lib/liblibserialport_plus.dylib` and
`lib/libsqlite3.dylib`; do not infer this inventory for other platforms.

Failures and development iterations remain visible. An initial native source
invocation before selecting the documented PATH chose Homebrew Clang 18.1.8 and
failed with `ld: library 'System' not found`; selecting the existing Apple compiler
resolved it. An early legacy datagram harness run preceded its isolation wrapper,
failed to open the managed default location (74), and inspection showed the user
default business directory remained absent. The final harness/probe and every
valid business test use explicit temporary directories or a delegated real opener.
The initial complete sandbox CLI run had **141 passed, 17 failed**: 16 existing
loopback binds returned Operation not permitted; one new process test incorrectly
expected source build-hook stderr to start with JSON. That test now removes only
the exact known build-hook prefix. Final full execution with local loopback
permission passed all 166 cases. Neither native probing permissions nor system
settings were changed. Earlier successful interim bundles/smoke were retained;
the `final/` bundles were rebuilt from the final implementation, not replaced
with an older artifact.

Evidence is retained under ignored `build/phase-1c8/`, including:

```text
pub-get.log
build-runner-final.log
schema-check-final.log
format.log
analyze.log
core-tests.log
link-tests.log
cli-tests.log
cli-tests-final.log
python-tests.log
python-toolchain.json
dart-toolchain.log
flutter-cache-toolchain.json
clang-toolchain.log
host-toolchain.log
cli-build-final.log
observation-build-final.log
datagram-acceptance-build-final.log
smoke-final.log
final/meshctl/bundle/
final/observation/bundle/
final/datagram-acceptance/bundle/
```

1C.8 code/tests/docs and the local source/AOT wiring gate are complete. No package
version, database/summary format, release/tag/publication state or hardware
acceptance conclusion changed. The concrete remaining delivery work is listed
in the 1C.9 handoff above.

### 1C.8 review fix: signal ownership across storage phases

The subsequent review correctly identified a gap in the initial 1C.8 wiring:
datagram runners subscribed only after storage open/resolution and canceled the
real source before storage finalization. A broadcast signal during either initial
await was lost; a late signal during DB close was also ignored. With actual
process watches these gaps could restore default termination while a handle was
still owned. The earlier dated validation above did not cover those windows.

`stored_datagram_command.dart` now owns the full host pipeline through the same
public core APIs. `DatagramSignals` subscribes once after independent lexical
validation and before open, latches synchronous/early signal and output intent,
and retains the real source through resolution, execution, maintenance and close.
A stop before device admission waits for any admitted storage Future, closes its
returned handle and skips transport/recording. During execution the runner owns
an actual forwarding subscription; the invocation keeps observing after that
observer is canceled. Late stop/source-error notifications and final replay feed
the existing primary-failure rules before the unique terminal output.

The actual source is canceled and awaited after the storage barrier, on success,
CoreException and unexpected-error paths. Recording's saved host scope describes
its forwarding observer, not the invocation's longer process-watch lifetime.
The new opt-in `signalCleanup` block describes actual invocation-source release;
its failed cancellation prevents success without rewriting core cleanup or
`RecordedResult.fullySuccessful`. Unrecorded normal envelopes stay unchanged;
source-cancellation failures retain the CLI cleanup aggregate plus the independent
signalCleanup block. Pre-device cancellation has null result/recording facts.
No core repositories, SQL/schema, dependencies, versions or device retries changed.

Validation on the same macOS 27.2.1 arm64 host used bundled Dart 3.13.7, installed
Flutter cache 3.47.9, Apple Clang 21.0.0, and the reverified explicit Homebrew
Python 3.15.2. Native/test commands kept the Apple-compiler-first process PATH.

| Review-fix check | Actual observed result |
| --- | --- |
| New gated reproductions against the pre-fix implementation | **All 12 failed**, reproducing SIGINT/SIGTERM loss in open, resolution and close, with and without recording |
| Focused datagram/storage/recording/legacy acceptance files | **91 passed**, including 26 new gated storage/source/error/priority/cancellation-Future cases |
| Complete CLI suite with required local loopback access | **200 passed**, including eight additional child-process tests using actual SIGINT/SIGTERM |
| Root format / fatal-info analyze | **137 Dart files, zero formatting changes**; no analysis issues |
| Python unittest discovery via `/opt/homebrew/bin/python3` | **49 passed** |
| Three fresh sequential native bundles | Product CLI, serial observation and development datagram acceptance all built successfully through normal native hooks |
| Shared source/AOT/relocated-bundle smoke | **90 process checks passed**, including real business SQLite and all five retained synthetic datagram scenarios |
| Patch/frozen-artifact review | `git diff --check` passed; schema/snapshot/generated files and lockfile unchanged |

The child-process protocol waits for a storage gate, sends the actual OS signal,
waits for acknowledgment of delivery, proves directory ownership is still held,
and only then releases storage. No scheduling sleeps or real devices are used.
Gated tests also retain earlier device failure, preserve signal/output ordering,
propagate source errors only after cleanup, and hold the real source cancel
Future pending after DB close to prove output/exit do not finish prematurely.
Existing pre-start tests now expect unknown/null device results when cancellation
prevents storage/device admission, rather than inventing a canceled task.

The exact commands were the existing `dart test`, root format/analyze and
`/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'` commands.
Fresh builds used `dart build cli` with the same three targets as the original
record and output roots under `build/phase-1c8-signal-review/final/`. The updated
`tool/smoke_cli.py` used those complete bundles with the explicit installed Dart.
Review-fix logs are retained under ignored `build/phase-1c8-signal-review/`:
`before-fix.log`, `targeted-third.log`, `cli-tests.log`, `format.log`, `analyze.log`,
`python-tests.log`, `cli-build.log`, `observation-build.log`,
`datagram-acceptance-build.log`, and `smoke.log`. The original records/artifacts
remain retained. Core implementation was unchanged, so its package suites were
not rerun for this host-only review fix. Remote CI, other-platform native and
hardware/RF acceptance were not run; the 1C.9 delivery boundary is unchanged.

### 1C.8 review fix: observation order and serialized process suites

A further review identified two remaining host/test issues. The admission error
branch selected a CoreException after all cleanup, unconditionally replacing an
earlier effective signal/output intent. Failed registration likewise assigned a
new primary code even when cancellation had already been observed. Separately,
the two CLI subprocess suites could launch SDK native-asset bundling at the same
time under default test-file concurrency. The reviewer observed `otool` failing
to open the shared `.dart_tool/lib/liblibserialport_plus.dylib`; a later passing
run did not remove that structural race.

The admission catch now freezes whether that failure was primary at its actual
observation point. Earlier SIGINT/SIGTERM/output intent keeps its reason/code;
a later admission failure retains its stable code/source in additionalFailures.
Conversely, an admission failure observed first remains primary if a signal
arrives while close is pending. Registration/save reporting uses the existing
first-cause chooser too and adds nonprimary save failures independently. Failed
registration still has no device/logical result, logical/cleanup saves remain
notAttempted, and its failed RecordingSave remains explicit. Existing frozen
non-canceled task/session precedence is unchanged.

`apps/meshctl/dart_test.yaml` now sets `concurrency: 1`, following the existing
core-package configuration. Default `dart test` therefore serializes test files,
preventing the two source-process suites from bundling into `.dart_tool/lib`
concurrently. No tests were skipped, child failures retried, native files
replaced or timeouts loosened. Ownership fixtures still keep the already-started
owner alive while a probe runs; readiness acknowledges that owner's native-asset
startup has completed before the next child launch.

`datagram_failure_priority_test.dart` adds 18 real-storage cases: delayed SQLite
creation failure, public resolver rejection, delayed registration-transaction
rollback, and reverse-order failure/signal controls. SIGINT, SIGTERM and output
failure are tested before later faults; both recorded and unrecorded admission
paths retain the correct primary and independent storage facts. Registration
rollback asserts zero transport and subscription-plan factories and reopens the
file to confirm no diagnostic committed. Against the pre-fix implementation,
**15 cases failed and the three reverse-order controls passed**; after the fix,
all cases and the related storage-signal/recording regressions passed.

Validation used the reverified installed toolchain: macOS 27.2.1 (26B131) arm64,
Flutter cache 3.47.9 stable, direct bundled Dart 3.13.7, Apple Clang 21.0.0, and
`/opt/homebrew/bin/python3` 3.15.2 with actual executable
`/opt/homebrew/opt/python@3.15/bin/python3.15`. The native/test process PATH kept
Apple's compiler first; no global settings or toolchain versions changed.

- Focused priority/storage-signal/recording files: **79 passed**.
- Two consecutive complete **default `dart test`** executions from apps/meshctl:
  **218 passed each**, with the authorized local loopback fixtures. The second
  deliberate verification ran only after the first succeeded; this was not a
  retry of a failed run. Both subprocess suites executed in each run without
  native-asset preparation failures.
- Root `dart format --output=none --set-exit-if-changed .`: **138 files, zero
  changes**; `dart analyze --fatal-infos`: no issues.
- Explicit Homebrew Python unittest discovery: **49 passed**.
- Three fresh sequential `dart build cli` bundles: product CLI, serial
  observation and development datagram acceptance all built successfully through
  the normal native hooks. Product and acceptance bundles include SQLite assets.
- Shared source/AOT/relocated-bundle smoke: **90 process checks passed**, including
  committed and reopened real SQLite through each product entry and all five
  retained synthetic datagram scenarios in source and AOT.
- Patch/frozen review: `git diff --check` passed; lockfile, schema/snapshot and
  generated verification artifacts unchanged. Core implementation, dependencies
  and package versions were unchanged; core/link suites were not rerun for these
  CLI/reporting/test-runner changes.

The exact package test command remained `dart test`, without a command-line
concurrency override. Fresh builds used the same three documented targets and
output roots under `build/phase-1c8-review-priority/final/`. The shared smoke ran
with the explicit installed Dart and all three complete bundles:

```sh
/opt/homebrew/bin/python3 tool/smoke_cli.py \
  --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart \
  --cli-bundle build/phase-1c8-review-priority/final/meshctl/bundle \
  --observation-bundle build/phase-1c8-review-priority/final/observation/bundle \
  --datagram-acceptance-bundle build/phase-1c8-review-priority/final/datagram-acceptance/bundle
```

Reproduction and validation logs are retained under ignored
`build/phase-1c8-review-priority/`: `before-fix.log`, `targeted-tests.log`,
`cli-tests-default.log`, `cli-tests-default-repeat.log`, `format.log`,
`analyze.log`, `python-tests.log`, `cli-build.log`, `observation-build.log`,
`datagram-acceptance-build.log`, `smoke.log`, and `frozen-artifacts.diff`. Earlier
validation records and failures remain historical. Remote CI, other-platform
native and hardware/RF acceptance were not run; the 1C.9 release/distribution
boundary remains unchanged.

### 1C.8 review fix: offline finalization failure priority

A further review reproduced an offline-command ordering defect: known
maintenance/DB-close failures were selected only after signal-subscription
cancellation. If that cancellation failed too, its later cleanup_failure/69
replaced the earlier storage-finalization failure that should have selected 74.

`runOffline` now selects storage_finalization_failure immediately after its
awaited BusinessStorage.finish barrier, before canceling signals. The existing
first-cause chooser preserves an already effective signal/output/business cause.
Later signal cancellation still runs and retains hostCleanup=failed with its
safe additionalFailures entry. Committed results, raw core export JSON, actual
storageClose and maintenance facts remain independent. No storage owner is
reopened or quarantine cleared to collect these reports.

Four new cases cover this ordering. Real settings commits trigger retention
delete failure followed by failed signal cancellation, with a gated earlier
SIGTERM control. Two child-process cases reject actual native DB close before
failing signal cancellation, checking draft and export output, process exit,
closeUnconfirmed, quarantine until process exit, and committed draft reopen
after exit. Against the old order, the three reproductions returned 69 instead
of 74; the earlier-SIGTERM control passed. After the fix, both affected files
passed all **23 tests**. Tests use real SQLite and explicit gates, no hardware or
scheduling sleeps.

The installed toolchain was reverified as macOS 27.2.1 (26B131) arm64, bundled
Dart 3.13.7, Apple Clang 21.0.0, and `/opt/homebrew/bin/python3` 3.15.2. Native
test commands retain the Apple-compiler-first process PATH. Root
`dart format --output=none --set-exit-if-changed .` checked **138 files with zero
changes** and `dart analyze --fatal-infos` found no issues.

The complete default `dart test` from apps/meshctl passed **222 tests**, including
both subprocess suites and the synthetic loopback fixtures, with local socket
access enabled. From apps/meshctl, the targeted command and new-only pre-fix
selection were:

```sh
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart test test/business_history_test.dart test/business_process_test.dart
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart test test/business_history_test.dart test/business_process_test.dart --name 'offline maintenance failure precedes|before signal cleanup failure|and signal cleanup fails'
```

Reproduction and validation logs are retained under ignored
`build/phase-1c8-offline-finalization-review/`:
`before-fix.log`, `targeted-tests.log`, `cli-tests.log`, `format.log`, and
`analyze.log`.

`git diff --check` and frozen lockfile/schema/generated-artifact checks passed.
This small CLI finalization change did not alter core APIs/implementation,
dependencies, schemas or package versions. Core/link/Python suites, fresh AOT
builds, remote CI and hardware/RF acceptance were not rerun for this fix; the
earlier validation records remain historical. No release/distribution action
was taken and the 1C.9 handoff boundary is unchanged.

### 1C.8 review fix: required offline IDs and revisions

Review identified that prepareOffline used ArgResults.options to decide which
fields to validate. That collection contains supplied/defaulted options, not all
declared options, so omitted IDs/revisions bypassed validation. A profile update
could therefore pass a null ID to core's intentional create form of save; other
actions could reach null assertions after opening storage. A missing draft
mutation field could also allow body-file I/O before rejecting the request.

Shared group/action predicates now determine ID and revision requirements for
both parser setup and preparation. Every applicable show/update/delete validates
its ID even when omitted; draft update/delete similarly validate the expected
revision. The existing validators reject these requests with 64 before body-file
reads, directory selection, storage ownership, signal subscription or devices.
Create/settings/list/export/prune and normal help/version behavior retain their
existing requirements. Core's save semantics and typed revision handling are
unchanged.

The new parser matrix covers 14 malformed argument combinations in text and
JSON mode, plus one help/version control. An additional product-entry process
test covers the reported complete profile-update preset without an ID, draft
show without an ID, and draft delete without a revision, requiring no isolated
data directory/database to appear. Before the fix, **29 regressions failed**
and the help/version control passed; the product profile-update child returned
0 instead of 64. After the fix, the two affected test files passed all
**50 tests**, retaining the actual SQLite persistence and native-close cases.
Tests also assert zero opener/policy/transport/subscription/enumeration calls
and safe option-only errors for the invalid-input paths.

Validation used the reverified macOS 27.2.1 (26B131) arm64 host, direct bundled
Dart 3.13.7 and Apple Clang 21.0.0 with Apple's compiler first in the native-test
process PATH. `/opt/homebrew/bin/python3` was reverified as 3.15.2; no Python
tooling changed. Root `dart format --output=none --set-exit-if-changed .` checked
**138 files, zero changes**, and `dart analyze --fatal-infos` found no issues.

The complete default CLI `dart test` passed **252 tests** with local loopback
access enabled, including all subprocess and synthetic transport suites.
From apps/meshctl, targeted and pre-fix selection commands were:

```sh
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart test test/business_cli_test.dart test/business_process_test.dart
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart test test/business_cli_test.dart test/business_process_test.dart --name 'missing --|missing required options still|product entry rejects missing'
```

Logs are retained under ignored `build/phase-1c8-required-options-review/`:
`before-fix.log`, `targeted-tests.log`, `cli-tests.log`, `format.log` and
`analyze.log`. `git diff --check` and frozen lockfile/schema/generated-artifact
checks passed. This fix did not change core APIs/implementation, dependencies,
schemas or package versions. Core/link/Python suites, fresh AOT builds, remote
CI and hardware/RF acceptance were not rerun for this parser-only change; earlier
validation records remain historical. The 1C.9 release/distribution boundary is
unchanged.

### 1C.8 review fix: offline primary and additional failure fields

Review found that offline commands retained an earlier signal/output reason and
exit code but unconditionally assigned a later CoreException to the primary
failure field. Export metadata had the same mismatch and omitted the later
error from additionalFailures.

`runOffline` now keeps the safe business error separately from the primary
failure, assigning the primary field only when that business error wins. A later
business error joins the shared additionalFailures list used by ordinary output
and export metadata. The independent business error still drives failed
operation/commit facts and safe stderr diagnostics, so moving an error to the
additional list cannot turn a failed admitted operation's committed=false into
unknown. Earlier business errors stay primary when a signal/output failure is
observed during final close. Raw export JSON and core lifecycle behavior are
unchanged.

`offline_failure_priority_test.dart` adds 18 real-SQLite cases. Twelve gate
creation, draft transaction or export-read failure until SIGINT/SIGTERM/output
failure is observed and require null primary failure plus the later core error
in additionalFailures. Six reverse-order controls observe the operation error
before injecting external intent while close is pending. They also verify safe
diagnostics, actual cleanup, reopened empty data, false commit facts and no
invented export. Before the fix, **12 reproductions failed and six controls
passed**. After the fix, the new file and related offline/datagram priority files
passed **98 tests**.

The reverified environment remains macOS 27.2.1 (26B131) arm64, direct bundled
Dart 3.13.7 and Apple Clang 21.0.0 with the Apple-compiler-first native-test PATH.
`/opt/homebrew/bin/python3` was reverified as 3.15.2. Root formatting checked
**139 files with zero changes**; `dart analyze --fatal-infos` found no issues.

The complete default CLI `dart test` passed **270 tests** with local loopback
access enabled, including subprocess and synthetic transport suites. From
apps/meshctl, the reproduction and focused commands were:

```sh
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart test test/offline_failure_priority_test.dart
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart test test/offline_failure_priority_test.dart test/business_history_test.dart test/business_cli_test.dart test/datagram_failure_priority_test.dart
```

Logs are retained under ignored `build/phase-1c8-offline-envelope-review/`:
`before-fix.log`, `targeted-tests.log`, `cli-tests.log`, `format.log` and
`analyze.log`. Patch whitespace and frozen lockfile/schema/generated-artifact
checks passed. This CLI projection fix did not change core APIs/implementation,
schemas, dependencies or package versions. Core/link/Python suites, fresh AOT
builds, remote CI and hardware/RF acceptance were not rerun; earlier validation
records remain historical. The 1C.9 release/distribution boundary is unchanged.

## Final regression and local dev.3 candidate (1C.9)

The [1C delivery record](releases/phase-1c-dev3.md) is the current source of
candidate paths/hashes, exact local results, CI checkout coverage, native assets,
materials and the 1D handoff. Work began on clean master at
`33dca83b109f4b9a22e218e29fde96d4c2adc493`, the actual PR #25 merge; the reviewed
head `e237be5c2fb9e4fd1cf2f2c26717582f34a5e757` is an ancestor.

Three members, internal constraints and the CLI constant now use `0.1.0-dev.3`.
Root workspace/lockfile and external dependency selections are unchanged.
Database/schema snapshot 1, summary format 1 and CLI schema 1 are unchanged.
Production changes are limited to versions; recording/CLI/core state machines
are reused. Historical dev.2 values and dated evidence above remain intact.

Use `tool/validate_dev_candidate.py` with an explicit fresh build directory and
installed Dart path, then `tool/check_schema_compatibility.py` and
`tool/package_1c_candidate.py` as documented in the release record. The new narrow
packager uses this software/native gate rather than the 1B hardware plan or latest
pointer. `package_dev_candidate.py` and metadata-only `revise_dev_candidate.py`
remain historical dev.2 tools; neither renames old bytes to dev.3.

Product, acceptance-tool and documentation hashes are separate. Core sources and
actual generated code are included; complete recursive runtime assets and log
hashes bind gates to tested bytes. Missing/failed gates or changed inputs fail
packaging. Archive checks reject extra/missing/duplicate/traversing/link/special
members and mode/hash changes before extraction. Only after extracted executable
business checks and post-run byte equality does external archive-verification
become PASS. The archive hash and final extraction record remain external to
avoid self-containing hash cycles.

New version and packaging regressions are discovered by existing Python CI;
updated shared smoke and Dart acceptance tests cover nonempty recording without
new actions/workflows. Final uncommitted dev.3 changes have no remote CI result.
Same-host relocation and ad-hoc signing are distinct from clean-machine,
Developer ID/notarization and public-distribution acceptance. No hardware/RF,
Flutter UI, dependency/toolchain upgrade, global settings or project-license
selection was performed.

### 1C.9 delivery-tool environment/path review follow-up on November 12, 2026

Three review findings were confirmed and corrected in Python tooling only.
`Checks` now accepts an explicit child environment and passes it through the
process runner. The schema-compatibility caller supplies its prepared
Apple-compiler-first environment; constructing that dictionary alone previously
had no effect on the legacy native build. Other callers retain inherited-env
behavior by default. No global PATH or compiler installation was changed.

Shared smoke resolves an explicit evidence directory against the invoking cwd
before any child runs. Source and relocated product processes therefore receive
the same absolute database paths even with a relative `--evidence-directory`.

A shared SDK locator now recognizes either an installed SDK binary or the
standard Flutter Dart launcher, including Homebrew symlinks. It validates the
SDK's version, API header and core library layout as well as LICENSE, and rejects
unrecognized layouts. Material collection resolves the SDK before copying any
notices. Validation also records the discovered SDK directory/version and finds
Flutter cache metadata relative to that SDK. The Flutter framework LICENSE can
no longer qualify as the Dart SDK notice merely because it exists.

New `tool/delivery_environment_test.py` covers actual child environment delivery,
compatibility-caller wiring, cross-cwd evidence paths, original SDK license/archive
notice collection for direct/launcher/symlink inputs, and rejection when SDK
structure is incomplete. Pre-fix failures are retained. An initial test-only
`/var` versus `/private/var` path-comparison mismatch was corrected by canonicalizing
the temporary fixture root; the subsequent targeted five tests passed.

Validation used the reverified Homebrew Python 3.15.2 (actual executable
`/opt/homebrew/opt/python@3.15/bin/python3.15`), installed Dart 3.13.7 and the same
macOS arm64 host. Complete Python discovery passed **61 tests**. A genuine old
schema-1 compatibility run using `/opt/homebrew/bin/dart` and a caller PATH headed
by `/opt/homebrew/opt/llvm@18/bin` passed all **8 process checks**; the recorded
child PATH starts `/usr/bin:/bin:/opt/homebrew/bin`. Complete source/AOT/relocation
smoke using that Flutter launcher and a relative evidence directory passed all
**101 process checks**. Real material collection through the launcher copied the
actual SDK LICENSE, SHA-256
`2cfa3ee8e7512e6d44c854b986510810fadc815f93f890373b3a81c1b6ccd256`,
which also matches the original candidate's SDK notice and differs from the
Flutter framework license. Python subprocesses continue to use sys.executable.

Logs, commands/times/exits, pre-fix failures, retained input/asset hashes and
license verification are under ignored
`build/phase-1c9/review-delivery-tools-20261112T190351Z/`. See review-gates.json,
review-inputs.json, schema-compatibility.json, relative evidence/process-checks.json,
launcher-materials-verification.json and review-verification.json.

Product compilation inputs and all three existing bundle inventories are unchanged.
No Dart production code, schema, dependency, native binary or SDK changed, so the
product suites and native builds were not repeated for these Python-only fixes.
The original archive remains unchanged at SHA-256
`6528394052e999de748323090db78d22344db7be1d9264a5ea1f8e35cfa4afe0`.
It was built with the direct SDK binary and already contains the correct SDK
license. No replacement archive or publication was issued. Original manifests
remain historical tool snapshots; current changed verification inputs are not
silently substituted into those old passing gates.

### 1C.9 schema-path review follow-up on November 12, 2026

Two further Python-only path findings were reproduced and fixed in
`check_schema_compatibility.py`. Row comparison now uses an escaped absolute
`Path.as_uri()` plus `?mode=ro`, rather than interpolating a filesystem spelling
into a URI. Literal `#`, `%` and `?` cannot change the database name or consume
the read-only query. The comparison connection is explicitly closed on return
or error. The Dart argument now uses the shared executable parser: resolve it
against the invoking cwd, require a nonempty executable file, and reject invalid
inputs before creating build files or extracting legacy source. Both legacy
child working directories receive the same absolute executable.

Four added delivery regressions exercise literal/percent-encoded/conflicting
filenames, spaces/Unicode, actual SQLite write rejection, missing-file preservation,
a real child executable selected through a relative symlink in two cwds, and
missing/empty/nonexecutable/directory argument rejection before build work.
Pre-fix results reproduced unintended write access, percent-decoding into a
neighboring file, and FileNotFoundError after changing cwd. Final targeted
execution passed **9 tests**; complete Python discovery passed **65 tests**
with the reverified Homebrew Python 3.15.2. The final runs have no database
ResourceWarnings; an earlier intermediate run and all pre-fix failures remain.

The actual compatibility command passed **8 process checks** with a relative
`--dart` symlink containing a space and a normal legacy-source cwd. The recorded
executable is absolute. A real old schema-1 file generated by that run was then
copied to `business#1%23?mode=rwc 中文/`: escaped read-only comparison preserved
its bytes, and **4 native process checks** completed AOT recording, a product
commit and nonempty product query/export. Old rows remained unchanged, new runs
use dev.3, and no URI-truncated database appeared.

A separate combined attempt with the legacy source checkout itself under
`build#1%23 中文/` remains **BLOCKED by an installed Dart 3.13.7 native-hook path
limitation**. Locked resolution passed, but Dart rejected the hook.dill path as
an unknown command before recording or Python row comparison. The failed
command/exit/log are retained; it is not called a successful combined build.
No SDK/pub-cache/upstream source was changed to mask this failure. This is
distinct from the corrected Python SQLite URI and executable-resolution defects.

Evidence is under ignored
`build/phase-1c9/review-schema-paths-20261112T191824Z/`: before-fix.log,
targeted-final.log, python-tests-final.log, review-gates.json,
schema-special-path-relative-dart.log, relative-dart-gate.json,
special-database-verification.json and review-verification.json.
Product compilation inputs, all three native bundles and the original candidate
archive remain unchanged. Dart production suites/native builds were not repeated
for these Python-only corrections. The reviewer's separate 255-passed/16-loopback-
failed restricted CLI run remains reported as sandbox socket blocking, not a new
passing CLI gate. No replacement archive or remote publication was issued.

### 1C.9 retained-artifact analyzer review follow-up on November 12, 2026

The review reproduced **28 issues** from incomplete third-party SQLite source
fragments preserved under the root build directory. The workspace previously had
only the recommended-lints include, so root `dart analyze --fatal-infos` analyzed
those delivery materials as if they were workspace code. Later candidate gates
therefore failed even though the actual member sources were unchanged.

`analysis_options.yaml` now excludes only root `build/**` from workspace analysis.
The original notices/source materials and old checkouts are retained byte-for-byte;
no package dependency, analyzer diagnostic severity, generated library file or
first-party source tree was excluded to hide a product issue. Existing packager
output layout and original candidate archives are unchanged.

On the reverified macOS arm64 host with bundled Dart 3.13.7 and Homebrew Python
3.15.2, a deliberate temporary core-library type error produced exactly one
`return_of_invalid_type` diagnostic (expected analyzer exit 3) while retained
source-material diagnostics were absent. That owned probe was removed. The final
root `dart analyze --fatal-infos` then exited 0 with no issues, root format checked
**707 files with zero changes** in this retained-artifact tree, and complete Python
discovery passed **65 tests**. Patch whitespace passed. No permanent test or
production source change was needed for this analyzer-configuration correction.

Evidence is under ignored
`build/phase-1c9/review-analyzer-scope-20261112T193239Z/`: before-fix.log,
first-party-analysis-control.log, analyze-after-fix.log, format-after-fix.log,
python-tests.log, review-gates.json and review-verification.json.
The 74 retained source-material files, all three native bundles and the original
archive were rechecked unchanged. `analysis_options.yaml` is deliberately part
of productCompilationInputHashes, so the captured input map has one new hash.
The review records that difference; it does not relabel any old candidate gate
as validation of the new configuration. No native rebuild, Dart suite rerun,
replacement archive or remote publication was performed for this scope-only fix.
Previous SDK-path, clean-environment, CI and distribution limitations remain as
recorded in their independent evidence.
