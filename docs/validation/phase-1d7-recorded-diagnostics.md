# Phase 1 / 1D / Step 7 — Recorded diagnostics

## Baseline and source identity

On November 14, 2026, the GitHub API confirmed PR #32 closed/merged, head
`cc0b032e97f518c5879a3286a8429553d85b055f`, base
`46c8937bee0d7d86d6bf700dbe45cad53a3126b0`, actual merge/master
`e92c5487243f17467f1030cfb426b8e063c3a90c`. Local master matched that actual
merge and had no dirty/untracked work. Work continued on
`codex/phase-1d7-recorded-diagnostics`; no old head was restored or cherry-picked.
Implementation and validation initially used an uncommitted working tree on that
baseline. The user subsequently authorized committing, pushing and opening a PR;
the publication check below records that source boundary. No tag, release, public
binary upload or production deployment is included.

Final source, status and full copied bundle SHA-256 manifests are retained outside
Git at `/private/tmp/meshchan-1d7-validation/`. The initial implementation cutoff
was exercised by the complete 197-test app run, Debug/Release builds, native host,
process gates and VM fixtures described below. The later closeout section records
the final 200-test run and rebuilt products after the admission/input-identity
corrections. Documentation and test-driver additions do not change the product
binary. Raw fixtures, screenshots, native test products,
binaries and logs are not committed.

The later post-review override-composition fix has a separate **202-test** app
validation below. Earlier native/GUI products keep their recorded source cutoffs;
they are not claimed to contain that subsequent presentation fix.

Toolchain: `/opt/homebrew/bin/python3` **3.15.2**;
`/opt/homebrew/share/flutter` **3.47.9 stable**, bundled Dart **3.13.7**, arm64
macOS **27.2.1 (26B131)** host, Xcode **27.2 (27B52)** and Apple Clang
**21.0.0**. Native commands use a process-local Apple-compiler-first PATH:
`/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin`. No global PATH, SDK, channel,
interpreter, cache sources, privacy, signing policy or keyboard settings changed.

## Delivered behavior and identities

Diagnostics provides explicit single PING and finite Responder. Its application
model owns override presence, selected/default profile ID, exact invocation text
or hex, preview generations and captured local input across navigation. Missing
content differs from empty bytes; text uses exact validated UTF-8 and hex retains
the existing strict ASCII/even-length syntax. No dataType editor or send/listen
execution path was added. Resolver precedence and independent descriptor/path
merging remain core behavior; presets are validated before overrides, and null
profile selection still means settings default.

The Device session selection is independent of resolution: an available exact
path from a successful nonstale list is required by the UI. Constructors,
navigation, profile reads and previews do not enumerate/connect. Neither hints,
last information, Device check budgets nor historical paths authorize a start.
Inputs are copied on Start; worker resolution, not preview output, is authoritative.

`StartRecordedDiagnostic`, `DiagnosticHandle.accepted` and
`CancelRecordedDiagnostic` are app contracts. Worker generation, RPC ID, host
attempt ID, gate lease and core run ID are distinct. The worker installs the gate,
initial attempt and complete device barrier synchronously, then quickly ACKs
admission. Only resolution joins the existing database queue. Hardware, cleanup
and save settlement never occupy an ordinary RPC. Core `record()` retains its
synchronous validation and registration-commit-before-lazy-factory contract. A
fresh serial transport is supplied for the captured exact path. Recorded app
version comes from Flutter build defines, defaulting to `0.1.0-dev.3+1`.

Scoped Cancel latches before record or immediately forwards to core after record;
it neither pauses offline business nor calls global Stop. Pre-record cancellation
has no fabricated logical result/run ID. Same-stack post-record cancel still
registers a real canceled run if registration succeeds. Late local errors and core
logical failure remain authoritative. True Stop/shutdown stays irreversible through
late ACK, resolution and finalizer delivery. Shared Refresh/Check/record admission
and identity-checked release prevent concurrent or stale device actions.

## Outcomes, privacy and shutdown

The adapter retains complete public Ping/Respond summaries, both cleanup scopes,
controlled failure details, safe committed run snapshots, phase save states,
finalCleanup and the authoritative final save-attempt sequence. Streams are
nonreplaying; named Futures and done repair missed broadcasts. Final cleanup
cannot regress to a late intermediate update. Named phase-save Futures also
retain authority before done, including cleanupSaved with finalCleanup=false. App observer cancellation is
independent of core-managed host subscriptions, attempts each subscription even
if another fails, and joins the full settlement barrier. Observation faults
preserve known results and block admission.

Null, false and zero remain distinct. Application RTT uses only applicationRttUs;
first matching PONG elapsed is separately labeled. Match/content evidence can
survive write failure without a successful RTT. Successful RTT survives cleanup
or save failure. Responder zero-response completion establishes no round trip;
local confirmations do not establish peer receipt and lastSend describes only the
last send. Real core zero-response Responder supplies an unattempted SendFacts
rather than null; the app preserves that actual value and also supports nullable
lastSend from the public model.

Resource release requires settled observations and successful/notRequired core,
host and aggregate cleanup, with no observer or explicit resource-uncertainty
failure. Save failure alone does not hold device resources. Pending, failed or
unknown final cleanup never frees the lease; quarantine retains the owner.
Pre-record work releases only after accepted local work settles without resource
uncertainty. No timer, cancel Future, logical result, done alone or fullySuccessful
boolean substitutes for release evidence.

The healthy occupied exception covers tracked recording resolve/prepared/running
and normal pending cleanup. Initial unconfirmed is not automatically a fault;
known scope failures, observer loss and cleanupUnconfirmed block the exception.
Target/document/session/stable-ID binding and the at-most-once final Save remain.
Continue preserves the task; Save/Discard precedes shutdown. One quit coordinator
waits database/device/app observation barriers, maintenance, storage close, owner
release ACK and actual worker exit. Storage close retains final drain duties;
no nonexistent final-unpin notification was added.

Safe result projection accepts public whitelist models only. It contains no raw
request/effective parameters, selected port, full route, endpoint IDs, nonce,
content, profile name, keys, frames, native cause/stack or arbitrary exception
text. The separate local input UI can display the explicitly selected/captured
port. No private core/link imports, SQL, StorageHooks, second task/session path,
second inbox consumer or new dependency was introduced.

## Software and native evidence at the initial implementation cutoff

All Flutter/Dart suites, process native hooks and builds ran sequentially in this
workspace. Logs and result JSON are in the external validation directory.

| Gate | Current result |
| --- | --- |
| `flutter pub get --enforce-lockfile` | PASS; root lockfile/manifests unchanged |
| Core `dart run build_runner build` and `dart run tool/check_schema.dart` | PASS; schema/generated artifacts unchanged |
| Root fatal-info analysis | PASS; no issues |
| Repository source Dart formatting | PASS; 200 files, zero changes |
| `git diff --check` | PASS |
| Complete app `flutter test --no-pub --concurrency=1` | PASS, **197/197** |
| Runtime/draft/profile/device process gates | PASS, all four current commands |
| `check_diagnostic_process.py` | PASS, **5 scenarios**, real worker/core/SQLite and public fake transports |
| Complete core `dart test` | PASS, **362/362** |
| Complete link `dart test` | PASS, **180/180** |
| Complete CLI `dart test` | PASS, **271/271** |
| Python tool unittest discovery | PASS, **65/65** |
| Fresh macOS Debug and Release builds | PASS, copied whole apps outside repository |
| Debug/Release `check_macos_runtime.py` | PASS; owned SQLite, startup/live-owner quit, independent reopen and relocated signature |
| Isolated native XCTest | PASS, **11/11**; disabled-owner plan checked before execution, external copied test products and execution derived data |
| Three fresh CLI/observation/acceptance native bundles | PASS |
| Source/AOT/relocated native smoke | PASS, **101 process checks** |

New app cases cover lexical/presence/byte handling, frozen exact input, stale
preview, mouse pointer-down composing guards, nullable outcome rendering, real
recorded PING and zero-response finite Responder, fresh check/record transitions,
18 dirty-quit cases, and 7 direct worker admission/health scenarios. Public fake
RecordedOperation tests cover missing broadcast replay, late pending updates,
independent save/cleanup failures, known scope failure with aggregate pending,
PONG-before-write-failure and RTT-before-cleanup-failure, nullable Responder facts,
Future/stream errors and independent app subscription cancellation failure.

The diagnostic process gate covers delayed Start ACK with responsive scoped
Cancel/GetStatus; resolve blocked before record; cancel with no factory/run;
actual Stop and late resolve; same-stack post-record cancel before factory
admission; successful fake PONG followed by pending/failed cleanup; owner
contention; one-use Draft/Profile/Settings final saves and Continue; close/worker
barriers and independently reopened committed history. Fault-child process exit
is explicit reclamation, never a normal-close pass. Product bootstrap exposes no
fixture transport or test-worker option. Both CI jobs invoke the new deterministic
hardware-free process gate.

Development failures remain separate evidence: the initial inherited Homebrew
LLVM native hook failed before process tests began; the documented Apple-first
rerun passed. Early tests found obsolete placeholder expectations, a paused legacy
resume condition, test-fixture wait ordering and the real zero-response lastSend
shape; those were corrected before final runs. A final review added the named
cleanupSaved ordering guard (including finalCleanup=false), then reran all 197
app tests, the 5 diagnostic process scenarios, analysis and fresh app/runtime
builds. The incremental Debug rebuild passed three real runtime processes but
failed relocated strict signature verification (nested code invalid); the failed
artifact and signature receipt were retained. Fresh external Xcode derived-data
and product directories were used for the following rebuild, without changing
SDK/cache sources or signing policy. The unchanged native XCTest/CLI/core/link gates preceded only this
adapter-specific guard; their scope is recorded separately. A root formatter also encountered
five preexisting ignored historical Dart artifacts under build/; those artifacts
were preserved. Final formatting covers tracked and nonignored new repository
Dart source, matching a clean checkout's source set.

## Actual GUI, IME and hardware boundary

The repository macOS VM GUI skill and guide were read before execution. The
existing authenticated executor verified VirtualMac hardware UUID/console user
and used guest-side input/focus/screenshots over SSH. No host pointer/keyboard,
VM native Refresh, USB passthrough or SPICE hardware attempt was made. The initial
run is `20261114T152309Z-product-975`, with separate owned Debug/Release bundles,
fixtures, PIDs/argv and source executable hashes in
`/private/tmp/meshchan-1d7-vm/session.json`. Debug normal Continue/Save and
Release Continue/Discard each confirmed release, worker exit and zero pending
requests/receive ports. Independent public-runtime reopen of the collected closed
fixtures verified the saved Debug Draft and empty Release Draft list. A fresh
final-bundle GUI run is `20261114T154003Z-product-12096`, recorded separately at
`/private/tmp/meshchan-1d7-vm-final/`. Both final bundles completed the same
Pinyin/guard/natural-commit/navigation/no-port/invalid-preview workflow, followed
by Debug Continue/Save and Release Continue/Discard. Both normal receipts prove
owner release, worker exit and zero pending requests/receive ports; independent
public-runtime reopen again confirmed Debug Save and Release Discard. Final
product PIDs were 14002 (Debug) and 17386 (Release). Executable SHA-256 values:

- Debug: `211eddbe07d39bb36f7cecf06338aad05f1f0d0194e02ad84bf0be18dbb31db4`.
- Release: `4e61b13892997b96d38547d06c02f79c5ff9bd10f68cccd64266f95ae6613bc3`.

Full final bundle inventories and source/status manifests are retained in the
external validation root; executable hashes alone do not identify Flutter assets.

Debug and Release each exercised Diagnostics PING content with real Pinyin:
original marked `zhong wen`, the `中文` candidate, exact foreground/focus PID and
selection were reviewed before guarded menu/content-mode/navigation/Command-Q
operations and natural Space commit. Exact committed `中文` and cross-navigation
retention were checked separately. No-port Start remained disabled; Preview
returned actual resolver invalid_input for the deliberately incomplete request.
Operation switching, dirty offline Continue and normal Save/Discard quit are
recorded independently of fake radio tests. GUI observations do not establish a
live recording, RF or successful serial initialization.

One Release SSH wait timed out after posting its key job. Its existing receipt
was inspected (exit 0) and the exact live product argv verified; input was not
repeated. Screenshot/focus collection then resumed for that same composition. An initial
Debug offline follow-up was refused because Release held foreground; no input
was attempted, and explicit activation preceded the successful Debug sequence.
Both the initial and final fresh Release VM screenshots show text raster artifacts outside the focused
content/candidate region. They are preserved as an observed visual limitation;
no cause, SDK fix or full visual-cleanliness pass is claimed. The focused marked
text/candidate and exact AX content checks remain separate evidence.

Host real USB metadata/check/PING/Responder, real RF PONG/RTT, hardware Cancel and
quit while hardware is active: **NOT_RUN**. This task supplied no current exact
host port or corresponding channel/test-ID/route/finite-budget/peer authorization.
Historical 1D.6 check permission and paths were not reused. No radio config,
retry/reconnect/resend or timeout policy was changed. Physical RF and 1D.11
stability/unplug/beta acceptance remain unproven.

## Unchanged contracts and 1D.8 handoff

Four Pub workspace members, one root lockfile, app/package versions, Bundle ID,
Sandbox/entitlements, default data directory, database schema **1** and diagnostic
summary **1** remain unchanged. The final Cocoa bundle reports its existing
normalized short version `0.1.0.3` and build `1`; Flutter build defines and the
recorded semantic app version remain `0.1.0-dev.3+1`. Core and link public APIs and CLI behavior remain
unchanged; no third-party dependency was added.

The current/latest session snapshot is not durable history. 1D.8 must use public
history repositories and preserve safe DiagnosticRun, all three save phases,
failed/partial persistence, finalCleanup independent of commit/release, nullable
facts and the summary allowlist. Maintenance/recovery remain core behavior;
waitForMaintenance covers requested work and close performs its final drain.
Recovery does not rerun diagnostics or prove the former process cleaned up.
Process-local facts may exceed what a partially saved history record contains.
Future export must use public safe summaries and stable pagination/output
contracts. Shared device gate, single storage owner, app lifecycle, explicit
port choice and no automatic device activity remain mandatory. History UI and
export were not started in this step.

## Step 7 closeout after the renderer follow-up (November 14, 2026)

The user explicitly set aside the striped-text investigation and resumed Step 7.
Its historical observations and raw evidence remain below; it is not an open
implementation task or a reason to change the product renderer. The GitHub
connector rechecked PR #32 as closed/merged and remote master as `e92c548`, still
matching this branch's actual merge baseline. Existing work was preserved.

The final review found and corrected two app-layer identity boundaries:

- A rejected duplicate Start could clear the first Start's admission latch
  before its ACK arrived. The regression deliberately withholds both the worker
  occupied snapshot and ACK; two later Starts must fail locally while GetStatus
  still works. The original implementation reproduced an unobserved fast error
  and a second pending RPC. Rejected handles now have an immediate error observer
  and never clear the earlier Start's latch. The worker gate remains independent.
- While a new Start awaits admission, the view hides the previous attempt's
  result rather than relabeling it with new input. A missing ACK does not prove
  rejection: the latest host identity and frozen request remain intact. If a
  runtime fault retains the previous worker result, a bounded, identity-bound
  local port association still labels that result with its original source.
  The latest unmatched Start is identified separately. Tests cover both a new
  observed attempt and no new observed attempt, preserve known prior facts, and
  keep the new frozen request unchanged while the next temporary input is edited.

Final verification evidence is in
`/private/tmp/meshchan-1d7-final-20261114T165124Z-f5bqmvkv/`.
The immediately preceding full runtime/process verification is in
`/private/tmp/meshchan-1d7-closeout-20261114T164650Z-nrif2l6l/`.
The final change after that full process run affects only Diagnostics model/view
and their model tests. Every runtime source file matches the passed process-run
manifest, as recorded in `process-source-equivalence.json`.

| Final closeout gate | Result |
| --- | --- |
| Actual SDK and locked dependency resolution | PASS, Flutter 3.47.9 / Dart 3.13.7; lock unchanged |
| Source formatting | PASS, 200 Dart files, zero changes |
| `flutter analyze --no-pub --fatal-infos` | PASS |
| `flutter test --no-pub --concurrency=1` | PASS, **200/200**, including the three closeout regressions |
| Runtime / Draft / Profile / Device process gates | PASS on the final runtime source |
| Diagnostic process gate | PASS, **5 scenarios**, final runtime source; no hardware |
| Fresh Debug and Release native builds | PASS, separate outside-repository derived-data directories |
| Final Debug / Release product runtime gates | PASS in both configurations: persistence, independent reopen, startup/live-owner normal quit and relocated deep/strict/all-architectures signatures |
| Final Debug / Release VM GUI and actual Pinyin | PASS after the user unlocked the guest; see the completion run below |
| Patch whitespace | PASS |

Both final native product gates run the actual compiled arm64 app and the copied
whole bundle. Ready-owner quit confirms actual worker exit, owner release and zero
pending requests/receive ports. Startup quit may correctly report that no worker
was spawned; it is not described as a worker-exit observation. Exact arguments,
closed owned fixtures, original process logs and full bundle hashes are retained.
The earlier red regression and intermediate passing products are retained at
their own cutoffs rather than promoted to final-artifact evidence.

An additional GUI rerun with these exact final products was attempted in VM run
`20261114T165429Z-product-34080`. Debug PID 34162 started with its exact owned
arguments and reached a real ready storage owner, but every activation check
refused product input. The original desktop capture and IOConsoleUsers report
confirmed `CGSSessionScreenIsLocked=Yes`. Final-product GUI/IME interaction was
therefore **BLOCKED**, not failed or passed; Release GUI was **NOT_RUN** in this
additional run. The existing Step 7 Debug/Release Pinyin/navigation/dirty-quit
sessions above remain evidence at their explicitly recorded earlier source
cutoffs. Unlocking the test guest was required for this additional final-product
GUI rerun; no input was sent through the locked desktop and no privacy/security
setting was changed. This follows the
[macos-vm-gui-testing skill](../../.agents/skills/macos-vm-gui-testing/SKILL.md)
requirement to keep the guest "logged in, unlocked and awake".

The owned Debug process was subsequently sent a normal AppKit Quit through
`NSRunningApplication.terminate()` after checking its exact PID, bundle path and
argv. Normal quit was accepted; process absence and the application's own receipt
confirmed ready-owner release, actual worker exit, zero pending requests/receive
ports and no maintenance failure. The executor then ended and SSH disconnected.
This is a **PASS for normal background quit/resource release**, not a GUI/IME
pass. No forced termination, default-directory launch or unlock workaround was
used. The captured original logs and helper source are retained outside Git.
A separate public runtime process reopened the collected closed fixture copy,
confirmed an empty Draft list, and closed with owner/worker release and zero
pending requests/receive ports. This copy check does not claim a guest-side
independent owner-reopen test.

Core/link/CLI/Python, schema generation, native XCTest and source/AOT smoke
evidence above belongs to this Step 7 implementation run, not inherited PR #32
counts. The closeout changes no source for those components or native test
contracts, so those already-passed suites were not repeated. No version, schema,
dependency, public core/link API, native quit policy or product startup option
changed. At this validation cutoff, no commit, push, PR or release had been made.
No 1D.8 implementation was added.

### Final-product GUI completion after unlock

After the user confirmed unlocking the guest, a new owned run,
`20261114T182921Z-product-41940`, completed the previously blocked final-product
GUI/IME checks in both configurations. Evidence is retained at
`/private/tmp/meshchan-1d7-unlocked-gui-20261114T182858Z-baz0mgfy/`.
The original blocked run and its normal background-quit evidence remain intact.

The source and full bundle inventories were checked before launching. These are
the exact final software-gate products, not a rebuild or earlier GUI artifact:

| Product | Actual guest PID | Executable SHA-256 | Final dirty-quit choice |
| --- | --- | --- | --- |
| Debug | 42052 | `958861a6e3fa5bbdbfa1d898a34bec325c216842ec4e3a45dab129fe244bbae6` | Continue editing, then Save |
| Release | 46460 | `9421ab9afbf67affecba1f79f87bf988388e1e285b36805ae45bc257e943eb19` | Continue editing, then Discard |

Both **PASS** the following hardware-free product workflow:

- Device shows no listed/opened port and no selection. Session-only 5/15/0 check
  defaults and invalid numeric/startup inputs were checked without Refresh/Check.
- Diagnostics uses actual Pinyin key events. Each original preedit image and
  focused-field JSON was reviewed separately, confirming the correct owned PID,
  underlined `zhong wen`, the selected `中文` candidate and no launcher overlay.
- Actual pointer clicks on operation/content-mode choices and navigation, followed
  by ordinary Command-Q, preserved the marked input, focus and `[9, 0]` selection. No menu or
  leave dialog opened. Each retained original image was reviewed before commit.
- One natural Space committed exact `中文`; the UI reported **6 UTF-8 bytes**.
  Restored US input, Device/Diagnostics navigation and PING/finite-Responder/PING
  switching preserved the call input. The deliberately incomplete preview
  returned controlled `invalid_input`; no-port Start remained disabled.
- A separate dirty Draft used actual Latin typing after source restoration.
  Command-Q opened the shared decision; Continue editing preserved its content
  and ready owner. A second Command-Q followed by the choice in the table led to
  normal application exit.

For both products, actual process absence and application shutdown receipts
confirm `resourcesReleased=true`, `workerExited=true`, owner `released`, zero
pending requests/receive ports and zero maintenance failures. The expected
`invalid_input` preview error remains in the receipts and is not a cleanup or
close failure. The executor then ended normally and SSH disconnected. No native
Refresh, serial open, recording Start or RF operation occurred. Enabled-Start
composition and active-recording behavior remain separately covered by the
widget/fake/worker/process tests, not inferred from this no-port GUI run.

Independent public-runtime processes then reopened the two collected, normally
closed guest fixture copies. Debug contained one revision-1 Draft with the exact
expected body; Release contained no Drafts. Both independent processes confirmed
their own owner/worker release and zero pending requests/receive ports on close.
`reopen-results.json` and the original process logs retain this Save-versus-Discard
evidence. This is a copied-fixture persistence check, not an independent reopen on
the guest's original directory. The run retained 18 original PNGs plus per-stage
AX, focus, source-restoration and quit receipts, all outside Git.

The Release screenshots retain the previously observed body-text raster artifact.
Per the user's instruction it was left outside this acceptance work; no renderer
setting, SDK, font or product code was changed. The actual preedit/candidate and
committed-input evidence above is independent of that artifact.

## Post-review fix: override collapse during composition (November 14, 2026)

The P2 review finding was reproduced in both PING and finite Responder. A real
mouse header click during an override field's marked input removed its
EditableText while the application-owned controller retained composition. Both
new regressions failed before the fix with the override field missing.

Diagnostics now owns a presentation-only public ExpansibleController whose
collapse entry checks live model composition before changing expansion state.
When composition is active, the existing defer notice is shown without collapsing,
disposing the editor, replacing its controller, clearing marked text or forcing
focus/commit. A stateful view owns/disposes only this UI controller; worker,
storage and task ownership are unchanged. Ordinary collapse remains available
after commit/cancel, and expansion can still reveal an existing field.

The two macOS Widget regressions deliver an input-method update and click the
header **before pumping a rebuild**, covering the stale build-time flag case.
They verify the same editor element, identical TextEditingValue, retained focus
and composing state, and deferred navigation/quit. They then exercise commit or
cancel, actual collapse/removal, re-expansion with preserved text, successful
departure and the existing quit coordinator's shutdown path.

Evidence is retained outside Git at
`/private/tmp/meshchan-1d7-review-ime-20261114T190645Z-_3hixsop/`:

| Review-fix check | Result |
| --- | --- |
| New PING / Responder mouse-composition regressions before fix | Both reproduced the missing editor failure |
| Full Diagnostics test file after fix | PASS, **9/9** |
| Complete app `flutter test --no-pub --concurrency=1` | PASS, **202/202** |
| `flutter analyze --no-pub --fatal-infos` | PASS |
| Changed Dart source formatting / patch whitespace | PASS |

The installed Flutter **3.47.9** and bundled Dart **3.13.7** were used with the
verified Python **3.15.2** and process-local Apple-compiler-first PATH. The suite
was executable with normal SDK-cache access in this implementation environment;
the reviewer's read-only-cache limitation was not counted as a test failure or
pass. No SDK source, version, dependency or global setting was changed.

These are headless Widget composition/quit regressions, not new physical Pinyin
acceptance. The earlier native bundles and actual GUI sessions retain their
recorded pre-review source cutoffs. Native builds/GUI, real serial/RF and unchanged
runtime/core/link/CLI/process gates were not rerun for this presentation-only fix.
Original artifacts and observations remain intact; no previous binary is claimed
to contain this patch. CI's existing complete app suite includes the new cases.

## PR publication check (November 14, 2026)

After the user requested a PR, the GitHub API again confirmed remote master at
`e92c5487243f17467f1030cfb426b8e063c3a90c` and no existing open PR for
`codex/phase-1d7-recorded-diagnostics`. A SHA-256 comparison of all **317** files in
the post-review source manifest found no differences from the **202/202** app-test
cutoff. Only this publication note and its historical-status clarifications were
then added; no product or test source changed for publication.

The subsequent independent review reported no actionable regressions. Its direct
Dart analysis and runtime, Draft, Profile, Device and five-scenario diagnostic
process gates passed. Its Flutter Widget suite did **not start** because its SDK
wrapper could not write to the read-only cache. That review limitation remains
separate from the completed 202-test implementation run above.

The PR retains the earlier native/GUI artifact cutoffs: the override-collapse fix
has headless Widget evidence but no subsequent native rebuild or actual Pinyin
GUI run. Real USB/serial and RF recording remain **NOT_RUN**, with no current
explicit test port and corresponding wireless scope supplied. The publication
does not extend acceptance to 1D.8 history/export or the 1D.11 hardware matrix.
Raw evidence remains outside Git; versions, schema, dependencies, public core/link
APIs, native quit policy and product launch options remain unchanged.

## Follow-up web research: striped text (November 14, 2026)

The user requested web research into the observed raster artifacts. No renderer,
SDK, application source, VM graphics setting or signing setting was changed by
this research. These are diagnostic leads, not a confirmed Meshchan root cause.

- Flutter's [Impeller documentation](https://docs.flutter.dev/perf/impeller)
  confirms macOS defaults to Impeller from 3.47 and documents
  `FLTEnableImpeller=false` in the app Info.plist for a packaged comparison.
  The current product log identifies MetalSDF; the project sets no override.
- Open Flutter [issue #196226](https://github.com/flutter/flutter/issues/196226)
  reports striped/patterned letter blocks in macOS Release with Impeller and a
  clean comparison with Skia. It was reproduced on Intel Iris Plus 650; Apple
  Silicon hardware did not reproduce it in the maintainer's test. It is similar
  evidence, not proof of the same bug in this arm64 macOS VM.
- Flutter [issue #193927](https://github.com/flutter/flutter/issues/193927)
  documents macOS glyph corruption under heavy GPU load. A maintainer reproduced
  that case on 3.47.7 and identified
  [PR #188965](https://github.com/flutter/flutter/pull/188965) as its likely fix.
  That PR changes HostBuffer reuse to wait for GPU completion; previously four
  resets were assumed sufficient, allowing in-flight vertex/uniform data to be
  overwritten under a deep pipeline. The installed 3.47.9 source still has the
  old four-slot Reset implementation, with no submission tracker in HostBuffer.
  That source observation does not establish our binary's failure mechanism.
- Do not prescribe the old `FLTEnableSDFs=false` recipe: macOS SDF opt-out was
  removed by [PR #186265](https://github.com/flutter/flutter/pull/186265), listed
  in the official 3.47 release notes, and the installed project's enableSDFs
  getter unconditionally returns YES.

The next useful experiment is an isolated same-source, same-SDK Release A/B,
using fresh owned build/products/data directories: default Impeller versus
`FLTEnableImpeller=false`, first in the same VM and then on the host. A clean
Skia comparison would identify a renderer-dependent symptom and provide a
potential temporary workaround; it would not prove which upstream engine bug
caused it. Capture renderer logs and original guest screenshots for each side.
Do not mutate/re-sign an existing validated bundle, upgrade the pinned SDK,
change fonts/widget layout, or adopt QEMU/ANGLE display recipes as an assumed
fix for the Apple Virtualization guest. At the research cutoff this A/B was
**NOT_RUN**. The subsequently authorized experiment is recorded below.

## Same-source Release renderer A/B (November 14, 2026)

**Executed; striped text NOT_REPRODUCED in this bounded VM/host comparison.
Root cause and the benefit of disabling Impeller remain INCONCLUSIVE.** Both
renderers produced readable body text in the reviewed Diagnostics, Device and
actual Pinyin/navigation screenshots. This does not erase the earlier Release
VM artifact screenshots or establish an engine fix. The product renderer setting
was not changed.

### Source, tools and build controls

Evidence root:
`/private/tmp/meshchan-renderer-ab-20261114T160412Z-cvm87gca/`.
The experiment used the existing dirty Step 7 work on
`codex/phase-1d7-recorded-diagnostics`, based on
`e92c5487243f17467f1030cfb426b8e063c3a90c`. `inputs.json` records the exact
SHA-256 of all **317** tracked/nonignored source files and original Git status.
Before this report update, all 317 original repository files still matched that
manifest. Existing work was preserved; no new commit, push or PR was made.

Two separate complete source snapshots were built sequentially. Their only
source difference was the B snapshot's macOS Runner Info.plist:

- A: no `FLTEnableImpeller` override, using the engine's default.
- B: `FLTEnableImpeller` set to the Boolean `false`.

Both used `/opt/homebrew/share/flutter/bin/flutter`, Flutter **3.47.9** stable,
framework `c197ca5199e9ee5661e865596c9c07294dfab51c`, Dart **3.13.7** and engine
`89c39edfdfae2949f6806e4a315c0c08522238b7`. The Python interpreter was
`/opt/homebrew/bin/python3`, **3.15.2**. Xcode was **27.2 / 27B52**. Native build
subprocesses used the documented Apple-compiler-first PATH. Commands in each
snapshot were `flutter pub get --enforce-lockfile`, then
`flutter build macos --release --no-pub`, followed by
`codesign --verify --deep --strict --all-architectures` on the copied whole app.
All six final command results passed. The earlier user-interrupted A build and
its `BUILD INTERRUPTED` log remain separate evidence; it was not counted as a
completed build. The subsequent build pair used the same captured inputs.

The actual engine framework binary is identical in both bundles, SHA-256
`0cf871403716d0aec6766cc6ef601f71eeb71039cef0041caf26cddd65d15821`.
Executable SHA-256 values are:

- A: `803f3d4f78f733c77d461ca7c71f8e637f9ef0e5a4e7d2713be3019f2b645b88`.
- B: `843c4628efb9c2e9d18157ce4e49754d2e0aa841590ca04578f14b042163e846`.

Full bundle manifests, `renderer-plist.diff`, `comparison-controls.json`,
`flutter-version.json` and the build/signature logs identify the products beyond
their executable hashes. The root lockfile, versions, schema, Bundle ID,
entitlements and original product Info.plist remained unchanged. No SDK, cache,
font, widget layout, graphics/VM setting or system privacy setting was patched.

### Actual GUI comparison and evidence

The VM ran first, using executor run
`20261114T160555Z-product-21063`. Identity/console-user/SSH guards and guest-side
input, focus queries and screenshots were retained. The guest was arm64
VirtualMac2,1 on macOS **27.2.1**. The host was arm64 **Mac14,6 / Apple M2 Max /
64 GB**, macOS **27.2.1 / 26B131**. The same two copied bundles were used on the
host after all VM product sessions had normally exited and the executor had
finished. The SSH control connection was then disconnected.

Each side covered Diagnostics initial text, explicit empty Text content with an
actual invalid-parameter preview, the untouched Device page, and three
Drafts/Diagnostics navigation round trips. The Device page confirmed no ports
had been listed or opened; no Refresh, Check or diagnostic Start was invoked.
Pinyin follow-ups used actual letter events, reviewed marked `zhong wen` and the
`中文` candidate before natural Space commit, then verified exact committed
`中文`, **6 UTF-8 bytes**, and retention across Device/Diagnostics navigation.
Each preedit was reviewed separately before its commit. These were temporary
call inputs; no Draft, profile or diagnostic record was saved.

| Environment and variant | Renderer confirmed by actual stderr | Body-text observation | Pinyin / navigation / normal exit |
| --- | --- | --- | --- |
| VM A, `vm/Impeller` + `vm/ImpellerInput` | `Impeller (MetalSDF)` | No stripes reproduced | PASS |
| VM B, `vm/Skia` + `vm/SkiaInput` | `Skia (Metal)` | No stripes reproduced | PASS |
| Host A, `host/ImpellerControlled` | `Impeller (MetalSDF)` | No stripes reproduced | PASS |
| Host B, `host/SkiaControlled` | `Skia (Metal)` | No stripes reproduced | PASS |

Host window bounds were explicitly fixed and verified for all seven captures in
each controlled run: **x=400, y=100, width=1200, height=850** on the same display.
An earlier host pair also showed readable text, but the OS placed A and B on
different monitors. That pair remains under `host/Impeller` and `host/Skia` as
supplemental evidence; the controlled pair is the primary host comparison. Host
native window captures are **2624 x 1924** including Retina scaling and shadow;
raw guest screen captures are **2734 x 1972**. Display differences across VM and
host were not treated as pixel-identical comparisons or performance measures.

The host's initial ABC-source preflight stopped before typing. Posted
Command-Space events did not produce an observed source change, so the existing
PID/fixture-guarded native driver's public input-source selection API selected
the already installed Pinyin source. Actual marked text/candidate evidence,
rather than source ID alone, established Chinese mode. The original app input
source was restored before each normal close. No Control-Space/Raycast shortcut,
TCC edit or new permission grant was used. In the VM B input follow-up, the first
preedit capture lacked the candidate window; a separate Down event exposed the
candidate UI, and that additional original image/focus record was reviewed
before natural commit. A host primary-display-only capture initially omitted a
window on another monitor; separately named per-display captures retained the
actual candidate evidence. These preflights were not counted as IME passes.

Two host navigation images appeared black in the tool's resized previews. Both
original PNG files were reopened at original resolution and show complete,
readable Diagnostics text. They were not overwritten or replaced, and the
preview observation was not promoted to an application black-screen failure.

A bounded supplemental VM run used the exact earlier validated Release bundle
whose screenshots had shown stripes, executable SHA-256
`4e61b13892997b96d38547d06c02f79c5ff9bd10f68cccd64266f95ae6613bc3`.
Its Pinyin/navigation screenshots in `vm/PriorImpellerReference` did not reproduce
stripes this time either. This is an intermittent-symptom observation, not a
third controlled build variant. No GPU-load stress, timing trace, engine patch
or long-duration raster stability test was performed. Different glyph-edge
rendering between backends is not evidence of the earlier grid artifact.

### Close, retained artifacts and conclusion

All **9 GUI sessions** (5 VM, 4 host, including supplemental runs) exited
normally. The VM used Command-Q; the host used the native window close action
through the existing quit coordinator. Process absence and shutdown logs confirm
`resourcesReleased=true`, `workerExited=true`, owner `released`, and zero pending
requests/receive ports. The intentionally incomplete preview leaves the expected
`invalid_input` request error in some receipts; it is not a close failure.
The public-core inspector subsequently reopened the **4 original host owned
directories** and **5 collected copies of normally closed guest fixtures**, one
at a time in a separate process. All nine contained zero Drafts, profiles and
history runs, zero maintenance failures, and closed successfully. The guest-copy
reopen is not presented as a second-process ownership test on the guest itself.

The evidence root retains **58 original PNGs** (18 VM, 40 host), dimensions and
SHA-256 in `screenshots-manifest.json`, original stdout/stderr, per-step AX/focus/
window geometry, exact PIDs/argv, renderer receipts, build logs, full bundles and
closed fixtures. AppleDouble `._*.png` metadata sidecars are preserved separately
and excluded from the screenshot count. `ab-summary.json` collects the results;
`independent-reopen.jsonl` records the nine public repository inspections. The
external scripts document the actual sequence. No screenshots, fixture data,
logs, credentials or binaries were added to Git.

The A/B execution and normal-close checks passed; **the original artifact was
not reproduced, so this experiment cannot demonstrate that Skia fixes it or
identify which engine/driver condition caused it**. Earlier failing screenshots
remain valid historical observations. The repository keeps its default Impeller
configuration. Real USB metadata enumeration, serial open/check, PING/Responder,
RF, hardware Cancel and hardware-active quit were **NOT_RUN by explicit task
scope**. No SDK upgrade or 1D.8 work was performed.
