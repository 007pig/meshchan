# Phase 2A Step 6 Companion transport factory

## Source and toolchain

On November 26, 2026, the starting checkout was clean `master` at
`c9e00297838a854efd6c2e37df817eb02043099a`, matching local
`origin/master`. GitHub recorded [PR #56](https://github.com/007pig/meshchan/pull/56)
as merged into `master` at that commit. The merge parents are
`f77a4e54529af4b2e0283cea5f0d6bf49b9cc4c1` and the Step 5 head
`889994cfa5886e422c42070998d7589c3d7f473e`. Step 6 uses local changes
in the existing checkout. The [Step 5 record](phase-2a5-connection-targets.md)
covers the target model and its historical validation.

The installed Flutter SDK at `/opt/homebrew/share/flutter` reported Flutter
3.50.0 stable (framework `ab2912035e`, engine revision `371f77202a`).
Its bundled Dart reported 3.14.0 stable on `macos_arm64`. The native test
commands use Apple Clang 21.0.0 (`clang-2100.4.1.1`) via a command-local
PATH. The Markdown check uses `/opt/homebrew/bin/python3`, Python 3.15.2,
with `sys.executable` at `/opt/homebrew/opt/python@3.15/bin/python3.15`.

## Implementation and scope

The [public barrel](../../packages/meshcore_link/lib/meshcore_link.dart)
exposes the synchronous `CompanionTransportFactory` function type,
`createCompanionTransportFactory({required bool appCompletionQueries})`,
and `UnsupportedCompanionTransportException`. The
[implementation](../../packages/meshcore_link/lib/src/transport/companion_transport_factory.dart)
switches exhaustively on the existing sealed targets. It passes the exact
USB path and the host policy to `createUsbCompanionTransport` for each
invocation and returns the wrapper directly. The internal builder seam
shares this dispatch with tests. The existing optional USB initialization
trace remains part of the USB builder.

The default factory rejects TCP and BLE synchronously with an exception that
stores the transport kind and reports that the configured factory has no
adapter for it. The switch reaches only the selected branch. USB construction
failures propagate directly. Each USB wrapper starts unopened, with its own
frames and lifecycle. The caller manages the attempt, the transport owns
adapter operations and physical cleanup, and the session owns Companion
initialization. The host still owns admission and release decisions.

The production CLI and App still use their string-based creation paths.
The change consists of the factory, its public export, focused tests, and
documentation.

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
  packages/meshcore_link/lib/src/transport/companion_transport_factory.dart \
  packages/meshcore_link/lib/meshcore_link.dart \
  packages/meshcore_link/test/companion_transport_factory_test.dart
"$flutter" analyze --no-pub --fatal-infos
(cd packages/meshcore_link && PATH="/usr/bin:$PATH" "$dart" test \
  --reporter expanded test/companion_transport_factory_test.dart)
(cd packages/meshcore_link && PATH="/usr/bin:$PATH" "$dart" test)
git diff --check
git status --short
shasum -a 256 pubspec.lock
```

| Check | Result |
| --- | --- |
| SDK and locked resolution | The initial default-sandbox Flutter version check could not write engine cache stamps. The installed Flutter launcher succeeded with authorized access to its SDK cache. Locked dependency resolution passed. The root lock retained SHA-256 `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`. |
| Format and workspace analysis | All three affected Dart files passed format verification, including the two new files. The Flutter analyzer with fatal infos reported no issues. |
| Focused factory tests | All 6 passed. The [tests](../../packages/meshcore_link/test/companion_transport_factory_test.dart) cover public construction, exact USB delegation with alternating policies, independent unopened wrapper lifecycles, the subscription guard, typed and sanitized synchronous rejection, and direct construction failure propagation. |
| Full link suite | All 264 passed, including the target and isolate tests, framing, serial transport, USB initialization and startup synchronization, session, cancellation, and cleanup. Native dependency build hooks ran as usual. |
| Change review | Git whitespace checks passed for tracked and new files. Local Markdown links and heading fragments resolved. The public barrel lists only the three intended additions. The CLI, App, target model, USB wrapper, session, manifests, root lockfile, schema, product version, CI, and signing files match the baseline. |

The default USB factory tests construct and close unopened wrappers and
exercise the production open guard without a listener. The guard precedes
metadata lookup and native acquisition. Tests with a listener only observe
the unopened frame stream and its closure. The injected builder uses an
in-memory test transport to observe subscription and lifecycle calls.

The Step 5 AOT smoke remains in its own record. Step 6 has no product entry
point or native implementation changes. Release and DMG builds, signing,
VM GUI, Swift fixtures, BLE probes, real USB/BLE/RF, and the SQLite process
matrix were outside this validation scope. The Step 9 integration and build
checks and the existing `local-adhoc` signing policy still apply.
The [Step 4 ledger](phase-2a4-ble-worker.md#execution-location-decision)
retains the execution-location decision and the evidence attached to each
probe build.

## Steps 7 and 8

Step 7 can convert the explicit CLI `--port` selection to `UsbSerialTarget`
and use a factory configured with `appCompletionQueries: false` on the
session and datagram paths. Preserve the injectable creation boundary, lazy
admission order, output and exit behavior, and the serial-only `ports` and
`port-check` diagnostics.

Step 8 can pass a typed selection in the App requests and compose a factory
with `appCompletionQueries: true` inside the worker for Check and Diagnostic.
Preserve the gate lease, scoped cancellation, recording, cleanup, and release
protocols. See the
[architecture handoff](../architecture/companion-connections.md#step-6-factory-handoff)
for the adapter boundary and future TCP and BLE responsibilities.
