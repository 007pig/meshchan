# Build 4 app USB compatibility and hardware continuation

This record ends at the first build 4 handoff. The subsequent
[authorized peer stop and manual Unicode path](phase-1d11-peer-stop-unicode.md)
preserves a separate failed B attempt, cumulative 2/8 send accounting and a
successful exact Chinese/emoji save/reopen. The original results below retain
their own time/source cut and 1/8 accounting.

Status: **Candidate prepared / acceptance incomplete.** The operator resumed
the real hardware matrix, then explicitly required integrating the finite USB
compatibility solution into the app before further testing. The current app is
`0.1.0-beta.1+4`; link/core/CLI remain `0.1.0-beta.1`. This record preserves the
successful bounded cases and the remaining prerequisites separately. There is
no current GUI exact-PONG, physical unplug/replug or complete Unicode user-path
acceptance claim.

## Source and implementation

The branch is `codex/phase-1d11-hardware-beta`, on actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16` plus manifested uncommitted work.
Owned raw evidence is
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-02/`.
The previous build 3 products, failures and diagnostic cohorts remain intact.

`UsbInitializationTransport` is app-local and uses public link APIs. The worker's
production finite-Check and recording factories both create this wrapper around
one SerialTransport. The initialization sequence is exactly QUERY, QUERY,
APP_START, QUERY, maximum four control frames / 34 framed bytes. The first step
waits for two complete DEVICE_INFO replies. The second waits for its extra
DEVICE_INFO, while the original session still requires SELF_INFO. APP_START is
sent once. Normal commands subsequently pass through once without further
probes. A mapped receive stream adds no second serial reader or inbox consumer.
Close settles a pending handshake and prevents a subsequent extra write.

The original session timers remain authoritative; there is no renewed request
deadline, startup delay, reconnect, RF retry or firmware change. Device Check
remains 5/15 seconds, startup zero; diagnostic requests use the reviewed
15/30-second budgets. The default library SerialTransport/session and product
CLI behavior are unchanged. Schema 1, summary format 1, CLI schemaVersion 1,
wire version, storage ownership, device gate, typed messages and Quit barriers
retain their contracts. Build metadata and direct-Dart assertions advance to 4,
including CI's explicit app-build check. Historical runs keep their old version.

## Fresh software and native checks

Toolchain: Python `/opt/homebrew/bin/python3` 3.15.2, Flutter 3.50.0 / bundled
Dart 3.14.0, Xcode 27.2, command-local Apple Clang; host macOS 27.2.1 arm64.
No SDK or third-party dependency upgrade occurred. The resolved graph has 99
unchanged package entries outside app build metadata. Root lock bytes are
unchanged. A separate comparison proves 67 CLI/core/link library/member-manifest
inputs equal the build 3 source manifest; it does not claim all product inputs
unchanged because the app changed.

| Scope | This build 4 result |
| --- | --- |
| Version, locked resolution, graph and lock | PASS; four members, five internal constraints, CLI constant and app fallback/build 4 |
| Dart format, complete workspace analysis | PASS; fatal infos enabled |
| New app compatibility regressions | 10 PASS: bounded held-reply completion, single reader, finite Check, normal command passthrough, missing SELF/extra replies, original deadline, cancellation, pending-write close and wrong-order refusal |
| Complete app suite | 262 PASS, concurrency 1 |
| Relevant process gates | runtime, Device, diagnostic, History PASS; direct process recordings require `+4` |
| Complete Python discovery | 135 PASS |
| Complete Debug / Release | PASS; separate external CompatDerived, arm64 destination |
| Native XCTest | 22 PASS; parallel testing disabled; disabled-owner environment verified in xctestrun |
| Strict signing / native inventory | Both complete apps PASS; no hand-edited bundle or re-signing workaround |
| Release runtime checks | 3 runtime runs and 2 Quit cases PASS |
| Finite SQLite probes | write/read PASS using probe-specific arguments |

Core/CLI/link full suites, generated/frozen schema checks, CLI bundles/smoke and
legacy dev.2 interoperability retain their previously documented source cuts;
they were not rerun merely for an app-local transport/build change. Current
core behavior was additionally exercised by real recording and independent
CLI reopening below. Draft/Profile process gates retain their build 3 cut;
the complete app suite and the relevant four process gates are fresh. There is
no remote CI result for this dirty build 4 source. PR #37 CI remains baseline
evidence only. Mobile probes remain inherited limited Step 10 evidence.

The initial peer-build gate was BLOCKED before execution because sandboxed
`/bin/ps` observation was unavailable; the observed execution environment passed.
A native-runtime label collided with an existing app-process runtime receipt;
the runner refused overwrite, and the distinct native-runtime continuation
passed. Two external audit-helper builds failed entry/package mapping checks;
the actual documented `--packages` / `--root-package=meshctl` build then passed.
All failed/blocked logs remain. None of these attempts touched devices or became
hardware passes.

The final whole-source privacy audit additionally found the current private
peer host in two preexisting example files and the dated 1D.8 record. Only those
endpoint strings were redacted: examples now use TEST-NET-1, and the dated record
uses a private-peer alias. Original bytes remain in owned external evidence;
historical versions, toolchains, results and counts were not changed. The first
audit failure and successful corrected audit are both retained. This was a
documentation-only correction with no product rebuild or hardware repetition.

## Bound artifacts

The complete tested Release and matching unchanged complete CLI are under
`/private/tmp/meshchan-1d11-20261116-01/delivery-beta1-build4/`.
`metadata/products.json` SHA-256 is
`212805a1e4190541eba11c1af98f04df22602718b605701ef9aeb1285d07068b`.
It inventories all app/CLI files, native assets, symlink targets and modes. Both
built apps report actual Apple short version `0.1.0.1`, bundle build `4`, Bundle
ID `org.meshchan.meshchan`; retained Flutter defines are `0.1.0-beta.1` and `4`.
The CLI reports `meshctl 0.1.0-beta.1`. Final inventories must remain equal to
these tested products; final documentation/source metadata does not rebuild them.

All GUI runs explicitly used the owned `fixtures/gui-a` directory. PID 53459 ran
the first build 4 GUI session; PID 60558 ran the second. Exact executable paths,
argv, source hashes, UTC times, outputs and reap receipts are retained. No
consumer inspected live app storage. Closed fixtures were copied only after
normal shutdown, OS exit and every independent consumer's close/reap.
Screenshots were rendered by Computer Use in the session transcript. The
available API did not persist them as local PNG files; no local screenshot path
is invented. Structured observations, raw process output and independent file
checks are retained in the owned evidence directory.

## Current device/peer prerequisites

A is the explicitly selected USB Companion; B is the selected TCP 5050 source
peer with a physically independent radio, as confirmed by the operator. The
historical Fabric forwarding scope remains; single-B-radio RF isolation is not
claimed. No other client was displaced. Shared inbox consumption was authorized,
and filtering occurs after consumption.

The fresh passive B session observed 95,003 ms ready with no host commands,
application sends or queue reads during observation, then cleaned up normally.
A following standard read-only audit failed A DEVICE_QUERY initialization at
15:23:59–15:24:14 UTC: requestTimeout, command 22 / expected 13, zero channel
queries, application sends and inbox reads, successful cleanup and OS exit.
That failure is preserved rather than attributed to the new app.

At 15:41:51 UTC the separately built source-only audit used the *same app
compatibility implementation* for A and completed. Only A slot 1 and B slot 3
were read. Their returned 16-byte keys matched in memory and were cleared, never
printed. Both endpoint sessions cleaned up/reaped. The audit's logical command
list excludes the wrapper's two extra initialization queries; those are explicitly
identified by its compatibility field. This is a prerequisite, not GUI evidence.
GUI Check later confirmed A's frequency 869618 kHz, bandwidth 62500 Hz, SF 8 and
coding-rate code 8, matching the retained selected-peer radio readback. Hidden
extended keys and independent protocol-oracle status are not established.

## Actual current GUI cases

| Case | Result and limited assertion |
| --- | --- |
| U00 | PARTIAL: explicit offline saves and no automatic device access observed on both launches; exact Chinese/emoji GUI input remains unestablished |
| U01 | PASS on the third invocation; first transport failure and second requestTimeout remain FAIL attempts, each with succeeded session/observer cleanup and OS port release |
| U02 | BLOCKED before A Start: finite B responder reached 128 entries and terminated before a live A-start window was established; no current GUI PONG |
| U03 / U04 | NOT_RUN: no B PING/A exact PONG, physical unplug/replug or recovery Check; the required live-session prerequisites were not established |
| U05 | PASS: one actual GUI PING, local write/OK/device acceptance true, then responseTimeout / waiting; no matching PONG and no successful RTT |
| U06 | PASS: actual GUI Cancel; post-result canceled / receiving, null listen stop reason, zero responses, cleanup and committed final save, independently reopened |
| U07 | PASS: same nonterminal finite run retained through dirty Continue editing/save; actual native Quit, normal barriers/OS exit and independent canceled / receiving result |
| U08 | PASS for bounded History/filter/new-file export/normal Quit/independent reopen subset; full RF/Unicode user path remains incomplete |

All operations used explicit A selection, slots A 1/1 and B 3/3, Direct empty
routes, local/peer IDs 3507552257 / 3507552258 in opposite roles and the reviewed
non-sensitive 18-byte PING content. No port was selected automatically. Existing
5/15 Check and 15/30 diagnostic budgets were not widened. No RF failure was
replayed. The application-send ceiling remains 8; actual use is **1**, with **7
remaining**. This counts application attempts, not physical airtime, firmware
retries or Fabric forwarding.

### U01 attempts and continuing USB limitation

In PID 53459 the first Check failed transport / initializing, command 22 /
expected 13. Its private native cause is not exposed in the public GUI, so it
is not asserted to be the same cause as the second Check. The second Check
failed requestTimeout at that command. Both returned Not connected with
succeeded session/observer cleanup; OS lsof showed no port owner before retry.
The third Check returned historical information observed at
15:47:31.714277 UTC: Heltec V4.3 OLED, v1.18.0-81dbae5, protocol 14, target 3,
then closed cleanly. This establishes current app initialization/close, not a
reliability fix. No successful snapshot was treated as a later live session.

### U02 receiver-window prerequisite

The one new B responder used request/init/task 15/30/90 seconds, 60-second listen,
maxEntries 128 and maxResponses 1, with no startup delay. Its first existing
GET_MSG write completed at 15:49:49.768964 UTC. The process then reached
entryLimit: 128 published/processed entries, 128 completed reads, zero response
attempts. The readiness check found it already terminal, so no A Start occurred.
Cleanup succeeded and PID 55776 exited/reaped. No second B responder was silently
started and no inbox-clear command or larger limit was used. This cohort consumed
128 B entries / 128 reads; earlier cohorts retain their separate 42/47 counts.
The cumulative B consumption is 170 entries / 175 reads, with zero B replies.

### U06 Cancel

Run `5207506d421cfee92d8b2a94d06ebf25`, host attempt 1 / lease 5, registered at
15:52:49.718215 UTC. Navigation to Device showed the diagnostic retaining the
device gate with Check/Refresh unavailable. Back on the same nonterminal run,
Cancel was invoked after the 15:53:17.108 UTC observation. The terminal result
was canceled / receiving, session cancellation at ready, null listenStopReason,
16 processed entries / 17 completed reads, zero response attempts/confirmations.
Core cleanup succeeded, core-managed subscriptions were notRequired, app
observer cleanup succeeded, adapter settled and resources were confirmed
released. Registration/logical/cleanup saves committed; five save observations
included a final committed cleanup save. Port-owner absence was independently
confirmed before further device work.

### U07 dirty Continue editing and active native Quit

Run `4ca56443614e119dd751fe25164fecd8`, host attempt 2 / lease 6, registered at
15:56:51.841710 UTC. The separate finite Responder used 180-second listen,
240-second task, maxResponses 1, maxEntries 128, with B closed. During the run,
an existing saved test draft was made dirty. Native Quit at 15:57:31.856 UTC
opened the dirty decision. Continue editing preserved the dirty draft; saving
before navigation committed revision 2. The same run/attempt was freshly observed
without a logical terminal before final native Quit at 15:58:34.086 UTC.

The app output confirmed resourcesReleased/workerExited true, owner released,
zero pending requests/receive ports, no maintenance failure; PID 53459 exited 0,
was reaped and was absent at the OS, with no port owner. Independent current CLI
reopen found canceled / receiving, null listenStopReason, one processed entry /
three reads, zero responses, aggregate cleanup succeeded, settled, no recovery.
App observer state was not invented as a persisted History field; the normal
runtime shutdown barrier and the separately stored core cleanup are distinct
evidence. The earlier U06 run reopened with the same expected facts and `+4`.

### U05 expected failure

PID 60558 was launched with the same complete app/owned directory. Startup again
showed no listed/opened ports or selected device until explicit Refresh/select.
After the actual 18-byte Preview and confirmation that B responders were closed,
run `3fcfb032bb5f3580a20930cdbf9ff1e2` registered at 16:05:49.925813 UTC.
The send was attempted/dispatched, local write and matching OK completed,
deviceAcceptanceConfirmed true, pendingAtTermination false. It ended in
responseTimeout / waiting, with no matching PONG, exact-content or round-trip
success and null applicationRttUs. It processed zero entries / one read.
Core/app observer cleanup and final saves succeeded. Independent reopen confirmed
the same settled `+4` record, no recovery and clean storage close. The task failure
is the expected test PASS; it is not RF round-trip evidence.

### U08 History, safe export and persistence

The actual GUI operation filter produced two Responder rows. Reset selected all
five rows, page size 50, zero recovered. The native Save panel published exactly
one new file under the owned exports directory. Its GUI job reported summary
generated, writer admitted and file published true, five rows, moreAvailable
false. File SHA-256 is
`131d803045243c1aa42e7bd6fb195a9a7fa3d64d06014795865a2abf7b129c27`.
After normal Quit and PID absence, the independent public-core CLI export's
entire five-run projection equaled the GUI file's runs. Their independent export
timestamps were not compared as if they shared a snapshot. The file uses
diagnosticSummaryFormatVersion 1; CLI metadata separately uses schemaVersion 1
and nextCursor null. It contains no test content, port, private endpoint, key or
raw exception. This is a redacted page, not an anonymous/restorable backup.

The ASCII test draft retained its exact title including two trailing spaces,
one line feed, 83 UTF-8 body bytes and revision 2 after save/Quit/reopen.
Settings retained defaultProfileId null/history limit 1000; all three reviewed
profiles remained. The earlier build 3 run's complete persisted projection was
unchanged. No live database was copied or queried through a second owner.

Host Computer Use initially had stale AX text and a coordinate
noWindowsAvailable error in the second app session. Native Window → Move to
Built-in Retina Display restored current observations, as in the earlier cut.
No alternative UI driver/system security change was used. Unicode paste did not
establish controller text; a synthetic Unicode typing attempt inserted only
ASCII. Those attempts are not Chinese/emoji or real Pinyin passes. No input
source was installed/changed, and no newer Dvorak, live preedit, conflict Reload,
Full Screen/focus/accessibility or complete Cut/Copy matrix is claimed.

## Remaining bounded continuation

All app/peer/inspector consumers are closed. U02 needs a fresh live receiver
window; the completed 128-entry session is not a standing responder. A concrete
**unexecuted** proposal retains all timeouts/routes/radio settings and the same
app, allows only two further B sessions (one responder, one PING), and raises
only B's finite maxEntries from 128 to 512. At most 1024 B entries could be
consumed across those sessions; no clear/reset operation is proposed. The next
U02 and U03/U04 reserve at most five additional application attempts, cumulative
maximum six including U05, within the existing ceiling eight. No RF replay or
automatic additional B session is admitted. This change requires an operator
decision because it exceeds the already executed per-case B receive allowance.

Physical unplug remains conditional on this trial's exact B PONG, actual B
cleanup and the same still-active A attempt. No unplug instruction has been
given and no physical action occurred in this continuation. Chinese/emoji input
needs reliable controller input in the owned GUI; no programmatic seed may be
relabeled as that test. Future artifacts must retain these exact app/CLI hashes
or repeat the affected gates. 1E still owns Developer ID, notarization, installer
and public distribution; no tag, GitHub Release, binary upload or push occurred.
