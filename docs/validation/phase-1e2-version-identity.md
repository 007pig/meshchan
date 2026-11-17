# Phase 1E.2 — version, identity, and compatibility validation

## Source and decision

Validated on November 17, 2026, from clean local `master` at
`692ac28edaef1d4913639f7c652bfadbf525ef99`, the merge of PR #39.
GitHub reported PR #39 **MERGED**, at `2026-11-17T07:07:34Z`, with head
`87e447a87585eac4976d9bf6a52447e04bd323d7` and base
`0f89fe81823e58d524ad5a35a1f18a454b6fa4bc`. Its contract was already an
ancestor of HEAD. No merge, reset, cleanup, commit, tag or upload was performed.
There were no preexisting working-tree edits. Results apply to that baseline
plus the reviewable 1E.2 working-tree changes, not to the unchanged merge commit.

No later version decision was found. This step explicitly selects engineering
candidate `0.1.0-rc.1`, build `6`, following accepted 1D Beta build `5`.
The 1D acceptance remains historical; the RC does not inherit its hardware pass.

| Identity | Validated value |
| --- | --- |
| Link/core/CLI manifests, CLI constant, five internal constraints | `0.1.0-rc.1`; constraints `^0.1.0-rc.1` |
| App manifest and compiled runtime/new App records | `0.1.0-rc.1+6` |
| Source and complete native CLI `--version` | `meshctl 0.1.0-rc.1` |
| New CLI diagnostic records | `0.1.0-rc.1` |
| Actual `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / string `6` |
| Actual `MeshchanProductVersion` / Bundle ID / product | `0.1.0-rc.1` / `org.meshchan.meshchan` / `Meshchan` |
| Standard About, observed in VM | `Version 0.1.0-rc.1 (6)` |

## Implementation and unchanged contracts

The [developer contract](../development.md#product-version-and-native-identity-1e2)
documents the source inputs and commands. Four manifests, five constraints,
CLI and App source constants, and tracked `Version.xcconfig` agree through the
extended version checker. No generated version file or new dependency is needed.
Strict SemVer validation maps only the numeric core to Apple's short version;
invalid input is rejected. The App uses source constants for full runtime
identity. Native plist uses dedicated Meshchan settings; standard About reads
its full-version metadata and build. The bounded runtime report adds
`appVersion`; its checker requires explicit version/build and checks compiled
identity before accepting resource/relocation results.

Both existing Xcode script phases run source/raw-input preflight before their
assemble/embed command. Flutter 3.50 source inspection and real generated
configuration confirmed that `FLUTTER_BUILD_NAME` is normalized to `0.1.0.1`
for this prerelease, while original full version/build are in `DART_DEFINES`.
`BUILD_NAME` / `BUILD_NUMBER` are optional when no override is supplied. Required
original Dart defines and any explicit raw overrides must agree with the source
decision. Native identity settings are also checked on the Runner target.

Historical `candidate_common.TARGET_VERSION` remains `0.1.0-dev.3`, with the
original three-member default. Current checks opt into four members explicitly.
The historical fixture now derives the current manifest version rather than
assuming Beta. Current version assertions and CI parameters were updated;
historical documents, records, checksums and compatibility versions were retained.

No storage, ownership, device, export or protocol implementation changed.
App/CLI default remains `~/Library/Application Support/meshchan`; explicit
`--data-dir` precedence and validation before resource initialization remain.
Existing App launch/directory tests passed. App Sandbox entitlements, local
signing configuration and deployment target `12.0` remain unchanged. Actual plist
minimum is `12.0`. Static signature inspection found no App Sandbox entitlement;
this local ad hoc product contains `com.apple.security.get-task-allow=true`
although the unchanged source Release entitlement dictionary is empty. This
records actual local signing behavior; formal entitlement review remains 1E.6. Database
schema 1, diagnostic summary format 1, CLI JSON envelope schemaVersion 1 and
wireless protocol remain independent of the product version.

## Actual tools and products

- Host: macOS 27.2.1 (26B131), arm64; Xcode 27.2 (27B52), macOS SDK 27.2.
- Existing SDK: `/opt/homebrew/share/flutter`, Flutter 3.50.0 stable,
  framework `ab2912035e`, bundled Dart 3.14.0. No upgrade/channel change.
- Host Python: `/opt/homebrew/bin/python3`, Python 3.15.2; existing Python
  subprocess paths continue to use `sys.executable`.
- VM: identity-checked VirtualMac2,1, macOS 27.2.1 (26B131), dedicated
  `meshchantest` console session, strict SSH host-key verification.
- Root lockfile unchanged, SHA-256
  `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`.
  Locked resolution passed; no third-party dependency changed.

Complete local products are at
`apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app` and
`build/phase-1e2/cli/bundle/` (executable plus serialport and SQLite libraries).
The App runner contains arm64 and x86_64 slices; CLI is arm64. This validates
arm64 execution, not Intel support. Local deep/strict/all-architectures signature
verification passed, including the guest copy and relocated App. This uses the
existing development signing configuration, not Developer ID acceptance.

| Product member | SHA-256 |
| --- | --- |
| Release `Contents/Info.plist` | `0f7647388820489cdfd334bda0d7bdc9cf906faaeb64e3f426f47e41ffc5786d` |
| Release `Contents/MacOS/Meshchan` | `c258e8394578717ce7c332f25591d62d106aaa8b63e143fe1e209664248cf1e4` |
| Release `Contents/Frameworks/App.framework/App` | `a589a217c8ccade1c95e5181193d06dcb808051d18a5a27e7e05620a4c11e8ca` |
| Complete CLI `bin/meshctl` | `cb69ccea12c141f17097b5f98dc1e75cca673ecfdb2ca4e803da8db6eef6ac5c` |

These identify local validation bytes, not distributable download checksums or
complete inventories. No installer, archive, release build-info or public asset
was created. Private logs, generated software fixtures and VM receipts remain
in ignored `build/phase-1e2/`; product UI and bounded runtime fixtures are under
the dedicated guest `~/utm-ui-isolation/products/20261117T072514Z-product-90091-*`.
No user production directory or database was opened.

## Commands and results

Commands used the above SDK; source/native-asset operations ran sequentially
with command-local Apple Clang PATH. Python commands used the explicit host
interpreter. Full command output and exact guest argv are retained in the
ignored evidence directory.

| Gate / command | Result |
| --- | --- |
| `flutter pub get --enforce-lockfile` at root | PASS; unchanged lock |
| `python3 tool/check_product_version.py --expected-version 0.1.0-rc.1 --app-build 6` | PASS; four members, five constraints, source constants and native template |
| `python3 -m unittest discover -s tool -p '*_test.py'` | PASS, 141 tests; final focused five identity tests also passed after adding empty-executable rejection |
| `flutter test --no-pub --concurrency=1` in App | PASS, 262 tests, including launch/directory guards and App record continuity |
| `dart test --concurrency=1` in CLI | PASS, 287 tests, including exact version, new records and Beta/dev record preservation |
| `dart run bin/meshctl.dart --version` and new bundle `bin/meshctl --version` | PASS; both exact RC output |
| `dart build cli --target bin/meshctl.dart --output ../../build/phase-1e2/cli` in CLI | PASS; complete new bundle |
| Existing observation and synthetic acceptance CLI builds into `build/phase-1e2/{observation,acceptance}` | PASS, sequential |
| `python3 tool/smoke_cli.py --expected-version 0.1.0-rc.1 --dart <bundled-dart> --cli-bundle build/phase-1e2/cli/bundle --observation-bundle build/phase-1e2/observation/bundle --datagram-acceptance-bundle build/phase-1e2/acceptance/bundle --evidence-directory build/phase-1e2/smoke` | PASS, 101 process checks; source/AOT/relocation, native assets, fake diagnostics, new RC records and SQLite reopen |
| `flutter build macos --release --no-pub` in App | PASS; fresh current-implementation Release |
| Explicit checker above plus `--app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app` | PASS; actual generated plist, separately reported from template |
| `codesign --verify --deep --strict --all-architectures <App>` | PASS locally and in VM, including full relocation |
| `flutter analyze --no-pub --fatal-infos`; tracked Dart format gate | PASS; no issues; 226 files, zero changes |
| Existing `check_runtime_process.py` and `check_diagnostic_process.py`, with bundled Dart | PASS; independent owner/refusal/reopen and five diagnostic lifecycle cases |
| `git diff --check` | PASS |

Mapping/negative tests independently assert RC, historical Beta and stable
numeric mapping; positive integer builds and known `6 > 5`; all member,
constraint, CLI/fallback mismatches; missing version fields; wrong/missing plist
fields; absent/incomplete App; malformed SemVer; missing/duplicate/conflicting
raw defines and overrides; and absent/wrong compiled runtime version. The local
build progression is a documented decision, not proof of a universal build registry.

App and CLI tests produce owned historical Beta/dev records through public
`CoreStorage.record()` with fake transports, close them, append current-version
records, close/reopen and compare original version values. They do not rewrite
historical records. Existing ownership/format contracts remain in force.

## VM observation and runtime evidence

Used the repository macOS VM skill and its existing guest executor. The
`host.py` sequence was `prepare`, `launch Release <App>`, real AppKit menu
`Meshchan / About Meshchan`, screenshot/collection, close About, Command-Q,
then `settled Release`. The original screenshot visibly shows
`Version 0.1.0-rc.1 (6)`; executable hash matches the local Release. Normal Quit
confirmed `resourcesReleased`, `workerExited`, owner release, zero pending
requests/receive ports and OS PID absence.

The guest has no installed Python/CLT. Invoking its `/usr/bin/python3` stub
failed before launching the runtime checker and displayed an install prompt;
it was dismissed through the guest executor, with no installation or settings
change. Instead, the same executor directly ran the existing bounded App entry:
`--meshchan-runtime=write`, then `read`, then `read` from a complete `ditto` copy,
each with `--runtime-exit` and explicit new
`runtime-shell/meshchan-1d3-sqlite`. These **launched Flutter/AppKit**. The host
reused `validate_runtime_report()` to validate actual guest process exit codes,
phases, compiled `appVersion`, persistence and shared shutdown reports.
All three passed with `0.1.0-rc.1+6`; the relocated signature passed too.
Exact argv/reports are in `vm-runtime-reports.json` and the retained orchestration
script `run_vm_runtime_shell.py`. The guest-Python wrapper and its additional
startup-quit modes were NOT_RUN successfully; they are not counted as passes.

A second fresh `ReleaseDiscard` fixture used the same App solely for owner
handoff: the complete native CLI's `history list --json` returned exit 69 and
`data_directory_busy` while GUI owned the directory. After normal Command-Q,
verified resource/worker/PID release, the same CLI command returned exit 0,
schemaVersion 1 and `storageClose.state=closed`. `finish` confirmed both ordinary
App owners absent and stopped the executor. No host GUI input, serial enumeration,
USB access or RF operation was performed.

## Failures, scope, and handoff

Retained initial failures: the first sandboxed Python run could not inspect
`/bin/ps`, and current-delivery test inputs still named Beta; permission-correct
reruns after updating those current inputs passed. The first native preflight
incorrectly required optional `BUILD_NAME`; SDK/generated-input inspection led
to the corrected required-original-Dart-defines check and a successful rebuild.
The failed guest Python attempt is recorded above. A late verification assertion
that actual Release entitlements would be empty was rejected: local Xcode signing
injected `get-task-allow`; the observed entitlement is recorded above, with Sandbox
still disabled and source signing settings unchanged. None is relabeled as a pass.

**1E.2 engineering acceptance is complete within this scope.** Remote CI was
updated but not run or claimed green here. No new hardware acceptance, complete
1D GUI/IME matrix, Beta installer replacement, clean-environment upgrade or
minimum supported macOS result is claimed. Those limits do not substitute old
Beta evidence for this RC.

1E.3 receives the explicit RC/build/identity contract, unchanged locked dependency
graph, actual local App/CLI identity and validation evidence for license and
third-party material review. No project license was selected here. Formal signing,
notarization, packaging, clean installation/upgrade, limited final hardware
acceptance and publication remain later 1E gates. This RC is not declared ready
for public distribution.
