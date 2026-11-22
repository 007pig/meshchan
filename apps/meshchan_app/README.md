# Meshchan macOS host

This Flutter workspace member provides Drafts, Device, and Diagnostics navigation.
Draft editing, device checks, recorded diagnostics and persisted history are
connected through public core APIs. Normal launch creates one application runtime and one long-lived worker owning one
`CoreStorage`. It reads settings and one bounded draft page without device I/O.
Navigation, rebuilds, focus and minimization do not reopen storage or recover again.
The public core packages and CLI remain pure Dart. The application uses the same
root Pub lockfile; do not resolve a separate member lockfile.

The current Release build candidate is `0.1.0-rc.1+9`; see the
[version input contract](../../docs/development.md#product-version-and-native-identity-1e2).
Its RC identity does not inherit historical hardware acceptance.
The historical complete `0.1.0-beta.1+5` Release has
[local finite beta acceptance with documented limits](../../docs/validation/phase-1d11-rf-matrix-completion.md).
Real USB/RF, physical fault/recovery, Cancel and active Quit were tested on the
host; remaining hardware-free UI/export ran in the existing macOS VM using the
same inventoried app. Follow `AGENTS.md`: VM first for UI without real USB,
host Computer Use only for real USB/serial steps. Intermittent initialization
and the retained input/timing limitations are not hidden by that acceptance.

## Runtime startup and shutdown (1D.3)

Normal startup resolves Foundation's CLI compatibility target,
`~/Library/Application Support/meshchan`, in the main isolate. Override it only
at startup with `--data-dir=/absolute/path`. The override takes precedence and
avoids the directory-facts call. Empty/relative/NUL/dot-segment paths, duplicate
options, unknown options and conflicting modes fail pure validation before resource
startup. The three documented Cocoa options require unique `YES`/`NO` pairs.
There is no fallback directory, automatic repair, retry, restart or device selection.
Opening the default directory performs real core recovery/maintenance. Use owned
fixtures for development; do not open an existing user's database to test access.

`runtime/controller.dart` belongs to the application, not a page. Its typed
generation/request-ID bridge calls `runtime/worker.dart`; core handles and native
resources stay there. The status area remains visible across all three pages:
Opening, Storage ready, Directory in use, Stopping, Closing, Closed and controlled
faults. Initial query failure retains the already-open owner and its safe error.
Offline reads default to 20 drafts, allow 1..50 and return an explicit cursor;
separate pages are not one database snapshot. Text is copied into immutable local
DTOs and is never automatically logged or exported.

Window close, menu Quit, Command+Q and Flutter's cancellable exit callback share
`shutdown()`. After resource bootstrap, AppKit retains the original termination
request with `terminateLater` and receives a reply only after Dart's conclusion.
This also preserves logout/restart/shutdown requests instead of canceling them
and starting an unrelated app quit. Failed release replies false and keeps the
window available. Before the first rasterized frame, neither the worker nor the
finite probe can start: both wait for native bootstrap authorization. A system
termination before that grant can exit immediately without abandoning an owner.
The explicit startup-quit acceptance path waits for Dart's handler, saves stop
intent and opens the resource-free barrier without starting a worker.
Shutdown pauses admission, applies stop, drains accepted work and recording
settlement, waits for requested maintenance, closes core once, then reports
release, receives an acknowledgement and ends the worker. Main permits exit only
after both release and `onExit`. Concurrent/repeated calls share one close process
and its current cached outcome. An earlier unknown outcome remains immutable;
late confirmed release plus actual exit automatically dispose client ports and
let later quit requests observe a verified outcome without another close request.
Widget dispose only removes UI observers. Save/maintenance errors do not invent a live connection;
unknown cleanup/close or worker loss remains a visible fault and vetoes quit.
Forced termination/crashes cannot guarantee saves or cleanup.

The device gate acquires synchronously before parameter reads. Cancellation and
logical completion do not release it. Final core/host/aggregate cleanup must all
be `succeeded`/`notRequired`, and adapter observation must be sound, before release.
`done` repairs missed broadcast events; final core unpin/drain still belongs to
`CoreStorage.close()`. Pending/unconfirmed/failed release quarantines the gate.
The 1D.3 checkpoint exposed no product start-record or metadata button;
1D.6 adds the explicit metadata and finite-check flow described below. Test-only
worker entries construct fake transports inside the worker and use the same
dispatcher, gate, adapter and shutdown implementation.

Request deadlines mean **result unknown**. They finish pending client requests,
pause new work and never resend, kill, reopen, replace the worker or infer release.
The first shutdown exchange remains available to an existing worker after such a
fault. It gets its own bounded observation; an earlier request/startup deadline
does not settle that new observation. If Hello is late, the same shutdown ID and
intent are retained until its port arrives, even after the shutdown observation
itself expires. Only one shutdown envelope is sent, and ordinary requests remain
faulted while actual drain/close continues.
Late responses cannot finish a request twice or replace newer query/runtime facts.
Open `cleanupUnconfirmed` and close `closeUnconfirmed` keep unknown ownership.
Rejected isolate creation is resource-free: no worker or `onExit` is invented,
the owner remains none, client ports close, and normal quit is permitted. A worker
that was successfully created and later crashes still requires release proof.
The whole directory remains exclusive, including CLI reads while the GUI owns it.

## Isolated verification modes

Normal, 1D.2 probe, 1D.3 runtime verification and native XCTest host modes are
mutually exclusive. The scheme's TestAction sets
`MESHCHAN_TEST_HOST=disabled-owner-v1` without inheriting LaunchAction arguments.
Swift detects the test host and adds the isolated Dart mode **before creating the
Flutter engine**. Missing/invalid test configuration fails closed; neither XCTest
`setUp` nor a late Widget pump is responsible for isolation. Normal Run/Release
does not inherit this setting. Widget tests inject `AppRuntime` without resources.

`--meshchan-runtime=write|read --data-dir=/canonical/parent/meshchan-1d3-name`
uses the production entry, controller and long-lived worker. Write requires a new
fixture and commits fixed Unicode/emoji/mixed-line-ending text through the bridge.
Read requires the prior closed receipt and an existing regular, nonempty database;
these preflight checks precede receipt invalidation and worker creation, so an
empty/missing database is rejected without initializing a replacement. Both modes compare exact
ID/revision/timestamps/text, serve multiple correlated reads and confirm close/exit.
An incomplete receipt never authorizes another read. `--runtime-exit` requests
normal AppKit quit after the report; it does not call `exit()`. Inspect the JSON
`passed` field as well as process exit. `--meshchan-runtime=hold` requires an explicit
fixture path and shows the ordinary runtime UI until normal quit. It does not write
fixture data or enumerate devices. There is no arbitrary execution/transport hook.
`quit-starting` and `hold-startup` are explicit fixture-only acceptance modes: a
resource-free directory-resolution barrier holds startup until the ordinary quit
coordinator saves stop intent. The first requests AppKit quit immediately; the
second keeps the ordinary pages available for a bounded manual responsiveness
check. They do not fabricate an open handle or inject a transport. A never-spawned
worker is reported separately from an actual `onExit` observation.
`--meshchan-runtime=quit-ready --data-dir=/canonical/parent/meshchan-1d3-name`
requests native quit with a live, ready owner. It exercises AppKit's pending
termination reply and the same Dart drain/close/exit barrier, unlike write/read
whose verification report already includes close. The bounded macOS checker runs
both `quit-starting` and `quit-ready`; neither accepts `--runtime-exit`.

```bash
# Run sequentially, with an Apple-Clang-first command environment on this Mac.
python3 apps/meshchan_app/tool/check_runtime_process.py --dart "$(command -v dart)"
python3 apps/meshchan_app/tool/check_macos_runtime.py \
  --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app
```

On this Mac invoke `/opt/homebrew/bin/python3` (3.15.2), including when the
command PATH starts with `/usr/bin`. The process gate verifies independent-owner
contention, committed exact-text continuity and reopen. The macOS gate copies the
complete app outside checkout and runs from another cwd. Neither enumerates ports.
See the [1D.3 record](../../docs/validation/phase-1d3-runtime.md) for actual results,
source inputs, failures, signatures and evidence boundaries.

## Offline drafts (1D.4)

Launch the normal app with an explicitly owned `--data-dir` during development.
Drafts work without a device. New creates an empty local buffer; only Save or
Command+S creates a stored record. An all-empty draft is valid. Select a row by
ID to read its committed version, edit Title/Body, then explicitly save. Delete
asks for confirmation and removes the record only after a revision-checked commit.
A new local draft is discarded locally; it never sends a fake delete.

The list loads 20 records at a time (app bound 1–50). Refresh replaces the cursor
chain. Load more deduplicates IDs; separate pages are not one database snapshot.
The loaded count is not a total. Saving/deleting refreshes the first page without
replacing editor text. A refresh error is separate from a confirmed commit.

Save snapshots the current text and confirmed revision. You can keep typing
while it runs; newer text remains unsaved. Repeated Save coalesces with that one
write. A returned create ID becomes the target of subsequent updates. Exact text,
including empty strings, whitespace, title newlines, CR/LF/CRLF, emoji, combining
characters and U+FFFD, is preserved. Body UTF-8 bytes counts the current body,
without a radio packet cap. The persistence boundary rejects unpaired UTF-16.
While either field has valid noncollapsed composing text, Save asks you to finish
composition. Routine refresh/status/save results never reset controller values.
Default selection, clipboard and Undo/Redo remain Flutter text editing actions.
Undo history belongs to one document session: switching drafts, New, Discard and
confirmed Reload start fresh history. Ordinary saves preserve that history.

A conflict retains local text and the last confirmed revision. View stored version
reads for inspection only; the explicit Reload choice replaces local edits and
adopts that version. Continue editing never silently changes expectedRevision.
Missing records and controlled failures remain visible with the local buffer.
An unknown save/delete may already have committed: no automatic retry, content
matching, new owner, or reconciliation runs in that faulted session. Safe resource
release does not turn an unknown write into success. Inspect records explicitly
after safe shutdown in a new session.

Switching drafts, New, leaving Drafts, window close and Command+Q protect local
edits with Save / Discard / Continue editing. Accepted writes settle before a
Discard; it cannot undo a commit. Unknown writes require an explicit warning
acknowledgment. A failed Save, unfinished composition or newer edit cancels
departure. Both exit sources share one application decision and final Save.
With active composition, departure is deferred before opening a dialog or pausing
admission; finish or cancel the candidate text, then try again. Outside mouse
clicks keep field focus until the action checks the current input. If a pending
write becomes unknown while the ordinary leave dialog is open, Discard shows a
second unknown-result warning and requires its explicit acknowledgment.
During quit, ordinary admission is paused; one document-scoped, single-use final
save can enter the same worker queue. Only an accepted departure initiates
irreversible runtime shutdown, then releases bootstrap, drains/closes and waits
for worker exit. Cancel resumes admission only after healthy worker confirmation.

Run the product process gate separately from the historical fixed-fixture probe:

```bash
python3 apps/meshchan_app/tool/check_draft_process.py --dart "$(command -v dart)"
```

This gate uses `fixtureWrites: false`, production CRUD, real SQLite, independent
owner/contender/reopen processes and a test-side production-dispatcher send boundary
that drops a committed create reply. It proves frozen retry and exactly one record
in a new process after safe close. It does not simulate a disk failure or RF.
See the [1D.4 record](../../docs/validation/phase-1d4-drafts.md) for actual evidence.

Actual Debug/Release editor, Pinyin/Command+S, dirty navigation/quit and relocated
Release product persistence were verified in the [GUI follow-up record](../../docs/validation/phase-1d4-drafts.md#november-13-gui-follow-up-after-ide-permission-restart).
For manual acceptance, foreground the exact bundle through LaunchServices with
an explicit owned directory and retain `open -W` until normal exit. Multiple
retained bundles share the Bundle ID; select by full path. A process existing in
the background is not evidence of an interactable window. Native UI automation
also needs an available trusted control surface and Flutter accessibility semantics;
verify that native input changed the product state and committed exact text.

## Build and run

Use the existing Flutter SDK (locally `/opt/homebrew/share/flutter`, 3.50.0 with
bundled Dart 3.14.0), with Apple Clang selected for native hooks:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
# From the repository root:
flutter pub get --enforce-lockfile
flutter analyze --no-pub --fatal-infos
(cd apps/meshchan_app && flutter test --no-pub)
cd apps/meshchan_app
MESHCHAN_WORKSPACE="$PWD/macos/Runner.xcworkspace"
MESHCHAN_BUILD_ROOT="$(mktemp -d /private/tmp/meshchan-build.XXXXXX)"
flutter build macos --debug --no-pub --config-only
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$MESHCHAN_BUILD_ROOT/Derived" -parallel-testing-enabled NO build-for-testing
# Inspect TARGET_BUILD_DIR, TEST_HOST and the generated .xctestrun first.
# Confirm MESHCHAN_TEST_HOST=disabled-owner-v1 before engine bootstrap.
(cd "$MESHCHAN_BUILD_ROOT" && xcodebuild -workspace "$MESHCHAN_WORKSPACE" \
  -scheme Runner -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$MESHCHAN_BUILD_ROOT/Derived" -parallel-testing-enabled NO test-without-building)
flutter build macos --release --no-pub --config-only
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$MESHCHAN_BUILD_ROOT/Derived" -parallel-testing-enabled NO build
codesign --verify --deep --strict --all-architectures "$MESHCHAN_BUILD_ROOT/Derived/Build/Products/Release/Meshchan.app"
MESHCHAN_DEV_DIRECTORY="$(mktemp -d /private/tmp/meshchan-app.XXXXXX)"
open -n "$MESHCHAN_BUILD_ROOT/Derived/Build/Products/Release/Meshchan.app" \
  --args --data-dir="$MESHCHAN_DEV_DIRECTORY"
```

Only macOS platform files are generated. The minimum target is macOS 12.0.
The product is `Meshchan`, Bundle identifier `org.meshchan.meshchan`. The package
version is `0.1.0-rc.1+9`. Tracked `Configs/Version.xcconfig` supplies Apple's
numeric `0.1.0` / `8` and the full `MeshchanProductVersion`. The standard About
panel displays `0.1.0-rc.1` and build `8`. Native preflight rejects conflicting
Flutter inputs; actual plist and compiled runtime are checked separately.
The previous build 3 observed short version was `0.1.0.1`, build `3`; its Dart
build defines retained `0.1.0-beta.1` and `3`. Build 4 was independently observed
as short version `0.1.0.1`, build `4`, with Flutter definitions `0.1.0-beta.1` / `4`.
The fresh build 5 was independently checked as short version `0.1.0.1`, build
`5`, with Flutter definitions `0.1.0-beta.1` / `5`. Its
[GUI/delayed-OK continuation](../../docs/validation/phase-1d11-build5-gui-delay.md)
retains a successful finite Check and a subsequent recording initialization
failure; it does not establish reliable USB initialization or an RF round trip.
The [beta record](../../docs/validation/phase-1d11-hardware-beta.md) separates
candidate preparation from acceptance. Development signing is ad hoc, with no
Developer ID/notarization.

A local incremental Release build once failed the outer bundle's nested-code
seal while its individual frameworks still verified. Preserve a failing generated
`.app`, rebuild into a new bundle at the normal products path, and repeat the
signature check before using that artifact as evidence. The final fresh local
bundle and its relocated copy passed. Do not hand-edit or re-sign SDK/cache
libraries to hide a failure; see the platform record for the retained result.


## Explicit finite platform verification

The **same** normal app/entrypoint, in debug or release, accepts these developer
arguments. The runner explicitly forwards them to Dart. No assertion drives a
critical check. The options are absent during normal startup.

The Cocoa boolean option pairs `-NSDocumentRevisionsDebugMode`,
`-NSTreatUnknownArgumentsAsOpen`, and `-ApplePersistenceIgnoreState`, each with
`YES` or `NO`, are filtered before probe validation. These are supplied by
ordinary Xcode launches and the native test host.
Other unknown arguments and malformed or duplicate probe options still fail
before resource access. Native `RunnerTests` also execute in the renamed
`Meshchan.app` host and verify that it hosts a Flutter view controller.

- `--meshchan-probe=write`: require a new fixture, create one fixed Unicode/emoji/
  mixed-newline draft through public `CoreStorage`, await maintenance and actual
  close, reopen its existing database, compare exact persisted facts, then close.
- `--meshchan-probe=read`: require an existing nonempty database and this probe's
  completed receipt; compare the original ID, revision, text, byte length and
  timestamps from another application process. Never create a replacement file
  when the fixture/receipt is missing or incomplete.
- `--fixture=/absolute/canonical/parent/meshchan-1d2-unique-name`: dedicated fixture
  only. The parent must already exist and resolve without symbolic links. Write
  refuses existing destinations. Read refuses directory/database/receipt links.
- `--enumerate-serial`: optionally call public `SerialPorts.listPorts()` **once**
  on macOS after SQLite has closed successfully. Output only count/warning count.
  This reviews metadata, never selects/opens/checks a port, creates a transport,
  initializes a session, reads data, or sends commands/RF. Do not use this option
  in automated tests or CI. Existing platform guards remain unchanged.
- `--probe-exit`: emit a JSON result to stdout and exit `0` only after successful
  comparisons and confirmed closes; invalid arguments exit `64`, runtime failures
  exit `1`. Without it, the developer window displays the result and stays open.
  A failure/exit is not evidence of confirmed resource release.

For a hardware-free local release persistence check:

```bash
# From apps/meshchan_app, after building:
MESHCHAN_PROBE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meshchan-probe.XXXXXX")"
MESHCHAN_PROBE_ROOT="$(cd "$MESHCHAN_PROBE_ROOT" && pwd -P)"
MESHCHAN_FIXTURE="$MESHCHAN_PROBE_ROOT/meshchan-1d2-sqlite"
MESHCHAN_APP="$PWD/build/macos/Build/Products/Release/Meshchan.app"
"$MESHCHAN_APP/Contents/MacOS/Meshchan" --meshchan-probe=write \
  --fixture="$MESHCHAN_FIXTURE" --probe-exit
"$MESHCHAN_APP/Contents/MacOS/Meshchan" --meshchan-probe=read \
  --fixture="$MESHCHAN_FIXTURE" --probe-exit
# Copy the entire app; run the new process from a different cwd.
ditto "$MESHCHAN_APP" "$MESHCHAN_PROBE_ROOT/Meshchan.app"
(cd "$MESHCHAN_PROBE_ROOT" && ./Meshchan.app/Contents/MacOS/Meshchan \
  --meshchan-probe=read --fixture="$MESHCHAN_FIXTURE" --probe-exit)
```

One temporary worker owns all SQLite/native resources for the entire fixed flow;
only sendable result maps cross isolates. Close and maintenance failures remain
in the result and prevent reopening. The receipt is marked `closed` only after
all successful closes. Read invalidates the previous receipt before opening and
restores it only after confirmed close. Failed fixtures are retained; the probe never
removes locks, force-unlocks, deletes directories, or touches a user database.
Reusing an explicit completed receipt is bounded fixture verification, not an
arbitrary database import or user-data recovery feature.

## Directory and Sandbox decision

The template enabled App Sandbox in both entitlement files. Its actual runtime
HOME/Application Support resolved into `~/Library/Containers/org.meshchan.meshchan/Data`;
an external fixture failed. This host deliberately omits App Sandbox in
Debug/Profile and Release to retain the adopted CLI directory target
`~/Library/Application Support/meshchan` and future direct POSIX serial access.
Debug/Profile retain the template JIT/network-server development entitlements;
Release has no requested entitlements. No USB entitlement is claimed sufficient.
This is a host architecture decision, not a system permission change. App Store
Sandbox/security-scoped authorization and public distribution require later
review. See the [contract update](../../docs/architecture/flutter-host.md#1d2-implementation-note).

A small runner method channel reports Foundation support/home paths, bundle
identity, and executable location. Normal runtime consumes its directory target;
the historical probe also reports those facts. Fixture access does not establish
existing user-library continuity. Runtime bootstrap, ownership and fault handling
are implemented in 1D.3; directory switching and persistent user-selected
authorization remain deferred. No directory plugin or CocoaPods dependency is needed.

See the [platform record](../../docs/validation/phase-1d2-platform.md) for actual
artifacts, commands, hashes, results and limits. The ordinary worker, typed bridge,
gate, adapter and basic quit barrier are 1D.3. Business pages remain 1D.4–1D.8;
full desktop quit interactions remain 1D.9.

## Profiles, settings, and offline preview (1D.5)

Open **Profiles and settings** beside the three main destinations. Profiles loads
20 records per page (app bounds 1–50) and uses core UpdatedCursor ordering; loaded
count is not a total or a shared cross-page snapshot. Select by full ID, including
duplicate names. New is local until Save preset or Command+S. All send, listen,
ping and respond fields are editable, including budgets, applicable channels,
route descriptor/path, data type/filter, endpoint labels, duration and limits.
Changing operation requires confirmation, retains name/hint/budgets and resets
operation fields. Required fields without core defaults start empty. Payload and
PING content belong only to an invocation. Port hints are optional reference text
and never select or authorize hardware. Name/hint text is preserved exactly.

Settings has exactly one global default profile ID and diagnostic history limit
(1–100000). Empty default ID clears the reference. The bounded list is a selector;
an existing default outside it remains represented by its ID. Save replaces both
fields. Restore defaults explicitly restores no default and 1000, without deleting
presets or drafts. Lower limits, including restoring 1000, may cause core to clean
eligible old history. Commit success and retained maintenance warnings are separate;
the host never acknowledges sticky warnings automatically. Deleting a profile
clears its matching default atomically through core, preserving the history limit.
Refresh failure cannot reverse a confirmed commit.

Offline preview uses saved presets, with an independently selected operation.
**Use settings default** sends null profile ID; it does not bypass the default.
An explicit ID goes directly to the resolver, without requiring a settings read.
Each Override checkbox controls presence independently from the raw input. Turning
it off makes that field absent. Route descriptor/path merge independently; empty
hex path explicitly clears it. Listen supports inherit, all types, and type zero.
Content supports Not provided, exact UTF-8 Text, or arbitrary Hex; empty Text/Hex
means explicitly zero bytes. Protocol integers accept decimal or 0x/0X hex;
budgets/durations/limits accept decimal integers. Hex bytes require even-length
ASCII hex with no prefix/separators. Invalid explicit input never becomes absent.

Click **Preview parameters** to call the public core resolver through the unique
worker. The result includes the actual profile ID and all effective fields;
content is shown only as a byte count. This is a local execution input, not a safe
history snapshot, and is never logged wholesale. Inputs or storage mutations
invalidate old results. Changing selection keeps explicit overrides, updates the
inherited display, and never changes operation. Preview does not save, read Draft
content, enumerate ports, acquire a device lease, connect, transmit, or record.

Profiles and Settings share one persistent editing session and the application's
Draft navigation/quit coordinator. Save snapshots A while continued typing B
remains dirty. Complete replacements have no revision or timestamp CAS. Both
normal exit entrances share one decision and shutdown. Paused ordinary requests
are rejected on host and worker; one final Save is scoped by decision, target,
session and ID, including a just-confirmed create ID. Delete/Restore/Preview do
not receive that permission. Unknown writes freeze retries and retain uncertainty
independently of later release; a late unknown requires another explicit warning.
Live composition defers Save, modal actions, navigation and quit before admission
changes. Session/type replacement resets EditableText Undo; ordinary saves keep
controllers, selection and history. Command+S has no save target in Preview.

The fixture-only process gate is:

```bash
python3 apps/meshchan_app/tool/check_profile_process.py --dart "$(command -v dart)"
```

See [the 1D.5 validation record](../../docs/validation/phase-1d5-profiles-settings.md)
for actual software/platform evidence and remaining acceptance limits.

## macOS GUI validation environment

For repeatable manual/native GUI acceptance, copy the complete app and create an
owned fixture under `/private/tmp`; use that external cwd and stdout/stderr paths
as well as explicit `--data-dir` on every launch. A checkout's `build/` path under
Documents is still protected Documents access and triggered repeated permission
prompts in 1D.5. The [developer setup and launch example](../../docs/development.md#reusable-macos-gui-fixture-and-input-setup)
avoids that test dependency without changing product defaults or security settings.

On the current test Mac Command+Space switches input sources; Control+Space
opens Raycast. The user also configured Caps Lock to switch Pinyin/ABC. The
reusable personal skill is `$macos-pinyin-input`. Verify actual keyboard-focus
ownership after switching, including launcher overlays.
Selecting the Pinyin input-source ID alone can still leave Latin input; verify
actual marked text and candidates, using the existing shortcut if needed. Restore
the user's latest intended mode and do not change keyboard preferences. See the
[testing preflight](../../docs/testing.md#native-gui-preflight-storage-location-and-pinyinabc).

## Explicit finite device checks (1D.6)

Device is now a product flow: **Refresh → explicitly select an exact port →
Check device → await actual close**. Startup, page navigation, presets, defaults,
port hints and offline preview perform no serial enumeration or access. Refresh
runs public `SerialPorts.listPorts()` in the existing worker under a short device
lease. Empty results, per-item metadata warnings, a failed refresh and stale
previous metadata have separate presentations. No first port is selected.
Selecting a path grants only session-local permission for a later explicit Check;
paths and USB metadata do not establish stable or authenticated device identity.

The session-local options default to request **5 seconds**, initialization
**15 seconds**, startup **0 milliseconds**. Request/initialization accept decimal
integers 1–86400; startup accepts 0–86399999 and must be strictly less than the
initialization budget in milliseconds. Raw invalid input is retained. Check
freezes the path/options; edits and selection changes affect only the next check.
These values are neither profile fields nor settings and require no final Save.

Each Check constructs a fresh `MeshCoreSession` and opens its App-owned USB
transport once after subscribing to session events. The session requests
DEVICE_QUERY (app target 3) and APP_START (`Meshchan`). The App sends a
completion query after each command. On macOS, the shared USB transport
recognizes Heltec V4.3 OLED by its USB VID/PID and a decoded DEVICE_INFO. It
can synchronize past a bounded startup prefix and advance after a single
valid DEVICE_INFO. It completes initialization after SELF_INFO and a
following DEVICE_INFO. The installed CLI uses the same compatibility path,
with one initial query. Existing request and initialization deadlines apply.
Set `MESHCHAN_USB_INITIALIZATION_TRACE=1` in the process environment to write
startup counts and failure categories as JSON to stderr.
Port opening and configuration can reset some boards, and initialization
changes device-side session state. Check uses no inbox reads, PING, RF
configuration, diagnostic recording, or retries.

Start acknowledges admission quickly. Cancel targets that check's host ID and
acknowledges intent separately from worker application and resource release.
Synchronous native calls cannot be immediately preempted. Cancellation does not
stop offline CRUD. After complete information is observed, it is published with
a fixed UTC time and source path, followed immediately by close. The UI displays
local time with a timezone, signed dBm, kHz frequency, Hz bandwidth and raw
protocol/coding-rate/mode codes. No public key, BLE PIN or frame crosses the app
bridge. Last successful information remains historical after close or a later
failure; selection, current/last attempt and history are independent.

**Not connected** requires confirmed resource settlement. Initialization failure,
session cleanup and host observer cleanup are separate facts. Pending close keeps
the device gate occupied, while healthy offline work remains usable. Failed or
unconfirmed cleanup quarantines the gate and vetoes normal quit. Navigation owns
no resource lifetime. Dirty Draft/Profile/Settings quit Save and Continue can use
the narrowly scoped database-only exception during a healthy tracked check;
second device actions remain blocked. Genuine Stop/Shutdown is irreversible by
Resume. Both native and Flutter Quit retain the existing shared close barrier.

Hardware-free entry points and current evidence are documented in
[testing](../../docs/testing.md#finite-device-checks-1d6) and the
[1D.6 validation record](../../docs/validation/phase-1d6-device-check.md).

The unlocked November 14 follow-up verified the final Debug/Release GUI, actual
Pinyin, navigation, scoped USB cancel and dirty native quit using owned fixtures.
It also fixed Device outside-tap composition preservation. Release obtained
complete information twice on the explicitly selected USB path and closed
normally; Debug's observed checks failed initialization but cleaned up normally.
These distinct outcomes and the 159-test/11-XCTest final receipts are retained in
the [validation follow-up](../../docs/validation/phase-1d6-device-check.md#unlocked-gui-and-explicitly-selected-usb-follow-up).

## Recorded diagnostics (1D.7)

Diagnostics supports one explicit PING or finite Responder at a time. Refresh
and select an available exact path on Device in this application session, then
choose the diagnostic operation, saved/default preset, presence-sensitive field
overrides and (for PING only) invocation content. No successful device check is
required. Preview resolves saved parameters without accessing hardware. Click
**Start and record** to capture the request and selected path; the worker resolves
again, freezes the effective parameters and calls public `CoreStorage.record()`.
The core commits registration before invoking a fresh lazy transport factory.
The current candidate records `0.1.0-rc.1+9`, using the source identity checked
against manifests and raw native build inputs, including direct Dart processes.
Historical runs retain their original app/build version.

Recorded diagnostics use the same App USB initialization wrapper as Check, a
compatibility sequence introduced in Beta build 4 and retained in RC build 8.
After initialization normal commands pass through once without additional
queries. The historical Beta validation records preserve their tested cuts and
outcomes. See the [RC hardware validation record](../../docs/validation/phase-1e10-hardware-acceptance.md)
for the current acceptance status.

Cancel requests cancellation of that attempt only. It does not pause offline
editing, retract transmission or release the device gate. Navigation retains the
form and current/latest session result. Dirty quit uses the existing single
coordinator: Continue keeps the finite task, while Save/Discard precede the
irreversible shutdown and complete recording/observer/storage/worker barriers.

Task facts, nullable send/reception details, successful application RTT, first
matching PONG elapsed time, Responder counters and last-send facts appear
independently from core/host/app observer cleanup, registration/logical/cleanup
saves, coordination faults and known history maintenance. Missing is not false
or zero. Local confirmation does not prove peer receipt; a completed Responder
with zero responses is valid but establishes no round trip. Save failure does not
retry RF or erase in-memory results. Unconfirmed cleanup quarantines device work.

The current/latest snapshot remains session memory, separate from the persisted
History page described below. See the
[implementation and validation record](../../docs/validation/phase-1d7-recorded-diagnostics.md).

### Diagnostic history and one-page export (1D.8)

Open **Diagnostics → History** without selecting a device. Apply operation,
record-state and strict UTC registration-time filters; empty bounds are open.
UTC input is `YYYY-MM-DDTHH:mm:ss[.ffffff]Z`, with an inclusive lower and
exclusive upper bound. Page sizes use the public 1–200 range (default 50).
Previous/Next retain seek cursors, Refresh page repeats the current selection,
and First page resets continuation. Counts describe only this page.

Select a run to read its persisted `DiagnosticRun`, including four operation
configurations/results and independent cleanup/recovery facts. The current
session's **Read this run from history** also performs a repository read.
Missing records remain identified; the app never substitutes another row or
reconstructs a session snapshot. Delete selected record freezes the confirmed
ID and reports success only after core commit. Active pins and ineligible
records can return `conflict`; failed terminal cleanup is not proof of release.

History displays latest and sticky maintenance reports separately, including
committed deletions, deferred eligible excess pins, nullable limit and errors.
Refresh status reads current worker memory without retry/acknowledgment.
Run maintenance uses global Settings retention, with a fast accepted action
and separately observed completion. Acknowledge failures is explicit and rejects
an unseen newer failure revision; these reports are handle-lifetime memory.

**Export one page of redacted summaries** captures the applied filter, page
size and the page's input cursor, and makes a fresh bounded core selection.
It can differ from the displayed rows. A native macOS Save panel requires a new
file name. The main isolate writes core JSON UTF-8 bytes unchanged to owned
same-directory staging, flushes/closes, then uses `renamex_np(RENAME_EXCL)`.
Existing files/directories/symlinks and unsupported exclusive publication fail
without replacement or fallback. Published-file success and staging cleanup
warnings remain separate. This summary omits profile IDs and execution inputs;
it is neither anonymous data nor a restorable database backup.

Export survives navigation. Before writer admission Cancel/Quit cancels output
while observing accepted generation/pre-IO; after admission Quit waits for
write, publication and cleanup. Runtime release and worker exit alone cannot
permit exit while host output is pending. Continue editing never restarts a
canceled export. No device enumeration, preset resolution or transport is needed.

## Desktop commands and window size (1D.9)

File → Save / Command+S saves the current Draft, Profile or Settings form using
its existing revision/session checks. Device, Diagnostics, History and Offline
preview have no Save action. Meshchan → Settings… / Command+comma runs the
current unsaved-edit decision and opens Settings. A modal dialog, native Save
sheet, live text composition or closed runtime admission prevents background
commands. Finish composition naturally before retrying a business action.

File → Close Window / Command+W follows the current AppKit window. Closing the
main window, Quit and Command+Q use the same application quit coordinator;
Continue editing cancels a dirty decision. Escape also continues editing. Edit
commands retain the current text responder and its undo history. Hide, minimize,
zoom, full screen and resize do not stop work or replace the storage owner.
The initial and minimum supported content size is 800×600 logical points; larger
windows preserve the same editing session across the Draft layout breakpoint.

Acceptance evidence and remaining platform cases are tracked in
[the desktop validation record](../../docs/validation/phase-1d9-desktop-behavior.md).
