# Phase 1 / 1D / Step 6 — Explicit finite device checks

The subsequent [VM product GUI follow-up](phase-1d6-vm-gui.md) is separate from
the host acceptance below. It records the new guest-side runner, real Pinyin,
reboot recovery and the guest's USB/serial-mapping boundary. It does not replace
or retroactively broaden the physical USB results recorded here.

## Latest unlocked follow-up outcome — November 14, 2026

The user unlocked macOS and explicitly selected `/dev/cu.usbmodem211101` for
this task. Final Debug and Release **Device GUI, real Pinyin, navigation,
scoped Cancel and normal dirty quit acceptance passed** with the limits below.
A real pointer/composition defect in the new Device fields was fixed before the
final builds: `TextField.onTapOutside` now preserves marked text until the
existing live composition guard runs. The final app suite has **159 tests**;
final-source isolated native XCTest is **11/11**. Analysis, rebuilt products,
actual arm64 execution, final runtime/relocation and signatures passed.

Actual USB results are intentionally not collapsed into one success flag:

- Final Release completed two explicitly requested finite checks, including the
  unchanged 5 s / 15 s / 0 ms defaults. Complete information was captured from
  the selected path at `09:12:50.975509 GMT` and `09:13:05.716520 GMT`, followed by
  successful actual session and observer cleanup and **Not connected**.
- Debug's observed attempts reported controlled transport/requestTimeout failures
  and successful actual cleanup. **A complete-information success was not observed
  in Debug.** Release success does not retroactively certify those attempts.
- Both configurations passed real USB scoped Cancel and navigation, and a real
  occupied check with dirty Draft Cmd+Q Continue followed by Cmd+Q Save. Checks
  closed before owner release/worker exit. No PING/data/inbox/RF/reset/unplug,
  protocol rewrite, automatic retry or 1D.7 implementation was performed.

Latest evidence is `build/phase-1d6/gui-followup-20261114/` and the continued owned
external root `/private/tmp/meshchan-1d6-gui-uue0dyu8/`. The initial locked-session
record below remains historical. The detailed follow-up at the end supersedes
its GUI BLOCKED and USB NOT_RUN cutoff; it preserves the original failures.

## Initial outcome before unlock (historical evidence)

Implemented the product Device flow, typed application runtime API, worker-owned
finite session coordinator, independent information/cleanup snapshots, scoped
cancellation, and the healthy occupied-check database-only final-save policy.
No 1D.7 recording, PING/Responder, inbox, history UI or export was added.

Software acceptance passed on November 14, 2026. The final app suite has **158
tests**, including 34 device/session/dispatcher/worker/widget/quit cases added to
the 124-test 1D.5 baseline. Actual native tests, Debug/Release builds, runtime
processes, relocation, signatures and an explicit metadata-only probe passed.
**Actual interactive Device GUI/IME is BLOCKED by loginwindow; actual USB Check
is NOT_RUN because no exact port was explicitly selected in this task.** These
are separate evidence layers; the native probe is not a product Refresh click.

The earlier 1D.5 final four-subtype GUI, settings, Pinyin, 24 quit combinations,
11 native tests and relocated Release acceptance remain completed historical
facts. The SDK-cache-limited independent review was another evidence run. Neither
those passes nor this step's software suite certify the new physical USB flow.

## Baseline and final inputs

- Initial branch: clean `master`; HEAD
  `46c8937bee0d7d86d6bf700dbe45cad53a3126b0`.
- PR [#31](https://github.com/007pig/meshchan/pull/31) was rechecked through GitHub:
  **MERGED**, head `2661d637d2db7b24df72491bf1231b603da3c1eb`, actual merge commit
  `46c8937bee0d7d86d6bf700dbe45cad53a3126b0`. This is not a temporary merge-test
  commit. Local ancestry contains the complete reviewed head and its final
  GuardedChoice/native Command+Q corrections.
- Implementation branch: `codex/phase-1d6-device-check`, based directly on that
  real merge. No reset, clean, cherry-pick, history rewrite, commit, push, tag,
  release, binary upload or deployment was performed.
- The implementation is a dirty working tree, including new untracked source.
  `final-inputs.json` inventories every tracked/nonignored untracked input by
  path, size and SHA-256; `final-status.txt` records the actual state. HEAD alone
  does not identify the tested implementation. `code-inputs.json` is the earlier
  pre-GUI inventory; final changes after it are documented evidence, the Python
  watchdog and a README clarification. Product Dart/native input hashes are
  compared in the final receipt.
- Four workspace members and the root lockfile remain unchanged. App version
  `0.1.0-dev.3+1`, link/core/CLI `0.1.0-dev.3`, database schema 1, diagnostic
  summary 1, `org.meshchan.meshchan`, Sandbox and default-directory policy remain
  unchanged. No core/link, dependency, generated schema or runner changes.

Repository evidence root: `build/phase-1d6/20261114/` (ignored).
External owned root: `/private/tmp/meshchan-1d6-gui-uue0dyu8/`.
`outside-paths.json` records complete app, fixture, cwd, log and driver locations.
Products are copied whole; application fixtures never use the default database.
Historical protected/default-directory incidents were not investigated, deleted
or rolled back. No privacy, keyboard, signing or security setting was changed.

## Product and worker boundaries

`AppRuntime.refreshDevicePorts(generation)` returns a typed bounded metadata
result, including its request generation and a controlled top-level failure.
`startDeviceCheck(exactPath, options)` synchronously allocates a stable host ID
and returns a handle whose Future acknowledges admission only. The worker
registers the complete connect/close/host-observer work before scheduling resource
creation. No long check/cleanup occupies the ordinary 30-second RPC or database
queue. `cancelDeviceCheck(id)` is scoped and fast; status remains observable
through application snapshots. Lost start acknowledgement is not retried.

Production uses the existing owner/worker with `fixtureWrites:false`, public
`SerialPorts().listPorts()`, lazy `SerialTransport(portPath: exactPath)` and a
fresh `MeshCoreSession`. Tests inject a complete enumerator and public fake
`CompanionTransport` inside their worker entry. `tool/device_fixture.dart` and
`device_process.dart` are software harnesses, not product launch switches or
GUI developer probes. The existing finite platform probe is identified separately
below; it does not exercise the Device View or the typed product refresh API.

The coordinator observes session events before calling connect once. The real
session drives only DEVICE_QUERY (target 3) and APP_START (`Meshchan`); unsolicited
0x83 does not trigger a read. No sendChannelData, 0x0A, raw-frame subscription,
RF change, automatic retry/reconnect, recording or history entry is involved.
Transport/session/Futures/subscriptions remain in the creating worker.

Refresh obtains a synchronous short lease and releases it after ordinary
metadata return/failure; missing metadata and warnings are not connection-release
proof or quarantine triggers. A finite check takes the same gate before its first
await and holds it through actual session close and app observer cancellation.
Constructor failure closes a returned transport not yet owned by a session.
Neither failed/closed state, connect completion nor event-stream completion is
substituted for the actual close Future. A failed/unconfirmed release quarantines
the gate and retains the owner. Old lease callbacks cannot settle a newer lease.

Scoped Cancel stores intent for the captured check, reuses close and leaves
offline CRUD usable. Native synchronous work cannot be immediately preempted.
Global Stop/Shutdown additionally sets irreversible host/worker intent; Resume
cannot clear it. The legacy isolated recording cancellation regression remains
reversible under its existing contract.

## Selection, information and cleanup facts

Selection begins empty and changes only on explicit choice. Refresh never selects
the first path; a disappeared selection is cleared, failure retains stale metadata
and blocks checking until a successful refresh. No profile/default/hint/history
restores device permission. Validation rejects only a missing/blank path; a
nonblank exact path is passed verbatim. A selected B does not retarget active A.
Selection/option text belongs to the application-session model, not page lifetime.

Options are independent from diagnostic/profile resolution: defaults 5 s request,
15 s initialization, 0 ms startup. Decimal integers only, request/initialization
1–86400, startup 0–86399999 and strictly below initialization × 1000. Invalid raw
text remains visible; no clamp, fallback or taskTimeout is added. Check freezes
values; later edits affect the next attempt. No settings/schema field is added.

The latest attempt preserves its ID, source path, options, real session state,
cancel application, primary failure, session cleanup and host observer cleanup.
The independent last successful information carries a fixed UTC observation time
and source path, displayed in local time with timezone. It survives normal close,
later failures and runtime faults. Information includes parsed name/model,
firmware/build date, raw protocol code, app target, max contacts/channels,
nullable repeat/path-hash mode, advert type, signed TX dBm, distinct max TX dBm,
frequency kHz, bandwidth Hz, SF and raw coding-rate code. Public key, BLE PIN,
coordinates, raw frames and native causes/stacks are excluded from the bridge.
No complete information snapshot is serialized to ordinary product logs.

Information can be visible while cleanup is pending. Initialization failure plus
successful close permits another explicit check; information plus close failure
retains history and quarantines. Host observer failure is separate from successful
session cleanup. Normal confirmed settlement displays **Not connected**. Runtime
faults retain known fields and label retained cleanup facts; late release updates
facts without erasing requestUnknown or restoring terminal admission.

Healthy tracked occupied checks permit offline list/CRUD/resolution. During a
quit decision, the original exact target/session/ID and one-use final-save checks
remain in force, with a database-only exception for this finite check. Continue
restores offline admission while the same check remains occupied. Recording,
unknown occupants, failed cleanup, observation loss, quarantine, stop or terminal
fault cannot use this exception. Both Quit entrances share one decision and
shutdown barrier; storage/owner close waits for complete accepted device work.

## Validation results

All build/test commands used the installed SDK, with shared native-asset builds
and tests executed sequentially. The SDK was not installed, upgraded or patched.
Normal tool cache writes required sandbox escalation; the initial sandbox-only
Flutter wrapper/version calls failed before validation. The existing tool snapshot
was used with explicit FLUTTER_ROOT, suppressed analytics and no version check.

| Layer | Result | Evidence under repository evidence root unless external path is named |
| --- | --- | --- |
| SDK/Python/OS | PASS: Flutter 3.47.9, bundled Dart 3.13.7 macos_arm64; `/opt/homebrew/bin/python3` 3.15.2 | `toolchain.json`; actual executable paths recorded |
| Locked workspace, production generation/schema | PASS, no lock/schema/generated changes | `locked.log`, `generate.log`, `schema.log`, `results.json` |
| Format/fatal-info analysis/whitespace | PASS | `final-format.log`, `final-analysis.log`, final receipt |
| App form/Widget/session/dispatcher/real isolate/quit | PASS, **158 tests** | `final-app-tests.log`; `final-software-results.json` |
| Real public session + app fake transport | PASS: fresh sessions, pair only/no inbox, stage cancellation, timeouts/no retry, information-before-close, constructor/observer/close failures | `device_check_test.dart`, app log; no physical serial |
| Product worker/process | PASS: typed refresh/start/cancel, blocked cleanup, offline final saves, delayed/lost ack, stale cancel, stop latch, contender/reopen, no diagnostic history | `final-*-process.log`; external `*-process/` fixtures/logs |
| Dirty quit | PASS: Draft/Profile/Settings × Save/Discard/Continue; concurrent Quit; pending Profile A/create → B/final save keeps one ID | `device_quit_test.dart`, final app log; software timing |
| Quarantined close failure | PASS as a failure assertion: info retained, owner held, no normal exit | external `device-process*/fault.log`; fault child exit is explicit reclamation, not release proof |
| Existing Draft/Profile/runtime regressions | PASS, included in final app and independent process gates | `final-app-tests.log`, `final-{runtime,draft,profile}-process.log` |
| core/link/CLI/Python | PASS: **362 / 180 / 271 / 65** tests | `core-tests.log`, `link-tests.log`, `cli-tests.log`, `python-tests.log` |
| Native bundles/source/AOT/relocation | PASS: **101 process smoke checks**, five datagram scenarios in source and AOT | `*-build.log`, `smoke.log`; existing synthetic smoke only, no new RF operation |
| Final Debug/Release builds | PASS | `debug-build.log`, `release-build.log`, `artifacts.json` |
| Isolated native XCTest | PASS, **11/11**; host/products, execution derived data and final xcresult all external; disabled-owner before engine | `external-native-path-preflight.json`, `external-xctestrun-preflight.json`, `native-final-command.json`, `external-native-tests-final.log` |
| Debug/Release runtime/startup/live-owner quit, finite SQLite probe and whole-app relocation | PASS | `native-results.json`; external `runtime-{Debug,Release}/`, `logs/probe-*` |
| Actual execution/signatures | PASS: Debug sample ARM64; relocated Release NSRunningApplication CPU_TYPE_ARM64 16777228; deep/strict/all-architectures checks | external `evidence/release-architecture.json`, `logs/debug-no-window.sample.txt`, signature JSON; `final-artifacts.json` |
| Native metadata | PASS through explicitly requested existing finite metadata-only probe; no selection/open/session | `native-metadata-probe.json`; **not** a Device GUI Refresh pass |
| Actual interactive Device GUI / Pinyin / physical CmdQ/editor regression / relocated GUI lifecycle | **BLOCKED**: frontmost `com.apple.loginwindow`; reliable target focus unavailable; no GUI/IME action counted | external `evidence/window-facts.txt`, `logs/debug-initial-gui.log`, input-before; no settings changed |
| Actual USB finite Check/Cancel/navigation/quit | **NOT_RUN**: no exact path explicitly selected in this task | Follow-up below; metadata alone is not permission |
| Remote CI / x86_64 execution / clean-machine distribution / full USB/LoRa/unplug | **NOT_RUN**, outside current local evidence | CI wiring added; 1D.11 retains hardware/beta scope |

Initial software failures were fixed and excluded from final passes: stale
placeholder text assertions, a test helper calling history.list instead of query,
a Widget fixture awaiting real session preparation under a virtual clock, a
cross-isolate instance-identity assertion, and a duplicate runtime-fault text
finder. Final app tests passed after these corrections. A later standalone
watchdog process invocation inherited the wrong compiler-first PATH and failed
native hook linking with Homebrew LLVM. Repeating that specific gate with the
documented command-local Apple Clang PATH passed; no SDK/cache/vendor source or
global PATH was changed. Original failures remain in ignored evidence.

The first native XCTest execution wrote its xcresult to Xcode's default global
DerivedData path (outside Documents but not this run's owned directory). The
final run explicitly supplied external execution derived data and resultBundlePath;
only that final fully owned run is the location-isolation acceptance. Repetition
was justified by the unresolved result-location preflight, not pass counting.

GUI preflight initially reported no accessible window. Exact native process
inspection then proved a real window/ARM64 process, existing AX/event/screenshot
permissions and loginwindow as foreground. No real Pinyin preedit or physical
button/shortcut action was attempted. The unused initial fixture was closed via
normal AppKit termination; existing shutdown logs confirmed release, worker exit,
zero RPCs and zero receive ports. Relocated Release also closed normally after
its architecture observation. Initial input source was US with Caps Lock off;
this run did not alter input mode. The user was asked asynchronously to unlock
for the remaining GUI checks. No password, permission or security change was
requested. The original 1D.5 actual Pinyin evidence is not relabeled as this step.

## Initial remaining acceptance and 1D.7 handoff (historical)

After the macOS session is unlocked, explicitly launch the complete final Debug
and Release app with a new external owned `--data-dir`, cwd and logs. Verify PID,
bundle, exact argv and focus before every UI read/action. Confirm initial no
selection/no access, click Refresh, inspect actual metadata/warnings, validate
option input and navigation, and repeat real Pinyin preedit/guard/natural-commit
plus dirty native Quit checks. After Quit use OS state and existing logs only;
never read a closed app UI and accidentally relaunch the default directory.

For physical USB acceptance the user must select an exact currently enumerated
path in this app session (or explicitly provide the exact path for this task).
Refresh/Select must not check. Click Check to observe initialization, source/time,
actual cleanup and Not connected; explicitly repeat using a fresh session.
Observe applicable Cancel/navigation/normal Quit release without inbox drain,
RF/data/PING, reset or unplug. Do not infer wireless or authenticated identity
from ready. Cleanup may remain pending without a native completion bound.

1D.7 must acquire this same device gate after a check actually releases. Use a
new lazy transport/session factory for every recording invocation, never reuse a
check session or automatically reconnect/check. Port selection and resolved
profile parameters stay independent. Preserve scoped cancel/global stop,
information/cleanup separation, database-only final-save limits, IME barriers
and the sole quit coordinator. Do not add device information to historical
summaries. This step does not start 1D.7.

## Unlocked GUI and explicitly selected USB follow-up

The user explicitly authorized `/dev/cu.usbmodem211101` after unlocking the Mac.
Before work, all 285 prior input hashes and prior external product hashes matched.
The same task branch/HEAD and installed SDK/Python were used. No commit or push
was performed. This follow-up changed only the Device outside-tap behavior and
its focused-mouse regression, plus documentation. Core/link, protocol, budgets,
dependencies, schema, versions and native runner code remain unchanged.

### Defect, correction and excluded attempts

The initial actual Debug Pinyin test established underlined `zhong wen` and a
real Chinese candidate panel in the Device request field. Physical pointer-down
on the port selector caused default TextField outside-tap handling to end
composition before `GuardedChoice` could reject opening the menu. This was a real
new Device defect; it is not counted as a pass. `UnlockedDebug-*-device-ime-*`
evidence preserves it. The fix adopts the existing Draft/Profile policy,
`onTapOutside: (_) {}`, on all three Device fields. It preserves controller,
selection and composing identity; it does not force unfocus or clear composition.

The new macOS regression focuses the actual TextField, sends a valid selection
and composing range, and uses mouse events on the selector and Refresh. It
checks focus/composition retention, no popup and no second enumeration for all
three fields. An early harness assertion targeted a read-only SelectableText's
EditableText and was corrected to the TextField descendant. The corrected test
fails without the product fix and passes with it. The complete **159-test** app
suite and fatal-info analysis then passed (`app-tests.log`, `analysis.log`,
`rebuild-results.json`). No test failure is presented as final acceptance.

The first incremental Debug/Release build left an outdated outer app seal for
App.framework, although nested frameworks individually verified. Failed products
were retained under external `apps/IncrementalFailed{Debug,Release}/`; no manual
re-signing or signing-setting change was used. Moving only these owned generated
app bundles caused the normal Flutter/Xcode build to regenerate the app/seal.
Both source products and complete external copies passed deep/strict/
all-architectures verification (`fresh-products.json`). Final GUI uses only
`apps/FinalVerifiedDebug/Meshchan.app` and `apps/FinalVerifiedRelease/Meshchan.app`.

The first direct-launch preflight ended before NSApplication registration; no GUI
or normal-release pass is claimed for it. The driver now waits for registration
and starts an independent process session. A Release Draft preedit attempt also
failed under a driver that redundantly raised the window before observations/
actions. That run saved intermediate Latin text and is excluded from IME passes.
The driver was corrected to avoid redundant AXRaiseAction and to prohibit
reactivation in strict preedit actions. With the product unchanged, actual
preedit/candidates, pointer Save/navigation/Cmd+Q deferral and natural exact commit
then passed. Original failed state files remain. No settings or SDK were patched.

### Actual final GUI matrix

Every driver invocation checks the live PID, `org.meshchan.meshchan`, exact
owned fixture argv, foreground and keyboard-focus owner before input/read. Native
focus receipts include app-level focus/window evidence and launcher-overlay
checks. The full app, fixture, actual process cwd, logs and driver are external.
Final Debug ran from the owned run root; Release ran from its distinct `cwd/`
directory, corroborated by OS process cwd inspection. Final Release's public
NSRunningApplication architecture was CPU_TYPE_ARM64 `16777228`. Debug was also
queried as actual arm64. No x86_64 execution is claimed.

| Actual final product check | Debug | Release | Evidence in external `evidence/` unless specified |
| --- | --- | --- | --- |
| Initial Device no enumeration/selection; 5/15/0 defaults | PASS | PASS | `Final*-device-initial.png`, default clipboard checks and state files |
| Native Refresh, explicit exact-path choice, Select does not Check | PASS | PASS | metadata, menu and selected snapshots; no first-item selection |
| Invalid raw input/cross-bound, navigation/selection retention | PASS | PASS | invalid request/startup and navigation snapshots |
| Device real Pinyin preedit/candidates; pointer menu, navigation and physical Cmd+Q deferred; exact natural `5中文` commit | PASS | PASS | `Final*-device-ime-*-region.png`, exact clipboard checks |
| Actual USB Cancel after navigation; same captured path/options; real cleanup | PASS | PASS | cancel active/return/settled states; both cleanup facts succeeded |
| Information retained across later canceled attempt and navigation | Software proof plus no successful native Debug info | PASS | Release history text/time before and after cancel compared exactly; `FinalRelease-historical-info-after-cancel.png` |
| Draft actual Pinyin pointer Save/navigation/physical Cmd+Q deferral and natural commit | PASS | PASS after driver correction | Draft preedit/deferred region screenshots and exact clipboard checks |
| Basic offline Profile/Settings save and return to Device | PASS | PASS | profile/settings state files and independent stored JSON; limit 1234 |
| Active real check + dirty Draft Cmd+Q Continue, then Cmd+Q Save | PASS | PASS | quit-check-active, continued, quit dialog, shutdown logs and independent reads |
| Discard and native exit | PASS, physical Cmd+Q Discard | PASS, native window-close Discard | final second-launch state/quit receipts; committed content unchanged |
| Restart does not restore port permission, check options or info | PASS | PASS | reopen no-device/selected-none/default checks; profiles/settings/drafts persist |
| Narrow window and scroll | PASS, 850×650 Device attempts/error views | PASS, 850×650 new-session Device view | `FinalDebug-narrow-*.png`, `FinalRelease-narrow-reopen.png` |
| Exact Chinese persistence, no diagnostic history | PASS | PASS | Debug title `FinalDebug Draft 中文`; Release body `Draft IME 中文 | Final save during check`; public CoreStorage independent reads have `historyCount:0` |

The startup delays of 10000 ms for Cancel and 60000 ms with a 90-second
initialization budget for dirty quit were explicitly set in the GUI to give
control observations time before initialization commands. They are genuine
session options, not fake cleanup delays or an application retry policy. The
same real close barrier remained authoritative. Normal product launch used only
explicit `--data-dir`; no fake transport, fixtureWrites, developer probe, CLI
adapter or GUI injection was used for these hardware/IME results.

After each quit only OS process state and existing logs were read; subsequent
GUI sessions were explicitly relaunched with fixture arguments. Independent
inspection opens only the normally closed owned fixture through public core APIs
in a separate process with an external cwd. All final normal quits reported
resourcesReleased/workerExited true, pendingRequests/receivePorts zero. The
inspector also awaited actual close. Default/protected user data was not opened.

### Physical USB outcomes

`hardware-attempts.json` records each observed attempt separately. Final Release
check 1 (5/15/0) and check 2 (5/15/2000, an explicit separate GUI action) obtained
complete info and then closed. Reported protocol code **14**, initialization app
target **3**, firmware **v1.18.0-81dbae5**, and model **Heltec V4.3 OLED** appeared
as separate fields. The UI displayed TX 10 dBm/max 22 dBm, frequency 869618 kHz,
bandwidth 62500 Hz, SF 8, raw coding-rate code 8, repeat false and path-hash mode
0 without treating false/0 as unavailable. Node name was shown only as local
untrusted display text. No key, BLE PIN, coordinates or frame was bridged/logged.
These are reported initialization facts, not authentication or radio acceptance.

The pre-fix Debug default attempt timed out waiting for DEVICE_INFO. Final Debug
check 1 reported transport failure at DEVICE_QUERY, check 2 with explicitly set
2000 ms startup timed out waiting for SELF_INFO, and a fresh-app default attempt
also timed out waiting for SELF_INFO. Each retained its controlled primary reason
and actual successful cleanup, with Not connected and usable offline storage.
No Debug complete-info success is claimed, no cause is guessed from exception
text, and no protocol/flush/retry/default-budget change was made to force a pass.
The Release successes do not erase these failures or establish broad USB
reliability. Full real USB/LoRa, unplug and beta acceptance remain 1D.11.

### Final software/native receipts and input state

The final-source app suite passed **159/159**, including the new regression.
Final-source native build/test used a fresh owned derived-data/host/products tree,
preflighted xctestrun disabled-owner environment, and explicit external execution
derived data/resultBundlePath: **11/11 passed**. Final Debug and Release also
passed the existing check_macos_runtime.py startup/live-owner quit, SQLite and
whole-app relocation gate (`native-final-results.json`). Prior unchanged
core/link/CLI/Python and source/AOT smoke results above remain separate evidence.

Current follow-up input preference was Pinyin with Caps Lock off, superseding
the earlier locked run's US state. Command+Space and actual native key events
established real marked text/candidates; Control+Space was never used. Natural
Space committed exact Chinese. A final Release owned-fixture mode check verified
real Pinyin again and was discarded through normal native window-close, with
independent read proving the stored Chinese body unchanged. Source ID alone is
not the Pinyin evidence. `followup-input-final.json` and the final-mode preedit
region are the receipts. No keyboard/privacy/security setting was changed.

Final source (including nonignored untracked files), helper and complete artifact
hashes are captured in this follow-up's `final-inputs.json`,
`validation-helpers.json` and `final-artifacts.json`; `final-status.txt` records
the dirty tree. The original input/artifact/blocked receipts remain historical.
No required GUI work remains blocked by loginwindow. The remaining physical
limitation is the unobserved Debug complete-information success, plus the
explicitly deferred 1D.11 stability/RF scope. 1D.7 was not started.

## Commit preparation

At the validation cutoffs above, the implementation was uncommitted and had not
been pushed. The user subsequently explicitly requested `git commit push`.
Before staging, all 285 tracked/nonignored untracked inputs exactly matched the
final follow-up inventory, with no added or missing inputs. Remote master still
pointed to the actual PR #31 merge commit and the 1D.6 branch did not yet exist
remotely. This delivery note is the only change after that inventory; tested
product, test and CI inputs are unchanged. Validation is reused rather than
rerun for this documentation-only receipt. The interrupted review produced no
completed independent review result and is not counted as review acceptance.
Ignored fixtures, logs and binaries are excluded from the commit. No merge,
tag, release, upload, deployment or 1D.7 implementation is part of this delivery.
