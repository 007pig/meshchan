# Companion connections

## Purpose and scope

Phase 2 aims to unify access to Companion devices over USB, TCP, and BLE.
Phase 2A establishes technical feasibility, the connection target model, and
the adapter boundary, then migrates the existing USB entry points internally.
Step 1 is the source review and documentation baseline. It authorizes no
product or runtime changes. Production TCP belongs to 2B, production BLE to
2C, and saved connections and database migration to 2D.

The baseline is macOS arm64, an explicitly selected device per operation, and
finite device checks and diagnostic tasks. CLI watch is a session observer
with an optional duration and otherwise ends on signal or failure. Changes
to device concurrency, selection, task lifetime, or recovery require a
decision in the applicable later step.

## Reviewed baseline

| Evidence | Baseline |
| --- | --- |
| Current implementation | On November 23, 2026, the reviewed checkout was clean `master` at `02f39e060194351bad02006418905272fdc9aa47`, matching the planning reference and local `origin/master`. The remote is `https://github.com/007pig/meshchan.git`. The [Dart workspace](../../pubspec.yaml) contains the Flutter App, Dart CLI, and two shared Dart packages. |
| Historical published package | macOS arm64 engineering Build 10 contains App `0.1.0-rc.1+10` and CLI `0.1.0-rc.1`, compiled from frozen source `c5cd5021da5e62c60127678b650d970721263296`. The Step 1 source baseline differs from that commit in 12 Markdown files. [Publication record](../releases/phase-1e12-publication.md) |
| Historical acceptance | The selected USB and openHop runs belong to the inventoried Beta Build 5, the original RC1 Build 9, and the restored RC1 Build 10 image. Each record carries its own source and limits. [Step 1 evidence ledger](../validation/phase-2a-connections.md#historical-evidence) |
| Step 1 changes | This architecture document and the [Step 1 validation record](../validation/phase-2a-connections.md) document the reviewed checkout. |
| Step 2 changes | The [transport baseline](companion-transport-baseline.md) pins the USB, TCP, and BLE sources, records initial acceptance targets, and sets the macOS BLE verification order. The [Step 2 validation record](../validation/phase-2a2-protocol-backends.md) records the separate checkout and static checks. |
| Step 3 changes | The [standalone macOS BLE probe](../../tool/ble_probe/README.md) carries the pinned backend, a private transport, and structural evidence for finite query/start. The [Step 3 validation record](../validation/phase-2a3-ble-host.md) tracks software and real-device evidence. |
| Step 4 changes | The standalone probe adds a private root-to-worker bridge and drives the existing runtime with an owned SQLite fixture. [Step 4 validation record](../validation/phase-2a4-ble-worker.md) |
| Planned changes and open questions | The [proposed responsibilities](#responsibilities-and-future-seams), [compatibility inventory](#compatibility-inventory), and [handoffs](#phase-and-step-handoffs) identify the future work and the evidence it still needs. |

## Current call paths

### CLI

[`runCli`](../../apps/meshctl/lib/meshctl.dart) dispatches the product commands.
The session and datagram entry points require an explicit `--port`. Their
injected transport factory is `CompanionTransport Function(String)` and the
production default is `_createUsbSessionTransport`. [CLI guide](../cli.md)

| Command family | Current path and responsibilities |
| --- | --- |
| `ports` and `port-check` | `runCli` dispatches to `SerialPorts.listPorts` (sorted metadata) or `SerialPorts.checkPort` (open and close the selected path). These native diagnostics have no storage, `MeshCoreSession`, or protocol exchange. [Dispatch](../../apps/meshctl/lib/meshctl.dart) · [Serial port API](../../packages/meshcore_link/lib/src/serial_ports.dart) |
| `info` and `watch` | `SessionOptions.port` → `runSessionCommand` → a fresh USB transport and `MeshCoreSession`. Info emits an initialized snapshot after confirmed close. Watch observes state and unassociated response summaries without reading the inbox. Its optional duration starts at ready, and JSON watch uses NDJSON. Both settle session and observer cleanup. [Session command](../../apps/meshctl/lib/src/session_command.dart) |
| `datagram send/listen/ping/respond` admission | `DatagramInput.port` → `runStoredDatagram` → `BusinessStorage` and `CoreStorage.resolveParameters`. Both modes acquire storage and resolve effective settings or a selected preset before transport creation. `DatagramOptions.effective` carries the invocation's explicit port into the unrecorded runner. [Options](../../apps/meshctl/lib/src/datagram_options.dart) · [Storage dispatch](../../apps/meshctl/lib/src/stored_datagram_command.dart) |
| Unrecorded datagrams | `runDatagramCommand` creates one session. Its raw runner does one send or one bounded reception, and its task runner delegates to `MeshchanPingTask` or `MeshchanResponderTask`. Unrecorded JSON listen streams datagram summaries and a final result. The command settles actual device, storage, and signal-source cleanup. [Datagram command](../../apps/meshctl/lib/src/datagram_command.dart) |
| Recorded datagrams | `runRecordedDatagram` → `CoreStorage.record`. Core commits registration before invoking the lazy transport factory, then owns the session and either a raw send/listen operation or a Ping/Responder task. It observes logical and cleanup saves separately. The CLI finalizes storage and its signal source before the final envelope. Recorded listen reports its bounded end summary. [Recorded command](../../apps/meshctl/lib/src/recorded_datagram_command.dart) · [Recording](../../packages/meshchan_core/lib/src/recording/recording.dart) · [Raw operation](../../packages/meshchan_core/lib/src/recording/raw_operation.dart) |

CLI output preserves the versioned JSON/NDJSON and safe failure projections.
The existing exit categories include `64` for usage, `69` for device or
cleanup failures, `74` for host or output failures, and `130`/`143` for
effective interrupts or termination signals. Cleanup and output errors
retain their own evidence under the existing exit precedence.
[Output writer](../../apps/meshctl/lib/src/cli_output.dart) ·
[CLI exit rules](../cli.md#new-machine-schema-and-exit-precedence)

### macOS App

`RuntimeController` sends requests to a long-lived worker isolate. Both device
requests carry `String port`, and both worker transport factories are
`CompanionTransport Function(String)`. The worker uses one `DeviceGate` for
Refresh, Check, and recorded diagnostics.
[Controller](../../apps/meshchan_app/lib/runtime/controller.dart) ·
[Request types](../../apps/meshchan_app/lib/runtime/protocol.dart) ·
[Worker](../../apps/meshchan_app/lib/runtime/worker.dart)

| Entry | Current path and responsibilities |
| --- | --- |
| Offline startup | The worker opens one `CoreStorage` handle and serves offline Drafts, Profiles, Settings, and History. Enumeration and port open occur on explicit device actions. [Worker](../../apps/meshchan_app/lib/runtime/worker.dart) · [App startup and shutdown](../../apps/meshchan_app/README.md#runtime-startup-and-shutdown-1d3) |
| Device Refresh and selection | `DeviceModel.refresh` → `refreshDevicePorts` → `RefreshDevicePorts`. The worker briefly holds the gate while listing port metadata. `DeviceModel.select` accepts an observed exact path. Failed refresh makes the prior list stale, and successful refresh clears a selection when the port is absent. [Device model](../../apps/meshchan_app/lib/device/model.dart) |
| Device Check | `DeviceModel.check` → `startDeviceCheck(port, options)` → `StartDeviceCheck` → worker lease → `FiniteDeviceCheck.run` → a fresh USB transport and `MeshCoreSession`. This initializes, publishes a timestamped device snapshot, and awaits session and observer cleanup. Check does no inbox reads, RF sends, or run recording. [Check runner](../../apps/meshchan_app/lib/runtime/device_check.dart) · [Check projections](../../apps/meshchan_app/lib/runtime/device_protocol.dart) |
| Recorded Ping/Responder | `DiagnosticsModel.startDiagnostic` freezes the selected path and parameter request → `startRecordedDiagnostic` → `StartRecordedDiagnostic`. The worker claims the gate before parameter resolution, then uses `CoreStorage.record` with a lazy transport factory. After registration commits, core creates a fresh session and the selected task. `RecordingAdapter` observes task, save, and cleanup facts and settles App subscriptions. [Diagnostics model](../../apps/meshchan_app/lib/diagnostics/model.dart) · [Worker](../../apps/meshchan_app/lib/runtime/worker.dart) · [Recording adapter](../../apps/meshchan_app/lib/runtime/recording_adapter.dart) |
| Cancel and normal Quit | Attempt-scoped Cancel acknowledges intent. The device gate waits for actual cleanup. Normal Quit also settles the draft decision, admitted storage work, recording saves, and maintenance. The controller requires affirmative release plus observed worker exit when a worker was started. Pending release keeps the gate occupied. Failed or unknown release is held in a faulted or quarantined state and can veto Quit. [Controller](../../apps/meshchan_app/lib/runtime/controller.dart) · [Worker](../../apps/meshchan_app/lib/runtime/worker.dart) · [Quit contract](flutter-host.md#normal-quit-and-desktop-behavior) |

### Shared transport and session

[`CompanionTransport`](../../packages/meshcore_link/lib/src/transport/companion_transport.dart)
already carries complete inner Companion frames through a single-subscription
stream. The owner subscribes before open and consumes without pausing.
[`SerialTransport`](../../packages/meshcore_link/lib/src/transport/serial_transport.dart)
owns native serial configuration, one reader, outer encoding and incremental
decoding, local writes, and actual cleanup. [Serial framing](../protocol/serial-framing.md)

[`MeshCoreSession`](../../packages/meshcore_link/lib/src/session/meshcore_session.dart)
owns a fresh transport for one attempt. `connect` starts bounded initialization
with `DEVICE_QUERY` and `APP_START` and associates `DeviceInfoResponse` and
`SelfInfoResponse` respectively. A single pending request and bounded ready
FIFO associate matching replies with local write results. Initialization and
per-dispatch deadlines are independent. Unassociated input can be observed
without dequeuing the device inbox. Explicit
[`MeshCoreReception`](../../packages/meshcore_link/lib/src/session/meshcore_reception.dart)
holds the sole shared-inbox read lease, including against manual reads.
It issues bounded reads and can consume ordinary queued chat, whose body is
discarded. [Session contract](../protocol/companion-session.md) ·
[Channel datagrams](../protocol/channel-datagrams.md)

`close` stops admission and settles logical work promptly. Its shared future
awaits the actual transport close and inbound subscription cleanup. Close
failures retain their own evidence. One attempt has one session and transport.
The finite [Ping/Responder tasks](../../packages/meshcore_link/lib/src/diagnostics/diagnostic_tasks.dart)
publish separate [result and cleanup facts](../../packages/meshcore_link/lib/src/diagnostics/diagnostic_results.dart)
under the [task contract](../protocol/diagnostic-tasks.md).

### USB initialization policy

CLI `_createUsbSessionTransport` passes `appCompletionQueries: false`. Both
App worker USB factories use `createUsbCompanionTransport` directly, with the
default `appCompletionQueries: true`. On the generic path the App retains
an extra `DEVICE_QUERY` for each initialization command. The CLI omits those
generic completion queries and passes initialization through on noncandidate
USB interfaces.

The USB wrapper checks selected-port metadata for candidate VID/PID
`303a:1001` at open. The serial startup decoder can use bounded initial
`DEVICE_QUERY` synchronization on that candidate interface. A decoded
`Heltec V4.3 OLED` match enables the model-specific path on both hosts, including
an `APP_START` completion query with evidence of `SELF_INFO` and matching
device information after that query. These are host- and device-specific
completion rules. Companion initialization itself continues to use the session's
typed response association and deadlines. Future TCP and BLE adapters require
their own verified framing and initialization behavior, with USB-specific
handling confined to the USB adapter.
[USB wrapper](../../packages/meshcore_link/lib/src/transport/usb_initialization_transport.dart) ·
[Startup synchronizer](../../packages/meshcore_link/lib/src/transport/usb_startup_sync.dart)

## Responsibilities and future seams

| Concept | Responsibility | Status |
| --- | --- | --- |
| Connection target | Represent the explicit target of one operation. Construction performs no discovery or I/O. | Proposed. The current CLI and App pass the selected USB path. |
| Transport | Own one local connection's lifecycle and exchange complete Companion frames. | Existing `CompanionTransport` boundary. A target-based factory is planned. |
| Session | Own Companion initialization, command association, deadlines, and inbox access. | Existing `MeshCoreSession` boundary. |
| Operation preset | Supply diagnostic parameters such as operation, channels, routes, endpoint test labels, and budgets. | Existing `ConnectionProfile` and resolver behavior. |
| Saved connection configuration | Persist a selection aid for a future explicit choice. | Planned for 2D, including its schema and migration. |

The current `ConnectionProfile` has a local ID, name, UTC update time, typed
send/listen/Ping/Responder parameters, and an optional `portHint`. The resolver
uses the requested or default preset as a parameter source. The selected USB
path and any per-run payload come from the invocation.
[Profile model](../../packages/meshchan_core/lib/src/models/connection_profile.dart) ·
[Parameter resolver](../../packages/meshchan_core/lib/src/parameter_resolver.dart)

The communication core `meshcore_link` and business/storage core
`meshchan_core` are Flutter-independent. The App owns Flutter UI and runtime
coordination. Reuse the existing frame and session abstraction for new
adapters. For macOS BLE, the chosen direction assigns the plugin, GATT,
notification provenance, and physical connection and release to the Flutter
root isolate. The worker keeps the session, device gate, storage, and recording
responsibilities. The root owns a broker and the worker owns its transport
proxy. The Step 4 fixture exercises open readiness, full frames, actual
per-write results, safe faults, and affirmative close. Cancel starts physical
cleanup independently of a pending open or write. A missing close or worker
release keeps the corresponding owner unavailable. Normal Quit requires
runtime release, acknowledgement, actual worker exit, and root cleanup.
The joint host scenario verified query/start and physical release with the
dual-patch 6.2.1 probe and paired Heltec target. Same-process reconnect has
synthetic coverage. The bridge is private to the probe and the recording
path retains its existing owner. [Step 4 decision](../validation/phase-2a4-ble-worker.md#execution-location-decision)
[Link exports](../../packages/meshcore_link/lib/meshcore_link.dart) ·
[Core boundaries](offline-core.md#package-responsibilities-and-dependency-direction) ·
[App boundaries](flutter-host.md#package-boundaries-and-host-structure)

## Behavior to preserve

| Area | Compatibility requirement |
| --- | --- |
| Offline and explicit selection | Normal App startup supports offline storage and editing without touching a device. Device Check and diagnostics use the selected path. The CLI requires its invocation's `--port`, including when a preset/default supplies parameters. `portHint` is optional local metadata and grants no device access. [App selection](flutter-host.md#explicit-device-selection-and-finite-checks) · [Profile model](../../packages/meshchan_core/lib/src/models/connection_profile.dart) |
| Ownership and deadlines | Keep one App device lease, one transport reader per session, one pending request, one bounded FIFO, and one explicit inbox consumption path. Preserve task, initialization, command and reception limits and the absence of implicit retry or reconnect. Development peer send timing is separately opted in. [Session deadlines](../protocol/companion-session.md#deadlines-cancellation-and-cleanup) · [Reception](../protocol/companion-session.md#explicit-bounded-reception-1b4) |
| Delivery evidence | Local write completion proves the adapter's local write boundary. Companion OK associated with a successful local write confirms device acceptance. A correlated exact-content PONG establishes the application round trip when the task also confirms local acceptance. RTT covers the end-to-end application timing. Success and cleanup remain separate. [Result types](../../packages/meshcore_link/lib/src/diagnostics/diagnostic_results.dart) · [Task results](../protocol/diagnostic-tasks.md#results-and-actual-cleanup) |
| Cancel, Quit, and uncertain release | Keep the first logical outcome, wait for actual device and observer cleanup, and settle admitted storage work. Release confirmation controls lease reuse and normal Quit. An uncertain native serial handle or database owner remains quarantined. Cancellation does not undo an accepted or remotely deferred send. [Serial cleanup](../../packages/meshcore_link/lib/src/transport/serial_transport.dart) · [App Quit](flutter-host.md#normal-quit-and-desktop-behavior) · [Storage close](../../packages/meshchan_core/lib/src/storage/storage.dart) |
| Persistence and continuity | Preserve exclusive data-directory ownership through recovery, admitted work, and actual SQLite close. Drift schema `1` has drafts, operation presets, settings, and diagnostic runs. `stored_profiles` carries `port_hint` and typed operation parameters serialized as JSON. Creation is transactional. `onUpgrade` rejects newer versions as unsupported and other upgrade requests as corrupt. A real migration and preserved historical data belong to 2D. [Database](../../packages/meshchan_core/lib/src/storage/database.dart) · [Schema](../../packages/meshchan_core/lib/src/storage/schema.drift) · [Directory owner](../../packages/meshchan_core/lib/src/storage/ownership.dart) |
| Safe diagnostic data | `DiagnosticConfiguration` keeps structural fields such as channels, budgets, route descriptor/path length, and content byte length. Bounded version-1 export can include opaque local run IDs, app version, timestamps, results, and cleanup. Keep connection addresses/paths, peer/device identifiers, profile identity, exact route bytes, nonce, keys and raw frame or payload content out of safe exports. Local preset editing and explicit Device/Info views have separate field boundaries. [Safe snapshot](../../packages/meshchan_core/lib/src/models/diagnostic_configuration.dart) · [History export](../../packages/meshchan_core/lib/src/history/history_repository.dart) · [Export contract](offline-core.md#privacy-retention-query-and-export) |
| USB compatibility | Keep each host's existing initialization policy and the bounded Heltec handling during the migration. Retain the zero default startup delay and existing time budgets. [USB initialization policy](#usb-initialization-policy) |
| Limits and historical closure | Intermittent initialization remains observed, including a stopped Build 10 attempt before the successful follow-up. Beta Build 5 covered one real unplug/error and explicit replug/reselect/new Check. This establishes that finite recovery path. General USB reliability, error timing, independent specified relay paths, and broader platforms remain outside the measured scope. [Build 10 first attempt](../validation/phase-1e12-publication.md#same-image-host-hardware-attempt) · [Beta limits](../validation/phase-1d11-rf-matrix-completion.md#limits-and-1e-handoff) |
| Signing | The macOS App and complete CLI use the ongoing `local-adhoc` policy. Only an explicit maintainer decision to adopt Developer ID Application signing changes that policy. There is no automatic change at Beta, MVP, or any other milestone, including to notarization or stapling. PR #45's Developer ID preflight block is historical. PR #46 introduced the local route. [Release policy](../releases/phase-1e-plan.md#current-signing-decision) · [Signing guide](../releases/phase-1e6-signing.md#local-signing-policy) · [Signing configuration](../../tool/release_signing_policy.json) · [Historical signing record](../validation/phase-1e6-signing.md#historical-developer-id-route) |

## Compatibility inventory

The source-only openHop peer, idle probe, and channel audit share
[`OpenHopPeerConfig.createTransport`](../../apps/meshctl/tool/support/openhop_peer_runner.dart).
An explicit private `tcpPort` selects `OpenHopTcpTransport` on the configured
host. The default `OpenHopFrameTransport` uses a JWT-authenticated binary
WebSocket proxy. REST preflight uses its credential reference separately from
the TCP frame connection. Neither mode falls back to the other. Both adapters
reuse the serial envelope codec over their byte streams, and TCP local write
completion is a socket sink flush. [Development adapters](../../apps/meshctl/tool/support/openhop_frame_transport.dart) ·
[Development acceptance](../openhop-acceptance.md#explicit-development-tcp-mode)

[Existing TCP tests](../../apps/meshctl/test/openhop_tcp_test.dart) use
loopback for split/coalesced input, late-open cleanup, remote close, timing
and cancellation, and explicit connection mode selection. The development
peer can opt in to a separate finite send-confirmation budget and start its
PONG window at acceptance. That policy leaves the total task deadline in
place. A server-deferred send can outlive client close.
[Historical delayed-OK software and native record](../validation/phase-1d11-delayed-ok-client.md)

| Initial target | Reviewed evidence | Open question for follow-up |
| --- | --- | --- |
| USB A on macOS arm64 | Heltec V4.3 OLED, reported firmware `v1.18.0-81dbae5`, protocol code `14`. Build 10 covered Check, recorded RF with the peer, Cancel, Quit, and closed History. [Build 10 host record](../validation/phase-1e12-publication.md#same-image-host-hardware-verification) | Confirm current availability and select representative additional USB targets if needed. |
| Controlled openHop B, direct TCP | Historically selected port `5050`. Build 5 and Build 10 recorded finite Direct RF with the selected peer. Earlier reported installation versions were Repeater `1.1.5.dev231` and Core `1.1.4.dev9`. Reviewed upstream source pins are separate. [Deployment observations](../openhop-acceptance.md#observed-deployment-differences) · [Build 5 matrix](../validation/phase-1d11-rf-matrix-completion.md#actual-host-matrix) · [Build 10 host record](../validation/phase-1e12-publication.md#same-image-host-hardware-verification) | Confirm B's current deployment version and state, physical modem identity and firmware, and compatibility targets beyond this deployment. |
| Controlled openHop B, binary WebSocket | Historical bounded initialization and a later passive-window failure preceded a separately selected TCP run. A virtual Companion has one client slot and a shared inbox. [Development acceptance](../openhop-acceptance.md) · [November 15 follow-up](../validation/phase-1d8-hardware-2026-11-15.md#explicit-tcp-continuation-and-real-rf) | Confirm current deployment and transport behavior separately from direct TCP. |
| BLE candidate | Product device access is USB-only. BLE feasibility remains open. [App device baseline](../../apps/meshchan_app/README.md#explicit-finite-device-checks-1d6) | Identify hardware and firmware, then verify macOS permissions, explicit selection, GATT services and characteristics, frame boundaries, notification/write semantics, errors, disconnect and actual release, and isolate compatibility. |

The App and shipped CLI have no TCP/BLE connection entry or saved target
configuration. The openHop evidence applies to the recorded peer, mode, and
scenario. Support for other TCP Companion implementations awaits validation.

The [Step 2 transport baseline](companion-transport-baseline.md) records the
shared inner-frame contract, USB/TCP serial envelopes and firmware-specific
BLE characteristic boundaries. It places `bluetooth_low_energy` 6.2.1 first
for the minimal macOS host and leaves plugin execution location open for
worker cooperation tests. The first host attempt on a Heltec V4.3 timed out
on the query and confirmed release. The [separately authorized paired
retest](../validation/phase-2a3-ble-host.md#paired-host-retest) completed both
commands, verified native notifications and expected lengths, and confirmed
release on the same target.

## Phase and step handoffs

| Subversion | Scope |
| --- | --- |
| 2A | Connection model, BLE feasibility, architecture seams, and existing USB entry migration. |
| 2B | Production TCP support in the CLI and macOS App. |
| 2C | Production BLE support in the macOS App. |
| 2D | Saved connection configurations, unified interaction, and database migration. |
| 2E | Disconnection recovery, connection switching, and lifecycle hardening. |
| 2F | Integrated real-device acceptance and a locally signed engineering release. |

| 2A step | Status | Handoff |
| --- | --- | --- |
| 1 | Completed | Fix the scope and baseline in this document and the [validation record](../validation/phase-2a-connections.md). |
| 2 | Completed | Pin the protocol baseline, acceptance targets, and BLE candidates in the [transport baseline](companion-transport-baseline.md) and [validation record](../validation/phase-2a2-protocol-backends.md). |
| 3 | Host and software checks complete, paired main scenario passed | The [real scenario ledger](../validation/phase-2a3-ble-host.md#real-ble-scenario-ledger) retains both attempts, actual release, and remaining coverage. |
| 4 | Joint hardware Case A and normal Quit passed | Adopt root BLE ownership and worker session, gate, and storage for the remaining design. The [scenario ledger](../validation/phase-2a4-ble-worker.md#real-ble-scenarios) retains the synthetic and outstanding hardware boundaries. |
| 5 | Planned | Implement pure Dart targets for one explicit operation. Carry identity as data and keep target construction free of discovery, plugin startup, or implicit selection. Preserve the existing USB path semantics. |
| 6 | Planned | Create a fresh transport per selected target. Preserve subscribe-before-open and the complete-frame, local-write, and actual-release contracts. A future BLE factory can supply a worker proxy to a root-owned connection. |
| 7 | Planned | Migrate internal CLI entry points. |
| 8 | Planned | Migrate App requests and worker entry points. |
| 9 | Planned | Run targeted regressions and build verification. |
| 10 | Planned | Record 2A delivery and hand off later-phase work. |
