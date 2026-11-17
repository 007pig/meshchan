# Build 5 finite GUI hardware matrix and offline completion

**Local beta accepted with documented limits** for macOS arm64 and the selected
USB Companion. The required finite host hardware targets and the remaining
offline path are established on complete `0.1.0-beta.1+5` Release. The operator
explicitly moved hardware-free UI work to the existing macOS VM; this record
separates that evidence from host USB/RF. Local 1D.11 acceptance is closed within
these limits. Developer ID, notarization, installers and public distribution
remain 1E work.

This is a finite acceptance conclusion, not a USB reliability claim. Earlier
initialization/RF failures, the U02 scheduling-margin failure, host Computer Use
input observations and the narrower GUI/IME coverage remain below and in their
original records. No failed result is overwritten or converted to PASS.

## Source, software and artifact correspondence

Baseline: actual PR #37 merge `0fd49a3495d972c88dee35fc709501db78a16d16`, tree
`e59fd975aeecdd72152424d1446683b3b647827f`; branch
`codex/phase-1d11-hardware-beta`, with manifested uncommitted beta/client work.
The final read-only PR check still reports MERGED, reviewed head
`67f5e8036e7f70d2b69ddd58210b510b967324de`, and successful `check`/`macos-app`
checks in runs [43805380656](https://github.com/007pig/meshchan/actions/runs/43805380656)
and [43805376816](https://github.com/007pig/meshchan/actions/runs/43805376816).
These are baseline CI, not CI for this dirty candidate. No commit, push, PR,
tag, GitHub Release or binary upload was performed.

Owned root `E`: `/private/tmp/meshchan-1d11-20261116-01`.
This continuation `H`: `E/hardware/run-09-rf-restart`.
The complete candidate remains `E/delivery-beta1-build5/`. Its immutable tested
`metadata/products.json` SHA-256 is
`edcdf862edae4733ff430feafcd08537bbce5e56afa716e93553d42d3f4e5782`.
All original product files, modes, sizes and symlink targets remain unchanged.
The [build 5 preparation](phase-1d11-build5-gui-delay.md) identifies compilation
inputs and the earlier failed matrix. This turn changed instructions/docs and
owned fixtures/evidence, not product code or dependencies. No rebuild after RF
was used to inherit the old binary's hardware results.

| Fact | Cut and result |
| --- | --- |
| Version | Link/core/CLI beta1; app `0.1.0-beta.1+5`; explicit manifest/five internal constraints/CLI constant/fallback check PASS |
| Actual Apple metadata | Debug/Release short version `0.1.0.1`, build `5`, Bundle ID `org.meshchan.meshchan`; Flutter definitions beta1 / 5 |
| Toolchain | Python `/opt/homebrew/bin/python3` 3.15.2, Flutter 3.50.0 stable, bundled Dart 3.14.0, installed Xcode 27.2 (27B52); no upgrade/global PATH change |
| Fresh build 5 software | Analyze PASS; app **262**, Python **135**, six process gates PASS |
| Retained member suites | Core **362**, CLI **286**, link **207**; their actual gate inputs, root workspace/lock and tests match the build 5 compilation cut (71/53/38 checked inputs respectively) |
| Fresh build 5 native | Complete Debug/Release, strict signatures, **22 XCTest**, three persistence/relocation runtime runs, two normal runtime Quit cases, two finite SQLite probes PASS |
| New matching CLI smoke | **101 fresh checks PASS** in `D11-b5-smoke-after-gui`, 2026-11-17 03:54:23–03:55:50 UTC: source/AOT/whole-bundle relocation, version, recording, nonempty History and export |
| Dependencies | Root lock SHA `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`; third-party graph unchanged; retained notices match that graph |
| Guest artifact | Both guest copies matched **all 29 regular files and 12 symlinks**, including hash/mode/size/target; strict signatures PASS, actual arm64, macOS 27.2.1 (26B131), VirtualMac2,1 |

The previous 101 native checks did not identify this newly built CLI. The fresh
smoke above closes that gap after normal host shutdown. Earlier generated/schema,
dev.2 compatibility, mobile dependency/API and optimized runner results retain
their explicit source cuts; they are not new mobile product acceptance. No
lifecycle/finalization implementation changed in this turn.

## Renewed authorization and finite plan

The operator renewed RF with the same selected USB A and B registration,
independent physical radios, explicit TCP 5050, no cumulative application-send
ceiling, unchanged finite parameters and abnormal-stop rules. Existing exclusive
client and shared-inbox consent remained. Public records use A/B aliases; private
selection/secret-reference equality was checked in memory. There was no openHop
code/service/configuration, firmware, channel/key, RF/duty-cycle/Fabric, VPN or
security-setting change. No WS fallback, automatic reconnect/retry/resend or
inbox clearing occurred.

Each case has fresh distinct nonzero local/peer IDs. Fixed non-sensitive content
is 18 bytes. Local slots remain A1/B3 and both return routes are explicit Direct
descriptor 0/empty path. The prior limited slot/key audit is inherited; this is
not a new all-slot audit or proof that Fabric forwarding used only one modem.

| Case parameters | Values |
| --- | --- |
| A PING | request/init/task/response 15/30/60/15 s, startup 0, maxEntries 128 |
| A U03 Responder | request/init/task 15/30/240 s, listen 180 s, maxResponses 2, maxEntries 128, startup 0 |
| A U06/U07 | Same clocks/listen/entry limit, maxResponses 1; no B sender |
| B both sessions | control/send confirmation/init/task 15/60/30/90 s, startup 0, maxEntries 512 |
| B U02 | Responder listen 60 s, maxResponses 1 |
| B U03 | One PING, response 15 s from actual acceptance; RTT origin before send |
| U01/replug Check | Original GUI request/init 5/15 s, startup 0 |

The new client policy separates B's send confirmation and PONG clocks within
the same whole-task budget. Actual OK is still required. This run does not
measure/reproduce a real OK delay beyond 15 seconds. The source-only peer reuses
project protocol code and is not an independent oracle or product transport.

## Actual host matrix

Host PID 56774 ran the exact delivered app with explicit `H/gui-a-data`.
All A operations below were real Computer Use GUI actions, not standalone CLI
substitutes. The two B sessions used the inventoried current native peer.

| Case | Target result and facts |
| --- | --- |
| U00 | Offline startup had no listed/opened ports or selection. Actual Preview matched saved finite parameters/new IDs. A new draft was explicitly saved during U06; old Chinese/emoji text was subsequently visually reopened. |
| U01 | PASS: Refresh and explicit A selection, one Check, observed 03:59:40.522102 UTC; Heltec V4.3 OLED, v1.18.0-81dbae5, protocol 14. Actual session/observer cleanup succeeded; Not connected. This closed snapshot did not imply later hardware readiness. |
| U02 | PASS exact RF target; scheduling assertion FAIL retained separately. GUI run `369ef85d078d87b25a8dfc299bf8aeba` completed with attempted/dispatched/write/OK/acceptance true, exact matching PONG, no duplicates, application RTT **2324003 us**. Core/observer cleanup, all saves and finalCleanup succeeded; fullySuccessful true. B replied exactly once, obtained OK and exited/reaped normally. |
| U03 | PASS exact B PONG: GUI run `02008ac4aabc6cde13ac45c069e4083a`, prepared 04:05:48.593375 UTC, finite maxResponses 2. One B PING received an exact-content PONG, RTT **3596318 us**, actual OK, normal cleanup/exit. A remained the same nonterminal attempt in the fresh 04:06:44.600 GUI observation. |
| U04 | PASS observed physical fault handling and explicit recovery, with timing limits: user actually unplugged A after U03 proof; selected OS path disappeared. Same run ended 04:08:13.135254 UTC as receptionFailed/settling, session transport/ready, retaining one attempted and locally confirmed response. No Cancel or natural listen completion caused this terminal. Cleanup/observer release and final saves succeeded. User reinserted only after release; GUI Refresh/reselection/new Check succeeded at 04:11:23.878999 UTC. No extra PING or automatic reconnect/resend. |
| U05 | PASS expected failure: run `df9e1b89c85704488c174792f32ba9b2` had local acceptance, then responseTimeout/waiting, no PONG/RTT, clean final saves. Both B consumers were closed. Initialization/transport/overall failures were not substituted. |
| U06 | PASS post-result receiving-stage Cancel: run `a2c62662e0be9ca70a16ab21b0246428`, prepared 04:14:53.332322 UTC. Device page exposed the current-diagnostic exclusion state, no executable competing Check/Refresh; navigation and explicit offline Save preserved the owner/run. Cancel 04:16:28.791–.855 UTC produced canceled/receiving, null listenStopReason, zero responses, successful core/observer cleanup/final saves. |
| U07 | PASS active native Quit: run `741865ad07abac5219d9d905450d4745`, prepared 04:17:34.717874 UTC. First native Quit showed a real dirty-draft decision; Continue editing retained 67 body bytes. A subsequent navigation decision explicitly discarded the 13-byte local edit. The same run was still nonterminal before final native Quit at 04:19:38.897 UTC. Independent terminal is canceled/receiving, null listenStopReason, zero responses; actual resources/worker/owner release, exit 0/reap/OS absence and unchanged committed draft all verified. |
| U08 | PASS for the operator-selected split route: host visual reopen/offline Save/normal close, then VM History/filter/system-panel new-file export/normal close on the same complete artifact and closed fixture lineage; independent current CLI verified all twelve projections and exact text/settings/preset. Host failed filter/black-frame observations remain separate. |

U02's pre-action guard observed 04:02:07.292 UTC before its planned
04:02:07.829364 deadline, but actual registration committed at
04:02:09.577559: **1.748195 seconds after the planned scheduling margin**.
Conservative B listen remaining at commit was 47.251296 seconds instead of 49.
The guard did not account for action-dispatch latency. The target round trip and
release actually completed inside the unchanged finite window; no timeout or
limit was relaxed. This preserves real PONG evidence while explicitly failing
the larger scheduling-margin assertion. It does not validate that guard as a
future worst-case admission guarantee, and no extra RF was used to erase it.

The U04 prompt requested action before 04:07:45 UTC. The operator later reported
only “after 04:07”; exact seconds and compliance with that prompt margin are
unknown. Record the actual unplug/absent-path/transport-failure correlation and
successful explicit recovery, without inventing an action timestamp or latency.
The transport terminal preceded the 180-second listen deadline, retained the
earlier response, and was not an initialization failure or a Cancel. No immediate
disconnect guarantee or universal unplug safety is claimed. `settling` after a
response is valid; the test does not require receiving as U04's terminal stage.

U06/U07 receiving is post-result stage evidence, not a GUI live-ready claim.
U07's app-observer completion follows the actual runtime release/worker barrier;
there was no separate live terminal observer projection after the process quit.
History fields are compared only where they are actually persisted. Application
RTT is integer microseconds including host/queue/USB/network/radio paths, not
pure LoRa airtime.

## Accounting and data integrity

| Scope | Actual attempts / consumption |
| --- | --- |
| U02 | A PING 1 + B PONG 1; B 59 entries/60 reads |
| U03/U04 | B PING 1 + A PONG 1; B 1 entry/2 reads; no added readiness/recovery PING |
| U05 | A PING 1 |
| U06/U07 | Zero responses/attempts each; no B sender |
| This continuation | **5 application attempts**, two B sessions, **60 B entries/62 reads**, 19 A entries/26 reads |
| Cumulative 1D.11 | **14 application attempts, 432 B entries/444 reads**; no cumulative send ceiling |

Attempts do not count all airtime, firmware retries, Fabric forwarding or site
traffic. Inbox filtering follows consumption; this was not a test-channel-only
peek. No uncertain dispatch is counted as zero. All current consumers ended
normally; no product or peer was killed to manufacture cleanup/normal Quit.

The fixture descended from the proven closed H8 copy, preserving seven rows.
Five new build 5 rows are settled with successful aggregate cleanup and no
recovery. All seven prior projections, including the earlier build 5
initialization failure, remain exactly unchanged. Terminal records were not
archived/replayed by reopen. Settings retention was 1000 during RF, later
explicitly saved as 1001; no row was deleted.

The old title `中文 🚀 beta4` and body `Meshchan 中文验收\nemoji 🚀🙂` remain exact,
revision 1. Actual Pinyin composition remains evidence from its build 4 cut;
this run visually/independently verifies persisted text, not new composition.
New GUI draft `Meshchan beta5 run09` retains the exact 54-byte body
`Offline edit while the finite USB responder is active.`, revision 1. Its
13-byte dirty Quit edit was explicitly discarded. The Quit preset's name was
saved as `D11 B5 active Quit verified`; all operation/budget/route/ID fields stayed
unchanged. Both Settings and profile changes were independently read after close.

## Offline VM path and retained host observations

The operator's new policy is now in [AGENTS.md](../../AGENTS.md): use the existing
VM for hardware-free UI; host Computer Use only for real USB/serial UI. The
[VM skill](../../.agents/skills/macos-vm-gui-testing/SKILL.md) was applied without
new permissions, TCC/SIP changes, executor replacement or USB passthrough. Every
remote action used strict SSH host-key/VirtualMac UUID/console checks and exact
owned PID/argv/focus guards. The guest was left running; task-owned product and
executor processes ended, their locks cleared normally, and SSH disconnected.

The host's final offline instance did visually reopen both exact drafts, save
the profile name and Settings, and display twelve History rows. Computer Use
then failed to select the History menu item, reported noWindowsAvailable, and
Down/Down/Down/Return was followed by a black frame/empty AX content. Cause is
unestablished. Native menu Quit still produced full release/worker/owner output
and OS exit; all committed data was verified before VM transfer. The host's
twelve-row export was NOT_RUN, not silently relabeled PASS.

VM run `20261117T043513Z-product-79674` used a new guest fixture copied only
after host normal closure. PING filter selected five rows; Reset restored
twelve. The actual NSSavePanel destination/filename/focused owner were checked
before publishing a new file. Export job 1 settled with generation/admission/
publication true, twelve rows and moreAvailable false. The JSON itself contains
format/exportedAt/runs; the pagination fact belongs to the GUI job, not an
invented JSON field. No staging files remained.

Collected file: `H/vm-offline/Release/exports/meshchan-beta5-summary-run09.json`.
SHA-256: `6205733d6e8c873807db1075a40b5bd55738b5a2fe2453cb0a1fd8db972d74d0`.
Format 1 and the ordered twelve safe run projections equal the independent core
export; separate export timestamps are not compared. Content, port, private
endpoint and credential markers are absent. Raw DBs/screenshots/logs remain
outside Git and outside product delivery.

A second focused VM run, `20261117T045222Z-product-86618`, used another
inventory-identical copy. The same three Down/Return keys selected `listen` and
the app stayed interactive: Apply returned zero rows, Reset twelve. The first
owned checker wrongly expected PING and retains FAIL; it is not a product
failure. Native Quit's first immediate PID-absence check was early and failed;
later OS observation and the actual shutdown report confirmed natural exit.
Quit was not repeated and no signal was used. Both original check failures
remain; this is not a complete keyboard matrix or a proven cause/fix for host
Computer Use's black-frame observation.

Other retained preparation failures include the stale `+4` diagnostic assertion,
the rejected first probe basename, the list/show projection comparison and the
first executor verifier's wrong `date` path. Passing follow-ups preserve the
original logs/cuts, correct only their own tools, and do not weaken product
assertions. Final inventories cover owned helper sources as well as products.

## Limits and 1E handoff

Intermittent USB initialization remains observed at earlier cuts of this same
binary; successful current sessions do not prove the completion handshake a
reliability repair. No startup delay, timeout expansion or automatic retry was
added. Physical-error timing and U02 dispatch margin have the limits above.
Host synthetic-input/rendering observations remain unresolved; the VM result
does not establish physical-host keyboard correctness. Dvorak, remaining
conflict/filename-preedit/Cut-Copy/full-screen/focus/accessibility variants retain
their earlier coverage. No new IME/host-interference measurement is claimed.

Only macOS arm64 with the explicitly selected USB Companion is accepted here.
Intel slices are not Intel runtime acceptance. B is source-only; no openHop
product entry point, BLE, mobile business storage, background receiver,
content publication/sync, backup/import or extra window was introduced.
Historical mobile dependency/API probes retain their separate Step 10 limits.

1E must close licensing/notices/corresponding-source/relinking and AOT runtime
correspondence, Developer ID/hardened runtime, notarization, installer/quarantine,
clean-machine and public-distribution checks. Local acceptance does not authorize
or claim those actions. Complete source/product/final-checksum metadata and
replayable owned evidence remain with the local candidate.
