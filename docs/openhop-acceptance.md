# USB and openHop development acceptance (1B.9)

The product `meshctl` remains USB-only. The source-only
[openHop peer](../apps/meshctl/tool/openhop_peer.dart) is a finite development
adapter for one explicitly selected virtual Companion. It is excluded from the
product bundle. It uses the same Meshchan session, reception, diagnostic tasks,
matching, nonce generation, and deduplication as the product; it is not an
independent application-protocol oracle. Successful hardware evidence would mean
native Meshchan USB CLI and an openHop virtual Companion interoperated through
real LoRa. Control traffic over HTTP/WS is not an application return path.

## Reviewed compatibility baseline

Reviewed Repeater commit:
`13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b`, depending on `openhop_core==1.1.3`;
reviewed Core commit: `e07722ea96093752ac8b3c6772d653f8b68224bf`.
These source revisions do not establish the installed deployment's versions.
No server upgrade, firmware flash, configuration change, or channel/key import is
part of this workflow. MeshCore stays pinned to
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`.

| Interface | Use and evidence boundary |
| --- | --- |
| `GET /api/companion/` | Discover registration names and reported running state; never silently choose the first item. |
| `GET /api/companion/self_info?companion_name=...` | Read selected identity/radio settings. The peer retains only necessary radio numbers. |
| `GET /api/companion/channels?companion_name=...` | Read slot/name metadata, retaining slot numbers only. Names cannot prove equal PSKs. |
| `/ws/companion_frame?token=...&companion_name=...` | JWT-authenticated binary byte proxy to the selected Companion frame server. URI parameters use Dart `Uri`, including registration-name encoding. |
| Text send, remote CLI command, SSE events | Not used for binary datagrams, reception evidence, or PONG correlation. |

Primary sources: [REST endpoints](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/companion_endpoints.py),
[WS proxy](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/companion_ws_proxy.py),
[routing](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/http_server.py),
[Core frame server](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/server.py),
[Core messaging](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/commands_messaging.py),
[persistent queue](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/companion/frame_server.py).
Actual observations belong in the [hardware record](hardware-validation.md#1b9-usb-and-openhop-acceptance-on-november-10-2026).

## Obtain and reference a JWT

REST accepts Bearer JWT or `X-API-Key`. The reviewed WS proxy accepts a JWT in
its query only; an ordinary API key cannot replace or be converted to it.
The reviewed login endpoint is **`POST /auth/login`**, not `/api/auth/login`.
It requires JSON fields `username`, `password`, and `client_id`; the reviewed
username is `admin` and the password is the existing administrator password.
A successful response has `success`, `token`, and `expires_in`. The latter is
controlled by deployment configuration; do not assume the source default.
See [login implementation](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/auth_endpoints.py)
and [JWT verification](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/auth/jwt_handler.py).

Log in using the existing browser UI with Network tools open and locate the
`/auth/login` response. Save `token` in a restricted file outside the checkout.
This zsh example prompts without echo and puts no secret in process arguments:

```zsh
umask 077
mkdir -p "$HOME/.config/meshchan"
read -rs 'meshchan_jwt?Paste the JWT, then press Return: '
printf '%s' "$meshchan_jwt" > "$HOME/.config/meshchan/openhop.jwt"
unset meshchan_jwt
chmod 600 "$HOME/.config/meshchan/openhop.jwt"
```

Use `"jwt": {"file": "/absolute/outside-checkout/openhop.jwt"}` or
`"jwt": {"env": "MESHCHAN_OPENHOP_JWT"}`. A separately exported terminal's
environment is not automatically inherited by an already-running agent.
Provide only the file reference when collaborating. Do not put secrets in source,
arguments, examples, reports, or commits. REST-only preflight can instead use
`"apiKey": {"env": "MESHCHAN_OPENHOP_API_KEY"}`; `info` reports
`BLOCKED_JWT_REQUIRED` without attempting WS if no JWT reference exists.
Normal SDK certificate validation remains enabled for HTTPS/WSS. Use the actual
supplied deployment URL; no host/port scan or certificate bypass is performed.

## Finite source tool

Use the installed Flutter SDK's bundled Dart. No new SDK, dependency, AOT product,
or CLI connection flag is required. Configuration parsing and route/budget
validation occur before secret reads or network access. Invalid configuration
reports a fixed safe error; raw HTTP responses, close reasons, exception URLs,
and credential values are not logged. Secret files must be absolute, at most
8192 bytes, and owner-only on Unix. Configurations are limited to 64 KiB.

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$MESHCHAN_DART" run apps/meshctl/tool/openhop_peer.dart --help
"$MESHCHAN_DART" run apps/meshctl/tool/openhop_peer.dart \
  --config /absolute/private/H0-b.json info
# After reviewing operation-specific configuration:
"$MESHCHAN_DART" run apps/meshctl/tool/openhop_peer.dart \
  --config /absolute/private/H3-b.json respond
```

The [peer example](examples/openhop-peer.example.json) uses offline example IDs
1/2 and placeholder slots; never use those IDs for a real matrix. `info` uses
`baseUrl`, registration `companionName`, `endpointLabel`, secret references,
`session`, and `idleTimeoutSeconds`. Only `info` allows a null idle timeout,
recorded as unknown, because it does not start an inbox listener. It performs the
three GETs, then one WS/session initialization and actual close. It sends no RF
diagnostic datagram. A reported REST running flag and a real session outcome are
recorded separately; an HTTP upgrade alone is not readiness.

`send/listen/ping/respond` additionally use `datagramArguments`, validated by the
existing product datagram option parser. Session budgets come from the explicit
`session` object, not product default changes. These operations require a known
positive idle timeout and explicit entry/response limits. `listen` requires
`expectedPayloadHex`, receive slot, type, duration, and max entries. It compares
actual queue events in memory and reports only channel/type/length, match flags,
and counts. It never prints ordinary-message bodies or raw payload bytes.
`ping` uses `MeshchanPingTask` with secure runtime nonce generation; `respond`
uses `MeshchanResponderTask`. No diagnostic algorithm is copied into the peer.

The thin transport uses `encodeSerialFrame` once and incremental
`SerialFrameDecoder` reception. A binary WS message can contain a partial frame
or several frames; a text message is rejected. SDK `maxPayloadLength=8192`
bounds messages before assembly, compression is disabled, and the existing
176-byte inner-frame/noise policies remain intact. HTTP redirects are disabled.
There is one connection attempt, one receive subscription, no reconnect/fallback,
and no WS heartbeat or extra queue polling. `0x09` is an unrelated notification;
it does not complete commands/PONGs or renew budgets. Late successful opens after
cancellation are awaited and closed; close is idempotent and awaits owned
connection/subscription/client cleanup. There is no forced successful cleanup,
production cleanup timeout change, or `exit()` workaround.

`localWriteCompleted` in **B peer** projections means only that the local WS
submission interface completed. It is not a native USB write, TCP receipt,
openHop processing confirmation, or RF transmission completion. A separately
associated Companion OK establishes local acceptance. Only an exact PONG
establishes an application round trip. RTT includes hosts, queues, USB, WS,
openHop, and radio processing, not just airtime.

After a task accepts ownership, only the task connects, sends, receives, and
closes. The helper's session observer subscribes read-only and emits
`peer_session_ready` only from an actual ready state; it does not claim RF
readiness or an empty queue. Raw B reception additionally emits
`peer_reception_active` after reception activation. Observers/signals are
unsubscribed after actual cleanup. The product's A raw listener/responder has no
ready or per-response event. Starting a process, starting a task, or sleeping
cannot establish A readiness.

## Prepare a reviewable matrix

Copy the [input template](examples/openhop-acceptance-input.example.json) outside
the checkout. Fill all four local slots, actual radio compatibility and key
confirmation, deployment versions/sources, radio binding, idle timeout, and
ownership/queue consent. Do not export PSKs. A and B's slots can differ.
A is the user's explicit `/dev/cu.usbmodem211101`; do not carry this selection to
a later replug without reconfirming the actual path.

```bash
python3 tool/prepare_openhop_acceptance.py \
  --input /absolute/private/acceptance-input.json \
  --output /absolute/private/new-matrix \
  --candidate /absolute/build/delivery/candidate
```

The generator performs no network/USB operations and rejects incomplete
prerequisites. It creates reviewable `commands.txt`, `plan.json`, and B JSON
configurations. Each H1-H7 case gets fresh, distinct, nonzero uint32 test IDs
(shared between its sides), avoiding 1/2; raw content includes a fresh marker.
PING still uses a new secure nonce at runtime. Test IDs are correlation labels,
not authenticated device identities. Do not rerun a failed case until a new
finite scope is authorized and separately recorded.

The starting plan fixes zero-hop Direct/empty paths on both sides. It uses
command 5 s, initialization 15 s, startup delay 0, PING response 20 s/task 60 s,
listener/responder duration 60 s/task 90 s, maxEntries 128. The generator requires
an actual idle timeout covering 90 s; shorter deployments need a separately
reviewed plan, not a server change or automatic budget increase. B's window must
cover A initialization plus response wait. Product defaults remain unchanged.

| ID | Receiver first and operation | Passing evidence; expected exits A/B |
| --- | --- | --- |
| H0 | One A native info; B REST plus one WS info | Both real initialization and actual cleanup; 0/0. No RF claim. |
| H1 | B raw listen, then A raw send once | A local write/OK; B real queue event with this trial's exact bytes/type/slot; 0/0. |
| H2 | A finite raw listen, then B raw send once within its window | A matching structure only; current A CLI cannot establish exact bytes/sender; 0/0. |
| H3 | B respond maxResponses=1, await real ready, then A ping | A exact PONG, non-null successful RTT, roundTripSucceeded, cleanup; B finite completion; 0/0. |
| H4 | A respond maxResponses=1, then B ping with empty content | B exact PONG proves A was responsive at that instant; A local response facts/cleanup; 0/0. |
| H5 | B respond maxResponses=1, then A ping at min of both route capacities | Both zero-hop Direct capacities permit 131 content bytes; includes NUL/non-UTF-8 and exact round trip; 0/0. |
| H6 | After all B responders complete and no automatic reply remains, A ping | Local acceptance succeeds, strict responseTimeout, null successful RTT, cleanup; 69/none. |
| H7 | A respond maxResponses=2; B obtains one exact PONG, then signal that still-active A PID | A SIGINT exit 130, correct first cause/cleanup, one planned reply, no later sends; B 0. An already-ended A cannot pass cancellation. |

The normal plan expects 11 application datagrams and permits at most 12 sending
attempts (H7 allows two responses). Record actual counts separately; this is not
RF airtime, total transmissions, forwarding, or existing-traffic accounting.
Every case runs once without implicit retries. Preserve failures and unknowns.
Record UTC start/end, argv without secrets, build/tool hashes, endpoints, slots,
routes, limits, content lengths, local facts, exact matches, reason/stage/opcode,
cleanup, and actual/expected exits. Expected 69/130 may pass their defined cases.
Initialization failure is not RF loss. If cleanup is pending/failed, stop before
opening a conflicting next connection; never use a watchdog/kill as cleanup.

One virtual Companion has one TCP client slot; WS can displace a Terminal/client.
The user must release that slot first. Its identity owns a persistent shared
inbox; reconnect is not a queue reset. `0x0A` consumes entries, including other
channels and ordinary chat, which spend maxEntries. Do not clear the queue,
automatically add quota, or replay a case after old traffic consumes its budget.

Independent relay paths and physical ready-state USB unplug are conditional and
separately counted. A logical openHop repeater sharing the same modem is not an
independent RF hop; Flood does not substitute for a specified route. Unplug
requires an actual `watch` ready event and the planned human action. A WS control
connection close is neither modem unplug nor RF failure. Historical incomplete
USB bodies and H10 failures are preserved; a new success does not prove repair
or establish a reliability percentage.


## Observed deployment differences

The selected deployment reports Repeater 1.1.5.dev231/Core 1.1.4.dev9, while the
reviewed baseline uses Core 1.1.3. H0 actual REST/WS initialization/cleanup passed;
its REST running flag remained false. The deployed Fabric has two modem_tcp
radios, bridge mode and origin_tx=all, so a single physical B radio cannot be
assumed. User-authorized management reads outside the peer's three-GET preflight
used `/api/stats` and explicitly redacted config export, keeping only required
version/binding/timeout fields. No raw config or secret was retained. Missing
explicit tcp_timeout is not a measured effective timeout. See the
[full actual record](hardware-validation.md#1b9-usb-and-openhop-acceptance-on-november-10-2026).

The user subsequently reported `link` modem temporarily off. This does not erase
the configuration snapshot or independently identify the remaining `local`
modem as distinct from A. No reconnection or setting change was attempted.


## Finite read-only channel audit

`apps/meshctl/tool/channel_audit.dart` is a separate source-only development
entry point. It queries A over the explicit USB path and B over the selected
Companion WS proxy. The product CLI and production session API are unchanged.
Use [the audit template](examples/channel-audit.example.json), with a restricted
JWT file/environment reference. Optional `endpoints` is `["A", "B"]` (default),
`["A"]`, or `["B"]`; a one-endpoint run never claims a key comparison.

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart run \
  apps/meshctl/tool/channel_audit.dart --config /absolute/private/audit.json
```

Validation precedes I/O. Slots are explicit unique indices 0-39, or
`"allReported"`, bounded by the device's reported capacity and a 40-slot limit.
The initial actual plan queries A's reported 40 slots and B slots 0-7 from its
previous REST listing, at most 48 channel queries and four initialization
commands. It opens each selected endpoint at most once per invocation. A failure
ends that invocation; there is no automatic retry inside the tool. Additional
user-authorized invocations retain separate plans/results.

The unchanged MeshCoreSession owns initialization/lifecycle around a tool-local
transport decorator. This decorator has one underlying receive subscription;
it intercepts secret-bearing `0x12` replies before production parsing/events.
After session ready, the only tool-originated commands are serialized
`GET_CHANNEL (0x1F)` operations. No production ready command/task/reception is
started, so the core FIFO stays empty. The adapter allowlists initialization
opcodes 0x16/0x01 and the private query path emits only 0x1F. It never sends
0x0A, RF application commands, configuration writes, or channel changes.
Current-time/waiting notices cannot satisfy queries or renew deadlines.

Replies must be exactly 50 inner bytes with the expected index: opcode/index,
32-byte name field, 16-byte key field. Longer/shorter key layouts and mismatched
indices fail closed. Empty-name/all-zero-key entries do not participate in
matching. Only slot metadata and comparison results are output; names, PSKs,
key fingerprints, raw frames and exception bodies are omitted. Owned key buffers
and intercepted secret-bearing frame buffers are cleared after use. This is
not a forensic erasure guarantee for every managed-runtime or SDK copy.

A match means equal **16-byte values returned by the Companion interfaces**.
It cannot inspect an internal extended key that a different server version might
hide behind a truncated response. `sameReturnedKeyConfirmed` and the explicit
`confirmationScope` retain this boundary. No channel pair is automatically
selected. Duplicate-key slot lists are reported; inferred receive slots are
null when queried duplicates make them ambiguous. A later real received event
still supplies the actual receive-slot/RF evidence.

Command/init/endpoint budgets are explicit (actual starting values 5/15/90 s).
Cancellation or timeout closes the real session and awaits cleanup before a
result. Cleanup is not forced successful by a watchdog. Separate endpoint mode
can inspect a still-unused endpoint without retrying a failed A connection.

The [actual channel audit record](hardware-validation.md#read-only-channel-audit-on-november-10-2026)
preserves two A initialization failures and a complete successful comparison,
plus the development WS cleanup fix and its independent B-only verification.

## Passive window and actual Direct execution follow-up

`tool/openhop_idle_probe.dart` (under `apps/meshctl`) opens one selected WS
Companion, initializes with only 0x16/0x01, then observes passively for an
explicit 1-120 seconds. It reuses the unchanged session/watch lifecycle and
filters reports to structural counts. There are no queue reads, RF sends,
heartbeat commands or reconnects. Add `observationSeconds: 95` to a private
info-compatible config and run:

```bash
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart run \
  apps/meshctl/tool/openhop_idle_probe.dart --config /absolute/private/probe.json
```

A successful finite observation reports a lower bound on the observed passive
window. It cannot determine the server's exact configured idle timeout. Actual
read-only config/log inspection found no effective value. Two early connections
were displaced by another client; after the user closed MeshCore One, a 95-second
window and actual cleanup passed. Client displacement is retained as an actual
limitation. The user also confirmed the remaining local modem is physically
distinct from A, with link temporarily off.

Peer configs accept either a positive exact `idleTimeoutSeconds` or a measured
`idleWindowLowerBoundSeconds`, never both. A lower bound must cover the configured
task timeout; it must not be relabeled an exact server timeout. The plan generator
can accept `idleWindowEvidence` pointing to a successful probe report; it checks
ready, duration, cleanup, and absence of post-init host commands. The actual
95-second evidence covered B's 90-second task windows without changing defaults.

`tool/run_openhop_acceptance.py --plan <absolute-plan> --output <fresh-directory>`
validates the actual generated plan without device/network I/O. Add `--execute`
only within the reviewed finite authorization. It never retransmits an application
packet automatically. The user's later initialization-retry permission allows
at most three attempts only when initialization failed before a send/consumption
and actual cleanup succeeded. `--only-case H2` or `H7` selects a separately
reviewed follow-up. Increased sending ceilings or command budgets require a
concrete additional authorized plan; pending plans are not evidence.

Actual A slot 1/B slot 3, zero-hop Direct execution established exact PONGs in
both directions and with 131 bytes of binary content. H1 also matched real raw
bytes in memory; H6 strictly timed out waiting for PONG after local acceptance.
H2 and H7 initially retained local-OK timeout failures. A subsequently authorized
B-command-15-second/A-5-second comparison passed H2 local acceptance and H7
exact-PONG-gated active cancellation; earlier failures remain. Cumulative
application send attempts are 14 of the approved 15 ceiling. The latest bounded matrix is
[recorded with all failures](hardware-validation.md#direct-rf-matrix-on-november-10-2026),
with the [comparison details](hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026).
Every basic case now has a passing record across these dated trials; this does
not relabel the original single matrix as a clean pass. RTT includes all host/control,
queue and RF processing. Specified relay paths and ready-state USB unplug remain
unexecuted, and historical USB failures remain unexplained.

## Review-fix validation boundary

The later review follow-up fixes raw listen failure reporting and WS close
before open/with paused public delivery. It preserves the existing receive-EOF
cleanup gate for real connections; no cleanup watchdog or product timeout was
added. A raw consuming-read timeout now keeps reception counts and its opcode
failure without inventing an application send. Legacy read-only results are also
excluded from the Python runner's application-send counter.

The runner's offline validation now reads each selected B config, checks the
expected A/B operations and explicit zero-hop/empty paths, and derives the send
allocation from actual command limits. H3/H4/H5 responders must explicitly use
1 and H7 must use 2; missing, duplicate or increased limits are rejected before
creating output or launching a process. Generated plans use canonical
`--name=value` options. This validates matrix roles/routes/send limits; ordinary
CLI/config validation remains in the existing Dart tools. The approved cumulative
ledger and concrete authorization still apply independently to each new run.
No new RF execution was performed for these review fixes. Actual earlier trial
hashes, failures and 14/15 accounting remain preserved separately from the later
source-only [91-test/6-test software record](development.md#development-tool-review-fixes-on-november-11-2026).

## Failed settlement and captured native evidence

A cleanup failure now stops further cases but still waits every already-started
finite peer before recording the case and STOPPED. Actual cleanup failures and
still-active PIDs remain visible. No extra signal, retry, connection or forced
kill is introduced. If a sender has no authoritative final send facts, actual
attempts are null; known attempts and the validated reserved upper bound are
retained. Such uncertainty blocks a passing summary and cannot replenish the
remaining sending allowance.

The summarizer requires each run's captured native hashes, agreement across
runs, and matching current candidate bytes. It also rejects stopped/incomplete
legacy runs lacking case results. Use a distinct output to preserve an earlier
summary:

```bash
python3 tool/summarize_openhop_acceptance.py \
  --directory /absolute/evidence-directory \
  --candidate /absolute/complete-product-bundle \
  --output /absolute/new-summary.json
```

`nativeHashes` now comes from the captures; it is not assigned from a newly
rebuilt binary. Missing/mixed captures or changed candidate bytes fail before
writing output. No-device Python regressions and the dated verification of
retained hardware evidence are recorded in the
[settlement/native-evidence follow-up](development.md#settlement-and-native-evidence-fixes-on-november-11-2026).

## Probe files, channel integers and interrupted-run coverage

`idleWindowEvidence` may point directly at the JSON written to stdout by
openhop_idle_probe.dart. Its flat `exitCode`/`status`/`cleanup`/passive-window
fields are validated without an outer wrapper. Historical files containing
`actualExitCode` plus `report` remain supported; both process and report exit
facts must agree when present. Unsuccessful cleanup, a short window or host/RF/
queue activity cannot qualify. The same validator is used when summarizing
recorded probe evidence. The exact timeout can be omitted when observed-window
evidence is provided; generated peer configs record it as null.

The finite runner accepts the product CLI's decimal channel syntax, including
`01`, and explicit 0x/0X hexadecimal. Receive-channel interpretation happens
before any device process starts. A validated numeric channel is retained for
later receive-event evaluation, without reinterpreting the original argument
after execution.

The summarizer now examines process metadata even alongside partial case
results. Every recorded invocation must be represented with matching identity
and available final facts. A later unfinished process, missing retry or stale
case result rejects generation rather than publishing an incomplete send total.
Reconcile the retained case/process evidence before trying again; rejection does
not restore sending quota or authorize a new run. See the
[25-test/91-test software record](development.md#interrupted-runconfiguration-review-fixes-on-november-11-2026).

## Execution coverage, raw-session health and archive provenance

The summarizer scans the entire selected evidence tree for execution-plan.json,
results.json, STOPPED.json and per-process metadata. Evidence outside its explicit
trial-directory registry rejects generation before output is written, even if an
older registered run passed. A new runner output directory must be reconciled
into that registry and its accounting before summarizing. Probe/config-only
directories do not constitute executions. Symbolic evidence entries also reject;
an incomplete ledger cannot establish a remaining sending allowance.

Raw info/send/listen completion also checks the session's recorded failure after
actual cleanup. A send OK followed immediately by a transport error preserves
local-write/OK/acceptance facts, but reports session_failure and exit 69. It cannot
qualify H2 as a successful B session. A session cancellation is handled by the
existing cancellation path; diagnostic task terminal gates remain task-owned.

Metadata-only archive revisions now copy a fresh verified extraction of the
original tar.gz. The original external verification binds its whole-archive hash,
member checksums, complete layout, executable permission and tested native hashes.
A regenerated sibling delivery directory and its manifests are not source evidence.
The [dated review record](development.md#ledger-raw-session-and-archive-provenance-fixes-on-november-11-2026)
documents synthetic regressions, local loopback tests and the verified revision.
No hardware run of the later helper source is inferred from those checks.

## Channel-audit failure boundary

The read-only channel adapter retains an observed failure independently of a
pending GET_CHANNEL query. A final reply cannot erase a following transport
failure before the session receives its queued event. The runner reconciles
that retained failure after each query and after actual cleanup before reporting
success or opening B. Completed read summaries remain visible, but a failed
endpoint cannot establish an A/B key comparison. Normal close and user signal
handling retain their existing meanings. The [offline regression record](development.md#channel-audit-final-query-failure-fix-on-november-11-2026)
does not constitute a new device readback or RF test.

The adapter also validates observed non-channel frames immediately with the
existing Companion decoder, including while final cleanup drains the input.
Malformed input cannot disappear behind a final GET_CHANNEL continuation or a
closing session. A retained protocolFailed result prevents endpoint success and
B startup; valid notices still do not renew deadlines or trigger queue reads.
Private channel reply lengths are checked before their buffers are wiped even
during cleanup.

## Evaluation metadata and failure persistence

Before creating output or launching a peer, the runner requires contentBytes
as an integer in 0..165 and explicit expectedAExit/expectedBExit values matching
the fixed case semantics. H6 expects A=69/B=null, H7 A=130/B=0, and other basic
cases A=0/B=0. Boolean, missing and invalid values reject validation-only and
execution modes. Existing CLI and route limits still validate actual content.

An unexpected evaluator exception after peer settlement records its sanitized
type in evaluationFailure, retains all settled invocation and send facts, writes
results.json and STOPPED.json, and stops before another case. It does not retry,
erase the completed send, or replenish quota. See the
[protocol/evaluation software record](development.md#protocol-input-and-evaluation-accounting-fixes-on-november-11-2026).

## Content and invocation evidence binding

contentBytes must also equal the bytes selected by the actual initiating command:
A argv for A send/ping, or the selected B config for B send/ping. Exactly one
hex/text source is required; text counts UTF-8 bytes and hex must use even-length
ASCII digits without separators. Fixed zero-hop Direct H5 must contain 131 bytes;
editing both its metadata and content to a shorter value still rejects. The
validated count is captured before execution. Existing product route checks remain.

When summarizing retained evidence, H5 is checked against the captured A ping argv
and explicit Direct/empty path, including older records. Send totals are recomputed
from every invocation with the same finite accounting used by the runner. A cached
counter disagreement rejects output rather than publishing a lower number.
Unknown send facts keep null actual counts and their reserved upper bounds;
initialization retries and legacy read-only send fields do not invent sends.
The [offline regression record](development.md#content-invocation-ledger-and-interpreter-fixes-on-november-11-2026)
does not add a hardware run or spending authorization.

## Runner cancellation, completion exits and the empty boundary

During execution, the runner latches SIGINT instead of letting it escape peer
settlement or evidence writes. Once requested, new peer starts and initialization
retries are refused. Already-owned finite peers are still observed with their
original deadlines; an interrupted wait resumes on the same peer. The runner
persists invocation/send/cleanup facts and STOPPED before exiting 130, then
restores its previous signal handler. Pending cleanup retains its PID and unknown
send bounds. Cancellation adds no child signal, reconnect, resend, forced kill or
larger budget; it is not evidence of successful cleanup.

A selected case that fails acceptance yields final runner exit 69 even if all
peers exit/clean up normally. Independent remaining authorized cases may continue,
but a later PASS cannot erase that exit status. All selected cases passing yields
0. Expected peer exits such as H6's 69 and H7 A's 130 can still be passing case
evidence; the runner exit describes acceptance across the selected cases.

H4 must use zero content bytes, in addition to the existing fixed 131-byte H5
boundary. Both actual initiating arguments and contentBytes must agree with the
empty H4 boundary before execution; evaluation also rejects a nonzero H4 count.
Empty content still carries the diagnostic header and nonce. See the
[offline cancellation/exit record](development.md#runner-cancellation-exits-and-empty-content-fixes-on-november-11-2026).


### Business-storage isolation in new plans (1C.8)

Newly generated product datagram argv includes an absolute `--data-dir` per
case under the plan output's `cli-data/` directory. Use a current product CLI
that supports that option. The source-only B peer retains its separate
configuration/transport path. H0 info still opens no business storage. Validation
and evidence summarization accept retained older argv for historical records;
this does not authorize replaying or altering an old RF plan. Generation/tests
perform no device work, and no new RF result is claimed by 1C.8.
