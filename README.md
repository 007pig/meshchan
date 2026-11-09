# Meshchan

Meshchan is an open-source decentralized content application based on MeshCore. Its long-term direction is Flutter and Dart, with a reusable communication core that stays independent of Flutter. Development starts with a command-line diagnostic tool before adding a user interface.

The current implementation covers **Phase 1 / 1A / Step 8: minimal tests and hardware-free CI**, retaining the Step 7 diagnostic CLI behavior. See the [testing guide](docs/testing.md) for the behavior audit and shared source/native smoke checks, including broken pipes and complete-bundle relocation. Step 9 hardware acceptance remains open. `meshctl info --port <path>` initializes one existing `MeshCoreSession`, awaits cleanup, and prints a complete closed-connection snapshot. `meshctl watch --port <path>` initializes once and observes session states and unassociated response summaries until duration, signal, or failure. The original `ports` and `port-check` commands remain available. All four commands support JSON; watch uses NDJSON. See the [CLI guide](docs/cli.md) for options, schemas, cancellation, exit codes, and explicit-port hardware authorization.

See the [session contract and minimal caller example](docs/protocol/companion-session.md), [Companion codec layout](docs/protocol/companion-initialization.md), [serial transport contract and read-only example](docs/protocol/serial-transport.md), and [serial framing protocol](docs/protocol/serial-framing.md). Session software tests use a fake transport and synthetic responses. An [authorized Step 6 hardware follow-up](docs/hardware-validation.md#authorized-session-hardware-follow-up-on-november-9-2026) passed actual source and AOT initialization and cleanup on one selected macOS USB port. A [subsequent timeout investigation](docs/hardware-validation.md#session-timeout-investigation-on-november-9-2026) reproduced a delayed 64-byte response body with an independent POSIX client, outside Dart. Zero- and one-second sessions also passed; three seconds is not an established fix for this intermittent USB delivery problem. The product startup-delay default stays zero. Step 2/4 hardware results and the Step 5 probe remain separate historical evidence. Ready means only the two initialization sends and parsed response types completed; it proves no authenticated identity, full protocol-version support, or LoRa communication. Step 7 software acceptance uses synthetic transport tests and hardware-free process checks; the historical hardware runs do not validate the new CLI on a device.

A separately authorized [Step 7 CLI hardware follow-up](docs/hardware-validation.md#step-7-authorized-cli-hardware-follow-up-on-november-9-2026) passed source/native watch, duration, and ready-state signal cleanup on one selected port; both initial info attempts timed out. A later [bounded native CLI comparison](docs/hardware-validation.md#step-7-cli-timeout-comparison-on-november-9-2026) observed both successful info snapshots and watch timeouts with unchanged defaults. Captured failures had incomplete input at the native receive boundary; no CLI initialization defect was demonstrated. The delivery issue remains unresolved.

A subsequent [independent POSIX control](docs/hardware-validation.md#step-7-independent-posix-comparison-on-november-9-2026) reproduced the header-only 64-byte wait three times without Dart, libserialport_plus, or its reader. At the unchanged request deadline the tty input queue was empty and direct OS reads returned no remaining bytes. The stall therefore does not require those client components; device/USB/driver responsibility remains unresolved, with no retry or configuration workaround added.

| Package | Responsibility and current status |
| --- | --- |
| `packages/meshcore_link` | Flutter-independent Dart core with single-use Companion sessions, message codecs, serial framing, an explicit-port transport, and serial diagnostics. |
| `apps/meshctl` | Asynchronous diagnostic CLI: `ports`, `port-check`, `info`, and `watch`; text/JSON output and awaited session cleanup. |

## Quick start

On this machine, use the Homebrew-managed Flutter SDK and its bundled Dart SDK:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"

# Run from the project root.
dart pub get --enforce-lockfile
cd apps/meshctl
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart ports --help
dart run bin/meshctl.dart port-check --help
dart run bin/meshctl.dart info --help
dart run bin/meshctl.dart watch --help
```

Running without arguments or with `-h` also displays help. The application version remains `0.1.0-dev.1`. Help and version do not access hardware. Select and authorize a port explicitly before device commands; old selections do not carry over. `ports` lists exact system paths, descriptions, transport types, and USB VID/PID when available. It does not open ports or send probes. Missing metadata appears as `-`; a per-port metadata failure retains the path and writes a warning to stderr.

**Current native platform limits:** macOS is locally validated. With the pinned `libserialport_plus` 1.0.5, native `ports` is blocked on Linux, Android, and Windows before enumeration because the backend can open unselected ports. Windows `port-check` is also blocked before native handle creation because the wrapper's handle state check is unsafe on 64-bit Windows. These operations return `69` with an explanation. Explicit-port checking on Linux/Android remains unverified. Malformed UTF-8 metadata on an enabled backend produces a warning for that path while other records remain available.

To check a device, select its exact path explicitly, then run `dart run bin/meshctl.dart port-check --port "$MESHCHAN_PORT"` after setting `MESHCHAN_PORT` to that path. The command opens only that port for reading and writing, checks its state, closes it, verifies closure, and disposes native resources. It does not read or write data or explicitly configure serial settings. Opening or closing a port can still reset some boards through driver or control-line behavior. No port is chosen automatically.

| Exit code | Meaning |
| --- | --- |
| `0` | Success, including a genuinely empty enumeration (`No serial ports found.`). |
| `64` | Invalid arguments, unknown commands/options, missing or blank `--port`, or extra positional arguments. |
| `69` | Expected serial, platform, session, or cleanup failure. |
| `74` | Output failure without an earlier primary failure. |
| `130` / `143` | SIGINT / SIGTERM cancellation; cleanup is still awaited. |
| `70` | Unexpected program error at the process boundary. |

**An open/close success does not identify a MeshCore device.** Transport `open()` establishes local I/O only; `sendFrame()` completion means the local native/OS API accepted the framed bytes. Neither proves command execution, physical TX completion, or remote receipt. Database features and the Flutter UI are outside this step. Automated tests do not access hardware.

## Native CLI bundle

Source execution and compilation run the dependency's build hook, so a working native compiler and platform SDK are required, even for source help/version commands. On this validated macOS installation, prefer the installed Apple Clang for this terminal session:

```bash
# Run from the repository root.
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
cd apps/meshctl
dart build cli --target=bin/meshctl.dart --output=build/dist
build/dist/bundle/bin/meshctl --version
build/dist/bundle/bin/meshctl info --help
build/dist/bundle/bin/meshctl watch --help
```

Move or copy the entire `apps/meshctl/build/dist/bundle/` directory, including `bin/meshctl` and `lib/liblibserialport_plus.dylib` on macOS. Do not distribute the executable alone. Build output is ignored by Git. This bundle was checked on local macOS arm64, including after moving it outside the repository; clean-machine compatibility and other platforms remain unverified, with the runtime restrictions described above.

See the [Developer Guide](docs/development.md) for toolchain requirements, reproducible checks, dependency sources and licenses, and CI details. The [Validation Record](docs/hardware-validation.md) separates verified software and selected-port checks from remaining validation.
