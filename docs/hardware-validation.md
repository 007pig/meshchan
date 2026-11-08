# Step 2 Validation Record

Validation date: November 8, 2026. Scope: Phase 1 / 1A / Step 2 only.

Status labels used below: **Passed**, **Failed**, **Not run**, and **Pending hardware validation**. Serial open/close checks establish only the observed behavior of the explicitly selected port; they do not establish MeshCore protocol or radio support.

## Observed environment

- macOS 27.2 (26B123), arm64, verified using `sw_vers`, `uname -m`, and the SDK output.
- Flutter 3.47.9 stable; bundled Dart 3.13.7 stable (`macos_arm64`).
- `libserialport_plus` 1.0.5, resolved by pub with the shared root lockfile.
- Xcode developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Successful native compiler: Apple Clang 21.0.0 (`clang-2100.4.1.1`), selected through the current process's PATH.
- Target board identity, target firmware, and target CPU architecture: **unconfirmed**. Host arm64 does not establish a connected board's architecture.
- After enumeration, the user explicitly selected port 3: `/dev/cu.usbmodem211101`. Only this port was opened for the device checks below.

## Results

| Check | Status | Actual result |
| --- | --- | --- |
| Existing baseline before edits | Passed | Locked dependency resolution, formatting, analysis, 4 original CLI tests, help, and version. |
| Dependency resolution and lock enforcement | Passed | `dart pub get` and `dart pub get --enforce-lockfile`; only 8 new transitive packages, with no existing package upgrades. |
| Formatting and static analysis | Passed | 7 Dart files require no formatting changes; `dart analyze --fatal-infos` reports no issues. |
| Hardware-free automated tests | Passed | 10 CLI tests and 10 core tests after both review rounds, including parameterized error cases; injected fakes/callbacks, no actual serial operations. |
| Initial native hook attempt | Failed | Homebrew Clang 18.1.8 selected from the original PATH; linker reported `library 'System' not found`. No package/source workaround was applied. |
| Native CLI build after compiler selection | Passed | Existing Apple Clang selected through session PATH; `dart build cli --target=bin/meshctl.dart --output=build/dist` generated a macOS arm64 executable and native dylib. |
| Source CLI help/version/subcommand help | Passed | Returned `0`; existing application version remains `0.1.0-dev.1`. Help documents the possible board-reset risk and protocol boundary. |
| Source CLI real `ports` | Passed | Returned `0`, 4 distinct paths, 2 Native and 2 USB transports as reported by the library, no warnings. No port was opened. Raw paths and unique identifiers are intentionally not retained here. |
| Unknown command and missing `--port` | Passed | Source processes returned `64`, empty stdout, brief stderr diagnostics, no stack trace. |
| Bundle help/version/real `ports` | Passed | Returned `0`; enumeration returned 4 paths and no warnings. Bundle includes `bin/meshctl` and `lib/liblibserialport_plus.dylib`, both Mach-O arm64. |
| Complete bundle outside the repository | Passed | Copied the entire bundle to a newly created directory under `/private/tmp`; from that directory, version and real enumeration returned `0`, with 4 port records and no stderr. No pub-cache library path was configured. |
| Missing native asset in a separate temporary copy | Passed | Removing only that copy's dylib made `ports` return `69`, empty stdout, and an actual native-load error without a stack trace. |
| Explicit real-device open/close | Passed | Source CLI checked the user-selected `/dev/cu.usbmodem211101` and returned `0`; open state and closed state were checked and native resources were disposed before success. |
| Reopen the same real port after release | Passed | After a 10-second stabilization interval, a second source CLI invocation on the same path returned `0`; it opened, closed, and disposed the port again. |
| Restricted-sandbox bundle device attempt | Failed | Reported `SerialPortException: Operation not permitted (code: 1)`. This attempt did not produce a success result; the approved-access check below passed. |
| Bundle real-device `port-check` | Passed | After a further stabilization interval, the bundle checked the same selected port using the same approved execution access as the source CLI and returned `0`. |
| Remote Ubuntu CI | Not run | Workflow updated, but not dispatched or observed for these changes. |
| Clean-machine relocation and other operating systems | Not run | Only moving the bundle on the same local macOS host was verified. |

Enabled metadata enumeration does not open serial ports; native Linux/Android/Windows enumeration is now rejected before entering backends that can implicitly open ports. Metadata handles are explicitly disposed, even when metadata access fails. Automated lifecycle tests verify close/dispose sequencing, release after failed open, and that cleanup errors do not replace the primary expected error. The selected-port checks above add limited real-device evidence; unplugging during access, general driver failures, and other permission environments remain unverified.

## Selected-port execution record

The checks ran on November 8, 2026, on the macOS arm64 host described above. From `apps/meshctl`, the following source command was run twice, with a 10-second interval after the first successful check:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
dart run bin/meshctl.dart port-check --port /dev/cu.usbmodem211101
```

After another stabilization interval, the compiled bundle was checked against the same port:

```bash
build/dist/bundle/bin/meshctl port-check --port /dev/cu.usbmodem211101
```

The restricted-sandbox bundle attempt failed with the permission diagnostic recorded above. With approved device access, both source invocations and the bundle invocation exited with `0` and printed:

```text
Serial port opened and closed successfully: /dev/cu.usbmodem211101
MeshCore protocol support has not been checked.
```

No serial data was read or written, and no baud rate, flow control, DTR/RTS, or radio settings were explicitly changed. Board-reset behavior was not independently observed. Device identity, firmware, and target CPU architecture remain unconfirmed. No MeshCore protocol, session, or LoRa check was performed.

## Review follow-up

On November 8, 2026, all three review findings were confirmed against the installed `libserialport_plus` 1.0.5 Dart and C sources and fixed in the Meshchan adapter, without changing the dependency or pub cache:

- A successful open now retains cleanup ownership even when the wrapper reports the open state as false. The strengthened regression failed against the previous code because no close occurred, then passed after the fix. Descriptor `0` is still reported as a validation failure by the pinned wrapper, but the port is closed and the native finalizer detached before disposal.
- Native open failures now attempt one recovery close, including when a descriptor was acquired before a lock/exclusivity failure. An already-closed error is tolerated only in this recovery path. Other cleanup errors are appended without replacing the original failure.
- Display metadata removes known USB serial numbers, including full and truncated Linux description suffixes. Exact system paths and non-unique metadata such as VID/PID remain available.

| Follow-up check | Status | Actual result |
| --- | --- | --- |
| Format, analysis, and hardware-free regressions | Passed | Formatting unchanged after formatting the two edited Dart files; analysis reports no issues; 7 core and 10 CLI tests pass. |
| Rebuilt native bundle | Passed | macOS arm64 build completed with the existing dependency and native asset. |
| Source and rebuilt bundle enumeration | Passed | Both returned `0` and 4 port records without warnings; no ports opened by enumeration. |
| Source real-device check after fixes | Passed | `/dev/cu.usbmodem211101`, explicitly authorized again by the user, opened, closed, and disposed successfully; exit `0`. |
| Rebuilt bundle reopening after source release | Passed | After a 10-second interval, the rebuilt bundle checked the same port successfully; exit `0`. Both invocations used approved device access. |
| Complete rebuilt bundle outside the repository | Passed | A new complete copy under `/private/tmp` returned `0` for version and real enumeration, with 4 port records and no stderr. |
| Forced descriptor `0`, native lock failure, and Linux-host execution | Not run | Edge paths and Linux description projection were covered with hardware-free callbacks/data; they were not forced on physical hardware or a Linux host. |
| Remote Ubuntu CI for review fixes | Not run | The existing workflow already includes both test suites and bundle checks; no remote run was dispatched. |

The real-device follow-up tested normal open/close behavior only. It did not read/write data, explicitly configure serial settings, identify the board or firmware, or check MeshCore or LoRa support.

## Platform and metadata review follow-up

On November 8, 2026, another review was checked against the installed 1.0.5 source. Its Linux backend opens `serial8250` candidates during enumeration; its Windows `isOpen()` passes four bytes to a native function that writes an eight-byte handle on 64-bit Windows; and its native metadata getter can throw `FormatException` for invalid UTF-8. Inspection also found that Windows metadata initialization opens USB serial ports to wake them.

The adapter now rejects Linux/Android enumeration and both Windows native diagnostics before the unsafe native entry point. These operations return `69`; rejection must not be recorded as successful enumeration. A narrowly scoped metadata decoder converts invalid UTF-8 to a per-port warning, preserving its path, disposing its handle, and allowing other records to continue. Programming errors and formatting errors outside that getter are not broadly translated.

| Follow-up check | Status | Actual result |
| --- | --- | --- |
| Existing baseline | Passed | 17 hardware-free tests, formatting, static analysis, and locked dependency resolution. |
| Updated formatting, analysis, and tests | Passed | 10 core and 10 CLI tests; zero formatting changes after formatting the edited files; no analyzer issues. |
| Platform safety guards | Passed | Hardware-free platform/callback tests verify that Linux/Android enumeration and Windows enumeration/creation never invoke their native callback; allowed macOS operations still invoke it. |
| Malformed UTF-8 metadata | Passed | A real Dart UTF-8 decoder rejects a truncated sequence; the metadata boundary turns it into a warning, keeps both enumerated paths, and disposes both handles without opening either. |
| macOS source enumeration | Passed | Returned `0`, 4 distinct port records, no warnings. |
| Rebuilt macOS arm64 bundle | Passed | Native build succeeded; executable and dylib confirmed as Mach-O arm64. |
| Rebuilt bundle help/version/enumeration | Passed | All returned `0`; enumeration returned 4 records with no stderr. |
| Complete rebuilt bundle outside the repository | Passed | A new complete copy under `/private/tmp` returned `0` for version and enumeration, with 4 records and no stderr. |
| Updated Ubuntu CI script syntax | Passed | Workflow YAML parsed; extracted shell and embedded Python passed syntax checks locally. Linux commands were not executed on macOS. |
| Actual Linux/Android/Windows execution | Not run | Guard ordering was tested with injected platform values; no corresponding OS process or device result is claimed. |
| Remote Ubuntu CI | Not run | Workflow updated to require the real source/bundle Linux safety rejection with exit `69`; no remote run was dispatched. |
| New real-device open/close in this review round | Not run | Earlier selected-port results remain recorded above; this round validated platform gates and metadata recovery without another device open. |

Ubuntu CI still requires the real native build to succeed. Its `ports` acceptance check now verifies refusal to use the unsafe backend, rather than native enumeration or runtime native library loading. This is a necessary change from the original Linux enumeration goal while the pinned dependency remains unchanged. No system serial library, new FFI, package-cache patch, or fake CI enumeration was introduced.

## Real-device checklist

Read `port-check --help` before selecting a target. Opening or closing a serial port can reset some development boards through driver or control-line behavior, even though Meshchan does not explicitly configure those lines. Do not batch-open candidates or automatically choose the first enumerated path.

From the repository root:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
cd apps/meshctl
dart run bin/meshctl.dart ports
dart run bin/meshctl.dart port-check --help
```

Only after explicitly selecting the target, set `MESHCHAN_PORT` to its exact enumerated path. The following guard prevents an unset or empty variable from becoming a check request:

```bash
: "${MESHCHAN_PORT:?Set MESHCHAN_PORT to the explicitly selected port path}"
dart run bin/meshctl.dart port-check --port "$MESHCHAN_PORT"
```

After the board state has stabilized, execute the same command once again to verify release and reopening. Do not use a rapid loop. If appropriate, check the native bundle against the same selected port:

```bash
: "${MESHCHAN_PORT:?Set MESHCHAN_PORT to the explicitly selected port path}"
build/dist/bundle/bin/meshctl port-check --port "$MESHCHAN_PORT"
```

Record the actual date, host, command exit code, whether close/dispose completed, and the second-open result. Record target firmware and CPU architecture only when independently confirmed. Do not record USB serial numbers or Bluetooth MAC addresses for this step.

A successful check must say that the serial port opened and closed and that MeshCore protocol support has not been checked. It proves no MeshCore identity, session, data transfer, or LoRa capability. Step 3 remains outside this task.
