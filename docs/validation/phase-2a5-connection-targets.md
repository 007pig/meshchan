# Phase 2A Step 5 connection targets

## Source and toolchain

On November 25, 2026, the starting checkout was clean `master` at
`f77a4e54529af4b2e0283cea5f0d6bf49b9cc4c1`, matching local `origin/master`.
[PR #55](https://github.com/007pig/meshchan/pull/55) was already merged at that
commit. The merge parents are the previous base
`b509b2e94920098d1de4173666ac1c8d24ddb997` and the Step 4 head
`92976fe8f34d1e336b0d6631c400d2fe74edea04`. Step 5 was validated in the
existing checkout with local changes on that baseline.

The installed Flutter SDK at `/opt/homebrew/share/flutter` reported Flutter
3.50.0 stable (framework `ab2912035e`, engine revision `371f77202a`).
Its bundled Dart at `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart`
reported Dart 3.14.0 stable on `macos_arm64`. The local compiler was Apple
Clang 21.0.0 at `/usr/bin/clang`. The Markdown link check used
`/opt/homebrew/bin/python3`, Python 3.15.2, with `sys.executable` at
`/opt/homebrew/opt/python@3.15/bin/python3.15`.

The Step 4 [execution location decision](phase-2a4-ble-worker.md#execution-location-decision)
assigns BLE plugins, unsolicited platform callbacks, and physical ownership
to the Flutter root isolate. The worker owns session, device gate, storage,
and recording responsibilities. The paired Heltec V4.3 Case A and normal
Quit with independent SQLite reopen belong to the earlier signed executable
with SHA-256 `fa541d36516b23fa525dccc96d8d4a4105197e17d7a8cc12f20f823168378455`.
The final signed executable with SHA-256
`2b0f3883ef569157e54a967c96d9696058dbfeea4156f9ef16893ebc9536905e`
has software and guest fake-backend evidence. Its physical Case A remains
unverified. Real same-process reconnect, maximum frames, other devices, and
broader recovery retain the status in the Step 4 ledger.
[Case A receipt](phase-2a4-ble-worker.md#case-a-receipt-and-release) ·
[Final build checks](phase-2a4-ble-worker.md#pre-pr-validation)

## Implementation and scope

The [target model](../../packages/meshcore_link/lib/src/connection_target.dart)
uses only implicitly imported `dart:core`. The
[public barrel](../../packages/meshcore_link/lib/meshcore_link.dart) exposes
`ConnectionTarget`, `CompanionTransportKind`, `UsbSerialTarget`, `TcpTarget`,
and `BleTarget` with explicit `show` exports. The model preserves all accepted
strings verbatim. USB takes an explicit path, TCP takes a validated ASCII DNS
name or bare IP literal and a required port, and BLE takes an opaque
host-scoped selection. A numeric DNS single label can end in a dot. Dotted
numeric sequences use the IPv4 parser and require a literal without the final
dot. The [architecture contract](../architecture/companion-connections.md#connection-targets)
specifies the input boundaries, exact value equality, and category-only
summaries. Validation errors report fixed reasons and omit argument values
and original parser exceptions.

The existing CLI and App continue to use USB string factories.
`ConnectionProfile` remains an operation preset. The diagnostic snapshot
and History export continue to use their current field allowlists. The
workspace manifests, SDK constraints, root lockfile, schema, production
transport and session code, CI, and signing configuration match the baseline.

## Local checks

The commands below use the installed SDK. Run them from the repository root
unless the command changes directories.

```sh
flutter=/opt/homebrew/share/flutter/bin/flutter
dart=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
"$flutter" --version
"$dart" --version
"$flutter" pub get --enforce-lockfile
"$dart" format --output=none --set-exit-if-changed \
  packages/meshcore_link/lib/src/connection_target.dart \
  packages/meshcore_link/lib/meshcore_link.dart \
  packages/meshcore_link/test/connection_target_test.dart \
  packages/meshcore_link/test/connection_target_isolate_test.dart
"$flutter" analyze --no-pub --fatal-infos
(cd packages/meshcore_link && "$dart" test --reporter expanded \
  test/connection_target_test.dart test/connection_target_isolate_test.dart)
(cd packages/meshcore_link && "$dart" test)
git diff --check
shasum -a 256 pubspec.lock
```

| Check | Result |
| --- | --- |
| SDK and locked resolution | The initial Flutter invocation under the default sandbox failed when it tried to update normal engine cache stamps. Running the installed Flutter command with cache write access succeeded. Locked dependency resolution completed, and the root lock SHA-256 stayed `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`. |
| Format and analysis | All four Dart files passed format verification, including the new untracked files. Workspace analysis with fatal infos reported no issues. |
| Focused tests | All 12 passed. The [value tests](../../packages/meshcore_link/test/connection_target_test.dart) cover the public API, input boundaries, exact strings, value collections, and safe errors and summaries. The [isolate test](../../packages/meshcore_link/test/connection_target_isolate_test.dart) sends all three objects through `Isolate.spawn`, checks fields, equality and collection keys inside the child, receives the target objects back, and observes child exit. |
| Full link suite | All 258 passed, including existing framing, serial transport, USB initialization, and session regressions. The standard Dart native-asset hooks ran without a toolchain change. |
| Standalone AOT smoke | `dart compile aot-snapshot` and the bundled `dartaotruntime` ran a temporary fixture importing the model directly. It verified safe labels for three valid values and sanitized runtime errors for an invalid USB path, TCP host and port, and BLE selection. The source and snapshot were removed after the check. |
| Change review | Reviewed the complete change set, including new files, the public export and import boundary, Markdown links and heading anchors, and the unchanged root lockfile. Whitespace checks passed. |

The isolate fixture covers direct object transfer between isolates that
share code. Production worker messages, `Isolate.spawnUri`, cross-process or
network serialization, and persistence are outside that check.

This value-only change required no product Release build, signature, DMG,
VM GUI, Swift fixture, BLE probe, physical USB/BLE/RF, or SQLite process
matrix. Existing `local-adhoc` signing policy and the Step 9 integration
and build verification plan still apply.

### IPv6 review follow-up

On the bundled Dart 3.14.0, the focused test reproduced an index error from
`Uri.parseIPv6Address` for the overfull compressed literal `1:2:3:4:5:6:7::8`.
The target validator now converts that parser failure into the fixed
`host` error with no invalid value attached. The regression also checks that
the neighboring valid literals `1:2:3:4:5:6:7::` and `1:2:3:4:5:6:7:8` retain
their original spelling.

After the fix, both focused test files passed all 12 tests and the full link
suite passed all 258. Format verification and workspace analysis passed. A
temporary AOT fixture compiled with `dart compile aot-snapshot` and run with
`dartaotruntime` also verified the same malformed and valid inputs.

## Step 6 handoff

The [factory handoff](../architecture/companion-connections.md#step-6-factory-handoff)
dispatches by concrete variant for each explicit operation. The USB branch
passes the original path into the existing wrapper and retains the CLI and
App initialization policies. Future TCP and BLE branches take the value
fields as inputs. The root BLE host will validate and map a selection, and
the worker will receive a new transport proxy. The transport, session, and
host continue to own frame subscription, write completion, logical
completion, and affirmative release. CLI and App migration follow in
Steps 7 and 8.
