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
| Implementation after 1B.3 | The 1B.2 binary codecs plus ready-state send and single consuming queue-read APIs, sharing a bounded command FIFO. See the scoped records below. |
| Implementation after 1B.4 | Explicitly started finite reception, coalesced notices, bounded batches through the original FIFO, typed observations, and pause/stop settlement. |
| Implementation after 1B.5 | Frozen diagnostic v1 payload, pure Dart message codec/classification, targeted PONG construction, exact field matching, and shared send-route capacities. |
| Implementation after 1B.6 | Single-run PING and finite responder tasks, secure nonce lifecycle, runtime deduplication, monotonic deadlines/RTT, and independent actual cleanup. See [task API](diagnostic-tasks.md). |
| Implementation after 1B.7 | Nested `datagram send/listen/ping/respond`, pure CLI input/budget validation, safe JSON/NDJSON projections, signal/output cancellation, and awaited actual cleanup. See [CLI contract](../cli.md#finite-datagram-commands-1b7). |
| Implementation after 1B.8 | Shared finite serial-byte scenarios, ordinary Dart tests, source/AOT development probe, strict shared process smoke and third CI bundle. See [coverage mapping](#1b8-software-coverage-mapping). |
| Remaining planned 1B behavior | 1B.9 explicit device/LoRa acceptance, final candidate handling, signing and release. |
| Pending device validation | Datagram support on the selected firmware, actual channel/radio compatibility, forward/return routes, timing budgets, and two-Companion LoRa acceptance. Protocol source inspection is not device evidence. |

The [session contract](companion-session.md) remains authoritative for the
implemented API. At the 1B.1 review its
[implementation](../../packages/meshcore_link/lib/src/session/meshcore_session.dart)
allowed `_send()` only while initializing, matched DEVICE_INFO and SELF_INFO,
and otherwise emitted structural summaries. The
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

At completion of 1B.2, ready-state command execution, queue consumption,
application PING/PONG, and device/LoRa validation remained pending. Encoding
`0x0A` performs no queue operation; parsing OK proves neither command association
nor delivery.
The application version remains `0.1.0-dev.1`.

### 1B.3 implementation and validation

1B.3 starts from clean `master` at `2b9b8c2d8bba349453711f248ac65a0910ffdf05`,
PR #10's merge of codec head `35711a7b85ed2d1ee8f218ae29727510a842fc6a`.
It reuses those codecs and the existing session, transport subscription, pending
slot, request budget, and cleanup path. The public session now provides:

- `sendChannelData(...)`: explicitly supplied channel, type, route, path, and
  payload are validated/copied on admission. Success returns the first
  `OkResponse` only after local write success; this is device command acceptance,
  not wireless delivery or application acknowledgment.
- `readNextMessage()`: one `0x0A` returns one `ChannelDataResponse`, ordinary
  `QueuedMessageResponse`, or `NoMoreMessagesResponse`, also requiring local write
  success. It consumes the shared inbox, including ordinary chat whose body is
  discarded. It never automatically reads again.
- One strict FIFO for both operations, with `maxQueuedCommands` default 8,
  counting waiting commands only. Zero allows an idle active command. Admission
  errors do no I/O and leave accepted work intact. Accepted command failures
  expose frozen per-command dispatch/write/response facts and the shared session
  root failure; cancellation and cleanup remain separate results.

The [session API contract](companion-session.md) documents local error types,
capacity, dispatch timing, the current matching table, and close cancellation.
Command deadlines start at dispatch, cover write plus response, and terminate the
whole session on expiration. Committed success survives later close; reserved
and queued work remains cancelable before its dispatch microtask.

At the 1B.3 implementation, reception was deliberately narrower than the full
plan below:
`0x83` only emits a structural summary, with no receive-pending flag or drain.
Unassociated datagrams also remain structural summaries. Typed queue results
are delivered only by an explicit read's Future, without new event subclasses
or a raw response stream. That historical boundary is extended by 1B.4 below
without a second transport subscription or send path.

Implementation is complete for this command-execution scope. Software evidence
for this step is recorded separately in the
[session verification section](companion-session.md#software-verification-and-references).
Historical 1B.1/1B.2 and hardware evidence above and below retain their original
boundaries. No new release, version change, USB repair, application protocol,
real serial access, or LoRa acceptance is included.

### 1B.4 implementation and validation

1B.4 starts from clean `master` at
`4a8ae298a85deb5812492c4e2fd5ca3d751c4805`, which merges PR #11 and includes
its `db3bf29db2cfbeac3cbb43e6675b91666ecb082e` command implementation.
The fixed MeshCore upstream remains
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`.

`createReception(duration:, maxEntries: 128, maxReadsPerBatch: 8)` returns an
inert `MeshCoreReception`; callers listen before `start()` and observe its
independent `done` / idempotent `stop()` result. The scheduling, typed entry,
pause, quota, and settlement policies below are now implemented. Existing
session events and CLI schemas retain structural diagnostics without payload.
See the [API and parameterized example](companion-session.md#explicit-bounded-reception-1b4)
and [actual software checks](companion-session.md#1b4-software-verification-on-november-10-2026).
Application layout, PING/PONG matching, coordination, and new CLI tasks remain
pending at the end of 1B.4, as do all real datagram/LoRa acceptance trials. No
version, dependency, native serial, or CI change is included; historical evidence
is retained above.

### 1B.5 implementation and validation

1B.5 starts from clean `master` at
`4f6171962ced32f5fe1cc6a0ea38b64e49bea51c`, the actual PR #12 merge,
including reception head `f99278b86360c84b0e3c1ae92941834a0e25d489`.
The PR page was rechecked on November 10, 2026, and showed merged status.
The pinned MeshCore upstream remains unchanged. The new
[`diagnostics/ping_pong.dart`](../../packages/meshcore_link/lib/src/diagnostics/ping_pong.dart)
is independent of session state and does no I/O. Its explicit root exports and
the shared Companion route-budget helper are documented below.

The implementation freezes the v1 format and default runtime deduplication
policy. Only codec, classification, construction, and field equality are
implemented; allocation of runs/requests, actual sending/responding, deduplication
state, timeout, and RTT remain 1B.6. The application remains `0.1.0-dev.1`.

Actual software checks on November 10, 2026, used
`/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` 3.13.7 stable,
`macos_arm64`, with process PATH
`/opt/homebrew/share/flutter/bin:/usr/bin:$PATH` and Apple Clang 21.0.0.
`flutter --version` failed because the sandbox denied SDK cache engine-stamp
and `engine.realm` writes. Existing SDK metadata reports Flutter 3.47.9 stable,
revision `c197ca5199e9ee5661e865596c9c07294dfab51c`; that is not a successful
fresh Flutter CLI check. No SDK, cache sources, permissions, or global settings
were changed, and no alternate SDK was installed.

| Check (using that bundled Dart) | Actual result |
| --- | --- |
| `dart --version`; `dart pub get --enforce-lockfile` | Dart 3.13.7; locked resolution passed with no dependency/lockfile changes. |
| `dart format` on the five changed Dart files, then `dart format --output=none --set-exit-if-changed .` | Passed; final workspace check covered 32 files with zero changes. |
| `dart analyze --fatal-infos` | Passed; no issues. |
| Core `dart test test/ping_pong_test.dart test/channel_datagrams_test.dart test/companion_messages_test.dart --reporter expanded` | Passed; 39 tests, including 17 new diagnostic groups and one shared-capacity regression. |
| Complete core `dart test --reporter expanded`, then complete CLI `dart test --reporter expanded` | Passed sequentially; 138 and 27 tests. |
| CLI `dart build cli --target=bin/meshctl.dart --output=/tmp/meshchan-1b5.8gyMU6/meshctl`, then core `dart build cli --target=example/serial_transport_check.dart --output=/tmp/meshchan-1b5.8gyMU6/observation` | Both passed once, sequentially, in fresh temporary output. |
| `python3 tool/smoke_cli.py --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --cli-bundle /tmp/meshchan-1b5.8gyMU6/meshctl/bundle --observation-bundle /tmp/meshchan-1b5.8gyMU6/observation/bundle` | Passed; all 46 macOS process checks, both native asset checks, and bundle relocation. Linux-only enumeration refusal was not applicable. |
| `git diff --check`, new/changed-file encoding, exports, relative links, and scope review | Passed; UTF-8 without BOM, LF, final newlines; version, dependencies, lockfile, CI, target 3, and session/reception/native behavior unchanged. |

The focused tests separately assert independent fixed encode/decode vectors,
ordered malformed/unsupported classification, uint32 and content boundaries,
route capacities, exact peer/slot/content matching, ordinary-message summaries,
offset views, ownership, and safe default output. No new runtime dependency,
fake clock, sleep, hardware fixture, or repeated attempt around failing tests
was needed. Native builds/smoke are existing-product regressions; they do not
establish diagnostic AOT execution, actual USB exchange, or LoRa round trips.
No remote CI, real serial enumeration/access, device command, or radio trial ran.
Historical 1B.1–1B.4 and hardware records retain their separate dates and limits.

### 1B.6 implementation and validation

On November 10, 2026, this step starts from clean `master` at
`87ca356a5a4cfb1dd71216ffe02f818ca3288732`, the PR #13 merge, with
`582069faded3e6710e235326b1e6b5b4b9d26d27` included. A fresh read-only GitHub
API check reports PR #13 `MERGED` at `2026-11-10T10:03:25Z`, with the expected
head and `master` base. No remote merge, push, workflow, or publication ran.
The fixed MeshCore upstream and diagnostic v1 wire format remain unchanged.

The new [task API and caller example](diagnostic-tasks.md) document actual
ownership, validation, nonce/elapsed test seams, deadlines, early PONG retention,
entry-delivery barriers, bounded responder pause/yield/settlement, value-key cache,
structural results, and separate actual cleanup. Public exports are in
`meshcore_link.dart`; implementation stays in `src/diagnostics/`. No session,
reception, FIFO, native transport, CLI, dependency, lockfile, version, or CI
behavior changed. The application remains `0.1.0-dev.1`.

Actual validation uses the existing Homebrew SDK's bundled Dart 3.13.7 stable
(`macos_arm64`), process PATH `/opt/homebrew/share/flutter/bin:/usr/bin:$PATH`,
Apple Clang 21.0.0, Python 3.15.2, and macOS 27.2.1 (26B131), arm64.
`flutter --version` was attempted and denied SDK engine-stamp/realm writes;
existing metadata reports Flutter 3.47.9 stable, revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`. That metadata is not a new Flutter
CLI success. No SDK, pub-cache source, global setting, permission, or alternate
SDK was changed/installed.

The focused task/cache tests use real session/reception/codec and fake transport,
controlled write/close Futures, and `fakeAsync.elapsed` with virtual timers.
Cleanup checks cross one zero-duration event turn for the SDK's shared
cancellation Future, then flush the owning virtual zones; they do not sleep
through budgets or retry failed cases. Initial test failures prompted corrections
to local rejection consistency, simultaneous entry/response admission limits,
and retention of entry-limit stop reasons during read failure; assertions also
now observe actual cross-zone cleanup completion.

The final software gate used that bundled Dart, with test processes and native
builds strictly sequential:

| Check | Actual result |
| --- | --- |
| `dart --version`; `dart pub get --enforce-lockfile` | Dart 3.13.7; locked resolution passed, with no dependency/lockfile changes. |
| Changed-file `dart format`; workspace `dart format --output=none --set-exit-if-changed .` | Passed; final workspace check covered 39 Dart files, zero changes. |
| `dart analyze --fatal-infos` | Passed; no issues. |
| Focused `diagnostic_cache_test.dart`, `diagnostic_tasks_test.dart`, `ping_pong_test.dart`, `meshcore_reception_test.dart`, and `meshcore_session_commands_test.dart` | Passed; 98 tests, including 38 new task/cache groups. |
| Complete core suite, then complete CLI suite (`dart test --reporter expanded`) | Passed; 176 core tests and 27 CLI tests on the final Dart candidate. |
| CLI `dart build cli --target=bin/meshctl.dart --output=/tmp/meshchan-1b6.SbwYx1/final-meshctl`, then core `dart build cli --target=example/serial_transport_check.dart --output=/tmp/meshchan-1b6.SbwYx1/final-observation` | Both passed sequentially in fresh final output. |
| Shared `tool/smoke_cli.py`, using those final bundles and the bundled Dart | Passed; all 46 macOS process cases, both native asset checks, and bundle relocation. Linux enumeration refusal was not applicable. |
| `git diff --check`, all changed/new-file encoding/whitespace, exports, relative links and anchors | Passed; UTF-8 without BOM, LF, final newlines; scoped API and documentation only. |

The first smoke invocation omitted the documented process PATH and selected
Homebrew Clang 18; its source build hook failed with `library 'System' not found`.
Restoring `/opt/homebrew/share/flutter/bin:/usr/bin:$PATH` selected the existing
Apple compiler, and all 46 checks then passed. No dependency/cache/permission
workaround was used. After the last task guards/test were added, the final suites
and fresh bundle gate were run again for the delivered candidate.

These software checks do not establish diagnostic task AOT execution, actual USB
exchange, device/firmware compatibility, a USB fix, or LoRa success. No real port
was enumerated/opened and no device/radio command ran. Historical records above
and the [hardware evidence](../hardware-validation.md) keep their separate limits.

#### Review follow-up: fractional diagnostic deadlines

Review identified that positive sub-millisecond task/response budgets could lose
their only timer callback: the installed Dart VM converts Timer delays through
`Duration.inMilliseconds`, while the task checks the finer Stopwatch elapsed
deadline. An early callback could therefore observe an unexpired budget and
leave no later check. The same truncation could stop responder listening early.

Task, response, listen, and task-owned reception scheduling delays now round up
to whole milliseconds. Absolute elapsed deadlines, earliest-deadline precedence,
and exact PONG/admission cutoffs retain their original precision. Zero-duration
fairness turns and existing session/reception implementations are unchanged.
See the [timing API contract](diagnostic-tasks.md#observation-time-and-settlement).

Four additional deterministic test groups use a narrow Zone timer adapter to
reproduce the VM's millisecond truncation, with `fakeAsync.elapsed` in the same
virtual time domain. The task/response/listen regressions failed before the fix.
Cases cover 999- and 1,999-microsecond budgets, both task types during pending
open, independent pending cleanup, and the exact PONG boundary: 998 microseconds
remains eligible for later local settlement, while 999 microseconds is rejected
for a 999-microsecond response budget. No real sleep or hardware is used.

Using the same bundled Dart 3.13.7 and process compiler PATH, locked dependency
resolution, formatting (39 files), and fatal-info analysis passed. Focused
task/cache/protocol/reception/FIFO regression passed 102 tests; the full core and
CLI suites passed 180 and 27 tests sequentially. This follow-up's native build
gate also passed: CLI and serial-observation bundles were freshly built, in
sequence, under `/tmp/meshchan-1b6-timer.XWdUrT/`, and the shared smoke script
passed all 46 macOS process checks, native asset checks, and relocation. Linux
checks were not applicable on this host. Whitespace, UTF-8/LF/newline, and
documentation-link checks passed. Earlier 1B.6 counts above remain the initial
candidate's evidence; no hardware or remote publication ran during this review.

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
diagnostic v1 content budget = maxPayload - 34
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
The public `maxChannelDataPayloadLength` is the single global payload constant.
`maxChannelDataPayloadLengthForRoute(routeDescriptor:, path:)` validates the
send descriptor and exact path with the same checks used by
`encodeSendChannelData()`, then computes the smaller radio/serial capacity.
`maxDiagnosticContentLengthForRoute(routeDescriptor:, path:)` subtracts the
34-byte diagnostic header without duplicating the route formula.

| Validated send route | Maximum payload | Maximum diagnostic content |
| --- | ---: | ---: |
| Flood, empty path | 165 bytes | 131 bytes |
| Zero-hop Direct, empty path | 165 bytes | 131 bytes |
| Direct with a legal 64-byte path (for example, descriptor `0x60`) | 107 bytes | 73 bytes |

Application construction/encoding enforces the global 165-byte limit; successful
encoding does not mean the payload fits an arbitrary route. The caller must
check its actual route, and the send encoder enforces that capacity again.
PING and PONG have equal header lengths and must carry identical content.
When both routes are known, the round-trip content capacity is the smaller
direction's payload capacity minus 34. When only the local route is known, check
only that route; do not infer remote capacity or silently shorten a response.
Receive metadata has no complete path and cannot construct the return route.
These limits do not define article size or a future BBS content format.

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

## Session ownership and staged response dispatch

The session remains the sole owner of
[`CompanionTransport`](../../packages/meshcore_link/lib/src/transport/companion_transport.dart):
one receive subscription, `open()`, `sendFrame()`, and `close()`. Subscribe before
open and keep reception unpaused through transport cleanup. CLI and diagnostics
consume typed results/events; they never also read `transport.frames`. Use a
fresh transport/session for each connection attempt; no automatic reconnect.

At most one device command may be in flight, with a finite pending queue and
explicit rejection when full. All sends and queue reads use that one scheduler.
Future task deadlines must cover queue wait; command timeout starts only at
dispatch. This fixes semantics, not a
general scheduling framework. Existing `info/watch` continue sending only their
two initialization commands; observing `0x83` never enables reception for them.

The following table describes receive integration after successful
initialization. In 1B.4, typed delivery and drain scheduling require explicit
reception start; without it, waiting notices and unassociated data remain
structural summaries. The send/read matching and terminal-failure rules remain
unchanged. A command result is retained on arrival but completes successfully
only after its local send also succeeds. Initialization keeps its existing
type-specific matching policy; OK cannot replace DEVICE_INFO or SELF_INFO.

| Received message | Waiting for send `0x3E` | Waiting for queue read `0x0A` | No pending command |
| --- | --- | --- | --- |
| First valid OK `0x00` | Retain local acceptance; complete when write also succeeds. | Unassociated summary; keep waiting for a queue result. | Unassociated summary. |
| Error `0x01` | Fail with raw code and stage; stop dispatch and clean up. | Fail with raw code and stage; stop dispatch and clean up. | Unassociated structural error; never cache for a later command. |
| Waiting notice `0x83` | Set one receive-pending flag only if receive is enabled; never acknowledge send. | Coalesce flag; never complete this read. | Set flag only for explicitly enabled reception. |
| Valid datagram `0x1B` | Do not acknowledge send; classify as unassociated and deliver to enabled typed reception/matcher if applicable. | Complete one read and classify/deliver the datagram. | Unassociated typed reception only if enabled; no implied push-support claim. |
| Valid chat `0x07/0x08/0x10/0x11` | Structural summary; enabled reception also observes the summary; do not acknowledge send. | Complete one read; enabled reception observes the summary and continues without application filtering. | Structural summary; also delivered to enabled typed reception. |
| Empty queue `0x0A` | Unassociated; cannot acknowledge send. | Complete this read; end drain only if no newer waiting notice remains. | Unassociated summary; does not clear reception demand. |
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

Implemented 1B.4 policy (see the [session API](companion-session.md#explicit-bounded-reception-1b4)):

1. Create a handle, install its single listener, then explicitly start on ready.
   The handle leases the shared queue; accepted manual reads prevent start, and
   running/stopping reception rejects new manual reads. Ordinary sends retain
   original FIFO/capacity semantics. One initial check is retained even without
   `0x83`; create/listen alone never enables reception.
2. Merge notices into one demand flag and a notification sequence. Reserve one
   read only when the original FIFO is idle, never an entire batch. Empty clears
   only demand covered at dispatch, so a notice arriving after empty but before
   write completion still causes a check. No polling or QueueFull retry loop.
3. Nonempty results continue, including ordinary messages. After at most
   `maxReadsPerBatch` completed reads (default 8, including empty), retain a
   continuation across a real Timer event turn. Idle wakes, notices, and resume
   cannot bypass that turn. Saturated user sends may defer reception indefinitely
   within its finite lifetime; there is no fair bandwidth guarantee.
4. Require positive `duration`, `maxEntries` (default 128), and batch size.
   Duration includes queue wait, pause, and batch waits; traffic never renews it.
   The sole decode-path hook adds only datagrams and ordinary-message summaries,
   once per input frame, including unassociated input. Reads' Futures never add
   entries again. Other applications' valid datagrams count normally.
5. Count every add against the lifetime entry cap, including while paused.
   Pause prevents new reads and can withdraw an undispatched owned reservation;
   the transport remains unpaused and no second payload buffer is created.
   Resume retains demand without a new initial check. Async listener callbacks
   do not make Dart wait for business processing.
6. Stop/cancel/duration/quota immediately disable observation and new reads.
   Withdraw only an owned undispatched reservation, without affecting sends or
   session failure facts. A dispatched read still matches/settles normally and
   may consume an entry after stopping; the lease persists until its continuation
   settles. `done` retains the first stop reason and any later command/session
   failure independently of paused stream done or pending native cleanup.

Consumed ordinary bodies are discarded; post-consumption filtering cannot put
entries back. Already-added stream entries can still be delivered after resume.
This is finite queue consumption, not lossless observation, chat archiving, or a
reliable persistent message service. 1B.5's pure application helpers consume
these typed datagrams; 1B.6 now coordinates runtime PING/PONG through the
[finite tasks](diagnostic-tasks.md).
Unassociated typed observation is not proof of firmware push support.

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

## Meshchan diagnostic PING/PONG v1

The outer experimental `data_type = 0xFFFF` is exported as
`diagnosticDataType`. This is a Meshchan diagnostic application protocol, not
MeshCore built-in fields, a production type allocation, or a BBS content format.
Offsets below start at application payload byte zero, excluding all Companion
and serial fields. `diagnosticHeaderLength` is **34 bytes**.

| Offset | Bytes | Field | v1 value or encoding |
| --- | ---: | --- | --- |
| 0..3 | 4 | Magic | ASCII `MCHP`, `4D 43 48 50` |
| 4 | 1 | Version | `01` |
| 5 | 1 | Kind | `01` PING, `02` PONG |
| 6..21 | 16 | Run nonce | Raw bytes, never an integer or UUID |
| 22..25 | 4 | Request ID | Nonzero uint32, little-endian |
| 26..29 | 4 | Sender test ID | Nonzero uint32, little-endian |
| 30..33 | 4 | Target test ID | Nonzero uint32, little-endian |
| 34 onward | Remaining | Test content | Exact binary bytes, possibly empty |

All multibyte fields explicitly use `Endian.little` with
`ByteData.sublistView` and uint32 reads/writes. The three IDs range from
`1..0xFFFFFFFF`; sender and target must differ. These are Meshchan diagnostic
policies, not MeshCore restrictions. Test IDs are user-configured local labels;
avoid duplicate labels in a test environment. They are not public keys, authors,
accounts, or authentication results.

Nonce validation checks only the 16-byte length; all-zero and fixed test nonces
are valid. The codec accepts an explicit nonce and never reads a clock, generates
randomness, or allocates IDs. For each new PING run, 1B.6 uses
[`Random.secure()`](https://api.dart.dev/dart-math/Random/Random.secure.html)
and `nextInt(256)` to generate 16 fresh bytes, with request ID 1. Fail if a
secure source is unavailable; do not fall back to ordinary `Random()`, timestamps, or session
counters. Never reuse or silently wrap a request ID under the same run nonce;
exhaustion requires a new run. Store/compare nonces as bytes, never uint64, one
Dart `int`, or decimal text. Uint32 IDs avoid large-integer representation
differences described in the [Dart number guide](https://dart.dev/resources/language/number-representation).
Nonce/ID correlation supplies no formal authentication, forgery resistance, or
persistent replay protection.

Content extends to the outer datagram boundary. There is no content-length
field, timestamp, checksum, terminator, or reserved tail. Preserve NUL, high
bytes, and invalid UTF-8 without truncation, transcoding, compression, or base64.
Budgets count bytes, never string length. Appending bytes within capacity yields
longer valid content; it can fail exact PONG matching without failing decoding.

### Public API and classification

The existing `package:meshcore_link/meshcore_link.dart` entry explicitly exports:

- `MeshchanDiagnosticMessage(kind:, runNonce:, requestId:, senderTestId:,
  targetTestId:, content:)`, with `DiagnosticKind.ping` / `.pong`, the fixed
  `version` getter, and read-only nonce/content. The factory checks all fields
  and global content capacity before copying bytes. Invalid parameters throw
  `ArgumentError` / `RangeError` without retaining private byte/ID values.
- `encodeDiagnosticPayload(message)`, returning independently owned bytes;
  `decodeDiagnosticPayload(payload)`, accepting logical offset views.
- `classifyDiagnosticDatagram(ChannelDataResponse)`, checking the outer data
  type before application parsing. `QueuedMessageResponse` is filtered by the
  caller's type check; its discarded chat body is neither restored nor parsed.
- `DiagnosticDecodeResult`, with `status`, nullable `reason`, and nullable
  `message`; `DiagnosticDecodeStatus` and `DiagnosticDecodeReason` describe
  nonmatching traffic without exceptions. Exactly a valid result has a message
  and no reason; every other result has a reason and no message/input storage.
- `createDiagnosticPong(datagram:, expectedReceiveChannelIndex:, localTestId:,
  peerTestId:)` and `matchesDiagnosticPong(expectedPing:, datagram:,
  expectedReceiveChannelIndex:)`, described below.
- `diagnosticDataType`, `diagnosticHeaderLength`,
  `maxChannelDataPayloadLength`, `maxChannelDataPayloadLengthForRoute`, and
  `maxDiagnosticContentLengthForRoute`, described in the capacity section.

Classification is ordered; check lengths before reading fields:

1. The datagram entry rejects other data types as `unrelated/differentDataType`,
   even when their bytes look like MCHP. The raw payload API starts at step 2
   and cannot establish the correct outer type or channel.
2. Fewer than four bytes or different magic gives `unrelated/differentMagic`.
3. Complete magic without a version gives `malformed/truncated`.
4. A version other than 1 gives `unsupported/unsupportedVersion`, without
   applying the v1 header length, capacity, or field layout to future versions.
5. Version 1 without kind gives `malformed/truncated`; unknown kind gives
   `unsupported/unsupportedKind` before any v1 body interpretation.
6. A known v1/kind requires at least 34 bytes and at most
   `maxChannelDataPayloadLength`, otherwise `malformed/truncated` or
   `malformed/payloadTooLong`. Zero IDs give `malformed/invalidId`; equal
   sender/target gives `malformed/identicalEndpoints`.
7. Only after validation, copy the nonce and all remaining content into a
   valid model and return `valid`.

An unknown, unsupported, or malformed application is expected nonmatching
traffic, not `CompanionProtocolException`. Parsing does not throw an out-of-range
read, retain failed inputs, close a session, or catch all programming errors.
Malformed Companion envelopes still use their existing protocol failure path.
The final application model does not extend sealed `CompanionResponse`; there
are no new transport subscriptions or session event types. All new application
code is pure Dart without Flutter, session, database, or clock dependencies.
The package's existing native serial code still means this step makes no
whole-package Flutter Web support claim.

### Pure response construction and field matching

`createDiagnosticPong()` validates the configured, distinct, nonzero uint32
local/peer labels and expected local uint8 receive slot (`0..255`). It returns
a PONG only when the actual slot matches, the outer type and application are
valid PING, target equals the local label, and sender equals the configured peer.
It swaps sender/target, preserves nonce/request, and echoes content byte for byte.
Other slots/peers/targets, PONG, unknown formats, and malformed applications yield
null. It does not send, count, reserve a deduplication entry, or check a selected
return route's capacity. A PONG never triggers another response.

`matchesDiagnosticPong()` requires a valid model whose kind is PING; passing a
PONG as the expected request or an invalid receive slot is a local argument
error. It checks the actual local slot, outer type, magic/version/PONG kind,
nonce by byte value, request ID, swapped sender/target, and both content length
and byte values. Independently allocated equal byte arrays match; `Uint8List ==`
identity is never the comparison. The local channel is absent from the payload:
A may send/receive in slot 2 and B in slot 5 on the same actual channel. B checks
5 for its received PING; A checks 2 for its received PONG. Slot configuration
itself is the caller's responsibility.

True means **field equality only**. It establishes neither an active/unexpired
request, uniqueness, local send success, nor a completed round trip. Reception's
typed entry may arrive before send-Future/local-OK settlement, and the local
write may subsequently fail. First-result commitment, early PONG retention,
failure precedence, remote deadlines, and RTT are implemented by the separate
[1B.6 task coordinator](diagnostic-tasks.md).
Unrelated traffic cannot renew runtime deadlines. Default summaries/errors expose
only kind/version/length/reason, never content, full nonces/test IDs, paths,
raw frames, or channel keys. Constructed/decoded bytes are independently owned
and read-only; encoded output is independently mutable.

### Independent fixed application vectors

Both vectors are 38-byte payloads only. They use nonce
`00112233445566778899AABBCCDDEEFF`, request `0x12345678`, A test ID
`0x89ABCDEF`, B test ID `0xF1020304`, and content `00 3C 80 FF`.
Outer type and local channel/receive metadata are explicitly supplied separately
in Companion fixtures. Expected bytes are fixed constants, not encoder output.

PING, A to B:

```text
4D 43 48 50 01 01
00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF
78 56 34 12
EF CD AB 89
04 03 02 F1
00 3C 80 FF
```

PONG, B to A:

```text
4D 43 48 50 01 02
00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF
78 56 34 12
04 03 02 F1
EF CD AB 89
00 3C 80 FF
```

### Frozen runtime deduplication policy (implemented in 1B.6)

Default to one PING without automatic resend. Each finite responder task must
have an explicit response count or duration and use this default policy:

- At most **128 entries**, with a **two-minute** window measured by monotonic
  time from first acceptance for settled records. Key by local receive channel,
  nonce bytes, request ID, sender test ID, and target test ID. Fixed channel/local
  values may be explicit task/cache scope instead of repeated entry fields.
- Content is excluded from the key. The same key with different content is a
  conflict: do not replace the original record or schedule an extra PONG.
- Reserve the first valid, configured-peer/target PING **before** asynchronously
  queuing its response. Duplicates neither send again nor refresh expiry.
  A failed send does not permit automatic retry on a later duplicate; schedule
  at most one response attempt per request by default.
- Remove expired, settled entries first. If 128 entries still remain, ignore
  new unique requests and record a structured runtime capacity reason. Do not
  evict unexpired records to admit more responses and break the window contract.
- An unsettled response remains recorded even beyond two minutes until it
  settles. Existing command/whole-task deadlines bound its lifecycle.
- Two minutes is neither a response timeout, radio delay bound, nor reliability
  promise. There is no persistent replay protection after task end/restart or
  outside the window. Duplicate initiator PONGs cannot replace the first committed
  observation/RTT; active-request checks and commitment belong to 1B.6.

1B.5 supplied the pure codec without a runtime cache or task. 1B.6 now
implements this policy in a task-scoped value-key cache and finite responder;
see [runtime API and settlement](diagnostic-tasks.md#finite-responder-and-deduplication).
Pure matching tests alone do not establish deduplication or round-trip success.

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

Typed task results record independent local-write/device-acceptance status,
matching-PONG observation, content validation, application RTT, failure stage,
raw device error code when present, and cleanup status (`pending`, `succeeded`,
or `failed`). An unattempted or unconfirmed stage must remain distinguishable
from success. The
[task-result Dart API](diagnostic-tasks.md#results-and-actual-cleanup) is
implemented in 1B.6; the [1B.7 CLI contract](../cli.md#finite-datagram-commands-1b7)
now defines command names and field projections. The current
command API is documented above.

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

## 1B.8 software coverage mapping

The [1B.8 audit](../testing.md#datagram-cross-layer-coverage-audit-1b8) and
[dated record](../development.md#1b8-software-validation-on-november-10-2026)
map software coverage to the original plan below. The unchecked historical
1B.1 checklist is retained as a plan, not retroactively marked as hardware
acceptance or as evidence that these tests existed in 1B.1.

| Original software group | Existing implementation evidence | Added 1B.8 representative acceptance |
| --- | --- | --- |
| Codec, length, paths, ownership | Core `channel_datagrams_test.dart`, `companion_messages_test.dart`, `serial_framing_test.dart`, `ping_pong_test.dart` | `raw_send`: independent full outer/inner binary frame and successful short write; fixed diagnostic TX/RX bytes |
| Command/notice interleaving | Core `meshcore_session_commands_test.dart`, `meshcore_session_test.dart`; CLI `datagram_cli_test.dart` | Ordered initialization, local OK, initial queue read, notification-triggered read, no unsolicited `0x1B` push |
| Bounded reception/cancellation | Core `meshcore_reception_test.dart`; CLI final-entry/read and signal tests | `bounded_listen`: ordinary and filtered consumption, final matching entry, split/coalesced bytes, exact quota |
| Application correlation | Core diagnostic codec/cache/task suites; CLI exact match/early-failure tests | `ping_round_trip` and `responder_reply`: fixed nonces/requests/content, swapped peer IDs, distinct slots/local return route, virtual microsecond RTT and finite response count |
| Timeout/disconnect/cleanup | Core session/transport/task suites; original 16 info/watch serial combinations and CLI failure-priority tests | `partial_pong_timeout`: full command/OK then partial outer PONG, first-cause response timeout, late tail, separate stop/done gates, one final failure after cleanup |
| CLI results/privacy | CLI parameter, signal, output, cleanup and private-data tests | All five shared scenarios parse real CLI JSON/NDJSON and check output/counts/facts/cleanup; smoke checks the exact source/AOT probe report |

No production protocol, ownership, queue bound, default, app target (3), or
application version (`0.1.0-dev.1`) changes here. The planned `0.1.0-dev.2`
candidate is not enabled. Core tests retain the broader algorithm and failure
matrices; five shared scenarios add cross-layer execution, not a duplicate
matrix. The native boundary remains synthetic even after AOT compilation.
This does not explain or repair the historical USB partial-body issue.

All hardware items below remain pending for 1B.9: explicit device/firmware and
channel/route inputs, direct and repeater paths in both directions, real local
acceptance versus remote receipt, no-responder timeout, binary boundaries,
cancellation/disconnect, and actual native cleanup. H10 and intermittent USB
findings retain their recorded limits. Builds and assets do not establish FFI
symbol loading, reader-isolate execution, or device compatibility.

## Acceptance to execute later

All boxes below were **planned / not run in 1B.1**. This retained full-1B
checklist is not a claim of passing software or device results; scoped 1B.2 and
1B.3/1B.4/1B.5/1B.6 implementation and validation are recorded above. Follow
the existing [testing evidence boundaries](../testing.md#evidence-limits).

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
  batch continuation/user-command priority, finite queue rejection, and
  cancellation with queued reads. Non-test traffic must finish reads without
  becoming PONG.
- [ ] **Application correlation:** correct peer/run/request/content, wrong
  IDs/version/content, stale or expired entries, duplicate PING/PONG,
  unsolicited PONG, early PONG, and early PONG followed by local failure.
  1B.5 now supplies the fixed application vectors and pure field matching;
  1B.6 adds active-request, deduplication, timeout, and early-failure tests
  through the real core wiring. CLI and hardware acceptance remain separate.
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
the public codec API above. 1B.3 now uses those interfaces for serialized ready
commands and explicit single reads. 1B.4 now exposes `MeshCoreReception` with
finite typed observation and owned-read settlement. 1B.5 now freezes diagnostic
v1 and supplies pure codec/classification, targeted PONG construction, exact
matching, shared route capacities, and the default deduplication policy above.
1B.6 now combines these helpers with the existing receiver/FIFO in
[`MeshchanPingTask` and `MeshchanResponderTask`](diagnostic-tasks.md), including
secure nonce/request lifecycles, finite runtime deduplication, monotonic deadlines,
failure commitment, and application RTT. 1B.7 integrates these operations into
the CLI: parse explicit device/channel/route/peer/content/budget inputs, create a
fresh session, connect cancellation signals, map structural results, and await
both `done` and actual `cleanupDone` plus output settlement. This adapter is now
implemented as `datagram send/listen/ping/respond`; it retains the coordination
logic above and adds only CLI validation, lifecycle wiring, and safe projections.
Radio waits still need measured operator inputs. See the
[1B.7 command contract](../cli.md#finite-datagram-commands-1b7) and separate
[software validation record](../development.md#1b7-software-validation-on-november-10-2026).
1B.8 adds the [software coverage mapping](#1b8-software-coverage-mapping)
and retained development bundles. No hardware acceptance or full-1B release is implied.

1B.1 review is limited to current-code/source comparisons, table/formula
consistency, relative and fixed-commit links, UTF-8/LF/whitespace checks, and
scope/diff review. It does not establish unit-test, build, or hardware acceptance.
The listed upstream evidence was accessible; deployment-specific firmware
support, channel settings, routes, and radio behavior remain unverified.
