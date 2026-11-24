# Companion transport baseline

Phase 2A Step 2 records the USB, TCP, and BLE protocol and the order for
macOS BLE feasibility work. The [connection architecture](companion-connections.md)
covers the existing call paths and ownership boundaries. The
[Step 2 validation record](../validation/phase-2a2-protocol-backends.md)
identifies the reviewed checkout, source retrieval, and historical observations.

## Evidence and source baseline

**Documented** means a published contract or API description. **Source-reviewed**
means behavior traced in the identified implementation. **Historically observed**
applies to the device, image, configuration, and run in the cited record.
**Requires measurement** identifies a concrete feasibility or acceptance check.
**Unknown** means the evidence does not identify a value or behavior. Public
sources in this document and the validation record were reviewed on November 24,
2026 (Europe/Dublin).

The existing Meshchan wire baseline is MeshCore
[Companion v1.18.0](https://github.com/meshcore-dev/MeshCore/releases/tag/companion-v1.18.0)
at [`81dbae592ffad40b4212bc0b37e82b38da08f4bc`](https://github.com/meshcore-dev/MeshCore/tree/81dbae592ffad40b4212bc0b37e82b38da08f4bc).
The official tag resolves to that commit and its prefix matches A's historical
firmware report. The report identifies a source version without establishing
the installed image hash, build configuration, or current device state. The
pin applies to the protocol and the firmware paths selected by the board build.
A's USB result supplies no runtime evidence for either BLE implementation.

| Source | Applicability |
| --- | --- |
| [Companion protocol](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/docs/companion_protocol.md) | Documented message and transport contract at the firmware pin. Use the corresponding handlers for implementation discrepancies. |
| [BaseSerialInterface](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h), [Arduino serial](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ArduinoSerialInterface.cpp), [Wi-Fi serial](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/wifi/SerialWifiInterface.cpp) | Source-reviewed size, markers, stream state machines, and Wi-Fi client boundary. |
| [Companion entry](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/main.cpp), [MyMesh handlers](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp), [BaseChatMesh](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseChatMesh.cpp) | Source-reviewed interface selection, initialization, inbox, and channel send/receive. |
| [ESP32 BLE](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp), [nRF52 BLE](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp) | Source-reviewed branches for the named stacks. Identify the target build and chip before applying individual branch findings. |

## Framing and protocol across transports

| Layer or event | USB serial | Direct TCP | BLE GATT |
| --- | --- | --- | --- |
| Inner Companion frame | The transport emits one complete, owned frame, including the opcode. | Same contract for each frame produced by the incremental stream decoder. | Deliver one complete, owned inner frame from an actual device notification on the selected characteristic. Validate the characteristic and frame before delivery. |
| Wire unit | Host writes `0x3C` and device writes `0x3E`, each followed by a uint16 little-endian length and that many content bytes. Length includes the opcode and excludes all three envelope bytes. | Reviewed source-only openHop TCP and the pinned MeshCore Wi-Fi interface use the same serial envelope. Each socket read is an arbitrary fragment of an ordered byte stream. A transparent serial bridge qualifies only if it preserves these bytes in order across splits and coalescing. | The intended protocol carries one inner frame per characteristic write or notification value when it fits. Check the stack-specific oversized-value behavior below. The serial marker and length would become part of the command if included. |
| Receive and malformed input | Meshchan's decoder handles split/coalesced data, skips bounded pre-marker noise, rejects lengths outside `1..176`, and preserves earlier completed frames before a decoder error. EOF with an unfinished frame is truncation. The USB startup synchronizer has a narrower, selected-device purpose. | The development adapter uses the same incremental decoder, surfaces its error, and handles clean EOF as peer closure or partial-frame EOF as truncation. | Characteristic values provide the boundary. Apply the existing inner-frame limits and response parsing. Measure disconnect, subscription loss, and oversize behavior with the chosen stack. |
| Local write boundary | Successful adapter write establishes the local serial write boundary. | Successful `Socket.flush()` establishes the local sink boundary. | A with-response write establishes the GATT write result. A without-response result can establish local submission or queue admission, depending on the backend. |
| Open and close | One reader, one owner and one attempt. Close awaits the reader and native handle. | Development close awaits late open, closes/destroys the socket, and cancels the input subscription. | Open includes connection, GATT discovery and notification readiness. Close needs evidence for scan/notification stop, pending actions, local disconnect, subscription disposal, and stale callback isolation. |
| Endpoint and shared state | Explicitly selected local port. A reception lease controls destructive reads within one session. | The reviewed raw client has no TLS or protocol authentication. Restrict this plaintext endpoint to a controlled, trusted network. Confirm the actual server's exposure, access policy, client slot, and inbox sharing. | Explicit selection and system Bluetooth permission apply. Check target-specific link security and system pairing behavior. Preserve exclusive inbox ownership at the session level. |

Source-reviewed Meshchan interfaces and call sites include
[`CompanionTransport`](../../packages/meshcore_link/lib/src/transport/companion_transport.dart),
[`SerialTransport`](../../packages/meshcore_link/lib/src/transport/serial_transport.dart),
[`SerialFrameDecoder`](../../packages/meshcore_link/lib/src/protocol/serial_framing.dart),
[`OpenHopTcpTransport` and `OpenHopFrameTransport`](../../apps/meshctl/tool/support/openhop_frame_transport.dart),
and [tool mode selection](../../apps/meshctl/tool/support/openhop_peer_runner.dart).
The [framing contract](../protocol/serial-framing.md) defines the 1,024-byte
noise budget and fatal parser state. The [TCP test source](../../apps/meshctl/test/openhop_tcp_test.dart)
covers splits/coalescing, late-open disposal, remote EOF, cancellation, and
explicit mode selection in the development adapter.

### Initialization and data path

[`MeshCoreSession.connect`](../../packages/meshcore_link/lib/src/session/meshcore_session.dart)
subscribes to the Dart frame stream before `transport.open()`. With BLE, there
is a second readiness boundary within open. Enable notifications and confirm
readiness after connecting and discovering GATT, before dispatching a
Companion command. With the default zero startup delay, the session sends
`DEVICE_QUERY` (`0x16`, target 3), associates `DEVICE_INFO` (`0x0D`), then
sends `APP_START` (`0x01`) and associates `SELF_INFO` (`0x05`). Each command
needs both a successful local write and the associated response. Other native
events and Companion pushes can interleave. These are expected responses for
the typed requests, with no assumption about the total number of frames
during initialization. The default 15-second total initialization deadline
includes open, and the default request budget is 5 seconds from dispatch.
Device errors, parser or transport errors, EOF and expired deadlines settle
the attempt under the [session contract](../protocol/companion-session.md).

The [CLI USB factory](../../apps/meshctl/lib/meshctl.dart) explicitly sets
`appCompletionQueries: false`. Both [App worker factories](../../apps/meshchan_app/lib/runtime/worker.dart)
use the default `true`. The [USB wrapper](../../packages/meshcore_link/lib/src/transport/usb_initialization_transport.dart)
keeps its generic App completion queries and the bounded special handling
for candidate VID/PID `303a:1001` and decoded Heltec V4.3 OLED, including
[`DEVICE_QUERY` startup synchronization](../../packages/meshcore_link/lib/src/transport/usb_startup_sync.dart)
and the model-specific completion query after `APP_START`. Keep those
rules confined to the existing USB host and device paths.

`CMD_SEND_CHANNEL_DATA` is decimal 62 (`0x3E`). The matching Companion OK
plus local write success establishes Companion acceptance. An exact correlated
remote PONG establishes the diagnostic application round trip when the local
send is also confirmed. The radio recipient's firmware queues a
`RESP_CODE_CHANNEL_DATA_RECV` entry (decimal 27, `0x1B`) and pushes
`MSG_WAITING` (`0x83`) as a wake-up signal. The explicit reception owner
drains through `SYNC_NEXT_MESSAGE` (`0x0A`) under its bounded read lease and
receives `NO_MORE_MESSAGES` when the queue is empty. Ordinary queued chat
can be consumed and its body discarded along that path. Info, Device Check,
and passive CLI watch observe or query without dequeuing. See the
[command and response codec](../../packages/meshcore_link/lib/src/protocol/companion_messages.dart),
[reception owner](../../packages/meshcore_link/lib/src/session/meshcore_reception.dart),
and [channel contract](../protocol/channel-datagrams.md#layers-commands-and-fields).
The legacy `CMD_SEND_RAW_DATA` (25) is a separate firmware command with
different fields and limits.

### Capacity by layer

| Layer and direction | Bound and evidence |
| --- | --- |
| Inner Companion and stream wire, both directions | The pinned `BaseSerialInterface.h` sets 176 content bytes and Meshchan accepts `1..176`. The USB/TCP envelope adds three bytes, for at most 179 on the wire. |
| Channel send, host to Companion | The pinned send branch enforces the 165-byte radio group payload limit. With `P` actual encoded path bytes, the host content is `5 + P + payload` and the cap is `min(165, 176 - 5 - P)`. Flood and zero-hop Direct allow 165 payload bytes, and a valid 64-byte Direct path allows 107. |
| Channel receive, Companion to host | Meshchan requires exactly `9 + payload` bytes for `0x1B`, with at most 165 payload bytes and 174 total. The firmware's 167-byte callback bound and the prose's send interpretation differ from the actual send handler. |
| Diagnostic v1, either radio direction | Subtract 34 bytes from the applicable send payload capacity. These example routes allow 131 and 73 bytes of application content respectively. With two known routes, use the smaller directional capacity. |
| GATT, central write and peripheral notification | The ATT MTU is a protocol parameter. Ordinary writes and notifications have ATT overhead and backend/characteristic constraints. On macOS, obtain the maximum for the selected write type and independently measure complete notification delivery. Both effective limits may be below the Companion cap. Keep oversize risk open until tested and keep the current product limits. [Bluetooth Core 6.2, Vol 3 Part F](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-62/out/en/host/attribute-protocol--att-.html) |

The detailed [capacity derivation](../protocol/channel-datagrams.md#capacity-and-implementation-discrepancies)
is based on the pinned [MeshCore radio constants](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/MeshCore.h)
and the current Meshchan codec. An ATT long write is a distinct operation
from multiple ordinary writes. The reviewed firmware consumes characteristic
write values as command units. App-level `splitWrite` would submit separate
commands and has no evidenced reassembly contract. CoreBluetooth's advertised
maximum alone establishes neither peer long-write support nor notification
capacity.

### Completion and ownership

Each attempt has a single owner, one ordered frame stream and a single-use
transport. The transport owns I/O, delivery of transport errors and peer
closure, rejection of operations after stop, and actual resource settlement.
The session owns command association, initialization and request deadlines,
late-response handling, and the sole inbox lease. Tasks own their deadlines,
admission, cancellation, and immutable outcomes. App runtime owns the device
gate and quit handshake. Closing stops logical admission promptly and awaits
actual transport and observer release on a separate path. A cancel
acknowledgment or timeout is insufficient release evidence. An unresolved
or failed close retains ownership isolation. No transport adds implicit retry,
reconnect or fallback. Client close also leaves any already accepted or
server-deferred operation outside its control.
[Task cleanup](../protocol/diagnostic-tasks.md#results-and-actual-cleanup) and
[App quit](flutter-host.md#normal-quit-and-desktop-behavior) define the existing
boundaries.

### Pinned firmware differences

| Firmware path | Source-reviewed behavior |
| --- | --- |
| USB at v1.18.0 | The firmware rejects oversized sends but truncates oversized incoming content after consuming its tail. Meshchan instead fails invalid declared lengths and closes the attempt. [Arduino serial state machine](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ArduinoSerialInterface.cpp#L24-L72) |
| ESP32 native Wi-Fi at v1.18.0 | The Companion build can expose raw TCP (default port 5000). Its binary stream parser uses the USB envelope. Accepting a replacement client resets the receive header and retains the send queue. The firmware can send a queued reply from the previous client before it reads the replacement client's first command. Wi-Fi join credentials are separate from Companion access. The raw serial interface implements no TLS or client authentication. [Build selection](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/main.cpp#L19-L84) · [Client replacement and queue drain](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/wifi/SerialWifiInterface.cpp#L52-L106) |
| ESP32 BLE at v1.18.0 | Nordic UART Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`. Device RX `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` is host → device, with the Write property. Device TX `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` is device → host, with Read and Notify plus a CCCD. Use with-response writes for this RX and subscribe to TX notifications before initialization. The PIN and authenticated bonding path belongs to the system and firmware. The handler queues one value per write callback, subject to size and queue limits, and publishes one value per notify call. [GATT registration](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp#L7-L53) · [RX value](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp#L114-L128) · [TX queue](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp#L168-L215) |
| Other BLE builds at v1.18.0 | nRF52 uses Bluefruit BLEUart with encrypted MITM security and a PIN. Its receive callback drains available bytes. The unbuffered transmitter can report failure after submitting some notification chunks. RP2040 registers the same service and RX/TX directions with authenticated Write and Read/Notify, and drops a notify if value bytes plus three exceed its current MTU. Confirm the actual chip, build flags, characteristic properties and callback boundaries before applying any stack's observations to a target. [nRF52 security and UART setup](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp#L159-L173) · [nRF52 RX callback](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp#L340-L377) · [RP2040 registration and I/O](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/rp2040/SerialBLEInterface.cpp#L8-L140) |
| Older serial capacity | Official Companion v1.14.0 at `9f1a3eafcc04a1bb200e75ba8cd5921cc04ce203` defines 172 inner bytes. That is an older frame buffer bound. [v1.14.0 definition](https://github.com/meshcore-dev/MeshCore/blob/9f1a3eafcc04a1bb200e75ba8cd5921cc04ce203/src/helpers/BaseSerialInterface.h#L5) |

The pinned Companion build can register BLE, Wi-Fi, USB, Ethernet and hardware
serial with one interface manager. It accepts commands from any enabled
interface and forwards outgoing frames to all enabled interfaces. Commands
and inbox state are shared across transports. A genuine BLE notification can
therefore be a response to a command issued over another interface.
[Interface registration](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/main.cpp#L195-L260) ·
[Frame routing](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/MultiSerialInterface.h#L151-L186)

The ESP32 v1.18.0 code calls `setMTU(MAX_FRAME_SIZE)` with 176. If 176 is
negotiated, an ordinary notification can carry at most 173 value bytes
after the three-byte ATT header. A legal 174-byte `0x1B` frame already exceeds
that case. Actual macOS negotiation, truncation/drop behavior, supported ATT
long writes and the maximum complete payload in each direction require
measurement. The pinned
[query/start](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L979-L1036)
and [channel send](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L1114-L1150)
handlers show the command paths. The
[receive callback](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L558-L592)
and [sync-next branch](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L1325-L1333)
show the queue boundary.

The nRF52 build's pinned Bluefruit fork configures the same NUS UUIDs, with
Notify-only TX and Write/Write Without Response RX. The library can emit
multiple notifications of up to `MTU - 3` bytes for an oversized value. In the
default unbuffered mode used here, `BLEUart::write` reports the requested length
or zero. If a later notification chunk fails after an earlier one was submitted,
the call returns zero and the firmware keeps the entire frame queued for retry
while connected. The host can therefore see a frame prefix followed by retried
bytes. The reviewed Companion protocol supplies no host reassembly contract for
those chunks. Treat that sequence as a failed complete-frame exchange.
[Bluefruit properties](https://github.com/meshcore-dev/Adafruit_nRF52_Arduino/blob/d541301665b40959682252911e57b11df3ee651a/libraries/Bluefruit52Lib/src/services/BLEUart.cpp#L155-L165) ·
[Unbuffered default](https://github.com/meshcore-dev/Adafruit_nRF52_Arduino/blob/d541301665b40959682252911e57b11df3ee651a/libraries/Bluefruit52Lib/src/services/BLEUart.cpp#L59-L71) ·
[UART write result](https://github.com/meshcore-dev/Adafruit_nRF52_Arduino/blob/d541301665b40959682252911e57b11df3ee651a/libraries/Bluefruit52Lib/src/services/BLEUart.cpp#L224-L240) ·
[Notification loop](https://github.com/meshcore-dev/Adafruit_nRF52_Arduino/blob/d541301665b40959682252911e57b11df3ee651a/libraries/Bluefruit52Lib/src/BLECharacteristic.cpp#L663-L713) ·
[Firmware retry](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp#L280-L310)

The ESP32 Arduino 2.0.17 stack has an ATT prepare/execute path that commits a
value through one callback. Target support and macOS interoperability still
need measurement. The official Python SDK v2.3.19 corroborates the unwrapped
value path with a TX subscription and single with-response RX write.
[ESP32 stack writes](https://github.com/espressif/arduino-esp32/blob/5e19e086c43d0fa5e5a596497ff8f11a0a43f6c2/libraries/BLE/src/BLECharacteristic.cpp#L228-L323) ·
[SDK adapter](https://github.com/meshcore-dev/meshcore_py/blob/50c92e960e0002d0a3a34af0fda23a518ead6331/src/meshcore/ble_cx.py#L185-L241)

## Initial acceptance targets

The following targets extend the [Step 1 inventory](companion-connections.md#compatibility-inventory).
Channel capability means binary `0x3E` with local write and OK, `0x83` wake-up,
and bounded inbox retrieval of complete `0x1B` frames. An endpoint displaying
device information or supporting text chat establishes a smaller capability.

| Role and transport | Model, platform or version | Required capability and evidence | Unknown and verification stage |
| --- | --- | --- | --- |
| A, existing macOS arm64 USB | Heltec V4.3 OLED, historically reported `v1.18.0-81dbae5`, protocol 14. | Historically observed on Build 10. First Check passed, then the read-only audit stopped on APP_START/SELF_INFO timeout before B TCP or RF. A later run of the same restored image passed finite Check, audit, one exact Direct TCP-peer PING/PONG, active Cancel, normal Quit and independent resource/History checks. Beta Build 5 separately exercised actual unplug, error, and explicit replug, Refresh, reselection and new Check. [Build 10 attempt](../validation/phase-1e12-publication.md#same-image-host-hardware-attempt) · [Build 10 follow-up](../validation/phase-1e12-publication.md#same-image-host-hardware-verification) · [Build 5 matrix](../validation/phase-1d11-rf-matrix-completion.md#actual-host-matrix) | Current availability and image identity unknown. Retain USB behavior in 2A migration regressions. Reconfirm current selected hardware and finite channel capability in 2F. Broader failure timing and recovery belong to 2E/2F. |
| B, controlled openHop direct TCP | Historical port 5050. Reported Repeater `1.1.5.dev231`, Core `1.1.4.dev9`, virtual Companion protocol 14, version `14.0`. The maintainer identified a Heltec V4.3 modem with openHop `1.4.0`. | Source-reviewed serial byte pipe. Historically observed Direct RF with the selected virtual Companion in Build 5 and Build 10. A separate run observed TCP OK and a duty-cycle deferral beyond the request budget. [Deployment observations](../openhop-acceptance.md#observed-deployment-differences) · [Modem report](../hardware-validation.md#finite-matrix-status) · [Delayed OK investigation](../validation/phase-1d11-openhop-ok-investigation.md) | Confirm current service build, binding/access controls, client slot and reply isolation across replacement, selected physical modem and firmware, RF route, and binary push/inbox capability in 2B/2F. The historical two-modem Fabric configuration leaves the actual RF path and current topology unknown. |
| B, openHop binary WebSocket | Same historical deployment reports, separate JWT proxy and REST credential boundary. | Earlier WS initialization and closure passed. A subsequent WS passive window stopped early for an unknown reason. The explicitly selected TCP continuation had its own passive and RF results. [WS development record](../openhop-acceptance.md#passive-window-and-actual-direct-execution-follow-up) · [Separate TCP continuation](../validation/phase-1d8-hardware-2026-11-15.md#explicit-tcp-continuation-and-real-rf) | Current proxy behavior, timeout and binary channel path need separate evidence if this development interface is used in 2F. Product TCP does not inherit the development REST preflight, JWT upgrade or WS result. |
| First macOS arm64 BLE target | Model, chip, installed firmware/build variant, availability and current pairing state are TBD. | Requires an explicitly selected, controlled Companion with a verified BLE build. Step 3 needs query/start and correctly sourced complete notifications. 2C/2F need the full binary channel path and directional size evidence. | Before Step 3, confirm possession/availability, model and chip, firmware/version and build mode, identity selection method, service and characteristic evidence, expected authorization/PIN flow, and authority for a bounded run. A's historical USB image does not qualify a BLE target. |

The pinned openHop source comparators are Core
[`e07722ea96093752ac8b3c6772d653f8b68224bf`](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/server.py#L86)
and Repeater
[`13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b`](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/companion_ws_proxy.py).
The former documents one client slot per virtual Companion. The latter
authenticates JWT, selects the named Companion and forwards arbitrary TCP
chunks in binary WebSocket messages. Its
[inbox implementation](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/companion/frame_server.py#L145-L179)
pops entries from a shared per-Companion queue. Development Core
[`63f9d305a7de79b3356123c07fe7d2f8d3f1e448`](https://github.com/openhop-dev/openhop_core/blob/63f9d305a7de79b3356123c07fe7d2f8d3f1e448/src/openhop_core/companion/frame_server/transport.py)
uses a plain socket listener, incremental length parsing and old-client
eviction. These source pins describe reviewed implementations. The installed
server hashes and any separate network protections remain unknown.
The pinned Core `0x3E` handler requires a configured bridge sender and waits
for the bridge result before OK. Its `0x1B` serializer is a separate binary
path. This makes bridge configuration part of target qualification.
[Core binary handlers](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/commands_messaging.py)

Both pinned Core implementations have a reply-ownership gap at client
replacement. Once dispatched, a channel send can finish after the connection
that issued it has been replaced. The handler sends its result through the
server's current reply queue, so a delayed OK or ERR can reach the replacement
client and be associated with the wrong request. This is a source-reviewed
risk. The behavior of B's installed service remains unverified.
[Earlier Core client lifecycle](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/transport.py#L230-L309) ·
[Development Core client lifecycle](https://github.com/openhop-dev/openhop_core/blob/63f9d305a7de79b3356123c07fe7d2f8d3f1e448/src/openhop_core/companion/frame_server/transport.py#L231-L312) ·
[Reply queue](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/transport.py#L88-L117) ·
[Channel send completion](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/commands_messaging.py#L173-L187)

Require reply isolation for connection replacement on openHop, native Wi-Fi,
native Ethernet, and serial bridges. Qualify replacement only when evidence
shows that the endpoint or controlled deployment prevents replies from
earlier connections reaching the new client, including replies from work
still in progress. For openHop B, establish that boundary for direct TCP in
2B/2F and independently for binary WebSocket if used. If reply ownership
remains unresolved, leave replacement unqualified and record any affected
command results as unconfirmed. Record deployment constraints with the evidence.

Native Wi-Fi/Ethernet Companion and transparent serial TCP bridges are later
qualification categories. Require an explicit endpoint, binary serial framing,
matching Companion binary channel handlers, known client/inbox ownership, and
bounded disconnect/release. Establish sole command ownership across the
Companion's enabled interfaces, including other interfaces on a radio reached
through a bridge. Check raw versus TLS/authenticated deployment conditions
before access.

The pinned CH390 and RAK13800 Ethernet drivers replace the client and reset
receive state while retaining the outgoing queue, as the native Wi-Fi path
does. The Ethernet path drains queued frames before reading the replacement
client's commands. Its binary mode uses the serial envelope.
[Ethernet receive reset and send queue](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ethernet/SerialEthernetInterface.cpp#L44-L78) ·
[CH390 client replacement](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ethernet/ch390/CH390EthernetInterface.cpp#L70-L86) ·
[RAK13800 client replacement](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ethernet/RAK13800/RAK13800EthernetInterface.cpp#L84-L100)

The pinned `ETHERNET_RAW_LINE` branch has a source-level build blocker.
Its transmit code uses `client.write` in the shared base implementation,
where the class exposes a virtual `write` method and declares no `client`
member. Ethernet qualification covers binary framing.
[Raw-line branch](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ethernet/SerialEthernetInterface.cpp#L56-L61) ·
[Ethernet base class](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ethernet/SerialEthernetInterface.h#L9-L60)

A transparent bridge also needs compatible UART settings and propagation or
bounded detection of device-side disconnect. These categories carry no
current support claim.

## BLE backends for the macOS App

The following is an order for feasibility checks. Production dependency and
execution location decisions follow Steps 3 and 4.

### Reviewed release sets

| macOS path | Exact releases | Static fit and build integration |
| --- | --- | --- |
| bluetooth_low_energy | Facade, Darwin, and platform interface all `6.2.1`. The manifests use caret constraints. [Release receipts](../validation/phase-2a2-protocol-backends.md#ble-release-archives) | All Dart `^3.9.2`. Facade and Darwin require Flutter 3.7+, interface 3.3+. Shared Darwin CoreBluetooth Swift sources. CocoaPods declares macOS 10.15 and Swift 5 language mode. SwiftPM declares macOS 10.15 and tools 5.9. [Darwin build files][ble-build] |
| flutter_blue_plus | Facade `2.3.15`, Darwin `9.0.5`, platform interface `9.0.4`. The facade bounds the latter two to the reviewed releases. [Release receipts](../validation/phase-2a2-protocol-backends.md#ble-release-archives) | All Dart `^3.0.0` and Flutter 3.7+. Shared Darwin Objective-C and CoreBluetooth, macOS 10.14 in CocoaPods and SwiftPM, Swift tools 5.9 for SwiftPM integration. [Darwin build files][fbp-build] |

Meshchan's [App manifest](../../apps/meshchan_app/pubspec.yaml) requires
Dart `^3.13.0` and Flutter 3.50+. The installed stable cache reports Flutter
3.50.0 and Dart 3.14.0. The [Runner project](../../apps/meshchan_app/macos/Runner.xcodeproj/project.pbxproj)
targets macOS 12.0 and references Flutter's generated Swift package. Both
reviewed release sets fit the declared floors. Toolchain compilation, arm64
linking and actual packaging still require verification. The
[link](../../packages/meshcore_link/pubspec.yaml) and
[business core](../../packages/meshchan_core/pubspec.yaml) manifests remain
Flutter-independent, as does the [CLI](../../apps/meshctl/pubspec.yaml).

### Darwin capability comparison

| Capability | bluetooth_low_energy 6.2.1 | flutter_blue_plus 2.3.15 / Darwin 9.0.5 |
| --- | --- | --- |
| Central scan and explicit selection | `CentralManager.startDiscovery(serviceUUIDs:)` filters natively, `discovered` can report duplicates, and `stopDiscovery` stops scanning. Advertisement local name and `Peripheral.uuid` come from CoreBluetooth. Use one selected current scan result. [Dart central][ble-dart] · [Swift implementation][ble-native] | `startScan(withServices:, timeout:)`, `onScanResults`, `stopScan`. Use only the service filter to retain native filtering. Combined filters can relax it. `onScanResults` avoids previous-scan cache replay. Advertisement name and platform name are display metadata, with `remoteId` from Darwin. [Dart scan][fbp-dart] · [Native plugin][fbp-native] |
| Connect, cancel and permissions | `connect` settles through connect/failure delegates. `disconnect` requests CoreBluetooth cancel. The disconnect delegate clears GATT and many pending completions. `stateChanged` exposes unauthorized, off and resetting. Darwin exposes neither explicit authorization handling through `authorize` nor a bond/PIN method. Measure system prompts and error delivery. [Swift implementation][ble-native] · [Dart central][ble-dart] | `BluetoothDevice.connect` with `autoConnect: false` defaults to a 35-second connection-event wait after the platform call and requests cancellation on timeout. `disconnect(queue: false)` skips the operation mutex and still acquires the separate disconnect mutex. Adapter events include off and unauthorized, with plugin exceptions and disconnect reasons. The macOS path relies on system pairing. `createBond` and explicit MTU requests are Android APIs. [Dart device][fbp-device] · [Native plugin][fbp-native] |
| Discovery, notification state and service changes | `discoverGATT` walks services, characteristics and descriptors. `setCharacteristicNotifyState` enables or disables notifications and awaits the delegate callback. The reviewed Darwin path has no `didModifyServices` event. Measure service invalidation or prove a safe disconnect boundary before another attempt. [Swift implementation][ble-native] · [Peripheral delegate][ble-delegate] | `discoverServices` and `setNotifyValue` use native discovery and notification-state callbacks. Native `didModifyServices` emits `onServicesReset` and invalidates cached services at the Dart layer. Measure the fate of an in-flight write and notification during reset. [Dart characteristic][fbp-characteristic] · [Dart device][fbp-device] · [Native plugin][fbp-native] |
| Write type, maximum and queue | `getMaximumWriteLength(type:)` calls CoreBluetooth's per-type API. `writeCharacteristic` sends one GATT value. With response it waits for the write delegate. Without response it returns after the native submission call with no wrapper backpressure. A completion slot is keyed by peripheral and characteristic. Serialize and observe pending write settlement. Use the per-type limit on Darwin, where `requestMTU` and `mtuChanged` are unavailable. [Swift implementation][ble-native] | `write` takes the plugin's operation mutex. The default queue is global. Per-device queuing requires calling `setOperationQueueMode(OperationQueueMode.perDevice)` before BLE work. The 15-second default timeout applies to the matching written event after acquiring the mutex and awaiting the platform call. The with-response path uses the native write delegate. The without-response path checks native readiness and reports a local readiness event. Darwin caps ordinary writes by its without-response maximum and 512 bytes. Opt-in `allowLongWrite` for with-response uses the with-response maximum capped at 512. Reported `mtu` is an inference from the ordinary payload cap and cache. Record the write mode and its effective limit separately. Skip app splitting and verify actual write support and deadline behavior. [Queue configuration][fbp-dart] · [Dart characteristic][fbp-characteristic] · [Native plugin][fbp-native] |
| Input provenance | `characteristicNotified` is a broadcast without replay or a local write echo. The shared read/notify delegate routes callbacks unclaimed by an active read to this stream. That branch does not check `error` or `isNotifying`. Avoid active reads on TX and explicitly validate subscription state, peripheral and characteristic, generation, and frame shape. Measure errors and late callbacks. [Dart central][ble-dart] · [Swift implementation][ble-native] | `onValueReceived` includes successful reads and device notifications, with no last-value replay or write echo. `lastValueStream` combines reads, writes, notifications and replays a cached value. Use the former on the selected notify characteristic without active TX reads. Check device, service, characteristic instance and generation before forwarding. [Dart characteristic][fbp-characteristic] · [Native plugin][fbp-native] |
| Native message delivery | The Swift registrar supplies its messenger to generated Pigeon `BasicMessageChannel` APIs. CoreBluetooth delegates call `CentralManagerFlutterApi`. Darwin `CentralManagerImpl` registers handlers at construction and creates its broadcast streams in the owning isolate. The reviewed package provides no background-isolate unsolicited delivery contract. [Darwin registration and generated Swift][ble-swift] · [Dart central and generated Dart][ble-dart-dir] | A native `flutter_blue_plus/methods` MethodChannel uses the registrar messenger, and the Dart Darwin implementation installs `setMethodCallHandler`. Native events are routed to Dart streams in the owning isolate. The reviewed package provides no background-isolate unsolicited delivery contract. [Darwin Dart][fbp-darwin-dart] · [Native plugin][fbp-native] |
| Close and actual release | Separately observe notify disable, Dart subscription cancellation and the disconnect callback. The disconnect event carries peripheral/state, while the native plugin keeps known peripherals and its disconnect path does not drain a pending connect completion. The API has no bounded public dispose/timeout. Measure whether pending connect cancels and late callbacks stay isolated. [Swift implementation][ble-native] | Observe disable, Dart subscription cancellation, local disconnect and settlement of pending Futures independently. Disconnect clears native instance state and delegate while known peripherals remain cached. Check the first-call restart cleanup path too, which polls connections without its own deadline. [Dart device][fbp-device] · [Dart scan and restart][fbp-dart] · [Native plugin][fbp-native] |

Apple's rolling CoreBluetooth docs describe platform-assigned peer UUIDs
(macOS 10.13+), the shared read/notify callback, and per-type write values
(macOS 10.12+ for the size API). A platform UUID and a display name serve
selection within the host. MeshCore identity comes from the initialized
Companion protocol. CoreBluetooth connect has no native timeout, and its
nonblocking cancel can leave commands without a completion. A local
disconnect delegate confirms the app's connection state while the system can
retain a shared physical link. These are API semantics with actual timing
and cleanup still to observe.
[Peer identifier][apple-peer] · [Value delegate][apple-value] ·
[Write length][apple-size] · [Write types][apple-write] ·
[Connect][apple-connect] · [Cancel][apple-cancel]

### Bundle permissions and release terms

The existing Runner [Info.plist](../../apps/meshchan_app/macos/Runner/Info.plist)
has no Bluetooth purpose string. The Step 3 host needs
`NSBluetoothAlwaysUsageDescription` (macOS 11+). The current
[Debug/Profile entitlements](../../apps/meshchan_app/macos/Runner/DebugProfile.entitlements)
allow JIT and network server, and the
[Release entitlements](../../apps/meshchan_app/macos/Runner/Release.entitlements)
file is empty. The Runner deliberately omits App Sandbox. Apple's
`com.apple.security.device.bluetooth` is documented as an App Sandbox hardware
capability (macOS 10.7+). Observe Bluetooth authorization, prompts, denial and
powered-off/reset state under the actual local-adhoc bundle identity and
effective entitlements. Preserve the project's
[local signing policy](../releases/phase-1e6-signing.md#local-signing-policy).
Developer ID, notarization and stapling remain outside this feasibility gate.
[Usage description][apple-info] · [Sandbox entitlement][apple-entitlement] ·
[Authorization state][apple-auth]

- All three bluetooth_low_energy archives include MIT LICENSE and no separate
  NOTICE. Redistribution retains the copyright and permission notice in copies
  or substantial portions. The reviewed macOS path contains no build telemetry
  hook in its manifest, podspec, or Swift package. The Darwin Dart layer can
  log characteristic bytes at INFO. Apply the logging controls in the
  [Step 3 plan](#step-3-macos-ble-host).
  [MIT license][ble-license] · [Dart central][ble-dart]
- All three flutter_blue_plus archives include FlutterBluePlus License 1.6 and
  `NOTICE.md` with the historical BSD-3 text and legacy contributor notices.
  Section 1 requires the copyright and full license text in source
  redistribution and prohibits relicensing. The BSD-3 text calls for retention
  in source and reproduction in binary materials where those terms apply.
  Section 2 covers personal users, registered nonprofits and accredited
  educational institutions subject to its terms and common conditions. Section
  3 requires a commercial license for use by or for a for-profit company,
  including development, testing or evaluation by a for-profit organization
  and commercial use by individuals. One valid commercial license covers the
  federated packages. The offer's current-version condition also applies.
  [Exact license][fbp-license] · [Project notice][fbp-notice]
- License 1.6 permits nonblocking build-time telemetry with package name,
  app name/version, plugin version and date, excluding source and end-user
  data. No corresponding hook was found in the three reviewed macOS-path
  archives. The separately inspected Android 9.0.5 build applies
  `license_ping.gradle` from its variant pre-build path. The script posts
  fields including application ID/name/version, plugin version, day and a
  derived hash, with bounded timeouts and caught failures. No hook was
  executed. [Android build][fbp-android-build] · [Android hook][fbp-hook]

### Verification order

Start Step 3 with **bluetooth_low_energy 6.2.1**, with Darwin and interface
6.2.1. Its explicit per-type write maximum, focused central APIs and MIT
terms are a good fit for an isolated macOS probe. The largest uncertainties
are complete bidirectional GATT values at the target's effective lengths
and whether canceled connects, subscription closure, service changes and
late native callbacks can be isolated and settled under existing deadlines.

**flutter_blue_plus 2.3.15** (Darwin 9.0.5, interface 9.0.4) is a conditional
fallback if a controlled Step 3 or 4 run attributes a blocker to the primary
plugin and the fallback has a relevant mechanism, such as service-reset
reporting, without-response backpressure where the target supports that
write type, or a disconnect path that can bypass the operation queue. Shared
CoreBluetooth, firmware, permission, or ATT limits do not provide that
attribution. Before any fallback build, test or evaluation, the maintainer
must establish which License 1.6 terms apply and any required commercial grant,
and assess redistribution/GPL coexistence and build telemetry for the proposed
scope.
No legal status or use permission was assumed here. If the condition is
unresolved or the blocker is shared, stop and record the gap.

If the fallback is exercised, record the queue mode and apply the probe's
end-to-end deadline across queue acquisition, platform invocation, and the
event wait. If that deadline expires with plugin work pending, observe its
settlement and retain the device lease until release is confirmed.
[Queue configuration][fbp-dart] · [Dart characteristic][fbp-characteristic]

[ble-build]: https://github.com/yanshouwang/bluetooth_low_energy/tree/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/darwin
[ble-dart]: https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/lib/src/central_manager_impl.dart
[ble-dart-dir]: https://github.com/yanshouwang/bluetooth_low_energy/tree/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/lib/src
[ble-swift]: https://github.com/yanshouwang/bluetooth_low_energy/tree/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/darwin/bluetooth_low_energy_darwin/Sources/bluetooth_low_energy_darwin
[ble-native]: https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/darwin/bluetooth_low_energy_darwin/Sources/bluetooth_low_energy_darwin/CentralManagerImpl.swift
[ble-delegate]: https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/darwin/bluetooth_low_energy_darwin/Sources/bluetooth_low_energy_darwin/CBPeripheralDelegateImpl.swift
[ble-license]: https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/LICENSE
[fbp-build]: https://github.com/chipweinberger/flutter_blue_plus/tree/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus_darwin/darwin
[fbp-dart]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus/lib/src/flutter_blue_plus.dart
[fbp-device]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus/lib/src/bluetooth_device.dart
[fbp-characteristic]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus/lib/src/bluetooth_characteristic.dart
[fbp-darwin-dart]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus_darwin/lib/flutter_blue_plus_darwin.dart
[fbp-native]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus_darwin/darwin/flutter_blue_plus_darwin/Sources/flutter_blue_plus_darwin/FlutterBluePlusPlugin.m
[fbp-license]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/LICENSE.md
[fbp-notice]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus/NOTICE.md
[fbp-android-build]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus_android/android/build.gradle
[fbp-hook]: https://github.com/chipweinberger/flutter_blue_plus/blob/23261064bb2e4c75072e6346ce36b28010ea4e39/packages/flutter_blue_plus_android/android/license_ping.gradle
[apple-peer]: https://developer.apple.com/documentation/corebluetooth/cbpeer/identifier
[apple-value]: https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didupdatevaluefor:error:)-1xyna
[apple-size]: https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)
[apple-write]: https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue(_:for:type:)
[apple-connect]: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/connect(_:options:)
[apple-cancel]: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:)
[apple-info]: https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription
[apple-entitlement]: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth
[apple-auth]: https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property

## Plugin execution and the Dart worker

The existing [controller](../../apps/meshchan_app/lib/runtime/controller.dart)
spawns one worker with typed request generation and request IDs. The
[protocol](../../apps/meshchan_app/lib/runtime/protocol.dart) carries snapshots
and outcome facts. The [worker](../../apps/meshchan_app/lib/runtime/worker.dart)
owns the device gate and storage, and [finite Check](../../apps/meshchan_app/lib/runtime/device_check.dart)
creates, observes and closes its session there. Normal Quit needs affirmative
resource release and worker exit after the release acknowledgment. A timed-out
request or worker exit alone leaves release unknown.

Flutter's [isolate guide](https://docs.flutter.dev/perf/isolates#limited-plugin-messages-from-host-platform-to-flutter)
documents request/reply support and the restriction on unsolicited messages to
background isolates. `BackgroundIsolateBinaryMessenger.ensureInitialized`
enables background calls and replies. Both reviewed BLE backends deliver scan
results, notifications and connection changes as native-initiated channel
messages. Their received event streams therefore need a root-isolate consumer
under this mechanism. The current worker bootstrap has no plugin messenger
handoff. The guide is rolling documentation and identified Flutter 3.50 when
reviewed on November 24, 2026.

The working hypothesis is that the Flutter host owns the plugin, native event
subscriptions and local BLE connection lifecycle. A sendable boundary would
carry owned complete frames, state changes and operation results to the
existing worker. The worker would continue to own `MeshCoreSession`, its sole
inbox lease, the device gate, storage and recording. Steps 3 and 4 must show
that this layout preserves the following contracts before choosing an execution
location.

- Preserve frame boundaries and delivery order within a connection, including
  when a response notification arrives before a GATT write result. Correlate
  write results, disconnects and errors to the originating operation and device
  lease. Reject late events from a prior connection or task generation.
- Preserve one dispatch, current request, initialization and task deadlines,
  and prompt logical cancellation with separately observed release. Keep
  optional-duration CLI watch behavior. Investigate a late native connect,
  stale notification, pending write and worker exit while the host still has
  state. Require an authoritative disconnect and subscription cleanup or keep
  the gate isolated. Apply the same rule at normal Quit.
- Keep platform objects in their owning isolate. Keep `meshcore_link` and
  `meshchan_core` pure Dart, USB behavior intact, and storage ownership in its
  existing worker. Keep BLE names, platform IDs, addresses, PINs, route bytes
  and raw frames out of History, safe logs and exports. The current
  `ConnectionProfile` remains an operation preset with an optional `portHint`.
  [Persistence and privacy contract](companion-connections.md#behavior-to-preserve)

## Step 3 macOS BLE host

**Planned / Not executed in Step 2.** Use an isolated minimal macOS Flutter
host and an explicitly authorized, identified target. Record exact macOS and
toolchain versions, pinned plugin/Darwin/interface set, target model/chip and
firmware build mode, expected GATT profile, and the local-adhoc bundle path,
ID, signature identity, effective Info.plist/entitlements and initial TCC
state. Have a documented, controlled means to drop the peer link. Use owned
fixtures, handle pairing through normal system UI, and record only the pairing
outcome. Ensure the probe is the only command sender on the target across all
enabled interfaces. Use a BLE-only configuration or isolate other active
transports from command-capable clients. Confirm that the target starts the
attempt without pending replies from earlier clients. If a prerequisite is
missing, record it and stop the affected scenario.

The pinned firmware includes the configured BLE PIN in `DEVICE_INFO`. The
priority plugin logs complete notification values and peripheral identities
at INFO. Its example forwards all log levels. Before the first probe launch,
suppress these plugin records or sanitize them before any console, file, or
evidence sink. Check the effective logging path without hardware using
synthetic records with frame bytes and records with peripheral UUIDs and
advertisement metadata but no frame bytes. Retain only structural evidence
such as opcodes, lengths, states, and timing.
[Firmware response](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L980-L998) ·
[Plugin discovery, connection and notification logs](https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/lib/src/central_manager_impl.dart#L230-L276) ·
[Example logging](https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy/example/lib/main.dart#L12-L26)

Confirm successful TX notification delivery independently of the plugin's Dart
stream. The pinned Darwin callback forwards values unclaimed by a read without
checking `error` or `isNotifying`. Keep active reads off TX. Use a sanitized,
test-only native observation of the selected TX update with `error == nil` and
`isNotifying` true, or equivalent evidence of successful central receipt.
Correlate it to the Dart event using the attempt, sequence and value length.
Retain only structural fields. If the evidence is unavailable, record notification
provenance as unconfirmed.
[Darwin value-update callback](https://github.com/yanshouwang/bluetooth_low_energy/blob/b97633b24405ace7dea0f0b30a08c0599aece19e/bluetooth_low_energy_darwin/darwin/bluetooth_low_energy_darwin/Sources/bluetooth_low_energy_darwin/CentralManagerImpl.swift#L443-L455)

Establish the expected complete response lengths independently of the BLE
notifications, using the identified firmware layout and known target fixture.
For the pinned v1.18.0 layout, expect 82 bytes for `DEVICE_INFO` and 58 bytes
plus the known on-wire node-name byte count for `SELF_INFO`. Obtain that count
from fixture data before connecting. The Meshchan decoder accepts the 58-byte
prefix and uses the remaining bytes as the name, so typed parsing can succeed
on a truncated name. Retain expected and observed lengths without the name or
raw payload.
[Firmware layout](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L979-L1036) ·
[Meshchan response decoder](../../packages/meshcore_link/lib/src/protocol/companion_messages.dart)

The following budgets are adjustable planning values. Use at most one explicit
attempt per scenario, plus the separately planned reconnect after verified
cleanup. Plan discovery for 10 seconds, connect/GATT/notify/initialization for
one 15-second total window with 5 seconds per Companion request, and observe
cleanup for up to 10 seconds. Expiring the observation window marks release
unconfirmed while ownership remains isolated. Record any revised budgets
before execution.

| Scenario and allowed actions | Observe and pass criteria | Stop conditions |
| --- | --- | --- |
| Select, connect and query. Scan with the verified service filter, select one identified result, stop scan, connect, discover GATT and enable TX notification. Send existing no-RF DEVICE_QUERY then APP_START through the known RX write type. | Confirm scan stop, exact selection and characteristic properties. Notify readiness precedes the first write. Correlate each independently verified TX update to one owned inner frame. Both response lengths match the independent expectations and the typed responses associate with the correct writes. Record structural lengths, write completion, safe error categories and ordering. | Missing/ambiguous target, unexpected service or security flow, unconfirmed notification provenance, missing or mismatched length evidence, deadline, unsupported properties, first protocol/transport failure, or cancellation. Close ownership without automatic retry. |
| Inspect directional size. Query native maximum for each relevant type and record characteristic properties and complete notification sizes during the supported no-RF exchange. | Establish observed sizes and write semantics for the authorized operations. Record the remaining largest-write and largest-notification risks explicitly. A boundary pass requires a safe documented stimulus and evidence of the complete value in that direction. | Without a valid no-RF boundary stimulus, leave that boundary for a separately scoped later test. Avoid unknown opcodes, fabricated commands, ordinary-write splitting, inbox reads and RF. |
| Permission denied, Bluetooth off, target absent, and controlled connection failure or deadline. Use isolated, known authorization states and one permitted negative action per case. | Record actual system prompts or their absence, adapter state, native/plugin error or timeout, logical outcome and release evidence. No wrong-device selection and no Companion dispatch before readiness. | First unexpected prompt, unavailable safe control, failed release or deadline. A deadline offers no proof that a late connection cannot arrive. |
| Cancel during pending connect or setup, then verify explicit local disconnect and controlled peer disconnect as separate cases. After confirmed release, perform one separately initiated connection to the same identified device. | Observe cancel intent, scan stop, notify disable where the link allows it, local disconnect state/callback, subscription settlement and handling of late connects or callbacks. A fresh explicit attempt uses fresh subscriptions and receives only its own frames. | Unknown release, stale value accepted, unexplained state change, or missed observation deadline. Keep the target unavailable for a new attempt while release is unknown. |

## Step 4 worker cooperation

**Planned / Not executed in Step 2.** Proceed after Step 3 completes the
no-RF query/start exchange with the selected backend and target, confirms
notification provenance and the expected response lengths, records the observed
write and notification lengths, and confirms resource release. These
observations are sufficient for Step 4's query/start scenarios. Record any
unresolved maximum lengths for separately scoped boundary tests.

Use the same version set, target identity, exclusive command ownership and
logging controls. Use an owned storage fixture and a test-only boundary around
the existing runtime. Use no-RF query/start for real events. Keep deterministic
mock timing, synthetic faults and local storage observations labeled separately
from the real-host evidence. Use one attempt per case, the existing command and
runtime deadlines, and a 10-second diagnostic observation window for cleanup
beyond the logical outcome. Keep one follow-on attempt only after proven release.
These are adjustable planning values.

| Scenario and allowed actions | Observe and pass criteria | Stop conditions |
| --- | --- | --- |
| Deliver real notifications from query/start and observe a controlled disconnect/error. | The worker sees actual frames and errors in attributable order. Apply Step 3's notification evidence check and record host callback, worker delivery, request association and write result with structural sequence/timing and generation evidence. The existing session owns readiness and response parsing. Reception lease ownership remains single. | Stop on loss, duplication, misassociation, unexpected inbox activity or unconfirmed notification provenance. |
| Exercise one occupied gate, cancel or deadline, then delayed write/notification/disconnect. Use synthetic control for timing that is unsafe or unreliable to force on hardware. | Check single admission, one logical settlement, no stale effects on the first outcome or next task, and no implicit retry or reconnect. | Stop if stale state reaches a new operation, a duplicate command is dispatched, or a missed callback leaves ownership unclear. |
| Correlate task outcome, native disconnect, observer/notification disposal, actual transport close, storage release, worker release/ack and observed exit. Inject withheld release or worker loss in a fixture. | Separate every fact. The gate and normal Quit remain held when release is unknown. After confirmed release, an explicit new attempt is admissible. | Stop with isolated ownership if any required proof is missing. Do not report normal success from a canceled Future or from worker exit alone. |

Choose an execution location only when the real and synthetic evidence together
shows ordered event delivery, generation isolation, compatible admission and
deadline semantics, and release proof. Record failure attribution before
considering the [conditional fallback](#verification-order). This feasibility
work leaves the full channel RF, production TCP/BLE, saved targets, recovery
and combined real-device matrix to their respective phases.
