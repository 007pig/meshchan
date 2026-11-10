# Channel datagrams: Phase 1B contract

## Status and scope

Phase 1 / 1B / Step 1 (1B.1) fixed the protocol, ownership, and acceptance
contract only. Review date: November 9, 2026. The reviewed Meshchan checkout was
clean on `master` at `98a50a3d5e9c8a1c843f3552ca0263a2c73a4369`, the same
commit as the task's historical reference. No hardware was accessed for this
review. The intended later 1B candidate is `0.1.0-dev.2`; the current application
remains `0.1.0-dev.1`.

| Status | Evidence and boundary |
| --- | --- |
| Implementation at the 1B.1 review | USB transport, serial framing, initialization codecs, a single-use session, and `ports`, `port-check`, `info`, and `watch`. No datagram codec, ready-state command executor, queue reader, or PING/PONG operation exists at the reviewed commit. |
| Planned 1B behavior | Binary datagram send/receive, bounded device-command execution, explicitly enabled queue consumption, one application PING/PONG exchange, and finite CLI diagnostic tasks. The contracts below do not expose those features today. |
| Pending device validation | Datagram support on the selected firmware, actual channel/radio compatibility, forward/return routes, timing budgets, and two-Companion LoRa acceptance. Protocol source inspection is not device evidence. |

The current [session contract](companion-session.md) remains authoritative for
1A. Its [implementation](../../packages/meshcore_link/lib/src/session/meshcore_session.dart)
allows `_send()` only while initializing, matches DEVICE_INFO and SELF_INFO,
and otherwise emits structural summaries. The
[codec](../../packages/meshcore_link/lib/src/protocol/companion_messages.dart)
recognized those two responses and device errors at the 1B.1 review; OK and
`0x83` were unhandled summaries. The
[CLI session runner](../../apps/meshctl/lib/src/session_command.dart) owns a fresh
session per invocation and awaits cleanup. Preserve those behaviors for existing
commands; readiness alone proves no LoRa exchange.

1B keeps the existing USB transport, framing, single-connection semantics, and
session ownership. It excludes long-content chunking/retransmission, persistence
or databases, Flutter UI, BLE/TCP, new author identities, automatic discovery,
complete route learning, infinite reconnection, and a long-running message service.

### 1B.2 implementation and validation

On November 10, 2026, 1B.2 extends the existing synchronous codec from `master`
at `abbab6803faecee119f8ec3057c8b7315aadd722`, which includes PR #9's contract
commit `5e1b9153e02da34edf31f3eb6832e41cda2228bf`. The historical 1B.1 review
and upstream evidence below remain separate from this implementation.

The public `package:meshcore_link/meshcore_link.dart` entry exports:

- `encodeSendChannelData`, requiring `channelIndex`, `dataType`,
  `routeDescriptor`, `path`, and `payload`. It validates numeric ranges, the
  exact Direct path length or empty Flood path, and both capacity limits before
  allocating a complete inner command. It does not check configured channels.
- `encodeSyncNextMessage`, returning a fresh one-byte command without a read.
- The existing `decodeCompanionResponse`, now also returning `OkResponse`,
  `MessageWaitingResponse`, `NoMoreMessagesResponse`, `ChannelDataResponse`, and
  `QueuedMessageResponse` / `QueuedMessageKind`. Datagram fields include
  `snrQuarterDb` / `snrDb`, `channelIndex`, receive-only `routeMetadata` /
  `isDirect`, raw `dataType`, and explicitly accessible `payload`.

Encoded commands copy the supplied path and payload. Received datagrams copy
only their payload into independent read-only storage; offset views are accepted.
Ordinary messages retain only kind, opcode, and content length. Default summaries
and exceptions omit body/path bytes. Malformed recognized responses use
`CompanionProtocolException`; unknown opcodes and device error tails keep their
existing compatibility policies. No session or CLI scheduling behavior changes.

Implementation is complete for the in-memory codec scope. Focused tests are
`packages/meshcore_link/test/channel_datagrams_test.dart` and the existing
`companion_messages_test.dart`; session and CLI regressions use their existing
fake transports. Run the focused files with core `dart test`, followed by the
complete core and CLI suites, using the installed SDK and locked dependencies
from the [testing guide](../testing.md).

Actual local software validation used the existing Flutter SDK's bundled Dart
3.13.7 on macOS arm64, with Apple tools preferred through the process PATH.
Installed SDK metadata reports Flutter 3.47.9 stable; the Flutter wrapper was
not run. Checks completed on November 10, 2026:

| Check | Result |
| --- | --- |
| `dart pub get --enforce-lockfile` | Passed; root lockfile unchanged, no dependencies added. |
| Format and format check of the six changed Dart files | Passed; final check made zero changes. |
| `dart analyze --fatal-infos` | Passed; no issues. |
| Focused datagram and initialization codec tests | Passed; 21 tests. |
| Complete core suite, then complete CLI suite | Passed sequentially; 77 and 27 tests, respectively. |
| Existing CLI and observation native bundle builds, then `tool/smoke_cli.py` | Passed once sequentially in fresh temporary output; all 46 macOS process checks and both native asset checks passed. Linux-only enumeration refusal was not applicable. |
| Patch and new-file hygiene | Passed whitespace checks, UTF-8 without BOM, LF, and final newline checks. |

The original notification-interleaving and privacy tests remain: legal `83`
uses one byte, private unknown tails use `FE`, and newly recognized responses
cannot complete initialization, renew deadlines, or cause extra sends. Malformed
controls/datagrams exercise existing protocol failure and awaited cleanup.
No remote CI, real port enumeration/access, device commands, or LoRa tests ran.

Ready-state command execution, queue consumption, application PING/PONG, and
device/LoRa validation remain pending later steps. Encoding `0x0A` performs no
queue operation; parsing OK proves neither command association nor delivery.
The application version remains `0.1.0-dev.1`.

## Fixed upstream evidence

The sources below were retrieved and inspected at MeshCore commit
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`. This review does not change the
repository's protocol baseline or upgrade firmware. Function names identify the
checked branches; prose and source disagreements are resolved explicitly below.

| Fixed source | Checked evidence |
| --- | --- |
| [Companion protocol](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/docs/companion_protocol.md) | Send/receive field descriptions and message names; compare its limits and delivery wording with implementation. |
| [MyMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp) | `handleCmdFrame()` branches for `CMD_SEND_CHANNEL_DATA` and `CMD_SYNC_NEXT_MESSAGE`; `onChannelDataRecv()`, `queueMessage()`, `onChannelMessageRecv()`, `Frame::isChannelMsg()`, and offline queue operations. |
| [MyMesh.h](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.h) | Default `OFFLINE_QUEUE_SIZE` and fixed-size queue entries. |
| [BaseChatMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseChatMesh.cpp) | `sendGroupData()` radio envelope, length check, packet allocation, and route selection; `onGroupDataRecv()` declared-length check. |
| [BaseSerialInterface.h](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h) | `MAX_FRAME_SIZE = 176`, excluding serial header. |
| [MeshCore.h](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/MeshCore.h) | `MAX_PACKET_PAYLOAD = 184`, `CIPHER_BLOCK_SIZE = 16`, `MAX_GROUP_DATA_LENGTH = 165`, and `MAX_PATH_SIZE = 64`. |
| [Packet.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/Packet.cpp) / [Packet.h](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/Packet.h) | `isValidPathLen()`, `writePath()`, path hash/count helpers, and route metadata. |
| [Number allocations](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/docs/number_allocations.md) | `0xFF00..0xFFFF` development range; the Companion document names `0xFFFF` as `DATA_TYPE_DEV`. |

These establish wire facts for this baseline. Meshchan rejection, scheduling,
and diagnostic policies below are project choices. Hardware claims require the
separate acceptance checklist.

## Layers, commands, and fields

Keep three layers separate:

1. The existing [serial frame](serial-framing.md) wraps complete Companion
   content with a direction marker and uint16 little-endian content length.
   The transport adds/removes that three-byte header exactly once.
2. Companion commands carry radio datagrams. `BaseChatMesh::sendGroupData()`
   puts uint16 little-endian `data_type`, uint8 payload length, and payload
   inside the group radio envelope. There is no built-in sender identity or
   timestamp in this application datagram.
3. The Meshchan test protocol is inside that payload. Its later header consumes
   part of the radio budget; it is not part of serial framing.

All offsets and lengths below refer to inner Companion content, including opcode
at offset 0 and excluding the serial header. Directions disambiguate reused codes.

| Direction | Opcode / firmware name | Purpose and result |
| --- | --- | --- |
| Host → device | `0x3E` / `CMD_SEND_CHANNEL_DATA` | Send a channel datagram; local `0x00` or `0x01`, with no remote delivery acknowledgment. |
| Host → device | `0x0A` / `CMD_SYNC_NEXT_MESSAGE` | Consume one entry from the shared queue, or receive empty-queue result. Command content is one byte. |
| Device → host | `0x00` / `RESP_CODE_OK` | Generic local success; one byte in the fixed implementation. |
| Device → host | `0x01` / `RESP_CODE_ERR` | Error code at offset 1, at least two bytes; retain unknown codes numerically. |
| Device → host | `0x83` / `PUSH_CODE_MSG_WAITING` | One-byte queue notification; never success for a particular send. |
| Device → host | `0x1B` / `RESP_CODE_CHANNEL_DATA_RECV` | One queued channel datagram, with the layout below. |
| Device → host | `0x0A` / `RESP_CODE_NO_MORE_MESSAGES` | One-byte empty-queue result, distinct from the host command with the same value. |
| Device → host | `0x07` / `0x10` contact message; `0x08` / `0x11` channel text | Another possible result of one queue read. Target 3 selects the V3 forms `0x10` / `0x11`; legacy forms remain identifiable as non-test queue entries. |

For the fixed one-byte device responses `0x00`, `0x83`, and `0x0A`, Meshchan
requires exactly one content byte. Any tail is a protocol error; it is not
treated as an unknown extension. This does not tighten the error response's
existing at-least-two-byte policy.

For sending, let `P` be the actual encoded path byte count:

| Offset | `0x3E` field |
| --- | --- |
| 0 | Opcode `0x3E`. |
| 1 | uint8 local channel index. It must refer to the explicitly selected configured channel. |
| 2 | Route descriptor: `0xFF` selects Flood; otherwise Direct. |
| 3 through `2 + P` | Direct path bytes only; absent for Flood or a zero-byte Direct path. |
| `3 + P`, `4 + P` | uint16 little-endian `data_type`; `0x0000` is invalid. |
| `5 + P` onward | Binary payload; length is the remaining content, with no separate host-command length byte or text terminator. |

For a Direct descriptor `d`, `hashCount = d & 0x3F`,
`hashSize = (d >> 6) + 1`, and `P = hashCount * hashSize`.
Reject reserved hash size 4 and products above 64. Validate the descriptor,
the exact supplied path byte count, and space for both type bytes before access.
Descriptor `0x00` is a zero-hop Direct route. Flood has `P = 0` and no path bytes;
never multiply the `0xFF` sentinel as a Direct descriptor. There is no silent
path truncation, inference, or fallback to Flood.

| Offset | `0x1B` field |
| --- | --- |
| 0 | Opcode `0x1B`. |
| 1 | Signed int8 SNR in quarter-dB units; divide by 4.0 for dB. |
| 2..3 | Reserved; ignore values. |
| 4 | Receiver's local uint8 channel index. |
| 5 | Receive route metadata: `0xFF` means Direct arrival; otherwise the observed Flood path descriptor. No path bytes follow. |
| 6..7 | uint16 little-endian `data_type`. |
| 8 | uint8 declared payload length `N`. |
| 9 onward | `N` binary payload bytes. |

Meshchan requires at least nine bytes before reading fields, `N <= 165`,
and exactly `9 + N` content bytes for this fixed layout. A short body or an
unexpected tail is a protocol error, not a truncated successful datagram. This
exact-length policy is stricter than the upstream prose's sample parser, which
only checks that the declared body fits. Validate a non-`0xFF` receive descriptor
as encoded metadata; do not skip bytes or construct a return route from it.

Ordinary chat classification needs no chat client or body display. The fixed
writer prefixes are 13 bytes for contact `0x07`, 16 for contact V3 `0x10`,
8 for channel `0x08`, and 11 for channel V3 `0x11`. Check the appropriate prefix
before classifying; remaining bytes are opaque non-test content, including any
contact extras. A valid non-test entry completes that queue read. A malformed
Companion prefix fails the session; a structurally valid datagram with an
unknown test identifier/version or invalid test body is classified and ignored
by the test matcher without failing the connection.

## Capacity and implementation discrepancies

For this fixed baseline:

```text
radio datagram payload limit = 184 - 16 - 3 = 165 bytes
send content length          = 5 + pathBytes + payloadBytes
maxPayload                   = min(165, 176 - 5 - pathBytes)
receive content length       = 9 + payloadBytes
test content budget          = maxPayload - testHeaderBytes
```

`pathBytes` is `P` above, not the descriptor's integer value. For example, Direct
`0x42` represents two two-byte hashes: four path bytes. Flood allows 165 payload
bytes in 170 content bytes; a valid 64-byte path allows only 107 payload bytes in
176 content bytes. A 165-byte receive payload occupies 174 content bytes.
These constants are not a promise about all future firmware. All counts are
bytes, never characters; payloads can contain NUL, arbitrary binary, or invalid
UTF-8. Zero-length datagrams fit the wire layout, but cannot contain a test PING.

The sender first validates the complete content capacity and radio limit and
rejects oversize input locally, before I/O. The receiver checks fields and declared
length before slicing/copying payload. There is no fragmentation or truncation.
Encoded output and received payloads must own their bytes rather than alias
caller buffers or reusable decoder storage.
165 is an application datagram limit, not an article limit or an unconditional
PING/PONG test-content budget. The exact test header size is deferred to 1B.5;
both outbound and return-route capacities must accommodate the chosen content.

Source/prose differences to retain in later implementation reviews:

- The Companion document says a 167-byte host bound lets 166/167-byte payloads
  reach the radio layer and return error 3. The actual `CMD_SEND_CHANNEL_DATA`
  branch checks `MAX_GROUP_DATA_LENGTH` (165) directly and returns
  `ERR_CODE_ILLEGAL_ARG` (6) above it, assuming a valid channel and route. Unknown
  channels return `ERR_CODE_NOT_FOUND` (2) first. `MAX_CHANNEL_DATA_LENGTH = 167`
  is used by the receive-frame callback; it is not the send-branch payload limit.
  Error 3 (`TABLE_FULL`) is the send helper's failure result, including packet
  allocation failure; it does not prove a particular queue condition or invite
  automatic retry.
- The send branch's initial `len < 4` guard does not fully validate the path and
  both type bytes before reading them. Meshchan must enforce the complete
  `5 + P` minimum itself and never depend on malformed-input firmware behavior.
- The receive prose calls `0x1B` a notification. In `onChannelDataRecv()` it is
  enqueued, while connected hosts receive a separate `0x83` tickle. Only
  `CMD_SYNC_NEXT_MESSAGE` removes and writes the queued entry. No unsolicited
  serial `0x1B` push capability has been established for this firmware.

## Planned session ownership and response dispatch

The session remains the sole owner of
[`CompanionTransport`](../../packages/meshcore_link/lib/src/transport/companion_transport.dart):
one receive subscription, `open()`, `sendFrame()`, and `close()`. Subscribe before
open and keep reception unpaused through transport cleanup. CLI and diagnostics
consume typed results/events; they never also read `transport.frames`. Use a
fresh transport/session for each connection attempt; no automatic reconnect.

At most one device command may be in flight, with a finite pending queue and
explicit rejection when full. All sends and queue reads use that one scheduler.
Queue wait is covered by the task deadline; command timeout starts only at
dispatch. This fixes semantics, not Dart class names, method signatures, or a
general scheduling framework. Existing `info/watch` continue sending only their
two initialization commands; observing `0x83` never enables reception for them.

The following table applies after successful initialization, for planned 1B
operations. A command result is retained on arrival but completes successfully
only after its local send also succeeds. Initialization keeps its existing
type-specific matching policy; OK cannot replace DEVICE_INFO or SELF_INFO.

| Received message | Waiting for send `0x3E` | Waiting for queue read `0x0A` | No pending command |
| --- | --- | --- | --- |
| First valid OK `0x00` | Retain local acceptance; complete when write also succeeds. | Unassociated summary; keep waiting for a queue result. | Unassociated summary. |
| Error `0x01` | Fail with raw code and stage; stop dispatch and clean up. | Fail with raw code and stage; stop dispatch and clean up. | Unassociated structural error; never cache for a later command. |
| Waiting notice `0x83` | Set one receive-pending flag only if receive is enabled; never acknowledge send. | Coalesce flag; never complete this read. | Set flag only for explicitly enabled reception. |
| Valid datagram `0x1B` | Do not acknowledge send; classify as unassociated and deliver to enabled typed reception/matcher if applicable. | Complete one read and classify/deliver the datagram. | Unassociated typed reception only if enabled; no implied push-support claim. |
| Valid chat `0x07/0x08/0x10/0x11` | Unassociated non-test summary; do not acknowledge send. | Complete one read as non-test data; never wait for a PONG within this command. | Unassociated non-test summary. |
| Empty queue `0x0A` | Unassociated; cannot acknowledge send. | Complete this read as empty and stop the drain. | Unassociated summary. |
| Other valid opcode or wrong response type | Structural summary; no completion or timer extension. | Structural summary; no completion or timer extension. | Structural summary; no response pool. |
| Malformed Companion content | Protocol failure; stop dispatch and clean up. | Protocol failure; stop dispatch and clean up. | Protocol failure while active. |

Keep the first matching command result; recognized duplicates cannot replace it
or be saved for a future command. Already consumed input is never replayed.
Responses after terminal timeout/cancellation/disconnect are discarded without
advancement. Generic OK/ERROR has no reliable end-to-end request ID: local tokens
only invalidate local callbacks. A same-type duplicate arriving after a new
command starts cannot always be distinguished on wire. Exclusive control and
serialization reduce ambiguity, but do not prove perfect association. In
particular, **a device-command timeout terminates the session**: stop dispatch,
reject queued work, and clean up so a late OK cannot satisfy the next command.

## Explicit, bounded shared-queue reception

`0x0A` consumes the device's shared queue, including ordinary chat and other
applications' datagrams. It is not a read-only peek or a test-specific inbox.
The fixed header defaults to 16 entries unless overridden at firmware build
time. On overflow, the implementation removes the oldest channel entry
(including `0x1B`) and appends the new entry; if no channel entry can be removed,
the new entry is dropped. Notifications therefore guarantee neither persistence
nor a particular number of retrievable messages.

Planned policy for a new diagnostic operation that explicitly enables receive:

1. Permit one bounded initial queue check after ready, even without `0x83`, to
   find data queued before subscription. Register test matching before any send.
2. Merge repeated `0x83` into one pending flag, not parallel tasks or one job per
   notice. Drain through the unique command scheduler, one entry per command.
3. Limit each batch by message count or elapsed time; choose concrete finite
   limits in the receive implementation. Yield between batches to user sends
   and cancellation. If the batch limit is reached, retain one continuation
   flag rather than requiring a new notification for existing queued data.
4. An empty result stops the current drain and clears its pending work; a newly
   observed notice can schedule another bounded batch. No default busy polling.
   All batches remain bounded by the operation's duration/count and task deadline.
5. Classify each consumed result promptly. Non-test data is never a PONG and
   does not keep a queue-read command pending. The 1B diagnostic does not persist
   ordinary chat history: consumed non-test bodies may be discarded after
   classification. Document that loss before enabling a future `listen` task;
   never describe it as harmless passive listening.

Use dedicated test Companions and exclusive sessions for initial acceptance.
Future firmware may offer other delivery modes; adopting them requires separate
evidence and a contract update.

## Results, deadlines, cancellation, and cleanup

Report these independent facts rather than one ambiguous “sent” state:

| Fact | Evidence / limit |
| --- | --- |
| Local write completed | Transport accepted the framed bytes through its local API; no physical TX or remote receipt guarantee. |
| Device accepted | Matching local OK for `0x3E`, with successful local write. ERROR, timeout, or an unrelated notice does not establish acceptance. |
| Matching response observed | A valid PONG for this run/request/peer/content was observed, even if local send processing has not finished. |
| Round trip succeeded | Local write and device acceptance succeeded, matching PONG and content verification succeeded, and no primary failure/cancellation/disconnect intervened. Cleanup is reported separately; final CLI success also requires successful cleanup and output. |

Install the application matcher and record the local monotonic start immediately
before initiating the PING send. Retain an early matching PONG, including one
observed before the send Future or local OK; it must not disappear while waiting
for local completion. This is a race-handling requirement, not evidence that this
firmware pushes queued datagrams. If the command later fails, preserve both
`matching response observed` and the local failure; do not claim normal success.
RTT runs from that monotonic start to the first fully validated matching PONG.
Label it **application round-trip time**: it includes host scheduling, device
processing, queue reads, and radio work, not just airtime. Wall-clock changes
must not affect it.

| Deadline | Starts | Ends / failure |
| --- | --- | --- |
| Initialization (existing default 15 s) | `connect()`, after receive subscription and before `open()`. | Both ordered initialization sends/responses succeed and ready is published; otherwise initialization failure. Includes open and startup delay (existing default 0). |
| Device command (existing initialization default 5 s; retain it) | Pending slot/timer registration immediately before `sendFrame()`. | Both local write and first permitted response succeed; error or expiration ends it. Applies separately to each later send/read. |
| Entire round-trip task (new finite parameter) | Diagnostic operation invocation, before connection starts. | Terminal exchange result or task failure/cancellation; includes initialization, queue waiting, local sends, and remote waiting, but not awaited resource cleanup. |
| Remote response (new finite parameter) | The monotonic PING-send start defined above, after matching is installed. | First fully valid PONG, or remote-response timeout on expiration; retain whether the local command was still pending. Also bounded by the task deadline. |

The earliest applicable deadline wins; record whether a command was still
pending when remote/task time expired. No unrelated notice, partial input,
duplicate, write completion, or non-test traffic restarts a budget. New wireless
and task budgets will be selected from measurements later; do not guess radio
constants or change initialization defaults here.

Distinguish failure stage and cause: connection initialization (open, protocol,
device rejection, request or total initialization timeout), local command
rejection/write failure, local device-command timeout, remote-response timeout,
overall task timeout, cancellation, active-stream disconnect, and cleanup failure.
On any terminal task outcome, stop new operations and close the diagnostic
session. A command timeout, unlike a missing remote PONG, leaves local response
association unsafe. Cancellation invalidates queued work, timers, and matchers;
it cannot retract a radio send already accepted by the device.

Preserve the first primary failure and its original cause/stack for explicit
inspection, with all cleanup failures separately available. Successful cleanup
cannot turn a failed operation into success; cleanup failure must not erase a
primary error or signal. Use the existing shared `close()` Future: keep reception
alive until transport close settles, then cancel the subscription and finish
events. Late open/send completions cannot revive work. Logical deadlines do not
preempt blocking native calls or prove resource release. Cleanup can remain
pending; do not invent a forced-free deadline or report pending cleanup as success.

## PING/PONG semantics; layout deferred to 1B.5

Use experimental `data_type = 0xFFFF` for 1B, with a Meshchan test-protocol
identifier inside the payload to distinguish other development traffic. This
does not allocate a production application number. Necessary application fields
are protocol identifier, version, message kind (PING/PONG), request ID,
sender test ID, target test ID, and test content. Run correlation must include
a fresh run nonce (or an equivalently unique request namespace), so a previous
run cannot supply the current response. Session-local request counters are not
application IDs and never substitute for this wire correlation.

Only the explicitly targeted responder may answer a matching supported PING.
Its PONG preserves the run/request correlation, names the responder as sender
and initiator as target, and echoes the test content byte for byte. The initiator
checks protocol/version/type, run/request, both test IDs, selected receive
channel, and exact expected content. A PONG never triggers another response.
Other IDs, stale runs, mismatched contents, and unknown application formats are
nonmatching data; they cannot extend the deadline.

Default to one PING without automatic resend. Responder/listen tasks need an
explicit finite response count or duration. Duplicate suppression uses a bounded,
expiring cache keyed by run/request and test peers: a duplicate PING cannot
cause repeated PONGs within that window, and duplicate PONGs cannot replace the
first observation or RTT. Test IDs and nonces provide correlation, not formal
identity authentication or replay-proof security.

**1B.5 owns** the exact protocol identifier value, field widths, application
endianness, nonce encoding, diagnostic header size, fixed test vectors, and
concrete duplicate-cache capacity/expiry. The Companion uint16 endianness above
is already fixed; it does not decide these application-layout choices.

## Device, channel, and route inputs

Later operators must provide both exact authorized ports, local channel slots,
send modes and encoded paths, test peer IDs, content, and finite task/wait limits.
No port, channel, route, or peer is selected or overwritten automatically. Both
devices need compatible radio parameters and the same actual channel
configuration/key; their local channel indexes may differ. Do not log keys to
demonstrate equality.

Configure and verify A's forward route and B's return route separately. Receive
`0x1B` carries no full path, and receive `0xFF` means Direct while send `0xFF`
means Flood. No automatic reverse-path construction or route learning is implied.
Both Companions may attach to one computer, but the test content and PONG must
cross LoRa; clients must not exchange them through local IPC, files, or networks.
Explicitly supplied test parameters do not authorize a local data-path shortcut.

Record the Meshchan revision/application version, client target version (still
3), each device's reported protocol code, firmware text/provenance, and actually
verified features separately. Reporting protocol 14 does not prove datagrams
work on that device. Keep DEVICE_QUERY then APP_START and the target unchanged;
do not guess a compatibility fix by changing handshake order or target.

## Diagnostics and privacy

Plan typed results with independent local-write/device-acceptance status,
matching-PONG observation, content validation, application RTT, failure stage,
raw device error code when present, and cleanup status (`pending`, `succeeded`,
or `failed`). An unattempted or unconfirmed stage must remain distinguishable
from success. Exact Dart API and new CLI field/command names remain later work.

Preserve the [CLI conventions](../cli.md): results on stdout, diagnostics on
stderr, one JSON object for finite result commands and NDJSON for event tasks,
versioned schemas, awaited cancellation/cleanup, and primary-failure precedence.
Retain exit meanings: 0 successful task/cleanup/output; 64 invalid input; 69
expected transport/session/task or cleanup failure; 74 output failure without an
earlier failure; 130/143 signals; 70 unexpected program error. A local OK alone
is never a successful round-trip exit. Existing command output schemas stay intact.

Default diagnostics omit channel keys, BLE PINs, coordinates, ordinary chat
bodies, and raw frames/payloads. Explicit callers may access owned datagram bytes
through typed results/events; default `toString()`, exceptions, verbose logs,
and structural debug output must not reveal them or recursively format causes.
No raw-message capture is needed for this step or for routine acceptance records.

## Acceptance to execute later

All boxes below were **planned / not run in 1B.1**. This retained full-1B
checklist is not a claim of passing software or device results; the scoped 1B.2
implementation and validation are recorded above. Follow the existing
[testing evidence boundaries](../testing.md#evidence-limits).

Software acceptance should use a few representative behavior groups:

- [ ] **Codec, length, and paths:** independent Companion vectors for both
  directions; little-endian type and signed SNR; arbitrary binary and zero payload; 165/166
  boundary; 176-byte complete-frame boundary; valid multi-byte-hash and zero-hop
  routes; reserved/oversize/truncated paths, type fields, declared receive
  lengths, and extra tails. Confirm local rejection before send and owned bytes.
- [ ] **Command/notice interleaving:** execute the dispatch table, OK before
  send completion, ERROR, repeated `0x83`, wrong types, duplicate results,
  unknown opcodes, and a command timeout followed by late OK; prove no next
  command is dispatched on that session and no response pool is reused.
- [ ] **Bounded reception/cancellation:** initial check without a notice,
  shared chat/other-application classification, empty queue, notice coalescing,
  batch continuation/fairness, finite queue rejection, and cancellation with
  queued reads. Non-test traffic must finish reads without becoming PONG.
- [ ] **Application correlation:** correct peer/run/request/content, wrong
  IDs/version/content, stale or expired entries, duplicate PING/PONG,
  unsolicited PONG, early PONG, and early PONG followed by local failure.
  Add fixed application vectors only after 1B.5 freezes the layout.
- [ ] **Timeout/disconnect/cleanup:** separate initialization, command,
  remote-response, and whole-task deadlines; unrelated traffic cannot renew
  them. Cover cancellation, stream error/done after ready, late callbacks,
  primary plus cleanup failure, and pending native cleanup without false success.
- [ ] **CLI results/privacy:** distinguish write, acceptance, observation,
  round trip, and cleanup; JSON/NDJSON parseability, stdout/stderr roles,
  signals/exit precedence, output failure, and absence of sensitive payloads
  from default diagnostics, exceptions, and `toString()`.

Hardware acceptance requires later explicit device/LoRa authorization and the
inputs above. Use dedicated Companions with exclusive sessions:

- [ ] Record both devices, host/client revisions, reported protocol/target/
  firmware separately, actual radio/channel configuration references (without
  secrets), A/B routes, payload byte count, and all chosen limits. Unknown model
  or firmware provenance stays unknown; configuration is an input, not invented.
- [ ] Establish ready on both devices, then test zero-hop Direct round trips
  A → B → A and B → A → B, one request each, over real LoRa.
- [ ] After the direct baseline, verify one explicitly supplied repeater path
  and separately configured return path, again in both directions. Record
  evidence for the named route rather than assuming Flood used a repeater.
- [ ] Run a no-responder timeout with successful initialization/local acceptance;
  distinguish it from USB or command timeout. Exercise a few binary boundaries
  (including NUL/non-UTF-8 and a route-budget edge), cancel an active task, and
  disconnect after ready with awaited cleanup. Record actual outcomes and stages.

For each trial retain local-write/acceptance facts, matching observation/content
result, monotonic application RTT if available, primary failure/stage/opcodes,
and actual cleanup outcome. Do not invent PASS, success rates, timing, ports,
channel values, routes, or hardware identity in advance.

The [1A delivery record](../releases/phase-1a-dev1.md) and
[hardware record](../hardware-validation.md) retain their dated evidence.
The basic 1A checks passed on their recorded setup; intermittent USB
initialization/delivery failures remain unresolved. H10 had three pre-ready
startup failures; ready-state unplug detection and a complete recovery cycle
remain untested. The separate post-replug R1 failure/R2 success is not an H10
pass. Initialization failures are not LoRa packet loss, and one successful run
does not prove waiting, retries, or replugging fixed the cause. This step reruns
no hardware, captures no raw messages, and repairs no USB issue.

## Handoff and document review

1B.2 implements the fixed Companion layouts, path/byte budgets, error-code caveat,
strict local validation policies, and binary ownership/privacy rules through
the public codec API above. 1B.3 can call those interfaces for later session
scheduling. Bounded reception then follows the contracts here; 1B.5 must freeze
application layout before PING/PONG vectors or
round-trip implementation depend on it. CLI syntax and concrete bounded runtime
parameters remain later implementation decisions, with radio waits selected
from measurements. The codec does not implement those subsequent steps.

1B.1 review is limited to current-code/source comparisons, table/formula
consistency, relative and fixed-commit links, UTF-8/LF/whitespace checks, and
scope/diff review. It does not establish unit-test, build, or hardware acceptance.
The listed upstream evidence was accessible; deployment-specific firmware
support, channel settings, routes, and radio behavior remain unverified.
