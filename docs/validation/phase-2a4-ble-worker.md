# Phase 2A Step 4 BLE worker cooperation

## Source and build identity

The starting checkout on November 25, 2026 was clean `master` at
`b509b2e94920098d1de4173666ac1c8d24ddb997`, matching local
`origin/master`. It is the actual merge of PR #54 with parents
`7c28e40e874eeae356897ae0099fed42ceb894d4` and
`ac96ac16f0bc7abf1a4636d061b567e0c1f6d680`. The generated project's
Git inputs use the merge commit. The source receipt inventories the current
probe templates, generator, and patches separately. [PR #54](https://github.com/007pig/meshchan/pull/54)

The generator copies 21 tracked `meshcore_link` inputs, 36 tracked
`meshchan_core` inputs, and seven unmodified runtime files. The runtime
copy contains `controller.dart`, `worker.dart`, `protocol.dart`,
`device_protocol.dart`, `device_check.dart`, `recording_adapter.dart`,
and `build_version.dart`. The two package copies retain the schema,
checked-in database code, and license sources. Their manifests omit only the
workspace resolution line. Both internal package paths resolve to private
copies under the generated project's external root.

| Input | Identity |
| --- | --- |
| Probe lock | SHA-256 `fe0e61684b5a1db153d9bae43205c95c9be29738c3db0a8fc517a7d620a84497`. The additions are core 0.1.0-rc.1, Drift 2.35.4, SQLite 3.9.1, convert 3.1.2, typed_data 1.4.0, and web 1.1.2. Existing resolutions include the three BLE 6.2.1 packages and libserialport_plus 1.0.6. |
| Product root lock | SHA-256 `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`. |
| Darwin upstream | Pub archive SHA-256 `63243add2f57ad201f09d42878a31bad6e5b93291c6ae3c36de24b5213178a0d`, with its MIT notice. |
| Observation patch | SHA-256 `fe94ab58c23b51cd7176d4ca0f479bb4aa6e5fb852bcff8dfb142fe29389410c`. Stamps the original plugin delivery and emits separate structural CoreBluetooth receipts. |
| Lifecycle patch | Applied second. SHA-256 `9979dedcc6e32508ea286646df763042db03d7ab793c8f318563879e2eb642fe`. Changes pending connect/cancel settlement and rebinding of the TX object after disconnect. |
| Toolchain | `/opt/homebrew/bin/python3`, Python 3.15.2. `sys.executable` is `/opt/homebrew/opt/python@3.15/bin/python3.15`. Existing Flutter 3.50.0 and bundled Dart 3.14.0 under `/opt/homebrew/share/flutter`. |
| Probe identity | `org.meshchan.probe.ble2a3`, local-adhoc. Worker mode supplies its own run ID in structural evidence. The copied product version constants identify only the runtime source. |

The observation-only Step 3 executable
`4635adad6e532392125005981732fbda18ef297c565e57090dd44c7e647343bc`
timed out during the first pairing attempt. The separately authorized paired
retest passed query/start, independent 82/64-byte responses, and physical
release. It used a fresh process and a restarted device. Both local writes
completed before their responses. The Step 3 review build
`92b9276e65208bbac38a29f2a6a6605e912a80dfc21873cc9857d5744e34f56f`
added the lifecycle patch and explicit arm-refusal handling and has
software, Swift-fixture, build, and signature evidence. Step 4 uses both
patches, private bridge code, and SQLite. Every physical conclusion requires
the new artifact's own receipt. [Step 3 entry and follow-up](phase-2a3-ble-host.md#step-4-entry)

## Ownership and correlation

`RuntimeController` spawns the fixture entry with its original bootstrap
and shutdown protocol. The entry builds the root-port proxy and configures
the original `WorkerDispatcher` with a fixture enumeration result, a
refusal for diagnostic transports, and the default real `CoreStorage.open`.
The actual `DeviceGate` admits `FiniteDeviceCheck`. That path constructs
the only `MeshCoreSession` for the case. The root broker attaches to the
existing probe transport, which holds the selected target and native link.
The query and start whitelist checks the full frame bytes for the worker's
2-byte `DEVICE_QUERY` and 16-byte `APP_START`. Root mode retains its
26-byte start.

- Run ID identifies the launch. Controller generation identifies the
  worker. An opaque token binds one Check attempt to the already-selected
  root transport and its native generation. This token authorizes no
  discovery. Check ID correlates the admission and settled snapshots.
- The bridge sequences requests and root deliveries independently. A
  request sequence also supplies its operation ID. A frame retains the
  write operation ID and root-validated native generation, sequence,
  timestamp, and both observed and independently expected lengths. Native
  sequence gaps are legal because the native stream covers callbacks
  beyond values. Bridge sequence gaps or duplicate current operations
  fault the bridge. Stale generation/token inputs cannot release a current
  attempt or repeat native work.
- The worker subscribes before Open. Root records successful Open only
  after GATT, TX notify, and write-limit checks. One write in flight and
  at most two accepted writes and responses bound the data path. A separate
  control slot allows Close during pending Open or Write. The full frame
  reaches the worker through a byte copy; both isolates log only structural
  facts. Root log elapsed time, worker elapsed time, and native callback
  time have separate origins. Use sequence and operation to relate them.
  For dispatch guards only, the pinned macOS Dart SDK implements
  `Timeline.now` on the same OS monotonic clock in both isolates. The
  broker refuses an expired queued Open or Write before native dispatch.
  [Dart VM timeline](https://github.com/dart-lang/sdk/blob/fa8c1270c374c1346931583a17c3b7f278d3822d/runtime/lib/timeline.cc#L24-L26) ·
  [macOS clock implementation](https://github.com/dart-lang/sdk/blob/fa8c1270c374c1346931583a17c3b7f278d3822d/runtime/vm/os_macos.cc#L70-L80)
- Session readiness requires the paired write and response, in either
  arrival order. The response receipt window remains 500 ms, with at
  most eight pending entries per source. Independent lengths stay at
  82 and `58 + N`. An uncertain notification during close can fail the
  case after successful logical initialization. It does not revoke an
  observed physical release.
- The root requests physical cleanup on Cancel or worker loss even when
  a platform Future is pending. Affirmative release requires the applicable
  terminal and mirror, settled platform work, fence retirement, and
  link and bridge subscription settlement. The worker proxy awaits the
  actual release result. A missing or failed result keeps gate ownership
  unconfirmed. A definite arm refusal has no native connection to retire.
  Lost acknowledgement can still require native retirement.
- Admission, logical result, physical close, session and observer cleanup,
  gate state, storage owner state, ReleaseReport, ReleaseAcknowledged, and
  actual worker exit are separate observations. The fixture entry closes
  its extra port in the dispatcher's finish path. The probe closes root
  bridge resources and allows native Quit after affirmative runtime and
  bridge cleanup. Independent reopen verifies storage after process exit.

## Local checks

Use the [probe instructions](../../tool/ble_probe/README.md#generate-and-verify-the-host)
to generate from the exact source and validate the owned project. Commands
use the probe lock and the existing SDK. The SQLite hook uses the default
locked native assets. No database source is regenerated.

The generated root is `/private/tmp/meshchan-ble2a4-final`. Its
`evidence/probe-source.json` has SHA-256
`5d520db8f2b72331de5fd182d8d4c7b33310f4dec683bbcb2d795b2b4f064311`.
Generation used `--offline` with the pinned local Darwin archive and an
owned Pub cache. The two cached SQLite dylibs matched the SQLite 3.9.1 hook's
arm64 and x86_64 upstream hashes. The hook resolved the locked binaries
without a manifest, source, or hook override.

| Check | Result |
| --- | --- |
| `python3 -B -m unittest discover -s tool -p prepare_ble_probe_test.py -v` | **Passed.** Eight generator tests. |
| `dart format --output=none --set-exit-if-changed lib test tool` | **Passed.** 27 generated files, zero changes. |
| `dart analyze --fatal-infos` | **Passed.** Zero findings. |
| `flutter --no-version-check test --no-pub --concurrency=1 --reporter expanded` | **Passed.** 41 generated-project tests, including the 27 earlier tests and 14 additions. |
| `dart --disable-analytics run tool/check_worker_cooperation.dart` | **Passed.** Six independent-process scenarios with Apple Clang on PATH. The initial direct-Dart attempt selected Homebrew LLVM 18 and failed on the macOS System library before executing the scenarios. Both logs are retained. |
| `flutter --no-version-check build macos --release --no-pub` | **Passed.** Xcode 27.2 (27B52) built the 47 MB universal probe on macOS 27.2.1 (26B131). The Flutter Assemble script emitted its output-dependency warning. |
| `codesign --verify --deep --strict --all-architectures --verbose=2` | **Passed.** Both slices are ad hoc with no Team identifier and no effective entitlements. The SQLite framework passed separate strict signature verification for both slices. |
| `dart --disable-analytics build cli --target=tool/check_cooperation_storage.dart` | **Passed.** An independent arm64 checker bundle was built and verified for guest storage checks. |

The Release executable SHA-256 is
`fa541d36516b23fa525dccc96d8d4a4105197e17d7a8cc12f20f823168378455`.
The arm64 and x86_64 CodeDirectory hashes are
`bb9f40bd5dd025b99b2af2226e421b7466915e32` and
`b5d33a2f687ddd8589b82048d55679d6c95e1511`, respectively. The universal
`Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3` binary has
SHA-256
`78592666674972ed235cb50387acf37905d9017d8dd6dc35d2b83b62a83fb60f`
and the expected `@rpath/sqlite3.framework/sqlite3` install name.

### Synthetic results

The spawned-worker tests covered both local write/response orders,
response-before-write-failure, byte isolation, occupied gate, initialization
budget expiry, waiting for notify readiness, Cancel during pending Open and
Write, stale identity, missing/duplicate/reordered bridge messages, and
incrementing generations. At the real probe boundary the synthetic receipt
sequence and its worker projection preserved 82/64 bytes with 2/16-byte
requests. A late duplicate during close invalidated provenance and blocked
reentry while preserving the first logical success and both actual releases.
The retained Darwin boundary suite covers explicit arm refusal, lost arm
acknowledgement, late arm after Cancel, and both native terminal forms. The
root transport suite covers pending GATT work, native terminal without
completed platform work, and native/Dart mirror separation. The underlying
callbacks in these checks are synthetic.

The process suite independently observed a busy SQLite owner, drained an
accepted draft during shutdown, then reopened and checked exact content and
empty diagnostic History. A withheld release acknowledgement kept Quit
blocked until the existing acknowledgement and actual exit settled. Withheld
physical release kept the gate quarantined and storage held. Abrupt worker
loss during Open, Write, and Close caused one physical cleanup request in
each case. Physical root release was then confirmed, while worker release
and normal Quit remained unconfirmed. The parent cleaned only the owned
synthetic process container after actual exit. Synthetic privacy markers were
absent from structural evidence and child console output.

### Signed guest GUI

The existing UTM guest reported macOS 27.2.1, `VirtualMac2,1`, and an
unlocked console. The authorized guest executor verified the same Release
signature and executable hash for four owned launches. The first AX lookup
ran before AppKit registered the new process. Independent PID and argv
inspection confirmed startup, and the next lookup found the intended window
without relaunching it.

| Guest scenario | Result |
| --- | --- |
| Real-mode offline startup | **Passed.** Worker offline, passive central and peripheral counts both zero, and the evidence view contained one offline startup row. Command-Q exited 0. |
| Synthetic success and explicit follow-on | **Passed.** The same process and worker completed Check IDs 1 and 2 with native generations 1 and 2. Both carried 2/16-byte writes and 82/62-byte native, root, and worker responses for the independent four-byte name fixture. Release was confirmed for both. |
| Synthetic Cancel and native window Close | **Passed.** Cancel during pending connect issued zero writes, observed the modeled native and Dart disconnect, and released the Check. Native window Close exited 0 after runtime cleanup. |
| In-app Close during synthetic connect | **Passed.** The in-app action waited for modeled link release after zero writes and completed the real worker/SQLite shutdown. The process exited 0. |
| Independent SQLite process | **Passed.** The contender saw the active owner busy. The running app mapped its packaged SQLite framework. After Command-Q and OS-observed exit, the arm64 checker independently reopened the owned directory and verified the exact draft, empty diagnostic History, and its own close. |

The three resource-bearing guest launches reported ReleaseReport,
ReleaseAcknowledged, worker port closure, actual worker exit, zero runtime
ports, and root bridge closure before their successful OS exits. The
evidence view was inspected at its default size under Accessibility. Each
app's stdout was empty and stderr held only renderer initialization. See
`evidence/vm/` under the generated root for signed hashes, exit status,
structural receipts, and screenshots of the evidence view. The guest
executor exited and the owned app copies and fixtures were removed.

## Real BLE scenarios

The operator confirmed that the known paired Heltec V4.3 was online with the
same official V4 Companion Bluetooth v1.18.0 image and independently known
`N = 6` from device configuration. They confirmed exclusive command access
across the enabled interfaces and the absence of pending replies, and
authorized Case A. The existing bond was used. The app's adapter reached
`poweredOn` and the NUS-filtered scan returned one choice. Native scan
stop and both scan subscriptions settled before the explicit selection.
No pairing or permission prompt was observed in the checked UI.
There was no device restart, pairing reset, or TCC reset.

| Scenario | Status | Attempts | Observation |
| --- | --- | ---: | --- |
| A. Final dual-patch worker query/start | **Passed** | 1 | Actual CoreBluetooth provenance, 82/64-byte response lengths, both write results, worker session success, and physical and worker release were confirmed. |
| B. Explicit follow-on in the same process and worker | **Not run** | 0 | The authorized host run ended after A. The signed guest success and follow-on used a synthetic backend. |
| Normal Quit after a real Check and independent reopen | **Passed** | 1 | Actual Command-Q, runtime release, acknowledgement, worker exit, OS process exit, and independent exact SQLite readback. |

Each case allows one explicit attempt. Applied budgets were 10 s for scan, 15 s for
combined initialization including the bridge, and 5 s per Companion
request within initialization. The original controller deadline is 30 s.
The cleanup observation is 10 s and the existing notify-off grace is 500 ms.
Start physical cleanup at the first loss of provenance, format or length
mismatch, unexpected prompt, protocol or transport failure, Cancel, or
deadline. Retain the first outcome. A follow-on requires confirmed physical
and worker release, the same selected target, and a fresh session, transport,
and native generation. No larger-frame, 174-byte channel receive, other
firmware or hardware combination, or broader recovery result follows.
Only query/start is issued, with no LoRa send request, inbox consumption,
or device configuration write.

### Case A receipt and release

Run ID `1795602730942171` identifies the actual host launch. Case A used
runtime generation 1, device Check ID 1, and native generation 1. Open
operation 1 returned readiness after the native TX notify-enable receipt
at sequence 2. GATT reported with-response RX write and notifying TX.
CoreBluetooth reported 512 bytes with response and 173 without response.
Only the advertised with-response path was used.

| Command / operation | Inner write | Write result | Notification and worker association |
| --- | ---: | --- | --- |
| `DEVICE_QUERY`, 2 | 2 bytes | Confirmed, root dispatch to result about 182 ms, root-to-worker sequence 2 | `DEVICE_INFO`, native receipt 3, root-to-worker sequence 3. Native, root, worker, and independent expected lengths each 82 bytes. |
| `APP_START`, 3 | 16 bytes | Confirmed, root dispatch to result about 177 ms, root-to-worker sequence 4 | `SELF_INFO`, native receipt 4, root-to-worker sequence 5. Native, root, worker, and independent expected lengths each 64 bytes. |

During Open the phase showed the active worker operation while the logical
result still showed the completed scan. The case result appeared when
the worker Check settled. The bridge recorded each write result before its
matching frame. Both responses came from the original plugin delivery,
matched the independent
successful notifying TX receipt, and reached the existing session. The root
observed the second response about 1.19 s after dispatching the Check.
The settled worker snapshot retained device information, no failure,
successful session and observer cleanup, and `released: true`. The gate
returned from occupied to free.

Close operation 4 drove native notify disable at receipt 5 and locally
requested disconnect at receipt 6. The Dart disconnect mirror, outstanding
platform work, native fence retirement, link subscription, and bridge root
subscription settled. Root returned the confirmed CloseResult on
root-to-worker sequence 6. The broker retained valid terminal provenance.
The worker's close and case result confirmed both sides. The root observed
physical release about 180 ms after the worker's Close request.

Before Quit, an independent process received the expected busy-owner
response, and OS file mapping showed the probe's own SQLite framework.
Command-Q then observed storage owner release, ReleaseReport,
ReleaseAcknowledged, worker bridge port closure, and actual worker exit.
The root closed its bridge port, and the controller's open-port count was
zero. Launch Services returned and an independent process check found the
original PID absent. A separate arm64 checker reopened the fixture, matched
the exact draft, found empty diagnostic History, and released its owner.

The host structural receipt at `evidence/host-case-a/cooperation-evidence.json`
has SHA-256
`f74668162053fe254327a2ae9688efaade2b7e88a30b359dd8de25062ff422c7`.
The sibling `storage-busy.json`, `storage-reopen.json`, `sqlite-mapping.txt`,
and OS exit receipts preserve the independent observations. The probe's
stdout was empty and stderr held only renderer initialization. No target
identifier, advertisement, node name, PIN, or raw frame was exported.

## Execution location decision

**Adopt for subsequent design.** Keep the plugin, unsolicited platform callbacks, native
provenance, and actual BLE ownership on the Flutter root isolate. Keep
session, gate, storage, and recording responsibility in the application
worker. Flutter supports request replies on a background isolate and
delivers unsolicited pushes to the root. Case A confirms this split for
finite query/start on the selected target and dual-patch 6.2.1 backend.
The synthetic tests support both arrival orders, bounded failure handling,
and refusal to reenter or quit on uncertain release. Same-process BLE
reconnect on hardware, maximum frame sizes, other devices, and broader
recovery remain open. [Flutter isolate limits](https://docs.flutter.dev/perf/isolates#limited-plugin-messages-from-host-platform-to-flutter)

Step 5 can keep target values pure Dart and represent a finite, explicit
selection without performing I/O. Step 6 can define fresh per-target
transport creation that preserves subscribe-before-open, local write
completion, and affirmative release. A future BLE factory should provide
a worker transport proxy while a host-owned component maps an opaque
selection to the physical connection. The private bridge validates that
lifecycle shape and carries no stable production API commitment. Product
entry migration remains in 2A Steps 7 and 8, with production BLE in 2C and
persistence and recovery in their own phases.

## Review follow-up

Two spawned-worker regressions reproduced a passing case after a duplicate
bridged `SELF_INFO` and a canceled verdict when Quit arrived during disconnect
after logical success. Case settlement now checks the correlated proxy-close
receipt on the bridge port for protocol validity. It records the logical
result, native provenance, and affirmative release independently. Once the
logical result is visible, Quit waits for the running check to settle before
stopping the runtime. The wait uses the runtime deadline.

A subsequent review reproduced late worker readiness and a false timeout
when Close arrived after an on-time exchange. The proxy now checks the
broker's absolute cutoff when delivering initialization results and frames.
The broker verifies the timestamp of the first worker snapshot with device
information and records `initializationOnTime` separately from release.
If the final response and write result were already dispatched, the broker
can release the transport at the cutoff and classify initialization when the
correlated Close arrives.

The per-request follow-up verified that a paused worker could accept late
completions and that a stalled native exchange could outlive the request
cutoff. The worker and broker now derive the same cutoff from each write's
dispatch timestamp. The broker arms a watchdog while either the native write
result or the matching response is outstanding and clears it once both have
been dispatched. The worker rejects successful completions delivered after
that cutoff. A timely exchange remains eligible to pass if Close arrives
after the request deadline.

The request regressions cover delayed worker delivery of either completion,
either native part stalling while the worker is paused, and a delayed Close
after timely completion. A further regression reproduced a passing verdict
after an unexpected notification with valid native provenance arrived before
Close. The case verdict now accounts for the root transport's first fault
and faults recorded by the broker. Worker logical success and confirmed
release remain visible when a root fault fails the case and blocks reconnect.

When the final receipt file is unwritable, Quit now leaves the window open
after release and opens the evidence view. The operator can retry the write
or copy the final shutdown receipt and then close. The widget tests inject
an actual file-write failure and cover both recovery paths, including a
clipboard failure that leaves Quit blocked. The real-scenario checklist
now gives the distinct pass criteria for root and worker modes.

Quit now rechecks the clipboard when a copy is the only retained final
receipt. Copying the fixture path after the receipt restores the need to
save the file or copy the receipt again. Disposing the controller invokes
worker shutdown even when idle and prevents delayed fixture creation from
starting a worker. The regressions verify the idle worker exits, the port
closes, and the SQLite fixture can be reopened.

## Pre-PR validation

The regenerated probe passed 56 Flutter tests and six independent process
scenarios, with clean formatting and analysis. The eight generator tests
passed with `/opt/homebrew/bin/python3` (Python 3.15.2, resolved executable
`/opt/homebrew/opt/python@3.15/bin/python3.15`). The Release source receipt
matches the tested probe templates and generator by SHA-256.

`flutter --no-version-check build macos --release --no-pub` built the final
probe with Flutter 3.50.0 and Dart 3.14.0. The locally signed app and embedded
SQLite framework passed strict signature checks for arm64 and x86_64. The
runner executable SHA-256 is
`2b0f3883ef569157e54a967c96d9696058dbfeea4156f9ef16893ebc9536905e`.

The macOS 27.2.1 UTM guest verified the copied app signature and executable
hash and ran `--worker-cooperation --fake-backend`. A separate process saw
`data_directory_busy` while the worker held the fixture. Command-Q exited
with status 0 and the original PID disappeared. The final receipt confirmed
storage release, worker exit, bridge closure, and zero runtime ports. The
independent AOT checker reopened the fixture, read the expected draft and
empty history, and released it. The real BLE Case A above applies to the
earlier signed artifact identified in that record.
