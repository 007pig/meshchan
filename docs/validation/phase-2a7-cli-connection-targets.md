# Phase 2A Step 7 CLI connection targets

## Source and toolchain

On November 26, 2026, the clean starting checkout was `master` at
`e764f272c9be4192a63b4672403fa9379ce5e48b`, matching local `origin/master`.
[PR #57](https://github.com/007pig/meshchan/pull/57) was already merged at
that commit. Its second parent is the reviewed Step 6 head
`25e3f173af993a0c543f589a90d225de2063b035`, with the same source tree as the
merge. Step 7 uses that factory and the Step 5 target model. This validation
applies to the Step 7 working-tree changes on that `master` checkout. The
earlier factory verification remains in the [Step 6 record](phase-2a6-transport-factory.md).

The installed `/opt/homebrew/share/flutter/bin/flutter` reported Flutter
3.50.0 stable (framework `ab2912035e`, engine revision `371f77202a`). The
bundled `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` reported
Dart 3.14.0 stable on `macos_arm64`. The commands use Apple Clang 21.0.0
(`clang-2100.4.1.1`) with `/usr/bin` first in the command-local `PATH`.
`/opt/homebrew/bin/python3` reported Python 3.15.2, with `sys.executable`
at `/opt/homebrew/opt/python@3.15/bin/python3.15`.

## CLI call paths

- `requiredPortOption` validates the explicit `--port` and returns its
  original string. The Companion parsers wrap it in `UsbSerialTarget`
  without I/O. Network-shaped values remain USB paths. `ports` and
  `port-check` use `SerialPorts` for native diagnostics.
  [Parsing](../../apps/meshctl/lib/src/business_input.dart) ·
  [Dispatch](../../apps/meshctl/lib/meshctl.dart)
- `runCli` accepts the public `CompanionTransportFactory`. Its production
  composition sets `appCompletionQueries: false`. Each admitted call creates
  a fresh, unopened USB transport using the existing initialization wrapper.
  `SessionOptions.target` carries the selection for `info` and `watch`. The
  display projection reads `portPath` for the existing `port` field, with
  normal JSON encoding and text escaping. Info publishes after actual close.
  Watch starts its duration at ready and observes events without consuming
  the inbox. [Session runner](../../apps/meshctl/lib/src/session_command.dart)
- `DatagramInput.target` carries the selection for all four datagram actions.
  The invocation owns the signal source, opens storage, and resolves effective
  parameters before admitting device work. Presets and `portHint` supply no
  connection authorization. `DatagramOptions.effective` keeps the same target
  object for the unrecorded runner. The direct `DatagramOptions` parser also
  constructs a USB target. [Options](../../apps/meshctl/lib/src/datagram_options.dart) ·
  [Storage admission](../../apps/meshctl/lib/src/stored_datagram_command.dart)
- Recorded datagrams pass `() => createTransport(input.target)` to
  `CoreStorage.record`. Core commits registration, checks cancellation, and
  then invokes the closure. The existing logical result, logical save,
  actual cleanup, and cleanup save remain independently observable. The CLI
  waits for storage and signal cleanup before delivering the final envelope.
  [CLI recording](../../apps/meshctl/lib/src/recorded_datagram_command.dart) ·
  [Core admission](../../packages/meshchan_core/lib/src/recording/recording.dart)

## Regression evidence

- `info` and `watch` each pass an exact `UsbSerialTarget` to the factory.
  The tests exercise leading and trailing spaces, a literal Tab, and a
  TCP URL passed as a USB path. They check the JSON `port` value, escaped
  text, watch NDJSON, the ready-based duration, and info waiting for close.
  Two invocations with the same target each create and close their own
  transport once. The serial integration fixture also checks the path
  received by the fake native connection builder.
  [Session tests](../../apps/meshctl/test/session_cli_test.dart) ·
  [Serial fixture](../../apps/meshctl/test/session_serial_cli_test.dart)
- Help, version, and syntax short circuits bypass Companion transport and
  storage. An omitted, blank, or NUL-containing `--port` returns the existing
  safe usage message and exit `64`. Native diagnostics still use the injected
  `SerialPorts`, with sorted metadata and the existing check result. They
  leave the Companion factory and business storage unused. Offline commands
  retain their storage-only behavior. [CLI tests](../../apps/meshctl/test/meshctl_test.dart) ·
  [Offline tests](../../apps/meshctl/test/business_cli_test.dart)
- Each of `send`, `listen`, `ping`, and `respond` runs in both modes with
  one factory call and the exact invocation target. The options tests check
  direct parsing and object identity through `DatagramOptions.effective`.
  A default preset and its hint cannot authorize a missing `--port`. Valid
  preset parameters leave the explicit target intact. Missing or mismatched
  presets and invalid merged parameters stop before the factory. The real
  SQLite fixture checks closure and reopen. [Datagram tests](../../apps/meshctl/test/business_datagram_test.dart)
- In each recorded success case, a one-shot hook after the real SQLite
  registration commit sets a flag. The injected factory asserts the flag at
  entry and checks the transport's open count is still zero. The test then
  checks one factory call, one open, one close, and the persisted result.
  A registration commit fault leaves the injected factory and subscription
  plan uncalled and closes storage. In the gated commit case, SIGTERM arrives
  before the commit can proceed. Registration later commits, the command
  returns `143`, and both factory and plan counts remain zero after storage
  closes. [Recording regressions](../../apps/meshctl/test/business_datagram_test.dart)
- Nonrecorded JSON listen retains its datagram events and end result.
  Recorded listen retains its bounded end summary. The exact
  `' SECRET_PORT\t '` selection is forwarded while recorded output and
  History export still omit the `SECRET_` port, preset hint, and payload.
  The same programming error thrown by the factory propagates after cleanup
  without reaching CLI output, and the directory can be reopened.
  The storage and failure-priority suites check signal and output handling
  during open, resolution, and close, including device failure precedence
  and waiting for signal-source cancellation after database close.
  Covered exits include `64` for usage, `69` for device and cleanup failure,
  `74` for host and output failure, and `130`/`143` for effective signals.
  The process-boundary test still reports unexpected errors safely as `70`.
  [Datagram tests](../../apps/meshctl/test/datagram_cli_test.dart) ·
  [Recording and export tests](../../apps/meshctl/test/business_datagram_test.dart) ·
  [Storage signals](../../apps/meshctl/test/datagram_storage_signals_test.dart) ·
  [Failure priority](../../apps/meshctl/test/datagram_failure_priority_test.dart)

## Validation commands

Run from the repository root. The CLI and link suites and the three native
builds run serially. The CLI keeps the configured test concurrency of one.

```sh
meshchan_flutter=/opt/homebrew/share/flutter/bin/flutter
meshchan_dart=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
meshchan_python=/opt/homebrew/bin/python3

"$meshchan_flutter" --version
"$meshchan_dart" --version
"$meshchan_python" --version
"$meshchan_flutter" pub get --enforce-lockfile
{ git diff --name-only HEAD -- '*.dart'; git ls-files --others --exclude-standard -- '*.dart'; } |
  sort -u | xargs "$meshchan_dart" format --output=none --set-exit-if-changed
"$meshchan_flutter" analyze --no-pub --fatal-infos

(cd apps/meshctl && PATH="/usr/bin:$PATH" "$meshchan_dart" test --reporter expanded \
  test/meshctl_test.dart test/session_cli_test.dart test/session_serial_cli_test.dart \
  test/datagram_cli_test.dart test/business_datagram_test.dart \
  test/datagram_storage_signals_test.dart test/datagram_failure_priority_test.dart)
(cd apps/meshctl && PATH="/usr/bin:$PATH" "$meshchan_dart" test)
(cd packages/meshcore_link && PATH="/usr/bin:$PATH" "$meshchan_dart" test)

(cd apps/meshctl && PATH="/usr/bin:$PATH" "$meshchan_dart" build cli \
  --target=lib/src/meshctl.dart --output=build/phase-2a7-cli)
(cd packages/meshcore_link && PATH="/usr/bin:$PATH" "$meshchan_dart" build cli \
  --target=example/serial_transport_check.dart --output=build/phase-2a7-observation)
(cd apps/meshctl && PATH="/usr/bin:$PATH" "$meshchan_dart" build cli \
  --target=tool/datagram_acceptance.dart --output=build/phase-2a7-datagram-acceptance)

PATH="/usr/bin:$PATH" "$meshchan_python" tool/smoke_cli.py \
  --expected-version 0.1.0-rc.1 --dart "$meshchan_dart" \
  --cli-bundle apps/meshctl/build/phase-2a7-cli/bundle \
  --observation-bundle packages/meshcore_link/build/phase-2a7-observation/bundle \
  --datagram-acceptance-bundle apps/meshctl/build/phase-2a7-datagram-acceptance/bundle \
  --evidence-directory apps/meshctl/build/phase-2a7-evidence/process

git diff --check
shasum -a 256 pubspec.lock
```

## Local results

| Check | Observed result |
| --- | --- |
| Locked resolution | `flutter pub get --enforce-lockfile` passed. The initial sandboxed Flutter launch could not write SDK engine cache stamps. The installed launcher succeeded with authorized cache access. The root lockfile retained SHA-256 `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`. |
| Formatting and analysis | All 16 affected Dart files passed formatting with zero changes. The first analyzer run flagged a local test callback declaration. After correcting it, the workspace analyzer with fatal infos reported no issues. The test suites below were rerun against that final Dart tree. |
| Targeted CLI tests | All 135 passed across the seven files listed above. |
| Full CLI suite | All 290 passed, including isolated SQLite, subprocess SIGINT/SIGTERM, and the source-only openHop idle, peer, and loopback TCP tests. |
| Full link suite | All 264 passed, including the public factory, USB initialization, and session lifecycle tests. |
| Three native CLI builds | Product CLI, serial observation, and datagram acceptance bundles built sequentially. All include `liblibserialport_plus.dylib`. The product and acceptance bundles also include `libsqlite3.dylib`. |
| Source, AOT, and relocated-bundle smoke | All 101 macOS process checks passed at `0.1.0-rc.1`. The checks cover a closed stdout pipe, complete bundle relocation, and real SQLite writes and reopen through source, AOT, and relocated entries. Five synthetic datagram scenarios passed in both source and AOT. The source and AOT recording probes each produced three saved runs. The smoke then queried and validated safe History exports, including through the relocated product bundle. The Linux enumeration case was inapplicable on this host. |
| Patch review | `git diff --check` passed. Both affected Markdown files passed whitespace, local link, and heading fragment checks. |

The test, analyzer, format, native build, and smoke logs are retained under
the ignored `apps/meshctl/build/phase-2a7-evidence/` directory. The smoke's
process ledger and closed test databases are retained in its `process/`
subdirectory.

The source audit found typed factory calls at the product CLI's three
transport creation sites and direct `SerialPorts` calls in native diagnostics.
The openHop idle probe still runs its separately injected transport and
displays `openhop-b`. The openHop peer retains its private TCP and WebSocket
selection and JWT-based builder. The scope check covers the App, core,
link package, schema, dependencies, lockfile, product version, CI,
and signing configuration.

The Step 7 verification uses synthetic transports, isolated SQLite files,
and local subprocess or loopback fixtures. The standalone core test suite
was outside this CLI-only change. Remote CI, VM GUI and Swift checks, App/DMG
and signing validation, BLE probes, and physical USB, TCP, BLE, and RF
acceptance were outside the Step 7 validation scope. Steps 9 and 10 cover
the wider 2A integration and delivery.

## Step 8 handoff

App Check and Diagnostic requests still carry USB path strings. Step 8
should carry a typed target in those requests and configure the factory with
`appCompletionQueries: true` inside the worker. Preserve the device gate,
attempt-scoped cancellation, lazy recording, actual release confirmation,
and the normal Quit contract. Product TCP and BLE adapters belong to 2B and
2C. The `local-adhoc` signing policy continues to apply.
[Architecture handoff](../architecture/companion-connections.md#step-8-app-handoff)
