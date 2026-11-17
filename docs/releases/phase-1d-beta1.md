# Phase 1D local beta 1 candidate

**Local beta accepted with documented limits.** Version `0.1.0-beta.1`, macOS
app build **5**. The [validation record](../validation/phase-1d11-hardware-beta.md)
identifies current fresh gates, retained failures, exact source/toolchain facts
and the [completed finite matrix](../validation/phase-1d11-rf-matrix-completion.md).
1D.11 local acceptance is closed for the selected macOS arm64/USB scope;
Developer ID, notarization, installers and public distribution remain 1E.

## Local contents and startup

Owned output root: `/private/tmp/meshchan-1d11-20261116-01`.
The original build 2 contents remain under `delivery/` as historical evidence.
The earlier repaired build 3 remains in `delivery-beta1-build3/`. The earlier
app-integrated USB compatibility candidate remains in `delivery-beta1-build4/`, with
[fresh software/native and bounded GUI hardware results](../validation/phase-1d11-app-usb-compatibility.md).
The current complete Release and matching CLI are in `delivery-beta1-build5/`.
The [build 5 continuation](../validation/phase-1d11-build5-gui-delay.md) records
fresh native checks and an unsuccessful U03 hardware attempt. Its current contents are:

- Complete `Meshchan.app` Release, with its original native assets, symlinks,
  modes and embedded notices.
- Complete `meshctl/` native CLI bundle; `meshctl/bin/meshctl --version` must
  report `meshctl 0.1.0-beta.1`.
- Source/dependency/build metadata, complete recursive inventories, checksums,
  signature results and local instructions. Evidence databases, credentials,
  screenshots and peer configuration are outside this deliverable directory.

Launch with an explicit new, owned absolute data directory:

```sh
MESHCHAN_BETA_DATA="$(mktemp -d /private/tmp/meshchan-beta-data.XXXXXX)"
open -n /private/tmp/meshchan-1d11-20261116-01/delivery-beta1-build5/Meshchan.app \
  --args --data-dir="$MESHCHAN_BETA_DATA"
/private/tmp/meshchan-1d11-20261116-01/delivery-beta1-build5/meshctl/bin/meshctl --version
```

The GUI must close normally and confirm cleanup, storage/owner release and
worker exit, followed by OS PID absence, before any CLI/core consumer opens the
same directory. An exit code from `open` is not that evidence. Unknown cleanup
keeps the device/directory quarantined. Do not delete ownership files or use a
second consumer to test release. A port hint never authorizes device access;
Refresh, explicit selection and finite operations require current user intent.

## Scope and known limits

Product target is macOS arm64 plus one explicitly selected USB Companion.
Offline explicit saves, finite checks, recorded PING/Responder, bounded History
and new-file-only safe single-page export use existing public core/link APIs.
Database schema 1, diagnostic summary format 1, CLI envelope schemaVersion 1 and
wire version remain independent of the product version. App run versions include
`+5`; CLI recorded versions do not need build metadata. Historical runs retain
their original build versions.

Historical real RF/Cancel/Quit results do not validate this new binary. The
[November 17 continuation](../validation/phase-1d11-rf-matrix-completion.md) uses
this exact complete build 5 Release: GUI PING and Responder exact PONG, actual
unplug/transport-failure/explicit recovery Check, expected responseTimeout,
receiving-stage Cancel and active native Quit. Five application attempts brought
the cumulative count to fourteen, without a cumulative ceiling. Twelve settled
records, seven prior projections, exact text/Settings/preset saves, a VM native
Save-panel export and normal independent reopen passed. Host Computer Use
input observations, the U02 scheduling-margin failure and unmeasured physical
detection latency remain documented limits; USB reliability is not established.
The operator's updated AGENTS policy routes hardware-free UI to the existing VM.

At the earlier build 5 cutoff, it
passed a GUI finite Check, but U03's recording then failed initialization at
DEVICE_QUERY before receiving or responding. B obtained actual local OK under
the explicit 60-second send-confirmation policy, then responseTimeout/waiting
without PONG. RF stopped. U02 did not start A after the fixed admission window
was missed; B naturally completed with zero responses. No physical action
occurred. Seven-row GUI safe export, normal Quit and independent exact data
read passed; second GUI reopen/close needs completion after Computer Use could
not locate the known live window. The owned fixture is excluded from live data
collection. Cumulative actual attempts are nine, with no cumulative ceiling.
The complete build 5 product manifest SHA-256 is
`edcdf862edae4733ff430feafcd08537bbce5e56afa716e93553d42d3f4e5782`.
That earlier cutoff did not establish USB reliability, an exact round trip or
beta acceptance; its pending second GUI close and new CLI smoke were subsequently
completed. Read the November 17 record for the final acceptance and limits.

Build 4
has fresh GUI responseTimeout, receiving-stage Cancel, active native Quit and
nonempty History/new-file export/reopen evidence. Current exact GUI PONG,
Responder round trip and proven-active physical unplug/replug remain incomplete.
The later [manual-input continuation](../validation/phase-1d11-peer-stop-unicode.md)
verified Chinese/emoji/multiline Save, exact independent read and new GUI reopen.
Its single newly authorized B responder failed after an unexpected matching
shared-inbox PING and one unconfirmed PONG attempt; RF stopped at 2/8 attempts with no
A Start or second B session. USB initialization remains intermittent: build 4
GUI Check failed twice before succeeding, despite the bounded compatibility
handshake. It is not an established reliability fix. Immediate physical
disconnect notification is not promised; finite timeout/Cancel and truthful
cleanup/explicit recovery must be assessed separately. No reliability percentage
is asserted. All current limitations and pending cases are in the linked record.
The subsequent offline review passed 31 focused TCP/peer/observer tests and
validated a corrected per-case ID proposal, including the U03 `--text` option.
The operator removed the cumulative send ceiling; actual attempts remain two,
and no RF retry was performed. Missing Companion OK is still unresolved.
The later authorized [v2 hardware continuation](../validation/phase-1d11-v2-hardware-continuation.md)
used both B sessions: U02's GUI admission was missed, and U03 failed to obtain
exact PONG despite one locally accepted A response. RF stopped again at four
cumulative application attempts, without a cumulative ceiling. The new settled
record, preserved Unicode/Profiles, six-row new-file export and normal
Quit/independent reopen passed; no physical action occurred. Products are unchanged.
The subsequent [B acknowledgment investigation](../validation/phase-1d11-openhop-ok-investigation.md)
found a fresh 19.1-second server duty-cycle deferral beyond the original
15-second budget. Standard OK succeeded for two B-only raw sends; the diagnostic
PING failed while sending. The upstream modification proposal was withdrawn
after the operator excluded server changes; no openHop code was changed.
Cumulative application attempts are seven with no cumulative ceiling; the real
GUI matrix and product inventory retain their cuts. The separate
[client delayed-OK implementation](../validation/phase-1d11-delayed-ok-client.md)
is a new source/peer cut, not a change retroactively compiled into build 4.
Its [first real B-only policy case](../validation/phase-1d11-delayed-ok-rf.md)
received OK after 4.165858 seconds and passed the planned post-acceptance timeout
and cleanup. Current cumulative attempts are eight. The actual OK was under
15 seconds, so real longer-delay tolerance and the GUI RF matrix remain open.

A universal binary slice is not Intel runtime acceptance. Mobile dependency
probes are bounded historical evidence, not mobile product support. No BLE,
background receive, content publication/sync, mobile business storage, automatic
connect/retry/resend or openHop product transport is introduced. The source-only
peer reuses the project protocol implementation and is not an independent oracle.
No fresh Pinyin claim follows from Unicode text entry.

## Distribution handoff

These complete local directories are candidates, not installers or a public
release. Signing is local/ad hoc; Developer ID and notarization are not configured.
1E must resolve project licensing, native corresponding-source/build/relinking
and notice completeness, complete AOT runtime correspondence, signing/hardened
runtime, notarization, installer/quarantine and clean-machine distribution checks.
No tag, GitHub Release, binary upload, deployment or public distribution is made.

## Historical build 2 cut at pause

Fresh local suites passed app/core/CLI/link **250/362/276/180**, six process
gates, **124** Python tooling tests, **16** optimized lifecycle/fault regressions,
three CLI builds and **101** smoke process checks. Actual dev.2 producer to beta
consumer compatibility passed. New Debug/Release, strict signatures, **22**
native XCTest, three persistence/relocation runtime runs, two normal runtime
Quit cases and two finite SQLite probes passed. These are local dirty-source
results; PR #37's successful remote CI is a separate baseline.

Info.plist reports short version `0.1.0.1`, build `2`; decoded Dart defines
report `0.1.0-beta.1` / `2`. The complete Release Runner hash is
`fd48cbf5bf9404f4f992a9dfe789d0663f0a0b06cf47f3234973167d0e7a83a5`.
The Runner hash alone is not the bundle identity: the full manifest is
`delivery/metadata/products.json`. This exact complete copy was used for the
limited offline GUI session and checked again afterward.

Offline GUI preset/settings saves, actual PING parameter preview, an empty
new-file safe export, normal Quit and independent CLI reopen passed. GUI
Chinese/emoji input did not establish the intended controller content; this
and all current hardware assertions remain explicitly incomplete. The full
validation record retains the tool/focus observations and actual saved text.
Hardware attempts/inbox sessions/application sends at pause are **0/0/0**.

`delivery/source/` retains the final repository source snapshot; metadata holds
both packaging and final source cuts. The final checksums cover the complete
local contents while preserving the initial preparation receipt separately.


## Build 3 repair continuation

The build 2 facts above remain historical. Its GUI finite Check crashed with
AXPlatformNodeCocoa startEditing; a separate resource-free native fixture
reproduced the failure. Build 3 replaces selectable display labels with
SelectionArea/Text, preserves real input fields and accessibility, and changes
no SDK/core/link/RF behavior. Its complete app suite is **252**, all six process
gates and **124** Python tests pass. Fresh native and actual GUI hardware results
must be read from the latest beta validation section. Build 2 is not an accepted
beta, and its Runner hash cannot identify the repaired app.

Build 3's fresh complete native checks passed: 22 XCTest, three runtime runs,
two normal runtime Quit cases, two finite SQLite probes and strict signatures.
Its actual GUI finite Check passed and returned to Not connected with successful
session/observer cleanup. U02 remains BLOCKED after automatic approval review
rejected A Start because the peer's initialization event was insufficient
receive-readiness evidence. No RF send occurred. A later synthetic-keyboard
redispatch/blank-window observation is retained; a subsequent pointer-only
offline normal Quit produced the complete release/worker/owner report. The
upstream keyboard-loop issue is still open; this does not establish physical
keyboard failure or active-hardware Quit. Required GUI RF, physical unplug,
Cancel/Quit phases and Unicode/export user-path assertions remain incomplete.

The operator later authorized exactly one replacement U02 B session and a pause
afterward. On the unchanged build 3 product, B's actual task-owned read-write
witness preceded GUI PING registration. A then failed initialization with
requestTimeout at opcode 22, before any send or reception; no exact PONG or RTT
was established. This actual U02 attempt is FAIL at the USB prerequisite.
Registration/logical/final-cleanup saves and all cleanup scopes settled; normal
app Quit/OS exit and current CLI reopen verified the same settled failure and
original appVersion. B naturally closed after consuming six entries in nine
reads, with zero responses. Total application sends remain 0/8. No retry fit the
remaining finite window, no later case ran, and the requested pause is in effect.
The earlier approval-blocked attempt remains separate. The latest validation
section and owned `hardware/u02-replacement-01/result.json` identify the evidence.

One further explicitly authorized U02 retry used the identical build 3 artifact
and unchanged finite parameters. Run `c286338ed69b459ade28faa4c62f3879` again
failed USB initialization (requestTimeout, opcode 22) before send/reception.
Cleanup, final committed saves, normal Quit/OS exit and current CLI reopen passed;
the prior failed record's persisted projection was unchanged. B naturally closed
with 36 consumed entries/37 reads and zero responses. Total application sends
remain 0/8. The explicit stop condition was met, no further case or retry ran,
and the operator-requested pause continues. Both initialization failures and the
earlier approval block remain separate; no PONG or USB repair is claimed.
The latest index is `final-summary-u02-replacement-02.json`, with raw safe facts
under `hardware/u02-replacement-02/` and unchanged product inventory.
