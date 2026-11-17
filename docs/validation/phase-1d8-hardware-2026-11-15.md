# 1D.8 hardware follow-up: November 15, 2026

Artifact boundary: the later [pagination review correction](phase-1d8-history-export.md#pagination-review-correction)
changes two Dart product files after this record's GUI/RF runs. The hardware and
file results below apply to the stated Release hash; that binary does not
include the later pagination correction.

Status: **finite CLI RF matrix, recorded Release app PING, real GUI Cancel,
active-hardware native Quit, independent reopen, and actual new-file export
PASS**. Application sends total **15 of the authorized maximum 18**. Initial
failures remain below; USB initialization is still intermittent. The full host
existing-target validation path is now **PASS** after the user explicitly
authorized clicking Replace on the task-owned test file. The initial automatic
approval block remains historical evidence; the resumed panel rejected the
target and independent byte/metadata checks confirmed no overwrite. Native
no-replacement tests retain their separate evidence. The local hardware skill
is installed outside Git.

## Source, tools, and isolation

Branch: `codex/phase-1d8-history-export`, HEAD
`e6572af73e289b8feca57ca77537aebb8541d10c`, with the existing uncommitted 1D.8
implementation preserved. The 48 app Dart/native product source files still
match the final 1D.8 product manifest. This follow-up does not change app, core,
link, or CLI production source, versions, schema, summary format, dependencies,
public API, or production launch arguments.

Host: macOS 27.2.1 (26B131), arm64. Python:
`/opt/homebrew/bin/python3`, 3.15.2. Dart: the installed Flutter SDK's bundled
3.13.7; no SDK/channel/cache/vendor modification or upgrade. Native builds use
the installed Apple compiler. The Swift diagnostic helper's module cache is in
the owned evidence directory, following an initial compilation that did not
start because the default cache location was not writable.

Evidence root: `/private/tmp/meshchan-1d8-hardware-gd63lmj4`. Secrets are outside
Git in its mode-0700 `secrets` directory; JWT is mode 0600. Credentials, complete
configuration responses, and exception bodies are absent from this record.
Authentication used the user-specified external password-copy script and
`POST /auth/login`; no password change occurred. Token expiry requires a fresh
login after the pause, not an RF retry.

A new native CLI was built with:

```sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart build cli \
  --target=bin/meshctl.dart \
  --output=/private/tmp/meshchan-1d8-hardware-gd63lmj4/cli
```

The current executable SHA-256 is
`f0edd287ae4bb65d353f392d7496d03a8213c17ba84fc18083b884a4e48d333a`.
`candidate-manifest.json` records all three native bundle files. A source-only
OpenHop peer was also built as a native diagnostic comparison; it did not
establish a Companion connection. It is not a new product transport.

## Real USB observations

The user explicitly selected `/dev/cu.usbmodem211101`. A pre-command attempt
with `--data-dir` was rejected before device work: `info` does not use storage
and does not accept that option. Database-using tests retain explicit owned
directories. No other listed serial port was opened.

After the first failure, the user explained that USB initialization had
previously required several attempts. Subsequent zero-RF initialization was
bounded to three total invocations, each after the previous process exited.

| Invocation | Actual result |
| --- | --- |
| Native info 1 | Exit 69; initializing DEVICE_QUERY (22) request timeout; no RF |
| Native info 2 | Exit 69; initializing DEVICE_QUERY transport failure; structural unassociated-response facts retained; no RF |
| Native info 3 | Exit 0; actual ready, closing, closed transitions; initializationCompleted/sessionClosed true |
| Debug app check 1 | APP_START (1), expected 5, request timeout; session and host cleanup succeeded |
| Debug app check 2 | Closed successfully; session and host cleanup succeeded; historical device information shown |

The successful information reports Heltec V4.3 OLED, firmware
`v1.18.0-81dbae5`, protocol 14, frequency 869618 kHz, bandwidth 62500 Hz, SF 8,
coding-rate code 8, TX 10 dBm. A success does not explain or repair the preceding
initialization failures, and does not establish a reliability percentage.

Host GUI navigation/Refresh/check/History used Computer Use after the user's
explicit preference. The initially used task-owned native GUI driver was then
retired from UI interaction. No Chinese input-method testing occurred. The
Debug owned database showed an empty History page and completed maintenance
with zero deletions, limit 1000, no sticky failures.

### Incidental Computer Use relaunch: isolation deviation

After normal Quit, Computer Use's inventory still reported Meshchan running.
An ensuing app-state read automatically relaunched the bundle without arguments.
This was detected from a new PID, 99888, without `--data-dir`; it was disclosed
and closed through the normal Quit menu, without further document actions.
The effect of core startup on default storage was not inspected and is not
claimed absent. That incidental instance is excluded from test acceptance.

Independent OS process inspection confirmed both the original owned PID 95085
and incidental PID 99888 absent. The owned fixture's actual owner lock was
available afterward. No closed-app UI query was used for the final check. The
incidental relaunch is not a successful isolation test or an owner-release receipt.

## OpenHop and network diagnosis

Read-only management projections report Repeater 1.1.5.dev231, Core 1.1.4.dev9,
registration `007-02` mapped to TCP 5050, matching frequency/BW/SF/CR, TX 16 dBm,
preamble 16. No explicit Companion tcp_timeout was returned. Fabric is bridge,
origin_tx=all, repeat_on_ingress=true, default local, with local/link radios.
The user confirms link is currently on, the local modem is physically distinct
from USB A, and other clients are disconnected. No deployment setting changed.

| Observation | Actual result |
| --- | --- |
| Python authenticated REST listing/self_info/channels | HTTP 200, success true; necessary metadata only |
| Dart peer from IDE agent | REST preflight failed, WS attempted false, cleanup succeeded |
| Native peer from IDE agent | Same REST-stage failure, WS attempted false |
| Dart TCP to router 192.168.1.1:443 | Connected; subsequent HTTPS certificate validation failed, without bypass |
| Dart TCP to OpenHop <private-peer-host>:8000 | SocketException, errno 65 |
| Python TCP to the same two management ports | Both connected |
| Explicit IPv4, local source address, known deployment hostname | OpenHop still errno 65; no routes/settings changed |
| User's first manual command, later clarified as IDE integrated Terminal | Same three errno-65 results; not an independent Terminal control |
| User's second command from independent Terminal.app | All three REST requests HTTP 200, success true |
| Native Network.framework probe from agent | waiting, path unsatisfied, unsatisfiedReason localNetworkDenied |

The last result follows Apple's diagnostic guidance and distinguishes the
current process's denied network path from a presumed remote-server failure.
It does not prove the underlying permission-cache defect or guarantee a restart
will repair it. Router reachability alone did not settle that question.

Computer Use read-only inspection confirms `IntelliJ IDEA.app` Local Network
switch **on**. Only one indexed installation was found:
`/Users/xiaoyu/Applications/IntelliJ IDEA.app`, bundle ID `com.jetbrains.intellij`.
The current executable UUID, `D4151CCE-BFBA-355E-8F7C-0F68F6D18E4D`, matches the
system's local-network attribution logs. Its JetBrains Developer ID signature
and stapled notarization ticket are present. The command parent chain leads
through Codex ACP to this same IDE.

The two newly built Dart AOT tools share executable UUID
`4C4C44A1-5555-3144-A11C-87B4518F022D`. Apple documents shared UUIDs as another
possible local-network identity problem; this is a diagnostic clue, not a
demonstrated cause here. No executable UUID or signature was modified.

Primary references:

- [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): responsible application identity, Terminal behavior, Network.framework denied-path diagnosis, executable UUID considerations.
- [JetBrains SUPPORT-A-564](https://youtrack.jetbrains.com/projects/DBE/articles/SUPPORT-A-564): IDE LAN failures despite enabled permission; refresh the existing Local Network toggle and check normal Terminal behavior.

Computer Use refused Terminal.app for safety reasons. No other terminal UI was
used to bypass that restriction. The user performed the independent control.
A proposed fixed external-terminal hardware workflow received only a no-device
dry-run, then was deleted at the user's explicit request. It was never executed.

## Tool changes and software validation

The preparation tool can explicitly capture B's reviewed 15-second command
budget while retaining A's 5-second budget. The runner requires a current,
explicit native manifest covering all bundle files instead of a hard-coded 1B.9
baseline; it stops on case failure. Initialization defaults to one invocation;
an explicit current authorization can select at most three initialization-only
attempts after successful cleanup, before RF/consumption. It never retries an
RF attempt. These changes do not enable hardware in CI.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
git diff --check
```

Python **70/70 PASS**, including changed-byte/missing-asset/path validation,
captured endpoint budgets, stop-before-later-case behavior, and bounded
initialization-only retries with no repeated RF. The existing CI discovery
includes these tests. `python-tests-retry.log` is the final software evidence.
No app/core/link suite rerun is claimed for these Python-only changes; the
preceding 1D.8 validation retains its own source/artifact cutoff.

## Initial pause and successful network resume

The user redirected work to fixing IntelliJ network access and requested a pause
if an authorization refresh requires IDE restart. All owned app processes have
closed. RF, current channel-key comparison, passive-window observation, recorded
hardware PING/Responder Cancel/Quit, and real hardware-derived export remain
**NOT_RUN**. A missing effective idle timeout is still unknown.

At the initial pause, the next step was the JetBrains-documented refresh of the existing IntelliJ Local
Network authorization and a user-controlled IDE restart. No system privacy,
network, VPN, signing, SDK, or server configuration was modified by the agent.
After restart, rerun the same read-only REST and Network.framework probes from
the IDE. If they pass, obtain a fresh JWT as needed, finish zero-RF readiness,
key and idle-window checks, then resume the existing finite 18-send scope.
No external-terminal workaround, extra hardware script, or RF resend is
authorized by that pause. The local skill remains conditional on successful
hardware acceptance and must stay outside Git.

After the user's restart, the same IDE-launched Dart REST probe returned three
HTTP 200/success results. The same Network.framework probe returned ready,
pathStatus satisfied, instead of localNetworkDenied. Evidence:
`post-restart-rest.jsonl`, `post-restart-network-path.json`. This establishes
the observed recovery after the user-controlled restart, without claiming which
internal OS cache or IDE mechanism caused it.

## Explicit TCP continuation and real RF

The resumed WS info session reached real ready and closed successfully. Its
following passive probe failed before the 95-second window, with webSocketClosed
and successful cleanup, zero RF and zero queue reads. Its output file spans
approximately 5.25 seconds including startup; the reported zero ready-window
duration is not an accurate time-to-failure measurement because no closing-state
timestamp was captured on that failure path. The user confirmed other clients
disconnected. Current timeout metadata did not establish an effective timeout;
the documented logs endpoint returned HTTP 404. No cause is asserted.

The user then explicitly selected direct TCP 5050 using a development-only
adapter. It reuses the public serial codec, CompanionTransport, Session, and
existing tasks, with no transport fallback or reconnect. The product remains
USB-only. Direct TCP info initialized and closed successfully. Its passive probe
observed **95008 ms**, established a **95-second lower bound**, sent only opcodes
22/1, read no inbox, sent no RF, and closed successfully. It does not establish
the exact configured timeout. Evidence: `h0-b-tcp.jsonl`,
`tcp-passive-evidence.json`.

Three channel-audit invocations failed during A initialization, before any
GET_CHANNEL or RF, with successful cleanup. After the user physically unplugged
and replugged A, metadata reconfirmed the same explicitly selected port. The
first new audit passed: queried A slot 1/B slot 3 return equal 16-byte keys and
both close successfully. Uniqueness is within those queried slots, not an
all-slot audit or a claim about hidden extended keys. Evidence:
`tcp-audit-{1,2,3}.json`, `ports-after-replug.json`, `tcp-audit-replug-1.json`.

The existing finite runner used the current candidate manifest and explicit
`--initialization-attempts=3`, A command 5 seconds/B 15 seconds, fixed Direct
routes, maxEntries 128, and the original response/entry limits. No case with an
RF failure was retried. Seven zero-RF A initialization failures were retained
across H1/H3/H4/H5/H7 before their accepted successful invocations.

| Case | Result | Actual sends | Specific evidence |
| --- | --- | --- | --- |
| H1 | PASS | 1 | A raw send, B exact payload match, exits 0/0, cleanup |
| H2 | PASS | 1 | B raw send, A channel/type/length reception, exits 0/0; no exact A body claim |
| H3 | PASS | 2 | A exact PONG, RTT 2644818 us, local acceptance, cleanup |
| H4 | PASS | 2 | B empty-content exact PONG, RTT 2829926 us, A response confirmed |
| H5 | PASS | 2 | 131-byte binary content exact PONG, RTT 6358613 us |
| H6 | PASS | 1 | Expected A exit 69, local acceptance, responseTimeout, null successful RTT |
| H7 | PASS | 2 | B exact PONG, RTT 3488569 us; A still active then SIGINT, exit 130, one response, cleanup |

Total **11/12** allowed matrix sends. These are application attempts, not total
airtime or radio/forwarding counts. Link remained enabled and Fabric origin_tx
was all, so this is end-to-end USB/OpenHop RF evidence, not isolation of one B
modem. `matrix-results/results.json` retains every invocation, actual cleanup,
counts and failures; `execution-plan.json` binds source and native hashes.

## Recorded Release app PING and GUI follow-up

Release PID 18584 was explicitly launched with the owned `fixtures/release`
directory, containing three presets created through the public CLI profile API.
Computer Use selected the explicit USB port, Hardware PING preset and 17-byte
ASCII content, then previewed the saved channels/budgets/Direct route. A finite B
responder reached actual ready before GUI Start and record.

The first app attempt completed with exact PONG, local OK/device acceptance,
RTT **2741258 us**, core cleanup succeeded, core subscriptions notRequired,
app observer cleanup succeeded, and committed registration/logical/final cleanup
saves. Run ID: `f7c3471bb315a4bade0d7a08ec38f46b`. The session's fully-successful
observation was true. This field and save-attempt observations were not claimed
as persisted history fields.

Read this run from history performed a separate persisted read of that ID and
showed settled, matching saved logical/cleanup facts, and no recovery. Apply
loaded the actual first page with one record. B separately completed with exactly
one confirmed response and successful cleanup. Total real sends so far are
matrix 11 + app A/B 2 = **13/18**. Evidence: `ui-ping-b.jsonl`,
`ui-observations.json`, Computer Use AX output and screenshot in this session.

Computer Use later encountered stale element IDs, cgWindowNotFound and
noWindowsAvailable during menu selection. The user restored/foregrounded the
existing window. Independent process inspection retained the same owned
PID/arguments. No alternative GUI driver was used to work around those failures.
Offscreen Flutter input clicks did not consistently focus the intended field;
AX setValue could report text without changing the actual controller. The
resulting invalid or unintended previews were not executed. Actual preview
confirmed request 15 s / initialization 15 s before the subsequent Starts.

### Real Cancel and retained unsuccessful initialization

Run `1ce9ea91bb8f6059028c316a820a4188` reached receiving/session ready and was
canceled using the application's Cancel button. It observed zero response
attempts, core cleanup succeeded, host subscriptions notRequired, app observer
cleanup succeeded, and committed registration/logical/final cleanup. This is
real hardware cancellation, not a fake or an initialization timeout. No B sender
ran for this case.

Other attempted Cancel observations included three initialization failures and
one naturally completed 60-second listener. A later explicit 15-second request
budget attempt failed immediately at DEVICE_QUERY with a transport failure,
before the successful Cancel. These failures and the natural completion are
retained; none is a Cancel pass. Additional Quit-preparation attempts failed at
APP_START with the actual total initialization deadline. All seven app
initialization failures were settled with successful cleanup and zero responses.
No claim is made that a larger budget fixed USB initialization.

### Exact PONG, normal Quit, then active-hardware Quit

The first B invocation mistakenly used the earlier pre-TCP native peer. It
reported authenticationOrSelectionRejected before send and cleaned up; it is
`ui-quit-b-old-ws.jsonl`, not a TCP or RF result. The next source invocation
selected Homebrew Clang and failed its build hook before the peer ran. The
documented command-local Apple Clang PATH then made source help/build pass.
The two associated A listeners naturally completed, with zero responses. These
tool and timing failures are preserved, not relabeled as successful Quit tests.

The explicit TCP source peer then sent one PING, received exact PONG, observed
local OK/device acceptance, successful RTT **4111070 us**, and successful cleanup
(`ui-quit-b-tcp-final.jsonl`). A run `5bfdbfa91ea64e2ca5ff1bff39e07822` confirmed
one response. Native menu Quit exited PID 18584. Independent public-core reopen
showed 13 settled records, but this last listener had ended normally at its
60-second duration before Quit. Therefore this proves normal Quit and persisted
RF facts, **not active-hardware Quit**. Total sends are matrix 11 + app PING 2 +
this B/A exchange 2 = **15/18**. No RF case was replayed to improve its result.

After the app and inspector exited, the public CLI profile API updated only the
owned Quit preset to request 15 s, initialization 30 s, task 240 s, listen 180 s.
The user had authorized a larger application budget. Product defaults, firmware,
radio settings and maxEntries/maxResponses remained unchanged. Release PID
48106 was launched explicitly with the same owned data directory. Actual GUI
preview showed all four new budgets before Start. No B sender ran for this
final zero-RF case.

Run `de554bd3671f2d0c7cbaf4d0b5e04680` was still in progress after the finite
initialization window, including Run/History navigation, then received native
menu Quit. The OS confirmed PID 48106 absent, without querying the closed app.
Independent public CoreStorage reopen showed canceled at **receiving/session
ready**, elapsed wall time about 72 seconds within the 180-second listen window,
zero response attempts, both cleanup scopes terminal (succeeded/not_required),
aggregate succeeded, recordState settled, and null recovery fields. This is the
accepted active-hardware normal Quit evidence, rather than inferring it merely
from a missing process.

Final same-directory reopen contains **14 settled app records**: 7
initializationFailed, 5 completed, 2 canceled. All aggregate cleanup is succeeded;
none required recovery on reopen. The three public-API test presets remain.
These bounded fixture counts do not imply product global counts. Evidence:
`release-reopen-final.json`, `release-active-quit-reopen.json`,
`release-profiles-final.json`, `ui-profile-quit-long-window.json`.

### Actual system panel and file

In PID 18584 two panel jobs generated seven summary rows but ended canceled,
writer admitted false / published false. The second panel's Save and New Folder
buttons stayed disabled, including in the dedicated writable owned directory;
the cause is not established. No file success is claimed for those jobs. After
normal app restart, the unchanged Release binary's panel used that same exports
directory, enabled Save, and published a newly selected suggested JSON name.

The actual output is
`exports/meshchan-summary-2026-11-15T06-01-08-082222Z.json`, **20408 bytes**, SHA-256
`ddb7b78680a1df9c146b59348138276a6b591c90ac495de23d510b954a0a08ea`.
The job reported generated/published true, **13 actual rows**, more false.
Independent file inspection confirmed summary format 1, exportedAt
`2026-11-15T06:01:08.081760Z`, the expected descending record order, stored
nullable/false/zero facts and integer microseconds, no BOM or appended newline,
and no forbidden profile/port/endpoint/content/path fields. All run objects
equal the earlier independently reopened 13-record fixture's public summaries;
this is a structural comparison, **not byte equality to a different export**.
The same-call JSON return was not captured in GUI. Automated writer tests retain
the same-call byte comparison. No owned staging objects remained. The later
14th database record does not alter this file's actual count.

A new panel selected the existing file and reached AppKit's Replace warning.
Automatic approval review rejected clicking Replace because it could overwrite
the JSON contrary to the new-file-only requirement. The warning and panel were
canceled; the job settled with writer admitted false / published false. At that
initial cutoff this host path stopped at the warning and was **BLOCKED**, not a
complete successful delegate-validation test. The later explicitly authorized
continuation below supersedes that current status without erasing the block.
Existing native XCTest separately exercises the
delegate and real RENAME_EXCL primitive against files, directories, symlinks,
dangling symlinks and a publication race. No bypass or fallback was attempted.
`gui-file-validation.json` records actual file inspection, including the
same-call-byte evidence limit.

### Authorized existing-target continuation: PASS

The user subsequently explicitly authorized clicking Replace on this task's
owned test file. At 06:31 UTC, a before-image and SHA-256/size/mtime/inode record
were captured under `replace-followup/` before app startup. The unchanged final
Release executable SHA-256 remained
`c8ea43b3886d1ee31fec7f209c4cd85efee7c67bf56d87f9eb0ef04c4292a7f2`.
PID 60280 was launched with the same explicit owned `fixtures/release` directory.
No Device Refresh/check, serial connection, OpenHop connection or RF ran.

Computer Use loaded the 14-row first History page (All operations/states,
size 50, no cursor or UTC boundary), started one export job, and selected the
existing 13-row JSON file in the system panel. After Save displayed AppKit's
Replace warning, the explicitly authorized Replace click reached the app's
native delegate validation. The observed alert read:

> Choose a new file name. This version cannot replace an existing target.

OK returned to the Save panel, with Save disabled for that rejected target.
Cancel then settled the original job: summary generated true, generated rows
**14**, more false, **writer admitted false**, **file published false**. This
is an observed pre-writer panel/delegate rejection, not a claim that the native
publish syscall ran in this GUI job. Existing XCTest covers that separate final
race authority.

Independent verification after normal native menu Quit and OS-confirmed PID
absence found the original file still **20408 bytes / 13 rows**, with exact
before-image byte equality, the same SHA-256
`ddb7b78680a1df9c146b59348138276a6b591c90ac495de23d510b954a0a08ea`, and unchanged
mtime and inode. The export directory contained only the original file, with
no staging objects or new output. A separate public-core reopen showed the same
14 persisted run objects as before, unchanged. Evidence:
`replace-followup/before.json`, `original-summary.json`, `result.json`,
`reopen.json`, plus this session's Computer Use AX observations. The alert's
combined screenshot was blank; its explicit AX text is the UI rejection
evidence, and the independent filesystem checks are the no-overwrite evidence.

This continuation adds zero RF sends, leaving the total **15/18**. It changes
no product source, build, dependency, schema or configuration. The validation
record and local-only skill reference now show PASS for this host path while
preserving the initial blocked attempt. This permission applies to the named
task-owned file in this test; it is not standing authorization to replace other
files.

### Local skill and remaining scope

`~/.codex/skills/meshchan-hardware-testing/SKILL.md` and its validated-setup
reference were created locally after the accepted real paths above.
`~/.config/meshchan-hardware/config.json` retains the user-supplied endpoints,
API key, username, external password-script reference, and dated radio/channel
facts requiring revalidation. The config directory is 0700, its file 0600;
the skill files are owner-only. Neither the admin password nor a JWT was saved
in the skill. The skill-creator validator reports **Skill is valid!**, using
Python 3.15.2 and the existing PyYAML installation without installing tooling.
No skill or private configuration is in Git.

This follow-up does not repeat actual Pinyin, the full desktop/window matrix,
unsupported target volumes, every retention/maintenance failure, isolated B
local-radio reception, or beta hardware qualification. Those retain their
original test-layer labels and later phase boundaries. Remote CI had not run at
this local evidence cutoff; publication was separately authorized afterward.
No 1D.9 work was started.

The development TCP adapter's first loopback run exposed a sink-close wait and
was not counted as a pass. The corrected code closes the output sink before
socket destruction and observes subscription cancellation; late connection,
paused consumer, framing, remote close and explicit port validation tests pass.
Final complete CLI suite: **276/276 PASS** (`cli-tests-tcp-final.log`); Python:
**71/71 PASS** (`python-tests-tcp-final.log`); fatal-info analysis: PASS
(`tcp-analysis-fixed.log`). Existing CI discovers the new loopback tests without
enabling hardware. No project dependency or production transport API was added.

`AGENTS.md` now records the user's reusable host-GUI rule: use Computer Use when
Chinese input methods are not under test; normal command-line build, fixture,
CLI and process/file verification remain separate. No native UI driver was used
after that direction.

## Final follow-up cutoff

`hardware-final-source-manifest.json` covers **330 tracked/new source files**;
`hardware-final-tracked.diff`, `hardware-final-new-files.tar`, and
`hardware-final-status.txt` preserve this uncommitted handoff outside Git. All
**48 app library/Runner product sources** still match the prior final 1D.8 build
manifest. The real host app tests above therefore use the unchanged final
Release binary, not a binary predating a later product fix. New source changes
in this follow-up are development peer/runner/test support, the host-GUI agent
rule, and documentation. No SDK, dependency, public core/link API, production
startup argument, version or schema changed.

Final whitespace check passed. The full CLI 276 / Python 71 suites and peer
fatal-info analysis above are the final affected software runs; this follow-up
does not claim another app/core/link/native/smoke run beyond their separately
recorded cutoffs in the 1D.8 validation record. After all app/inspector/CLI
operations, OS checks show all owned Release PIDs absent and no open handle for
the selected USB port. Public CLI profile inspection opened and closed normally.
The repository credential scan found no retained API key in any tracked/new
file; skill/private configuration permissions and external paths were checked.
No commit, push or PR had been performed at this evidence cutoff; the user
subsequently authorized PR publication, recorded in the main 1D.8 validation
record. No tag, deployment or binary upload was performed.
