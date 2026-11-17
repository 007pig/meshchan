# Phase 1D.11 USB initialization investigation — November 16, 2026

Status: **root cause unconfirmed; firmware HWCDC transmission is the leading
investigation direction**. This source and evidence review does not change the
candidate's **prepared / acceptance incomplete** status or either failed U02
result. The initial source-review pass performed no USB open, inbox read, RF
attempt, reset, firmware installation, system setting change, or GUI interaction.
The subsequently authorized single native-traced initialization is recorded below.
The later [ten-attempt native/POSIX control](phase-1d11-usb-posix-controls.md)
adds fresh independent OS-read/empty-tty-queue evidence and a naturally delayed
body delivered with later device data; exact device/USB/host responsibility is
still unconfirmed.

## Current failure and evidence boundary

The checkout is based on actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, with the beta changes described in
[the acceptance record](phase-1d11-hardware-beta.md). Both U02 attempts used the
same complete Release `0.1.0-beta.1+3` and product inventory SHA-256
`e29ea92734ba09ddb2618c0842cff187df0656720ace4692cd4e817d59d97420`.

| Fact | Replacement 01 | Replacement 02 |
| --- | --- | --- |
| Run ID | `e91733230cfe9c02dcfc387b186d210f` | `c286338ed69b459ade28faa4c62f3879` |
| Registered, UTC | 07:20:20.887618 | 09:31:13.275881 |
| Logical end, UTC | 07:20:35.902929 | 09:31:28.288437 |
| Registration-to-end interval | 15.015311 s | 15.012556 s |
| Primary result | initializationFailed / connecting | initializationFailed / connecting |
| Nested session result | requestTimeout / initializing | requestTimeout / initializing |
| Pending command / expected reply | DEVICE_QUERY `0x16` / DEVICE_INFO `0x0D` | Same |
| Application sends, A + B | 0 + 0 | 0 + 0 |
| Cleanup, saves, normal Quit, independent reopen | Confirmed separately | Confirmed separately |

The configured request/init/task/response budgets were 15/30/60/15 seconds with
zero startup delay. The measured intervals include registration and scheduling;
they are consistent with the **first request's 15-second deadline**, not the
30-second initialization deadline or an RF PONG response timeout. The session
cannot send APP_START until DEVICE_INFO completes. Neither failing attempt
established that first response or reached diagnostic PING/reception.

`send.attempted=false` describes the diagnostic **application send**, not the USB
handshake write. Current recording results do not expose the five-byte framed
DEVICE_QUERY's native accepted-byte count or partial native RX chunks. A pending
opcode and request timeout therefore do not prove either zero USB writes or a
particular missing-byte pattern. No byte-level trace was captured for these two
runs. B's real consuming reads are retained in the acceptance record; they do
not establish A's USB health.

## Heltec model and official firmware

The operator recalls a standard **2 MB PSRAM** board and installing **Heltec V4
Companion USB v1.18.0** from the [official flasher](https://meshcore.io/flasher).
This is operator provenance, not a device flash readback. Earlier current-artifact
U01 Check returned `Heltec V4.3 OLED`, `v1.18.0-81dbae5`, protocol 14, then closed
successfully. Thus the same candidate/device combination can initialize; the
failure is intermittent in the observed cases.

[Heltec's current manual](https://wiki.heltec.org/docs/devices/open-source-hardware/esp32-series/lora-32/wifi-lora-32-v4/)
identifies standard V4 as ESP32-S3R2, 2 MB PSRAM and 16 MB flash, and distinguishes
its USB path from V3's CP2102 bridge. V4.3 also uses a different RF front-end
selection from V4.2. In the
[pinned MeshCore board implementation](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/variants/heltec_v4/HeltecV4Board.cpp),
the model string is selected by the detected FEM type and display build. It does
not independently attest RAM size or the loaded binary. The separate R8 firmware
target remains relevant only if the physical board identification changes.

The latest official Companion release at review time was
[v1.18.0](https://github.com/meshcore-dev/MeshCore/releases/tag/companion-v1.18.0),
published October 15, source
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`. The current main cut
`75b04ef06def54b348400cb1b138afb6749ffd4f` had identical root platform settings,
standard V4 variant settings and ArduinoSerialInterface source to that release.
This comparison covers those three files, not the entire firmware tree.

The public app-only release asset
`heltec_v4_companion_radio_usb-v1.18.0-81dbae5.bin` was downloaded for offline
inspection: 652112 bytes, SHA-256
`3f60baf23c3dca1ec2d27078caa0dcd60764e157a42b67b7d18dacf0a02b1c73`, matching
the release API asset digest. Its ESP application description at offset 32
contains `idfVersion=v4.4.7-dirty`, project `arduino-lib-builder`, and SDK library
build date March 5, 2024. That date describes SDK library metadata, not the
October 2026 MeshCore firmware build. The asset was neither executed nor flashed;
its hash does not attest the bytes currently loaded on A.

The pinned standard V4 target uses `platformio/espressif32@6.11.0`. That
[platform definition](https://github.com/platformio/platform-espressif32/blob/v6.11.0/platform.json)
declares Arduino framework `~3.20017.0`, the Arduino-ESP32 2.0.17 line. Its
[board flags](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/boards/heltec_v4.json)
select CDC-on-boot and `ARDUINO_USB_MODE=1`, mapping `Serial` to **HWCDC / USB
Serial-JTAG**, not TinyUSB. The USB Companion environment enables the binary USB
interface; its debug logging options are explicitly left disabled.

## Related defects and what upstream changed

| Source | Verified change or report | Applicability here |
| --- | --- | --- |
| [MeshCore #2734 / merged #3006](https://github.com/meshcore-dev/MeshCore/pull/3006), July 21 | Standard V4 changed USB mode 0 to 1 to restore the correct peripheral. | Already present in v1.18.0. Repeating this configuration advice is not a new fix for this candidate. |
| [Espressif #12606](https://github.com/espressif/arduino-esp32/pull/12606), May 22 | HWCDC TX changes address interrupt enable/disable races, partial FIFO writes, transient connection detection and end-of-transfer ZLP handling. | Strong mechanism match to historical missing-byte/stall observations; absent from the reviewed 2.0.17 source. Its sustained-write reproducer is not this initialization case. |
| [Espressif #13048](https://github.com/espressif/arduino-esp32/pull/13048), November 3 | Separates enumeration from host endpoint polling/open detection. | Related connection-state lead, not proof of this first-request failure. |
| [Espressif #13103](https://github.com/espressif/arduino-esp32/pull/13103), November 12 | Primes TX and fixes detection when a host restarts a port without new line-control events. | Another relevant lead; its upload/reopen scenario differs from the recorded GUI attempts. |
| [Offband fork #1143](https://github.com/OffbandMesh/meshcore-firmware/pull/1143), September 11 | Defers a framed-protocol ZLP until the ring drains and FIFO is writable. | Independent fork evidence, not an official MeshCore fix or a tested firmware recommendation for A. |
| [MeshCore #2598](https://github.com/meshcore-dev/MeshCore/issues/2598) | A V4.3 user reported successful flashing but failed USB application handshaking on Linux. | Similar symptom outside Flutter/macOS; closure redirected the report rather than demonstrating a firmware fix. |

The official
[Arduino 2.0.17 HWCDC source](https://github.com/espressif/arduino-esp32/blob/2.0.17/cores/esp32/HWCDC.cpp)
drains at most 64 bytes per ISR pass. Its empty-ring branch disables the TX
interrupt without the explicit final-ZLP path added in
[commit 2ecad23](https://github.com/espressif/arduino-esp32/commit/2ecad233178bfbba9c584ffd9f67e941d84adbb7).
It also ignores the low-level FIFO write's accepted count before returning the
ring item, and uses unsynchronized interrupt-register updates. These are concrete
code differences; their occurrence in the two current attempts is unobserved.
MeshCore itself writes its three-byte header and body separately and ignores
the header write's return value. Its lack of an explicit frame flush alone is
not sufficient proof, because HWCDC performs internal flush operations.

Downloaded official Arduino **3.3.12** source contains the May TX/ZLP changes.
The November connection changes were inspected separately on master. Neither is
therefore obtained merely by selecting MeshCore v1.18.0, and a framework upgrade
would require a new firmware build and compatibility testing. No upgrade was
performed or prescribed as a verified solution.

The Offband PR reports a real C6 hardware A/B using its class methods: 15/40
aligned frames held without the terminator and 0/40 with it. Its report explicitly
limits that experiment to a separate instance/manual pump and defers tighter
production-instance testing. It is evidence for the mechanism, not this Mac,
standard Heltec V4.3, official firmware, or our 82-byte DEVICE_INFO response.
The fork also has different buffering and write policies; copying its helper
alone into official MeshCore is not an evaluated patch.

Espressif's
[current Serial/JTAG guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-guides/usb-serial-jtag-console.html)
describes host buffering that may retain device output until further traffic or
an appropriate device-side flush. This is general controller guidance from a
newer IDF, not proof that its current driver implementation is in A's firmware.

## Historical evidence and ranked interpretation

The committed [November 9 investigation](../hardware-validation.md#step-7-independent-posix-comparison-on-november-9-2026)
records three independent Python/POSIX failures with a complete DEVICE_INFO,
all APP_START bytes accepted, then only a three-byte header declaring a 64-byte
body. At the deadline, FIONREAD/select/final read found no remaining tty data.
An earlier authorized experiment reported a delayed body released by an extra
diagnostic query, plus a 63/64/65-byte correlation. Native tracing separately
recorded a 21-of-85-byte DEVICE_INFO, missing a 64-byte suffix.

These are **historical committed reports**, not fresh runs or revalidated raw
captures. They establish that Flutter and libserialport are unnecessary for the
historically reproduced symptom. They do not identify every current timeout's
cause or absolve all client code. The 82-byte body is not a multiple of 64;
separate writes/ring wrapping could leave an 18-byte chunk followed by 64, but
that packetization explanation remains an inference without a bus trace.

| Priority | Hypothesis | Evidence needed to distinguish it |
| --- | --- | --- |
| Leading | Device HWCDC TX completion/ZLP, lost interrupt wakeup, or short-write loss | First establish current native accepted write/RX structure; device-side or USB trace is needed to separate these mechanisms. |
| Still possible | macOS USB/CDC buffering or port-open state interaction | A partial frame can still be retained below tty reads; compare a controlled host or bus trace only after preserving the same firmware/input cut. |
| Lower support | Cable/hub/power fault, device mode/sleep, or wrong firmware target | No current reset/disconnect/power observation proves these. Standard R2/operator provenance and a successful Check reduce wrong-target suspicion. Repeater sleep reports do not directly establish Companion USB sleep behavior. |
| No demonstrated defect | Meshchan decoder/reader/session or Flutter GUI causing missing bytes | Current reader subscription precedes open/handshake and timeout classification is consistent. The historical POSIX reproduction argues against making a Flutter-only change. Current native writes/RX still need observation. |

No RF/channel/route adjustment can repair a missing DEVICE_INFO response before
the radio task starts. Extending request time, adding startup sleep, toggling
DTR/RTS, flushing/discarding host input, or adding a release query would change
the experiment and could hide the mechanism. No such workaround was added.

## Initial diagnostic proposal

The following proposal was subsequently authorized and executed once, as recorded
below. The initial review itself did not execute it.

The next useful observation is one **zero application-send, zero inbox-read**
initialization attempt on A alone, with B closed. It should use one owner and
one native reader, the unchanged 115200/8N1/no-flow setup, zero startup delay,
15-second request and 30-second initialization budgets. Send DEVICE_QUERY once;
only after complete DEVICE_INFO, send APP_START once; close after success or
the first failure. Maximum two USB protocol command writes, no GET_MSG, PING,
responder, reset, line toggle, extra query, reconnect or retry. Opening a USB
port can itself have device effects; this remains subject to the operator's
pause and a new specific authorization.

Record monotonic times, requested/native-accepted byte counts, native RX chunk
lengths, complete opcode/length counters and partial-header/body counts without
payloads, names, keys, locations or raw exceptions. A passive decorator of
already-decoded public frames cannot observe the necessary partial-byte state;
this requires a finite diagnostic at the existing native boundary, not a second
reader in the GUI or a claimed live-ready indicator. No new executable with
these trace guarantees was implemented during the initial documentation review.

Classify zero RX, header-only, missing-tail, complete unassociated frames and
complete matching frames separately. A single passing attempt is inconclusive;
a failing trace could narrow the current symptom, but attribution to ZLP versus
interrupt or host buffering would still require the next controlled observation.
Stop on unknown ownership, cleanup or write outcome, preserving the failure.
This diagnostic cannot substitute for the GUI U02 acceptance assertion.

## Retained evidence

Research files are under
`/private/tmp/meshchan-1d11-20261116-01/research/usb-init-20261116/`, outside Git.
They include pinned official/fork source, API responses, failed fetches, official
binary metadata, source comparisons and a research manifest. Initial attempts
to fetch Offband #1093 as a PR returned 404; the actual issue and closing PR
#1143 were then identified. No failed fetch was counted as source verification.
Python was `/opt/homebrew/bin/python3` 3.15.2. The initial review added only
research/documentation evidence; the tested product bundles and previous
acceptance cut remain intact.

## One authorized native-traced initialization

The operator explicitly approved one attempt on A, with B closed, no application
RF sends or inbox reads, unchanged deadlines, no firmware changes and no automatic
retry. The new owned directory is `hardware/usb-init-trace-01/` under the existing
evidence root. No app/storage fixture was opened or copied.

The source-only `packages/meshcore_link/tool/initialization_trace.dart` uses the
existing internal native-construction seam **inside the link member**. It wraps
the real native connection, uses the real transport/codec/session, and preserves
the sole reader. No product library, public export, CLI command or GUI entry was
changed. The real OS name is passed to the existing platform guard; no platform
guard is disabled. The wrapper forwards the original native chunk and records
only structural facts in memory, publishing after actual cleanup. An exact-byte
guard blocks any native write except DEVICE_QUERY and the configured APP_START,
including their normal partial-write suffixes. The existing two-second write
budget/progress behavior is retained; no logical command is retried.

The initial analysis gate failed on three incorrect positional constructor calls
(six analyzer diagnostics). That gate and source cut remain preserved. After
correcting the named `transport` arguments, analysis passed, the complete link
suite passed **188 tests** (180 existing plus 8 diagnostic regressions), and a new
complete native diagnostic bundle built. Entry checks confirmed help is inert
and the selected port without `--execute` is rejected before acquisition. These
preparation checks opened no port. Current native enumeration then matched A's
selected path/VID/PID, no app/B client was present, and lsof found no port owner.

The single execution gate was `D11-usb-initialization-trace-actual-01`:

| Observation | Actual result |
| --- | --- |
| PID / UTC interval | 29196; 10:48:15.444767 to 10:48:15.742262 on November 16 |
| Whole tool interval | 297495 microseconds, including native setup and cleanup; not application/LoRa RTT |
| Request/init/startup/write budgets | 15 s / 30 s / 0 ms / 2 s |
| Native write 1 | DEVICE_QUERY `0x16`, requested 5, accepted 5 framed bytes |
| Native write 2 | APP_START `0x01`, requested 19, accepted 19 framed bytes |
| Native RX chunks | 341 bytes, then 67 bytes; 408 bytes total |
| Complete frames | `0x88`/77, `0x83`/1, `0x88`/77, `0x88`/78, DEVICE_INFO `0x0D`/82, SELF_INFO `0x05`/64 content bytes |
| Unassociated notifications | Four; no GET_MSG was sent in response |
| Final native decoder projection | Complete; no partial header/body; zero omitted trace events |
| Ready / cleanup | Ready reached; reader done/stop confirmed before port close and dispose, all successful |
| Acquisition / command frames | One acquisition, two completed initialization frames, zero blocked writes |
| Application sends / inbox reads / B sessions / retries | 0 / 0 / 0 / 0 |
| Process / ownership | Exit 0, OS reaped/absent, no runner signals, no remaining port owner |

The six complete frames account for 397 framed bytes. The remaining **11 bytes**
were outside completed frames under the existing decoder policy; no content was
retained and their origin is unknown. This is not a claim that a response body
was missing. Native read chunks are not USB bus packet boundaries. Unsolicited
device notifications and ambient radio activity also mean that zero application
sends does not measure all firmware/over-the-air activity.

**PASS applies only to this one initialization and cleanup.** The timeout was
not reproduced. Tracing/native callbacks can perturb scheduling, and this is a
separate source diagnostic, not the Release GUI task. No additional attempt was
made to obtain a failure or a preferred outcome, and no U02 PASS is inferred.
The two failed GUI records remain unchanged and root cause is unconfirmed.

Post-verification checked exact command/write counts, trace/receipt hashes,
normal lifecycle, OS PID absence, selected port release, the complete diagnostic
bundle against its pre-execution inventory, all three diagnostic source hashes,
root lock hash and both complete delivered product inventories. The diagnostic
inventory JSON SHA-256 is
`85abad34547cf6f466e28181c94bfc2bc09f87f873194e29f50445cfd235adb9`;
the trace log SHA-256 is
`f1b3f320025353f6267fdcd52ea773be340da0b16fe54ef7cc8a938e2109bf08`.
`hardware/usb-init-trace-01/result.json` is the verified result. It explicitly
records `timeoutReproduced=false`, `rootCauseConfirmed=false` and
`guiAcceptance=false`.

## Detailed Offband applicability review and adoption decision

The reviewed fork cut is `aecafa96d4f4c1d527e2954fcb24886df9f0f461`; original
PR #1143 merged as `3534a642ae6497a671ac9108cce6c9f2d24a3cdc`. The review read
the original four-file diff, current serial interface/header/ZLP helper, native
framing test source, production main/interface-manager wiring and upstream issue
metadata. Sources and API responses are retained in
`research/offband-review-20261116/`. Fork code/tests were not executed, installed
or copied into Meshchan. A first license fetch used the wrong filename and
returned 404; the actual `license.txt` was subsequently retrieved.

The deferred ZLP is a technically credible **device-firmware mechanism**: it
keeps payload bytes unchanged, waits for the TX ring to drain and FIFO to become
writable, and avoids an inline spin/flush on the framed protocol path. Production
source does register `usb_serial_interface` and service its `loop()` through
`interface_manager.loop()`. These source observations support plausibility, not
new hardware verification. The wider current fork also changes short-write
admission, bounded completion, filler padding and TX timeouts; those changes are
not a small, interchangeable version of official MeshCore's writer.

Three specific limits prevent treating it as a verified fix for this project:

1. The trigger predicate is based on total frame bytes modulo 64. Our normal
   DEVICE_INFO is **3 + 82 = 85**, remainder **21**; SELF_INFO is **3 + 64 = 67**,
   remainder **3**. The reviewed per-frame trigger does not arm for either.
   Historical separate-write/ring packetization may matter, but applying this
   predicate alone is not evidence that the missing-64-byte symptom is covered.
2. [Fork #1141](https://github.com/OffbandMesh/meshcore-firmware/issues/1141)
   remained **open** on this review. It explicitly tracks runtime production
   instance/main-loop verification beyond the reported C6/manual-instance A/B.
   The native frame-atomicity tests inspect different short-write behavior; they
   are not macOS/S3 USB packet-delivery tests.
3. `usb_serial_jtag_ll_txfifo_flush()` runs on the **ESP32 device's IN endpoint**.
   Meshchan is the macOS host and contains no ESP32 firmware build target. A host
   serial flush/drain cannot be substituted for that device endpoint operation.
   Extra queries, padding bytes or client retries would change the approved
   protocol/experiment and are not equivalent fixes.

**Decision: do not adopt Offband's firmware patch or the whole fork as a Meshchan
product fix at this evidence cut.** Its mechanism is worth a separately scoped
device-firmware investigation, but current-case applicability and end-to-end
reliability are unestablished, and firmware flashing is explicitly excluded from
this authorization. The project change implemented here is the bounded source
diagnostic and its regressions. Product versions, dependencies, wire/schema
formats, deadlines and tested Release/CLI binaries remain unchanged. Further
hardware acceptance stays paused after the single authorized diagnostic.

## Three further authorized attempts and GUI comparison

The operator separately authorized **at most three** further A-only traced
initializations, stopping at the first initialization failure, with B closed,
zero application sends/inbox reads, unchanged 15/30-second request/init budgets,
zero startup delay and no firmware change. This allowance does not extend the
earlier single-attempt authorization. Evidence is in
`hardware/usb-init-trace-series-01/` under the same owned root.

All three runs used the **same existing complete diagnostic bundle**, without
rebuilding or changing its entry/support source. Its executable SHA-256 remains
`c14749c9aee889d1f3dd27c9eb95b715476e4b9513fa937740ee464b7b6f2b87`.
Each attempt had a fresh native acquisition. Before each run, a separate gate
verified the diagnostic/product inventories, original diagnostic source and lock
hashes, A's selected metadata, absence of app/B clients and an unoccupied port.
Subsequent attempts required the previous result to be ready, zero-send/read,
cleanup-confirmed, process absent and port released. Preflight enumeration did
not open the port. There was no intentional inter-attempt startup delay, repair
query, flush, line change, queue drain or parameter adjustment.

| Attempt | UTC start on November 16 | PID | Native RX chunks | Result | Whole tool interval |
| --- | --- | --- | --- | --- | --- |
| 1 | 11:47:34.938984 | 51237 | 341 + 67 bytes | PASS: ready, complete DEVICE_INFO/SELF_INFO | 239357 us |
| 2 | 11:50:03.269350 | 52896 | 341 + 67 bytes | PASS: ready, complete DEVICE_INFO/SELF_INFO | 230421 us |
| 3 | 11:52:37.444484 | 54020 | 341 + 3 bytes | FAIL: APP_START requestTimeout, incomplete expected SELF_INFO | 15213299 us |

Every attempt had exactly two native writes: DEVICE_QUERY requested/accepted
5/5 bytes and APP_START requested/accepted 19/19 bytes. All three cleanup scopes
confirmed reader stop, port close and dispose; OS exit/reap and absent port
owner were independently verified. The runner sent no termination signals.
**Three attempts used, first failure at attempt 3, then stop.** There was no
fourth initialization, additional device Check, B session, inbox read or RF
application send. The three-try sample is not a reliability estimate.

### Fresh failed trace and its observation boundary

Attempt 3 received a complete 82-byte DEVICE_INFO in its first native chunk.
APP_START then accepted all 19 bytes at trace offset 115536 us. At 224945 us,
the existing native reader delivered only three bytes: a complete serial header
declaring 64 content bytes. No content byte followed in any callback before
the request failed. Failure observation was at 15116973 us, or **15001437 us
after APP_START began**; header delivery was 109409 us after that write began.
This is scheduling around the original 15-second deadline, not an enlarged
budget. Cleanup continued afterward and is not extra response acceptance time.

The primary session failure is `requestTimeout / initializing`, command
`0x01`, expected response `0x05`. The passive trace's final projection is
`truncatedFrame`, **received 3 of 67 bytes**. Since the body never arrived,
`0x05` is the expected opcode, not an observed reply opcode. This structural
projection does not replace the primary requestTimeout with a protocol error.
There were zero omitted trace events and no intervening reader-error event.
The failure log SHA-256 is
`cd3c3ae85b9d478e504963f972c5a61eb4280c6f3326f78b4af5dc6b8a33eb7e`.

This is a **fresh reproduction of the header-only/missing-64-byte symptom in
an independent native diagnostic**, using no Flutter engine, GUI, recording
storage or B peer. It establishes that those components are unnecessary for
this symptom. It does not identify firmware versus USB path, macOS buffering
or the shared native reader backend. Observation ends at the existing
native-reader callback into transport; this round did not inspect FIONREAD,
perform independent POSIX reads, capture USB bus packets or instrument firmware.
The historical independent POSIX findings remain a separate source cut.

All first chunks were 341 bytes including the 85-byte DEVICE_INFO frame plus
256 other bytes. Their unsolicited frame structures differed between attempts.
That size is compatible with the old firmware's 256-byte TX-ring/backlog policy,
but no ring snapshot or byte provenance was observed. Neither read-chunk size
nor this arithmetic proves USB packet boundaries, a particular buffering cause
or a ZLP failure.

### What is actually different from the GUI runs

| Dimension | Recorded Release GUI U02 | Independent trace | Finding |
| --- | --- | --- | --- |
| Command/session policy | MeshCoreSession, app name Meshchan, target 3, queue 8, request/init/startup 15/30/0 | Same | No changed initialization payload or requested timeout explains the contrast. |
| Transport/native settings | SerialTransport, 115200/8N1, no explicit RTS/DTR setters, original 2-second write budget | Same implementation and settings; native decorator adds observation | No configuration workaround was used. |
| Execution owner | Long-lived runtime worker isolate, itself spawning the library reader isolate | CLI main isolate spawning the same library reader isolate | Different nesting, host and scheduling; no isolated causal experiment was performed. |
| Recording work | Parameters resolved and registration committed before session construction; task/recording observers and host snapshots | Direct session initialization, no business storage | Extra work exists, but the new independent failure proves it is not required for this symptom. |
| Native implementation | Embedded universal framework, arm64 runtime slice | Arm64 dylib in complete diagnostic bundle | Actual arm64 code-section comparison matched; packaging/signature identity differs. |
| App Sandbox | Actual signed Release entitlement has no app-sandbox key | Ordinary CLI process | No App Sandbox denial was established; GUI already had a successful Check and both GUI failures reached initializing. |
| Peer/environment | B's finite responder active; no application responses recorded | B closed; unsolicited A notifications still present | Device/ambient state was not held constant between old GUI cases and these runs. |
| Failing handshake step | Both prior GUI failures waited for DEVICE_INFO (`0x16` → `0x0D`) | New failure waited for SELF_INFO (`0x01` → `0x05`) | The exact first-request GUI failure has **not** been reproduced or attributed by this second-request failure. |

Actual native artifacts were inspected offline. Both arm64 `__TEXT,__text`
sections are 35360 bytes, SHA-256
`397b859d9f8f152936e26ee8a9b2f98e8bfa4cd9752d8649df8ff4618dc94c05`.
This rules out different code bytes in that section; it is not a claim that the
whole signed framework/dylib or their runtime environment is identical, or that
the common backend cannot contain defects. The first offline comparison helper
incorrectly assumed a thin Mach-O and failed before any comparison. That failure
is retained; the corrected helper selects the app's arm64 slice explicitly.
Entitlement and dependency outputs are retained alongside it. No SDK/cache,
signature, entitlement or system setting was modified.

The source-only observer also adds decoder/counter work and asynchronous
delegation around native setup. Thus it may perturb timing. A previous success
did not prove a GUI-specific fault; the new failure directly demonstrates
intermittency in the independent entry as well. Conversely, this does not clear
all GUI paths of bugs or establish that the two old DEVICE_QUERY failures have
the same root cause.

### Software follow-up and current conclusion

After all hardware had stopped, a ninth source-tool regression reproduced the
safe structural sequence: 341-byte chunk containing complete DEVICE_INFO,
APP_START accepted, three-byte/64-content header, then the original 15-second
deadline. It checks no false ready, no extra command, correct command/opcode
provenance, retained primary timeout and cleanup despite the trace's final
truncation projection. Analysis and the full link suite passed **189 tests**.
The new test is synthetic software evidence, not another hardware attempt.
Only that test and documentation changed after execution; trace entry/support,
root lock and the complete diagnostic/app/CLI bundles remained unchanged.

The investigation now has a current native trace for an intermittent
initialization failure. Delivery of the missing body before the transport's
framing/recording/UI layers is the principal boundary to investigate. Device
HWCDC TX completion/wakeup and host/backend delivery remain candidates; a
firmware-only or macOS-only root cause is **not confirmed**. The reviewed
Offband per-frame ZLP predicate still does not arm for this normal 67-byte
SELF_INFO frame, so this reproduction does not justify adopting that patch as
a verified solution. No production workaround or firmware change was made.
Both old GUI failures and this different-stage failure remain explicit FAILs.
Candidate status remains **prepared / acceptance incomplete**, with all task
consumers closed and further hardware work paused.

## Ten-attempt continuation

The operator later authorized ten more attempts, allowing known initialization
failures to continue after confirmed release. A fixed five-pair native/POSIX
cohort used all ten: eight passes and two APP_START timeouts (native attempt 7,
POSIX attempt 8). Both left only a three-byte header for 64 content bytes.
The independent POSIX failure had FIONREAD 0, select not readable and final
nonblocking read 0 at the unchanged 15-second deadline. This removes Dart and
libserialport as necessary causes of this freshly reproduced symptom. A separate
POSIX success received its delayed 64-byte body with a later 47-byte notification
about 5.826 seconds after the header, without additional host commands. These
facts strongly fit a USB completion/buffering direction but do not prove a
specific ZLP/firmware versus host-driver branch. See the
[independent detailed controls record](phase-1d11-usb-posix-controls.md) for each
attempt, software checks, evidence boundaries and remaining investigation work.
No product/firmware change or GUI hardware acceptance PASS followed.
