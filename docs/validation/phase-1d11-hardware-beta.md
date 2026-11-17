# Phase 1D.11: local beta candidate and host hardware acceptance

## Status

**Local beta accepted with documented limits.** Current candidate:
`0.1.0-beta.1`, app build **5**. The
[November 17 completion](phase-1d11-rf-matrix-completion.md) closes the required
finite host GUI RF/physical/Cancel/active Quit targets and the operator-selected
offline VM path on an inventory-identical Release. Fresh new CLI smoke passed
101 checks. Twelve settled records, seven preserved prior rows, exact text and
new-file safe export/normal independent reopen are verified. Earlier failures,
the U02 scheduling-margin assertion and input/timing limits remain explicit.
1D.11 local acceptance is closed within that scope; 1E is not a public release.

### Earlier preparation and attempts (historical cuts)

Two separately authorized build 3 U02 GUI attempts actually executed and failed the USB
initialization prerequisite, with zero application sends. Their normal cleanup,
saved failures, app Quit and independent reopen are verified below. The latest
[build 4 continuation](phase-1d11-app-usb-compatibility.md) adds real GUI finite
Check, expected responseTimeout, receiving-stage Cancel, active native Quit and
nonempty History/export/reopen. U02's new B session reached entryLimit before A
Start. The subsequently authorized [peer-stop/Unicode continuation](phase-1d11-peer-stop-unicode.md)
adds exact manual Chinese/emoji Save/reopen, but B attempted an unconfirmed PONG
before A Start and failed waiting for OK. Actual cumulative attempts remain two;
the operator later removed the cumulative send ceiling. The linked offline
review validates separate per-case IDs and corrects the unexecuted U03 option,
with 31 focused tests. The subsequently authorized [v2 hardware continuation](phase-1d11-v2-hardware-continuation.md)
left U02's A target BLOCKED by the finite admission window, then executed U03:
A responded once with local acceptance, while B failed responseTimeout/sending
without OK or exact PONG. RF stopped; U04 remains NOT_RUN. Actual cumulative
attempts are four with no cumulative send ceiling. All consumers are closed;
six-row export and independent reopen passed. Earlier ceilings below describe
their original execution cuts.

The latest [B TCP/0x3E investigation](phase-1d11-openhop-ok-investigation.md)
added three B-only send attempts, for seven cumulative attempts without a
cumulative ceiling. Two raw sends obtained standard OK; the diagnostic PING
reproduced a sending-stage timeout while the server logged a 19.1-second
duty-cycle deferral. RF stopped. The operator rejected the proposed server
change; it was never deployed and was removed from project deliverables.
The subsequent [client compatibility](phase-1d11-delayed-ok-client.md) separates
explicit finite send confirmation from the PONG window within the original
whole-task budget. Its software checks do not establish new GUI/RF acceptance.
The subsequent [one real B-only policy case](phase-1d11-delayed-ok-rf.md) passed:
OK after 4.165858 seconds, then the planned 15-second no-responder window and
normal cleanup. It adds one attempt / 75 entries / 76 reads, for current totals
8 attempts / 357 B entries / 364 reads with no cumulative send ceiling. No
real OK delay beyond 15 seconds, GUI exact PONG or physical cycle was established.

The later [complete build 5 GUI/delayed-OK continuation](phase-1d11-build5-gui-delay.md)
rebuilt Debug/Release and the matching CLI/peer. Fresh app/Python counts are
262/135, with six process gates, 22 XCTest, three runtime runs, two normal
runtime Quit cases and two finite probes. GUI U01 Check passed; U02 missed
its fixed admission window and never started A. U03 failed A initialization
before receiving, while B obtained local OK but no exact PONG. RF stopped with
no physical action. Seven-row GUI safe export, first normal Quit and independent
exact data read passed. Cumulative attempts are now nine, B entries/reads
372/382, with no cumulative ceiling. The second GUI reopen is blocked by a
Computer Use window lookup error while the known process remains live; no
live database copy or final-release claim is made. Earlier closed-consumer
facts and counts above retain their original cuts.

## Source, tools and evidence

Work started from clean `master`, actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, tree
`e59fd975aeecdd72152424d1446683b3b647827f`. Its second parent is the reviewed
`67f5e8036e7f70d2b69ddd58210b510b967324de`; the successful-parent descendant
drain and nonzero/interruption/publication fixes are present. Work is on
`codex/phase-1d11-hardware-beta`, with an uncommitted, manifested source cut.
No merge, cherry-pick, tag, release, push or binary upload is performed.

Fresh owned evidence: `/private/tmp/meshchan-1d11-20261116-01` (0700).
`baseline.json`, source snapshots, per-gate source manifests, argv/cwd/environment,
UTC start/end, exit codes, logs/hashes and `ledger.jsonl` preserve the actual cuts.
Documentation changes after software gates are independently tracked. Product
inputs changed for beta metadata and the worker version fallback; the Step 10
claim of 271 unchanged product inputs does not apply to this candidate.

Verified toolchain: `/opt/homebrew/bin/python3` **3.15.2**; installed Flutter
**3.50.0 stable**, framework `ab2912035e160d9cad6306df307576da6128ebdb`, bundled
Dart **3.14.0**; Xcode **27.2 (27B52)**. Commands select Apple Clang locally;
no SDK/dependency upgrade or global environment change is made. `os.txt`,
`sdk.txt`, `clang.txt` and `arch.txt` retain actual host facts.

PR #37 was rechecked as MERGED at `2026-11-16T04:55:19Z` with the actual merge
above. Latest-head CI runs [43805380656](https://github.com/007pig/meshchan/actions/runs/43805380656)
and [43805376816](https://github.com/007pig/meshchan/actions/runs/43805376816)
completed successfully for both `check` and `macos-app`. These are baseline CI,
not CI for this dirty beta source. The first GitHub connector returned 401;
read-only `gh pr view` supplied the retained `pr37.json` result.

## Version and compatibility changes

Link/core/CLI are `0.1.0-beta.1`; the app at this earlier cut was `0.1.0-beta.1+3`.
Build 4's later app-local change and fresh gates are in the linked continuation.
The root workspace
has no product version. `check_product_version.py` independently validates four
manifests, five internal constraints, the CLI constant and app build fallbacks.
The worker uses Flutter build defines when present and manifest-validated
`build_version.dart` fallbacks for direct Dart processes. Diagnostic process and
worker assertions require the beta app version. Build 2 advanced historical 1;
build 3 advances build 2 for the reproduced display-label repair.

`candidate_common.versions()` keeps its historical three-member dev.3 default,
with optional explicit expected version/app build. The existing four-member
runner forwards `--expected-version` into smoke and schema compatibility;
`--app-build` adds the four-member check. Smoke passes the expected version to
source/AOT recording, nonempty History/export and report validators. The old
acceptance harness defaults and explicit dev.2 legacy override remain. CI's
current smoke invocation explicitly selects beta and checks app fallback facts.
No candidate/archive format or runner lifecycle behavior is changed.

Historical producer stays at `e237be5c2fb9e4fd1cf2f2c26717582f34a5e757`, with
explicit dev.2/legacy arguments. Old rows/versions, Unicode/CRLF, schema 1,
summary format 1, CLI envelope schemaVersion 1 and wire version are preserved.
Future/corrupt rejection compares both bytes and presence of main/WAL/SHM/journal.
The root lock and third-party resolved graph are not upgraded.

## Fresh software and native results

Results are updated from retained gate receipts; no planned result is a PASS.
The first Python discovery (`R08-python`) executed 124 tests and failed two
errors/one assertion because three existing environment tests still invoked
current consumers with the historical default. `delivery_environment_test.py`
now passes explicit beta for those current-consumer tests. The failed gate/log
remains. Corrected complete discovery (`R08b-python`) passed all **124** tests.
The added four tests cover manifest/constraint/fallback rejection, historical
default refusal on beta, runner propagation, AOT/source recording arguments,
report rejection, and nonempty History/export version enforcement. Two initial
new-test fixture errors were corrected before the baseline: timestamp format
and a mock receipt containing a non-JSON callback; neither was a product result.

The fresh results and product hashes are recorded below. The native plan used
external DerivedData, test/runtime cwd and fixtures.
XCTest preflights settings and `.xctestrun` before execution; disabled-owner must
be active before the engine. Normal runtime and finite SQLite probes remain
separate from disabled-owner XCTest and from actual hardware Quit.

## Original concrete hardware plan before authorization

The local hardware skill and its validated-setup reference were read. Private
configuration exists, but its November 15 setup is not a current device choice
or standing send allowance. No enumeration, open, management/session connection,
inbox read or application send has been made for this beta session.
Private exact paths/endpoints and proposed peer files are under `hardware/` in
the evidence root; public aliases are **USB A** and **source-only TCP peer B**.
B must use a physical radio distinct from A. Historical Fabric forwarding is
not evidence of isolated single-radio reception. No automatic WS/TCP fallback.

Proposed slots are A send/receive **1/1**, B send/receive **3/3**, both routes
Direct (`descriptor=0`, empty path). Current role/USB identity, independent
physical B/Fabric scope, selected-slot key equality and radio compatibility
must be rechecked without printing keys. Both clients must have exclusive
ownership. Inbox filtering occurs after consumption; this can consume other
messages. No clear/reset, reconfiguration or displacement of unknown clients.

Fixed non-sensitive content is `Meshchan D11 beta1`; new A/B local IDs are
`0xD1110001` / `0xD1110002`. These are test identities, not authenticated identities.
Device Check uses request/init/startup **5 s / 15 s / 0 ms**. A PING uses
**15 s request / 30 s initialization / 60 s task / 15 s response / 128 entries**.
A Responder uses **15 s / 30 s / 240 s task / 180 s listen / 128 entries**, zero
startup delay, maxResponses **2** for U03/U04 and **1** for U06/U07. These finite
preselected windows allow Computer Use and human actions; they are test presets,
not changed defaults or a workaround for initialization failure.
B uses request/init/task **15/30/90 s**, zero startup delay; U02 responder listen
60 s, 128 entries, maxResponses 1; U03 PING response 15 s, 128 entries.
A fresh passive B window covering 90 s or verified actual timeout is required.
No old passive observation is relabeled current; proposed RF configurations
intentionally lack admissible window evidence until that prerequisite is met.

| Case | Planned assertion | Status / sends reserved |
| --- | --- | --- |
| U00 | Offline startup, explicit Draft/Profile/Settings saves, preview/reopen | BLOCKED full target: offline components passed; exact Chinese/emoji GUI input not established / 0 |
| U01 | Explicit Refresh/select A, finite Check, confirmed close and dated snapshot | BLOCKED current selection / 0 |
| U02 | B actually ready; GUI A PING; exact correlated PONG, separate saves/cleanup | BLOCKED current RF authorization / 2 |
| U03 | GUI A Responder maxResponses 2; one B PING/exact PONG; A still active | BLOCKED current RF authorization / 3 shared with U04 |
| U04 | Same proven active A run; user unplug; observe 30 s, truthful error/cleanup; explicit replug/new Check | BLOCKED human action and prerequisites / no extra PING |
| U05 | B responders closed; GUI PING locally accepted, actual responseTimeout | BLOCKED current RF authorization / 1 |
| U06 | No B sender; GUI Cancel; post-result canceled/receiving/null listenStopReason/0 responses, cleanup/saves | BLOCKED device authorization / 1 (expected 0) |
| U07 | Separate no-sender Responder; dirty Continue editing if window permits; native Quit; post-result receiving and real release/worker/OS exit | BLOCKED device authorization / 1 (expected 0) |
| U08 | Current History, new-file safe export, normal Quit and independent current CLI/core reopen | BLOCKED hardware-dependent final path; empty offline export and normal Quit/reopen passed / 0 |

Expected sends **5**, conservative maximum **8 application-send attempts**;
actual **0**. One initialization invocation per device case; **no retries**.
U01 and the explicit post-replug Check are separate zero-RF sessions. Channel
and passive probes require separate explicit selected-device/session permission.
Budget counts attempts even when dispatch/acceptance is unknown, and does not
claim airtime, firmware retry or Fabric traffic counts.

Stop on ambiguous send, RF failure, unclear ownership, cleanup pending/failed/
unconfirmed or exhausted budget. Do not replay a failed RF case. U04 needs B's
exact PONG, actual B cleanup and a fresh observation of the same nonterminal A
run before asking for unplug. If prerequisites fail, physical action is NOT_RUN.
After 30 s, absence of immediate error is not detection PASS; use authorized
Cancel/Quit to settle, and replug only after confirmed owner release. No kill
is authorized or planned. Never probe a disputed owner by opening another client.

The recording UI has no live hardware-ready indication. U06/U07 are conditional
candidate actions, with receiving proven only by frozen terminal/persisted
results after action. `RuntimePhase.ready`, Device Check and prepared commit
cannot establish diagnostic readiness. A PONG remains an independent fact after
later failure. Responder stage settling after a response is valid; it need not
be receiving during the physical case. No extra reader or inbox consumer is added.

## Inherited limits and 1E handoff

Historical [1D.8 hardware results](phase-1d8-hardware-2026-11-15.md), including
initialization/network/tool failures, naturally completed Quit attempts and the
15/18 ended budget, retain their original binaries and scope. H10 never reached
ready before its planned physical action and does not prove detection/recovery.
No USB reliability fix or reliability percentage follows from a new success.

Step 10 iOS and Android API 36 arm64 dependency/API probes are inherited at
their original cut: assets, SQLite load/read/write/close and public mobile refusal.
No mobile hooks/guards/dependencies changed; beta tagging does not turn these
into mobile product acceptance. Mobile business storage, BLE, background receive,
content publication/sync and Intel runtime remain unsupported or untested.
Actual Dvorak, conflict Reload, native filename live preedit Quit, complete
Cut/Copy, remaining Full Screen/focus/accessibility and Replace/delegate variants
retain the Step 9/10 matrix status unless explicitly updated here. Unicode
paste/type is not fresh Pinyin composition acceptance.

1E still needs the distribution/legal/native-source correspondence review,
Developer ID configuration, hardened release/signing decisions, notarization,
installer/quarantine and independent clean-machine distribution validation.
This local candidate performs none of those steps and is not publicly released.

## Original build 2 automated results at the first pause

| Scope | Fresh local result | Evidence under the new root |
| --- | --- | --- |
| Four versions, five constraints, CLI constant and app fallback | PASS; beta / app +2 | R01-versions |
| Locked resolution / actual graph | PASS; root lock unchanged, 100 total resolved packages; third-party graph matches verified Step 10 cut | R02-pub, R02-graph, inherited-mobile.json |
| build_runner / schema / five tracked frozen/generated artifacts | PASS; no artifact diff | R03-generate, R04-schema/tracked/diff |
| Tracked/new Dart format and fatal-info analysis | PASS | R05-format, R05-analyze |
| App / core / CLI / link complete suites | PASS; **250 / 362 / 276 / 180** | R06-app, R09-core, R10-cli, R11-link |
| Runtime/draft/profile/device/diagnostic/history process gates | PASS; all six, synthetic device boundary where applicable | R07-* |
| Complete Python tooling | PASS; **124** after the retained version-test correction | R08b-python |
| Lifecycle/fault regressions | PASS; 16 normal cases included in discovery; the same **16** explicitly with optimized Python | R08b-python, N10-optimized |
| Product CLI / observation / acceptance complete native bundles | PASS | R12-*, cli-products.json |
| Source/AOT/whole-bundle relocation/recording/nonempty History smoke | PASS; **101** process checks | R13-smoke, smoke-recordings/process-checks.json |
| Actual dev.2 producer to beta consumer | PASS; old four-table rows/versions preserved; three new beta runs; future/corrupt main and sidecar preservation | R17-legacy, schema-compatibility.json |
| Wrong expected version/build | PASS; manifest mismatch and actual AOT recorded appVersion mismatch rejected at intended checks | V01-negative, negative-versions.json |
| Source-only peer preparation | PASS help/build only; no network, inbox or RF | V02-peer-help |
| Fresh Debug / Release complete builds | PASS; natural helper drain, no success-path termination signals | N03-build-Debug, N03-build-Release |
| Native disabled-owner XCTest | PASS; **22 passed, 0 failed, 0 skipped** | N06-xctest, native.xcresult, native-test-summary.json |
| Strict full-bundle signing | PASS; Debug/Release ad hoc, all architectures | N07-products, macos-products.json |
| Production Release runtime persistence/relocation | PASS; **3** runs | N08-runtime, runtime/runtime-processes.json |
| Normal runtime Quit | PASS; **2** cases, distinct from active hardware Quit | runtime/startup-quit.json, runtime/ready-quit.json |
| Finite SQLite native probes | PASS; write/read **2** | N09-probes, sqlite-probes.json |
| Offline normal GUI Quit and independent current CLI reads | PASS with the limited GUI observations below | gui-a-stdout.log, gui-a-reopen.json |

Native preflights retained two failed helper assertions: N02 compared lexical
/tmp versus /private/tmp paths; N05 incorrectly expected TestHostPath to include
a path inside the app. Corrections resolve the actual filesystem path and
require the exact external app bundle root, respectively. N02b also checks
RunnerTests TEST_HOST, and N05b requires disabled-owner before executing tests.
No native tests ran before the valid preflight. Early helper revisions were
reconstructed from this execution's exact edits, rather than contemporaneous
helper hashes; `helper-source.json` explicitly records that evidence limitation.
Repository per-gate source manifests and original failed logs remain untouched.
The first restricted xcresult summary read could not write Xcode's TestReport
cache; the approved read produced the actual 22/0/0 summary. No denial is counted
as another passing test.

## Final artifacts and source binding

The tested Release was copied as a complete bundle to
`delivery/Meshchan.app`; the matching complete CLI is `delivery/meshctl`.
The copy's full inventory equals the built/tested inventory, including after
GUI execution. No executable/dylib was substituted, and no re-signing was used.
`delivery/metadata/products.json` records all **41 app entries** and **3 CLI
files** (file hash/size/mode and symlink targets, plus symlink modes).
`cli-products.json` also inventories all three development/product bundles.
`resolved-native-inputs.json` hashes 276 resolved native/config inputs; the
candidate retains the lock, actual graph/package configs and generated xcconfig.

| Product fact | Observed value |
| --- | --- |
| Release Runner SHA-256 | `fd48cbf5bf9404f4f992a9dfe789d0663f0a0b06cf47f3234973167d0e7a83a5` |
| Debug Runner SHA-256 | `2a81664acfecc6345991cef543d4a43eb2c3b573a7a8a52e4ef3da955f6e50e0` |
| Release App.framework SHA-256 | `7eb5315d9eca659f7467a71749d0dd2e9bf8c3dcca48a021ae535482b4dc30f9` |
| Actual Info.plist short/build | `0.1.0.1` / `2` |
| Decoded Dart build name/number | `0.1.0-beta.1` / `2` |
| Identity | Meshchan / org.meshchan.meshchan; existing Sandbox/ownership contracts |
| OS/runtime | macOS 27.2.1 (26B131), arm64 |
| SDK/compiler | macOS SDK 27.2, Xcode 27.2 (27B52), Apple Clang 21.0.0 |
| Architecture boundary | Debug arm64; Release/embedded native assets have arm64 and x86_64 slices; only arm64 executed |

The original sqlite3 and libserialport_plus framework hashes match the locked
Step 10 native assets. Available original package/SDK/native notices were copied
separately; completeness and source/relinking correspondence remain 1E work.
`delivery/SHA256SUMS`, `delivery-prepared.json`, the final source snapshot and
final summary associate the complete products with this dirty source cut.
The focused 134-file build-source continuity check covers root/member manifests,
lib/bin and native source; it stayed unchanged from R01 through post-GUI checks.
This is not the old 271-file four-member classification (which also includes
member tests/tools/READMEs). Complete repository per-gate/final source manifests
remain the broader evidence, including later documentation changes.

## Actual offline GUI, persistence and remaining user path

Computer Use bound PID **80921** to `delivery/Meshchan.app` and the explicit
`fixtures/gui-a` directory. Public beta CLI APIs prepared only three presets
and initial Settings while the app was closed; those are not claimed as GUI
creation. GUI changed and saved `D11 PING reviewed`, changed/saved History limit
500 to **1000**, selected saved PING for Offline preview and supplied fixed
18-byte content. First preview with content not provided returned invalid_input;
the subsequent actual resolver result matched the planned channels, route,
IDs and budgets. No device operation followed this preview.

Device showed **Not connected**, **No ports have been listed or opened**, and
**Selected port: None**. History showed zero persisted rows and zero recovery.
The real system Save panel created new `offline-summary.json`, job 1 settled,
generated/admitted/published true, rows **0**, moreAvailable false. Independent
file inspection confirms only diagnosticSummaryFormatVersion 1, exportedAt and
an empty runs array. This empty export does not meet the hardware-record U08
selection/redaction assertion.

Unicode `typeText` omitted Chinese/emoji; `paste` produced AX text inconsistent
with actual rendered/controller content. Native Select All did not establish a
reliable replacement in this interaction. These are retained tooling/focus
observations, not a reproduced product regression or successful Pinyin test.
Actual explicit Save committed draft `216f422fab0e482e6bdda9f66679c87d`, title
`Beta ` (trailing space), body `GUI beta line 1\nLine 2\nLine 2`, revision **2**,
**29 UTF-8 bytes**. After confirmed shutdown, current CLI independently read
those exact bytes/revision, the reviewed preset, Settings limit 1000 and empty
History; each consumer confirmed storageClose closed and hostCleanup succeeded.
The intended Chinese/emoji GUI save and independent GUI restart remain pending.
Native runtime/process suites separately passed their fixed Unicode fixtures.

Command+Q was normal offline Quit. stdout reports resourcesReleased/workerExited
true, owner released, zero pending requests/receive ports, no maintenance failure;
it honestly retains the earlier preview invalid_input in the error field.
The launcher session completed with exit 0; external OS inspection confirmed
PID absence before independent reads. Host export was already settled. This is
not active-hardware Quit. No peer, inspector or product app remains active from
this task; no business DB was copied while live. CUA images were rendered in the
session; the available API did not expose a local PNG persistence operation.
`gui-observations.json` retains the limited facts and `gui-a-reopen.json` retains
the independent business/shutdown observations.

At pause, U01-U07 have **zero attempts**, zero inbox sessions and zero application
sends. U00/U08 have the offline component results above but their complete
acceptance targets remain blocked. Present selection/ownership/budget confirmation,
real conditional physical actions and reliable Chinese/emoji GUI input are the
remaining user-assisted steps. No successful historical or synthetic run replaces
them. The local candidate is ready for that bounded continuation, with acceptance
incomplete and no permission to infer or start extra sends.

## Continuation inputs and commands

After the operator confirms present A/B selection and exclusive clients, use
the exact peer entry reviewed by V02 from the installed bundled Dart, with the
command-local Apple Clang PATH. Private endpoint values stay in the owned files.

```sh
PATH=/opt/homebrew/share/flutter/bin:/usr/bin:/bin:/opt/homebrew/bin \
  /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart run \
  apps/meshctl/tool/openhop_peer.dart \
  --config /private/tmp/meshchan-1d11-20261116-01/hardware/b-info.proposed.json info
```

U02 uses the same source entry with a newly admitted `b-respond` config and
`respond`; U03 uses a newly admitted `b-ping` config and `ping`. The existing
`*.pending-window.json` proposals are deliberately not RF-admissible until a
fresh finite passive window or actual known timeout is recorded. They contain
only a JWT environment reference, with no token; obtain the authorized current
credential from the existing private setup without printing or logging it.
The proposals are not old manifests or a claim that a session was started.
No unimplemented U-case selector or automatic full CLI H1-H7 replay is used.

GUI launches use the exact complete `delivery/Meshchan.app` and
`--data-dir=/private/tmp/meshchan-1d11-20261116-01/fixtures/gui-a`. The current
fixture has no runs; its existing saved draft/presets/settings remain evidence.
Keep B/CLI business directories separate. Before any subsequent read/copy of
this fixture, again require actual release/worker exit and OS absence for the
new app PID. The prior offline Quit receipt authorizes only the prior process's
closed directory, not a future active owner.

## Authorized hardware continuation and build 2 crash

The operator subsequently confirmed USB A, source-only B registration/TCP mode,
independent B radio, exclusive clients and shared-inbox consumption, U01-U08 and
USB connection retries. The operational ceiling remains the concrete eight
application-send attempts; an unquantified additional allowance is not used.
Eligible zero-send/zero-consuming-read USB initialization retries are bounded to
three total invocations, each requiring prior cleanup/release. New continuation
records are under `hardware/run-01`; the original pause summary stays historical.

Fresh metadata found the selected USB path/role. Fresh B login and actual TCP
info/close passed; REST isRunning false is retained separately. The first
credential helper invocation used zsh for a bash script and failed before login;
the corrected declared-bash invocation succeeded, with no password retained and
clipboard formats restored only while its change count was still owned. A
95.004-second passive window passed with only initialization, zero inbox reads,
zero application sends and successful cleanup. The selected A slot 1/B slot 3
audit passed: equal returned 16-byte keys compared only in memory, one query
per endpoint, zero writes/RF/inbox reads, both sessions closed. No hidden
extended-key or isolated single-radio/Fabric guarantee follows.

On the unchanged build 2 Release, PID 120, the GUI explicitly refreshed and
selected A. Clicking finite Check U01 attempt 1 caused exit 134 with uncaught
NSInvalidArgumentException, AXPlatformNodeCocoa startEditing unrecognized
selector. No normal shutdown receipt exists. The Check stage was not observed;
it is FAIL, not normal cleanup/Quit PASS or an ordinary USB retry. RF diagnostic
operations have not started; application sends remain zero. OS confirmed the
PID absent and selected port without an owner; the closed crash fixture and
report were collected separately, with no normal-cleanup inference or lock deletion.

An isolated resource-free Debug fixture reproduced the same exception by
updating one SelectableText value. It contains no worker, business storage,
bootstrap grant, transport or inbox. Source, full bundle inventory and crash
output are retained. A focused software assertion also failed before correction
because readonly display semantics were isTextField. An initial clipboard test
waited on an unstubbed platform call and was explicitly interrupted; its wrapper
returned zero on SIGINT, which is not counted as PASS. A root-cwd test invocation
and a test semantics-handle lifecycle mistake are retained as tooling failures.
Corrected focused tests passed both static live-update semantics and exact
multiline Chinese/emoji selection-copy. Fatal-info analysis also required replacing
a deprecated test-only hasFlag query with flagsCollection; no lint was suppressed.

The app-level fix uses SelectionArea plus Text for selectable display labels,
leaving real editing fields and accessibility enabled. It changes no SDK/cache,
core/link/device protocol, defaults or cleanup budgets. Eighteen constructor
sites were verified and structurally rewritten with ast-grep's identifier rule.
The current repair candidate advances the app to build 3; link/core/CLI stay
0.1.0-beta.1. Build 2 binaries and all prior outcomes remain immutable evidence.
Affected app/process/Python and fresh complete native validation are recorded
below; no new hardware result is inherited across the changed app artifact.

The requested web research found the same exception signature in official
[Flutter issue 151428](https://github.com/flutter/flutter/issues/151428), closed
by [engine PR 54364](https://github.com/flutter-team-archive/engine/pull/54364)
on August 6, 2024. That change recreates the native platform node when editable
state/role changes. Its NodeDataChanged code is already present in the installed
SDK source, so the historical closure does not prove this current reproduction
fixed. [RustDesk's firsthand discussion](https://github.com/rustdesk/rustdesk/discussions/7766)
contains old-version workarounds and reports of improvement with a later arm64
nightly; paste did not help every reporter. No exact stable Flutter version is
asserted to fix this current trigger. SelectionArea is a supported selection
mechanism per [the official API](https://api.flutter.dev/flutter/material/SelectionArea-class.html);
its use here is a locally tested app-level mitigation, not an upstream-prescribed
workaround or a claim that the whole engine defect has been fixed.

Build 3's complete app suite passed **252** tests, including the two new focused
regressions. All six affected process gates and complete Python discovery
(**124**) passed. The lock remains unchanged after locked resolution and the
actual graph is retained separately. Fresh Debug/Release/native/runtime gates
are recorded under D11-b3-*; no build 2 native result is silently relabeled as
build 3. The old complete CLI/core/link results remain at unchanged consumer
inputs; the app display fix and app build metadata do not change those products.

## Build 3 native results and GUI continuation

Fresh external Debug/Release builds, strict signatures, disabled-owner native
XCTest **22 passed / 0 failed / 0 skipped**, three runtime runs, two normal
runtime Quit cases and two finite SQLite probes all passed. The exact Release
copy is `delivery-beta1-build3/Meshchan.app`; the complete CLI remains unchanged.
`hardware/run-01/delivery-build3-prepared.json` binds the complete products
manifest SHA-256 `e29ea92734ba09ddb2618c0842cff187df0656720ace4692cd4e817d59d97420`.
The Runner SHA-256 is
`66e3b1982998a982f3589418a70941948b83ec83d3cbe4d29b6149160ed20622`.
Info.plist is short version `0.1.0.1`, build `3`; decoded Flutter defines are
`0.1.0-beta.1` / `3`. The full inventory, rather than Runner alone, identifies
the tested product. macOS runtime was arm64; an x86_64 slice is not a runtime test.

U01 attempt 2 on this Release, PID 21523, passed via actual host GUI Refresh,
explicit selection of USB A and finite Check. Check 1 closed with session
cleanup and host observer cleanup succeeded. The GUI returned to Not connected
and retained a dated historical snapshot, observed at
`2026-11-16T06:33:53.354619Z`. This is a new Check result, not evidence that a later
recording is ready. Returned model/firmware and RF metadata are retained privately;
the A/B RF parameters agree. No application send or queue read was needed.

U02's B responder reached Companion initialization and naturally ended its
60-second window. It reported zero response attempts, one completed consuming
read, no entries, successful cleanup and actual process exit/reap. The A GUI
PING Start was **rejected before execution by automatic approval review**:
`peer_session_ready` proves initialization only, not active responder reception.
The rejection, A-not-started fact and complete B lifecycle remain in
`hardware/run-01/U02-blocked.json`. U02 is BLOCKED, with zero RF sends; the
rejected action was not repeated through another tool or CLI. Restarting that
consuming B session is a new concrete attempt, not a silent retry.

While selecting the next preset, AX menu clicks did not establish controller
selection. Keyboard End/Return, then a later Escape observation, were followed
by a blank window and sustained high CPU. A sample at 06:50:48 UTC showed the
FlutterKeyboardManager/FlutterChannelKeyResponder redispatch path. Native menu
Quit ended PID 21523 with exit 0, but **no shutdown report was received**; this
does not establish normal resource release. No diagnostic task had started.
The fixture was copied only after OS PID absence, with this abnormal/unconfirmed
classification. Independent public CLI reopen then succeeded for Drafts,
Profiles, Settings and empty History, and each new consumer confirmed close.
That reopen does not retroactively prove old cleanup. A leftover resource-free
reproduction process was identified separately and closed by its native menu;
it held no business data or device.

The requested upstream search also found
[Flutter issue 189722](https://github.com/flutter/flutter/issues/189722), still
open when verified on November 16. It describes a similar macOS Accessibility
key-injection redispatch loop, including a minimal stock app, and has no known
verified workaround in the report. The local stack is consistent with that
signature, but root-cause identity is an inference. Neither report establishes
ordinary physical keyboard reproduction. Its alternative event injection is
not adopted: host GUI continues to follow Computer Use. No SDK patch, speculative
native keyboard interception or accessibility disabling is introduced.

A fresh launch of this same Release, PID 32426, rendered the normal Drafts and
held storage without any automatic port listing/selection or diagnostic task.
Pointer-only native menu Quit produced the actual shutdown report:
resourcesReleased/workerExited true, owner released, no maintenance failures,
zero pending requests/receive ports. The process exited 0 and OS PID absence was
confirmed without querying a closed app. This is an offline normal Quit result,
not U07 active-hardware Quit. `app4-stdout.log` retains the report. The earlier
blank-window attempt is retained separately.

The source-only peer now has a narrow transport evidence adapter for respond.
It forwards the existing single stream and operations; the first existing
GET_MSG write completion emits `peer_receive_read_written` with a UTC timestamp.
It adds no reader, subscription, GET_MSG, session getter, retry or command.
This witness is stronger than initialization alone, but does not prove a remote
message, successful response or continued liveness. It must be correlated with
the same still-active finite peer process. The product app remains unchanged.
New regressions check exact forwarding/no added operations, one event only after
successful write, failed-write refusal, and event integration before cancellation
cleanup. An initial test-fixture close lacked a listener and hit the existing
30-second test timeout; that failure remains classified, and the fixture lifecycle
was corrected without changing production timeout or weakening assertions.

Complete source-peer follow-up gates passed: CLI **278**, Python **124**, fatal-info
analysis, format, whitespace and actual help. Receipts are D11-peerobs-* in the
same ledger. The full CLI suite adds two adapter regressions to the earlier 276;
the existing active peer cancellation test now also verifies the real witness's
order and limited fields. Source-only tool changes do not change product CLI
compilation inputs or the tested app, and do not add a hardware success.

## Build 3 pause before replacement U02 authorization

| Case | Current result | Established facts and remaining target |
| --- | --- | --- |
| U00 | Partial; full target NOT_RUN | Offline preset/settings/draft saves, preview and no automatic device access observed; intended Chinese/emoji GUI content remains pending. |
| U01 | PASS on build 3; build 2 crash retained | Explicit selection and finite Check closed; historical snapshot and separate cleanup facts retained. |
| U02 | BLOCKED | One B finite responder session ended with cleanup and zero sends. Automatic approval rejected A Start before execution; actual current exact GUI PONG not established. |
| U03/U04 | NOT_RUN | The Responder preset selection was not established before the input-path failure. No A responder, B PING or physical unplug occurred. |
| U05 | NOT_RUN | No no-responder PING was started; responseTimeout target remains unestablished. |
| U06 | NOT_RUN | No active recording Cancel; receiving-stage terminal evidence remains required. |
| U07 | NOT_RUN | Offline normal Quit does not establish active hardware Quit. |
| U08 | Partial; full target NOT_RUN | Closed-fixture CLI reads and empty safe export are limited results; nonempty current hardware History and one-page export remain pending. |

Application sends remain **0 / 8**, with no uncertain send or hidden RF retry.
The B consuming read in the blocked U02 remains counted even though it returned
no entry. All product, reproduction, peer and independent CLI processes from
the continuation are closed at this pause. The last ordinary app Quit has its
actual resource/worker/owner report. The earlier unconfirmed shutdown remains
unconfirmed. No live database copy, lock deletion or force termination was used.

Remaining assistance is specific: allow one replacement B finite responder
session for U02 (60-second listen, maxResponses 1, existing budgets and the same
eight-send ceiling), then correlate the new read-write witness and fresh live
process before the existing authorized GUI PING. Manual physical keyboard/mouse
help may be needed if Computer Use preset/key operations fail; do not change
the SDK or input source to obtain a pass. Chinese/emoji content must be entered
into the owned fixture and explicitly saved, then independently read after normal
Quit. Physical unplug/replug is requested only later, after a real matching B
PONG proves the same active A Responder and a fresh GUI observation shows it
still nonterminal. No physical action is requested at this paused point.

The complete build 3 local candidate and manifests are prepared, but neither
1D.11 nor full 1D is accepted. Mobile, BLE, Intel, historical USB reliability,
remaining GUI/IME variants and 1E distribution limits above remain unchanged.

The finite final continuation check D11-b3-final-checks passed: all 82 preceding
gate receipts/log hashes agree, including five retained non-PASS gates; all five
finite peer/CLI command receipts/logs agree and confirm reaping. Exact product
compilation inputs still match their builds (72 CLI inputs and 136 combined
app/native/CLI inputs under that check's explicit filter). Complete app/CLI
file, symlink target/mode and strict signature checks passed without rebuilding
or substituting bundle members. After the last confirmed normal app Quit,
the current CLI independently read the original exact draft title/body,
revision 2 and 29 UTF-8 bytes and closed normally. These counts describe the
recorded filters, not a claim that the old 271-input list is unchanged.

`source-build3-paused/` and its JSON/diff freeze this repository cut. Current
delivery metadata retains both packaging and final source cuts, original
prepared checksums, final checksums and acceptance status; the earlier
`source-final/`, `final-summary.json` and build 2 delivery remain historical.
Raw databases, secrets, crash reports, screenshots and private peer plans stay
outside the deliverable products and Git. No commit/push/PR or public release
was performed in this session.

## Authorized replacement U02 and requested pause

The operator explicitly authorized one replacement B finite Responder session,
keeping the proposed parameters, and requested a pause after this item because
manual input assistance was unavailable. An additional unquantified send
allowance was offered; it was not needed or used. The operational ceiling stays
eight application-send attempts. No later U-case or physical action was started.
New owned evidence is `hardware/u02-replacement-01/`; the previous blocked
attempt and first build 3 pause remain historical.

The exact complete build 3 Release/CLI inventories and source cut matched the
prepared candidate before use. Existing credentials were refreshed through the
configured helper, with password only in memory, JWT in an owned 0600 file, and
clipboard restored only while its change count remained owned. No credential,
configuration or security setting was changed. The app PID was 41665, launched
from `delivery-beta1-build3/Meshchan.app` with the explicit `fixtures/gui-a`
directory. GUI Refresh listed local metadata; the user-selected USB A was
explicitly selected. No extra Check was run before PING. The actual Preview
matched the saved PING preset, fixed 18-byte content, A/B IDs, Direct/empty route,
slots 1/1, request/init/task/response 15/30/60/15 seconds, startup 0 and 128 entries.

B PID 43004 used the explicit selected TCP mode, request/init/task 15/30/90
seconds, listen 60 seconds, maxEntries 128, maxResponses 1 and startup 0. The
source peer emitted exactly one `peer_receive_read_written` at
`2026-11-16T07:20:10.489342Z`, from the existing task-owned GET_MSG write.
This evidence was read from the same running finite process before the actual
GUI Start. It proves the consuming-read write, not a remote message or future
health. The new Start was allowed and executed; no alternative tool was used to
replay the earlier rejected action without its missing prerequisite.

The GUI committed run `e91733230cfe9c02dcfc387b186d210f`, host attempt 1,
gate lease 2, appVersion `0.1.0-beta.1+3`, at
`2026-11-16T07:20:20.887618Z`. Logical end was
`2026-11-16T07:20:35.902929Z`:

| Fact | Actual result |
| --- | --- |
| Case assertion | **FAIL**; USB initialization prerequisite failed, exact PONG not established |
| Primary reason / stage | initializationFailed / connecting |
| Session failure | requestTimeout / initializing; command opcode 22, expected response opcode 13 |
| A sends / receiving | attempted false, pending false, reception null, processed entries 0 |
| RF round trip | matching PONG false, exact content false, roundTripSucceeded false, successful RTT null |
| Core / core-managed subscription cleanup | succeeded / notRequired; aggregate succeeded |
| GUI observer / settlement | observer succeeded, core done observed, adapter settled, resources confirmed released |
| Saves | Registration/logical/cleanup committed; five observed save attempts; final cleanup save committed and finalCleanup true |
| Persisted state | settled; no recovery timestamp/reason; original primary failure and nullable send facts retained |

This is not the expected responseTimeout case, an RF loss measurement, a
successful round trip, or proof that historical intermittent USB initialization
has been repaired. At A's logical end, B's planned window had only **34.586413
seconds** remaining, less than the complete 30-second initialization plus
15-second response budgets. No USB retry was started inside that insufficient
window, and no second replacement B session or RF retry was made.

B naturally ended at its duration limit, cleanup succeeded and exit 0 was
reaped. It reported **6 published/processed entries**, **9 dispatched/completed
consuming reads**, **0 response attempts**, and **0 local responses confirmed**.
Those shared-inbox entries are real consumption even though no test PONG was
sent; no bodies/raw frames were logged. Actual application sends are **A 0 + B
0 = 0**, still **0/8** for this task. An initialization failure does not erase
the peer's consuming session.

GUI History read the same committed settled run and failure. Device then showed
Not connected. A normal native-menu Quit produced resourcesReleased and
workerExited true, owner released, zero pending requests/receive ports and no
maintenance failure. OS confirmed app/peer PID absence before the current native
CLI independently opened this run. The CLI confirmed exact ID/version/config,
the same primary failure, cleanup aggregate succeeded, settled state and null
recovery; its storageClose was closed and hostCleanup succeeded, with exit 0
reaped. Only after all consumers had exited was the owned fixture copied.
`result.json`, the two finite command receipts/logs, GUI observations, shutdown
output and `closed-fixture/` preserve those distinct layers. CUA screenshots were
rendered in the session; no unsupported local PNG persistence API was invented.

The candidate remains **prepared / acceptance incomplete**, with this executed
U02 prerequisite failure explicitly retained. Current PONG, Responder, expected
responseTimeout, active Cancel/Quit, physical unplug/recovery and the complete
Unicode/nonempty-export path remain unestablished. There were no product input
changes, rebuilds or software failures in this continuation; earlier software
and native results remain at their documented cuts. The operator-requested pause
is now in effect, with all related processes closed. No additional confirmation
or immediate physical/input action is requested.

`source-u02-replacement-paused/` freezes the subsequent documentation/source cut.
Delivery metadata keeps the prior acceptance/source/checksum records alongside
the updated current index; `final-summary-u02-replacement-01.json` is the latest
owned summary. The tested app/CLI product inventory is unchanged. No required
software/native gate is rerun for these documentation-only updates, and no
unexecuted hardware assertion is promoted to PASS.

## One explicitly authorized U02 retry, then stop

The operator subsequently allowed one more B finite Responder session and one
U02 retry, with every parameter unchanged, explicitly requiring stop if USB
initialization failed again and continued pause afterward. No manual input or
physical action was requested. New owned evidence is
`hardware/u02-replacement-02/`; the blocked attempt and replacement 01 remain
unchanged historical evidence. The same complete `0.1.0-beta.1+3` Release/CLI
inventories were verified before use, with no rebuild, timeout/startup-delay
change, firmware/channel/route adjustment or new product source.

The app PID was 92489 with the same explicit owned data directory. GUI preparation
initially showed deferred AX updates and a coordinate noWindowsAvailable error.
Bundle-ID-only selection was rejected as ambiguous, so the exact registered
`/tmp` path was used (the same resolved `/private/tmp` artifact). Native Window
selection and moving only this test window to the built-in display restored
observable updates. This used Computer Use throughout, changed no system display
or input-source setting, and added no device open. The actual fixed text and
18-byte controller value then matched; the actual Preview again matched the
saved PING preset and unchanged 15/30/60/15-second budgets, slots/IDs/Direct route,
zero startup delay and 128 entries. B was not started during that preparation.
Fresh existing-credential login succeeded, with the same private file/clipboard
ownership discipline; no credential value was added to Git or the product.

Exactly one B PID 95935 used the same TCP mode and 15/30/90-second budgets,
60-second listen, maxEntries 128 and maxResponses 1. Its actual first existing
GET_MSG write witness was `2026-11-16T09:31:05.383460Z`, read from the still-running
finite peer before exactly one GUI Start. Run
`c286338ed69b459ade28faa4c62f3879` registered at
`2026-11-16T09:31:13.275881Z` and logically ended at
`2026-11-16T09:31:28.288437Z`, appVersion `0.1.0-beta.1+3`:

| Layer | Actual result |
| --- | --- |
| U02 assertion | **FAIL**, repeated USB initialization prerequisite failure; exact PONG not established |
| Primary reason/stage | initializationFailed / connecting |
| Session failure | requestTimeout / initializing, command 22 (0x16), expected response 13 (0x0D) |
| A application send/receive | attempted false, pending false, reception null, processed entries 0 |
| Round trip | matching PONG/exact content/roundTripSucceeded false, successful RTT null |
| Cleanup | core succeeded, core-managed subscriptions notRequired, aggregate succeeded; app observer succeeded and resources confirmed released |
| Saves | Registration/logical/cleanup committed; five observed save attempts, finalCleanup true on final committed cleanup save |
| B finite terminal | durationElapsed, cleanup succeeded, exit 0/reaped; 36 entries published/processed, 37 reads dispatched/completed, 0 response attempts/confirmed responses |
| App shutdown | Normal native-menu Quit; resourcesReleased/workerExited true, owner released, zero pending requests/receive ports, no maintenance failure; OS PID absent |
| Independent persistence | Current CLI read the same settled failure/version/config, null recovery and succeeded cleanup, then confirmed storageClose closed/hostCleanup succeeded and exit 0/reap |

The stop condition was met. No second Start, additional B session, USB/RF retry,
device Check, input-method test, unplug/replug or later U-case followed. B was
allowed to finish naturally inside its unchanged finite window. Current
application sends are **A 0 + B 0**, still **0/8** overall. All finite B sessions
so far consumed 42 entries in 47 completed reads (blocked 0/1, first replacement
6/9, this retry 36/37); these are shared-inbox consumption, not application-send
or airtime counts. No consumed bodies/raw frames were logged.

GUI History retained the new settled record and Device returned to Not connected.
After confirmed normal release and app/peer OS exit, separate finite public CLI
consumers checked the new record and compared the prior run's entire persisted
projection with its original captured projection: unchanged. Both consumers
closed normally and were reaped before the owned fixture was collected. The
new result, GUI facts, command receipts/logs, shutdown output and closed fixture
remain separately indexed. Native screenshots were rendered in the CUA session.

The copied evidence verifier initially retained the previous case label in its
budget-publication guard and exited 1 after its evidence comparisons. That tool
failure, verifier bytes and provisional result were preserved. The exact label
was corrected; the rerun also verified the already collected closed fixture's
full inventory and succeeded, without repeating hardware, deleting evidence or
weakening assertions. This is a bookkeeping correction, not a new hardware pass.

The failure pattern remains unexplained; these two attempts do not identify its
root cause or establish a USB reliability percentage. The current GUI RF target
is still unmet. The candidate remains prepared / acceptance incomplete, and the
operator-requested pause is effective with every task app/peer/consumer closed.
Product compilation inputs and complete tested bundles remain unchanged; only
documentation/evidence metadata is updated, so no software/native suite is
repeated for this continuation. A final privacy check found a private management
host in a historical documentation line already present in HEAD. The current
line was redacted without changing its original test facts; the audit rejection
and earlier source cuts remain retained, and the same strict audit is rerun.
`source-u02-retry2-final/` freezes the latest
source cut, and `final-summary-u02-replacement-02.json` is the latest owned index.
Earlier source, acceptance and checksum cuts are retained alongside it.

## USB initialization investigation after the requested pause

The operator requested official Heltec V4.3 / MeshCore firmware research and
reported a likely standard 2 MB PSRAM board installed from the official flasher's
Heltec V4 Companion USB v1.18.0 selection. The separate
[USB initialization investigation](phase-1d11-usb-initialization-investigation.md)
records pinned sources, offline official firmware inspection, related Espressif
HWCDC fixes, historical POSIX evidence and a finite proposed diagnostic. Firmware
HWCDC transmission is the leading direction, but the current attempts have no
native byte trace and their root cause is unconfirmed. No new device operation,
RF attempt, firmware change, product rebuild or hardware PASS occurred. The
candidate remains prepared / acceptance incomplete and hardware work stays paused.

The operator then explicitly authorized one A-only native initialization trace,
with B closed, zero application sends/inbox reads, original deadlines and no
retry or firmware change. The new source-only diagnostic and eight regressions
passed analysis, the full **188-test** link suite and native bundle build after
a preserved initial constructor-call analysis failure. The sole actual attempt
at 10:48:15 UTC reached ready: native writes accepted 5/5 DEVICE_QUERY and 19/19
APP_START bytes; complete DEVICE_INFO (82 content bytes) and SELF_INFO (64) were
received. Reader stop, close/dispose, OS exit/reap and absent port owner were
confirmed. App/CLI complete inventories are unchanged. No RF case was rerun.

The [detailed trace and Offband review](phase-1d11-usb-initialization-investigation.md#one-authorized-native-traced-initialization)
preserves chunk/notification counts, hashes, limitations and the adoption
decision. This one source initialization PASS does not reproduce/explain either
GUI timeout or establish U02. Offband's device-side ZLP predicate does not arm
for our normal 85/67-byte frames, and its production-instance hardware follow-up
remains open. No unverified firmware/client workaround was adopted. The
candidate remains prepared / acceptance incomplete; all task consumers are
closed and hardware acceptance remains paused.

A later, separate authorization allowed at most three further A-only traced
initializations, B closed, zero application sends/inbox reads, identical budgets,
stopping at the first failure. The unchanged complete diagnostic bundle produced
PASS at 11:47:34 UTC and 11:50:03 UTC, then **FAIL at 11:52:37 UTC**, after which
all hardware work stopped. The failed attempt accepted both native writes (5/5
and 19/19), received complete DEVICE_INFO, then only the three-byte header for a
64-byte body. APP_START ended in requestTimeout at its original 15-second deadline;
final trace projection was received 3 of 67 bytes. Reader stop, port close,
dispose, OS exit/reap and absent port owner were verified for every attempt.

The [three-attempt comparison](phase-1d11-usb-initialization-investigation.md#three-further-authorized-attempts-and-gui-comparison)
records the GUI/worker/storage differences and matching arm64 native code-section
hashes. The fresh failure demonstrates that the GUI is unnecessary for this
header-only symptom, but it is at APP_START rather than the two GUI failures'
DEVICE_QUERY stage. No common exact cause or reliability rate is asserted.
A structural regression added after hardware stopped passed with analysis and
the complete **189-test** link suite; the executed diagnostic and delivered
products were unchanged. Evidence is `hardware/usb-init-trace-series-01/`.
The three-attempt allowance is exhausted, no further hardware was run, and the
candidate remains prepared / acceptance incomplete.

The operator subsequently authorized ten more zero-application-send/zero-inbox
initializations, allowing known failures to continue after verified cleanup.
The fixed five-pair [native/POSIX control](phase-1d11-usb-posix-controls.md)
completed 10/10: eight passes and two APP_START timeouts. Native attempt 7 and
independent POSIX attempt 8 both received only the header of a 64-byte body.
The POSIX deadline observations showed FIONREAD 0, select not readable and final
read 0, without Dart/libserialport. Another POSIX case delivered the body with
later device data after about 5.826 seconds, without a repair query. These are
fresh initialization observations, not GUI/RF passes or proof of a particular
firmware/host-driver cause. All ten had confirmed close, OS exit/reap and absent
port owner. The new source control passed 11 focused / 135 complete Python
tests; the hardware-free worker process gate and pure-codec plan checks passed.
The delivered beta app/CLI inventories, product sources, lock and firmware are
unchanged. The allowance is exhausted, further hardware is paused, and candidate
status remains prepared / acceptance incomplete.

After the operator requested a consecutive-request solution, a separate
[finite completion-query candidate](phase-1d11-usb-completion-candidate.md)
was implemented in source tooling only. It sends QUERY, QUERY, APP_START, QUERY
and requires complete original/probe replies within the unchanged deadlines.
Its final software cut passed analysis, 196 link tests, complete native bundle
build and inert entry guards. At that preparation cut, candidate hardware was
NOT_RUN and the four proposed checks required a new allowance. No delivered
product or GUI/RF result changed.

The operator then explicitly authorized the four-case
standard/probe/probe/standard comparison. All four ran once on the same complete
candidate bundle at 15:14:18–15:14:28 UTC and **passed**. Both probe cases received
all three DEVICE_INFO replies and the original SELF_INFO, with a complete final
input projection. Every case confirmed known full writes, reader stop, close,
disposal, natural OS exit/reap and absent port owner before the next case.
Actual totals were 12 initialization control frames / 116 serial bytes, zero
application sends, zero inbox reads and zero B sessions, within the approved
scope. The allowance is exhausted and hardware is paused. Because both standard
controls also passed, this establishes bounded feasibility rather than a proven
reduction in intermittent failures. The candidate remains source-only; the
delivered beta inventories and all incomplete GUI/RF/physical assertions retain
their previous status. Exact traces, source/binary binding and limits are in the
[completion-query comparison](phase-1d11-usb-completion-candidate.md#executed-four-case-comparison).
