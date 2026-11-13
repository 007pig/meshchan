# Phase 1 / 1D / Step 3 runtime validation

## Input and evidence identity

Implementation branch: `codex/phase-1d3-app-runtime`. The initial clean worktree,
local HEAD, remote `master` and PR #28's actual merge were all
`6b0acee049330ec7078f6ddd760a0e1c9ddab62d`. A fresh `gh pr view 28` returned
`MERGED`, merged `2026-11-13T05:42:55Z`, head branch
`codex/phase-1d2-flutter-macos`, head
`1b763457d8e503259643a6127d4674101e9bc4b3`; `git ls-remote` independently matched
master. No cherry-pick, reset, clean or history rewrite was performed.

The implementation input includes the **uncommitted** files listed in
`build/phase-1d3/20261113/final-native-inputs-v6.json`, not just the old HEAD. That
record hashes compilation inputs, including new app runtime files and native
runner changes. Software gate argv/cwd/times/exit codes and original input hashes
are in `software/validation.json`. Documentation and bounded acceptance-driver
updates made during validation are recorded separately from compiled inputs.
The final artifact audit checks compilation inputs again. No public release, tag,
upload, deployment or hardware action was performed.

Implementation status: **Implemented**. Bounded automated software and local
macOS fixture acceptance: **Passed**. The manual default-directory incidents below
are validation errors and prevent any claim that existing user data was untouched.
Remote/hardware/distribution work remains Not run.

Local host: macOS arm64 (`uname -m`, not a CI label), Flutter **3.47.9** revision
`c197ca5199`, bundled Dart **3.13.7**, Xcode **27.2 / 27B52**, Apple Clang
**21.0.0 / clang-2100.4.1.1**. Python was explicitly invoked as
`/opt/homebrew/bin/python3`, resolving to
`/opt/homebrew/opt/python@3.15/bin/python3.15`, **3.15.2**. Source native hooks
used a command-local Apple-compiler-first PATH. No SDK/vendor cache source,
global PATH, security, keychain or Xcode setting was modified. The app remains
`0.1.0-dev.3+1` (macOS `0.1.0.3`, build `1`); the other three members remain
`0.1.0-dev.3`, schema 1 and diagnostic summary 1. Manifests/lockfile are unchanged.

## Implemented boundary

| Main isolate | Worker isolate |
| --- | --- |
| Pure mode/configuration parsing, Foundation directory facts, one application controller, Widgets, pending request/query versions and supervised ports | One `CoreStorage`, retained history reports, repository queue, synchronous device gate, recording adapter and actual close |
| Generation/request-ID envelopes, stop/quit intent | Hello, sequenced owner/status snapshots, correlated values/errors, stop receipt/application and release report |
| Acknowledge a trustworthy release, then await onExit | Retain the control port until release is acknowledged; unknown release stays quarantined |

Normal main creates the runtime once outside `build()`. One `Isolate.spawn`
serves settings and bounded draft reads, with a default page size of 20 and an
app maximum of 50, explicit cursor and immutable defensive DTO copies. The fixed
fixture write uses this same dispatcher/queue and public committed `drafts.create`.
Open-success/query-failure retains the owner. Open failures distinguish core
categories from host faults and independent `cleanupUnconfirmed`. No fallback,
repair, retry, automatic restart, device enumeration or transport construction
occurs on startup/navigation. Production exposes no start-record UI or fake
transport command. All test fake resources are constructed in test-side entries.

Device admission acquires a lease synchronously before the first await. Resolution
and recording are observed async branches, so dispatcher controls remain available.
Stop has separate sent intent, received and applied facts, including pre-handshake
and pending-open cases. A real event-loop turn occurs before open/resolution and
after resolution. An observed stop blocks new resources; once record is called,
the operation's own cancel gate applies. A synchronous native call cannot be
preempted by a message that the worker has not received.

The adapter observes prepared/logical/logicalSaved/cleanupUpdates/cleanupDone/
saveUpdates/cleanupSaved/done and errors immediately. Final named results repair
missed broadcast events. Logical/cancel completion is never a cleanup barrier.
Gate release requires done plus core/host/aggregate cleanup all succeeded or
notRequired and no observation failure; save success is independent. Failed,
pending, unconfirmed and unconfirmedAfterExit do not prove release. Core close
remains the final admission/unpin/maintenance drain barrier.

`pauseAdmission`/`resumeAdmission` provide the pre-close decision boundary; resume
requires open storage, a free gate and no close started. Shutdown shares one
Future, preserves stop, drains accepted DB and device work, waits requested
maintenance, awaits one actual core close, reads only retained in-memory history
reports after close, reports release, acknowledges, then awaits isolate exit.
Resources released and worker exited are separate facts. Swift vetoes the first AppKit quit, keeps the regular event loop/window alive,
and permits a single native reentry only after Dart confirms release; window close, menu/Command+Q and cancellable Flutter
exit route to that coordinator. Native forwarding also retains a pre-handler quit.
Unknown release/worker loss prevents new work and vetoes normal termination.

Pending replies terminate exactly once with success, controlled error or unknown.
Duplicate/stale requests do not execute. Reversed reads cannot replace newer query
data; sequence/generation checks reject stale snapshots. Timeout does not cancel,
undo a commit, resend, kill or reopen. onExit alone is never native release proof.
The release-report/ack handshake prevents healthy worker exit from overtaking the
main receipt. A worker that exits without proof leaves ownership unknown.

## Test isolation and software gates

The scheme's TestAction has its own `MESHCHAN_TEST_HOST=disabled-owner-v1`, without
LaunchAction inheritance. Swift detects native-test context and supplies a strict
no-owner Dart mode **before Flutter engine creation**. Missing/invalid test
configuration fails closed. XCTest asserts the environment, pre-bootstrap window
marker, actual executable and Flutter view controller. Normal Run/Release does
not inherit the setting. Widget tests use resource-free `AppRuntime`; disposal
only removes observers. Automated tests and fixture acceptance do not use the production database.
A manual computer-use mistake did open the default directory twice; see the
explicit incident below. Foundation's compatibility path is directory-resolution
evidence; persistence is proved only with self-owned fixtures.

The sequential software run is retained under `software/`; no shared native-asset
build/test overlap was used. Results at this implementation:

| Gate | Result | Evidence |
| --- | --- | --- |
| Root enforced Flutter resolution, four members + workspace root | PASS / 0 | `pub-get.log`, `workspace.log` |
| Production/probe generation, schema and tracked artifact diff | PASS / 0 each | `generate.log`, `schema.log`, `generated-diff.log` |
| Full format, fatal-info Flutter analysis | PASS / 0 | `format.log` (724 files, zero changes), `analyze.log`; final analysis repeated |
| Python tool suite | PASS / 65 tests | `python-tests.log` |
| App/runtime/probe suite | PASS / 29 tests | `app-tests.log`, `../v6-app-tests.log` |
| meshchan_core complete suite | PASS / 362 tests | `core-tests.log` |
| meshcore_link complete suite | PASS / 180 tests | `link-tests.log` |
| meshctl complete suite | PASS / 271 tests | `cli-tests.log` |
| CLI, serial observation and datagram acceptance native bundles | PASS / 0 each | `cli-build.log`, `observation-build.log`, `acceptance-build.log` |
| Existing source/AOT/relocation smoke | PASS / 101 process checks | `smoke.log`, `smoke-evidence/` |
| Independent runtime owner/contender/reopen processes | PASS / 0 | `runtime-process.log` |
| Native XCTest host, actual arm64 | PASS / 1 test / 0 failures / exit 0 | `v3-native-tests.log`, `native-tests-v3.xcresult` |

The app tests include real worker multiple requests/commit/close; public-core
future-schema/corrupt fixtures with unchanged bytes; query errors with a tracked
owner; pending DB drain; synchronous competing device requests; pre-handshake and
pending-open stop; resolver/gate/cancel generations; registration failure/null
logical/notAttempted saves; logical-before-cleanup; done without release;
all named Future/stream errors; save/maintenance failure independent of release;
duplicate/stale/reversed events; repeated start/shutdown; worker fast fatal/exit;
lost response; and ordered release-report/ack/onExit.

Three real worker/core/fake-transport cases cover stop before resolution, actual
record followed by cancel before prepared, and an actually opened simulated
transport canceled while real cleanup waits on a worker-local Completer. The last
case responds to status/cancel/quit while cleanup is pending, preserves logical
cancellation and committed saves, then releases, closes and reopens history. Fake
transports never cross isolates. Tests import no core private hook/SQL/helper.

The independent source process gate committed draft
`faf0b699b8d187fe139f8555f4d0f1af`, revision 1, with exact
`First\r\n第二行 🙂\nLast\rEnd`. A concurrent process returned busy with no owner;
after confirmed owner close a fresh process read identical ID/revision/body.
All healthy clients ended with zero pending requests and receive ports.
The fixture path is recorded in `software/runtime-process.log`; no lock was removed.

## macOS artifacts and execution

Final results are recorded below after actual execution. Build success, legacy
probe, production runtime, native quit, relocation and signature are distinct gates.

| Gate | Result | Evidence |
| --- | --- | --- |
| Final Debug build | PASS / 0 | `v6-debug-build.log` |
| Final Release build | PASS / 0 | `v6-release-build.log` |
| Production Debug/Release multi-request commit/read/close/normal quit | PASS / 0; Opening → Ready → Stopping → Closing → Closed | `final-app-runtime-v6.json`, v6 process reports |
| Startup quit before ready | PASS / 0, quitPhase starting, no worker created | v6 `startup-quit.json` for both build modes |
| Window close and Command+Q | PASS / 0 for both, confirmed owner release and onExit | `gui-ready-controlled.*`, `gui-window-close.*`, `gui-observations.json` |
| Complete app outside checkout, different cwd | PASS; exact file/link inventory match | v6 relocated process reports, `final-native-audit-v6.json` |
| Final native assets/architecture/deep strict signatures | PASS / 0 for Debug, Release and relocated Release | `final-native-audit-v6.json` |
| Legacy 1D.2 receipt write/read | PASS / 0 for Debug and Release write/read | `legacy-probes-v6.json` |
| Real serial enumeration/device/USB/LoRa | NOT_RUN | No request or automation admits hardware |
| Remote CI / clean machine / distribution | NOT_RUN | Local workflow configuration is not remote execution |

Final owned app fixtures are outside checkout:

- `/private/tmp/meshchan-1d3-v6-debug-20261113/meshchan-1d3-sqlite`: ID
  `6dcd11a1301592e70bac169bdaad07ae`, revision 1, 30 body bytes,
  created/updated `2026-11-13T06:58:30.251339Z`.
- `/private/tmp/meshchan-1d3-v6-release-20261113/meshchan-1d3-sqlite`: ID
  `4d6a2e0166319d0f0c0069d52cd1cea6`, revision 1, 30 body bytes,
  created/updated `2026-11-13T06:58:34.349483Z`.
- Both new-process reads and whole-app relocated reads preserve those exact facts
  and the fixed Unicode/emoji/mixed-line-ending body. All healthy clients report
  zero pending requests/receive ports and confirmed close plus worker exit.

The final Debug Mach-O components are arm64. Release and relocated Release
components are universal x86_64 + arm64; actual execution and vmmap are **ARM64**.
The installed Flutter tool also applied its standard Widget Preview migration
to root `.gitignore`, adding `.widget_preview/`. That generated-cache ignore rule
is retained; no SDK source was edited.
`codesign --verify --deep --strict --all-architectures` succeeds on all final
products. `relocated-vmmap-v6.log` proves SQLite loaded from the relocated app's
own framework. Serial framework packaging/architecture/signature passed; actual
serial-native execution was **NOT_RUN**. The vmmap-only verifier had already
reported confirmed resource close/worker exit before its result window received
SIGTERM; that later process reclamation is not counted as normal quit evidence.
Independent normal-quit app processes passed separately.

`final-native-inputs-v6.json` and `final-native-audit-v6.json` both confirm unchanged
compilation inputs. Native XCTest v3 used the final Swift, scheme and isolation
code; the only later compiled-source delta is phase collection inside the explicit
runtime verifier, which native-test mode never enters. Final app tests/analysis
were rerun after that addition, and v6 native runtime reports include the actual
Opening-before-Ready sequence. Manual GUI evidence used the same normal/controller/
worker/native code before this verifier-only change. No old result is relabeled as
an execution of a different runtime or native host.

Exact command argv/cwd/exit codes are in the retained JSON records. Typical local
reproduction, using the installed SDK and explicit Python:

```bash
/opt/homebrew/share/flutter/bin/flutter pub get --enforce-lockfile
(cd apps/meshchan_app && /opt/homebrew/share/flutter/bin/flutter test --no-pub)
PATH=/usr/bin:/bin:/opt/homebrew/bin:/opt/homebrew/share/flutter/bin:$PATH \
  /opt/homebrew/bin/python3 apps/meshchan_app/tool/check_runtime_process.py \
  --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
(cd apps/meshchan_app && /opt/homebrew/share/flutter/bin/flutter build macos --debug --no-pub)
(cd apps/meshchan_app && /opt/homebrew/share/flutter/bin/flutter build macos --release --no-pub)
/opt/homebrew/bin/python3 apps/meshchan_app/tool/check_macos_runtime.py \
  --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app
```

The app guide gives the native XCTest command and scheme isolation requirements.
The complete inherited software/native commands are recorded in
`software/validation.json`; source/AOT/CLI evidence remains independent of Flutter.

## Failures, corrections and limits

Initial compilation found the missing `dart:ui` AppExitResponse import and fake
field override inference; the first Widget assertion also selected both a rail
label and its page heading. These were corrected without removing assertions.
Early logs remain under `initial/`. A default-PATH source process attempt selected
Homebrew LLVM 18 and failed `ld: library 'System' not found`; the documented
command-local Apple Clang PATH passed. No SDK/native dependency was patched.

Cross-process validation exposed a real timer retention issue: the losing
`Future.delayed` branch of `Future.any` survived a successful worker exit for 30
seconds. It was replaced with `Future.timeout`, whose timer is canceled on exit.
The final independent process gate completes without that delay. Native-hook
progress can prefix a Dart source process JSON line, so the test harness preserves
and parses the product object explicitly. Script invocation/redirection mistakes
were corrected; they are not counted as product passes. No forced process exit is
counted as a normal-release result. Failed attempts/fixtures remain retained.

The software run's initial hash map precedes a brace-only controller formatting
correction and later app acceptance-report/early-quit instrumentation. Core/CLI
inputs stayed identical. Final app tests/analysis/native builds and the final
compilation map bind the delivered app to the later source; the original map is
not relabeled as unchanged. Detailed generated data and binaries remain ignored.

No guarantee is made for forced termination, SIGKILL, system crash, native cleanup
that cannot be confirmed, unsaved future editor buffers, existing user-data
continuity or actual device behavior. Fault paths deliberately retain unknown
ownership/quarantine; cleanup of a dedicated crashed test process would only be
test-environment reclamation. Full dirty-edit decisions and the desktop input/window
matrix remain 1D.9. No public release/signing/notarization claim is made.


A manual GUI validation mistake occurred at approximately 06:38 UTC. A detached
fixture subprocess did not remain alive after its parent tool command returned.
Calling the desktop tool's getApp then automatically relaunched the Release app
without arguments (PID 71579, confirmed with `ps`), so the **real default directory
was opened**. A later desktop state query after a successful fixture title-bar
close also auto-relaunched without arguments. There were **two unintended default
directory opens**; both were stopped promptly with normal Command+Q. The visible page showed Storage ready; Command+Q immediately closed
the app normally. No device access was requested. Normal bootstrap may also have performed its bounded settings/draft reads. No
manual data inspection, database copying/export/deletion or repair/rollback was
attempted.
Core open may perform recovery/maintenance, so this record cannot promise the
existing default data was unchanged or describe the incident as a read-only check.
This is an agent validation error, not approved fixture evidence or a continuity
PASS. Subsequent GUI runs retain their parent process until normal exit and verify
PID plus full explicit `--data-dir` arguments before computer interaction, and
use process logs rather than desktop state queries after exit. No Meshchan process
remains running. `gui-observations.json` records both incidents and the bounded
manual results. The manual pending-startup UI showed Starting and accepted Device
navigation; its 30-second deadline elapsed before the quit callback, which then
reported requestUnknown with owner none and exited normally. It is responsiveness
and controlled no-owner fault evidence, not an early-quit timing PASS. The separate
automated startup-quit reports are the actual before-ready quit evidence.

The first native startup-quit attempt reached Ready in Debug and stalled before
its first frame in Release until the 120-second test timeout. That terminated test
process is **not** release evidence. The runner originally used terminateLater;
it now vetoes the first request, lets the ordinary event loop continue, and permits
one native reentry only after Dart confirms release. Explicit `quit-starting` and
`hold-startup` validation modes use a resource-free directory-resolution barrier
released after saved stop intent. They prove the early-resolve quit/control path,
not interruption of synchronous SQLite/FFI. Pending-open and active cleanup races
are separately covered by controlled worker tests. A never-created worker is now
reported as workerWasSpawned=false and workerExited=false, rather than inventing
an onExit observation.

Incremental v3 Debug/Release copies failed strict signature verification with
nested code modified/invalid. Failed copies remain in their v3 directories; the
failing Release product is retained as `failed-incremental-Release.app`.
A normal subsequent Debug build and a fresh Release bundle at the standard path
were generated with the same frozen source. No manual signing, vendor/SDK edit or
system change was used. Final v4 checks independently revalidate the whole copies.

## November 13 lifecycle review follow-up

Both review findings reproduced against the existing uncommitted 1D.3 worktree on
`codex/phase-1d3-app-runtime`, HEAD
`6b0acee049330ec7078f6ddd760a0e1c9ddab62d`. Evidence for this follow-up is separate:
`build/phase-1d3/review-lifecycle-20261113/`. The earlier native artifacts and their
input maps above remain historical; they do not validate this later controller.

Before correction, new real-isolate client tests reproduced permanent negative
shutdown caching after late release/exit and the cleanupUnconfirmed=true result
for an actual rejected SDK spawn. The exit-before-release variant also exposed
that onExit was not projected after a prior fault because `_fail` returned early.
`before-fix.log` retains all four failed regressions, including that variant's
30-second test failure-detection timeout. No timeout or test process reclamation
counts as a release result.

The controller now keeps the one stop/close process separate from its cached
outcome observation. A timeout's negative outcome and failed pending requests stay
immutable. Once the same shutdown's authoritative release and actual onExit are
both known, either event order automatically starts one memoized client-disposal
Future and updates the cached outcome for later native quit calls. It does not
repeat stop/close, resume admission, resend a request or infer release from exit
alone. If only one fact is known, quit remains vetoed. onExit remains observable
even after a prior timeout/fault.

Isolate creation is tracked as pending versus successfully created. Only rejection
of the `Isolate.spawn` call itself proves no worker could own storage. That path
reports spawnFailed with owner none and cleanupUnconfirmed=false, closes client
ports, and permits normal exit with workerWasSpawned=false/workerExited=false.
Successful creation followed by fatal/exit still retains unknown ownership until
there is release proof. The regression uses a ReceivePort-capturing entry closure
to make the real SDK reject its object graph before worker entry; it does not
replace the spawner or open a real/default database.

| Follow-up gate | Actual result | Evidence |
| --- | --- | --- |
| Focused lifecycle regressions | PASS / 4 tests / exit 0 | `after-fix-focused.log` |
| Final complete app/runtime/probe suite | PASS / 33 tests / exit 0 | `final-app-tests.log` |
| Fatal-info Flutter analysis | PASS / exit 0, no issues | `final-analyze.log` |
| Independent owner/contender/reopen, committed exact text | PASS / exit 0 | `runtime-process.log` |
| Scoped Dart format and patch whitespace | PASS / exit 0 each | `format.log`, `whitespace.log` |
| New native app build / native GUI / remote CI / hardware | NOT_RUN in this follow-up | Earlier records retain their earlier inputs |

The tests explicitly assert one shutdown request, unchanged earlier unknown
outcomes, no resurrection of timed-out requests, no quit permission with just
release or just exit, automatic zero client ports before a subsequent quit call,
and a shared verified Future for repeated subsequent calls. Existing fatal-worker,
closeUnconfirmed, real-core/fake-transport and genuine SQLite tests also pass in the
complete suite. The independent-process fixture retained draft
`458ed9fd6761aa6f28b61309a0a64fa7`, revision 1 and the exact fixed mixed-line-ending
body; the contender was busy before confirmed close and reopened afterward with
zero pending requests/receive ports.

`validation.json` records argv/cwd/exit codes, worktree and scoped input hashes.
Final source inputs remained unchanged across the gates. An initial analysis
attempt found one missing brace pair in the new test harness; that log and exit 1
are preserved, and final analysis passes after the correction. Toolchain was the
existing Flutter 3.47.9 / bundled Dart 3.13.7 on arm64, with verified
`/opt/homebrew/bin/python3` 3.15.2 (actual selected interpreter
`/opt/homebrew/opt/python@3.15/bin/python3.15`). Commands used normal SDK-cache access
and a command-local Apple-Clang-first PATH; no SDK/vendor source, global setting,
dependency, version, native runner or core/CLI behavior was changed. No desktop
automation or default-directory launch was performed in this follow-up.

## November 13 timeout-control and empty-read review follow-up

The subsequent P1/P2 review findings both reproduced on the existing uncommitted
branch at HEAD `6b0acee049330ec7078f6ddd760a0e1c9ddab62d`. Evidence is retained
separately in `build/phase-1d3/review-timeout-read-20261113/`. That directory
preserves the pre-fix controller/verifier source and hashes, failing reproductions,
final command argv/cwd/exit codes and the tested source input hashes. Earlier
records above, including the 33-test review suite and native app artifacts, retain
their earlier inputs rather than being relabeled as validation of these fixes.

The pre-fix production dispatcher/real-SQLite tests failed to obtain the first
shutdown after open, read or handshake timeout. The owner remained held, and the
delayed-Hello case could not reconcile because no shutdown ID/exchange existed.
The read-verification regression first created and successfully read a legitimate
fixture, then truncated its database with the completed receipt intact. Before
correction, failed read verification changed the file from **0 to 57,344 bytes**.
`before-fix.log` preserves all five failures. Test failure-detection timeouts are
not release evidence. Failure cleanup used the production dispatcher/core close
and acknowledged only confirmed release; failed fixtures remain retained.

The controller now separates ordinary fault state from the shutdown control
exchange. The first requested close gets a new observation after startup settles,
so a prior business/startup timeout cannot poison its wait. New ordinary work
remains faulted. A still-running worker receives one correlated ShutdownRuntime,
which applies its stop intent and drains accepted work. When the control port is
not available yet, the intent/ID survives until Hello, even beyond that close
observation's deadline. Its timer explicitly settles the observation even when
`_fail` has already recorded another fault. The previous late release/onExit
reconciliation still requires actual proof and never sends another close.

Runtime read verification now rejects a missing, nonregular or empty database
before invalidating the receipt or starting the worker, matching the finite
probe's nonempty-file requirement. The test confirms the valid write/read control
passes, the truncated file stays at zero bytes, the original closed receipt stays
byte-for-byte identical, and failure shutdown reports no worker created, no owner,
zero client ports/pending requests and permitted normal exit.

| Follow-up gate | Actual result | Evidence |
| --- | --- | --- |
| New real-core timeout/read-preflight regressions | PASS / 5 tests / exit 0 | `after-fix-focused.log` |
| Complete app/runtime/probe suite, including prior lifecycle regressions | PASS / 38 tests / exit 0 | `full-app-tests.log` |
| Fatal-info Flutter analysis | PASS / exit 0, no issues | `analyze.log` |
| Independent process busy/close/reopen and exact committed text | PASS / exit 0 | `runtime-process.log` |
| Scoped Dart format / patch whitespace | PASS / exit 0 each | `format.log`, `whitespace.log` |
| Native app build / GUI / remote CI / hardware | NOT_RUN in this follow-up | Older native records keep their own source scope |

The timeout cases assert one worker open, one shutdown request and one actual
close, resource release plus onExit, zero pending requests/client ports and exact
ID/revision/body continuity after reopen. Open/read barriers also prove the worker
receives shutdown while the resource operation is still pending. The separate
late-Hello case first observes an unknown close result, then actual close/exit and
the reconciled positive result without a resend. All barriers and wrapped public
core resources are built inside the test worker; no private core hooks, SQL or
main-isolate resources are sent across the bridge.

The independent-process fixture retained draft
`1e19dc9461eb69ba434704032070c3c7`, revision 1 and the fixed mixed-line-ending body.
The contender was busy while the owner held storage and reopened only after its
confirmed close. `validation.json` records unchanged tested inputs, the arm64 host,
Flutter 3.47.9 / bundled Dart 3.13.7 and explicit Homebrew Python 3.15.2
(`/opt/homebrew/opt/python@3.15/bin/python3.15`). SDK commands used normal cache
access and the command-local Apple Clang PATH. No SDK/vendor source, global
setting, dependency, version, core/CLI code or native runner was changed. No desktop
automation or default-directory open occurred in this follow-up.

## November 13 system-termination review follow-up

The latest P2 is valid: the previous delegate returned `terminateCancel` for the
original request and later called `terminate` again. That does not preserve an
AppKit logout/restart/shutdown request. The correction follows Apple's
[applicationShouldTerminate contract](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:))
and [terminateLater run-loop behavior](https://developer.apple.com/documentation/appkit/nsapplication/terminatereply/terminatelater),
cross-checked with the installed AppKit headers and Flutter SDK. No actual logout,
restart or system shutdown was requested during validation.

This follow-up uses the same existing uncommitted branch
`codex/phase-1d3-app-runtime`, HEAD
`6b0acee049330ec7078f6ddd760a0e1c9ddab62d`, retaining all earlier 1D.3 changes
and review fixes. Separate evidence is in
`build/phase-1d3/review-system-termination-20261113/`. `before-inputs.json` and the
five `*.before` files preserve the original inputs. Final command records contain
argv/cwd/exit codes and code/lockfile hashes, not merely the old HEAD. Prior native
artifacts and the earlier veto/reentry design above remain historical.

After bootstrap authorization, `RuntimeTermination` retains the original reply
closure, returns `terminateLater`, schedules forwarding after the delegate return,
and replies to that same request after Dart's sole shutdown coordinator concludes.
Pending requests coalesce. A positive conclusion replies true without a replacement
`terminate` call; unconfirmed cleanup replies false and keeps normal quit available
for later authoritative reconciliation. Native code does not own a second resource
drain/close state machine.

To avoid the previously observed pre-first-frame modal-loop stall, runtime directory
resolution/spawn and the legacy finite probe wait for `HostResourceBootstrap`:
first rasterized frame, then explicit native authorization. Native grants only
after Dart's quit handler is installed and while no quit is pending. Before that
monotonic grant, `applicationShouldTerminate` can return `terminateNow` without
abandoning a storage/transport owner, and later authorization is denied. Explicit
startup acceptance forwards quit on the regular run loop, saves runtime stop intent
and releases the bootstrap wait. It never resolves a directory or creates a worker
after observing that stop. Tests also stop between the frame and a pending native
reply; a late grant cannot restart the runtime. Verification-only receipt preflight
still precedes worker creation, including rejection of an empty read database.

The new strict fixture-only `quit-ready` mode asks native quit while a real ready
owner is still held, using the normal production dispatcher/coordinator. It does
not close ahead of the native request, unlike write/read verification. The existing
CI-invoked `check_macos_runtime.py` now checks this mode as well as startup quit,
persistence and relocation, so no separate test-only close implementation is used.

| Follow-up gate | Actual result | Evidence within the follow-up directory |
| --- | --- | --- |
| Focused Dart bootstrap and prior shutdown/timeout races | PASS / 13 tests / exit 0, before adding the parser case | `focused-app-tests.log` |
| Final complete app/runtime/probe suite | PASS / 44 tests / exit 0 | `full-app-tests.log` |
| Fatal-info root Flutter analysis | PASS / no issues / exit 0 | `analyze.log` |
| Final isolated arm64 native build and XCTest host | PASS / 9 tests / exit 0 | `native-tests-final.log`, `native-tests-final.xcresult` |
| Final Debug production entry, write/read/new process, relocation | PASS / all processes exit 0 | `debug-runtime-final.log`, `debug-evidence/runtime-processes.json` |
| Debug startup / live-owner Ready quit | PASS / exit 0 each | `debug-evidence/startup-quit.json`, `ready-quit.json` |
| Release build with identical source copy and enforced lockfile | PASS / exit 0 each | `temporary-pub-get.log`, `release-build-final.log`, source-copy records |
| Final Release production entry, write/read/new process, relocation | PASS / all processes exit 0 | `release-runtime-final.log`, `release-evidence/runtime-processes.json` |
| Release startup / live-owner Ready quit | PASS / exit 0 each | `release-evidence/startup-quit.json`, `ready-quit.json` |
| Original and relocated Debug/Release strict signatures | PASS / exit 0 | `artifacts.json`, both copied `signature.json` files |
| Independent source processes, busy / close / reopen / exact text | PASS / exit 0 | `runtime-process.log` |
| Legacy release finite write/read/receipt probe | PASS / exit 0 each, serial enumeration NOT_RUN | `legacy-probes.log`, `legacy-processes.json` |
| Scoped Dart formatting / final patch whitespace | PASS / exit 0 each | `format.log`, `final-whitespace.log` |
| Actual OS logout/restart/shutdown, new GUI key/menu matrix, hardware, remote CI | NOT_RUN in this follow-up | Native callback and bounded app evidence is the tested scope |

Both Debug and Release live-owner quits report quitPhase=ready, resourcesReleased=true,
workerWasSpawned=true, workerExited=true, owner=released, no error and zero pending
requests/receive ports. Both startup quits report quitPhase=starting, owner=none,
workerWasSpawned=false and workerExited=false, without creating the fixture
directory. The native tests cover original-request replies, false then later true,
duplicate requests, synchronous completion after returning Later, safe no-grant
termination and pre-handler explicit quit. A final regression reproduced a late
negative startup reply revoking an already accepted resource-free system quit
(`native-startup-race-before-fix.log`, exit 65, one test/two failed assertions).
The terminal-decision guard now ignores that late reply; the final nine-test suite
passes. The initial eight-test suite and first Debug/Release runtime passes retain
their earlier inputs in `native-tests-tmp.*`, `*-runtime.*` and
`*-evidence-initial/`. After that native-only correction, the two Swift files were
byte-checked into the same source mirror (`native-copy-updates.json`), and both
final binaries were rebuilt and revalidated in fresh fixture/relocation directories.
The 44-test Dart suite, analysis and legacy probe precede that last native-only
guard; their Dart/probe inputs are unchanged. The prior late release, rejected spawn,
first shutdown after timeout and zero-byte read regressions remain in the 44-test
suite. The independent process fixture preserved draft
`b9bc7cbc12d42e12687d3b94a914ad25`, revision 1 and the exact mixed-line-ending body.

The first native-test attempt under the checkout's Documents path was blocked
before application entry in `dyld`. A targeted TCC log identified the pending
Documents-folder permission request. It was interrupted (exit 75), not counted as
a test/normal-release pass; `native-tests.log`, `native-tests.xcresult`,
`native-host-sample.txt` and `native-tcc.log` preserve it. That attempt also spans a
comment-only native source edit and is not final-input test evidence. A second
isolated host built at
`/private/tmp/meshchan-1d3-system-termination-native-20261113` ran all eight tests.
The initial checkout Release build also stalled in Apple `dsymutil` at
CFBundleCreate/directory open. Its exact cause is not established by the sample;
the interrupted build returned 1 and remains a failure in `release-build.log` and
`release-dsym-sample.txt`. Neither interruption proves application resource release.

The safe Release retry copied 250 tracked/untracked source inputs, byte-checked
and recorded in `temporary-source-inputs.json`, to
`/private/tmp/meshchan-1d3-system-termination-source-20261113`. It used the same SDK,
unchanged root lockfile and normal Flutter/Xcode signing; enforced pub get and a
fresh Release build passed there. Native input hashes match the original checkout.
Bounded final Debug/Release runtime evidence and complete relocated apps remain at
`/private/tmp/meshchan-1d3-system-termination-{debug,release}-final-20261113`; their JSON
reports are also copied into the ignored workspace evidence directory. Reproduce
with the recorded `xcodebuild` argv and a temporary derived-data path, then run the
recorded `check_macos_runtime.py --app ... --evidence ...` commands on those products.

`toolchain.json` records macOS 27.2.1 / 26B131, actual `uname -m` arm64, Flutter
3.47.9 / bundled Dart 3.13.7, Xcode 27.2 / 27B52, Apple Clang 21.0.0 /
clang-2100.4.1.1 and explicit Homebrew Python 3.15.2. Debug native components are
arm64; Release executable/frameworks, including SQLite and serial native assets,
are universal x86_64 + arm64. Execution here proves arm64, not x64 execution.
`codesign --verify --deep --strict --all-architectures` passes for both original
products and whole relocated copies. Serial packaging is not invocation evidence;
no enumeration, port open or RF was performed. No SDK/vendor source, privacy or
security settings, global PATH, manual signing, dependency/version/schema or core
code was changed. Every app run in this follow-up used disabled-owner XCTest
configuration or an explicit owned fixture; no developer default database was
opened. Full core/CLI/native acceptance and desktop interaction outside this review
scope were not rerun and retain their earlier input-specific records.

## Handoff to 1D.4

Use the application `AppRuntime`/`RuntimeController`, its ready/owner/error facts,
`ReadOffline`, `OfflineSnapshot`, `DraftSnapshot` and `DraftCursor`. Main owns edit
buffers, dirty state and per-editor versions. Add only needed typed draft mutation
requests to the worker queue; success must follow public committed transactions,
preserve exact text and expected revision/conflict semantics, and correlate results
to the requesting editor/query version. Keep pages out of storage ownership,
recovery and shutdown. `CreateFixtureDraft` remains explicit validation-only and
must not become a product save API. This step does not implement 1D.4 screens.
