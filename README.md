# Meshchan

Meshchan is an open-source decentralized content application based on MeshCore. Its long-term direction is Flutter and Dart, with a reusable communication core that stays independent of Flutter. Development starts with a command-line diagnostic tool before adding a user interface.

The current implementation covers **Phase 1 / 1A / Step 2: serial library and native build validation**. It includes serial port enumeration, an explicit single-port open/close diagnostic, hardware-free tests, and a CLI bundle with its native library. Local macOS checks passed for an explicitly selected real port, including reopening after release and running the bundle. MeshCore protocol support remains unverified.

| Package | Responsibility and current status |
| --- | --- |
| `packages/meshcore_link` | Flutter-independent Dart core with a thin `libserialport_plus` FFI adapter and explicit resource cleanup. |
| `apps/meshctl` | CLI help, application version, `ports`, and `port-check --port <path>`. |

## Quick start

On this machine, use the Homebrew-managed Flutter SDK and its bundled Dart SDK:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"

# Run from the project root.
dart pub get --enforce-lockfile
cd apps/meshctl
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart ports
dart run bin/meshctl.dart port-check --help
```

Running without arguments or with `-h` also displays help. The application version remains `0.1.0-dev.1`. `ports` lists exact system paths, descriptions, transport types, and USB VID/PID when available. It does not open ports or send probes. Missing metadata appears as `-`; a per-port metadata failure retains the path and writes a warning to stderr.

**Current native platform limits:** macOS is locally validated. With the pinned `libserialport_plus` 1.0.5, native `ports` is blocked on Linux, Android, and Windows before enumeration because the backend can open unselected ports. Windows `port-check` is also blocked before native handle creation because the wrapper's handle state check is unsafe on 64-bit Windows. These operations return `69` with an explanation. Explicit-port checking on Linux/Android remains unverified. Malformed UTF-8 metadata on an enabled backend produces a warning for that path while other records remain available.

To check a device, select its exact path explicitly, then run `dart run bin/meshctl.dart port-check --port "$MESHCHAN_PORT"` after setting `MESHCHAN_PORT` to that path. The command opens only that port for reading and writing, checks its state, closes it, verifies closure, and disposes native resources. It does not read or write data or explicitly configure serial settings. Opening or closing a port can still reset some boards through driver or control-line behavior. No port is chosen automatically.

| Exit code | Meaning |
| --- | --- |
| `0` | Success, including a genuinely empty enumeration (`No serial ports found.`). |
| `64` | Invalid arguments, unknown commands/options, missing or blank `--port`, or extra positional arguments. |
| `69` | Expected serial, platform, or native runtime dependency failure. |

**An open/close success does not identify a MeshCore device.** MeshCore protocol support, sessions, frame handling, all data transfer, and LoRa communication remain unimplemented. Database features and the Flutter UI are outside this step. Automated tests do not access hardware.

## Native CLI bundle

Source execution and compilation run the dependency's build hook, so a working native compiler and platform SDK are required, even for source help/version commands. On this validated macOS installation, prefer the installed Apple Clang for this terminal session:

```bash
# Run from the repository root.
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
cd apps/meshctl
dart build cli --target=bin/meshctl.dart --output=build/dist
build/dist/bundle/bin/meshctl --version
build/dist/bundle/bin/meshctl ports
```

Move or copy the entire `apps/meshctl/build/dist/bundle/` directory, including `bin/meshctl` and `lib/liblibserialport_plus.dylib` on macOS. Do not distribute the executable alone. Build output is ignored by Git. This bundle was checked on local macOS arm64, including after moving it outside the repository; clean-machine compatibility and other platforms remain unverified, with the runtime restrictions described above.

See the [Developer Guide](docs/development.md) for toolchain requirements, reproducible checks, dependency sources and licenses, and CI details. The [Validation Record](docs/hardware-validation.md) separates verified software and selected-port checks from remaining validation.
