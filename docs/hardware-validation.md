# Hardware validation record

Current status on November 9, 2026: the initial [Step 9 basic matrix](#step-9-device-acceptance-on-november-9-2026)
passed H2–H7. Three separately authorized H10 startups failed before ready, most
recently [attempt 3](#step-9-h10-third-startup-on-november-9-2026); all cleanups
succeeded. A separate manual replug sequence had R1 info FAIL/R2 info PASS.
Ready-state disconnect detection and the full H10 recovery cycle remain untested;
recommendation is development with known limitations. Historical evidence below
is retained, including the earlier successes and failures.

## Historical Step 2 validation

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

## Step 7 CLI validation boundary on November 9, 2026

Step 7 connects the existing session to `info` and `watch`. Initial acceptance
authorized software-only checks: fake transport tests, hardware-free process checks,
and native builds. No real enumeration, port check, valid-port session, or
valid-port read-only example ran. Earlier selected ports and configuration
permissions were not reused. The historical records above are unchanged evidence
of their own separately authorized tasks.

See the [actual Step 7 software results](development.md#diagnostic-session-cli-step-7)
and [manual CLI acceptance checklist](cli.md#manual-hardware-acceptance).
At that point, Step 7 CLI hardware behavior was **Not run / Pending explicit authorization**.
The intermittent USB body-delay cause, hardware cleanup failure/hang behavior,
and LoRa round trips remain unverified; this step adds no device workaround.

## Step 7 authorized CLI hardware follow-up on November 9, 2026

After software acceptance, the user explicitly requested a device test on
`/dev/cu.usbmodem211101`. This new authorization was used only for that exact
port. No enumeration, preliminary port-check, alternate path, read-only example,
third-party process termination, browser disconnection, or configuration change
was performed. The worktree remained on `master` at Step 6 merge
`e27c024850ea80c8b3537f9c6aaf41895cbd812e`, with the uncommitted Step 7 changes.
The CLI native bundle was rebuilt from this worktree before hardware execution
and reported application version `0.1.0-dev.1`.

Environment: macOS 27.2 arm64, the same Homebrew SDK's direct Dart 3.13.7,
Apple Clang 21.0.0, and locked `libserialport_plus` 1.0.5. The selected character
device existed. Hardware execution had tool-approved device access. All six
invocations ran serially with app target 3, app name `Meshchan`, request budget
5 seconds, total initialization budget 15 seconds, and startup delay 0 ms.
Each invocation used the product CLI and its actual session/serial transport;
there was no replacement handshake, transport wrapper, extra query, or retry.

An external Python 3 harness launched the source or complete native CLI bundle,
parsed JSON/NDJSON only in memory, and retained structural summaries. It checked
ready snapshot fields and prefix format without printing or saving device names,
model/firmware text, keys, PIN, positions, or payloads. Source build-hook progress
was treated as prelaunch stderr. It waited for natural process completion without
a cleanup timeout or forced kill. The two cancellation checks sent signals only
to the child CLI processes created by this harness, immediately after their
ready record was received. No unrelated process received a signal.

| Case and start time (UTC) | Actual result |
| --- | --- |
| Source `info --json --verbose`, 14:51:16.397 | **Initialization failed**, exit 69 after 6.528 s including source startup. One requestTimeout diagnostic at initializing, command `0x16`, expected `0x0D` (DEVICE_QUERY / DEVICE_INFO). Stdout remained empty; no successful snapshot. No cleanup failure diagnostic. |
| Source `watch --json --duration 5`, 14:51:22.926 | **Passed**, exit 0 after 6.103 s including source startup. One valid ready snapshot, app target 3, reported protocol code 14. Five state records, one end, no failure, zero NDJSON parse errors. Observed ready-to-end interval 5.099 s, including cleanup/output. End: reason duration, exitCode 0, cleanup succeeded. |
| Native bundle `info --json`, 14:51:29.029 | **Initialization failed**, exit 69 after 5.494 s. One requestTimeout diagnostic at initializing, command `0x01`, expected `0x05` (APP_START / SELF_INFO). Stdout remained empty; no successful snapshot. No cleanup failure diagnostic. |
| Native bundle `watch --json --duration 5`, 14:51:34.524 | **Passed**, exit 0 after 5.325 s. One valid ready snapshot, target 3, reported protocol code 14; five states, one end, no failure, zero NDJSON parse errors. Ready-to-end interval 5.084 s, including cleanup/output. End: duration, 0, succeeded. |
| Native bundle watch, SIGINT after ready, 14:51:39.849 | **Passed**, exit 130 after 0.257 s. One ready, five states, one stopping notice, one end, no failure. End: sigint, 130, succeeded. Ready-to-end interval approximately 0.011 s. |
| Native bundle watch, SIGTERM after ready, 14:51:40.107 | **Passed**, exit 143 after 0.253 s. One ready, five states, one stopping notice, one end, no failure. End: sigterm, 143, succeeded. Ready-to-end interval approximately 0.010 s. One initializing-stage unassociated response was summarized as opcode `0x88`, contentLength 84; no body was retained or displayed. |

Each of the four watch runs observed opening, initializing, ready, closing,
and closed in that order. Every completed line parsed independently as the
expected schemaVersion-1 watch object, and end.exitCode matched the process exit.
Both failed info runs returned naturally after the CLI's awaited close path,
without cleanup errors; subsequent invocations successfully reopened the same
selected port. This supports the observed cleanup/reopen behavior, not a claim
that the port is globally unowned or every driver cleanup path is safe.

The outcome is **four passing watch/cancellation checks and two failed info
initializations**. Correct exit-69 handling and empty stdout do not convert the
info attempts into successful hardware initialization. No successful hardware
info snapshot was obtained in this follow-up. No additional info invocation was
made to hide those failures, and no timeout or startup-delay setting changed.

Historical intermittent response delivery remains a limitation. The current
SELF_INFO timeout has the same command/expected-response stage as some earlier
failures, but this harness observed only CLI structural data: it did not capture
a serial header or prove that a 64-byte body stalled in this particular run.
The DEVICE_INFO timeout's cause is also unconfirmed. A firmware, USB, driver,
or client root cause is not established by these outcomes. No repair query,
flush, name change, reset, retry, or forced resource release was attempted.

This verifies source/native watch initialization, structured output, duration,
and ready-state SIGINT/SIGTERM cleanup on this selected device for these runs.
Text-mode hardware output, cancellation before ready, output-consumer failures,
forced disconnects, hardware cleanup failures/hangs, long-term reliability,
other devices/platforms, and remote Actions were not tested in this follow-up.
Ready still does not establish authenticated identity, full protocol-14 support,
or LoRa transmission/reception. No implementation, dependency, version, or device
configuration change was made; only validation documentation was updated.

## Step 7 CLI timeout comparison on November 9, 2026

The user explicitly requested continued investigation on
`/dev/cu.usbmodem211101`, including a minimal fix if a client defect was found,
without retries, larger timeouts, or device configuration changes. The existing
Step 7 worktree and product bundle were preserved. No implementation, dependency,
version, app target, serial setting, startup-delay default, or device configuration
was changed during this investigation. No enumeration, preliminary port-check,
alternate port, reset, flush, repair query, firmware update, or process termination
was used. All sessions completed their own cleanup before the next invocation.

### Method and scope

Code inspection confirmed that both commands use the same argument-to-session
mapping, subscribe before connect, and immediately observe the same connect
Future. Their successful-result behavior branches only after full initialization:
info requests shared close and later prints a snapshot; watch prints ready and
starts its observation timer. Watch's asynchronous output flush worker does not
pause the session/transport receive subscription or gate initialization.

The experiment used a fixed sequence, chosen before execution rather than adding
attempts until one succeeded:

1. Unmodified product AOT CLI: watch, info, info, watch.
2. Traced actual CLI with memory sinks: info, watch, watch, info.
3. The same traced actual CLI with real stdout/stderr IOSinks: info, watch,
   watch, info.

All twelve invocations used the same selected port, app target 3, `Meshchan`,
5-second request budget, 15-second initialization budget, and zero startup delay.
Watch used duration 1 second after ready solely to bound the observation phase;
it did not change initialization budgets. All commands requested JSON. Each
invocation made one session attempt without retry. Counts below describe these
finite cases, not reliability rates or statistical equivalence.

The ignored temporary probe called the real `runCli`, `MeshCoreSession`, and
`SerialTransport`. The existing internal connection-construction seam supplied
a thin delegate to the actual native connection. It buffered only monotonic
structural events until cleanup: write lengths/accepted counts, native chunk
lengths, complete frame opcode/length, send completion, and cleanup order.
A passive instance of the existing `SerialFrameDecoder` inspected those same
chunks; it introduced no replacement parser or protocol policy. Its `finish()`
reported only pending-frame byte counts after shutdown. A map on the one owned
transport stream recorded complete frame delivery without adding a second
subscription, pausing reception, or modifying input.

Memory sinks removed actual stdout/stderr flush activity during initialization;
IOSink cases retained the production output boundary. The native trace was never
printed during initialization. Instrumentation still adds small CPU/allocation
costs, so the unmodified cases were retained as controls. The probe used the same
Dart 3.13.7 and native asset dependency as the product. It passed focused fatal-info
analysis, source and AOT no-argument exit-64 guards, and a fresh native build before
device use. All device processes had tool-approved access. The external Python 3
runner waited for natural completion without a forced cleanup timeout or kill.
Raw input, device text, keys, PIN, positions, and payloads were not logged or saved;
only structural projections were retained. No independent POSIX control or USB
bus capture was performed in this round.

### Fixed hardware outcomes

All times below are UTC on November 9, 2026; elapsed time includes process startup
and cleanup. Successful info objects had schemaVersion 1, the exact selected
port, `sessionClosed: true`, and reported protocol code 14, distinct from target 3.
Watch end records matched their process exit code and reported cleanup succeeded.

| Case | Start UTC | Result |
| --- | --- | --- |
| 01, unmodified watch | 15:04:19.069 | Exit 0, 1.457 s; one ready and duration end. |
| 02, unmodified info | 15:04:20.527 | Exit 0, 0.264 s; valid closed snapshot. |
| 03, unmodified info | 15:04:20.792 | Exit 0, 0.259 s; valid closed snapshot. |
| 04, unmodified watch | 15:04:21.051 | Exit 0, 1.355 s; one ready and duration end. |
| 05, traced memory info | 15:04:22.407 | Exit 69, 5.428 s; SELF_INFO requestTimeout, empty stdout. Native chunks 85 and 3 bytes; incomplete frame received 3 of 67 bytes. |
| 06, traced memory watch | 15:04:27.835 | Exit 0, 1.362 s; native chunks 85 and 67 bytes, complete DEVICE_INFO and SELF_INFO, duration end. |
| 07, traced memory watch | 15:04:29.198 | Exit 0, 1.417 s; native chunks 85 and 67 bytes, complete responses, duration end. |
| 08, traced memory info | 15:04:30.616 | Exit 0, 0.256 s; complete responses and closed snapshot. |
| 09, traced IOSink info | 15:04:30.872 | Exit 69, 5.202 s; SELF_INFO requestTimeout, empty stdout. Native chunks 85 and 3 bytes; incomplete frame received 3 of 67 bytes. |
| 10, traced IOSink watch | 15:04:36.075 | Exit 69, 5.230 s; SELF_INFO requestTimeout, no ready, failure end with successful cleanup. Native chunks 85 and 3 bytes; incomplete frame received 3 of 67 bytes. |
| 11, traced IOSink watch | 15:04:41.305 | Exit 69, 5.111 s; DEVICE_INFO requestTimeout, no APP_START or ready, failure end with successful cleanup. One native chunk of 21 bytes; incomplete frame received 21 of 85 bytes. |
| 12, traced IOSink info | 15:04:46.417 | Exit 0, 0.269 s; complete responses and closed snapshot. |

Both commands had four successful and two failed initializations in these twelve
fixed cases. The earlier two failed info runs remain failed historical results;
the later successes do not erase them. Unmodified info can succeed without any
workaround, and watch can fail at either initialization request.

### Timing and byte-boundary evidence

For all eight traced cases, every complete frame found at the native callback
matched a frame delivered through the transport, in order. Each started send
completed once. Native writes accepted the entire expected framed byte count:
5 for DEVICE_QUERY and, when reached, 19 for APP_START. No extra send occurred.
Case 11 sent only DEVICE_QUERY because DEVICE_INFO never became complete.

| Failed case | Last send to CLI close request | Pending frame at shutdown |
| --- | --- | --- |
| 05, memory info | 5.001332 s | Header only: 3 of 67 total bytes, missing 64-byte SELF_INFO body. |
| 09, IOSink info | 5.002620 s | Header only: 3 of 67 total bytes, missing 64-byte SELF_INFO body. |
| 10, IOSink watch | 5.001467 s | Header only: 3 of 67 total bytes, missing 64-byte SELF_INFO body. |
| 11, IOSink watch | 5.002414 s | 3-byte header plus 18 of 82 DEVICE_INFO body bytes: 21 of 85 total, missing 64 body bytes. |

In case 09, for example, APP_START was requested at 114.637 ms, its complete
19-byte native write was accepted at 114.778 ms, the next native callback supplied
only the three-byte header at 221.883 ms, and close was requested at 5117.257 ms.
No further chunk arrived before or during cleanup. The reader was active; this
was not a missing subscription or a full response rejected by the CLI.

Successful traced info requested close 73 microseconds (case 08) and
132 microseconds (case 12) after delivery of complete SELF_INFO, never before it.
All eight traced cleanups had the same order: reader stop request, natural reader
done, stop completion, native port close, native disposal, transport close
completion. The failed sessions did not need to reach closed state to finish
cleanup. All twelve processes returned naturally, and later invocations reopened
the same selected port.

The captured failures therefore precede complete-frame delivery to the session
and CLI. They were not caused by info closing before initialization, a lost
complete transport frame, different request budgets, duration starting early,
or slow watch stdout preventing reception. No CLI initialization defect was
demonstrated, so no production fix was justified. These observations do not
prove every possible client/driver path correct or identify which lower layer
failed to deliver the missing bytes.

The missing 64-byte suffix is consistent with the historical independently
reproduced delivery issue, and case 11 adds an observed partial DEVICE_INFO
boundary. A USB packet/flush mechanism remains an inference, not a confirmed
firmware or macOS driver diagnosis. This round did not observe the missing bytes
at the OS API, USB bus, or firmware boundary, so responsibility among device,
USB/driver, native library, and reader-side delivery is not conclusively assigned.
The prior independent POSIX findings remain separate historical evidence.

### Regression and remaining limits

A new hardware-free CLI integration group replaces only the native connection
and runs the real framing decoder, SerialTransport, MeshCoreSession, and runCli.
Its 16 virtual-time combinations cover info/watch, DEVICE_INFO 21/85 versus
SELF_INFO 3/67 partial input, timely versus absent suffix, and ordinary versus
blocked output. A suffix arriving at 4999 ms succeeds; an absent suffix times out
at 5000 ms with correct command/expected-response metadata, and late bytes cannot
revive the command or trigger APP_START after a DEVICE_INFO failure. Tests verify
no premature ready/info/close, one cleanup in the required order, no extra sends,
ready-relative duration, and no remaining timers. Fixtures are synthetic, not
hardware captures; no native handle or real device is used by these tests.

Core's complete 68-test suite and CLI's complete 27-test suite passed serially.
The focused new group passed all 16 combinations. No dependency or lockfile
change was needed. Root formatting, fatal-info analysis, and diff checks passed.
The temporary probe source was removed from the package after validation; its
ignored native build artifact is not a product command. No extra production API,
retry, larger timeout, startup delay, repair query, reset, flush, or device
configuration change was added. This investigation does not establish LoRa,
long-term reliability, other-platform operation, or remote CI results.

## Step 7 independent POSIX comparison on November 9, 2026

The user explicitly requested an independent POSIX client on the same selected
`/dev/cu.usbmodem211101` to distinguish upstream delivery from loss inside
libserialport_plus or its reader. This followed the CLI timing investigation
above; it did not reuse historical configuration-change authorization. The
worktree stayed on `master` at `e27c024`, preserving the existing Step 7 changes.
No production source, dependency, app target, timeout policy, or device setting
was changed. No port enumeration, port-check, alternate path, extra query,
command retry, serial flush, device-name/radio/firmware change, modem-line toggle,
process termination, or forced cleanup was performed.

### Independent control and baseline

The control was a temporary Python 3.15.2 standard-library process using only
`os.open`, `os.write`, `os.read`, `select`, `termios`, and `fcntl` for device I/O.
It did not import or execute Dart, libserialport_plus, its FFI, or its reader.
Normal outgoing frames were generated beforehand by the existing Dart encoders
and serial framing API, using app target 3 and app name Meshchan. The resulting
fixture contained only the two static outgoing commands, of 5 and 19 framed
bytes; it contained no received data. The control's receive path independently
counted `>` frame boundaries and lengths, retained only the first two content
bytes for structural opcode/version/error checks, and never decoded display
text, names, keys, positions, or payloads.

Each POSIX attempt used nonblocking read/write open with O_NOCTTY/O_CLOEXEC,
flock and TIOCEXCL, then applied the same existing host tty baseline:
115200/8N1, raw input/output, CLOCAL/CREAD, no software or CTS/DSR flow control,
VMIN/VTIME 0, and HUPCL cleared. All six applied profiles were identical, including
disabled RTS/DTR flow, and no RTS/DTR output level was explicitly changed.
TCSANOW applied settings without flushing or draining. Like the existing native
transport, the control did not restore a different host line configuration at
close. The newly opened tty reported 9600 baud, HUPCL on, CLOCAL off, and VMIN 1
before configuration on all six opens; the control consistently applied the
existing 115200 baseline rather than assuming that a previous descriptor's
termios state persisted. These are host tty settings, not stored device/radio
configuration changes.

The request budget was exactly 5 seconds, registered before writing each command;
the total initialization budget was 15 seconds, starting before open. Startup
delay was zero. The nonblocking write path could advance only over an accepted
suffix, never resend an accepted prefix or restart a command. In the actual
twelve cases every command was accepted in a single write, so each attempt had
exactly one 5-byte write and one 19-byte write. Only a complete DEVICE_INFO allowed
APP_START. Unassociated input never caused another send, and earlier responses
were not pooled for a later stage.

At a request deadline, a read-only probe recorded FIONREAD, zero-wait select,
and one immediate nonblocking read, then closed. It did not wait longer, accept
late input as a successful initialization, send a release query, or flush.
With VMIN 0 an empty read can return zero bytes; this was recorded as no data,
not misclassified as proof of device disconnection. The control released its
exclusive flag and closed its own descriptor in finally. No background reader
or native pointer existed in this path, and no process timeout killed a child.

The comparison used the unchanged, reviewed AOT native-boundary probe from the
previous investigation, calling the real info command with memory output and
buffered structural tracing. Its native connection delegated to the normal
libserialport_plus path. POSIX read as soon as select reported input; no artificial
100-ms coalescing delay was added to imitate the native reader. This affects
observation granularity, so elapsed times are not a performance comparison.
The fixed sequence was POSIX/native/native/POSIX,
repeated as three blocks, chosen before hardware execution. No case was added
because a previous one failed or succeeded. Both clients kept the same command,
port, target, name, 5/15-second budgets, zero delay, and immediate close after
success or failure. They ran serially and exclusively, never as competing
readers of one descriptor. Different processes cannot observe the same individual
packet simultaneously; the comparison establishes independent reproduction,
not packet-by-packet equivalence or reliability rates.

Before hardware execution, the Python counter passed three focused self-test
groups: every two-part split of synthetic 82-byte DEVICE_INFO and 64-byte
SELF_INFO frames (154 split positions), both observed missing-64-byte shapes,
and bytewise/coalesced/noisy input plus invalid lengths. Guard checks rejected
missing and non-authorized ports with 64 before open. The outgoing-fixture helper
passed focused Dart fatal-info analysis. The existing native probe's no-argument
exit-64 guard passed. All actual device invocations had tool-approved access.

### Fixed outcomes

UTC times are on November 9, 2026. Elapsed values below are process wall time,
including interpreter/runtime startup and cleanup, not per-request budgets.
All twelve attempts completed cleanup naturally and later attempts reopened the
same port. Complete expected frames were 82-byte DEVICE_INFO (reported protocol
code 14) and 64-byte SELF_INFO; no display fields or raw receive bytes were saved.

| Case | Start UTC | Actual result |
| --- | --- | --- |
| 01, POSIX | 18:34:27.607 | Exit 0, 0.093730 s; both responses complete. One preceding unassociated opcode 0x88/125-byte frame was summarized, with no extra send. |
| 02, native | 18:34:27.702 | Exit 69, 5.275714 s; APP_START/SELF_INFO requestTimeout, complete DEVICE_INFO then only a 3-byte header declaring 64 content bytes. |
| 03, native | 18:34:32.979 | Exit 0, 0.323414 s; complete responses and closed info snapshot. |
| 04, POSIX | 18:34:33.304 | Exit 0, 0.177171 s; both responses complete. |
| 05, POSIX | 18:34:33.491 | Exit 69, 5.131784 s; APP_START/SELF_INFO requestTimeout. After APP_START, direct os.read returned only 3 bytes, declaring a 64-byte body; none of that body arrived before close. |
| 06, native | 18:34:38.623 | Exit 0, 0.263311 s; complete responses and closed snapshot. |
| 07, native | 18:34:38.887 | Exit 0, 0.267757 s; complete responses and closed snapshot. |
| 08, POSIX | 18:34:39.156 | Exit 69, 5.062930 s; same header-only 64-byte-body wait after APP_START, no body returned by direct reads. |
| 09, POSIX | 18:34:44.219 | Exit 69, 5.062591 s; same header-only wait, no body returned by direct reads. |
| 10, native | 18:34:49.282 | Exit 69, 5.253131 s; same header-only 64-byte-body wait, requestTimeout. |
| 11, native | 18:34:54.536 | Exit 0, 0.261043 s; complete responses and closed snapshot. |
| 12, POSIX | 18:34:54.798 | Exit 0, 0.073697 s; both responses complete. |

The fixed sample contained three POSIX successes/three timeouts and four native
successes/two timeouts. These counts are descriptive only. Failures remain
failures; subsequent successes did not turn them into passes or justify retry.
No DEVICE_INFO timeout occurred in this round.

The first POSIX read also contained 128 bytes outside recognized frames,
discarded under the bounded synchronization policy. In contrast, every failed
POSIX attempt had exactly 85 bytes for complete DEVICE_INFO and then 3 bytes
after APP_START, so no received 64-byte body was hidden in discarded input.

### OS-read evidence in the three POSIX failures

Each failed POSIX attempt first received complete DEVICE_INFO, then wrote all
19 APP_START bytes once. The sum of all subsequent nonempty os.read returns was
exactly 3 bytes: one serial header, with declared content length 64. Thus the
independent frame counter was not discarding a previously read 64-byte body.
Because no content byte arrived, the response opcode itself could not be read;
SELF_INFO was the expected response at this stage, not an inferred body value.

| POSIX case | Request-to-deadline observation | At the deadline |
| --- | --- | --- |
| 05 | 5.005099 s; header received about 0.57 ms after APP_START | FIONREAD 0 before/after probe, select not readable, final read 0 bytes, 64 content bytes still missing. |
| 08 | 5.001678 s; header received about 0.54 ms after APP_START | FIONREAD 0 before/after, select not readable, final read 0 bytes, 64 missing. |
| 09 | 5.001762 s; header received about 0.47 ms after APP_START | FIONREAD 0 before/after, select not readable, final read 0 bytes, 64 missing. |

The small deadline overshoot is observed OS/Python scheduling and probe overhead,
not a larger configured timeout or an added grace period. No later data was
accepted as success. Input queues were also empty when close began. For the two
native failures, the actual reader callback likewise reported chunks of 85
(complete DEVICE_INFO frame) and 3 bytes, and the passive decoder ended with
3 of 67 total bytes. Native reader done preceded port close/dispose in all six
native runs; every native transport close completed successfully.

### Conclusion and limits

The header-only 64-byte wait was reproduced three times with no Dart,
libserialport_plus, or reader in the POSIX process. The missing content was not
available from the OS tty input stream within the existing request budget; it
was not data returned to that client and subsequently discarded by its parser.
Therefore libserialport_plus/reader are not necessary causes of this stall, and
the observations do not support a wrapper/reader fix for the reproduced symptom.
No client implementation defect was demonstrated and no production fix was made.

This narrows the observed failure to generation/delivery before a POSIX read can
obtain the bytes: the device, USB path, or host driver can still be responsible.
An empty public tty queue does not reveal whether bytes remained in firmware,
a USB endpoint, driver-private buffering, were never emitted, or were lost lower
down. No USB bus or firmware trace was obtained, and no query was sent to force
release, so this round proves non-delivery within five seconds, not the eventual
fate of the missing bytes. It does not prove the native library has no other bugs
or that every native failure has the same cause. In particular the earlier
DEVICE_INFO 21/85-byte case was not independently reproduced here; its individual
cause remains unconfirmed. Historical POSIX release experiments remain separate
evidence, not actions performed in this no-extra-query round.

The control scripts and structural results were kept outside the repository;
the temporary encode-only Dart helper was removed from the package. No capture
of device text, keys, PIN, locations, or payload was retained. The only repository
changes for this follow-up are documentation. No production code or dependency
changed, so the preceding 68 core/27 CLI tests remain earlier results, not a new
run for this documentation-only follow-up. Fresh control self-tests, Python syntax
checks, root format/fatal-info analysis, and diff checks passed. No commit, push,
PR, release, other-platform/remote CI run, or LoRa test was performed.


## Step 9 device acceptance on November 9, 2026

The user selected one exact USB path for this task, then explicitly authorized
one metadata enumeration, the fixed H2–H7 matrix, H9 initialization cancellation,
and SIGINT/SIGTERM only to this task's child processes. Physical unplug/replug
and emergency forced termination were not authorized. Public records use `$PORT`
and device alias **Companion USB A**. The physical model, firmware provenance and
node name had no independent second source and remain unknown; successful device
fields are device-reported, with only structural facts retained here. No prior
Heltec label is used to identify this device.

The software gate passed before hardware access. `BIN` is `bin/meshctl` in the
complete CLI bundle copied to a fresh delivery directory outside the repository;
all native hardware commands used that copy and that directory as cwd. `SRC`
is the same SDK's direct Dart `run bin/meshctl.dart` from `apps/meshctl`.
Source HEAD was clean `e1e16e28c2d99be197a9ed18a1df269f522e5c40` on `master`.
Host: macOS 27.2 (26B123), arm64; direct Dart 3.13.7; libserialport_plus 1.0.5.

Default sessions used target 3, 115200/8N1, request budget 5 s, total initialization
budget 15 s, startup delay 0. H9 alone explicitly used 1000 ms to expose a
cancellation window, with no default or workaround change. Each listed process
ran once; H4a/H4b were the only predetermined repeated info calls. Every actual
cleanup and process return completed before the next case. A temporary Python
standard-library wrapper drained stdout/stderr concurrently, parsed results in
memory, and retained only structural summaries. It implemented no protocol,
retry, extra query, or USB capture. No raw device output or bytes were saved.

Native artifact SHA-256 (unchanged through final archive extraction):

- `bin/meshctl`: `51d4e7e10e3f7ea64927797f252a436b7f72ab775bfea262356aa837dce6b914`
- `lib/liblibserialport_plus.dylib`: `6a3fbe15228b7e860b0cd9ec3fd8a60b55f0e40fbbe2ef3b5cef0f3a7ea4a56d`

All times below are UTC on November 9, 2026. Elapsed values are whole-process
wall time, including startup, source build hooks where applicable, and cleanup;
they are not pure handshake latency. `succeeded` for info/error paths means the
CLI awaited close and returned naturally with no cleanup diagnostic; successful
info also explicitly reports sessionClosed. Watch independently reports its end
cleanup result. H1 does not open a port and has no session cleanup to assess.

| Case / attempt | Artifact / exact command | Start UTC → end UTC | Elapsed s | Result / actual exit / cleanup | Structural evidence |
| --- | --- | --- | --- | --- | --- |
| H1 / 1 | `BIN ports --json` | 20:41:26.706 → 20:41:26.967 | 0.260218 | PASS / 0 / not_applicable_no_open | Parsed one JSON object; 4 paths; explicit selected path matched; no port open. |
| H2 / 1 | `BIN port-check --port $PORT` | 20:41:26.967 → 20:41:26.998 | 0.030558 | PASS / 0 / succeeded | Open/state/close/dispose success; protocol not checked. |
| H3 / 1 | `SRC info --port $PORT --json` | 20:41:26.998 → 20:41:28.443 | 1.445170 | PASS / 0 / succeeded | One complete schema-1 info snapshot; initializationCompleted and sessionClosed true; target 3, reported protocol 14. |
| H4a / 1 | `BIN info --port $PORT --json` | 20:41:28.444 → 20:41:28.804 | 0.360280 | PASS / 0 / succeeded | One complete closed info snapshot; target 3, reported protocol 14. |
| H4b / 1 | `BIN info --port $PORT --json` | 20:41:28.804 → 20:41:29.060 | 0.255486 | PASS / 0 / succeeded | One complete closed info snapshot; all device/self fields and target equal to H4a in memory, including public-key prefix consistency only. |
| H5 / 1 | `BIN watch --port $PORT --json --duration 3` | 20:41:29.061 → 20:41:32.401 | 3.340159 | PASS / 0 / succeeded | One ready, one end: duration / 0 / succeeded; ready-to-end 3.092708 s. |
| H6 / 1 | `BIN watch --port $PORT --json` | 20:41:32.402 → 20:41:32.759 | 0.356518 | PASS / 130 / succeeded | SIGINT once after ready to this native child PID; one end: sigint / 130 / succeeded. |
| H7 / 1 | `BIN watch --port $PORT --json` | 20:41:32.761 → 20:41:33.019 | 0.258034 | PASS / 143 / succeeded | SIGTERM once after ready to this native child PID; one end: sigterm / 143 / succeeded. |
| H8 / 1 | `BIN info --port $CHECK_DIR/no-such-serial-port` | 20:41:33.020 → 20:41:33.143 | 0.123084 | PASS / 69 / succeeded | Confirmed nonexistent temporary path; opening-stage transport failure, no command/expected opcode; empty stdout, no stack. |
| H9 / 1 | `BIN watch --port $PORT --json --startup-delay 1000` | 20:41:33.144 → 20:41:33.389 | 0.245712 | PASS / 130 / succeeded | SIGINT once on initializing state before ready, with explicit startup-delay 1000 ms; no ready, one end: sigint / 130 / succeeded. |
| H10 / 0 | None | — | — | NOT_RUN / — / — | NOT_RUN: no physical unplug/replug authorization or action; recovery info also not run. |

H8's `$CHECK_DIR/no-such-serial-port` was verified absent immediately before the
fixed matrix; it was not another real device node. H9 used watch NDJSON to observe
the initializing state after signal registration; process existence was not used
as a readiness proxy. H6/H7 signals were sent to actual native child PIDs after
ready, never to a terminal group or unrelated process.

**Outcome:** H2–H7 basic gate passed on this host/device. H1, H8 and H9 passed;
H10 and post-replug recovery were not run. There were 10 command invocations
(including enumeration and the expected nonexistent-port failure), eight selected
real-port open attempts, six complete initialized sessions, zero initialization
timeouts, zero failed cases, zero unconfirmed cleanups, and no retry, external
observation deadline, forced termination, or manual intervention. Every process
returned naturally; no task process remains pending. JSON/NDJSON parsing reported
zero errors. The fixed H4 pair had equal stable fields in memory; public-key prefix
consistency is not identity authentication. No raw snapshot is retained for later
field inspection, and no device-reported model/firmware value was independently
verified.

This round did not reproduce a request timeout. It neither repairs nor disproves
the historical intermittent missing-64-byte observations and independent POSIX
failures above. No lower-level bytes were captured in this round, so no new
byte-boundary attribution is made. These finite counts support no reliability or
success-rate estimate. No firmware/configuration change, unplug, port-release
intervention, delay workaround, flush/drain, control-line operation or additional
query was requested. No unexpected configuration difference was observed in the
H4 snapshots; this is not a full configuration audit.

Ready establishes only this implementation's two-command initialization and
expected parsed responses, not full protocol-14 support, authentication or radio
reachability. The software suite proves the two-command contract; this round did
not count outgoing USB packets. No LoRa send was requested by this CLI; the
device's own configured RF behavior was not measured. With no heartbeat after
ready, silence cannot establish physical disconnect. A future authorized H10
requires ready, user unplug, a bounded observation window (for example 10 s),
normal authorized SIGINT if no notification arrives, then explicit confirmation
of the replugged path before an independent info call. SIGINT success is not
disconnect-detection success.

The [delivery record](releases/phase-1a-dev1.md) separates software, hardware,
artifact integrity and redistribution status. Clean-machine/quarantine behavior,
other platforms, physical disconnect detection and the historical delivery issue
remain open. Two-device LoRa round trips belong to a separately authorized Phase
1B; none was started here.


## Step 9 H10 follow-up on November 9, 2026

After the initial fixed matrix and archive validation, the user explicitly
authorized assisted physical unplug/replug testing. No physical action was
requested before ready. One H10 watch was started using the same outside-checkout
candidate executable, cwd and unchanged asset hashes recorded above. It failed
before ready. The user then confirmed the device had remained connected and
explicitly authorized exactly one additional startup attempt. That second
attempt also failed before ready; no further startup was attempted.

Both commands were `BIN watch --port "$PORT" --json`, using unchanged defaults:
target 3, request budget 5 s, total budget 15 s, startup delay 0, 115200/8N1.
A temporary standard-library wrapper drained both streams and retained only
structural events. It did not inspect raw bytes or implement another handshake.
No additional enumeration, query, delay, flush/drain, control-line operation,
configuration change or firmware change was performed. No user unplug/replug
was requested or reported; the additional attempt was an explicit user-approved
finite attempt, not an automatic retry. Emergency forced termination remained
unauthorized and was not used.

| Case / attempt | Start UTC → end UTC (November 9) | Wall time s | Actual result | Exit / cleanup | Protocol evidence |
| --- | --- | --- | --- | --- | --- |
| H10 watch / 1 | 20:54:37.590 → 20:54:42.791 | 5.201052 | FAIL: initialization prerequisite | 69 / succeeded; natural return | requestTimeout, initializing, command 0x16, expected 0x0D; 0 ready, 1 end: failure / 69 / succeeded; no signal or stack. |
| H10 watch / 2 | 20:55:31.116 → 20:55:36.247 | 5.131309 | FAIL: initialization prerequisite | 69 / succeeded; natural return | requestTimeout, initializing, command 0x16, expected 0x0D; 0 ready, 1 end: failure / 69 / succeeded; no signal or stack. |

**Current H10 result:** two failed startup attempts. Physical disconnect detection
is **NOT_RUN**, since neither invocation reached ready. Recovery info is
**NOT_RUN**, since no physical unplug/replug cycle occurred. Do not count these
as disconnect failures, cancellation successes or recovery successes. Both
processes completed their own cleanup and were reaped; no task process is pending,
no signal was sent, and no forced termination occurred. The user confirmation
and separate second-attempt authorization are the only manual interactions.

The original H2–H7 basic gate remains a passed dated matrix, not a claim that
later sessions all initialize successfully. Across both Step 9 parts there were
12 invocations, 10 selected-port open attempts, six complete initializations and
two initialization timeouts. Counts are descriptive only; no reliability estimate
is inferred. All completed-process cleanups were confirmed. Software gate evidence
is unchanged because the executable, dylib and compilation inputs are unchanged.

This follow-up reproduces a request-wait timeout, not a proven recurrence of the
historical missing-64-byte cause. No receive-byte trace was collected. The current
recommendation is **development-with-known-limitations**: a local development
candidate can support further authorized testing with this initialization issue
explicitly recorded, but full hardware acceptance and disconnect/recovery remain
open. No root-cause fix, reset workaround, new retry behavior or Phase 1B work was
added. A new documentation-only archive preserves the same native hashes and
supersedes the initial archive's acceptance overview; the initial archive remains
an earlier snapshot, not the current recommendation.


## Step 9 post-replug follow-up on November 9, 2026

After the two H10 startup failures, the user asked whether USB unplug/replug
could help. Both earlier watch processes had naturally returned with cleanup
succeeded. The user then confirmed one physical unplug/replug cycle, requested
one new metadata enumeration, and explicitly confirmed the current selected
path again before any new open. There was no watch running at unplug time, so
this action was not a ready-state disconnect-detection test. The device alias
remains Companion USB A; path selection is not independent identity proof.

R0 enumeration completed at 21:00:04.582 UTC, exit 0 with four total paths,
two USB ports, no warning, and no candidate open. Only the user-confirmed path
was used afterward; no other enumerated device was opened. R1 was one explicitly
authorized native info call. After its failure, the user asked about waiting for
firmware startup and explicitly requested one more call, R2. No further physical
change, artificial wait, startup delay, query or timeout adjustment was made.
Both used `BIN info --port "$PORT" --json`, defaults target 3, request 5 s,
total initialization 15 s, startup delay 0, 115200/8N1, and the same unchanged
native assets and outside-checkout cwd as the preceding H10 attempt.

| Case / attempt | Start UTC → end UTC (November 9) | Wall time s | Result / actual exit / cleanup | Structural evidence |
| --- | --- | --- | --- | --- |
| R1 / 1 | 21:00:45.350 → 21:00:50.576 | 5.225721 | FAIL / 69 / succeeded | requestTimeout at initializing, command 0x01, expected 0x05 (APP_START / SELF_INFO); no complete snapshot. |
| R2 / 1 | 21:03:15.104 → 21:03:15.361 | 0.256838 | PASS / 0 / succeeded | One complete schema-1 snapshot; initializationCompleted and sessionClosed true; target 3, device-reported protocol 14. |

Both processes returned naturally and were reaped. No signal, forced termination,
stack, raw-output retention or unconfirmed cleanup occurred. R1 reached the
APP_START/SELF_INFO stage, so DEVICE_QUERY had completed its send/response
condition, but initialization still failed. R2 later completed the entire session.
It is a separately authorized single attempt, not an automatic product retry.
No additional hardware invocation followed it in this record.

R1 started at least about 40 seconds after the post-replug enumeration completed,
so a simple assumption that the board had only just been reconnected does not
explain the full observation. R2 started about 150 seconds after R1 started.
These wall times are not firmware boot-time measurements: the actual unplug/
replug instant was not instrumented, opening might affect device state, and
previous sessions can also affect it. There was no independent reset or firmware
startup telemetry. R2 success cannot be attributed to waiting, a firmware fix,
or a demonstrated stable recovery. No received bytes were captured, so R1's
SELF_INFO timeout is not proof of the historical missing-64-byte mechanism.

The original H2–H7 matrix remains a dated pass. H10's two startup prerequisites
failed, and ready-state physical disconnect detection remains **NOT_RUN**.
A separate real unplug/replug followed by initialization was performed: R1
**FAIL**, R2 **PASS**. This is not a completed H10 fault-detection/recovery cycle.
Across all Step 9 parts: 15 calls (including two enumerations and the nonexistent
path case), 12 selected-port open attempts, seven complete initializations and
three request timeouts. All process cleanups were confirmed; counts establish
no success-rate estimate or causal fix. Recommendation remains
**development-with-known-limitations**, with public redistribution blockers and
Phase 1B exclusions unchanged. The latest documentation-only archive retains
identical native hashes and supersedes earlier acceptance overviews; earlier
archives remain dated snapshots.


## Step 9 H10 third startup on November 9, 2026

After R2 info succeeded, the user explicitly requested another single H10 watch
on the same selected path, with unplug instructions only after ready. The same
verified native executable and dylib, outside-checkout cwd and default parameters
were used: `BIN watch --port "$PORT" --json`, target 3, 115200/8N1, request 5 s,
total initialization 15 s, startup delay 0. No artificial delay, retry or protocol
change was added. This was H10 startup attempt 3, separately authorized after the
previous two H10 failures and the standalone R1/R2 sequence.

| Case / attempt | Start UTC → end UTC (November 9) | Wall time s | Result / exit / cleanup | Evidence |
| --- | --- | --- | --- | --- |
| H10 watch / 3 | 21:06:27.516 → 21:06:33.100 | 5.583720 | FAIL / 69 / succeeded | requestTimeout, initializing, command 0x16, expected 0x0D; zero ready; exactly one end: failure / 69 / succeeded. |

The process returned naturally and was reaped, with no signal, forced termination,
stack, parse error or pending cleanup. No unplug instruction was given because
ready was never reached, and no new physical action was reported. H10 ready-state
disconnect detection and its recovery cycle remain **NOT_RUN**. The earlier manual
replug with R1 FAIL/R2 PASS remains separate evidence and does not supply this
missing fault-detection test.

Current combined Step 9 counts: 16 calls, 13 selected-port open attempts, seven
complete initializations and four request timeouts (three DEVICE_INFO, one
SELF_INFO). Every process cleanup was confirmed. These exact counts are not a
reliability estimate. The original H2–H7 matrix remains a dated pass; this later
watch failure shows that the preceding R2 success did not establish stable
initialization or a waiting/replug fix. No raw bytes were captured and no new
64-byte attribution is made. Recommendation remains
**development-with-known-limitations**. No further hardware call followed this
attempt in this record. The latest documentation-only archive keeps identical
native asset hashes; previous archives remain dated snapshots.
