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

Successful open/close does not identify a MeshCore device or establish protocol support, firmware identity, a session, or LoRa communication. No reader, frame handling, `APP_START`, device queries, reconnection, radio tests, database, or UI is implemented in this step.

## CI and SDK updates

The existing single `ubuntu-latest` job remains pinned to Flutter `3.47.9` stable via `subosito/flutter-action@v2.23.0`, using its bundled Dart and read-only repository permissions. It runs locked dependency resolution, formatting, analysis, both test suites, source help/version smoke checks, `dart build cli`, and bundle `--version`. A separate step invokes real source and bundle `ports` commands and strictly requires exit `69`, empty stdout, the exact Linux safety diagnostic, and no stack trace. Any different failure or a successful enumeration fails that step. It never runs `port-check` and does not ignore native build failures. No platform matrix or release workflow was added.

This is an intentional restriction of the earlier Ubuntu enumeration acceptance check: with the pinned backend, successful enumeration would violate the no-open requirement. Ubuntu CI validates native compilation/packaging and the refusal to enumerate, not successful native enumeration or runtime native library loading. Actual enumeration remains locally validated on macOS. No fake enumeration or ignored failure is used in CI.

CI configuration was updated; no remote workflow was run for these changes. Ubuntu results remain unverified. Local macOS success does not establish Linux, Windows, mobile, or clean-machine support.

After a Homebrew SDK change, record the actual versions/channel, run every applicable check above, and review lockfile changes. Update the fixed CI baseline and this guide together only when the local SDK actually changed and compatibility checks pass. Do not upgrade Flutter, switch channels, or reinstall Homebrew packages as part of routine project validation.

See the [Validation Record](hardware-validation.md) for dated results and remaining hardware work.
