# Meshchan macOS host

This Flutter workspace member provides Drafts, Device, and Diagnostics navigation.
The pages describe features that are not connected yet. Normal launch/navigation
opens no database, enumerates no ports, and constructs no transport or session.
The public core packages and CLI remain pure Dart. The application uses the same
root Pub lockfile; do not resolve a separate member lockfile.

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
open build/macos/Build/Products/Release/Meshchan.app
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
identity, and executable location only when the probe is selected. It does not
create/open the production directory. A fixture beneath a separately created
Application Support validation directory establishes that access only. Existing
user-library continuity, bootstrap/recovery, app owner, directory switching and
persistent user-selected authorization remain 1D.3 work. No path_provider/file
selector plugin or CocoaPods dependency is needed here.

See the [platform record](../../docs/validation/phase-1d2-platform.md) for actual
artifacts, commands, hashes, results and limits. The ordinary worker, request and
control bridge, device gate, cancellation, stale-result protection and fault
recovery remain 1D.3; business pages remain 1D.4–1D.8; product quit is 1D.9.
