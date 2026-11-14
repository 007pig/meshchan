# Phase 1D.5 — Profiles, settings, and offline parameter preview

## Delivery and acceptance status

Product implementation, local software gates and the requested macOS GUI
acceptance are complete after the November 14 follow-up. Final Debug and Release
binaries were exercised with fresh owned fixtures for all four complete profile
subtypes, CRUD/type conversion, settings/default deletion, Undo, actual Pinyin,
dirty navigation and both quit entrances. The relocated Release chain and fully
external native XCTest also passed. The final tables below distinguish actual
GUI, controlled timing tests and retained historical checkpoints.

Earlier BLOCKED/NOT_RUN entries are preserved with their original checkpoints;
the final results supersede them only for the cases explicitly rerun. Remote CI
was not run as part of local validation; subsequent checks are reported on the PR.
Real disk faults, hardware/RF, OS logout/reboot and distribution remain NOT_RUN.
During validation, no 1D.6 device selection/checking, recording execution, history
business UI, export, release/tag, upload, deployment, commit or push was performed.

## Baseline and exact inputs

- Initial working tree: clean, local `master`, HEAD
  `50bb88570677c88f0a16d55f2fe605143ca437a1`.
- GitHub [PR #30](https://github.com/007pig/meshchan/pull/30) was rechecked through
  the connected GitHub API: closed/merged, reviewed head
  `5e66ed4022b7ab0de343967dddc0d56456cd2601`, actual merge `50bb885...`, base
  `66bae904f875e45d8795da734121f127072cb52d`. The baseline includes the last
  composing-departure, document Undo, and late-unknown fixes. No PR content was
  reapplied and no temporary merge-test commit was used.
- Validation-cutoff branch: `codex/phase-1d5-profiles-settings`; HEAD was the merge
  commit, with the implementation in the working tree. The manifests capture that
  exact input; subsequent PR preparation commits it without rewriting the baseline.
- Evidence root: ignored `build/phase-1d5/20261113/`. `final-inputs.json` includes
  SHA-256 for every tracked and nonignored untracked input; `input-status.txt`
  records the complete working-tree inventory. `final-artifacts.json` records
  artifact digests. A refreshed delivery manifest also includes this document.
- Four-member Pub workspace, root lockfile, public core/link APIs, schema 1,
  summary 1, package/app versions, Bundle ID and Sandbox are unchanged.
  `unchanged-boundaries.diff` records the initial delivery. The follow-up later
  changes MainFlutterWindow Command+Q routing and adds two RunnerTests cases;
  that narrow runner exception is documented below. No dependencies were added.

The app additions are `lib/profiles/{choice,parameter_form,editor,preview,view}.dart`,
`test/profiles_test.dart`, and the test-side `tool/profile_fixture.dart`,
`profile_process.dart`, `check_profile_process.py`. Runtime protocol/controller/
worker, app navigation, the existing quit coordinator and small Draft session/
prompt integrations were extended. Documentation and CI include the new gate.
All new files are in the input manifest, including files not yet tracked by Git.

## Implementation contracts

All four profile subtypes round-trip their complete applicable budgets, channels,
route/path, data type/filter, endpoints, duration/timeouts and limits. Profile
Content never includes invocation bytes. Name/hint preserve exact text; hint
presence is explicit. Duplicate names select by ID. Operation conversion confirms
loss of operation-specific input, retains common text/budgets, resets Undo identity
and requires missing fields. No invented channel, endpoint, task-timeout or
revision/timestamp-CAS defaults were introduced. Profile saves replace one whole
subtype through the public repository. No-op updatedAt need not change.

ProfilesEditor maintains the confirmed object, raw buffer signature and immutable
in-flight typed object separately. Saving A never writes controller values back
over B. Saves coalesce, writes serialize, and the returned create ID is the sole
subsequent update target. Selected reads, bounded lists, settings and preview have
independent generations/lifetimes. The list is 20 per page, app bound 1–50, using
UpdatedCursor; there is no offset, total count, watch stream or shared page snapshot.

Settings is one complete null-or-ID/history-limit form. A failed settings read
remains visible, with blank unknown limit; explicit complete save and Restore
remain available. A default outside the loaded page remains represented by its
ID. Deletion uses core's atomic reference clearing, without a preliminary settings
save. Subsequent settings entry reads committed state rather than writing stale
cached settings. Save/restore commit and maintenance are independent: the worker
observes core-requested maintenance and retains latest/sticky reports, never
acknowledging warnings or retrying settings writes. UI explains cleanup when a
limit is lowered, including Restore defaults to 1000.

ParameterForm maintains each Override switch independently from raw input. Typed
requests use null for absent values, preserve explicit zero, distinguish absent
path from [], and use Listen null/DataTypeOverride(null)/DataTypeOverride(0).
Send/PING content is separately Not provided/Text/Hex; explicit empty Text/Hex
becomes []. Text uses exact valid UTF-8; Hex can represent arbitrary bytes. Protocol
integers use decimal or 0x/0X hex, other integer fields decimal, byte text even-length
ASCII hex without separators/prefix. Invalid explicit input is never inherited,
trimmed, clamped, truncated or converted to zero. Public route/capacity helpers
provide local hints; core repository/resolve APIs remain the validation authority.

Null profile selection means **use settings default**. Explicit ID requests do
not require settings to be read, do not change operation, and never fall back.
Preview calls only CoreStorage.resolveParameters through the unique queue; it
uses saved profiles and the real defaults, with generation-bound immutable results.
Form/storage changes invalidate prior previews. Effective values are shown locally,
with content byte count, without wholesale logging/history export. No portHint
enters requests and no device gate, transport or recording API is invoked.

The historical DraftDecision name now carries target kind, session and target ID.
Host and worker both reject paused ordinary reads/writes/resolves, and independently
consume at most one final Save before enqueueing. Profile create in flight can
bind only its own session's returned ID; Draft requests now carry session identity
as well. Cross-kind, cross-record, stale, repeated, canceled and stopped permissions
cannot authorize unrelated work. Delete, Restore, Preview and reads receive no
final-save bypass. Human decision time holds no RPC deadline.

One persistent auxiliary session cooperates with Drafts through the existing
application quit coordinator. Native requestQuit and Flutter lifecycle requests
still share a single attempt and shutdown. Composition is checked on live values
before modal/admission/read-only changes, including outside mouse focus behavior.
Fields remain mounted in scrolling forms, and session/type replacement keys reset
EditableText and delayed Undo pushes. Ordinary saves preserve input state. Unknown
writes freeze retry, do not infer identity or rollback, and remain independent of
resource release. A pending-to-unknown transition requires another explicit Discard
warning. Healthy EndDecision confirmation is required before resuming admission.

## Toolchain and commands

Observed on November 13, 2026:

| Item | Actual value |
| --- | --- |
| Host | macOS 27.2.1 (26B131), arm64 |
| Flutter | existing `/opt/homebrew/share/flutter`, stable 3.47.9, c197ca5199 |
| Dart | bundled 3.13.7 |
| Python | `/opt/homebrew/bin/python3`, 3.15.2; Python children use sys.executable |
| Compiler | Apple clang 21.0.0, clang-2100.4.1.1 |
| Final Debug main executable | arm64 (after isolated arm64 XCTest build) |
| Final Release main executable | universal x86_64 + arm64; actual runs were arm64 |
| Signature | existing ad-hoc local signing, Bundle ID org.meshchan.meshchan |

Native hooks used command-local PATH:
`/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/share/flutter/bin:/opt/homebrew/bin`.
No global settings, SDK channel/cache source, vendor source, security settings,
signing policy or Python installation was changed. SDK startup needed ordinary
cache-stamp access outside the sandbox; the existing SDK ran with approved access.

`gates.json`, `accepted-gates.json`, and `final-source-gates.json` retain argv,
member cwd and exit status. The final product code was written before the final
Debug/Release build commands; final analysis/app tests include the last UI wording
and pending-create quit test. Core/link/CLI and bundle inputs did not change after
their gates. Relevant commands are the repository's existing commands:

```bash
flutter pub get --enforce-lockfile
dart pub workspace list
# packages/meshchan_core:
dart run build_runner build
dart run tool/check_schema.dart
# repository root:
flutter analyze --no-pub --fatal-infos
# apps/meshchan_app:
flutter test --no-pub --reporter expanded
# repository root, with explicit verified local Python and bundled Dart:
/opt/homebrew/bin/python3 apps/meshchan_app/tool/check_profile_process.py --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart --evidence-root build/phase-1d5/20261113/profile-process-final
# Existing draft/runtime process checks; core/link/CLI dart test; Python discover;
# three dart build cli bundles and tool/smoke_cli.py (full argv in gates.json).
# apps/meshchan_app:
flutter build macos --debug --no-pub
flutter build macos --release --no-pub
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/macos -parallel-testing-enabled NO test
# repository root (fresh evidence directory):
/opt/homebrew/bin/python3 apps/meshchan_app/tool/check_macos_runtime.py --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --evidence build/phase-1d5/20261113/macos-runtime-accepted-new
```

## Initial software and process checkpoint

| Check | Result | Evidence below the evidence root |
| --- | --- | --- |
| Locked resolution/workspace, generation/schema | PASS | `resolution-final.log`, `workspace-final.log`, `generation-final.log`, `schema-final.log` |
| Final fatal-info analysis | PASS, no issues | `analyze-final-source.log` |
| Initial delivery full app suite | PASS, 119 tests, including original 91 and 28 added tests | `app-tests-final-source.log` |
| Complete field/control mapping, type conversion, New Undo, scoped Command+S, composing/departure | PASS in Widget/unit tests with actual macOS shortcut variant | same app log and `test/profiles_test.dart` |
| Raw invalid input, presence/zero/empty/filter/content, stale preview | PASS | same app log |
| A/B saves, duplicate create prevention, pending create + Quit final update, late unknown confirmation | PASS; controlled completions, not actual disk faults | same app log |
| Settings failed-read recovery, full replacement/restore, unknown and independent maintenance warning | PASS with controlled runtime states | same app log |
| Real host/worker final-save isolation | PASS, including direct dispatcher checks independent of host filtering | same app log |
| New product independent processes, fixtureWrites false | PASS: four typed profiles, no-op/type replacement/cursors, settings bounds/default deletion/restore, four resolves, explicit/default selection, descriptor/path independence, contender, reopen, delayed create/final update, committed reply loss, frozen retry and safe close | `profile-process-accepted.log`, `profile-process-final/*.log` |
| Original Draft/runtime independent process gates | PASS on final runtime source | `draft-process-accepted.log`, `runtime-process-accepted.log` |
| Core / link / CLI suites | PASS: 362 / 180 / 271 tests | `core-tests-final.log`, `link-tests-final.log`, `cli-tests-final.log` |
| Python suite | PASS: 65 tests | `python-tests-final.log` |
| Three native bundles + source/AOT/relocation smoke | PASS: 101 process checks | `*-build-final.log`, `smoke-final.log` |
| Retained finite Release SQLite write/read probe | PASS, fresh owned fixture; no serial access | `finite-app-probe.json`, `finite-app-write.log`, `finite-app-read.log` |
| Final Debug / Release builds | PASS | `debug-build-accepted.log`, `release-build-accepted.log` |
| Isolated native runner/termination XCTest | PASS: 9 tests | `native-tests-accepted.log`, app build's xcresult |
| Fresh-fixture macOS runtime / relocation / startup quit / live-owner quit | PASS | `macos-runtime-accepted-new.log`, `macos-runtime-accepted-new/*.json` |
| Debug/Release/relocated codesign deep/strict/all-architectures | PASS | `artifact-audit.log`, `final-artifacts.json` |
| Formatting and whitespace | PASS for all 178 tracked/new Dart sources, zero changes; diff check clean | `tracked-format.log`, `whitespace.log` |
| Remote CI | NOT_RUN; both jobs now include the new product process gate | `.github/workflows/ci.yml` |

The lost-create process is a test-side production dispatcher's send boundary:
SQLite commits, one reply is omitted, the client becomes unknown, a final write
is refused, shutdown is safely confirmed, and a new process requires exactly one
record. Delayed create separately confirms one final update of that same ID.
Neither scenario is a disk failure or force-kill-as-close. Parent watchdog cleanup
never counts as a successful close.

Failures/corrections retained during development: the first native hook selected
Homebrew LLVM and failed to link System (tool transcript and initial process log);
Apple-Clang-first PATH corrected that without dependency edits. The first Widget
form scrolled the Save widget out of a lazy list; fields now remain mounted, and
later pointer tests ensure visibility. The initial Undo test used default-platform
bindings; the corrected macOS variant passes. Intermediate session-hardening
compile/lint failures were corrected before final analysis/builds. A repeated
macOS runtime write check reused an already populated evidence fixture and was
correctly rejected (`macos-runtime-accepted.log`); the fresh directory passes.

Root `dart format --output=none --set-exit-if-changed .` also encountered the
pre-existing ignored `build/review-drafts/probe.dart`. It was not overwritten.
`format-final.log` records that local-artifact limitation. The exact tracked plus
new-source inventory passes independently (`tracked-format.log`); clean CI has no
such retained local probe.

## Initial GUI checkpoint and limits (historical)

All UI reads were preceded by OS PID/argv checks. Final Debug PID 2293 and
relocated Release PID 3033 were observed with their exact owned --data-dir values.
No UI getter was called after OS-confirmed process exit. The relocated whole app,
working directory and fixture are recorded in `relocated-gui.json`; it was copied
outside checkout and launched from that different cwd. The Release fixture was
explicitly seeded by a test-side public runtime with fixtureWrites false and four
same-name Unicode profiles. **This seed is not GUI creation evidence.**

Observed through Computer Use:

- Exploratory Debug: auxiliary entry, local invalid preset retained on Save,
  dirty navigation/Discard, canceling and reissuing Command+Q, two-setting Restore
  confirmation and successful restore, missing-parameter Preview invalid_input,
  normal exit. Earlier exploratory UI was before final wording/signature changes;
  it is not substituted for the final build below.
- Final Debug: owned-fixture startup, auxiliary entry, persisted Settings display,
  normal Command+Q exit. Command+W did not establish process termination and is
  not counted as a passing close-button test.
- Final relocated Release: four saved types and duplicate Unicode names/IDs;
  default Send inherited values; Text mode with explicit empty content resolved
  successfully with content byte count zero and the actual default ID. Changing
  default from Send to Listen saved while history limit visibly remained 2345.
  Listen's all-types checkbox edited and saved the full preset. A Ping hint
  presence edit was saved through a navigation Save decision. The eventual target
  changed to Listen, so that dialog is **navigation Save, not proven quit Save**.
  A subsequent clean Command+Q normally exited.
- Independent process after that normal exit: all four types still present,
  default Listen and limit 2345 persisted, Listen filter became null, Ping hint
  became null, gate stayed free, and close confirmed no ports/pending requests.
  `gui-independent-reopen.log` reports all assertions true. This verifies actual
  product GUI mutations independently of the accessibility proxy values.

BLOCKED: native text focus/modifier delivery was unreliable, with AX value updates
that did not reliably update the Flutter buffer, and a later noWindowsAvailable
response. Those assignments are excluded. No alternative raw CGEvent/System Events
control or security-setting changes were introduced. Actual Pinyin candidate
composition and complete final GUI Undo/CRUD/type/delete/dirty-quit matrix remain
unverified. Widget evidence, the earlier 1D.4 GUI pass and its last-correction gap
do not close this acceptance gap. The next reproduction entry is a foreground
final Debug or Release launched by exact bundle path with a new owned --data-dir;
use trusted real keyboard/pointer input and verify saved values by a new process.

Automatic action review also rejected one deletion click using a stale element
number, before any deletion occurred. The live tree was reread, the selected
record was checked, and unrelated safe checks continued. No deletion retry or
indirect bypass was performed. GUI default-profile deletion/restore combinations
remain NOT_RUN; their worker/SQLite contracts passed separately. Native screenshots
and observations are in the Computer Use transcript; `gui-observations.json`
retains the acceptance classification without full business snapshots.

The existing [1D.4 default-directory incident](phase-1d4-drafts.md#default-directory-isolation-exception)
remains unchanged historical evidence. This round did not open, inspect, modify,
repair or remove the default database. XCTest retained the existing pre-engine
MESHCHAN_TEST_HOST=disabled-owner-v1 isolation and TestAction configuration.
Actual disk faults, OS logout/reboot/shutdown, hardware, RF and distribution were
NOT_RUN.

## 1D.6 handoff

Reuse AppRuntime's typed profile selection/read/resolve APIs, ParameterForm's
presence/raw-text model, ParameterPreview's immutable effective result and
invalidation generations, and the single protected edit/quit flow. Before using
an effective result in later work, obtain independent explicit user port selection;
neither a profile, a default, a portHint nor an offline preview authorizes a port.
Keep one owner and worker, retain device gate admission and existing shutdown
barriers. Reuse completed 1D.5 checks as regressions; new device workflows need
their own explicit acceptance. Do not
reinterpret these offline entry points as device checks, recordings or history.

## November 13 native-driver follow-up

The user explicitly authorized the existing System Events/CGEvent driver to
complete native GUI acceptance, limited to owned 1D.5 fixtures and without system
security changes. Evidence is in `build/phase-1d5/gui-followup-20261113/`.
`baseline.json` verifies the initial product source and both signed artifacts
against the prior manifests. Python is still the explicitly invoked Homebrew
3.15.2; Flutter/Dart remain 3.47.9/3.13.7 (`flutter-version.json`).

The first sequences selected the Pinyin source but produced plain Latin text.
They were excluded from IME passes. The user enabled Chinese and explained that
Caps Lock is configured to switch Pinyin/ABC. Actual underlined `zhong wen` was
then observed. This exposed a real menu-before-composition bug: clicking the
profile type selector opened its menu and ended preedit before onChanged could
check it. The before/attempt images and `selectors-before-fix.log` preserve the
reproduction; five corresponding Widget cases failed before correction.

`profiles/choice.dart`, `view.dart`, and `preview.dart` now check live composition
before opening profile type, settings default, preview operation/profile and
content-mode menus. The correction leaves runtime/core, schema, versions,
dependencies unchanged. At this selector-fix checkpoint the native runner was
unchanged; the later Command+Q correction is described below. All **124 app tests**
pass, fatal-info
analysis passes, both configurations were rebuilt sequentially and isolated native
XCTest passes. `type-ime-after-fix-result.json` and its actual Pinyin images confirm
that the rebuilt Debug selector defers and leaves the menu closed.

The user reported repeated macOS Documents-access requests. A Release update was
observed in requestUnknown while that access interaction was present. No save was
retried. The actual unknown warning was acknowledged with Discard; normal shutdown
confirmed release, worker exit, and zero pending/ports (`documents-timeout-close.json`).
This retained unknown is not reclassified as a failed or successful original write,
and is not a disk-failure claim. Only after that normal close, owned fixture files
were copied for subsequent tests. The prior Documents fixtures remain intact.

`outside-paths.json` records the subsequent complete Debug/Release bundles,
fixtures, stdout/stderr, driver and cwd under `/private/tmp/meshchan-1d5-gui-rkzu1m0f`.
The driver verifies exact live PID, Bundle ID and fixture argv and checks foreground
before native keys. It never queries a closed app. It now waits explicitly for
the first actual window/Storage ready state instead of treating PID existence as
window readiness. Screenshots, scripts and archived logs remain in ignored
repository evidence; no app access to Documents is required for these runs.
The product default Application Support decision is unchanged; the default database
was not opened. No privacy permissions, Full Disk Access, signing settings or
keyboard preferences were changed. The user's latest intended Pinyin mode is the
mode to restore after this follow-up.

The reusable location and Pinyin/ABC procedure is now documented in
[development](../development.md#reusable-macos-gui-fixture-and-input-setup) and
[testing](../testing.md#native-gui-preflight-storage-location-and-pinyinabc).
The passing matrix and any remaining limits are finalized below after completion.

### Paused checkpoint — November 13, at the user's request

The user requested a pause until tomorrow. No scheduled or automatic continuation
was created. OS process inspection confirmed that all driver/orchestrator/build
processes had ended. The owned Debug app remains open at PID 53400, with an
unsaved new Draft buffer from the last IME preflight. No Save, Discard, close,
kill, owner reopening or further native input was performed for the pause.
Its exact executable, argv, fixture and external log are in `Debug-session.json`;
the live root is `/private/tmp/meshchan-1d5-gui-rkzu1m0f`. This temporary directory
must be rechecked on resumption and must not be copied while its owner is live.

The follow-up exposed a second actual-input defect: a vetoed Command+Q could add
`q` to pending Pinyin despite the Dart quit attempt being correctly deferred.
A Dart-only shortcut interception experiment did not fix the native reproduction
and was removed. Its 127-test log is historical, not the final test count. The
final Dart product inputs match the passing 124-test selector-fix inputs.
MainFlutterWindow now consumes only ordinary Command+Q before Flutter's input
method and routes it through the existing AppKit terminate request. This preserves
the single coordinator and original request/reply barriers. Two native tests
cover matching with Caps Lock and rejection of other modifiers/events/shortcuts.
`native-window-quit-probe.log` and the associated actual Pinyin screenshots confirm
that the rebuilt Debug app defers quit, retains the exact natural Chinese commit,
and subsequently exits with resources released and worker exit confirmed.

| Follow-up check | State at pause | Evidence under `gui-followup-20261113/` |
| --- | --- | --- |
| Four types, all applicable fields, GUI create/edit and independent committed read | PASS in Debug and Release at their recorded input checkpoints | `results.json`, `*-four-created-stored.json`, `*-edited-undo-stored.json`, matrix logs |
| Ordinary Save Undo/Redo, A→B, New, Discard/reload history isolation | PASS in both configurations at recorded checkpoints | `results.json`, `*-state-*-undo*.json`, exact clipboard checks and stored snapshots |
| Explicit Send→Listen conversion, Cancel, missing required fields, common text, subtype/Undo replacement, confirmed temporary-record delete | PASS in both configurations at recorded checkpoints | `*-converted-stored.json`, `*-conversion-deleted-stored.json`, matrix logs |
| Settings complete replacement, one-field preservation, default clear/ID selection, invalid limit retention, Restore cancel/confirm/Undo isolation | PASS in both configurations at recorded checkpoints | `*-settings-one-field-stored.json`, `*-restored-settings-stored.json`, `results.json` |
| Final Debug actual Profile Pinyin: Command+S, Save, Settings navigation, type menu, Command+Q and red close | PASS, marked preedit, deferred action, natural exact 中文 commit, explicit save | `final-ime-Debug.log`, `Debug-profile-ime-*-{preedit,attempt,committed}.{json,png}` |
| Final Debug actual Settings Pinyin in numeric history field: shortcut, Save, Profiles navigation, default menu, Command+Q, red close | PASS, invalid intermediate text retained, then explicitly corrected and saved | `completed-ime-Debug.log`, `finished-ime-Debug.log`, manual quit retry evidence, `Debug-settings-ime-*`, `results.json` |
| Final Debug Draft actual Pinyin retry | BLOCKED at input preflight; Latin text was detected and the Save action was never attempted | `finished-ime-Debug.log`, `Debug-draft-ime*-preedit.{json,png}` |
| Final Release Pinyin and full dual-entrance Profile/Settings Save/Discard/Continue matrix | NOT_RUN after final native correction; queued stages did not execute | `finished-stage-results.json`, `run_after_setup.py` |
| Final GUI duplicate-ID/deletion/default-clearing matrix, expanded offline preview/navigation and relocated chain | NOT_RUN in this final follow-up queue | `more.py`, `preview_nav.py`, `relocated.py`; earlier partial GUI evidence remains separate |
| App tests / analysis / Debug+Release rebuild / native tests | PASS: 124 app tests, no analysis issues, both rebuilds, 11 native tests at the recorded checkout-host checkpoint | `app-tests-after-selector-fix.log`, `rebuild-native-quit-progress.log`, `native-tests-selector-fix.log` |
| Fully external XCTest host/product/isolation preflight and build-for-testing | PASS; no test host launched by this preflight | `external-native-path-preflight.json`, `external-native-build-for-testing.log`, `external-xctestrun-preflight.json` |
| Execute final external native 11 tests, refresh final runtime/relocation/probe checks and delivery artifact manifest | NOT_RUN at pause | `external_native.py` and existing acceptance tools |

The repeated Documents prompt was not fully prevented by moving the product GUI
alone: the subsequent checkout-local XCTest host still lived under Documents.
The next native execution has been prepared with external DerivedData, host,
cwd and logs. The generated `.xctestrun` explicitly identifies the external host
and `disabled-owner-v1`; `/tmp` and `/private/tmp` aliases were canonicalized in
the path check. No privacy grant or keyboard preference was changed. The default
database was not opened. Existing isolation exceptions remain historical facts.

On resumption, first verify this checkpoint's input hashes and exact live process.
Resolve the retained Draft buffer through the normal protected UI when testing
resumes. Do not blindly restart `run_after_setup.py`: it starts from the beginning
and assumes a closed app, while completed writes and this open session already
exist. Continue from the failed actual-Pinyin preflight, verify marked text before
each action, then run the remaining stages with new log names. Pinyin source ID
alone and a Caps Lock event are insufficient proof; the last Draft attempts
still produced ABC text and are excluded. Restore the user's latest intended
Chinese mode only after actual mode verification; that mode is unverified at pause.
Do not proceed to 1D.6.

### November 14 resumption

The user explicitly resumed the paused acceptance. All 271 input hashes from
`paused-inputs.json` matched; branch and HEAD were unchanged. OS inspection found
the same owned Debug PID/fixture, with no driver or orchestrator running. Both
external bundles passed strict/deep/all-architectures signature checks and their
main executable hashes matched the current builds. `nov14-artifact-preflight.json`
also confirms that the final Dart product files match the 124-test selector-fix
inputs. Debug is arm64, Release contains x86_64 and arm64, and actual GUI runs
remain arm64. Homebrew Python is still 3.15.2.

The retained Draft Pinyin check was completed using the existing input-mode
toggle and keeping that established mode during preedit. The screenshot shows
marked text; Command+S produced the composition notice, natural selection yielded
exact `Draft IME 中文`, and an explicit later Save/normal quit/new-process read
confirmed the exact body (`nov14-Debug-draft-ime-*`,
`Debug-nov14-ime-stored.json`). No pending pause-time write was retried.

Release preflight initially continued to produce ABC text even with Pinyin
selected and several synthetic Caps Lock forms. The native driver stops before
Save/leave when its warm-up letter remains literal, and these attempts are
excluded from IME passes (`nov14-ime-Release.log`, source/caps probe evidence).
The resulting local buffer was discarded through the normal protected quit
dialog. Subsequent non-IME tests use a GUI-created Draft and independently
verified storage; pasted Chinese in that Draft is not counted as Pinyin evidence.

`nov14-remaining-*` logs/results retain each subsequent stage separately from
the November 13 checkpoints. The final matrix and any limits are recorded after
those stages settle; no earlier NOT_RUN is silently reclassified.

All eleven `nov14-remaining` stages passed:

| Actual final-app GUI check | Result and independent confirmation | Evidence |
| --- | --- | --- |
| Profile and Settings, Debug and Release, red close and Command+Q, each Save/Discard/Continue | PASS: all 24 combinations. Cancel retained the same PID/buffer and allowed further editing/retry; Discard preserved committed baseline; Save persisted the exact target/values. Every completed exit confirmed owner release, worker exit and zero pending/ports. | `nov14-remaining-quit_matrix-*.log`, `*-profile-*-{before,discard,save}-stored.json`, `*-settings-*-{before,discard,save}-stored.json`, quit screenshots |
| Offline preview in both configurations | PASS: default and explicit selection, operation mismatch, missing content, explicit empty Send/Ping, zero/unset presence, Listen inherit/all/zero, descriptor-only error followed by explicit empty path, arbitrary Hex and exact UTF-8 byte count. Preview Command+S made no profile write. | `nov14-remaining-preview-*.log`, `*-before-preview-stored.json`, `*-after-preview-stored.json`, preview state JSON/screenshots |
| Drafts↔Profiles and Settings↔Profiles navigation | PASS: actual Save/Discard/Continue controls, retained buffer on cancellation, exact Draft persisted through navigation Save. | `nov14-remaining-navigation-*.log`, `*-navigation-stored.json` |
| Default-profile deletion and all four saved subtype deletions | PASS in both configurations: default reference cleared, history limit stayed 4321; all four IDs removed only after confirmation; independent reopen was empty. | `nov14-remaining-delete_all-*.log`, `*-default-deleted-stored.json`, `*-all-deleted-stored.json` |
| Duplicate Unicode names | PASS in Release: two actual GUI creates, different IDs, selection verified each exact hint, bound deletion, independent reopen. | Release duplicate state/screenshots, `Release-duplicates-{created,deleted}-stored.json` |
| Complete Release relocated outside checkout with different cwd | PASS: fresh actual GUI Ping create/update, settings 1234, explicit empty-content offline preview, red close, independent reopen, GUI read/delete, Command+Q, final independent empty read and strict signature verification. No seeded profiles. | `nov14-remaining-relocated.log`, `relocated.json`, `Relocated-*-stored.json`, screenshot |

`nov14-remaining-stage-results.json` records exit code zero for every stage.
These runs use the rebuilt native Command+Q correction. The earlier four-type
creation/edit/type/Undo checkpoints remain historical. Because selector and native
corrections changed the final inputs, a fresh final-binary four-type matrix was
subsequently completed as recorded below. Release IME and external XCTest results
are recorded separately in the next section.

The user then corrected the input-source shortcut: on this Mac **Command+Space
switches input sources; Control+Space opens Raycast**. Earlier automated use of
Control+Space was an incorrect assumption. Its direct-CG attempt is excluded:
the expected field did not receive composition, and the foreground-app check
alone did not establish keyboard focus. Raycast was dismissed with Escape without
executing any result. No preferences or security settings were changed.

The follow-up driver now checks focus ownership as well as foreground/fixture
identity. System-wide focus APIs returned cannot-complete, while app-level
AXFocusedUIElement and AXFocusedWindow returned the exact fixture PID; that
fallback is paired with an on-screen launcher-overlay check
(`nov14-focus-api-probe.json`). Correct Command+Space then selected Pinyin and
actual Release marked text, natural Chinese commit and deferred actions worked.
`nov14-cmdspace-focused-ime-Release.log` records those cases as they complete;
failed keyboard/focus preflights remain excluded.

At the user's request, the reusable personal `$macos-pinyin-input` skill was
created at `~/.codex/skills/macos-pinyin-input/SKILL.md`, with UI metadata and
automatic discovery enabled by default. It records Command+Space, the Raycast
exclusion, the user-configured Caps Lock behavior, target/focus verification,
actual composition/commit evidence and fixture location precautions. The
skill-creator initializer and validator were used. The validator ran under
Python 3.15.2 with an existing read-only PyYAML package; no dependencies were
installed and no app/workspace dependency changed. `skill-installation.json`
records the skill hash. Project development/testing/app documentation was corrected
to the same bindings. The historical Control+Space script is retained as a text
artifact; its former executable entry now stops with an explanatory message.

### Final Pinyin, Draft and native results

The corrected input-source workflow completed the remaining actual-input cases.
Both Debug and Release now have actual Profile Pinyin evidence for Command+S,
Save preset, Settings navigation, the operation menu, Command+Q and red close;
Settings evidence for Command+S, Save settings, Profiles navigation, the default
menu and both exit entrances; and Draft evidence for Command+S, auxiliary
navigation and both exit entrances. Each passing case includes marked preedit,
the deferred action with no departure/type modal, natural exact `中文` commit,
and a later explicit Save. Numeric fields retain the invalid intermediate text
(`12中文` or `Settings IME 中文`) until the test explicitly corrects it to 2345.
Some source-establishment attempts still produced Latin text and were stopped
before the tested action; only the subsequent marked-text attempts are passes.

Release completed through `nov14-cmdspace-focused-ime-Release.log`,
`nov14-cmdspace-resumed-ime-Release.log`, and
`nov14-final-release-draft-resume.log`. Debug Profile/Settings evidence is in the
November 13 final-native logs; `nov14-final-debug-draft-ime.log` adds all four
Draft cases. Actual Draft ordinary-save Undo/Redo and A→New/Discard→B history
isolation passed in both final configurations. Independent reads in
`Final{Debug,Release}-physical-ime-stored.json` confirm the exact saved Profile,
null/2345 settings and the two final Draft bodies after those history tests.
These platform checks close the applicable 1D.4 composing-departure and document
Undo gaps. Late pending→unknown remains covered by controlled Widget/process
timing, with the actual Documents-related unknown incident retained separately;
no real disk fault is claimed.

The fully external XCTest execution passed **11 tests, zero failures**
(`external-native-tests.log`, `nov14-external-native.log`). Its generated host
and isolation preflight preceded launch; Xcode cwd/products/host/logs all resolve
outside Documents. The final Release runtime checker passed three normal worker
write/read/relocated runs plus startup and live-owner quit barriers
(`nov14-macos-runtime.log`, `runtime-nov14/*.json`). Finite SQLite write, independent
read, relocated read and strict signature checks also passed
(`nov14-finite-*.log`, `nov14-relocated-signature.log`). The complete command/cwd/
exit-code record is `nov14-post-gui-results.json`.

The final Release process was also checked through the public
NSRunningApplication executableArchitecture property: CPU_TYPE_ARM64, 16777228.
The earlier `ps arch` metadata query was unsupported and is excluded as
architecture evidence. `nov14-final-input-mode.json` records the actual arm64
process, real Chinese composition/commit in an owned fixture, normal Discard of
the temporary mode-check text, unchanged independent storage and restored Pinyin
source. No text was typed into the user's editor to test its input mode.

### Final binary coverage and delivery receipt

To bind the entire four-subtype matrix directly to the final binaries, two new
owned fixtures, `VerifiedDebug` and `VerifiedRelease`, were created after the
selector and native corrections. Each used the already rebuilt final app; no
seed writer or device was involved. Both passed all complete-field create/edit/
read checks, exact Unicode names and multiline hints, ordinary-save Undo/Redo,
New/Discard/row history isolation, Send→Listen Cancel/required fields/type Undo,
and an atomic replacement retaining the exact independently confirmed ID. All
four types and the conversion record were then deleted by their confirmed IDs.
Deleting the selected default cleared only its reference and preserved limit
5678. New processes confirmed the full field snapshots and the final empty list.

`nov14-final-crud-{Debug,Release}.log`,
`nov14-final-crud-results.json`, and
`Verified{Debug,Release}-{complete-fields,all-deleted}-stored.json` are the final
binary CRUD evidence. This closes the source-input difference in the earlier
creation/edit checkpoints rather than treating those older runs as final-binary
proof. The last source/SDK/artifact/focus receipts are retained in
`build/phase-1d5/gui-followup-20261113/`, continuing the same owned run across dates.

| Final delivery check | Result | Evidence in that follow-up directory |
| --- | --- | --- |
| Final Debug/Release complete four-type CRUD, type replacement and Profile Undo | PASS, fresh actual GUI fixtures and exact independent reads | `nov14-final-crud-*`, `Verified*-stored.json` |
| Two settings, default selection/clear, Restore and default-profile deletion | PASS, actual GUI; limits 1000/2345/4321/5678 and independent reads as recorded | settings/restore, deletion and final CRUD logs/snapshots |
| Presence/default/explicit offline preview and no-save shortcut scope | PASS in both configurations | `nov14-remaining-preview-*` |
| Dirty navigation and both native quit entrances | PASS, 24 Save/Discard/Continue combinations, confirmed release/exit | `nov14-remaining-quit_matrix-*`, navigation logs and shutdown reports |
| Actual Pinyin across Profile/Settings/Draft, natural exact commit, composing Save/navigation/type/quit deferral | PASS in both configurations, excluding failed preflights | final IME logs and preedit/attempt/commit images listed above |
| Actual Draft Save Undo/Redo and document isolation | PASS in both configurations | `nov14-final-*-draft-*.log`, `Final*-physical-ime-stored.json` |
| Final Dart product and original Draft regressions | PASS, 124 app tests; five added selector regressions; current product hash matches that passing input | `app-tests-after-selector-fix.log`, `nov14-artifact-preflight.json` |
| Analysis and final Debug/Release builds | PASS, no issues; rebuilt after corrections | `rebuild-native-quit-progress.log`, build logs |
| Fully external native XCTest | PASS, 11/11, isolated before engine/bootstrap | `external-native-tests.log`, external path/xctestrun preflights |
| Final runtime, startup/live-owner quit and finite SQLite/relocation probes | PASS, normal close/worker exit confirmed | `nov14-post-gui-results.json`, runtime/probe logs |
| Complete relocated Release GUI and signatures | PASS, different cwd outside checkout; actual Release arm64 | `relocated.json`, `nov14-final-input-mode.json`, artifact receipts |
| Format / whitespace | PASS, 179 tracked/new Dart files, no format changes; diff check clean | `nov14-format.log`, delivery whitespace receipt |
| Personal Pinyin skill | PASS, created/installed and validator passed; correct Command+Space/Raycast binding used in real follow-up | `skill-installation.json`, `skill-staging/macos-pinyin-input/` |

The final inventory, including nonignored untracked source, is
`delivery-inputs-20261114.json`; `delivery-status-20261114.txt` records the dirty
working tree rather than presenting HEAD as the full input. The artifact and
validation-helper hashes are in `delivery-artifacts-20261114.json` and
`delivery-helpers-20261114.json`. The personal skill and UI metadata are captured
separately because they are installed outside the repository. No product source
changed after the final rebuilt inputs; subsequent changes are documentation,
owned validation evidence and the requested personal skill.

The completed local matrix does not claim remote CI, actual disk failures,
hardware/RF, system logout/reboot, x86_64 execution or distribution acceptance.
Unknown/maintenance/final-save race timing uses the controlled software and real
worker/process evidence described earlier. Earlier isolation and Documents-access
incidents remain recorded; later launch receipts place every live app/fixture/
cwd/log and XCTest host outside Documents. The product default directory was not
opened, and no privacy, keyboard, signing or Sandbox settings were changed.
All owned GUI apps closed normally. At the validation cutoff the implementation
remained uncommitted on the task branch, without push, release, upload or
deployment. Step 1D.6 was not started. Later PR preparation is recorded below.


## Independent review and PR preparation

A subsequent independent review reported no actionable defects in the staged,
unstaged or untracked changes. It passed static analysis, Dart formatting, patch
whitespace checks, and the profile/settings, Draft and runtime cross-process
gates. That review did not rerun the full Flutter suite because its sandbox
blocked Flutter SDK cache writes, and did not rerun native macOS XCTest. Those
limits apply to the review run; the source-bound 124-test app and 11-test external
native acceptance records above remain separate evidence.

The user then requested creation of a pull request. Before preparing the commit,
all 271 source/input hashes matched `delivery-inputs-20261114.json`, and remote
master still pointed to the actual PR #30 merge commit. PR preparation changes
this document to distinguish the historical validation cutoff and review limits;
no product code changes after review are included. The personal Pinyin skill is
installed outside the repository; only its reusable project guidance is included
in the PR. Fixture data, raw logs and binaries remain ignored local evidence.
