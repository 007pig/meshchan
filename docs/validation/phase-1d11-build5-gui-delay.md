# Build 5 current-source GUI and delayed-confirmation continuation

This record freezes the November 16 run-08 cutoff. Its pending normal close and
new CLI smoke were completed on November 17; the later
[run-09 completion](phase-1d11-rf-matrix-completion.md) contains fresh exact
GUI round trips, physical fault/recovery, Cancel/active Quit and the final
offline VM path. The failures and incomplete assertions below retain this cut.

Status: **candidate prepared / acceptance incomplete; the current U03 hardware
attempt failed.** This continuation does not complete 1D.11. U01 passed, U02's
A target was not started, and U03 failed USB initialization before receiving.
RF stopped without a physical action. B's actual local OK is separate from the
missing end-to-end PONG. The second GUI reopen remains pending because Computer
Use could not locate the known live window.

## Source and complete products

The baseline remains actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, tree
`e59fd975aeecdd72152424d1446683b3b647827f`, on
`codex/phase-1d11-hardware-beta`. The uncommitted beta/client changes and all
prior failures remain. No upstream openHop code, firmware, RF/duty-cycle/Fabric,
credentials, SDK or dependencies were changed. No commit, push, tag or release
was performed. Remote CI remains the separately identified PR #37 baseline;
there is no remote CI claim for this dirty source.

Owned evidence root `E` is `/private/tmp/meshchan-1d11-20261116-01`;
this continuation `H` is `E/hardware/run-08-gui-delay`. Compilation inputs are
`source-hw08-build5-input.json` and its retained source bytes/diff. The
immediate pre-GUI cut is `source-hw08-build5-ready.json`. Later documentation
and CI build-number changes do not modify the tested binary.

The complete local candidate is `E/delivery-beta1-build5/`, with fresh complete
`Meshchan.app`, matching `meshctl/`, inventories and source/build metadata.
`metadata/products.json` SHA-256 is
`edcdf862edae4733ff430feafcd08537bbce5e56afa716e93553d42d3f4e5782`.
The recursive inventory includes file hashes, sizes, modes and symlink targets;
all product links were checked to remain inside their own bundle. Runner alone
does not identify the artifact. Builds 2/3/4 remain at their original paths.

| Version fact | Actual observation |
| --- | --- |
| Link/core/CLI | `0.1.0-beta.1` |
| App manifest/fallback/recorded run | `0.1.0-beta.1+5` |
| Flutter build name / number | `0.1.0-beta.1` / `5` |
| Actual Debug and Release Info.plist | short version `0.1.0.1`, build `5`, Bundle ID `org.meshchan.meshchan` |
| Native CLI `--version` | `meshctl 0.1.0-beta.1` |
| Root lock SHA-256 | `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c` |

Python was `/opt/homebrew/bin/python3` 3.15.2; Flutter 3.50.0 stable and bundled
Dart 3.14.0; Xcode 27.2 (27B52), macOS 27.2 arm64. Apple Clang was selected
locally for native commands. Locked resolution did not change third-party
packages; the resolved graph differs from build 4 only in app build metadata.
Notices were preserved against that unchanged dependency graph. Database schema
1, diagnostic summary format 1, CLI envelope schemaVersion 1, wire version and
frozen schema files retain their independent versions.

This turn changed the planned app build number from 4 to 5 and corresponding
fallback/tests/process assertions. The previously reviewed client delayed-OK
implementation and app USB compatibility sequence are compiled into this
complete Release. No new USB retry, delay or relaxed deadline was introduced.
The later `--app-build 5` CI/documentation update describes this candidate;
historical build numbers, producer versions and persisted runs are unchanged.

## Software and native gates

The existing sequential runner retains each gate's absolute argv/cwd,
environment, source-before/after manifests, log/hash, exit code, publication and
owned descendant drain. No success-path termination or wrapper deadline was
used. The following are local results, not remote CI.

| Scope | Result and evidence boundary |
| --- | --- |
| Locked resolution and explicit four-member version check | Fresh PASS, app build 5, five internal constraints/CLI constant/app fallback |
| Flutter analyze | Fresh PASS with fatal infos |
| Complete app suite | Fresh **262 PASS** |
| Complete Python discovery | Fresh **135 PASS** |
| Runtime/draft/profile/device/diagnostic/history processes | Fresh six PASS; diagnostic passed on retained second attempt after correcting stale tooling assertions |
| Core/CLI/link suites | Inherited **362/286/207**, from the client implementation cut; not rerun for app-only build metadata |
| Debug/Release complete app | Fresh sequential config-only/Xcode builds under `H/Derived`; strict signatures and complete inventories PASS |
| Native XCTest | Fresh **22 PASS**, `-parallel-testing-enabled NO`; actual external TEST_HOST and `.xctestrun` verified, `MESHCHAN_TEST_HOST=disabled-owner-v1` before engine bootstrap |
| Native runtime | Fresh three persistence/whole-app-relocation runs and two normal Quit cases PASS |
| Finite SQLite probes | Fresh write/read PASS on the legal dedicated `meshchan-1d2-build5` fixture |
| CLI/source-only peer | Fresh complete native bundles; CLI inventory differs from the previously smoked native binary, so that earlier AOT smoke cannot identify this binary |
| Current CLI smoke | NOT_RUN for the new CLI while the second GUI lifecycle remains pending; the earlier 101 checks remain evidence for their original artifact |

Gate names use `D11-b5-*` under `E`. Three preparation/verifier failures remain
separate FAIL rows rather than being overwritten: the diagnostic process still
expected `+4`; the first finite probe used a basename rejected by the existing
fixture guard; the first independent comparison compared a `history list` row
with a `history show` result that additionally contains `configuration`.
Corrections were limited to those tools/fixtures. The passing comparison checks
the exact list projection and separately retains the full show configuration;
all six older rows are compared exactly. Product checks were not deleted or
weakened. These are not RF retries or product timeout changes.

Historical dev.2 compatibility, mobile finite dependency/API probes and earlier
schema results retain their documented cuts. They are not fresh beta mobile or
new native-binary acceptance. No mobile hooks/guards changed in this turn.

## Authorization and finite configuration

The operator renewed the same selected USB A and independent physical-radio B,
direct TCP 5050, with the reviewed client send-confirmation allocation. Other
clients were asserted disconnected and real shared-inbox consumption allowed.
Public documentation uses aliases; exact endpoint/credential references remain
only in private local configuration and owner-only evidence. Same-name slots do
not establish key equality: the limited prior A1/B3 channel audit is inherited,
not a new all-slot/key audit. A and B have distinct modem ownership.

There is no cumulative application-send ceiling. Each planned task/session
remains finite, with no automatic replay, fallback or silent initialization
retry. Failure still stops conflicting/RF work. Each case uses fresh, distinct,
nonzero IDs, fixed non-sensitive content, explicit local slots A1/B3 and direct
route descriptor 0/empty path. IDs and raw correlation stay in `H`.

| Endpoint/case | Request / send confirmation / initialization / task | Other finite parameters |
| --- | --- | --- |
| A U01 GUI Check | request 5 s / initialization 15 s | startup 0; one actual attempt |
| A U02 PING preview | 15 / default 15 / 30 / 60 s | response 15 s, maxEntries 128, 18 content bytes; A never started |
| A U03 GUI Responder | 15 / default 15 / 30 / 240 s | listen 180 s, maxResponses 2, maxEntries 128, startup 0 |
| B U02 Responder | 15 / 60 / 30 / 90 s | listen 60 s, maxResponses 1, maxEntries 512 |
| B U03 PING | 15 / 60 / 30 / 90 s | response 15 s from actual acceptance, maxEntries 512 |

B's policy preserves RTT origin before send and the original whole-task budget.
`peer_timing_policy` identifies it in both real sessions. Normal USB request/send
defaults are unchanged. A source-only peer reuses Meshchan's protocol code; it is
not an independent oracle or a product transport.

## Actual GUI/hardware matrix

The first GUI process was PID 93917 at the full delivered build 5 app path,
with explicit `H/gui-a-data`. OS argv/path and complete inventories were checked.
Computer Use drove the host GUI. No CLI diagnostic substituted for an A GUI task.

| Case | Current build 5 result | Actual evidence |
| --- | --- | --- |
| U00 offline start/preview | Partial PASS | Device initially showed no ports listed/opened, selection None, Not connected; actual worker preview matched saved finite U02 parameters. Fresh Pinyin/edit-save target not repeated; prior exact text remains historical. |
| U01 Refresh/select/finite Check | PASS | Explicit A selection; model Heltec V4.3 OLED, firmware v1.18.0-81dbae5, protocol 14, observed 21:02:19.315008Z; session/observer cleanup succeeded, Not connected. Snapshot is historical, not a live recording session. |
| U02 GUI PING | BLOCKED / A NOT_RUN | B's real task-owned first GET_MSG write was witnessed. The required 49-second remaining-listen admission window expired at 21:06:38.318363Z. CUA guard observed 21:06:41.018Z and did not click Start. No A run/send. B naturally completed duration with zero responses, 12 entries/13 reads, cleanup succeeded and exit/reap/PID absence. No guard relaxation or replacement session. |
| U03 GUI Responder + B PING | FAIL at A initialization prerequisite | A run `a6740f0243e983b7120570e0be31af80`, Start 21:09:31.521–.541Z, appVersion beta1+5. A failed initialization before receiving; B actually wrote/sent and obtained OK, then responseTimeout/waiting without matching/exact PONG or RTT. |
| U04 proven-active unplug/replug | NOT_RUN | No exact B PONG, so the physical-action prerequisite was not established. User was not asked to unplug. |
| U05 expected no-responder timeout | NOT_RUN | RF stopped after U03. B's waiting timeout does not replace this A GUI target. |
| U06 receiving-stage Cancel | NOT_RUN | Build 4 evidence retains its original artifact; no fresh build 5 active cancellation claim. |
| U07 active native Quit | NOT_RUN | First build 5 Quit occurred after task settlement; it is not this target. |
| U08 History/export/close/reopen | Partial PASS; final GUI reopen BLOCKED | Seven-row GUI export, first normal Quit and independent exact data comparison passed. Second GUI process is live but CUA window lookup failed; final closure is not yet established. |

A U03 public terminal facts: `initializationFailed / connecting`, session
`requestTimeout / initializing`, command 22 (`0x16` DEVICE_QUERY), expected
response 13 (`0x0D` DEVICE_INFO). Logical end was 21:09:46.551825Z. There were
zero response attempts, zero locally confirmed responses and zero processed
entries. The compatibility factory is used by both Check and recording; a
successful closed Check did not establish reliable initialization for the next
session. There is no native byte trace for this exact GUI failure, so the
location of the missing bytes and a root cause are not asserted.

Core cleanup and app observer cleanup succeeded; core-owned subscriptions were
not required. Adapter settled/resources released were true. Registration,
logical and cleanup saves committed with finalCleanup true; fullySuccessful
was false. These are session observations, not invented History fields.

B U03 terminal facts independently report attempted/dispatched/write/OK/
deviceAcceptanceConfirmed true, pending false; no matching PONG, exact-content
success, round-trip success or application RTT. It consumed three entries in
five reads, cleaned up successfully and exited 69/reaped. This is a failed
round-trip test, not the planned U05 expected-timeout pass. No openHop change
or further RF followed.

This continuation consumed two B sessions, **one B send attempt**, zero A
response attempts, **15 B entries / 18 reads**. Cumulative accounting is
**nine application-send attempts / 372 B entries / 382 reads**, without a
cumulative ceiling. Attempts are not total airtime, firmware retries, Fabric
forwarding or all site traffic. Zero A responses does not erase B's send.

## Persistence, export and lifecycle

Before first launch, a proven normally closed fixture was copied to the new
owned directory. Six older run projections were preserved. The existing
manually entered title `中文 🚀 beta4` and two-line body
`Meshchan 中文验收\nemoji 🚀🙂` retain their original text/version context;
the text was not relabeled beta5. All five finite presets and settings were
verified through public CLI before launch and after normal closure.

The GUI read seven History rows, zero recovered. A native Save panel published
one new file, `H/exports/meshchan-beta5-summary-run08.json`, with seven rows,
moreAvailable false, diagnosticSummaryFormatVersion 1. Its SHA-256 is
`ad41b940be4e5c7e6bd12a339521419083a6843e4036d64e23466639fdaef569`.
Safe keys and absence of content/private markers were checked. The initial
filename keyboard edit did not replace the selection; native AX setValue plus
commit corrected the actual filename before Save. No malformed file or overwrite
was published, and no complete native Select All variant is claimed.

Native Quit at 21:19:02.095–21:19:03.574Z produced exit 0/reap/PID absence and
the actual shutdown report: quitPhase ready, resourcesReleased/workerExited
true, owner released, maintenanceFailureCount/pendingRequests/receivePorts 0,
error null. Only after that did independent CLI/core open the directory.
It confirmed the new settled beta1+5 failure with no recovery, six older rows
unchanged, exact Unicode text, all presets/settings unchanged, and identical
seven safe run projections in GUI/core exports. Separate export timestamps
were not compared byte-for-byte. Every independent consumer closed and exited
before the next GUI launch. Closed fixture collections remain separate from
the subsequently live directory.

The second explicit same-path GUI launch began 21:26:02.789410Z, PID 4234.
OS observation confirmed that exact process/path/data-dir. Computer Use returned
`cgWindowNotFound` for both canonical path aliases; Bundle ID selection was
ambiguous because historical apps have the same ID. This does not prove a
crash or startup defect. No alternate UI driver, forced termination or concurrent
database reader was used. The live directory is excluded from collection;
final offline GUI reopen and normal closure require the pending handoff.

Evidence indexes include `H/preflight.json`, `U02-observation.json`,
`U03-observation.json`, `budget.json`, `gui-export-verification.json`,
`first-normal-quit.json`, `independent-verification.json`, `commands.jsonl`
and the per-gate runner records. Raw databases, logs, private configuration,
screenshots/Computer Use transcript and xcresult remain outside Git and outside
the product directories. App2 running logs are not treated as final receipts.

## Remaining work and handoff

Finish the second GUI lifecycle safely, then run fresh smoke on the current
complete CLI bundle and finalize the closure/inventory index. Complete current
GUI exact PONG in both directions, expected A timeout, receiving-stage
Cancel/active Quit, proven-active physical unplug and explicit recovery only
under a reviewed continuation after this retained failure. No retry-to-PASS or
timeout expansion follows from the unlimited cumulative send authorization.

Intermittent USB initialization remains unresolved; the bounded completion
handshake is not a reliability guarantee. No immediate disconnect, physical
recovery, real B OK delay beyond 15 seconds or Intel runtime result is claimed.
Historical IME/Dvorak/conflict/filename-preedit/Cut-Copy/full-screen/focus/
accessibility variants retain their exact coverage limits. Mobile finite probes
are not mobile business storage support; BLE, background services, content
publication/sync and automatic connect/retry/resend remain outside scope.

1E retains Developer ID/hardened runtime, notarization, installer/quarantine,
clean-machine checks and licensing/notices/corresponding-source/relinking
closure. These local directories are unaccepted candidates, not public releases.
