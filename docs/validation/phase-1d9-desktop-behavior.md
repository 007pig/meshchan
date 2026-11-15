# Phase 1D.9 — desktop behavior

## Baseline and evidence boundaries

Implementation starts from clean `master` at
`e007e87ddc6e5034d70e68100f35980e9a1ca2a3` (PR #35, Flutter 3.50.0).
Git ancestry contains PR #34's actual merge
`8e7b81a9185540f5c139e0c54a99baf3d88655bb`, including the final pagination
correction. A fresh GitHub API query reports PR #34 MERGED at
2026-11-15T07:49:29Z, head
`6bdc11fe1b671039cb28d3ed5a58a0f1eb797018`. No duplicate merge/cherry-pick or
rollback was performed. Work is on `codex/phase-1d9-desktop-behavior`.

Evidence root: `/private/tmp/meshchan-1d9-20261115`. Raw logs, owned fixtures,
complete products, guest captures and xcresult stay outside Git. The initial
worktree was clean. This record is local acceptance; remote Actions were not
run for this work. Historical 1D.8 software/GUI/hardware facts retain their
original cutoffs, including the binaries that predate its pagination fix.
Historical RF quotas and target-replacement approvals were not reused.

## Implementation and command contract

XIB defines File Save, File Close Window and Meshchan Settings. Save/Settings
use one host dispatcher alongside requestQuit. The shell and shared auxiliary
navigation select the current editor and call existing model methods. Save has
no fallback to a hidden editor or Export. Live callback checks cover current
route, native sheet, runtime admission, composing, pending/unknown/confirmation
and active auxiliary subpage. Native enablement additionally requires the main
key window and no native modal/sheet. Native sheet state is job-numbered.

Close uses `performClose:`; the main window delegates to the existing termination
bridge. Independent windows retain their own close semantics. Standard Edit
responders remain; unsupported template text subsystems were removed. Narrow
main-window S/comma/W equivalents prevent vetoed IME commands becoming marked
characters. Command+Q matching and the original AppKit deferred reply protocol
are unchanged. The installed AppKit SDK's NSApplication.h and Apple's
[termination reply documentation](https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:))
require the original deferred request to receive a reply. Flutter's
[PlatformMenuBar documentation](https://api.flutter.dev/flutter/widgets/PlatformMenuBar-class.html)
confirms a separate native event/menu owner; this implementation retains XIB
instead of installing a competing owner.

Draft beginConfirmation checks live composing before any dialog/read-only
transition. The responsive Draft form uses a stable Flex and document-generation
key. Same-session resize preserves EditableText state; document replacement
still isolates undo. Dirty-dialog Escape/dismissal continues editing. Native
minimum and initial content sizes are 800×600 logical points; wide layouts are
also tested at 1024×768 and 1280×800. Shell status is bounded and scrollable;
existing forms/lists retain their scrolling and full error text.

Quit now awaits BeginDraftDecision before pre-writer drain, retaining the same
owner, controlled Save token, accepted queue and final runtime/output barriers.
Composition/confirmation veto occurs before cancellation or admission changes.
Continue ends only a healthy decision; Stop/fault cannot be resumed by this
layer. No core API/schema/summary/version/dependency/launch-option change,
wireless operation, mobile work, release or deployment belongs to this step.

## Reproductions and corrections

`before-tests.log`: 25 passed / 11 failed before product fixes. Eight failures
cover title/body × Delete/Inspect-Reload × immediate/no-pump and built input.
Two prove the old Row/Column switch disposes EditableTextState. One proves no
Begin barrier exists during summary drain. After shared fixes these cases pass.
The first focused integration run additionally exposed shell navigation being
unnecessarily tied to ready storage in the existing test; navigation was restored
to its original availability, while business commands still check admission.
A newly written real-controller test initially failed compilation (abstract
request constructor and nonexistent client dispose); the test now uses the
public concrete Ping request and existing shutdown ownership. A test string
interpolation lint failed one analysis run and was corrected. Failed logs are
retained separately; these tool/test-development failures are not product GUI
passes.

## Toolchain and executed gates

Installed SDK: `/opt/homebrew/share/flutter`, Flutter 3.50.0 stable,
framework `ab2912035e160d9cad6306df307576da6128ebdb`, engine
`371f77202a73e8dff57a8b3bff75bca55c090aee`, bundled Dart 3.14.0.
Python entry `/opt/homebrew/bin/python3`, actual executable
`/opt/homebrew/opt/python@3.15/bin/python3.15`, Python 3.15.2.
No SDK/channel/cache/vendor/system privacy or input bindings were changed.
Initial sandboxed Flutter version/GitHub queries could not access the ordinary
SDK cache/network; approved normal tool access then succeeded. Branch creation
also required normal Git metadata write access. These were launch/access
failures, not assertions. Commands, cwd, UTC times and exit codes are in
`ledger.jsonl`; the six process checkers and native gates run sequentially.

## Actual desktop findings and rebuild history

The first new Debug/Release pair passed 16 native tests and the three-run
runtime/relocation gate. A subsequent real Release Pinyin gate exposed
Command+comma inserting punctuation. The native matcher now recognizes the ANSI
comma key (43) under exactly the ordinary Command modifier, plus character-based
comma/localized-comma matching. The rebuilt Release retained the original
marked `zhong wen` after Command+comma and naturally committed `中文` with Space;
17 native tests passed at that cutoff. Save/Delete buttons, disabled native
Save/Settings menus, Command+S, Command+W, File Close Window and Command+Q have
separate retained focus/images. These earlier binaries predate the later dialog
Escape correction below.

The guest menu helper initially dismissed disabled menus with Escape, naturally
canceling Pinyin. That is a harness failure, not a passing business gate. Its
corrected AXCancel dismissal retained marked text; retry images remain separate.
One old `initial` scenario was inadvertently interleaved with a subsequent menu
command and failed a validation expectation after the page had changed. Its
partial results are not a complete initial-scenario pass. Long Go-to-Folder
key typing exceeded the host command-observation window; the original guest
reply was allowed to finish, with no input resend. The later snapshot confirmed
the complete intended owned path before Return was sent.

The pre-comma-fix Release PID 14179 disappeared after a later File Close event
without the required shutdown receipt. No matching crash report was found;
collected OS termination records do not establish application resource release.
This session is **FAIL / unexplained exit**, not normal Quit acceptance. Its
fixture remains separate. Later rebuilt Release red Close → Continue →
Command+W → controlled Save did produce a normal receipt, with owner released,
worker exited and zero requests/ports; that does not erase the earlier incident.
Independent public CLI inspection of a normally closed copy subsequently read
Draft `049edf9997b37ab5291bb7ed97a39052`, revision 4, exact body `中文xyk`,
9 UTF-8 bytes, and reported storageClose closed/host cleanup succeeded.

Real dirty dialogs also exposed that native text-input cancellation could
consume Escape before Flutter's dialog shortcut, even with safe-action
initial focus. Tab then Escape worked, but initial Escape did not. The final
implementation adds a narrow main-window unmodified Escape equivalent only
while the existing models report a Flutter decision/confirmation. Dart again
requires a noncurrent home route and an active decision before popping with
null (existing Continue/Cancel semantics). No sheet/native alert, ordinary text
field, unmodified Enter/Space or Stop action is captured by this bridge.
The native test covers key-down/up and all extra modifiers.

An incremental Release rebuild reported Xcode build success but failed deep
signature verification (modified/invalid nested code). That product was not used
for GUI acceptance. Final products are rebuilt into a fresh external derived
directory instead of manually changing signatures or SDK/cache settings. The
reused runtime-gate directory also rejected a second fixture write; a fresh
owned directory passed. Logs retain these build/fixture failures.

## Final AppKit reentrancy correction

The supplemental run reproduced the earlier receipt-less exit on PID 39738:
File Close displayed one dirty dialog, then ordinary Command+Q ended the process
before a normal receipt. This establishes a native reentrancy defect rather than
an unexplained recovery success. Dart's shared `_attempt` could not prevent a
second `NSApplication.terminate` from reentering AppKit's deferred exchange.

Menu Quit now targets AppDelegate's user-request selector; ordinary Command+Q
and main-window Close use the same facade. `RuntimeTermination.requestUserQuit`
coalesces while its original pending reply or Dart forwarding exists. A veto
clears the exchange and permits a later user request. The first request still
enters AppKit terminate, and the original system reply remains authoritative.
Two new native regressions prove no second terminate call while pending,
startup coalescing, retry after veto and original-reply preservation.

Fresh `QuitDerived` Debug and Release products pass **20/20** native tests,
deep signature checks and a new three-run runtime/relocation gate. Actual final
Debug PID 48871 and Release PID 50715 both survive adjacent File Close,
Command+Q, Command+W and menu Quit with exactly one dirty dialog. Escape cancels
that original decision; a later request still works. Final Debug then saved
normally and quit with a native sheet open; final Release later red-closed with
Discard. Both have released-owner/worker-exit receipts and zero requests/ports.
Another final Debug PID 53986 exercised dirty red Close → controlled Save;
final Release PID 52788 exercised About-window scope and sheet-open menu Quit.
All four final-product sessions closed normally. The two pre-fix failures and
their separate fixtures/raw replies remain in the evidence root.

After menu Quit had taken native menu focus during a dirty dialog, Escape
restored the editor route but the helper did not always observe an actual text
responder until the field was clicked. The buffer and selection were retained.
Simple dirty-cancel paths did restore the original field directly. This native
menu focus difference remains a documented usability limit, not proof of lost
text or a reason to force-focus/commit live IME.

## Final software gates and products

All commands used the installed SDK and a command-local Apple compiler PATH.
The complete app test working directory was `apps/meshchan_app`.

| Gate | Actual command / result |
| --- | --- |
| Locked dependencies | `flutter pub get --enforce-lockfile`; exit 0; root lockfile unchanged |
| App analysis | `flutter analyze --no-pub --fatal-infos`; exit 0, no issues |
| Complete app suite | `flutter test --no-pub --concurrency=1 --reporter expanded`; **245/245**, exit 0 (`app-delivery.log`) |
| Six process gates | Python 3.15.2 `check_{runtime,draft,profile,device,diagnostic,history}_process.py --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --evidence-root ...`; all exit 0 |
| Python tooling | `python3 -m unittest discover -s tool -p '*_test.py'`; **72/72**, exit 0, including live/closed/unknown collection subcases |
| Formatting / whitespace | `dart format --output=none --set-exit-if-changed ...`; 36 files unchanged; `git diff --check`, exit 0 |
| Native builds | Sequential Flutter `build macos --debug/--release --no-pub --config-only`, then absolute-workspace Xcode Runner builds with `-derivedDataPath /private/tmp/meshchan-1d9-20261115/QuitDerived`; both exit 0 |
| Native XCTest | Xcode Runner Debug, arm64, `-parallel-testing-enabled NO`, isolated TestAction; **20/20**, exit 0; `native-quit-final.xcresult` |
| Signatures | `codesign --verify --deep --strict --all-architectures` on both complete final bundles; exit 0 |
| Native runtime / relocation | Python `check_macos_runtime.py --app .../QuitDerived/Build/Products/Release/Meshchan.app --evidence .../native-runtime-quit-final`; **3 runs**, exit 0; startup/ready quit receipts also retained |
| Remote CI | **NOT_RUN** for this uncommitted branch |

The last product change is native AppKit user-request coalescing. The 245-test
Dart gate covers the final unchanged Dart source, and final native builds/tests
cover the changed AppDelegate/XIB/window source. Later changes are test tooling
or documentation only. No core/link/CLI production source changed; their whole
suites were not rerun as a substitute for desktop validation.

Final complete products:

| Configuration | Bundle | Runner executable SHA-256 |
| --- | --- | --- |
| Debug | `/private/tmp/meshchan-1d9-20261115/QuitDerived/Build/Products/Debug/Meshchan.app` | `fb623fc89bf20f385572b6c73de4c9a0479bcb8c649f7ce89dbee030fde0b2c4` |
| Release | `/private/tmp/meshchan-1d9-20261115/QuitDerived/Build/Products/Release/Meshchan.app` | `08d0d1c8c2d05fa08d42c18faf8c42327533a4d349986780c5356e87d11287ca` |

The complete earlier `FinalDerived` products (Debug `17fd60ab...`, Release
`757e191d...`) contain the final Dart/IME/layout/Escape implementation but
predate only the native coalescing correction. Earlier GUI input/resize/export
cases retain that precise cutoff; affected repeated-Quit, child-window and
sheet-Quit routes were retested on final `QuitDerived` products above. Full
source and bundle manifests retain hashes, sizes and symlink targets externally.

## Actual GUI / IME matrix

All GUI events ran inside the identity-checked VirtualMac guest through the
existing signed executor, never through host GUI scripting. The configured
hardware UUID, console user and strict SSH host key guard were checked before
remote operations. Guest desktop: macOS 27.2.1, 1367×986 logical points,
backing scale **2**, screenshots **2734×1972** pixels. AX outer window
800×632 corresponds to the XIB/native 800×600 content area (32-point title bar).
Other tested outer sizes 1024×800 and 1280×832 correspond to content 1024×768
and 1280×800. `guest-screen-facts.json` records direct NSScreen facts.

Raw run archives:
`20261115T135141Z-product-9668`, `20261115T141440Z-product-26690`, and
`20261115T143644Z-product-39650`. Product session JSON records full bundle path,
Runner hash, PID and exact `--data-dir` argv. Each image has its own matching
focus facts/command reply; real Pinyin images were viewed before the next gate
or natural Space/cancel. Plain owned emoji paste is explicitly separate from
Pinyin. The final guest input mode is U.S.; host input bindings/mode were not
changed. No serial Refresh, device open or RF action was performed in the VM.

| Case | Observed result and evidence scope |
| --- | --- |
| G01 | **PASS**: three destinations and auxiliary subpages, no ports selected/listed; same owner/session across navigation. |
| G02 | **PASS**: actual multiline input, File Save, Command+S, owned emoji/combining-text paste, selection and same-document Undo/Redo; independent exact reopen. Paste helper preserves previous clipboard formats in memory and restores only its own unchanged change count. Actual Cut/Copy matrix is **NOT_RUN**; native responder wiring is tested. |
| G03 | **PASS**: Draft dirty Settings Save/Continue, Profile dirty Continue/Discard, actual Settings form, auxiliary Preview → Settings. |
| G04 | **PASS**: Device/Run/History/Preview Save disabled; final About key window disables background Save/Settings. |
| G05 / G05a | **PASS** for separately captured Draft Save button, Delete, File Save/Settings/Close, S/comma/W/Q equivalents and composing veto. Comma failure is preserved before its fix. Conflict Inspect/Reload actual GUI is **NOT_RUN**; eight focused Widget regressions cover title/body immediate and built input. |
| G06 | **PASS** representative actual Profile name, Settings limit, Device request, Diagnostics content choice, Offline preview path override and History UTC guards. Preview's initial offscreen selector attempt did not select the intended field; the reviewed image proves the actual path override, not content. Full override-collapse cross-product remains **NOT_RUN** in this run; controlled Widget tests pass. |
| G07 | **PASS** representative Tab/Shift+Tab, modal keyboard cancel, safe initial action, guarded popup and retained input. Native menu focus restoration limit is stated above. A complete assistive-technology navigation audit is **NOT_RUN**. |
| G08 | **PASS**: actual initial/minimum/wide sizes, continuous breakpoint crossing, focused marked text/selection retained, and post-save Undo/Redo; matching Widget tests retain EditableTextState identity. |
| G09 | **PASS**: readable Settings validation failure, History details/maintenance, scroll-reachable actions at minimum size; controlled long-message tests have no overflow. Long cleanup/output-failure interleavings retain controlled-test labels. |
| G10 | **PASS**: Hide/restore, Zoom/restore, Minimize/restore, Full Screen entry/keyboard return with the same owner. An immediate AX geometry query during Full Screen animation could not find the window; settled Full Screen geometry is **NOT_RUN**, not a product exit. |
| G11 / G12 | **PASS on final products after reproduced failures**: red Close, File Close, W/Q/menu Quit, Save/Discard/Continue, repeated adjacent native entries, single dialog, new request after veto, and normal receipts. |
| G13 | **PASS**: native filename text/selection/Edit, Save/Settings scope, About child Close; sheet Command+W retained the native sheet and same main PID, without global shutdown. |
| G14 | **PASS**: final Debug sheet-open Command+Q and final Release sheet-open menu Quit; canceled owned output settles before normal release. Native filename Pinyin was separately captured/committed earlier; Quit during its live marked text on the final coalescing product is **NOT_RUN**. |
| G15 | **PASS**: real task-owned existing-target subalert Cancel/recovery, unchanged SHA-256 before/after, no Replace click. Full delegate rejection after system Replace is **NOT_RUN**; native existing-file/directory/symlink/race refusal tests pass. No earlier task's Replace authorization was reused. |
| G16 | **PASS**: actual new summary JSON, format 1, one run, UTF-8/no BOM, no staging directory; hash `0d9fbc28ea5d3d429d4c7429cd64936d9b17690b7f1d5df2c6b88ad2902e98dc`. Same-job byte fidelity is a controlled-test result; no comparison to a second independently generated timestamped summary is claimed. |
| G17 | **PASS**: all final product sessions have OS absence plus released owner, worker exit, zero pending requests/receive ports; public CLI independently reopens/closes, preserving Draft ID, text and persisted History identity. No closed product UI was queried or relaunched for verification. |

The published file is in this task's earlier owned guest output directory, not
an arbitrary remembered user destination. A first Chinese-name Save encountered
a remembered existing-target alert; it was canceled without Replace, then Go to
Folder selected the explicit owned directory. The final known-file alert test
uses only the new owned output and verifies the same hash after cancellation.

## Collection correction and final handoff

The inherited product harness originally archived its whole fixture with live
screenshots. This violated the current no-live-database-copy policy. Those copies
were not treated as release evidence; the current live copy was quarantined as
`unsafe-live-copy-not-for-reopen`. `Product.collect` now excludes `fixture` for
live or unknown OS process results and collects a database only after an absent
PID. A new regression verifies all three states; the complete Python suite is
72/72. Final coalescing-product fixtures were collected with this corrected
policy, after normal closure, before independent public CLI reads.

Final public reopen after Discard confirms Draft
`049edf9997b37ab5291bb7ed97a39052`, revision **6**, exact body
`中文xykd🙂\né中文` (the displayed `\n` denotes the actual LF), **24 UTF-8
bytes**, unchanged committed timestamp; storageClose closed and host cleanup
succeeded. The earlier newline process fixture separately verifies LF, CRLF,
CR, mixed newlines and combining characters. Persisted History still contains
the original seeded run; export does not change its identity.

1D.10 can reuse DesktopCommands, ProfilesNavigation, the single platform
handler, native user-request coalescing, the original system reply bridge,
job-numbered sheet blocking, 800×600 minimum geometry, the existing decision
barrier and final runtime/output drains. Remaining evidence limits are the
explicit NOT_RUN cells above, particularly native menu focus restoration,
settled Full Screen geometry, live native filename Quit, actual conflict Reload
and the system Replace/delegate-validation path. These are not hidden as passes.
The reproduced premature-exit defect is fixed and retested; broader acceptance remains bounded by the NOT_RUN cells.

No schema, summary, app/package version, Bundle ID, Sandbox, launch option,
dependency, workspace/lockfile or storage/device ownership change was made.
No hardware/RF, mobile, tag, release, binary upload or deployment action occurred.
No new commit, push or PR was requested/performed; this is a reviewable dirty
worktree on `codex/phase-1d9-desktop-behavior`, HEAD `e007e87...`. Full source
manifest, tracked diff and new-file archive are outside Git. 1D.10's sequential
regression/old schema-1 and limited mobile risk checks, 1D.11 hardware/beta and
1E distribution remain separate; this task does not implement them.

Final controlled dirty Save on corrected Debug independently reopens as the
same ID at revision **8**, exact body `中文xykd🙂\né中文tb`, **26 UTF-8 bytes**,
with storageClose closed. The separate corrected Release Discard fixture remains
revision 6, so Discard did not roll back or invent a commit. Latest manifests
cover the `QuitDerived` products; the earlier `FinalDerived` manifests are kept
under their pre-reentrancy names. A preparatory edit command once used the app
cwd with repository-relative paths and failed before editing; final source and
all gate commands use the recorded correct directories. The initial Swift build
also rejected redundant inherited menu-validation conformance/missing override;
that compile failure is retained separately from subsequent successful native
builds. Final evidence collection fails closed on process-query stderr as well
as unknown status. The Python 72-test rerun includes this fourth collection
subcase.

## Review corrections: asynchronous Settings departure and keyboard layouts

Both subsequent review findings were reproduced before changing production
code. The branch remains `codex/phase-1d9-desktop-behavior`, HEAD
`e007e87ddc6e5034d70e68100f35980e9a1ca2a3`, with the existing 1D.9 changes
preserved. This section supersedes the earlier product cutoff only for the
review corrections; earlier GUI cases keep their recorded source/bundle scope.
New evidence is outside Git at `/private/tmp/meshchan-1d9-review-fixes`.

### Reproductions and fixes

- **P1, confirmed:** after a clean Draft passed its first departure check,
  delayed `readSettings()` left the Draft editable. Completing the read hid
  later edits without another decision. Five added Widget regressions failed
  before the fix: Save/Discard/Continue after late edits, live composition
  arriving without an intervening build, and replacement Draft generation.
  The focused suite was 4 passed / 5 failed (`before-dart.log`). The shell now
  captures the source Draft generation/ID, rejects a replacement or pending
  read, and rechecks the live departure decision after Settings loads and before
  changing the active destination. Continue leaves that Draft dirty and visible;
  a subsequent Quit prompts again and can be vetoed without shutdown. The
  existing editor, save/revision rules and quit coordinator retain ownership.
- **P2, confirmed:** the unconditional ANSI-comma key-code fallback classified
  Dvorak's Command+W as Settings. New native tests failed three assertions across
  two cases (`before-native.log`, `before.xcresult`, 22 tests executed). Shortcut
  characters now take precedence. The physical key-43 fallback is permitted
  only when the live Carbon input source is
  `com.apple.inputmethod.SCIM.ITABC`. Missing source, U.S., Dvorak and unrelated
  input methods do not invent a Settings command. Command/Caps Lock W remains
  Close even when the supplied source is Pinyin. Modifier/key-up, modal and
  existing Command+Q semantics are unchanged. The installed Carbon SDK headers
  were checked; no input source or system binding was installed or changed.

The P1 interleaving is a controlled test, not a GUI storage-delay injection.
The Dvorak mapping is exercised with native NSEvent characters/key code and
source ID; actual system Dvorak layout GUI acceptance is **NOT_RUN**. This
round does not infer that test from the Pinyin GUI results below.

### New software and complete products

The selected interpreter was `/opt/homebrew/bin/python3`, Python 3.15.2
(`sys.executable` resolves to Homebrew's versioned executable). The existing
Flutter SDK was 3.50.0 / Dart 3.14.0. `ledger.jsonl` records exact argv, cwd,
timestamps and exit codes. Flutter tests, builds and XCTest ran sequentially.

| Gate | This review's actual result |
| --- | --- |
| Focused app tests | From `apps/meshchan_app`: `flutter test --no-pub --concurrency=1 --reporter expanded test/desktop_test.dart`; **9/9**, exit 0 |
| Complete app suite | Same cwd: `flutter test --no-pub --concurrency=1 --reporter expanded`; **250/250**, exit 0 |
| Analysis | Same cwd: `flutter analyze --no-pub --fatal-infos`; no issues, exit 0 |
| Native builds | Flutter Debug/Release `--no-pub --config-only`, then sequential arm64 Xcode Runner builds with external `AfterDerived`; both exit 0 |
| Native XCTest | Isolated disabled-owner Runner Debug, `-parallel-testing-enabled NO`, external `after.xcresult`; **22/22**, exit 0 |
| Signatures | `codesign --verify --deep --strict --all-architectures` on each complete app; exit 0 |
| Native runtime / relocation | `check_macos_runtime.py --app .../AfterDerived/Build/Products/Release/Meshchan.app --evidence .../native-runtime`; **3 runs**, exit 0 |
| Format / whitespace | Targeted Dart format check and `git diff --check`; exit 0 |
| Other process/Python gates | Earlier results above retain their original cutoff; these unchanged tools were not rerun in this review |
| Remote CI | **NOT_RUN** |

Before-product test development also encountered a missing test import and an
ambiguous Save finder. Their logs are retained separately as
`test-import-failure.log` and `test-finder-failure.log`; they are not counted as
product reproductions. An initial resumed SSH attempt was denied by the
sandbox before sending any guest action; the approved identity-checked rerun
completed. The reviewer's earlier localhost socket limitation does not describe
the successful full Flutter run recorded here.

Both new complete bundles are under
`/private/tmp/meshchan-1d9-review-fixes/AfterDerived/Build/Products/`:

| Configuration | Bundle suffix | Runner executable SHA-256 |
| --- | --- | --- |
| Debug | `Debug/Meshchan.app` | `618621ee38e40b357515ceeaf5aa046c961847295c93e22ce4a79c36c9d5e7ea` |
| Release | `Release/Meshchan.app` | `941d362e7af78ecf9a8d99a3d721b42d546fc9996b99ba0bfd9b6632f2b2ff0d` |

These include both review fixes. No product source changed after those builds;
later edits document the evidence. Source/bundle manifests and current dirty
diff are preserved externally. Older `QuitDerived` products predate these fixes
and do not cover them.

### Focused real Pinyin and normal-close verification

Following the current VM skill and product guide, events ran inside the
identity-checked guest through its existing signed executor. Run
`20261115T165229Z-product-55279` used the new complete Debug and Release bundles,
PIDs **56069** and **57876**, and separate owned fixture/explicit `--data-dir`
roots ending in `-Debug` and `-Release` under
`/Users/meshchantest/utm-ui-isolation/products/`. `vm/session.json` and raw
launch/focus logs retain product identity/argv; hardware UUID, console user and
strict host key checks remain enabled. The same macOS 27.2.1/scale-2 guest used
1280×832 outer windows, corresponding to 1280×800 content points.

For **each** configuration, its original `draft-preedit.png` and focused-field
facts were reviewed independently, then Command+comma was sent and the resulting
`pinyin-comma-deferred.png` was viewed. Actual underlined `zhong wen`, candidate
`中文`, focus on the owned Draft body and selection `[9, 0]` remained intact;
Settings did not open and no comma entered marked text. **PASS** on both new
products for this affected G05a path. Natural Space committed `中文`; the scenario
restored U.S. input and saved through Command+S. After commit, Command+comma
opened the existing Settings form on both configurations. One Debug helper
attempt expected a dirty Continue dialog after that scenario had already saved;
the missing-button failure is retained as a test expectation error, not a product
navigation failure or dirty-decision pass.

Both apps then exited normally through Command+Q. OS absence plus receipts
confirmed `resourcesReleased=true`, `workerExited=true`, `owner=released`,
`pendingRequests=0` and `receivePorts=0`. Only then were fixtures collected and
independently reopened using the existing public `meshctl draft list/show --json`
commands. Debug Draft `2d0e1404076ef71158b519dda8475336` and Release Draft
`80a6645743bf704d5f24d62156b55fa0` both retain revision **1**, exact body `中文`,
**6 UTF-8 bytes**, with `storageClose=closed` and successful host cleanup.
Release's copied, normally closed Debug record also preserves its original ID.
No closed-app UI query was sent. The executor finished normally, raw run was
collected and SSH disconnected. Final guest input source was U.S.; host input
settings were untouched.

The full earlier desktop/export/layout matrix was not repeated for these narrow
changes. Its NOT_RUN limits remain as recorded, and this review adds no hardware,
mobile, release or distribution work. The 1D.10 handoff now includes asynchronous
Settings departure revalidation and the source-scoped Pinyin comma fallback.

## PR preparation

After the review corrections, a further review found no actionable regressions,
including in new files. Its independent analysis, Python tooling suite (72/72)
and whitespace checks passed; its targeted Flutter run could not start because
of the review sandbox's localhost restriction, and it did not rerun native/GUI
tests. These limits do not replace the successful product verification above.

The user then explicitly requested a PR. Before committing, `origin/master` was
fetched and remained `e007e87ddc6e5034d70e68100f35980e9a1ca2a3`; no PR existed
for this branch. All 58 entries in the review build's source manifest still
matched the worktree, and `git diff --check` passed. The earlier no-commit/PR
statements describe their acceptance cutoff; this subsequent request authorizes
the commit, branch push and review PR, without merging or releasing the product.
