# Authorized peer continuation, RF stop and manual Unicode path

Status: **Candidate prepared / acceptance incomplete; RF stopped after a peer
failure.** The exact same complete `0.1.0-beta.1+4` Release and CLI inventories
remain in use. No product source, dependency, firmware, timeout or radio
configuration changed. This continuation adds a failed B prerequisite and a
successful real Chinese/emoji save/reopen path. It adds no GUI exact-PONG or
physical unplug/replug pass.

The later offline review below validates a corrected fresh-ID proposal, records
the operator's removal of the cumulative application-send ceiling, and adds two
local TCP regressions. It performs no new USB, peer, RF or shared-inbox operation.

## Authorization and source binding

The operator explicitly approved one replacement U02 B Responder and the
original U03 B PING, at most two B sessions, each maxEntries 512, total at most
1024 consumed entries. The 15/30/90-second B request/init/task budgets,
60-second Responder listen, maxResponses 1, 15-second PING response budget,
selected USB A / independent TCP peer B, routes and all other parameters were
unchanged. The overall application-send ceiling remained eight, with one already
used by U05. The operator also offered manual Chinese/emoji input and physical
unplug assistance, only when prompted. Abnormal results require stopping.

Owned evidence is
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-03/`.
The build 4 complete product inventory SHA-256 remains
`212805a1e4190541eba11c1af98f04df22602718b605701ef9aeb1285d07068b`.
Both product bundles and the source-only peer bundle were verified unchanged
before launch. Python was `/opt/homebrew/bin/python3` 3.15.2. The branch remains
`codex/phase-1d11-hardware-beta` on actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, with manifested uncommitted work.

The existing credential reference was refreshed without printing the password
or token. Clipboard formats were held in memory and restored only while the
helper still owned the change count. No extra Companion info/passive session
was started; the prior selected-slot audit/passive evidence retains its source
cut. A private dispatch guard enforces the two approved B command shapes and
the 512/15/30/90 bounds before reserving a session. It is evidence assistance,
not a new product transport or hardware framework.

## U02 peer prerequisite failure and stop

The complete app ran as PID 75172 with explicit owned `fixtures/gui-a`. Startup
was offline, then the GUI explicitly refreshed and selected USB A. Actual PING
Preview matched the existing reviewed profile: 18-byte synthetic content,
A send/receive slots 1/1, Direct empty path, local/peer IDs 3507552257 /
3507552258, request/init/task/response 15/30/60/15 seconds, startup zero and
maxEntries 128. No A Start was executed.

The single B Responder, PID 76047, started at 16:44:15.524017 UTC. Its existing
first GET_MSG write completed at 16:44:15.589320 UTC. The admission check did not
admit A Start: its separate scheduling-headroom guard required 49 seconds
remaining, comprising the original 45-second A init/response budgets plus four
seconds of action headroom. That guard is not a product timeout or proof that
the actual A session initialized. No assertion was relaxed to start late.

B had encountered a valid matching shared-inbox PING and attempted a PONG before any
A task started. It ended at 16:44:30.627882 UTC with exit 69:

| Fact | Actual result |
| --- | --- |
| Task reason / stage | sendFailed / settling |
| Session failure | requestTimeout / ready, command 62 (0x3E), expected OK opcode 0 |
| Local send | attempted true, dispatched true, localWriteCompleted true |
| Acceptance | matching local OK false, deviceAcceptanceConfirmed false |
| Pending at termination | false |
| Response attempts / local confirmations | 1 / 0 |
| Listen stop reason | responseLimit |
| Inbox | 62 published/processed entries, 62 completed reads |
| Cleanup | succeeded; process naturally exited/reaped and OS PID absent |

The attempted PONG counts as **one application-send attempt**, irrespective of
missing acceptance. It is not zero RF, confirmed delivery or a remote PONG.
The matching PING's origin is not established: no request nonce/content was
retained for comparison. A prior queued request using the same labels is a
plausible explanation, not a proved correlation with U05. The missing OK is
separately unresolved; neither source-code inspection nor a new successful
initialization explains it.

The failure triggered the authorized stop. There was no second B session,
GUI A Start, RF replay, U03/U04, physical unplug/replug, recovery Check, timeout
increase, inbox clear or device reconfiguration. B was not killed. OS observation
confirmed it had exited and the selected USB port had no owner. Application
attempts are now **2/8 cumulative**, with a numerical remainder of six; that
remainder does not bypass the stop rule. This continuation used **1/2 B
sessions**, **62/1024 entries**, and 62 reads. Across the prior/current 1D.11
cohorts, B consumption is 232 entries / 237 reads. Earlier cohorts retain their
original accounting.

## Practical isolation correction prepared without RF

The existing finite Responder accepts any valid PING addressed to its configured
local label from its configured peer label and receive slot. It does not require
an active remote GUI run, and a newly created responder's cache does not prove
that its shared inbox contains only new requests. The previous plan reused the
same labels across U02, U05 and U03; consequently the planned no-responder U05
could leave an eligible request for a later responder. This is a planning risk,
not a new packet-correlation or authentication guarantee.

The existing **17-test** public PING/PONG codec suite passed without hardware.
A separate bounded pure-codec check also passed: a synthetic old-label PING is
accepted with those same labels, ignored by a fresh label pair, and a new-label
PING is accepted by its matching pair. The check opens no transport and proves
no actual hardware packet's source, RF delivery or repair of the missing OK.

An unexecuted proposal prepares independent, fresh nonzero IDs for U02 and U03,
with opposite A/B roles. Both pairs differ from all previously used labels and
from each other. Private B config files and explicit A override instructions
are ready, retaining all other parameters. No live profile or packet was changed.
This addresses accidental cross-case eligibility while preserving secure PING
nonce matching; IDs remain labels, not authentication. RF stays stopped pending
reviewed resumption. The unused second B-session allowance was not repurposed
for diagnosis or another attempt.

## Actual manual Pinyin, Chinese/emoji and persistence

After RF stopped, the operator assisted only with offline input in the verified
app/data directory. Computer Use opened a fresh Draft and focused Title. The
operator typed Pinyin `zhongwen`, reported a visible candidate and stopped
before commit. The app screenshot/AX showed focused, underlined `zhong wen`
preedit. The floating candidate popup was not included in the app-only image;
its visibility is operator-reported, not claimed as screenshot evidence.

The operator naturally committed with Space/candidate selection and entered
the rest of the synthetic text. The actual screen showed:

```text
Title: 中文 🚀 beta4
Body:
Meshchan 中文验收
emoji 🚀🙂
```

This body differs from the longer suggested line labels; the observed 36-byte
two-line text was fixed as the expected fixture **before Save**. Computer Use
then explicitly clicked Save. The list showed the correct title and revision 1.
The title field's AX text had briefly mirrored the body, so AX assignment/text
alone was not treated as controller proof; the rendered title, actual save and
independent persisted value were checked separately.

The app quit normally. Runtime reported resourcesReleased/workerExited true,
owner released, zero pending requests/receive ports; exit 0/reap and OS PID
absence were verified before any independent consumer. Current CLI then opened
the same owned directory and read Draft
`dcd28063dce1a2b7c8f6f00585bc7224`: exact title, exact Chinese/emoji body, one
line feed, 36 UTF-8 bytes, revision 1. The CLI closed storage and exited normally.
All five prior History projections were unchanged, with no A diagnostic run
created by this continuation. A closed fixture was collected only after those
consumers exited.

A separate app launch, PID 81431, visibly reopened the saved title and full body,
revision 1 / 36 bytes. The known stale/empty AX observation was resolved through
the native Window → Move to Built-in Retina Display command, without another
UI driver or system security change. Device then showed Not connected, selected
None, and no ports listed/opened, confirming no automatic device access. Final
native Quit again completed all normal barriers and OS exit. Input mode was
operator-managed; the agent did not install/switch an input source or claim a
source ID as proof. No complete IME, marked-text Save/Quit deferral, Dvorak,
conflict Reload, native filename preedit or full Cut/Copy matrix is inferred.

## Current handoff

| Item | Current state |
| --- | --- |
| Exact tested app/CLI | Unchanged complete build 4 products; earlier fresh software/native gates retain their cut |
| U00 Chinese/emoji Draft subpath | PASS actual input, explicit Save, independent exact read and new GUI reopen |
| U01 / U05 / U06 / U07 | Earlier build 4 limited passes retained with their original failed attempts and source evidence |
| U02 | A target NOT_RUN in this continuation; peer prerequisite FAIL and RF stop |
| U03 / U04 | NOT_RUN; no current exact PONG, no physical action or recovery Check |
| U08 | Earlier five-row safe export/reopen retained; five History projections unchanged; new Draft persistence additionally verified |
| Consumers | All owned app/peer/inspectors closed; selected USB owner absent |
| Candidate | Prepared / acceptance incomplete; not a completed 1D.11 or accepted local beta |

No product change or rebuild was made after these hardware results. Only
evidence, redacted documentation and unexecuted fixture proposals changed. The
next RF decision must account for the failed peer send, unused-but-stopped
allowance and fresh per-case labels; it must not relabel this failed invocation
as a successful U02 or silently replay it. 1E distribution work, limited inherited
mobile evidence, BLE exclusion, Intel runtime and remaining GUI variants keep
their previous boundaries.

## Offline peer failure and fresh-ID review

The operator requested review of the failure and proposed IDs, then explicitly
removed the cumulative application-send ceiling. The earlier 2/8 and numerical
remainder of six above describe the failed invocation's original authorization.
There is now no cumulative application-send ceiling. Actual attempts remain
two, with zero added by this review. Finite per-task parameters, explicit device
selection, session/inbox constraints and stop-on-uncertain-write/owner/cleanup
rules remain. Removing the send ceiling does not itself execute a retry, erase
the peer failure or establish a new hardware pass.

### Findings and practical correction

1. **The two failure questions remain separate.** B received an eligible PING
   before the GUI started A and attempted one PONG. Reusing labels across cases
   allows a request left in the shared inbox to qualify later. A prior U05
   request is a plausible source, but no saved nonce/content identifies this
   actual request. Independently, the PONG command's TCP flush completed without
   a matching Companion OK within the original 15-second request budget. Neither
   a new label nor an initialization handshake is a demonstrated repair for
   that missing OK. B had already initialized; this is not the earlier A USB
   initialization failure.
2. **Response limit is not premature transport close.** The Responder stops
   further reception at its response-attempt limit, then waits for the pending
   send. The command FIFO may withdraw the reception owner's undispatched read;
   it does not withdraw the PONG command. The peer runner awaits task cleanup
   before idempotent session close. The new TCP tests exercise this boundary
   through the actual peer runner, observation adapter, session and transport.
   They support this bounded local behavior, not a claim that the deployed
   virtual Companion returned OK or that all possible transport faults are
   excluded.
3. **The original U03 proposal was not runnable.** Both the retained original
   B PING config and the first fresh-ID proposal used unsupported `--content`.
   Actual `OpenHopPeerConfig` validation rejected it before any credential read
   or connection. The corrected file is
   `hardware/run-03/peer-review-01/fresh-u03-b-proposed-v2.json`, using
   `--text=Meshchan D11 beta1`: the same exact 18 UTF-8 bytes. The invalid files
   and failed gate are preserved. This was an unexecuted plan error and did not
   cause the real B Responder failure. No new product argument alias was added.

The corrected proposed pairing is:

| Case | A operation / local / peer | B operation / local / peer |
| --- | --- | --- |
| U02 | GUI PING / 1251977030 / 2195432628 | Responder / 2195432628 / 1251977030 |
| U03/U04 | GUI Responder / 2807791422 / 695414388 | PING / 695414388 / 2807791422 |

All four labels are distinct nonzero uint32 values, distinct from both old
labels. The existing parser and core profile contract accept the full uint32
range, including these values above the signed 32-bit boundary. B remains TCP
5050, slots 3/3, Direct empty path, request/init/task 15/30/90 seconds, zero
startup delay and maxEntries 512. B Responder remains listen 60 seconds /
maxResponses 1; B PING retains its 15-second response budget. A's explicit
overrides are still proposed, not applied to live storage. Before any future
Start, the actual GUI Preview must show the corresponding IDs and original
effective parameters.

The saved `D11 Unplug Responder` profile is distinct from `D11 Cancel Quit`:
the retained creation receipt specifies maxResponses 2 for the former and 1
for the latter, with different profile IDs; the later U08 listing retains those
IDs and creation timestamps. U03 must use the former, with its original
180-second listen / 240-second task, slots 1/1, maxEntries 128 and zero startup
delay. Using the Cancel/Quit profile would close after the first response and
fail to establish U04's active window. The proposal's A profile ID correctly
selects the former, but current Preview still needs to be checked at execution.

Labels isolate cases; they do not authenticate a sender, clear an inbox or stop
unrelated entries consuming the limit. PONG success still requires this run's
nonce, request ID, opposite endpoint labels and exact content, in addition to
local acceptance and cleanup. The independent U03 pair prevents an eligible U02
request from triggering U03. A matching PING received before its planned sender
starts remains an abnormal stop, including when fresh labels are used.

From this stop point, U02 plus U03 would require two future B sessions, each
maxEntries 512, hence at most 1024 consumed entries. The old unused second
session was not used by this review. Reads and consumed entries remain separate
counts. Expected additional sends are four; the existing finite task limits
allow at most five across these two cases. These are planning counts, not a
reinstated cumulative ceiling. No unlimited responder, automatic resend or
retry loop is proposed.

The original U02 scheduling guard also remains: A must be ready at Preview
before launching B, and admission needs a still-running matching B session,
the first task-owned GET_MSG write witness and at least 49 seconds remaining
(45 seconds of A init/response budgets plus four seconds of action headroom).
With a 60-second listen window, only 11 seconds are available before that guard
becomes unsatisfied. Prepare all UI/config checks first and minimize the
launch/witness/GUI round trips; if admission is missed, record it and allow the
finite B task to settle. Do not start late, extend timeouts, clear the inbox or
silently launch a replacement. This scheduling constraint does not explain the
missing OK in the earlier B command.

For that future guard, conservatively count the 60 seconds from the owned B
process launch, which precedes actual listening, rather than resetting the
window at first-write observation. The write witness is not a precise listen
start timestamp and may arrive later. Keep both the witness and independent
process-liveness checks; neither alone proves a remaining response window.

### Fresh offline verification and evidence

Owned review files are under
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-03/peer-review-01/`.
Python remains `/opt/homebrew/bin/python3` 3.15.2; Dart remains the Flutter
3.50.0 bundled 3.14.0. Every gate uses the existing sequential runner and process
observation. No actual endpoint credentials are read by the new tests or plan
validator.

| Gate | Result and scope |
| --- | --- |
| `D11-hw03-review-tcp-peer-correct-projection` | PASS, 31 focused TCP/peer/observer tests, including two new local TCP cases |
| Delayed OK at response limit | PASS: 61 old-label synthetic entries ignored, fresh matching entry 62 causes exactly one byte-exact PONG; TCP stays open for the delayed OK body; one local confirmation and successful cleanup/EOF |
| Missing OK at response limit | PASS expected failure: same bounded synthetic inbox shape, original 15-second request timeout, sendFailed/settling, responseLimit, 1/0 attempts/confirmations, 62/62 reads, preserved write facts and successful cleanup/EOF |
| `D11-hw03-review-proposal-v2-validation` | PASS pure constructors, old invalid option rejected, new option/content valid, both ID directions and unchanged settings checked |
| `D11-hw03-review-test-analysis` / `D11-hw03-review-final-format` | PASS fatal-info analysis and formatting |

The synthetic 62-entry shape is a regression model, not a replay or attribution
of the 62 real packets. TCP writes the OK header and content separately; no
claim is made about kernel packet boundaries. The earlier 17-test codec pass
retains its original source cut. No full product suite or native rebuild was
needed for test/document/proposal changes.

Two review failures remain in the ledger: the initial new test incorrectly
read the PING projection key `send` instead of the Responder's `lastSend`
(`D11-hw03-review-tcp-peer-regressions`, 29 passes / 2 test assertion errors),
then the original proposal failed actual option validation
(`D11-hw03-review-proposal-validation`). The test correction changed only the
new assertions; the plan correction changed only the unsupported option's
spelling while preserving content. Neither failure is hidden as a product fix.

Review disposition: **the corrected per-case ID proposal is valid for a future
finite attempt; the real missing-OK failure remains unresolved.** Product code,
the complete build 4 app/CLI and the source-only peer binary were not modified
or rebuilt. The new review source snapshot is separate from the compilation
and hardware cuts. This review leaves RF stopped, all consumers closed, U02's
GUI target and U03/U04 unexecuted, and the candidate acceptance incomplete.
