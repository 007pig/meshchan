# Developer Guide

## Project language and workspace

Use American English for project documentation, code comments, CLI output, and configuration text. Keep identifiers in English.

The root `pubspec.yaml` lists `packages/meshcore_link` and `apps/meshctl`. Both members use `resolution: workspace`; all packages use `publish_to: none` and `sdk: ^3.13.0`. Keep the single root `pubspec.lock`. Do not create member lockfiles or add Flutter SDK dependencies. The CLI resolves `meshcore_link` to the local workspace member without overrides. Check membership with `dart pub workspace list`.

The root provides `lints`; the CLI uses `args` and `test`; the core uses `libserialport_plus` and has its own `test` development dependency. No Flutter engine or platform project is involved.

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
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
(cd packages/meshcore_link && dart test)
(cd apps/meshctl && dart test)
```

For a clone with an unchanged lockfile, start with `dart pub get --enforce-lockfile`. After intentional dependency changes, let pub resolve and update the root lockfile, review the diff, then enforce it. Do not perform unrelated workspace upgrades. Format only files involved in a change when fixing formatting.

Tests inject a small serial service, handle adapter, or native operation callbacks and never enumerate or open actual hardware. CLI tests check output, warnings, exit codes, exact-path forwarding, and that help/version/invalid arguments do not invoke diagnostics. Core tests check metadata failures, close/dispose behavior, open/state/close/dispose failures, and primary-error preservation. Regressions also cover false open-state reports, partial acquisition before an open failure, already-closed recovery, and USB serial numbers embedded in full or truncated Linux descriptions. Platform tests verify that blocked backends never execute their native callbacks. Invalid UTF-8 decoding tests retain the affected path, continue other records, and dispose every metadata handle; errors outside that decoding boundary still propagate. Build hooks compiling native assets are expected during tests.

## Serial framing (Step 3)

Step 3 introduced serial framing and its software tests. Step 4 connects that unchanged codec to a native serial transport; Step 5 adds a separate in-memory Companion message codec. Sessions and real initialization remain unimplemented. See [Serial transport](protocol/serial-transport.md) for its separate stream and resource contracts.

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

## Source CLI behavior

From `apps/meshctl`:

```bash
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart ports --help
dart run bin/meshctl.dart port-check --help
dart run bin/meshctl.dart ports
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
| `69` | Expected serial, platform, or native runtime dependency error. |

Normal results go to stdout; errors and warnings go to stderr. Expected operation errors retain available native error details without a stack trace or an assumption that the port is busy. Unexpected programming errors propagate. A source build-hook failure can terminate Dart before the application runs and is not governed by the application's exit-code contract.

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

Successful open/close does not identify a MeshCore device or establish protocol support, firmware identity, a session, or LoRa communication. Step 3 added in-memory framing; Step 4 adds the reader/writer adapter described above. Step 5 encodes APP_START and DEVICE_QUERY and parses their expected content layouts in memory. Sending initialization commands, sessions, reconnection, radio tests, database, and UI remain unimplemented.

## CI and SDK updates

The existing single `ubuntu-latest` job remains pinned to Flutter `3.47.9` stable via `subosito/flutter-action@v2.23.0`, using its bundled Dart and read-only repository permissions. It runs locked dependency resolution, formatting, analysis, both test suites, source help/version smoke checks, `dart build cli`, and bundle `--version`. A separate step invokes real source and bundle `ports` commands and strictly requires exit `69`, empty stdout, the exact Linux safety diagnostic, and no stack trace. Any different failure or a successful enumeration fails that step. It never runs `port-check` and does not ignore native build failures. No platform matrix or release workflow was added.

This is an intentional restriction of the earlier Ubuntu enumeration acceptance check: with the pinned backend, successful enumeration would violate the no-open requirement. Ubuntu CI validates native compilation/packaging and the refusal to enumerate, not successful native enumeration or runtime native library loading. Actual enumeration remains locally validated on macOS. No fake enumeration or ignored failure is used in CI.

CI configuration was updated; no remote workflow was run for these changes. Ubuntu results remain unverified. Local macOS success does not establish Linux, Windows, mobile, or clean-machine support.

After a Homebrew SDK change, record the actual versions/channel, run every applicable check above, and review lockfile changes. Update the fixed CI baseline and this guide together only when the local SDK actually changed and compatibility checks pass. Do not upgrade Flutter, switch channels, or reinstall Homebrew packages as part of routine project validation.

See the [Validation Record](hardware-validation.md) for dated results and remaining hardware work.
