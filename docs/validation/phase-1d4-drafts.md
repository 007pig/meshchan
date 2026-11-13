# Phase 1D.4 offline drafts validation

Latest GUI status: the [native GUI follow-up](#november-13-gui-follow-up-after-ide-permission-restart)
completed the Debug/Release editor and relocated Release product matrices. It also
records a default-directory isolation exception; the GUI passes do not erase that
exception. The BLOCKED/NOT_RUN rows below remain the historical result of the first attempt.
The later [editor review corrections](#november-13-editor-review-corrections)
change product code and have fresh software/process evidence. Those changes were
not rebuilt or rerun through actual Debug/Release GUI acceptance; the preceding
GUI observations describe their earlier inputs only.

Date: November 13, 2026. Implementation and validation are separate facts. This
record describes the task branch `codex/phase-1d4-draft-editor`; it is not a release,
tag, deployment or remote CI result. The initial implementation run used owned
fixtures. The later GUI follow-up has one documented default-directory isolation
exception below. No serial enumeration, device, inbox or RF access was performed.

## Inputs and baseline

The initial worktree was clean on `master` at
`66bae90` (Merge pull request #29). The merged PR head is
`cc5e5e3edf5451a048264d12ea72bd39fbd10f2d`; its prior base was
`6b0acee049330ec7078f6ddd760a0e1c9ddab62d`. GitHub's public
[PR #29 page](https://github.com/007pig/meshchan/pull/29) reported **Merged** on
November 13. The GitHub connector returned an authentication error; the public
page and local real merge ancestry supplied the independent confirmation. No PR
was merged, temporary merge-test commit used, reset/clean performed, or duplicate
cherry-pick applied for this step. A new task branch was created from that master.

Evidence is retained under ignored `build/phase-1d4/20261113/`, with relocated
complete bundles/fixtures under the owned system temporary directories named in
`native-results.json`. `build-inputs.json` and `final-inputs.json` include SHA-256
for tracked and untracked source inputs; HEAD alone does not identify this work.
`initial-status.txt`, `base.txt`, `toolchain.txt`, gate command/status JSON and
individual logs retain reproducibility details. GUI observations are recorded
separately from software results.

Actual local toolchain:

| Component | Observed value |
| --- | --- |
| macOS / execution architecture | 27.2.1 (26B131), arm64 |
| Flutter SDK | Existing `/opt/homebrew/share/flutter`, stable 3.47.9, `c197ca5199e9ee5661e865596c9c07294dfab51c` |
| Dart | Bundled 3.13.7, macos_arm64 |
| Python | `/opt/homebrew/bin/python3`, 3.15.2 |
| Native compiler | Apple Clang 21.0.0 (`clang-2100.4.1.1`) |
| Xcode developer directory / macOS SDK | `/Applications/Xcode.app/Contents/Developer`, SDK 27.2 |

Flutter's first sandboxed version invocation could not acquire its normal SDK
cache lock. Subsequent normal tool invocations used the approved execution
boundary; no SDK/vendor source, pub cache source, channel, global PATH, Python
installation, system security or signing setting was edited. Native commands use
a command-local Apple-Clang-first PATH. Python subprocess tooling uses the selected
interpreter (`sys.executable`) where it launches Python.

## Implemented behavior

Product list/read/save/delete are typed `AppRuntime` methods and distinct worker
requests. Save creates or updates using the captured confirmed ID/revision;
`DeletedDraft` returns the committed target ID. All use the existing short admitted
queue and public draft repository. The normal runtime defaults to
`fixtureWrites: false`. Fixed `CreateFixtureDraft` remains only the legacy explicit
verification operation; no page invokes it or core/CLI internals. Draft list/read
are independent of settings and the older `ReadOffline` compound query.

The editor has current controller values, immutable `PendingDraft` text/generations/
expected revision, and confirmed `baseline`. Empty New is local and not Saved;
explicit Save can create all-empty text. During Save A, B stays in the controller;
A's returned ID/revision advances baseline only. Dirty uses exact current/baseline
text equality, including undo back to A. Duplicate Save coalesces, and delete
cannot overlap save. Delete keeps the buffer until committed success and binds
its confirmation to ID/document generation. Unsaved New uses local discard.

List, document load and stored-version inspection use separate generations. List
pages default to 20, permit 1–50, retain the dual UTC-microsecond/ID cursor and
core order, and are explicitly separate snapshots. Refresh and mutation invalidate
old cursor chains; Load more deduplicates IDs. Current editing survives row
movement and refresh failure. A confirmed mutation remains confirmed even when
its subsequent list refresh fails.

Conflict/not_found/invalid_input/read-write failures preserve local text and the
last confirmed baseline. Inspection reads do not adopt a revision; explicit Reload
replaces text with the exact version displayed to the user. Unknown mutation
outcomes retain text and the earlier baseline, freeze dangerous retry, and never
infer identity from matching content. Explicit local discard acknowledges that
the write may have committed. Later release/onExit only settles resources.

Title/body preserve empty strings, whitespace, Chinese, emoji, combining text,
U+FFFD and mixed CR/LF/CRLF. Title is multiline without a single-line formatter.
The body has no datagram cap. Body UTF-8 bytes previews only body text and caches
its count until body changes; it does not certify UTF-16 validity. Core rejects
unpaired surrogates as invalid_input. A valid noncollapsed composing range in
either controller defers button, Command+S and departure Save. No forced
clearComposing/unfocus/sleep or save-response text assignment is used.

`DraftQuitCoordinator` is application-owned. Native requestQuit and Flutter
onExitRequested share one attempt Future, one decision and final save. Cancel is
not cached. BeginDraftDecision freezes host/worker ordinary admission and binds a
fresh generation to one document session. Accepted earlier writes settle first;
one final save with that decision can use their actual new ID/revision through the
same repository/commit queue. Reusing the decision for another save is rejected.
Human decision time has no worker RPC timer. Cancellation resumes only after a
healthy EndDraftDecision acknowledgment. Faults keep admission frozen.

Only an allowed departure starts irreversible runtime.shutdown, then releases the
bootstrap barrier, drains admitted work and waits for storage release and worker
exit. Both canExit facts remain mandatory. The native original AppKit request
reply/terminateLater behavior, first-rasterized-frame and native authorization,
release acknowledgment and late release/onExit reconciliation are retained.
Early resource-free quit never waits for an editor dialog/context. Page disposal
removes UI resources/observers; it never closes the owner.

## Software and process evidence

Final observed results are listed below. Individual commands,
working directories and exit codes are retained in `gates.json`. The product
process gate has its own `product-process.log` and per-process logs. New process
receipts contain only fixture identities/metadata; ordinary app logs do not dump
editor text or full business snapshots.

The first Widget run found a short-window overflow when status/error text squeezed
the body to zero height. The form now scrolls. A follow-up composing shortcut test
also found that inserting notice controls could rebuild the unkeyed body container
and lose its input connection; its stable key now retains focus/composition.
`first-widget-failure.log` preserves the initial failure. Test-only fixture sizing,
dialog finder ambiguity and platform-override cleanup were corrected separately;
those harness errors are not disk/native failures.

The real product gate uses a test-side production-dispatcher send boundary to
omit the committed create reply. The client times out to requestUnknown, rejects
retry, safely closes, and retains unknown. A fresh independent process requires
exactly one record, revision 1, with fixture text. This is controlled response loss,
not a claimed disk fault. Independent process contention and committed reopen,
including a deleted record remaining absent, are also checked. No private storage
hooks, SQL/Drift executor or CLI implementation are imported by app tests.

## Actual platform evidence

Results here must distinguish build, native callback/process, and actual GUI
interaction. Historical PR #29 evidence does not validate the new editor. Native
XCTest TestAction continues to supply `MESHCHAN_TEST_HOST=disabled-owner-v1` before
engine/bootstrap and does not inherit ordinary LaunchAction arguments. Missing or
invalid markers remain fail-closed. Every normal manual launch supplies a dedicated
`--data-dir`; the legacy finite probes have their separate owned fixtures.

| Gate | Actual result | Evidence under `build/phase-1d4/20261113/` |
| --- | --- | --- |
| Locked resolution / workspace | PASS; four members plus root, lock unchanged | `pub-get.log`, `workspace.log`, `gates.json` |
| Generation / schema / generated artifact diff | PASS | `generate.log`, `schema.log`, `generated-diff.log` |
| Whole-tree Dart format / root fatal-info analysis / whitespace | PASS; 740 files, zero format changes; no analysis issues | `format-check.log`, `final-analyze.log`, `whitespace.log` |
| Final app suite | PASS; 74 tests | `final-app-tests.log` |
| Final editor unknown/navigation/quit focused regressions | PASS; 23 tests | `final-editor-tests.log` |
| Public product worker/SQLite CRUD | PASS; included in app suite | `draft_worker_test.dart`, `final-app-tests.log` |
| Product independent processes / lost committed create | PASS; normal fixtureWrites false, frozen retry, new-process record count 1 | `product-process.log`, `product-process/*.log` |
| Prior runtime independent owner/contender/reopen | PASS | `runtime-process.log` |
| core / link / CLI / Python complete suites | PASS; 362 / 180 / 271 / 65 tests | `core-tests.log`, `link-tests.log`, `cli-tests.log`, `python-tests.log` |
| Three native bundles / source-AOT-relocated smoke | PASS; 101 process checks | `*-build.log`, `smoke.log`, `smoke-evidence/` |
| Final Debug / Release builds | PASS | `final-debug-build.log`, `final-release-build.log` |
| Final Debug / Release ordinary runtime verification, startup quit and live-owner quit | PASS; release/exit confirmed, zero pending/ports | `native-progress.log`, `native-results.json`; external per-mode JSON/logs |
| Final Debug / Release legacy bounded probe | PASS; write/read without serial enumeration | `debug-legacy-*.log`, `release-legacy-*.log` |
| Complete Debug / Release app relocation and signatures | PASS for bounded runtime/probe path, different cwd outside checkout | `native-results.json`, external `runtime-processes.json`, `signature.json` |
| Final deep/strict/all-architectures signatures and binary inventory | PASS; Bundle ID unchanged | `artifact-audit.log`, `final-artifacts.json`, `release-signature.txt` |
| Isolated native XCTest / termination callbacks | PASS; actual arm64 destination, 9 tests, no failures | `native-tests.log`, `native-tests.xcresult` |
| Actual Debug editor window / keyboard / dirty quit | **BLOCKED**; no usable Computer Use window | `gui-observations.json`, `gui-debug-01.log`, tool transcript |
| Actual Release editor GUI / dirty quit | **NOT_RUN** after the Debug surface blocker | `gui-observations.json` |
| Actual Chinese IME, GUI Undo/Redo/paste, Command+S, pending-save typing | **BLOCKED**; corresponding Widget cases passed, not native input evidence | `gui-observations.json`, `final-app-tests.log` |
| Relocated Release normal product editor persistence/quit | **BLOCKED**; bounded fixture runtime relocation is a separate passing result | `gui-observations.json`, `native-results.json` |
| OS logout/restart/shutdown, devices/RF, remote CI/distribution | NOT_RUN; outside this step's executed scope | No such execution claimed |

The normal final Debug executable was launched with the explicit owned
`gui-debug` directory. Computer Use could list the running application, but
`getApp` for the explicit app path and display name returned `cgWindowNotFound`.
The optional native launch API was unavailable; a subsequent system window query
stalled and returned `timeoutReached` (reported tool wall time 3559.6385 seconds).
No successful screenshot, AX editor tree, New/input/Save/delete click or actual
keyboard/window-close/Command+Q was obtained. Release GUI interaction was not
attempted through the failing surface. `gui-release` was seeded only via the
normal product runtime for a future GUI run; this is not GUI evidence.

To avoid abandoning the Debug fixture owner, cleanup used a local Debug VM service
invocation of the existing public RuntimeController.shutdown. Its retained facts
were released=true, workerExited=true, shutdownVerified=true. The standalone
Debug VM could not evaluate source (no compilation service); invoking the private
native quit helper returned a VM UnhandledException result and did not terminate
the UI process. After confirmed public shutdown, that windowless process was
reclaimed with SIGTERM (exit 143). A fresh product runtime reopened the fixture
and confirmed zero records. This controlled cleanup is **not** a normal GUI quit
PASS, and no failed/unknown write was reclassified by it. See `gui-cleanup.json`,
`gui-cleanup.log`, `gui-debug-inspect.log` and `gui-debug-records.json`.

Builds emitted the existing SDK Xcode/x86_64 informational notice and a stale
1D.3 native asset path warning. No SDK/configuration workaround was applied; final
builds and deep strict signatures passed. The executable stub contains x86_64 and
arm64 slices; actual local app/native test execution was on arm64. The complete
Mach-O inventory and hashes are in `final-artifacts.json`.

Reproduce the blocked GUI acceptance after restoring a usable native window
surface, without using the default library:

```bash
MESHCHAN_GUI_ROOT="$(mktemp -d /private/tmp/meshchan-1d4-gui.XXXXXX)"
open -n apps/meshchan_app/build/macos/Build/Products/Debug/Meshchan.app \
  --args --data-dir="$MESHCHAN_GUI_ROOT/debug"
# After normal closure, repeat with Release and an owned release directory.
```

For each mode, run empty → New → exact Chinese/emoji/multiline input → button
Save → edit → Command+S → normal close/reopen, then existing selection, delete and
reopen. Include an empty record, a product-seeded title containing LF/CRLF and a
body larger than one datagram. Exercise Save/Discard/Continue for draft switching,
New and leaving Drafts. Separately exercise all three choices for dirty window
close and Command+Q, confirming continued editing after cancel and committed data
after reopen. Observe a real installed Chinese IME's marked text, paste/selection,
Undo/Redo, and ensure Command+S defers composition. Pending/failure/conflict/unknown
can use explicitly labeled controlled Widget/worker harnesses. Copy the complete
final Release app outside checkout, launch from another cwd with a new explicit
fixture, and repeat a normal product create/save/reopen/quit chain. Keep each
app's parent process until confirmed normal exit; force reclamation never counts
as normal quit evidence.

## Scope and 1D.5 handoff

No core, schema 1, diagnostic summary 1, versions (`0.1.0-dev.3`, app
`0.1.0-dev.3+1`), Bundle ID, Sandbox/directory policy or third-party dependencies
changed. Native runner sources and XCTest isolation remain the prior implementation.
Four Pub workspace members and the single root lockfile remain intact. CI adds the
normal product CRUD/lost-write process gate to both software and macOS jobs and
keeps shared native operations sequential (`concurrency: 1`). Workflow editing is
not remote CI execution.

1D.5 can reuse the typed runtime queue, list/session generations, explicit-save
View/ViewModel, navigation decision and application quit coordinator. Presets and
settings still need their own public-model UI, validation and save semantics.
Device selection/connection, PING/Responder, history/export, autosave, recovery of
uncommitted buffers, merge/diff UI, multiple documents/windows, the full OS
logout/restart/shutdown matrix, mobile, hardware and distribution are not added.


## November 13 GUI follow-up after IDE permission restart

This follow-up continues the same uncommitted task branch and product source.
Evidence is under ignored `build/phase-1d4/gui-resumed-20261113/`; the native driver
source/binary and initial diagnostic files remain under the adjacent
`20261113-gui-followup/`. `input-check.json` confirms no app library source changed
since the prior signed builds. Final input/artifact inventories include the new
validation scripts and documentation. No core, dependency, app version, schema,
Bundle ID, runner, SDK or global setting was changed by the agent.

### Window and input diagnosis

LaunchServices foreground launch with an exact app path restored an observable
window: `open -n -W -a <complete .app> --args --data-dir=<owned fixture>`.
Bundle-ID lookup alone was ambiguous among retained artifacts. A later native
check observed an off-screen window and Flutter lifecycle `hidden` with frames
disabled while a real dirty quit decision was pending. Reactivating the same
process exposed the existing dialog; no close had begun and no second owner was
created. The user then explicitly authorized local CGEvent/System Events UI
control, granted IntelliJ computer-control permission in System Settings, and
restarted IntelliJ. Subsequent checks reported accessibility trusted, event posting
allowed and screen capture allowed. The agent did not grant itself permissions or
change security/signing settings.

The native driver verifies the target PID's bundle and explicit owned 1D.4
`--data-dir`, foreground activation, and the main window title. It requests Flutter
semantics through app-local accessibility attributes. Without that request, the
native tree contained only a shell; IME candidate windows also must not be mistaken
for the main window. The driver uses actual System Events keyboard modifiers and
native clipboard paste, keeping/restoring prior clipboard data only in memory.
It uses the already installed U.S. and Simplified Pinyin input sources and restores
the original Pinyin source. Window sizing/click bounds keep fields visible.
No accessibility text-value assignment, Dart VM mutation, fixture probe, CLI
subprocess business API, fake disk failure, or fixtureWrites mode produced the
passing editor results. The early unreliable AX value assignments are excluded.

These observations establish a working launch/control procedure. They do not
prove a single retrospective cause for every earlier cgWindowNotFound result.
The original failure record is retained. No product workaround that hides an
AppKit request or cancels/reissues termination was added.

### Actual native GUI results

`run_gui.py` and `extra_gui.py` drive the normal final app in each build mode.
Snapshots and PNGs show actual windows; after normal exit, `fixture_driver.dart`
uses typed production AppRuntime/public core requests in a new process to compare
exact text, bytes, identity and revisions. It closes before another GUI launch.
Normal app logs confirm release, actual worker exit, zero pending requests and
zero client ports. No force termination or VM shutdown was used for these passing
runs. `release-vmmap.txt` identifies the actual Release process as ARM64 on macOS.

| Actual flow | Debug | Release | Evidence in the follow-up directory |
| --- | --- | --- | --- |
| Empty list → local New → native Unicode/multiline paste → button Save | PASS | PASS | `debug-saved.png`, `Release-*-first-save.json`, normal-mode logs |
| Body UTF-8 bytes; emoji, combining character, U+FFFD; body beyond one datagram | PASS; initial body 869 bytes | PASS; initial body 869 bytes | first-save/byte snapshots and exact `*-first-reopen-records.json` |
| Actual Command+S, selection/copy/paste, Undo/Redo | PASS | PASS | `*-command-save.png`, undo/redo/byte snapshots |
| Normal quit and new-process exact saved reopen | PASS | PASS | `*-first-reopen-records.json`, per-launch shutdown logs |
| Dirty page departure: Save / Discard / Continue editing | PASS | PASS | `*-nav-*.json`, stored revision continuity |
| Dirty New and stable-row switching decisions, including New / Save | PASS | PASS | `CuaDebug-new-save-reopened-records.json`, `CuaRelease-new-save-reopened-records.json`, Computer Use transcript, switch snapshots |
| Explicit all-empty create and confirmed hard delete; deleted record absent after restart | PASS | PASS | delete-confirm PNGs and `*-after-delete-ime-records.json` |
| Actual installed Chinese Pinyin composition and shortcut deferral | PASS | PASS | `*-ime-preedit.png`, `*-ime-shortcut.png`, `*-ime-saved.png` and JSON |
| Existing title LF/CRLF retained while editing mixed CR/LF/CRLF long body | PASS | PASS | `*-mixed-newlines-open.png`, `*-mixed-reopen-records.json` |
| Dirty red-window-close: Continue editing, Discard, Save | PASS | PASS | `*-close-*-decision.png`, discard/save reopened records and shutdown logs |
| Dirty Command+Q: Continue editing, Discard, Save | PASS | PASS | `*-key-*-decision.png`, discard/save reopened records and shutdown logs |
| Window visible while native dirty decision is pending | PASS | PASS | decision PNGs and raw `post-quit-*.json` captured before later activation |

The native Pinyin display segments the marked text as underlined `zhong wen`.
The first harness incorrectly required the unsegmented string `zhongwen` and
stopped despite the product correctly deferring Save. That harness assumption was
corrected; the failure is retained in `first-matrix-attempt.log`. The screenshots
show the marked text preserved after Command+S with “Finish composing text before
saving.” A natural space-key candidate commit followed by Command+S produces a
confirmed save. The committed reopen contains Chinese candidate text, not unconfirmed preedit.
Input-source switching is asynchronous and document-specific: retained native
supplement attempts that instead delivered Latin text did not pass the exact
candidate assertion and are not counted as successful Chinese-input checks.
The later manual Release test supplies the exact Chinese/emoji confirmation below.

For both native quit entrances, Continue editing is followed by another real edit
in the same process/owner. Discard is followed by a fresh-process comparison to
the prior committed body. Save is followed by a fresh-process comparison to the
new body with the original main record ID. The final save uses the same ordinary
worker queue while admission is paused. The native original-request reply and
release/exit barriers complete normally. Raw visibility facts are recorded before
any subsequent activation, so reopening a hidden window is not counted as meeting
the pending-window requirement.

### Relocated Release and final boundaries

A complete final Release bundle was copied under an owned `/private/tmp/meshchan-1d4-gui-relocated-*`
directory and launched from that different cwd with an explicit new product data
directory. The actual product GUI created Unicode text, saved with the button,
updated with Command+S, normally closed, reopened the exact record in a new GUI
process, deleted with confirmation, and normally closed again. A new typed runtime
process required an empty list after deletion. Deep/strict/all-architectures
signature verification passed for the relocated bundle. `relocated.json` records the actual bundle/cwd/data path and created ID;
`Relocated-cua-reopened-records.json`, `Relocated-cua-deleted-records.json`, the
Computer Use transcript and normal-quit logs retain the observations. The relocated
record had an empty title and multiline Chinese body. Computer Use performed the
buttons, Pinyin key/candidate commit, dirty New/Save, reopen, delete and menu quits;
a native System Events Command+S completed the update where Computer Use modifier
delivery was unreliable. This is explicitly a mixed-driver result.

`gui-results.json`, `gui-progress.log`, `human-observations.json`, `gui-audit.json`
and the final manifest summarize the completed checks. Ordinary logs still omit
business text; full text is confined to explicit owned-fixture evidence artifacts.
The previous software/core/CLI/native/probe gates retain their exact earlier input
records; product code and signed artifact identity were checked unchanged, and
root analysis/format/whitespace were checked again for this documentation follow-up.

No actual disk failure, GUI conflict/unknown-write injection, OS logout/restart/
shutdown, device/RF, remote CI or distribution was run. Controlled pending/error/
conflict/unknown scenarios retain the separately passing Widget/worker/process
coverage. The former actual Debug/Release editor, IME, dirty-quit and relocated
Release product GUI blockers are closed by this follow-up, with the fixture-isolation
exception below retained as an acceptance limitation. Work remains within
1D.4; presets/settings/device business were not started.


### Computer Use retry, manual Chinese input, and driver boundaries

After the IDE restart, Computer Use was retried at the user's request. It
successfully delivered ASCII text, real Pinyin keys/candidate commit in the
relocated Release, actual button saves, dirty New/Save decisions, row selection,
confirmed delete and native-menu Quit. Fresh public-runtime processes confirmed
its exact committed revisions/bytes and the deletion. Separate Debug and Release
Computer Use New/Save checks each left one committed record and an unpersisted
new blank buffer. Bulk Unicode typeText/paste and Command-modifier delivery were
unreliable in these tool attempts; no unsupported event was counted as a shortcut
pass, and AX text-value assignments were excluded. Native System Events supplied
the independently passing shortcut/IME/quit matrix, with each driver identified.

The user offered manual Chinese testing and clarified that their configured input
source shortcut is **Command+Space**, not Control+Space. No shortcut setting was
modified. In a fresh owned normal Release fixture, the user reported that Save was
deferred while composing, then confirmed the candidate and saved. Computer Use
observed Saved, revision 1, and Body UTF-8 bytes 24 after the handoff. A window PNG
was retained as `HumanRelease-saved.png`. After normal menu Quit, an independent
public-runtime process required the exact observed Chinese/emoji body, empty title,
revision 1 and 24 bytes. This is user keyboard evidence plus post-save Computer Use
observation and exact process verification; it is not labeled automated native
preedit observation. No automated input ran while the user typed. See
`human-observations.json`, `HumanRelease-reopened-records.json`, `HumanRelease-01.log`
and the user/tool transcript.

### Default-directory isolation exception

During the Computer Use retry, calling getAXState after the Release app had
normally quit was followed by an automatic **no-argument relaunch** (PID 39846).
Process arguments proved this was not an owned fixture launch. The new window
reported a held owner and an empty loaded draft page: the normal startup opened
the default directory and automatically read its bounded draft list. Core
startup/recovery/maintenance may also have run. This violated the intended fixture-only boundary.
No draft create/read-selection/update/delete action was sent to that unintended
window. The agent freshly inspected the menu, selected the exact native Quit
command, and confirmed no Meshchan process remained using OS process observation.
A stale-index click was first rejected by automatic approval review; the rejection
was respected and fresh inspection supplied the safe exact Quit target.

No additional default-database connection, SQL or business query was issued for
investigation beyond that automatic app startup. No rollback, deletion, lock removal
or permission change was attempted. Only directory/database file metadata was recorded. That metadata
does not establish that all startup maintenance was harmless or unchanged.
`computer-use-isolation-incident.json` retains the actual trigger, PID, cleanup and
impact boundary. The default target is an existing directory; its main database
metadata predates this incident. No claim of complete default-library isolation is
made for this follow-up, even though the owned GUI flows passed.

For future runs, verify the live process and exact fixture arguments before UI
reads. After Quit, observe the process and existing shutdown log only; do not call
Computer Use on the closed app, since that can launch it without arguments. Any
new GUI session must be launched explicitly again through LaunchServices with its
owned data directory. The final check found no running Meshchan processes.

## November 13 editor review corrections

All three review findings were reproduced and fixed in the existing dirty
`codex/phase-1d4-draft-editor` worktree. HEAD remains
`66bae904f875e45d8795da734121f127072cb52d`, the real PR #29 merge baseline.
No branch/history rewrite, commit, push, dependency, core, schema, version or native
runner change was made for these corrections. Prior implementation and GUI
evidence are retained. This follow-up is confined to 1D.4.

Evidence: `build/phase-1d4/review-editor-20261113194024/`. `final-inputs.json`
hashes tracked and untracked source inputs, including the new regression file;
HEAD alone does not describe the tested tree. `toolchain.json` records the actual
arm64 host, existing Flutter 3.47.9 / bundled Dart 3.13.7 and
`/opt/homebrew/bin/python3` 3.15.2. SDK UndoHistory and pointer/focus behavior were
inspected read-only. Normal Flutter execution was needed for the SDK cache and
loopback test socket; neither sandbox restrictions nor the reviewer's blocked
test attempt were counted as a passing test.

| Finding | Confirmed reproduction | Correction |
| --- | --- | --- |
| A leave/quit modal loses composition before Save checks it | Focused title/body with `zhong`, composing `0..5`, could save provisional text and allow quit. Desktop mouse pointer-down could clear composition even before the action callback. | Check live composition before `deciding`, `quitting`, admission pause or any modal. Keep field focus on outside pointer-down, including input updates before the next build. Defer the entire departure attempt with “Finish composing text before leaving.” until the user finishes or cancels composition. No forced text/focus reset or write occurs. |
| Undo crosses document identity | After saving edited A and selecting B, Command+Z restored A's text while B's baseline/ID remained selected. | Key the form by document generation so intentional replacement disposes EditableText/UndoHistory and its pending 500 ms throttled push. Switching, New, Discard and confirmed Reload start fresh history; ordinary Save/status updates retain history, selection and input state. |
| Unknown write bypasses acknowledgment | A pending save becoming unknown while the initial non-unknown prompt waited let its later Discard leave after only that ordinary prompt. | Capture the unknown flag passed to the displayed prompt before awaiting its answer. If the write settles unknown before or after the initial Discard response, show a second explicit unknown-result prompt. Continue editing retains the buffer and vetoes departure/quit; acknowledgment never claims rollback or changes the unknown outcome. |

Review source changes are `lib/drafts/editor.dart`, `view.dart` and
`quit_coordinator.dart`. Tests are the new `draft_departure_regression_test.dart`
and the extended `draft_editor_test.dart`, all under `apps/meshchan_app/`.
The app README, host architecture and testing guide describe the corrected input,
Undo and acknowledgment behavior. The two native/Flutter quit sources still share
the existing application coordinator; no shutdown starts on deferred composition
or a declined unknown warning.

The first focused reproduction ran 34 cases and failed nine assertions across
all three findings (`before-focused.log`). That was an earlier regression-file
variant. The final tests add 17 cases to the prior 74 app tests: 13 Widget cases
and four controlled editor orderings. Widget cases drive real buttons, macOS
mouse events, Command+S/Z/Shift+Z, TextEditingValue selection/composition, actual
modal prompts, and shared quit attempts. They check both fields, New/row/page
departure, pending history pushes, and unknown during page/quit dialogs. They use
injected runtimes, not a live database or installed input method.

| Check of review corrections | Result | Evidence |
| --- | --- | --- |
| `cd apps/meshchan_app && flutter test --no-pub --reporter expanded` | PASS, 91 tests, sequential native configuration, including real worker/SQLite tests and existing runtime/shutdown regressions | `app-tests.log` |
| Workspace `flutter analyze --no-pub --fatal-infos` | PASS, no issues | `analyze.log` |
| Dart format of three editor sources and two changed tests; `git diff --check` | PASS | `format-check.log`, `whitespace.log`, `gates.json` |
| `/opt/homebrew/bin/python3 apps/meshchan_app/tool/check_draft_process.py --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --evidence-root .../product-process` | PASS with `fixtureWrites: false`: CRUD, owner contender, fresh-process persistence, committed lost create, frozen retry, safe close, exactly one record after reopen | `product-process.log`, `product-process/*.log` |
| Actual Debug/Release GUI, installed Chinese input method, native dirty close/Command+Q, relocated Release, rebuilt bundle signatures | NOT_RUN for this code correction; preceding GUI results belong to their recorded earlier inputs | No new app build/GUI or signing claim |

The new checks only use fakes or process-owned fixtures. No GUI app was launched,
no user/default directory opened, and no device or RF action performed in this
review follow-up. No actual disk fault was injected: unknown writes are controlled
fake completions or the existing production-dispatcher response-loss boundary.
To repeat platform acceptance, first rebuild Debug/Release from `final-inputs.json`
and run the documented owned-directory GUI flow, adding active-Pinyin departure
before candidate completion, A-to-B Undo, and pending-to-unknown prompt cases
(the latter requires a labeled controlled harness). Avoid UI reads after Quit as
described in the isolation incident. No 1D.5 implementation was started.
