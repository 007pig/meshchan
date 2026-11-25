# Phase 2A Step 3 macOS BLE probe validation

## Source and runtime scope

On November 25, 2026, this work started from a clean `master` at
`7c28e40e874eeae356897ae0099fed42ceb894d4`. That checkout contains the
actual merge `72865ee31a331bce8787d538fff112b4d9ecd30b` of PR #53, with
parents `e313bc33a4f105eceeb830f657ea9ab410072059` and
`130edf214067d40cf32efba455fb2477dff84a36`. Git ancestry and the GitHub
merge state both confirmed the relationship. The source receipt distinguishes
the fixed package inputs from the new, uncommitted probe inputs.
[PR #53](https://github.com/007pig/meshchan/pull/53) ·
[Step 2 evidence](phase-2a2-protocol-backends.md)

The probe uses the public `CompanionTransport` and `MeshCoreSession` from
the fixed copy of `meshcore_link`. The session subscribes before open and
owns the initialization deadline, request matching and typed decoding. In
the isolated root isolate, the private transport opens the selected link,
discovers the NUS service and characteristics, verifies TX notify readiness
and records both native write maxima. It writes one inner value at a time
to RX using the with-response type. The only dispatched commands are
`DEVICE_QUERY` and `APP_START`. No reception lease, inbox read, USB operation
or RF send command is part of the probe. The device may have its own background
RF activity.
[Probe instructions](../../tool/ble_probe/README.md) ·
[Shared session contract](../protocol/companion-session.md)

### Build inputs

| Item | Observed |
| --- | --- |
| Host and build tools | macOS 27.2.1 (26B131), arm64, Xcode 27.2 (27B52) from `/Applications/Xcode.app/Contents/Developer`, Swift 6.4.2. |
| Python | Invoked `/opt/homebrew/bin/python3` 3.15.2. `sys.executable` reported `/opt/homebrew/opt/python@3.15/bin/python3.15`. |
| Flutter and Dart | Existing SDK at `/opt/homebrew/share/flutter`, Flutter 3.50.0 stable, framework `ab2912035e160d9cad6306df307576da6128ebdb`, engine `371f77202a73e8dff57a8b3bff75bca55c090aee`, bundled Dart 3.14.0. |
| Link snapshot | 21 tracked inputs at the source commit, including all 18 `lib/` files, the manifest, GPLv3 license text and project copyright. The receipt binds source and vendor file hashes. The only content change is removal of the external manifest's workspace resolution line. |
| BLE dependencies | `bluetooth_low_energy`, `bluetooth_low_energy_darwin`, and `bluetooth_low_energy_platform_interface` all resolved to 6.2.1. The probe lock contains 58 packages and independently resolves `libserialport_plus` 1.0.6 under the existing link package constraint. |
| Probe lock | `7f0547396caad4418c0e30675639bfc1571ae914d27b6394b65c2feaa27e865d`. Enforced offline Pub resolution consumed the same bytes and the two relative vendor paths. |
| Product lock | `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c` before and after local generation. |
| Darwin release | Upstream `b97633b24405ace7dea0f0b30a08c0599aece19e`. Archive SHA-256 `63243add2f57ad201f09d42878a31bad6e5b93291c6ae3c36de24b5213178a0d`. The private vendor copy retains the MIT license and `Copyright (c) 2025 zeekr.dev`. |
| Observation patch | SHA-256 `fe94ab58c23b51cd7176d4ca0f479bb4aa6e5fb852bcff8dfb142fe29389410c`. The receipt records every original and patched archive file hash. |
| Protocol reference | Companion v1.18.0, `81dbae592ffad40b4212bc0b37e82b38da08f4bc`. A device's installed firmware needs its own correspondence evidence. |

The observation patch preserves the existing native callback delivery,
with a generation and sequence stamp on the original plugin events.
A separate native channel records callback metadata for the bound TX
characteristic and selected peripheral object. The host joins it to the
plugin event by generation, sequence, order and length, requiring a
successful callback and `isNotifying`. The join rejects missing, duplicate,
invalid and out-of-order evidence. Receiver values stay on the plugin path.
Native disconnect and the plugin's Dart mirror are retained independently.
The native fence retires only after the observed app connection stops and
outstanding Futures settle. The probe holds the lease when the observation
deadline expires, even if logical work has settled.

The plugin's Dart logger is turned off before manager creation. The exported
schema uses fixed labels and structural numbers and booleans. The synthetic
checks cover logs containing bytes and PIN markers, logs containing a
peripheral identifier and advertisement with no frame bytes, and platform
exceptions containing synthetic private data. Device selection metadata stays
in the selection UI and its in-memory model.
[Observation patch](../../tool/ble_probe/darwin-observation.patch) ·
[Source archive receipts](phase-2a2-protocol-backends.md#ble-release-archives)

## Local software and build checks

The [generator](../../tool/prepare_ble_probe.py) produced an external project
at `/private/tmp/meshchan-ble2a3-20261125-final`. The machine-readable source
receipt is `evidence/probe-source.json` under that root. Its input inventory
includes the Git snapshot, actual template bytes, original and transformed
source hashes, dependency graph, and generation commands.

```sh
PUB_CACHE=/private/tmp/meshchan-ble2a3-lock-bootstrap/pub-cache \
  /opt/homebrew/bin/python3 -B tool/prepare_ble_probe.py \
  --destination /private/tmp/meshchan-ble2a3-20261125-final \
  --flutter /opt/homebrew/share/flutter/bin/flutter \
  --source 7c28e40e874eeae356897ae0099fed42ceb894d4 \
  --darwin-archive /private/tmp/meshchan-ble2a3-darwin-6.2.1.tar.gz --offline
/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p 'prepare_ble_probe_test.py' -v
```

The Python generator suite passed all six tests. A second generator-only run
with an explicit source commit and a destination containing spaces also
resolved the exact lock. The target rejected in-checkout, ancestor, existing,
and symlink-aliased destinations in the isolation tests.

The source receipt for the final directory has SHA-256
`4367e6f100a1ec3a06d88bd01075e675d90017bf93bd0fd3861606d8a1448a21`.
The isolated logs in `evidence/` capture these completed checks.

| Check in the generated host | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | Passed, 11 actual Dart files checked, zero changes. |
| `dart analyze --fatal-infos` | Passed, zero issues. |
| `flutter --no-version-check test --no-pub --concurrency=1 --reporter expanded` | Passed, all 24 tests, including 3 widget, 11 Darwin-boundary, and 10 transport/controller cases. |
| `flutter --no-version-check build macos --release --no-pub` | Passed, 42.1 MB Release app. The stock Flutter assemble script still emits a build-phase output warning. |
| `codesign --verify --deep --strict --all-architectures --verbose=2` and per-architecture signature/entitlement inspection | Passed for the app and embedded code. The actual app is ad hoc signed with no Team identifier. Effective app entitlements are empty on both slices. |
| `plutil -extract` for the built Info.plist and `lipo -archs` on the executable | Passed, display name `Meshchan BLE Probe`, identifier `org.meshchan.probe.ble2a3`, macOS minimum 12.0, arm64 and x86_64. Usage declaration is “Scan for and check a Companion device you select with Bluetooth.” |

The first Release build succeeded but exposed Xcode's ad hoc
`get-task-allow` injection on bundle inspection. Its log and signed-metadata
receipt are retained as preliminary evidence. The generator now disables
base entitlement injection. The following signed build has empty effective
entitlements, including for sandbox, Bluetooth, and debugger attachment.

Final app path

```text
/private/tmp/meshchan-ble2a3-20261125-final/host/build/macos/Build/Products/Release/Meshchan BLE Probe.app
```

The executable SHA-256 is
`4635adad6e532392125005981732fbda18ef297c565e57090dd44c7e647343bc`.
The arm64 CodeDirectory hash is `e7a7eb6b73f741acb7e48f27d0ec5d2fc1c77a2f`.
The x86_64 CodeDirectory hash is `d879e7f2063b4e16fe5b58704f7808edbec6bf77`.
The probe uses the local-adhoc route. Debug build/run, official signing and
release packaging were outside this validation.

The targeted checks exercise scope, redaction, subscription order, a response
before write completion, invalid native callbacks, absent and duplicate
receipts, stale generations, separately controlled native and Dart disconnect
events, initialization and request deadlines, early Cancel, idempotent cleanup,
and single explicit reconnect. A test uses a truncated name that the shared
decoder accepts and verifies that the probe's independent length check rejects
it. When a synthetic native Future stays pending after a terminal callback, the
logical outcome settles, release remains unknown, and reconnect and normal
close stay blocked. The local check scope is the new tools, external probe and
updated documentation.

## Signed guest GUI checks

The verified Release bundle was copied into an owned SSH-controlled guest
fixture. Both the host verification and guest deployment verified the bundle
signature. The guest reported macOS 27.2.1 (26B131), `VirtualMac2,1`, and an
unlocked test console. All GUI input used the authorized guest executor.

| Guest scenario | Result and evidence |
| --- | --- |
| Preliminary offline evidence view | **Failed.** Opening the evidence page under macOS Accessibility terminated the app with an `AXPlatformNodeCocoa startEditing` exception in the Flutter bridge. No scan was requested. The log is retained in `evidence/preliminary-accessibility/`. The final probe uses read-only evidence text and a finite byte-count picker for the pinned name field. |
| Corrected default startup and Command-Q | **Passed.** Before using the Scan control, the window reported Offline and no active work. The passive native observation counted zero central and zero peripheral manager allocations. No Bluetooth prompt was observed. The startup export contained only the `offlineStartup` fact. Command-Q exited 0. An independent repeat captured `evidence/vm/offline-counts.png` and also exited 0. |
| Corrected synthetic scan, Cancel, reconnect, and Close | **Passed.** The operator explicitly started and stopped fake discovery, selected the single synthetic target and its fixture, canceled the first pending connection with no frame writes, and waited for the synthetic release confirmation. One explicit reconnect then completed both requests and synthetic cleanup. The evidence page exported 71 structural events. The macOS Close button exited 0 after release. |

In synthetic generation 2, the fake reported 185 bytes for both native write
maximum queries and with-response support on RX. The probe dispatched 2 bytes
for `DEVICE_QUERY` and 26 bytes for `APP_START`. The two modeled native
receipts, sequences 2 and 3, each matched the Dart value of 82 or 62 bytes and
the preselected expectations of 82 and `58 + 4`. Each response reached the
session before the corresponding write completion. Both generations recorded
the modeled local native disconnect, Dart disconnect, settled subscriptions,
zero pending operations, and confirmed synthetic release. The [real scenario
ledger](#real-ble-scenario-ledger) has separate hardware status.

The screenshots show only the owned probe windows with device selection hidden.
The retained exports passed field allowlist, marker exclusion, sequence,
length and outcome checks. Each normal run produced an empty application
stdout and the renderer initialization message on stderr. The guest
executor exited 0 and its owned probe copies were removed. The receipt,
screenshots, exit codes and JSON exports are under `evidence/vm/`.

## Real BLE scenario ledger

No qualified BLE target was available during the implementation run. In a
follow-up on November 25, 2026, the operator supplied a Heltec V4.3 board
running the official Heltec V4 Companion Bluetooth v1.18.0 build and a
six-byte node-name length based on device configuration. The signed host
probe opened offline with that length and basis selected. The operator
could not confirm exclusive command access and the absence of pending
replies, so the run stopped at preflight. The host preflight receipt is
`evidence/host-preflight.json`.

The operator later closed the web client, restarted the device, and
confirmed that no other clients had connected since restart. The same signed
Release probe made one scan and one real initialization attempt on the host.
The selected result matched the known device name uniquely in the local UI.
The test did not retain the device name, its identifier, a selection screenshot,
or any raw values. The probe observations did not capture the system PIN
dialog. After the run, the operator reported seeing the macOS pairing dialog,
completing PIN entry, and seeing the device in System Settings under
**My Devices**. The supplementary receipt
`evidence/host-ble-main-20261125-attempt-01-operator.json` records those
observations without the PIN or device name.

Planned budgets applied to each case are 10 seconds for scan, 15 seconds
combined for connect, GATT, notify and initialization, 5 seconds per request
within that total, and at most 10 seconds to observe release after the logical
result. Notify disable can use up to 500 ms of the release window before the
probe requests a needed disconnect. One explicit reconnect to the same
selected target is admissible after confirmed release.

| Real scenario | Status | Attempts | Evidence or remaining condition |
| --- | --- | ---: | --- |
| Explicit selection and query/start | Attempt 1 failed. Attempt 2 passed. | 2 | Both scans stopped and released. The first query timed out in the first-pairing attempt. The separately authorized post-pairing retest completed both commands with matched native responses and verified release. |
| Directional lengths and write/response ordering | Passed for query/start | 2 | Both attempts reported 512 bytes with response and 173 without response. RX advertised with-response write. The retest completed writes of 2 and 26 bytes and verified notifications of 82 and 64 bytes. |
| macOS permission denied | Blocked | 0 | The real scan reached powered-on discovery. A separate controlled denial was unavailable. |
| Bluetooth powered off | Blocked | 0 | An authorized and isolated powered-off state. |
| Target absent | Not run | 0 | A controlled absence condition was not exercised. |
| Connect failure or initialization deadline | Request deadline observed in main attempt | 1 | The Companion request deadline expired during initialization. A separate controlled connect failure and the 15-second initialization deadline were not exercised. |
| Cancel during pending connect or setup | Not run | 0 | A separate controlled pending-connect or setup case was not exercised. |
| Local disconnect | Observed in both main attempts | 2 | Both attempts recorded a local native terminal callback, the Dart mirror, subscription settlement, and zero pending work. The retest also confirmed notify disable. A separate manual disconnect was not exercised. |
| Controlled peer disconnect | Blocked | 0 | An owned live connection and an authorized, independently controlled peer action. |
| Explicit reconnect after confirmed release | Completed in a separate paired run | 1 | The same peripheral was selected after a device restart and fresh probe process. Same-process reconnect and stale-event isolation were exercised by synthetic tests. |
| Largest write and notification lengths | Not run | 0 | A protocol-backed, no-RF stimulus with independently known boundary data. |

### First host attempt

The allowlisted receipt is
`evidence/host-ble-main-20261125-attempt-01.json` with SHA-256
`1e206b9b6e4c7535da260014651df3c4771014639244b06286e40593325cf725`.
The 10-second scan stopped on its original deadline. The adapter reported
`poweredOn` before discovery. The CoreBluetooth notify-state callback for
the selected TX characteristic had sequence 2, `errorFree=true`, and
`enabled=true`. The plugin completed its notify-enable request before the
first write dispatch. The discovered RX advertised with-response support
and no without-response support. The two native write maxima are reported
capabilities for the peripheral and write type.

The fixture set `N=6` from device configuration. The independent expected
lengths were 82 bytes for `DEVICE_INFO` and 64 bytes for `SELF_INFO`.
The probe submitted one 2-byte `DEVICE_QUERY` write with response, opcode
`0x16`. The write was still pending at the request deadline, approximately
5.004 seconds after dispatch. There was no observed RX write success or TX
value receipt. `APP_START` was not dispatched. Real notification provenance
and response lengths therefore remain unconfirmed.

Notify disable remained unconfirmed when its 500 ms grace expired. The probe
requested a local disconnect and observed the native terminal callback,
sequence 3, followed in Dart by the failed pending write and the disconnected
mirror. The pending notify operation also failed during cleanup. The pinned
Darwin disconnect delegate fails outstanding write and notify completions.
The event order is consistent with that cleanup path. The operator
observations establish that the run prompted for pairing and that macOS
subsequently listed the device under **My Devices**. The PIN entry had no
synchronized timestamp. These observations leave the timing of authenticated
RX access relative to the write deadline and the cause of the original
write delay open.
[Pinned Darwin write and disconnect code](https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/darwin/bluetooth_low_energy_darwin/Sources/bluetooth_low_energy_darwin/CentralManagerImpl.swift)

The disconnect Future, native observation retirement, and both subscription
settlements were confirmed. Pending operations were zero. The probe confirmed
release approximately 0.529 seconds after logical settlement. After a normal
Command-Q request, an independent OS process check found zero probe processes.

### Paired host retest

The operator separately authorized one retest, kept the existing macOS
pairing, restarted the Heltec, and confirmed that no other command client
connected after startup. The same locally signed Release bundle opened in
a new process. The operator tool privately matched the scanned peripheral
against the first attempt's platform identifier and known selection name.
No identifiers, raw values, or selection screenshots were retained. The
same 10-second scan, 15-second initialization, 5-second request, and
10-second release budgets applied.

The allowlisted receipt is
`evidence/host-ble-main-20261125-attempt-02.json` with SHA-256
`c9962c571a64fc1b1d4ab5c94999826846867d556d49b44e15dced1ec966ab2a`.
Native scan stop and the discovery subscription retirement were confirmed.
After connecting, the probe rediscovered RX with-response and TX notify.
The native TX enable receipt was sequence 2. CoreBluetooth again reported
native write maxima of 512 bytes with response and 173 without response.
The fixture again set `N=6` from device configuration.

| Command | Actual inner write | Local write result | Independently checked response |
| --- | ---: | --- | --- |
| `DEVICE_QUERY` | 2 bytes | Confirmed in 299 ms, before its response | `DEVICE_INFO`, native receipt 3. Native, Dart, and expected lengths all 82 bytes. |
| `APP_START` | 26 bytes | Confirmed in 88 ms, before its response | `SELF_INFO`, native receipt 4. Native, Dart, and expected lengths all 64 bytes. |

Both received frames met the native receipt gate for the selected TX
characteristic, including an error-free callback and active notification
state. Each receipt matched its plugin-delivered Dart value by generation,
sequence, and length. The accepted frames went through the existing
session and both requests completed in a combined initialization lasting
about 1.25 seconds from connection attempt to logical result. Native notify
disable was confirmed at sequence 5. Local disconnect was confirmed by
native sequence 6 and the Dart mirror. The probe retired the native
observation and subscriptions, counted zero pending operations, and
confirmed release about 0.272 seconds after the logical result. After normal
Command-Q, an independent OS process check again found zero probe
processes.

The first attempt's deadline remains in the ledger. The post-pairing
scenario passed with the existing bond and a freshly restarted device.
The two attempts leave the original write delay's cause unresolved.

The shared 176-byte inner-frame limit, a CoreBluetooth write maximum, and an
effective notification capacity are separate quantities. The pinned ESP32 MTU
path leaves a known risk for a 174-byte legal channel receive frame. Hardware
limits on other chip and firmware variants also remain open.
[Step 2 length analysis](../architecture/companion-transport-baseline.md#step-3-macos-ble-host) ·
[Fixed firmware handlers](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L979-L1036)

## Step 4 entry

The paired host retest meets the limited Step 4 query/start entry for this
backend version set and identified target. It completed the two commands
with independently matched successful native notifications, independently
expected response lengths, recorded write and notification sizes, and
confirmed app connection release. Step 4 worker cooperation itself remains
planned. The largest-frame cases and remaining separate negative scenarios
stay open.

## Review follow-up

The real host attempts above used the observation-only Darwin copy. The
reviewed generator still pins the same published 6.2.1 archive and applies
the same observation patch. A separate
[lifecycle patch](../../tool/ble_probe/darwin-lifecycle.patch) changes how the
private copy settles outstanding connect and cancel calls at a terminal
native callback. It also uses the CoreBluetooth disconnect boundary and
generation stamps to allow rebinding a characteristic object on reconnect.
In Dart, a definite native arm refusal releases its unused Dart link.
A lost arm acknowledgement still requires an affirmative native retirement.

On November 25, 2026, the amended probe was generated and checked in
`/private/tmp/meshchan-ble2a3-review-r1` using the same locked dependencies
and SDK. The lifecycle patch SHA-256 is
`9979dedcc6e32508ea286646df763042db03d7ab793c8f318563879e2eb642fe`.
The source receipt records both patch hashes and the final vendor files.
All seven focused Python tests and 27 generated Dart and Flutter tests passed.
Formatting and analysis passed. A synthetic Swift fixture compiled the
exact patched callback and observer bodies against local stubs. It reproduced
the four pre-fix failures and passed the two terminal callback paths, the
late-cancel race, and TX object reuse after retirement. The fixture inputs
and result are in `evidence/native-fixture/` and
`evidence/native-lifecycle-fixture.log`.

The amended isolated Release bundle built and passed strict local ad hoc
signature verification. Its executable SHA-256 is
`92b9276e65208bbac38a29f2a6a6605e912a80dfc21873cc9857d5744e34f56f`.
The lifecycle changes have software and build verification. Both real BLE
receipts retain the original artifact identity.
[Worker-cooperation gate](../architecture/companion-transport-baseline.md#step-4-worker-cooperation)
