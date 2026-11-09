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

A successful check must say that the serial port opened and closed and that MeshCore protocol support has not been checked. It proves no MeshCore identity, session, data transfer, or LoRa capability. Step 3 remains outside this historical Step 2 validation.

## Step 4 transport validation boundary

On November 9, 2026, Step 4 added the serial transport, hardware-free lifecycle
tests, and an explicit-port [read-only observation example](protocol/serial-transport.md).
During the initial software validation, no new hardware access was authorized or
performed: no enumeration, port check, reader, configuration, or native TX operation
ran against a device. The Step 2
results above remain unchanged historical diagnostic evidence and do not establish
Step 4 transport operation. Native builds and simulated tests are recorded in the
[Developer Guide](development.md#serial-transport-step-4). At that point, live reader/configuration,
driver disconnect handling, native TX, device identity, Companion handshakes, and
LoRa reception/round trips were **Not run / Pending hardware validation**.

### Authorized read-only follow-up on November 9, 2026

The user subsequently requested hardware testing and enumeration, then explicitly
selected `/dev/cu.usbmodem211101` for 115200/8N1 configuration, a three-second
read-only observation, and shutdown. This authorization did not include sending
bytes. The environment remains macOS arm64, direct bundled Dart 3.13.7, and
`libserialport_plus` 1.0.5, on the Step 4 worktree based on `ec2a98a`.

| Check | Status | Actual result |
| --- | --- | --- |
| Source CLI `ports` after authorization | Passed | Exit 0; four serial paths, including two USB entries, no warnings. No port was opened by enumeration. |
| Initial source transport observation attempts | Failed | Both the restricted attempt and the attempt with tool-approved device access returned 69 with a generic opening I/O error. Neither printed the local-open success message; zero frames were reported. The example did not expose each attempt's underlying native cause. |
| Existing `port-check` on the selected path | Failed | With tool-approved device access, exit 69 and `SerialPortException: Resource busy (code: 16)`. No data or explicit configuration was sent by this diagnostic. |
| Open-file ownership inspection | Inconclusive | `lsof -nP` for the selected `cu` node and its paired `tty` node returned 1 without output. No visible owner was identified; this is not proof that the port was free. No process was stopped. |
| Source observation after user-confirmed release | Passed | With tool-approved device access, local open/configuration succeeded; two complete Companion content buffers of 50 and 47 bytes arrived during the three-second window; exit 0. Successful result recorded at 05:01 UTC. |
| Normal reader stop and native cleanup | Passed | The source example awaited transport close before returning. Reader stop and natural stream completion preceded subscription cancellation and native close/dispose; no cleanup error or hang was observed. |
| Native TX, forced disconnects, and bundled-example hardware execution | Not run | No send operation or forced device removal was performed. The existing AOT bundle result remains build-only evidence. |
| Device identity, firmware, Companion commands, and LoRa | Not run | Opaque frame lengths establish none of these capabilities. |

Using the current-process PATH `/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`,
the source observation command was run from `packages/meshcore_link`:

```bash
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart run \
  example/serial_transport_check.dart /dev/cu.usbmodem211101
```

After the user released the busy port, its output included:

```text
Local serial port opened; observing for 3 seconds.
Frame 1: 50 content bytes.
Frame 2: 47 content bytes.
Observation ended: 2 frames. Zero frames is valid.
```

No payload bytes, device identity, or keys were printed or retained. No
`sendFrame()`, test character, query, startup command, flush, drain, break, or
explicit DTR/RTS change was performed. Driver-induced board reset behavior was
not independently observed. This single source run validates the observed normal
receive/shutdown path only; it does not generalize to every driver or platform.

## Step 5 authorized command probe on November 9, 2026

After the Step 5 software validation, the user requested a real USB test on the
explicit path `/dev/cu.usbmodem211101`. The probe used the existing
`SerialTransport` at 115200/8N1 and the new public codec APIs, with one
DEVICE_QUERY (`appTargetVersion: 3`) followed by one APP_START (`Meshchan`). Target
3 is an explicit test choice, not a product default or a claim of complete
protocol-version support. DEVICE_QUERY can change the firmware's session target
version. No radio, time, position, contact, or channel settings are requested.

A temporary ignored Dart script under
`packages/meshcore_link/.dart_tool/step5_hardware_probe.dart` passed focused static
analysis and an argument guard that performs no hardware access. It subscribes
before opening, allows one second for startup, waits at most five seconds for
each expected response, and awaits transport shutdown before canceling the
subscription. It uses structural response/error summaries only, retaining no
capture file or device payload. It adds no product session layer, CLI command,
retry, or change to the existing read-only example.

The probe used the same Homebrew SDK's direct Dart 3.13.7 binary and locked
`libserialport_plus` 1.0.5. Its historical execution command from the repository
root was:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart run \
  packages/meshcore_link/.dart_tool/step5_hardware_probe.dart --run-authorized-probe
```

The temporary script was removed after this test; it is not a committed example
or a new product initialization executor.

| Attempt | Actual result |
| --- | --- |
| Restricted execution at 10:00:34 UTC | Exit 69: native open rejected with `Operation not permitted (code: 1)`. Zero frames, no commands sent, awaited cleanup passed. |
| Device-access execution at 10:00:54 UTC | Exit 69: native open rejected with `Resource busy (code: 16)`. Zero frames, no commands sent, awaited cleanup passed. |
| Read-only ownership inspection at 10:01 UTC | `lsof -nP` on the selected `cu` path and its paired `tty` path found Brave PID 44377 holding the selected `cu` node. No process was stopped or browser connection closed. |
| User-confirmed release, device-access execution at 10:02:52..10:02:54 UTC | Exit 0. Local serial open/configuration succeeded. Each command was sent once; no retry was performed. |
| DEVICE_QUERY / DEVICE_INFO | Local send completed; a complete 82-byte DEVICE_INFO response parsed successfully. The device reported protocol code 14, distinct from the test's app target 3. Only the supported known prefix was interpreted; full protocol-14 support is not claimed. |
| APP_START / SELF_INFO | Local send completed; a complete 64-byte SELF_INFO response parsed successfully, including the required 58-byte prefix. No names, keys, coordinates, PIN, or payload dump were printed. |
| Reception and normal shutdown | Two complete frames, zero parser failures, both expected response types observed. Awaited transport cleanup succeeded before subscription cancellation; no cleanup hang or failure occurred. |

The successful run's structural summary was:

```text
Received: DeviceInfoResponse(protocolVersion: 14, contentLength: 82)
DEVICE_INFO parse: PASS.
Received: SelfInfoResponse(opcode: 5, contentLength: 64)
SELF_INFO parse: PASS.
Awaited transport cleanup: PASS.
Summary: frames=2; parserFailures=0; deviceInfo=true; selfInfo=true; cleanup=true.
```

This is limited evidence that these two USB Companion commands produced their
expected response types through the existing framing/transport and new parser on
this selected port. It adds local command TX/response evidence to Step 4's earlier
passive reception record. The initial failed opens remain failures. It does not
establish authenticated identity, independently verified firmware identity, full
protocol-version compatibility, automated session management, reconnect behavior,
forced-disconnect recovery, LoRa transmission, or a radio round trip. No device
capture was saved, and no other serial port was enumerated or opened.

## Step 6 session validation boundary on November 9, 2026

Step 6 implements callable `MeshCoreSession` initialization and error handling.
Initial acceptance used a fake transport, synthetic responses, and virtual-time tests;
the [development record](development.md#companion-session-step-6) separates those
software results from existing-product build regressions. No real serial port
was enumerated, opened, configured, or sent initialization commands during this
initial software acceptance. No process or browser connection was stopped.

The Step 5 record above remains unchanged evidence of its separately authorized
temporary two-command probe. It does not establish hardware acceptance of the new
session implementation. At the end of initial acceptance, session hardware and
AOT execution were **Not run / Pending**. The subsequent authorization and actual
session runs are recorded below. CLI `info` and `watch` are not added.

### Authorized session hardware follow-up on November 9, 2026

The user then explicitly selected `/dev/cu.usbmodem211101` for real session tests,
stating that it was a dedicated test device and authorizing configuration changes
as needed. The test used the public `MeshCoreSession` itself, not the Step 5
two-command probe. Production initialization policy and code were unchanged.

Environment: macOS arm64, existing Homebrew SDK direct Dart 3.13.7, locked
`libserialport_plus` 1.0.5. The selected node existed; no port enumeration was
needed. All hardware invocations had tool-approved device access. No process or
browser connection was stopped. A selected-node `lsof` check between failed
attempts returned 1 with no visible owner; that is not proof of exclusive access.

A temporary ignored `.dart_tool/step6_hardware_session.dart` in the core package
provided an explicit run flag and selected-port argument. It passed focused
fatal-info analysis and a no-argument exit-64 guard before use. Its transport
wrapper counted and summarized sends and complete received content while
delegating actual I/O to the unchanged `SerialTransport`. One session owned one
receive subscription. The wrapper added no command, raw capture, parallel reader,
retry, or protocol parser. Only structural summaries were printed.

All runs used app name `Meshchan`, app target 3, serial 115200/8N1, request budget
5 seconds, and initialization budget 15 seconds. Each attempt used a new
transport/session, and close completed before the next attempt. Startup delay was
an explicit caller setting; the session default remains zero.

| Attempt and UTC interval | Result and cleanup |
| --- | --- |
| Source, delay 0 ms, 10:54:29.530..10:54:34.869 | Exit 69. DEVICE_QUERY sent once and locally accepted. Three unassociated frames: `0x88`/81 bytes, `0x88`/132 bytes, `0x3E`/68 bytes. No DEVICE_INFO; requestTimeout on command `0x16`, expected `0x0D`. No APP_START, ready, or partial info. Awaited close succeeded; state remained failed. |
| Source, delay 1000 ms, 10:55:15.893..10:55:22.157 | Exit 69. Two unassociated startup frames (`0x88`/149 bytes, `0x80`/33 bytes), then DEVICE_QUERY/82-byte DEVICE_INFO succeeded. APP_START's local send completed, but no SELF_INFO arrived within its request budget. requestTimeout on command `0x01`, expected `0x05`; no ready. Awaited close succeeded; state remained failed. |
| Source, delay 3000 ms, 10:56:48.532..10:56:51.886 | Exit 0. Both commands locally sent once, 82-byte DEVICE_INFO with raw protocol code 14, 64-byte SELF_INFO. Two complete frames total. Ready after 3331 ms including startup delay. Full expected state sequence and awaited cleanup passed. |
| AOT, delay 3000 ms, 10:57:44.562..10:57:47.955 | Exit 0. Fresh session reopened the same port after source cleanup. Startup pushes `0x88`/148 bytes and `0x80`/33 bytes were summarized without extra sends; both expected responses then arrived at 82 and 64 bytes. Ready after 3378 ms including startup delay. Four complete frames total; full expected state sequence and awaited cleanup passed. |

The first harness summary incorrectly printed `cleanup=false` because its check
also required state closed, although a faulted session intentionally remains
failed. The preceding awaited-close message showed success. The harness summary
was corrected to check actual cleanup completion/errors separately from the
successful lifecycle assertion. This was a temporary test-harness correction,
not a production session change. The failed initialization remains a failed run.

Historical source invocation from `packages/meshcore_link`:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart run \
  .dart_tool/step6_hardware_session.dart \
  --run-authorized-session /dev/cu.usbmodem211101 3000
```

The zero-delay run omitted the final optional delay argument, and the one-second
run supplied `1000`. The actual session API performed all initialization.

The same harness was compiled with `dart build cli` using the direct SDK binary,
target `.dart_tool/step6_hardware_session.dart`, and output
`build/step6-hardware-session`. Build succeeded. A no-argument run of the compiled
bundle returned 64 before I/O; the authorized hardware invocation was:

```bash
build/step6-hardware-session/bundle/bin/step6_hardware_session \
  --run-authorized-session /dev/cu.usbmodem211101 3000
```

Both successful runs observed:

```text
opening -> initializing -> ready -> closing -> closed
appTarget=3; reportedProtocol=14; deviceInfoBytes=82; selfInfoBytes=64
opens=1; sends=2; closes=1; sharedClose=true; result=PASS
```

The harness verified that connect's result was the session's published info,
lastFailure was null at ready, the send order was DEVICE_QUERY then APP_START,
cleanupFailures was empty, repeated close returned the same Future, and the
underlying close was invoked once. Its source was removed after validation. The
AOT bundle remains an ignored local build artifact; no product CLI was added.

This supplies observed source and AOT initialization/normal-cleanup evidence for
one selected device with an explicit three-second delay. It does not establish
the root cause of the earlier timeouts, a universal delay requirement, or a
long-term success rate. The raw protocol code 14 is distinct from app target 3 and
does not imply full protocol-14 support. No names, model/firmware text, public
keys, PIN, coordinates, or payload dumps were logged or saved as a capture.

Only the two initialization command types were sent. No firmware update,
factory reset, explicit DTR/RTS change, flush, radio/time/contact/channel setting,
private-key operation, or LoRa transmission test was performed. The device may
have emitted unsolicited radio-related notifications; those do not establish
LoRa communication acceptance. Forced disconnects, hardware cleanup failures or
hangs, other operating systems, and remote CI remain unverified.

### Session timeout investigation on November 9, 2026

The user requested investigation of the zero- and one-second failures, including
fixes if the session or serial implementation was responsible. Testing continued
on the same explicitly authorized dedicated device. Production session, framing,
codec, native adapter, defaults, and dependencies were left unchanged while the
failure boundary was investigated. All device runs were serialized and used the
existing direct Homebrew Dart 3.13.7 or Python 3's standard library.

**Confirmed failure boundary:** the host can receive a complete three-byte serial
header declaring 64 content bytes, then receive none of that response body within
five seconds. This was reproduced outside `MeshCoreSession`, `SerialTransport`,
`SerialPortReader`, Dart, and libserialport, using a small independent POSIX
control with `os.open`, raw 115200/8N1 termios settings, `os.write`, `select`, and
`os.read`. Thus the captured SELF_INFO failure is not caused by Dart response
matching, an unsubscribed receiver, or this reader failing to assemble already
delivered bytes. The underlying device/USB/host-driver delivery path still has an
intermittent issue; a particular firmware or driver defect has not been proven.

Evidence, recorded in UTC:

| Experiment | Actual observation |
| --- | --- |
| Native-boundary Dart tracing, source, 11:02:27 and 11:03:45, delay 0 | Both passed. DEVICE_QUERY and APP_START native writes accepted the exact expected 5 and 19 framed bytes; native input contained complete 82-byte DEVICE_INFO and 64-byte SELF_INFO. |
| Buffered native tracing, source, 11:03:26 and 11:07:15, delay 1 second | Both passed. Logs were buffered until cleanup to reduce diagnostic I/O effects. No fixed startup requirement was established. |
| Unchanged earlier AOT harness, 11:04:43..11:04:48, delay 0 | DEVICE_INFO completed, APP_START local send completed, then requestTimeout waiting for SELF_INFO. Close succeeded. |
| Native-boundary tracing, AOT, 11:05:36..11:05:41, delay 0 | Expected writes accepted 5 and 19 bytes. After DEVICE_INFO, the reader delivered a three-byte chunk and no further bytes before timeout. Session stayed failed; native reader stop preceded close/dispose. |
| Independent POSIX control, 11:08:14, delay 0 | DEVICE_INFO arrived in full. APP_START accepted all 19 framed bytes. The next read contained exactly the header for length 64, with zero body bytes. Five seconds elapsed without the body; control initialization failed with exit 69 and closed. |
| Independent POSIX control, 11:09:35, delay 1 second | Same header-only 64-byte stall for five seconds. One explicitly diagnostic DEVICE_QUERY was then sent; the missing 64-byte SELF_INFO body arrived about 0.5 ms later. The original initialization remained a failure. This extra query exists only in the temporary control, not in the session. |
| Restored-original-name native-traced AOT, 11:13:17 and 11:13:28 | Delay 0 and delay 1 second both passed with the original 64-byte response, confirming intermittency rather than a deterministic short-delay failure. |

The release experiment demonstrates delayed delivery rather than a response that
the session had already received and discarded. The fixed firmware baseline's
[serial writer](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ArduinoSerialInterface.cpp)
submits the three-byte header and content with separate writes. A 64-byte-body
USB short-packet/ZLP or flush-completion issue is consistent with the observation,
but **that mechanism is an inference**. No USB bus trace, firmware-side trace, or
other-host comparison was obtained, so firmware versus macOS USB-driver
responsibility is not distinguished. The exact loaded firmware source revision
was not independently established.

#### Controlled response lengths and actual session retests

Under the user's configuration authorization, the independent control retained
the original six name bytes only in memory, temporarily changed the node
name length, and restored the exact original bytes in `finally`. No original
name, key, PIN, location, model text, firmware text, or payload capture was saved
or printed. A name-setting acknowledgment and a subsequent SELF_INFO comparison
verified restoration after each experiment. No radio parameters were changed.

The first experiment, 11:11:22..11:11:26, made SELF_INFO 65 bytes and ran the
unchanged existing AOT session harness with fresh transports/sessions:

| Startup delay | Repetitions | Result |
| --- | --- | --- |
| 0 | 2 | Both passed; connect took 232 and 219 ms. |
| 1 second | 2 | Both passed; connect took 1221 and 1216 ms including delay. |

Every run had one open, one DEVICE_QUERY, one APP_START, complete ready info, the
expected state sequence, one underlying close, and a shared close Future.
The original name and original 64-byte response length were then restored and
verified. This was a diagnostic configuration change, not a permanent workaround
or a new operation performed by `MeshCoreSession`.

A second fixed comparison, 11:14:25..11:14:29, held the independent POSIX port
open and tested three trials at each response length. Here an immediate result
means that the body arrived within the control's one-second observation window,
before any diagnostic release query; this is separate from the product's
five-second request deadline:

| SELF_INFO body length | Immediate results | Stalled results |
| --- | --- | --- |
| 63 bytes | 3/3 | 0 |
| 64 bytes | 2/3 | 1; only the three-byte header arrived, then an explicit diagnostic query released the body. |
| 65 bytes | 3/3 | 0 |

Restoring and verifying the original 64-byte response reproduced another
header-only stall, again released by the diagnostic query. Restoration verified
`originalNameMatches=true` and `selfBytes=64`; the control then closed normally.
These small samples support a 64-byte-boundary correlation, not a universal
success rate or proof that other lengths cannot be affected.

#### Client findings, regression, and remaining limits

No client implementation defect was demonstrated by these captures, so no sleep,
extra command, retry, response-type relaxation, serial flush, or forced resource
release was added. The product default remains zero startup delay, and the
original device name is restored. In particular, the earlier three-second
successes should not be treated as a fix for the USB delivery behavior.

One new hardware-free integration regression uses the real `MeshCoreSession`,
`SerialTransport`, framing, and Companion decoder with the existing synthetic
native connection. With a standalone header declaring a 64-byte SELF_INFO body,
the session remains initializing. A body delivered before the deadline completes
ready; a missing body produces requestTimeout, performs one cleanup, and a late
body cannot revive the session. Both cases send exactly the two initialization
commands, with no automatic release query. Time budgets use `fake_async`.

The historical first zero-delay DEVICE_QUERY timeout had only content-level
summaries. Its exact cause was not separately reproduced with a native capture;
the SELF_INFO findings must not be presented as proof of that individual query
timeout's cause. USB-side instrumentation or a cross-host test would be needed
to assign the delayed-body issue to a specific firmware or host-driver mechanism.
No firmware was flashed or USB-driver/SDK/cache source modified. The temporary
diagnostic sources were removed after recording the results; ignored AOT build
artifacts are not product commands. No LoRa transmission test was performed.
