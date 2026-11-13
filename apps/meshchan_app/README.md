# Meshchan macOS host

This Flutter workspace member provides Drafts, Device, and Diagnostics navigation.
The pages describe editing/device features that are not connected yet. Normal
launch creates one application runtime and one long-lived worker owning one
`CoreStorage`. It reads settings and one bounded draft page without device I/O.
Navigation, rebuilds, focus and minimization do not reopen storage or recover again.
The public core packages and CLI remain pure Dart. The application uses the same
root Pub lockfile; do not resolve a separate member lockfile.

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
No product start-record or metadata button is exposed in this step. Test-only
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

Use the existing Flutter SDK (locally `/opt/homebrew/share/flutter`, 3.47.9 with
bundled Dart 3.13.7), with Apple Clang selected for native hooks:

```bash
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
# From the repository root:
flutter pub get --enforce-lockfile
flutter analyze --no-pub --fatal-infos
(cd apps/meshchan_app && flutter test --no-pub)
cd apps/meshchan_app
flutter build macos --debug --no-pub
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/macos -parallel-testing-enabled NO test
flutter build macos --release --no-pub
codesign --verify --deep --strict --all-architectures build/macos/Build/Products/Release/Meshchan.app
MESHCHAN_DEV_DIRECTORY="$(mktemp -d /private/tmp/meshchan-app.XXXXXX)"
open -n build/macos/Build/Products/Release/Meshchan.app \
  --args --data-dir="$MESHCHAN_DEV_DIRECTORY"
```

Only macOS platform files are generated. The minimum target is macOS 12.0.
The product is `Meshchan`, Bundle identifier `org.meshchan.meshchan`. The package
version is `0.1.0-dev.3+1`; Flutter maps its numeric macOS short version to
`0.1.0.3` and its build number to `1`. This mapping is a development build, not a
public release. Development signing is ad hoc, with no Developer ID/notarization.

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
