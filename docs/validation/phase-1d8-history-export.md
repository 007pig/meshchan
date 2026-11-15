# Phase 1D.8 — History, maintenance and one-page export

## Baseline and source boundary

The later [pagination review correction](#pagination-review-correction) changes
two Dart product files after the build/GUI/hardware cutoffs below. Its fresh
software validation is recorded separately; earlier binaries and GUI results
must not be claimed to include that correction.

Implementation starts from actual PR #33 merge
`e6572af73e289b8feca57ca77537aebb8541d10c`, containing reviewed
`59ae88603bae736b4d67589be5a21a4340e7e454` and its final override-collapse fix.
Remote master and merged PR facts were independently checked on November 14,
2026. The initial worktree was clean. Work is on
`codex/phase-1d8-history-export`; no reset, clean, rebase or repeated merge was used.
PR #33 evidence retains the source/product limitations in its own validation
record; prior binaries are not evidence for this change.

The installed toolchain is Flutter 3.47.9 / bundled Dart 3.13.7 and
`/opt/homebrew/bin/python3` 3.15.2. Local native-asset commands use an Apple-first
process PATH, without changing global settings. SDK/cache/vendor sources,
renderer, input preferences and TCC were not patched. External evidence is under
`/private/tmp/meshchan-1d8/`: command logs/results/source hashes, full products,
native derived data, owned fixtures, GUI captures and exported files stay outside
Git. Final results and product identities are recorded below after execution.

## Delivered contracts

History is a Diagnostics subpage, preserving three primary destinations. Its
application-owned model separates editable filters from the applied bounded
selection, preserves page input and next cursors separately, and rejects stale
page/detail replies. UTC Z input includes seconds and optional 1–6 fractional
digits; date overflow/timezone omission and invalid half-open ranges are rejected.
Default page size is 50; core's valid range remains 1–200. Counts describe the
current page. Fresh export is disabled for unapplied/failed/loading selections.

Details render the actual public persisted `DiagnosticRun`, supporting all four
operation configurations/results and all three record states. Null/false/zero,
logical end, recovery observation and two-scope cleanup remain separate. Shared
read-only facts do not fabricate session gate/observer/save-attempt data. Recovery
runs only during exclusive open; it never replays a task or establishes cleanup
in the previous process. Missing IDs stay identified, including session-to-history
reads after retention. Single deletion freezes the confirmed ID, waits for core
commit, and retains controlled not_found/conflict without force or automatic retry.
Core remains the pin/eligibility authority; terminal failure can be eligible
without being proof of release.

The existing maintenance projection retains latest/sticky reports, nullable limit,
committed/deferred counts and errors. Explicit status refresh reads current public
getters. Manual maintenance installs an identity/action barrier before a quick ACK;
completion does not occupy the ordinary RPC budget or device gate. Worker drains
automatic wait observers and manual work before release. Acknowledgment captures
worker generation/revision/count, recaptures current facts and checks/acks without
await. New failure, clearing, and later same-code/count failure change revision.
Refresh, later success, navigation and close never implicitly acknowledge.

Export captures applied query/size/input cursor and calls `exportSummary()` once.
Actual count comes only from returned safe JSON; more comes from its next cursor.
UTF-8 output preserves the original JSON string byte for byte; no metadata or
newline/envelope is added. Local profile IDs/configuration/UI state are never
serialized by the app. Core's existing allowlist remains authoritative.

The main-isolate coordinator owns generation, native sheet, target, staging,
writer, exclusive publish and cleanup. The selected parent holds a unique
`Directory.createTemp` child; `writeAsBytes(flush: true)` covers open/write/flush/
close. Native `renamex_np(RENAME_EXCL)` is the publication authority, with no
exists-then-rename fallback. UX validation uses `panel(_:validate:)`, not
`shouldEnable`. Existing files, directories and symlinks cannot be replaced.
Unsupported publication returns a controlled error. Only known staging objects
are removed, nonrecursively; post-publication cleanup failure keeps file success
and a separate warning. This is not a full backup, anonymity guarantee or universal
power-loss durability promise.

Quit first checks live composition/departure preflight, then cancels pre-writer
output and pauses admission. Pending generation/pre-IO is still observed; panel
cancellation completes before dirty-document modal handling. Writer admission is
the final synchronous cancel/Stop check followed by invoking the writer with no
await in between. Admitted writers finish write/publish/cleanup. Continue never
restarts canceled output. First and reentrant quit require both real runtime
release/worker exit and settled host work. Main Stop intent is checked before
worker snapshots arrive. Host output never becomes device work or another owner.

## Validation execution

The serial runner retains exact commands and exit codes in
`validation/results.json`, logs per command, and `source-manifest.json`.
The initial broad formatting check included ignored historical `build/` Dart
fixtures; it failed without modifying them. The final local check selects current
tracked/untracked repository Dart source. First process attempts retained compiler
and invalid-fixture failures; corrected fixtures use valid public Send data type
and explicit budgets. Those attempts are not counted as passes.

Final software results and actual GUI stages are recorded below, with retained failed attempts distinguished from final passes.

## Stage boundary and 1D.9 handoff

Reuse HistorySelection/HistoryModel, maintenance action/revision snapshots and
ExportCoordinator through the sole DraftQuitCoordinator. Diagnostics Run/History
and auxiliary Profiles/Settings preserve application state and live composition
checks. Session memory, persisted history, maintenance reports, fresh summary JSON
and host publication are separate sources. No all-database count, permanent
save-attempt audit or final-unpin notification was added. File replacement, full
backup/import and unsupported-volume fallback remain excluded.

Package/app versions, schema 1, summary 1, Bundle ID, Sandbox/default directory,
four-member workspace, root lockfile, third-party dependencies, core/link public
API and product startup options stay unchanged. The VM harness alone accepts a
closed owned fixture source. Test fixture entrypoints are never product launch
options. 1D.9 should complete broader desktop/menu/window behavior; 1D.10 mobile
risk checks and 1D.11 hardware/RF/beta matrix are not implemented here.

### Retained actual GUI failure and final repair

The first Debug bundle displayed/read/filtered/paged real records, naturally
composed a Chinese filename, and produced verified one-row, five-row and empty
JSON files. Existing-name selection first displayed AppKit's Replace prompt;
even confirming it reached the app's new-name validation and preserved the
original file SHA-256. That is not permission to replace in this version.
However, ordinary Command-Q while a new Save sheet was open did not reach the
quit bridge. The process stayed alive. Its original captures and state were
retained under `vm/Debug/panel-quit-not-forwarded.*`; after canceling the sheet,
ordinary Quit produced the real release/worker-exit receipt. This initial
panel-open Quit attempt is FAIL, not a successful shutdown test.

An attempted panel-job-scoped key monitor reused the existing recognizer and
native termination path; its unit tests passed, but actual GUI still remained
open. That second failed attempt is retained in `vm-final/` and
`products-monitor-attempt/`. It is not final acceptance evidence for panel Quit.
The installed SDK's NSWindow.h and [Apple's modal termination contract](https://developer.apple.com/documentation/appkit/nswindow/preventsapplicationterminationwhenmodal)
explain that a modal window normally prevents termination before the delegate
is consulted. The final implementation sets this Save panel's
`preventsApplicationTerminationWhenModal=false`, removes the extra monitor,
and retains the original native/Dart termination coordinator. Native XCTest
checks the configured panel property and the existing shortcut/termination suite.
Two presentation follow-ups clear an obsolete composition notice after a
permitted action and display the captured deletion target in pending/error status.
Final artifacts are rebuilt and affected tests/GUI are repeated below.

## Final software results and component cutoffs

Host: arm64 macOS 27.2.1 (26B131), macOS SDK 27.2, Apple clang 21.0.0
(clang-2100.4.1.1). Guest: identity-checked VirtualMac2,1, macOS 27.2.1,
`meshchantest`, SIP enabled. The configured signed executor was reused; no new
TCC grant, keyboard setting or renderer change was made.

| Check | Result | Evidence/cutoff |
| --- | --- | --- |
| Locked workspace dependencies | PASS | `flutter pub get --enforce-lockfile`; root lockfile unchanged |
| Source formatting, fatal-info analysis, whitespace | PASS | `validation-modal-final/`; source-only local formatting preserves ignored historical fixtures |
| Complete Flutter app suite, serial | **225/225 PASS** | `validation-modal-final/app-tests-final.log`, after the final presentation changes and additional filter/result-fact assertions; product sources unchanged |
| Runtime/Draft/Profile/Device/diagnostic process gates | PASS; diagnostic **5 scenarios** | `validation/`; controller/protocol/worker/export source hashes still match that tested cutoff |
| New history process gate | **3 scenarios PASS** | `validation-final/history-process.log`; includes real UTC boundary and continuation after deleting the cursor row, recording/pin/Stop/drain, recovery/reopen |
| Core / link / CLI / Python regression | **362 / 180 / 271 / 65 PASS** | `validation/`; these package/tool sources were not changed afterward |
| Generated DB/schema helpers | PASS | `build_runner build`, `tool/check_schema.dart`, tracked artifacts unchanged |
| Debug and Release builds | PASS | `validation-modal-final/`, includes the final modal termination property |
| Isolated native XCTest | **14/14 PASS** | final `native-tests.log` and xcresult under external `native-derived/` |
| Production startup/persistence/quit/whole-bundle relocation | PASS, **3 runs** | final `native-runtime.log`; signature verification included |
| Source/AOT/relocated CLI and native asset smoke | **101/101 PASS** | `validation/smoke.log`; unchanged CLI/link/core source and their recorded bundles |
| Remote GitHub Actions execution | NOT_RUN | workflow updated for both jobs; no push/PR was requested by existing session authorization |

The history process fixture uses public recorder/fake transports only. Prepared
and logical-saved children are terminated by their owning parent to test actual
next-open recovery; those abnormal exits are not normal cleanup passes. A second
open preserves the first recovery time/reason and existing partial facts. Normal
worker scenarios verify committed delete/retention and unrelated Draft survival.
Long maintenance, new sticky failures/ack races, controlled corruption projections,
write/flush/close failure, unsupported publication and cleanup warnings are
covered with controlled public fakes where deterministic real failure is unavailable.

The final native test directly executes exclusive rename in an owned local
directory for new files, preexisting files/directories/symlinks/dangling links and
a target created after a UX existence check. The final result—not the UX probe—is
the no-replacement authority. Exact UTF-8 equality to the same returned summary
is tested in the app coordinator; real staging IO is also exercised. Native
primitive tests do not substitute for actual Save panel/file evidence below.

Final full products are under `products/`. Complete file/link hashes are in
`final-bundle-manifests.json`; primary identities are:

| Product | Runner executable SHA-256 | App.framework SHA-256 |
| --- | --- | --- |
| Debug | `037105106806fb02fac020eb2695f133f3700265cd4aa97e7d3a91b11ef24e3a` | `9abe2b30c73cc36fbb9110f346c5e4aefbdf7224f79a706c9f57bf3526695636` |
| Release | `c8ea43b3886d1ee31fec7f209c4cd85efee7c67bf56d87f9eb0ef04c4292a7f2` | `7ddd980e577c0c082de4053befb014ba1b83ac92c6ef4febe5fe3a2a10108ad5` |

No source fixes follow these final builds. Documentation/evidence bookkeeping
may follow; product source hashes are checked separately before handoff.

## Actual GUI, IME, files and normal close

The final executor run is `20261114T210138Z-product-74872` under
`vm-modal-final/`. Its `Debug` session is the focused final panel-open Quit
regression. `DebugDiscard` is a separate full Debug fixture; the label is a harness
slot and does not imply discarded records. `Release` is the full AOT fixture.
Both full fixtures were copied before app launch from the same closed public-core
source: four canceled settled operation records plus one actually recovered
prepared PING. No active database was copied or modified to seed an owner.

The full final Debug and Release runs passed persisted five-row/four-operation
reads, recovered partial/null detail, 1-row seek paging/previous/refresh, invalid
UTC input rejection, deleted-ID confirmation/cancel/commit, explicit not_found,
empty archived-state filtering, maintenance request/status and Run/History
navigation. Each selected persisted detail came from a fresh `read`, not the
session. No Device Refresh, check, transport, inbox or RF action was invoked.

Each final full run separately captured and reviewed original filter preedit and
native filename preedit. The review confirmed the exact product/focus PID,
underlined `zhong wen`, the `中文` candidate and no launcher overlay. Real mouse
Run/Apply/menu actions and ordinary native Command-Q preserved filter composition,
focus/value/selection. Only after each review was Space used to commit naturally;
the original Latin source was restored and verified. The filename was not pasted,
assigned through AX, or written directly by a test. Final files are actually named
`中文.json`. Original screenshots, focus JSON and per-gate review records remain
under their product directories. These are product Pinyin proofs, independent of
TextEdit baselines and headless composing tests.

| Final product/session | Actual JSON file | Count / selection | Result |
| --- | --- | --- | --- |
| Debug / `DebugDiscard` | owned `cwd/中文.json`, 5188 bytes | fresh first page, 5 rows, four operations plus interrupted archive | PASS; SHA-256 `2c9e35c01b58102a2ba3f399c4e8b7057daad7676f92023a7aef996f74a884f5` |
| Release / `Release` | owned `cwd/中文.json`, 5188 bytes | same bounded selection, 5 actual returned rows | PASS; SHA-256 `381f1c472a5eba51a0efeb10571a3dfbf010ad96993f4a3e9104041f1b7eb8bd` |

Independent file inspection verifies root schema/summary 1, operation/ID ordering,
UTC Z with six fractional digits, actual exportedAt values
`2026-11-14T21:05:06.506003Z` and `2026-11-14T21:10:08.422544Z`, nullable logical
end/result on the archive, preserved first recovery facts, Listen's null filter
and channel 0, integer microsecond cache TTL, no profileId/content sentinel,
no BOM/app envelope/added newline, and no remaining owned staging directory.
The exact JSON return of these GUI calls was not captured, so these GUI checks
are not claimed as a same-call byte comparison. That equality is the separate
automated coordinator assertion against the original returned string.

The earlier Debug run additionally produced an actual second-page 1-row file
with `more=true`, an empty runs file, a five-row file and an existing-name
refusal. Its panel remained open well beyond the ordinary worker RPC budget
without a worker fault; generated JSON retained its original generation time.
Confirming the system Replace prompt still reached the app's new-name refusal;
the existing file hash did not change. Its writer/publish source is unchanged,
but those captures retain their earlier native modal-policy cutoff.

All **three final sessions** exited normally through Command-Q while a fresh
Save panel was open. Each has process absence plus a release receipt with owner
`released`, resourcesReleased/workerExited true and zero pending requests/receive
ports. A separate public-core AOT inspector then opened each **original guest
directory**, after verifying the corresponding app PID was absent: 5 records
for the untouched Quit regression fixture, 4 for each full run after its captured
archive deletion. `final-gui-reopen.json` retains the bounded inspection output;
these are same-directory guest reopen checks, not merely host copies. Exported
files were inspected independently of database ownership.

### Limits and remaining desktop coverage

Real USB enumeration/open/check/recording, hardware-active Cancel/Quit and RF are
**NOT_RUN**, outside this step's supplied scope and without an explicit current
host port/radio setup. Fake PONG is not RF acceptance. No VM USB/SPICE work ran.
The later user-authorized [November 15 host follow-up](phase-1d8-hardware-2026-11-15.md)
adds real USB initialization/check, a finite real RF matrix, recorded Release
PING, real Cancel, active-hardware native Quit/reopen, and actual new-file
export. It retains initial failures and an incidental Computer Use relaunch
deviation, and records the IDE local-network recovery, the initially blocked
host Replace warning followed by an explicitly authorized successful
existing-target rejection/no-overwrite check, and the local-only hardware skill
separately. It does not retroactively change this original cutoff.
No genuinely unsupported target volume was available; unsupported publication and
writer/cleanup failures use controlled fakes, while successful/no-replacement
publication uses the real local filesystem primitive. Actual UI maintenance
failure/partial-delete races were not forced by corrupting a live database;
controlled app tests and existing real core retention tests cover those facts.
Remote CI had not run at this local validation cutoff. Publication and its CI
state are recorded on the subsequently authorized PR.

The initial SDK-cache version check did not start, then passed with normal SDK
access. A first process-hook linker failure and invalid seed parameters were
retained; they are not passes. Two harness observations timed out before their
late completed request files were read; input was not resent. A long Go-to-folder
path was confirmed from its actual focused value before continuing, and subsequent
path typing was split into bounded key-event chunks. Wrong-working-directory test
attempts did not execute the app tests; the listed complete suites use the app
package directory. No failure was hidden by SDK/cache/vendor/TCC/renderer edits.

### Final Release filter and override supplement

Run `20261114T211831Z-product-87761`, `vm-followup/ReleaseDiscard`, uses the exact
final Release executable and a fresh unchanged five-record fixture. Actual Apply
for Send/Listen/PING/Responder returns **1/1/2/1** rows; prepared/settled/
recoveredArchived returns **0/4/1**. The UTC interval
`[2026-11-14T20:39:06.510772Z, 2026-11-14T20:39:06.510773Z)` returns exactly the
boundary record. These are known bounded-fixture assertions, not product claims
of a full-database count.

Both PING and Responder request-timeout override editors then received real
Pinyin letter events. Each original marked-text/candidate image and focus JSON
was individually reviewed before actions or Space. A real mouse collapse,
History switch and native Quit retained the marked value, selection, actual focus
PID and expanded editor. Natural Space produced `中文`; the original U.S. source
was restored, ordinary Latin input remained usable, and collapse afterward
removed only the intended editor (PING retained its separate content field;
Responder had zero remaining text fields). This adds actual product coverage to
the two retained before-rebuild Widget regressions, without claiming native UI
reproduced that headless no-rebuild timing.

The helper's button-only lookup initially could not target the disclosure.
Static-text bounds and window-relative pointer preflights were retained rather
than counted as passes. One test-helper CGFloat/Double cast aborted its owned
helper before posting input; it did not terminate the app or establish resource
release. The corrected helper was compiled/signed/deployed as an executor child;
no product source or signature changed. The raw executor reply archive retains
these failed attempts. Final pointer targets used reviewed screenshots and the
verified NSWindow frame, including its title bar, before each guard assertion.

The supplemental app exited normally through a new Save panel's Command-Q,
with released owner, worker exit and zero requests/ports. Independent public-core
inspection of the same closed guest directory still returns its five records.
Together with the primary final run, **four final-bundle sessions** have actual
normal panel-open Quit receipts. SSH control connections are disconnected after
collection; no owner, lock or process is cleared to manufacture a pass.

## Final worktree handoff

At the local validation cutoff, the source handoff was the uncommitted worktree on
`codex/phase-1d8-history-export`, based on HEAD
`e6572af73e289b8feca57ca77537aebb8541d10c`. There was no new commit, pushed branch
or PR at that cutoff. The user subsequently explicitly authorized creating a PR;
the publication preparation below preserves the separate source/product
boundaries. No tag, release, binary upload or deployment was performed.

`final-source-manifest.json` records **328** tracked/new source files, including
**208** Dart files. `final-tracked.diff`, `final-new-files.tar` and
`final-status.txt` preserve the reviewable dirty cutoff outside Git. All **48**
product library/Runner source files match the final build manifest exactly;
later edits are tests, GUI harness and documentation only. Final source formatting,
app analysis, Python syntax and patch whitespace passed. The last whole app suite
is **225/225**; the two additional tests explicitly verify all operation/state/UTC
AND combinations and four-type null/false/zero/local/remote result distinctions.
The four executor run archives preserve unique raw replies, including failed
attempts; full products, native xcresults, screenshots and fixture/output files
remain outside Git.

1D.9 can reuse the three primary destinations, Run/History state, auxiliary
Profiles/Settings, the single quit coordinator, typed history selection/action
bridge, monotonic acknowledgment revision and host output drain. The final bundles
cover no-device history, protected deletion, maintenance success, real Save sheets,
Chinese filenames, actual files and native panel Quit; controlled failure/long-work
races retain their test-layer labels. Broader desktop/window/shortcut/sub-alert and
accessibility geometry behavior remains for that stage's full matrix. Keep the
absence of permanent save-attempt audit/global counts/final-unpin events explicit.
No 1D.9 implementation, mobile work or 1D.11 RF/beta scope was started.

## Pagination review correction

On November 15, review identified a stale continuation after a failed Apply:
`_load` installs the attempted filter/size while retaining cached rows from the
previous successful page. Next previously reused that cached page's cursor with
the failed new selection; subsequent success could authorize an incorrectly
reached page for export. A failed continuation could also leave Previous enabled
and mutate navigation state before a successful retry.

`HistoryModel` now requires a non-loading, error-free page and selection before
allowing either continuation direction or export. Its direct Next method and
the Widget's Next button use the same `canNext` guard; Previous uses the same
page-readiness condition. Cached rows remain visible with the existing error
notice. Refresh page/First page/Apply remain explicit recovery actions. A
successful refresh supplies the fresh cursor before continuation and export can
resume; blocked attempts do not mutate the previous-cursor stack.

Three new regressions cover combined operation/state/UTC/page-size Apply failure,
both directions after a continuation failure with a nonempty previous stack,
and real Widget button disabling. Before the product change all three failed
on the expected assertions. After the change the focused History/Export tests
pass **25/25**, the serial complete app suite passes **228/228**, fatal-info app
analysis passes, and format/patch whitespace checks pass. The tools remain the
installed Flutter 3.47.9 / bundled Dart 3.13.7, with an Apple-first command-local
PATH and no SDK/cache/vendor modifications. Logs and source hashes are under
`/private/tmp/meshchan-1d8-pagination-review/`:

```sh
cd apps/meshchan_app
flutter test --no-pub --concurrency=1 --reporter expanded test/history_test.dart test/export_test.dart
flutter test --no-pub --concurrency=1 --reporter expanded
flutter analyze --no-pub --fatal-infos
dart format --output=none --set-exit-if-changed lib/history/model.dart lib/history/view.dart test/history_test.dart
```

This correction changes `lib/history/model.dart`, `lib/history/view.dart`,
their regression tests, and documentation. It does not change worker/core/link,
native/file output code, versions, schema, dependencies, or launch arguments.
The earlier process/native/GUI/RF results retain their original cutoffs; no new
native build or actual GUI/RF run is claimed for these two changed Dart product
files. The previous final bundles therefore predate this correction. This review
does not advance 1D.9; publication was separately authorized afterward.

## Publication preparation

After the final review, the user explicitly requested a PR. The remote default
branch is master and still points to actual PR #33 merge
`e6572af73e289b8feca57ca77537aebb8541d10c`; there is no repeated merge or
cherry-pick. The publication branch is `codex/phase-1d8-history-export`, containing
the full implementation, development-only TCP acceptance support, validation
records, and pagination correction.

The pre-publication audit covers 41 intended changed/new repository files.
Known API-key/JWT values were absent; the local hardware skill, private
configuration, fixtures, logs, screenshots and binaries remain outside Git.
All 209 tracked/new Dart source files pass formatting without changes, patch
whitespace passes, and the three files covered by the final pagination tests
still match their 228-test source hashes. Only publication documentation changed
after that software validation. The PR description retains the native/GUI/RF
artifact boundary instead of presenting earlier bundles as containing the later
pagination correction. Remote CI results belong to the published PR checks.
