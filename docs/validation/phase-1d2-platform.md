# Phase 1D.2 macOS platform validation

A November 13 code-review follow-up is appended below. Earlier sections and
hash records retain the original pre-review source/artifact facts; the follow-up
records the changed launch parser and native project configuration separately.

Validation dates: November 12–13, 2026 (UTC). This is a local development-host
record, not a beta, clean-machine install, hardware connection, or distribution
acceptance. The GUI automation permission wait crossed midnight; earlier
November 12 evidence is retained rather than relabeled.

## Source and toolchain

- Started on clean `master` at `98bb7f40aa2b17970546db12fd73f350ce4392c2`.
  Fresh read-only GitHub API checks confirmed PR #27 is merged/closed, its head
  is `4af02a09fa3f9ecd917adac90cd39dcf3780cf57`, its actual merge and latest
  remote master are `98bb7f4`. The host contract was already present; no
  cherry-pick/reset/cleanup was used. GitHub connector authentication failed;
  the authenticated local `gh api` query supplied the fresh remote facts.
- Working branch: `codex/phase-1d2-flutter-macos`, same HEAD plus uncommitted
  changes/new app files. No commit, push, PR, tag, release or deployment was made.
  `app-inputs.json` records actual hashes for 92 source/dependency/config inputs,
  including new files; the old HEAD alone does not identify the tested inputs.
- macOS **27.2.1 / 26B131**, **arm64**; Flutter **3.47.9 stable**, revision
  `c197ca5199e9ee5661e865596c9c07294dfab51c`, engine
  `89c39edfdfae2949f6806e4a315c0c08522238b7`, from
  `/opt/homebrew/share/flutter`; bundled Dart **3.13.7**, `macos_arm64`.
- Xcode **27.2 / 27B52**, developer directory
  `/Applications/Xcode.app/Contents/Developer`, macOS SDK **27.2** at its
  `Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`; Apple Clang **21.0.0**
  (`clang-2100.4.1.1`). Native commands preferred `/usr/bin` in process-local PATH.
- Python **3.15.2**, invoked as `/opt/homebrew/bin/python3`, resolving to
  `/opt/homebrew/opt/python@3.15/bin/python3.15`. Child tooling uses
  `sys.executable`. No SDK/channel/dependency upgrade, extra toolchain manager,
  system library/cache repair, global Xcode/PATH/security or keychain change.
  Flutter's normal SDK-cache bookkeeping needed execution access outside the
  workspace sandbox; SDK/vendor source was not edited.

Evidence root (ignored): `build/phase-1d2/20261112/`. It retains commands,
stdout/stderr, exit results, input and bundle hashes, native audit and hook JSON.
The run directory name is its November 12 start date; final checks are November 13.

## Workspace and application

The official installed template was inspected with `flutter create --help`, then
created with `flutter create --platforms=macos --project-name=meshchan_app
--org=org.meshchan --no-pub --empty apps/meshchan_app`. Only macOS product files
were generated. The app joined the shared workspace before dependency resolution;
there is one root Pub lockfile and no member lockfile. The three existing members,
CLI version, schema 1 and diagnostic summary 1 remain unchanged.

Both normal navigation and probe use **`lib/main.dart` in the same target and
same `.app`**, without a second target or compile-time probe flag. The runner
explicitly forwards `CommandLine.arguments.dropFirst()` through
`FlutterDartProject.dartEntrypointArguments`; successful debug/release reports
establish actual delivery. Normal launch constructs no storage/serial/transport/
session resources. Drafts, Device, Diagnostics and the history placeholder show
honest unconnected states and have no fake success actions.

| Configuration | Actual fact |
| --- | --- |
| Product / Bundle identifier | `Meshchan` / `org.meshchan.meshchan` |
| Package version | `0.1.0-dev.3+1` |
| Numeric Bundle short version / build | **`0.1.0.3` / `1`**, the current SDK's observed prerelease mapping |
| Minimum macOS | 12.0 |
| Debug architecture | arm64 for runner, App, FlutterMacOS, serial and SQLite frameworks |
| Release architecture | x86_64 + arm64 for those binaries; actual runtime **ARM64**, not inferred from universal packaging |
| Requested Debug/Profile entitlements | `cs.allow-jit`, `network.server`; App Sandbox omitted |
| Requested Release entitlements | Empty dictionary; App Sandbox omitted |
| Actual signed entitlements | Debug adds `get-task-allow`; Release also has `get-task-allow` from Xcode's development signing |
| Signing identity | Ad hoc, no TeamIdentifier/Developer ID/notarization; no public-distribution claim |
| Profile execution | NOT_RUN; Profile shares `DebugProfile.entitlements`, no Profile runtime claim |

## Resolution and software gates

`flutter pub get` exposed the real `flutter_test` pin to `test_api 0.7.12`, which
conflicted with `test 1.33.0` (0.7.15). Relaxing only test constraints to
`^1.31.0` then exposed its analyzer `<14` conflict with `build_runner 2.17.1`.
The nearest compatible generator line is `^2.16.1`. Final shared resolution:

- Changed development tooling: `test` 1.33.0 → 1.31.1, `test_api` 0.7.15 →
  0.7.12, `test_core` 0.6.21 → 0.6.18, analyzer 14.7.0 → 13.3.0,
  `_fe_analyzer_shared` 111 → 103, `build_runner` 2.17.1 → 2.16.1,
  `build` 5.0.0 → 4.0.11, `build_config` 1.4.0 → 1.3.3, `source_gen`
  4.3.1 → 4.2.4, `package_config` 3.0.0 → 2.2.0.
- Added Flutter SDK `flutter`/`flutter_test`/`sky_engine`, plus `characters`,
  `vector_math`, `material_color_utilities`, and the three `leak_tracker` packages.
- No production dependency/native hook version changed: Drift 2.35.4,
  drift_dev 2.35.3, sqlite3 3.9.1, libserialport_plus 1.0.5. No overrides/cache edits.
- Both `flutter pub get --enforce-lockfile` and the installed bundled
  `dart pub get --enforce-lockfile` passed. `dart pub workspace list` showed root
  plus four members. `flutter analyze --no-pub --fatal-infos` passed.

Eight hardware-free Flutter tests passed (`flutter-tests.log`), covering page
navigation/default boundary silence, explicit-only probe startup, invalid input,
missing/existing fixture refusal, independent maintenance failures, awaited close
failure and invalidation of read receipts before another process can reopen.
The initial analyzer warning in a new fake test was fixed and revalidated.
`plutil -lint` passed runner project/plists/entitlements; the workflow YAML parsed.

The unchanged CLI-only validator was run sequentially with:

```bash
/opt/homebrew/bin/python3 tool/validate_dev_candidate.py \
  --dart /opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart \
  --build-directory build/phase-1d2/20261112/final-cli-gate
```

All 15 gates passed with exit 0 and `inputsUnchanged: true`: code generation,
schema snapshot/generated diff, format, analysis, 65 Python tests, 362 core tests,
271 CLI tests, 180 link tests, three native bundle builds, 101 source/AOT/relocation
smoke checks and whitespace checks, plus enforced resolution. This tool's member/version,
CLI closure, bundle and archive assumptions were not generalized to Flutter. Its
results do not cover the app.

## Sandbox and actual directories

The original template enabled App Sandbox in both files. A real sandboxed debug
probe exited **1**, before opening storage, against a new external fixture.
`template-sandbox-runtime.json` records Foundation home, Dart HOME and support
under `/Users/xiaoyu/Library/Containers/org.meshchan.meshchan/Data`; it did not
reach the CLI directory. That failure is retained.

The explicit [host decision](../architecture/flutter-host.md#1d2-implementation-note)
omits Sandbox in both Debug/Profile and Release. In both actual modes,
Foundation `NSHomeDirectory`, `FileManager.homeDirectoryForCurrentUser`, and
Dart HOME returned `/Users/xiaoyu`; Application Support returned
`/Users/xiaoyu/Library/Application Support`, so the compatibility target is
`/Users/xiaoyu/Library/Application Support/meshchan`. The runner only resolves
and reports these paths. It never opens/creates that production database.

A new, owned **sibling** `meshchan-1d2-validation-*` directory in Application
Support tests the runtime access mechanism with real SQLite. A separate owned
`/private/tmp` directory tests external access. This verifies resolution and
fixture access, not existing user-library continuity/migration. No file-selection
plugin, transient grant or persistent security-scoped authorization was used.
App Store Sandbox/authorization, production bootstrap/recovery, directory switching
and application ownership remain future work. No USB entitlement or global
library search environment variable was added.

## Runtime, native assets and relocation

The exact commands/reports, PIDs, paths, original/copied inventories and hashes
are retained in `app-runtime.json`; `run_apps.py` is the bounded local evidence
reproduction driver, not product/release tooling. Product build commands from
`apps/meshchan_app` were `flutter build macos --debug --no-pub` and
`flutter build macos --release --no-pub`, with Apple Clang selected. Both exited 0.

The fixed fixture is titled `Meshchan platform fixture 🧪`; its body is
`草稿 / café / 🌍\nSecond line\r\nLast line\n` (**45 UTF-8 bytes**). Public core
creates revision 1 with a generated ID, retains exact timestamps, waits for
maintenance and confirmed close, checks the nonempty existing file, reopens by
the original ID, compares exact content/revision/bytes/timestamps and closes again.
Each flow stays in one worker named `meshchan-platform-probe`; only sendable
result maps return to the main isolate. Release executes comparisons without
assertions. Read requires this fixture's completed receipt and invalidates it
before opening; failures leave it incomplete. Nothing force-unlocks or deletes
fixture data, sidecars or locks. No closeUnconfirmed/maintenance failure occurred
in the real runs; injected tests verify they cannot be hidden by a successful read.

Actual serial sources in pinned libserialport_plus were reviewed read-only:
macOS `list_ports`/`get_port_details` query IOKit registry metadata, without port
open. Public `SerialPorts.listPorts()` exercised actual symbols only in explicit
manual probe invocations; each invocation returned **4 ports / 0 warnings**, with
no paths/identities in the general results. No `checkPort`, serial open, transport,
session, initialization, inbox read, RF or device configuration was performed.
Other-platform guards are unchanged. Empty/nonempty enumeration proves only
this metadata invocation, not device connection or wireless capability.

Actual bundle paths in both products:

- `Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus`;
  install-name `@rpath/libserialport_plus.framework/libserialport_plus`, system
  IOKit/CoreFoundation/libSystem dependencies.
- `Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3`; install-name
  `@rpath/sqlite3.framework/sqlite3`, system Foundation/libSystem dependencies.
- `App.framework/.../flutter_assets/NativeAssetsManifest.json` maps package asset
  IDs to those framework paths. Its `absolute` loader tag is not an absolute
  checkout path. `otool -L/-l` found bundle-relative loader paths and system
  dependencies; no required absolute SDK/cache/Homebrew/source/temp library path.
  `vmmap` records ARM64 and both libraries loaded from the **relocated** bundle.

An incremental Release build had a valid standalone App.framework signature but
failed the outer bundle's nested-code seal check. The artifact/audit is retained;
this is not recorded as a passing signing check. A fresh-bundle rebuild and its
corresponding runtime/signature results are recorded below.

Normal debug and release windows were observed with the computer-use interface;
Drafts → Device → Diagnostics navigation showed the expected unconnected text,
including History. The automation initially timed out, then succeeded. These
are actual WindowServer/UI observations, separate from build and probe results.
Final artifact correspondence and relocation details are finalized below.

## Final artifact results

The failed incremental artifact is retained as
`build/phase-1d2/20261112/incremental-release-seal-failure.app`, with its original
`native-audit.json` and `app-runtime.json`. Moving only this agent-created
Release `.app` out of the generated products directory, then repeating
`flutter build macos --release --no-pub`, produced a fresh bundle. No manual
re-sign, SDK edit or global clean was used. Its log is `fresh-release-build.log`.
Debug, fresh Release and relocated fresh Release all passed
`codesign --verify --deep --strict --all-architectures` (exit **0**), recorded in
`fresh-release-signature.log` and `final-native-audit.json`. This resolves the
final artifact check; incremental resource-seal behavior remains a local build
caveat, not an established SDK root-cause diagnosis or distribution acceptance.

| Final check | Actual result |
| --- | --- |
| Debug normal window and all three destinations | PASS, final debug artifact observed via accessibility/screenshot |
| Debug fixed SQLite worker | PASS, PID 9689, two `closed`, two completed maintenance reports |
| Debug metadata | PASS, one explicit final-debug call, 4 ports / 0 warnings |
| Fresh release SQLite write/reopen | PASS, PID 15225, exit 0, two `closed`, two completed maintenance reports |
| New release process reads same fixture | PASS, PID 15265, exit 0, one `closed`, completed maintenance |
| Complete fresh `.app` copy outside checkout | PASS, every file hash and symbolic-link target matches; no runtime bundle changes |
| Relocated read and metadata | PASS, PID 15279, same ID/facts, one `closed`, completed maintenance, 4 ports / 0 warnings |
| Relocated library loading | PASS, `fresh-release/relocated-vmmap.log`: ARM64, both actual frameworks loaded from the relocated app |
| Relocated controlled exit | PASS, PID 17579, exit 0, same ID/facts, one `closed`; no additional serial call |
| Final relocated normal window/navigation | PASS, normal process PID 16078; executable path confirmed with `ps`; all three destinations observed |
| Compilation input correspondence | PASS, 92 recorded inputs unchanged; whole-bundle inventories/hashes retained; CLI workspace manifests also covered by the completed CLI gate |
| Final Flutter-aware analysis | PASS, exit 0, no issues (`final-flutter-analyze.log`) |
| Remote CI / clean-machine / actual USB or RF | NOT_RUN / NOT_RUN / NOT_RUN |

PID 15279 kept its developer result window alive for `vmmap`, then received
SIGTERM **after** its successful confirmed-close report (recorded exit -15).
Termination is not its cleanup evidence. A separate relocated `--probe-exit`
process, PID 17579, subsequently confirmed the same fixture and exited 0.
Normal GUI observations are retained in `gui-observations.json` and
`final-window-process.log`; screenshots were observed in the tool session.
Preliminary manual metadata calls remain retained too: **four finite app
metadata invocations total**, two debug and two relocated-release, each 4/0.
No automated software test/CI serial call, repeated polling, device open or
communication was introduced.

Final persistence fixture (created and owned only by this validation):

`/Users/xiaoyu/Library/Application Support/meshchan-1d2-validation-t0dv7gst/meshchan-1d2-sqlite`

ID **`f4d1b4f94d71da38ef69ed94fbf7cfff`**, revision **1**, body **45 bytes**,
created/updated **`2026-11-13T04:28:21.468098Z`** in the original, second and
relocated app processes. The production `meshchan` directory was never opened.
All fixture directories and failed artifacts remain for review; no old lock or
data was removed.

Final local products:

- `apps/meshchan_app/build/macos/Build/Products/Debug/Meshchan.app`.
- `apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app`.
- `/private/tmp/meshchan-1d2-runtime-y_ohjst1/relocated/Meshchan.app` (fresh release copy).
- `build/phase-1d2/20261112/fresh-release/app-runtime.json`: exact argv/cwd,
  results, fixture paths, inventories and copy equality for the fresh release.
- `build/phase-1d2/20261112/final-native-audit.json`: final signatures,
  architectures, loader commands, native-asset manifest and hashes.
- `build/phase-1d2/20261112/final-cli-gate/validation.json`: all 15 existing
  gates passed, `inputsUnchanged: true`, with logs/bundle inventories.

Local implementation and the bounded macOS arm64 platform checks are complete.
Remaining work is the expressly deferred product/runtime/distribution scope and
unexecuted remote CI, not an inferred device or public-release capability.

## CI and next-step boundary

CI now resolves/analyzes the mixed workspace with Flutter, adds the eight app
tests, and retains Linux pure-Dart/CLI/schema/Python/native smoke coverage.
A separate `macos-15` job prints actual toolchain/architecture, builds debug and
release sequentially, and runs SQLite write/read in distinct release processes
without `--enumerate-serial`. The current [runner catalog](https://github.com/actions/runner-images#available-images)
assigns that label to arm64. The new workflow is local and uncommitted:
**remote CI NOT_RUN**, no run/commit claim. A future headless runtime failure must
remain a runtime failure. Local ARM64 evidence does not rely on CI's label.

1D.3 must implement the long-lived worker/control bridge, unique application
owner, device gate, cancellation/stop responsiveness, stale-result protection,
worker faults and production directory bootstrap/contention. The temporary
probe proves one bounded path only. Business pages remain 1D.4–1D.8; product
window-close/Command+Q finalization remains 1D.9. USB opening, LoRa, unplug,
mobile/platform risk matrix, beta and formal distribution remain later steps.
The work stops at 1D.2.

## November 13 review follow-up: Xcode launch and native test host

Both review findings were reproduced or confirmed in the actual project.
Xcode's checked-in scheme enables document-versioning launch arguments, while
all Debug/Release/Profile `TEST_HOST` settings still named the old executable.
New Flutter regressions first failed with `Unknown launch option.` before the
parser fix. The parser now filters only the known Cocoa boolean pairs
`-NSDocumentRevisionsDebugMode`, `-NSTreatUnknownArgumentsAsOpen`, and
`-ApplePersistenceIgnoreState`, requiring `YES`/`NO` values. The latter two
were observed on the real XCTest host process. Cocoa-only startup selects normal
navigation; mixed explicit probes still work. Unknown options, malformed Cocoa
values and malformed/duplicate probe options remain rejected before resources.

The native test host and `BUNDLE_LOADER` now resolve to
`Meshchan.app/Contents/MacOS/Meshchan` in all three configurations. Product file
references and all five scheme product names match. The empty native template
test was replaced with a host integration check for the actual app executable
and Flutter view controller; macOS CI now invokes `xcodebuild test` sequentially
with the existing build/runtime checks. No dependency, SDK, schema, core/CLI or
business-resource ownership change was required.

Review evidence is retained under
`build/phase-1d2/review-20261113T045506Z/`, with Python 3.15.2 invoked through
`/opt/homebrew/bin/python3` (`/opt/homebrew/opt/python@3.15/bin/python3.15`).
Nine Flutter tests pass, including navigation with actual Cocoa arguments,
explicit probe mixing, and strict negative cases. Flutter analysis, formatting,
project plist and workflow YAML validation pass. `xcodebuild build-for-testing`
exits 0 (`native-build-for-testing.log`); Xcode's resolved settings confirm the
correct host/loader in Debug, Release and Profile (`settings-*.json`).

The first two native execution attempts stalled in `dyld`/`__open` before
entering `main` and were stopped with SIGINT (exit 75, zero tests). Their logs,
samples and result summaries remain preserved as interrupted attempts. Release
symbol generation also waited in a filesystem open through `dsymutil`/CoreFoundation.
During this review, the user explicitly granted Meshchan access to Documents.
The pending Release build then completed, and a fresh native execution against
the already built test host succeeded:

```bash
# From apps/meshchan_app, using the review's isolated derived-data directory:
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ../../build/phase-1d2/review-20261113T045506Z/native-build \
  -resultBundlePath ../../build/phase-1d2/review-20261113T045506Z/after-permission-runner-tests.xcresult \
  -parallel-testing-enabled NO test-without-building
```

The action exited **0**: **1 test passed, 0 failures**, including the actual
Meshchan executable/Flutter view-controller assertions. The result summary is
`after-permission-native-summary.json`; the test log records completion at
`2026-11-13T05:18:26Z`. Native test execution is now **PASS**, with no remaining
local blocker observed. This supersedes the earlier interrupted execution
status. The agent did not change system security, SDK/vendor sources or loader
settings; the user granted the app-specific Documents permission.

Fresh normal Debug and Release apps were built at their standard product paths,
and both passed deep/strict/all-architecture signature verification. The earlier
products are preserved as `previous-Debug.app` and `previous-Release.app` under
the review evidence directory. Compiled Debug/Release probes received all three
Cocoa pairs together, passed real-file SQLite close/reopen, and exited 0; a new
Release process and a whole-app copy outside checkout read the same fixture and
also exited 0. No serial enumeration or device access was requested in this
review. The review fixtures are owned directories inside the ignored review
folder; their Documents access reflects the user's grant and does not test or
change production-library bootstrap/continuity.

`review-results.json` records every command/result and current source hashes;
`review-artifacts.json` inventories the final apps and confirms that the copied
Release matches every source-bundle file and symbolic link. Its relocated copy
is recorded in `review-results.json`. Root Flutter-aware analysis and final
format/whitespace checks pass. Five compilation inputs changed from the original
pre-review map: the parser, app test, native test, Xcode project and scheme.
No core/CLI code, dependency or version changed, so the earlier full CLI/core
gates retain their original source scope rather than being rerun or relabeled.
The workflow change adds the native test gate; remote CI remains **NOT_RUN**.
