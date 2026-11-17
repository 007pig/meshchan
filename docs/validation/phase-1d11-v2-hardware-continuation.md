# Reviewed v2 IDs: real GUI continuation and peer failure

Status: **Candidate prepared / acceptance incomplete; RF stopped after U03
peer failure.** The exact complete `0.1.0-beta.1+4` Release, matching CLI and
source-only peer binary are unchanged. U02's GUI target was not started because
its finite admission window was missed. U03 did execute: A responded once with
local acceptance, but B did not establish an exact PONG. No physical unplug,
replug or recovery Check occurred.

## Authorization, inputs and isolation

The operator explicitly resumed U02 and U03 using the reviewed v2 configs and
fresh per-case IDs, the same selected USB A and independent TCP peer B, and all
original finite parameters. The cumulative application-send ceiling was removed;
actual attempts are still counted. The two B sessions each retain maxEntries
512, for at most 1024 consumed entries. Abnormal RF/write/owner/cleanup results
require stopping; no B retry, fallback, firmware or radio change is authorized
implicitly. Physical action requires a new prompt after the exact-PONG and
same-active-A prerequisites have actually been established.

Owned evidence is
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-04/`.
The complete product manifest SHA-256 remains
`212805a1e4190541eba11c1af98f04df22602718b605701ef9aeb1285d07068b`.
The branch remains `codex/phase-1d11-hardware-beta` on actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, with manifested uncommitted work.
Python is `/opt/homebrew/bin/python3` 3.15.2. No product code/dependency/build
changed during this continuation; prior software/native results retain their
own source cuts.

While the app was closed, the current public CLI read and updated the two owned
Profiles. Exact comparison proved that only endpoint labels changed; all other
parameters were preserved. Each CLI confirmed storage close and natural process
exit/reap before the next consumer. The corrected B PING uses supported
`--text=Meshchan D11 beta1`, the same 18 UTF-8 bytes. Both actual B config files
were byte-identical to their reviewed counterparts and matched the private
selected endpoint. TCP did not transmit the referenced JWT; no new login,
Companion preflight, inbox clear or configuration change was performed.

| Case | A role / local / peer | B role / local / peer |
| --- | --- | --- |
| U02 | GUI PING / 1251977030 / 2195432628 | Responder / 2195432628 / 1251977030 |
| U03/U04 | GUI Responder / 2807791422 / 695414388 | PING / 695414388 / 2807791422 |

A uses slots 1/1 and B slots 3/3, with independently specified Direct empty
paths. The retained selected-slot key/radio audit is inherited from its own
build 4 source cut; this continuation did not query keys or claim a fresh audit.
Labels isolate cases and do not authenticate devices or prevent unrelated inbox
consumption. The source-only peer reuses the project protocol implementation;
it remains outside the product and is not an independent protocol oracle.

## Current GUI startup and finite Check

The exact Release started as PID 98297 at 17:35:02.592207 UTC with explicit
owned `fixtures/gui-a`. Computer Use initially returned cgWindowNotFound;
one Finder-selection call then took approximately 3655 seconds to return.
No B session or application send ran during that tool stall. OS observation
confirmed the one expected app PID/argv. Normal Finder activation and native
Window → Move to Built-in Retina Display made the already-running window
controllable; no alternate input driver or security setting was used.

Before explicit Refresh the app showed Not connected, selected None, and no
ports listed/opened. The GUI enumerated metadata, explicitly selected USB A
(VID 12346 / PID 4097), and ran one finite Check with request/init/startup
5 seconds / 15 seconds / 0 milliseconds. At 18:40:43.088397 UTC it reported
Heltec V4.3 OLED, firmware v1.18.0-81dbae5, protocol 14. Session and app observer
cleanup succeeded, Not connected was restored, and OS inspection found no USB
owner. This new success does not erase earlier initialization failures or prove
reliability repaired. Other listed ports were not opened.

## U02: finite B completion, GUI admission blocked

Actual GUI Preview showed the new U02 IDs, 18-byte synthetic content,
request/init/task/response 15/30/60/15 seconds, startup zero, maxEntries 128,
slots 1/1 and Direct empty path. B PID 25666 started at 18:44:11.407311 UTC;
its first task-owned GET_MSG write witness was 18:44:11.487418 UTC. It used
request/init/task 15/30/90 seconds, listen 60 seconds, maxResponses 1 and
maxEntries 512. The witness means a completed write, not an empty inbox or
remote reception proof.

The first launch-tool response exposed PID only; a second tool round trip
obtained the write witness. At the guarded GUI action, 25.158 seconds had elapsed
since B launch. Conservatively only 34.842 seconds remained, below the required
49 seconds (45 seconds of A init/response budgets plus four seconds of action
headroom). The guard declined Start. There is no A U02 run or application send.
No timeout/guard was relaxed and no replacement B session was started.

B naturally finished at 18:45:11.494504 UTC: exit 0, completed/settling,
durationElapsed, zero response attempts/local confirmations, 48 entries and
49 completed reads, successful cleanup and natural process reap/OS absence.
U02 is **BLOCKED: GUI admission window missed**, not a PING or USB initialization
failure and not a round-trip pass. There was no RF/owner/cleanup failure in this
invocation. After its proven release, the separately approved independent U03
proceeded once; U02 was not silently retried. Future orchestration must avoid
the additional model/tool round trip within the same finite window, and still
decline a late Start if service latency makes admission impossible.

## U03: real accepted A response, no exact B PONG

GUI Preview selected the distinct `D11 Unplug Responder` Profile, ID
`617ac1fcebec1cd39aaaeffc3c8f780e`, with the U03 pair above. Original A parameters
were request/init/task 15/30/240 seconds, startup zero, listen 180 seconds,
maxResponses 2, maxEntries 128, slots 1/1 and Direct empty path. The GUI Start
action was bracketed by 18:47:40.915 / 18:47:40.953 UTC. Registration committed
run `facf2a6dcae2dfafbec4b802d0fde4f9` at 18:47:40.952940 UTC, app version
`0.1.0-beta.1+4`, host attempt 1 / gate lease 3. GUI in-progress text established
only a committed nonterminal recording, not live hardware readiness.

The one B PING, PID 26964, ran from 18:47:53.370788 to 18:48:08.444972 UTC,
using the corrected v2 config and original 15/30/90-second budgets. It initialized
but exited 69:

| B fact | Actual result |
| --- | --- |
| Task reason / stage | responseTimeout / sending |
| Send | attempted, dispatched and localWriteCompleted true |
| Acceptance / pending | localOkObserved false, deviceAcceptanceConfirmed false, pendingAtTermination true |
| Exact round trip | matchingPongObserved, exactContentValidated and roundTripSucceeded false; successful RTT null |
| Session failure projection | canceled / ready, command 62 (0x3E), expected OK opcode 0 |
| Reception | 1 entry / 1 completed read; sessionClosed |
| Cleanup / process | succeeded; natural exit/reap and OS PID absence |

The primary reason is responseTimeout while sending; the session cancellation
was captured as the task closed its still-pending command. Do not rewrite this
as a requestTimeout or the expected U05 response timeout after local acceptance.
The attempted PING counts even though OK was absent. The real A result below
also prevents interpreting B's missing OK as proof that nothing reached A.

The RF failure stopped further B sessions and prevented the physical-action
prompt. Fresh GUI observation showed the same A run still nonterminal. Normal
GUI Cancel began at 18:48:36.591 UTC; the logical result committed at
18:48:36.632081 UTC:

| A fact | Actual result |
| --- | --- |
| Reason / stage | canceled / settling; no listen stop reason |
| Response attempts / local confirmations | 1 / 1 |
| Last PONG send | attempted, dispatched, write completed, matching local OK and device acceptance all true; pending false |
| Reception | 17 published/processed entries, 18 completed reads |
| Cleanup | core succeeded, core subscriptions notRequired, app observer succeeded, resources confirmed released |
| Saves | registration, logical and final cleanup committed; finalCleanup true |
| Persisted state | settled, no recovery timestamp/reason |

The accepted local response is real evidence of A receiving and replying to an
eligible fresh-label PING. Its nonce/content were not retained for independent
correlation. B did not obtain the matching exact PONG, so **U03 is FAIL** for
the intended round-trip assertion. A's settling stage after one response is
consistent with continued reception and must not be relabeled receiving. This
cleanup Cancel is not a new zero-response U06 pass. U04 is **NOT_RUN** because
its exact-PONG prerequisite was never established; no unplug, replug or recovery
Check was requested. No RF replay or firmware/endpoint/timer change followed.

## History, new-file export and normal close

The same app's History read the new settled run, then explicitly applied the
all-operation first page: six rows, zero recovered. A real NSSavePanel exported
one page to new owned `exports/meshchan-beta4-summary-run04.json`; the job settled
with six generated/exported rows, moreAvailable false, writer admitted and file
published true. A filename insertion did not initially replace the whole field;
the native field was corrected and visibly verified before Save. No existing
file or Replace confirmation was used.

Native Quit at 18:52:42.093 / 18:52:42.435 UTC was after task settlement, not an
active-hardware Quit pass. The process naturally exited/reaped at
18:52:42.501678 UTC. Output reported resourcesReleased/workerExited true, owner
released, no error, zero pending requests/receive ports/maintenance failures.
OS verified PID absence and no USB owner before collection or independent open.
Closed fixtures were copied only after these barriers.

Sequential current CLI/public-core consumers independently verified:

- The exact new run, version, accepted response, canceled/settling result,
  successful persisted cleanup and no recovery; no U02 A run exists.
- All five older History projections unchanged and six total records.
- Both new-ID Profiles and all their finite parameters unchanged after GUI use.
- The previously composed Draft still exactly `中文 🚀 beta4`, body
  `Meshchan 中文验收\nemoji 🚀🙂`, one LF, 36 UTF-8 body bytes, revision 1.
- The GUI file is summary format 1 and its six `runs` equal independent core
  export projections. Separate export timestamps were not compared. No content,
  endpoint test labels, nonces, keys, device path, private endpoint or raw
  exception fields leaked. The intended run IDs remain in the safe summary.

The GUI export SHA-256 is
`ee26030e8c6edea0c2be74891e62dbb1579179c33ef44d2e5937d9da1f57e0e0`.
CLI envelope schemaVersion 1 remains separate from summary format 1. Every
independent consumer confirmed storage close and natural exit/reap/OS absence.
No new Pinyin composition or fresh GUI reopen after this run is claimed; the
earlier exact-input/new-GUI-reopen evidence retains its source cut.

## Accounting, disposition and handoff

This continuation used exactly **2/2 B sessions**, **49/1024 consumed entries**
and 50 completed reads. B U02 sent zero; U03 attempted one B PING and one A PONG,
both counted. Cumulative application attempts are **four, with no cumulative
ceiling**. Across retained 1D.11 B cohorts, consumption is 281 entries / 287 reads.
These are application attempts and consumption counts, not RF airtime, firmware
retransmissions, Fabric forwarding or all ambient traffic.

Fresh IDs have not been shown to repair missing OK: U02 did not send, while U03
again lacked B acceptance. They remain useful case isolation, not a repair claim.
The blocking observation is now the B command-acknowledgment/round-trip path;
the physical fault cycle cannot be accepted until its prerequisite succeeds.
Any further RF attempt requires a separately reviewed resumption after this stop.
Do not change the app to ignore local OK, issue parallel inbox reads, resend,
increase budgets or mark the real remote success from A local acceptance.

Current app/CLI/peer inventories and product inputs are unchanged. Updated
delivery/source/evidence manifests preserve compilation and earlier hardware
cuts. No new full software/native run, CI pass, product fix, commit, push, PR,
tag, installer, notarization or public release is claimed. All consumers are
closed; the candidate and 1D.11 remain incomplete. The earlier U05/U06/U07 passes,
USB intermittency, limited mobile evidence, excluded BLE/Intel runtime and
remaining GUI/IME variants retain their documented limits.
