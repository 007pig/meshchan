# openHop TCP 5050 / command 0x3E: missing OK investigation

Status: **Failure reproduced; upstream modification proposal withdrawn.**
The operator explicitly excluded changes to openHop. Meshchan's subsequent
[client compatibility work](phase-1d11-delayed-ok-client.md) handles delayed OK
within its own finite policy. No openHop code or configuration was changed.
The deployed B deferred a local
transmission by 19.1 seconds, beyond the unchanged 15-second client budget.
Standard OK worked for two single sends. A subsequent PING received no OK and
timed out while sending. Meshchan must retain that failure; it must not convert
local flush, a raw receive log or a late transmission into device acceptance.
The beta remains prepared / acceptance incomplete, with RF stopped.

## Scope and provenance

The operator requested web/source investigation of selected B's TCP 5050 and
`0x3E` implementation, practical compatibility, and renewed RF tests. Existing
USB A / independent B selection, exclusive-client assertion, no cumulative
application-send ceiling, original finite parameters, shared-inbox consent and
abnormal-stop rules remained. No A app, USB client or responder was started.
No firmware, radio/duty-cycle/Fabric setting, startup delay or timeout changed.
No WS/REST-send fallback, resend or server reset occurred.

Hardware evidence is
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-05/`; fetched source and the
isolated upstream candidate are in the same evidence root's
`research/openhop-ok-20261116/`. Python is `/opt/homebrew/bin/python3` 3.15.2;
Dart is Flutter 3.50.0's bundled 3.14.0. The branch remains
`codex/phase-1d11-hardware-beta` on actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, with manifested uncommitted work.
Complete product app/CLI inventories and their 106 compiled product inputs
remain unchanged. The diagnostic peer has a separate complete native bundle.

Read-only documented `/api/stats` reported Repeater `1.1.5.dev231`, Core
`1.1.4.dev9`, radio type `modem_tcp`, and two radio entries. The first metadata
probe rejected the response at its 64 KiB bound; the retained second probe read
225500 bytes under a 1 MiB metadata-only bound and projected version fields.
This did not change a hardware-task budget. API keys stayed in memory; stats
configuration, keys, locations and packet contents were not published. Recent
server logs are owner-only outside Git. No remote code or configuration was
written. Reported package versions do not attest installed file hashes.

## Upstream contract and actual observations

Reviewed source cuts include:

- Core main `e07722ea96093752ac8b3c6772d653f8b68224bf` and dev
  `63f9d305a7de79b3356123c07fe7d2f8d3f1e448`. Dev declares version
  `1.1.4.dev9`; the two `_cmd_send_channel_data` method ASTs are identical.
- Repeater main `13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b` and dev
  `98444069ee49d21aff1e2a4d67a53ae7c53fecaa`. These public source cuts are
  comparison inputs, not a claim that installed files exactly match them.

The [Core command handler](https://github.com/openhop-dev/openhop_core/blob/63f9d305a7de79b3356123c07fe7d2f8d3f1e448/src/openhop_core/companion/frame_server/commands_messaging.py#L264)
validates the selected slot/route/type/payload, then awaits
`send_channel_data`. Success calls `_write_ok`; failure calls existing
TABLE_FULL error 3. The [TCP transport](https://github.com/openhop-dev/openhop_core/blob/63f9d305a7de79b3356123c07fe7d2f8d3f1e448/src/openhop_core/companion/frame_server/transport.py#L121)
frames OK as `3e 01 00 00`; there is no alternative success code to accept.
Its read loop awaits the command handler before reading another command or EOF.

The [Core send method](https://github.com/openhop-dev/openhop_core/blob/63f9d305a7de79b3356123c07fe7d2f8d3f1e448/src/openhop_core/companion/base_send.py#L569)
awaits its packet injector with wait_for_ack false. This flag concerns the RF
ACK path; it does not eliminate the Repeater's transmit scheduling wait. The
[Repeater router](https://github.com/openhop-dev/openhop_repeater/blob/98444069ee49d21aff1e2a4d67a53ae7c53fecaa/repeater/packet_router.py#L429)
awaits the local engine. The [engine](https://github.com/openhop-dev/openhop_repeater/blob/98444069ee49d21aff1e2a4d67a53ae7c53fecaa/repeater/engine.py#L513)
adds a duty-cycle wait for local traffic and awaits the actual egress task.
Thus OK can remain unwritten while a valid command waits to transmit.

The diagnostic uses the actual source peer runner/session/TCP transport with a
transparent socket/frame observer: one connection, one socket receive
subscription, no additional command or polling. It records chunk sizes and
complete-frame opcode/length; only exact public control-byte patterns are
retained as bytes. No ordinary message payload, name, location or key is logged
by that observer. The observation layer passed real local TCP self-tests in
both host Dart VM and native AOT before real B use. Here VM means the Dart
runtime on the host Mac; no macOS guest or USB passthrough was used.

| Finite case | Actual result |
| --- | --- |
| Host Dart VM B-only raw send, 18-byte synthetic payload | PASS local acceptance: actual standard OK after 2150134 microseconds; zero GET_MSG; normal cleanup |
| Native AOT same raw-send shape | PASS local acceptance: actual standard OK after 2324412 microseconds; zero GET_MSG; normal cleanup |
| Native AOT PING without A/responder, 18 content bytes / 52 diagnostic payload bytes | FAIL local-acceptance prerequisite: one send, one GET_MSG/entry, no OK, responseTimeout/sending at the original 15 seconds; normal cleanup |

Each case used one application-send attempt, request/init/task 15/30/90 seconds,
startup zero, B slot 3 and Direct empty path. The PING retained response 15
seconds/maxEntries 512 and fresh nonzero labels distinct from prior cases.
The intended no-responder result required local OK then responseTimeout/waiting;
the actual sending-stage timeout did not satisfy that assertion. The runner
stopped after this unexpected result. No native-original comparison, retry,
GUI matrix continuation or other RF test followed.

The PING wire trace shows GET_MSG at 19:24:41.620120 UTC, one channel-data
response, then command `0x3E` at 19:24:41.620644 UTC, 60 serial bytes. After that
only one complete `0x88` raw receive-log frame arrived. All received bytes are
accounted for by complete frames: there was no residual partial OK. The final
projection retained dispatched/write-completed true, OK/acceptance false,
pendingAtTermination true, exact PONG/round trip false and RTT null. It closed
at approximately 19:24:56.623 UTC. No `0x88` frame is treated as acknowledgment.

In the same selected connection window, the server logged:

| Server time, UTC | Event |
| --- | --- |
| 19:24:41.612938 | Companion client connected on 5050 |
| 19:24:41.618459 | Duty-cycle limit: local TX deferred 19.1 seconds, estimated airtime 705.5 ms |
| 19:25:02.653705 / 19:25:03.414734 | Two 69-byte transmissions completed |
| 19:25:03.414924 | Companion connection ended, writer_failed |

The 19.1-second deferral itself exceeds the original client budget and matches
the awaited upstream code path. The later transmission sizes/timing are strongly
consistent with that diagnostic send; no unique RF packet hash was retained,
so they are not claimed as a cryptographic packet-identity comparison. These
observations explain this fresh failure mechanism. They do not retroactively
prove the causes of all earlier missing-OK invocations or isolate payload size
from reception/interleaving using only these three cases.

Closing the local peer does not retract a remote job already queued behind this
await. Local cleanup succeeded, but the server could still transmit later. This
is why an ambiguous send counts and why retrying on the timeout is unsafe for
this acceptance workflow. The two radio completions are not two additional
application-send attempts; actual airtime/forwarding remains a separate fact.

## Withdrawn upstream proposal

The initial investigation prepared a two-file server proposal. The operator
rejected that direction because modifying openHop is outside this project's
scope. It was never deployed and is no longer a Meshchan deliverable. The
following describes that preserved historical attempt, not requested next work:

1. The Repeater router labels only companion-originated GRP_DATA injects.
2. If the engine already knows that duty-cycle budget is insufficient, it returns
   false **before scheduling** that send. Other injectors and packet types retain
   their current behavior; with budget available this candidate retains the
   existing send path.
3. The existing, unchanged Core handler returns standard `ERR 3`, not a fake OK.
   Meshchan already handles this as deviceRejected, without local acceptance,
   retries or a false round-trip claim.

The withdrawn patch is based on Repeater dev
`98444069ee49d21aff1e2a4d67a53ae7c53fecaa` and has SHA-256
`cbcb03e528da3447d4960a6823bbb910561aa864a16e42185865cca68767043b`.
The patch and licenses remain only in prior owned research/source snapshots,
outside the repository, to preserve provenance. They were removed from the
current repository; no deployment is proposed. The previous frozen delivery
source snapshot is also a historical cut, not the current client source.

Eight focused Python tests execute the fetched upstream method ASTs with
bounded dependency stand-ins. The original engine schedules the modeled
19.1-second wait; the candidate refuses without scheduling; an available budget
and other local origins preserve their original path. Router scoping is checked
for companion GRP_DATA versus non-companion and other types. The real fetched
Core handler/writer emit the exact existing ERR frame after rejection and defer
OK until a successful send actually returns. An isolated `git apply --check`,
apply and byte comparison matched the tested candidate. No upstream dependency
was installed, no full upstream suite was run, and no live service was changed.

Meshchan adds one actual loopback TCP regression proving that ERR 3 becomes
deviceRejected with no retry or false acceptance. The focused TCP/peer/observer
subset now passes **32 tests**; fatal-info analysis and formatting pass. Gate
receipts are `D11-hw05-upstream-candidate-focused`,
`D11-hw05-TCP-peer-error-compatibility` and `D11-hw05-error-test-analysis`.
The first external-entrypoint native build lacked an explicit package map and
failed before hardware; that receipt remains. The corrected explicit-package
build and AOT loopback/config gates passed. No product code was changed.

The withdrawn candidate did not bound unrelated TX-lock, modem, network or
other server waits. Full upstream and deployed tests were not run. These
offline checks do not count as client compatibility or beta acceptance.

## Historical RF cutoff and current scope

This investigation used three real B sessions / three application-send attempts,
one consumed inbox entry and one read. Cumulative application attempts are
**seven with no cumulative ceiling**; retained B consumption is 282 entries /
288 reads. RF is stopped, all owned consumers have exited, and USB was not
opened. Existing app `0.1.0-beta.1+4`, CLI `0.1.0-beta.1`, GUI History six rows,
previous manual text and the tested complete product inventories remain at
their original cuts. No new GUI exact-PONG, active Quit or physical cycle pass
is inferred from this diagnostic work.

The operator explicitly prohibits modifying the existing Repeater service.
No SSH/deployment access or server restart is needed for the current work.
The client now separates its finite send-confirmation and remote-response
clocks while preserving a fixed whole-task deadline, real OK/exact-PONG checks,
one owner and no automatic retry. See the linked client record for its actual
software/native coverage and pending RF validation. No installer, SDK/dependency
upgrade, commit, push, PR or public release was performed. 1D.11 and the beta
hardware acceptance remain incomplete.
