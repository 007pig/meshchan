# Meshchan

Meshchan is an open-source decentralized content application based on MeshCore. Its long-term direction is Flutter and Dart, with a reusable communication core that stays independent of Flutter. Development starts with a command-line diagnostic tool before adding a user interface.

The offline business core and product CLI now cover **Phase 1 / 1C / Step 9**:
persistent drafts, complete operation presets, typed settings, default/explicit
profile resolution, opt-in diagnostic recording, recovery, bounded history,
protected deletion, retention and safe single-page export. The [CLI guide](docs/cli.md#offline-business-commands-and-storage-1c8)
explains data directories, revision/cursor inputs and independent logical,
cleanup, save, maintenance and close results. All finite datagrams open business
storage; only `--record` adds a diagnostic run. Recorded listen emits one final
summary, while unrecorded listen keeps its per-entry NDJSON. Package versions
are `0.1.0-dev.3`; the [local delivery record](docs/releases/phase-1c-dev3.md)
separates source/native/archive acceptance from CI, clean-environment and public distribution status.
These are software/source/AOT results, not new hardware acceptance.

**Phase 1 / 1D / Step 3** connects the [Flutter macOS host](apps/meshchan_app/README.md)
to one application-owned long-lived storage worker, a typed control/read bridge,
device admission, recording lifecycle observation and confirmed shutdown.
Normal startup reads bounded offline data without enumerating or opening devices.
Drafts, Device and Diagnostics share real runtime status; their business workflows
remain later steps. See the [runtime record](docs/validation/phase-1d3-runtime.md)
for current results and limits, and the [1D.2 platform record](docs/validation/phase-1d2-platform.md)
for the historical finite probe. The [host contract](docs/architecture/flutter-host.md)
retains the macOS arm64 + USB target and the deferred distribution/hardware scope.

The historical hardware track covers **Phase 1 / 1B / Step 9: finite USB/openHop development acceptance and a local `0.1.0-dev.2` candidate**. The product remains USB-only. A source-only [openHop peer](docs/openhop-acceptance.md) reuses Meshchan's existing core for a selected virtual Companion over binary WebSocket. It is excluded from the product bundle and is not an independent application-protocol oracle. The fresh [software gate](docs/development.md#1b9-software-validation-on-november-10-2026) and source/AOT synthetic checks passed. [Real Direct acceptance](docs/hardware-validation.md#direct-rf-matrix-on-november-10-2026) established exact round trips in both directions, the binary boundary, and no-responder timeout. A later [authorized H2/H7 comparison](docs/hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026) passed local acceptance and active cancellation with B command=15 s/A=5 s. Every basic case now has a passing record, with all earlier failures retained; relay paths and physical unplug remain untested. See the [dev.2 local delivery record](docs/releases/phase-1b-dev2.md).

Historical 1A evidence remains separate. On November 9, 2026, a fresh software gate and the fixed H2–H7 USB hardware matrix passed on one macOS 27.2 arm64 host and one explicitly authorized Companion USB device. H1 enumeration, H8 nonexistent-port handling and H9 initialization cancellation passed. Later H10 startups failed three times before ready, with confirmed cleanup; a separate manual replug/info sequence had one timeout and one success. Ready-state disconnect detection and a complete H10 recovery cycle remain untested. See the [1A delivery record](docs/releases/phase-1a-dev1.md) and [latest H10 attempt](docs/hardware-validation.md#step-9-h10-third-startup-on-november-9-2026).

The complete archived 1A bundle passed extraction and integrity checks. The recommendation remains **development with known limitations**: historical intermittent USB delivery failures remain unresolved, and a successful info call did not establish stable initialization or a waiting/replug fix. The [channel-datagram contract](docs/protocol/channel-datagrams.md) is implemented in software. Its basic Direct real-device cases have passing records in the [November 10 matrix](docs/hardware-validation.md#direct-rf-matrix-on-november-10-2026) and the [November 11 H2/H7 follow-up](docs/hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026), with earlier failures retained. Specified relay paths and ready-state physical USB unplug remain untested; public redistribution remains open.

See the [testing guide](docs/testing.md) for the behavior audit and shared source/native smoke checks, including broken pipes and complete-bundle relocation. `meshctl info --port <path>` initializes one existing `MeshCoreSession`, awaits cleanup, and prints a complete closed-connection snapshot. `meshctl watch --port <path>` initializes once and observes session states and unassociated response summaries until duration, signal, or failure. The original `ports` and `port-check` commands remain available. All four commands support JSON; watch uses NDJSON. See the [CLI guide](docs/cli.md) for options, schemas, cancellation, exit codes, and explicit-port hardware authorization.

See the [session contract and minimal caller example](docs/protocol/companion-session.md), [Companion codec layout](docs/protocol/companion-initialization.md), [serial transport contract and read-only example](docs/protocol/serial-transport.md), and [serial framing protocol](docs/protocol/serial-framing.md). Session software tests use a fake transport and synthetic responses. An [authorized Step 6 hardware follow-up](docs/hardware-validation.md#authorized-session-hardware-follow-up-on-november-9-2026) passed actual source and AOT initialization and cleanup on one selected macOS USB port. A [subsequent timeout investigation](docs/hardware-validation.md#session-timeout-investigation-on-november-9-2026) reproduced a delayed 64-byte response body with an independent POSIX client, outside Dart. Zero- and one-second sessions also passed; three seconds is not an established fix for this intermittent USB delivery problem. The product startup-delay default stays zero. Step 2/4 hardware results and the Step 5 probe remain separate historical evidence. Ready means only the two initialization sends and parsed response types completed; it proves no authenticated identity, full protocol-version support, or LoRa communication. Step 7 software acceptance uses synthetic transport tests and hardware-free process checks; the historical hardware runs do not validate the new CLI on a device.

A separately authorized [Step 7 CLI hardware follow-up](docs/hardware-validation.md#step-7-authorized-cli-hardware-follow-up-on-november-9-2026) passed source/native watch, duration, and ready-state signal cleanup on one selected port; both initial info attempts timed out. A later [bounded native CLI comparison](docs/hardware-validation.md#step-7-cli-timeout-comparison-on-november-9-2026) observed both successful info snapshots and watch timeouts with unchanged defaults. Captured failures had incomplete input at the native receive boundary; no CLI initialization defect was demonstrated. The delivery issue remains unresolved.

A subsequent [independent POSIX control](docs/hardware-validation.md#step-7-independent-posix-comparison-on-november-9-2026) reproduced the header-only 64-byte wait three times without Dart, libserialport_plus, or its reader. At the unchanged request deadline the tty input queue was empty and direct OS reads returned no remaining bytes. The stall therefore does not require those client components; device/USB/driver responsibility remains unresolved, with no retry or configuration workaround added.

| Package | Responsibility and current status |
| --- | --- |
| `packages/meshcore_link` | Flutter-independent Dart core with single-use Companion sessions, serialized commands, bounded shared-inbox reception, binary channel codecs, finite diagnostic PING/responder tasks, serial framing/transport, and serial diagnostics. |
| `packages/meshchan_core` | Persistent drafts/profiles/settings and parameter resolution; finite diagnostic recording with separate logical/cleanup/persistence results and exclusive startup recovery; bounded history queries, guarded deletion, automatic retention and safe JSON summary export (1C.7). SQLite schema 1 remains unchanged. The public host API is now wired into meshctl (1C.8). See the [offline history API and example](packages/meshchan_core/README.md#diagnostic-history-retention-and-safe-export-1c7). |
| `apps/meshctl` | Offline draft/profile/settings/history commands and asynchronous diagnostic CLI: `ports`, `port-check`, `info`, `watch`, and finite `datagram send/listen/ping/respond`; text/JSON/NDJSON output and awaited cleanup. Separate development-only source/AOT acceptance probe. |
| `apps/meshchan_app` | Flutter macOS navigation skeleton and explicit finite native fixture probe, version `0.1.0-dev.3+1`. Normal startup does not bootstrap business resources. |

Local Python scripts and tests use the latest installed stable Python **3.15 or
newer**. On this Mac, `/opt/homebrew/bin/python3` is the verified 3.15.2 entry;
see [toolchain selection](docs/development.md#local-python-toolchain) to keep it
selected alongside Apple Clang. Python is not required by the product bundle.

## Quick start

On this machine, use the Homebrew-managed Flutter SDK and its bundled Dart SDK:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"

# Run from the project root.
flutter pub get --enforce-lockfile
cd apps/meshctl
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart ports --help
dart run bin/meshctl.dart port-check --help
dart run bin/meshctl.dart info --help
dart run bin/meshctl.dart watch --help
dart run bin/meshctl.dart datagram --help
dart run bin/meshctl.dart datagram ping --help
dart run bin/meshctl.dart datagram respond --help
```

Running without arguments or with `-h` also displays help. The application version is `0.1.0-dev.3`. Help and version do not access hardware. Select and authorize a port explicitly before device commands; old selections do not carry over. `ports` lists exact system paths, descriptions, transport types, and USB VID/PID when available. It does not open ports or send probes. Missing metadata appears as `-`; a per-port metadata failure retains the path and writes a warning to stderr.

**Current native platform limits:** macOS is locally validated. With the pinned `libserialport_plus` 1.0.5, native `ports` is blocked on Linux, Android, and Windows before enumeration because the backend can open unselected ports. Windows `port-check` is also blocked before native handle creation because the wrapper's handle state check is unsafe on 64-bit Windows. These operations return `69` with an explanation. Explicit-port checking on Linux/Android remains unverified. Malformed UTF-8 metadata on an enabled backend produces a warning for that path while other records remain available.

To check a device, select its exact path explicitly, then run `dart run bin/meshctl.dart port-check --port "$MESHCHAN_PORT"` after setting `MESHCHAN_PORT` to that path. The command opens only that port for reading and writing, checks its state, closes it, verifies closure, and disposes native resources. It does not read or write data or explicitly configure serial settings. Opening or closing a port can still reset some boards through driver or control-line behavior. No port is chosen automatically.

| Exit code | Meaning |
| --- | --- |
| `0` | Success, including a genuinely empty enumeration (`No serial ports found.`). |
| `64` | Invalid arguments, unknown commands/options, missing or blank `--port`, or extra positional arguments. |
| `69` | Expected serial, platform, session, or cleanup failure. |
| `74` | Host/storage/file/output I/O failure without an earlier primary cause; see the CLI guide for independent finalization facts. |
| `130` / `143` | SIGINT / SIGTERM cancellation; cleanup is still awaited. |
| `70` | Unexpected program error at the process boundary. |

**An open/close success does not identify a MeshCore device.** Transport `open()` establishes local I/O only; `sendFrame()` completion means the local native/OS API accepted the framed bytes. Neither proves command execution, physical TX completion, or remote receipt. Offline database features are available in the CLI; Flutter business pages remain later 1D work. Automated tests do not access hardware.

## Native CLI bundle

Source execution and compilation run the dependency's build hook, so a working native compiler and platform SDK are required, even for source help/version commands. On this validated macOS installation, prefer the installed Apple Clang for this terminal session:

```bash
# Run from the repository root.
export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
cd apps/meshctl
dart build cli --target=bin/meshctl.dart --output=build/dist
build/dist/bundle/bin/meshctl --version
build/dist/bundle/bin/meshctl info --help
build/dist/bundle/bin/meshctl watch --help
```

Move or copy the entire `apps/meshctl/build/dist/bundle/` directory, including `bin/meshctl` and all serial/SQLite native assets under `lib/` on macOS. Do not distribute the executable alone. Build output is ignored by Git. This bundle was checked on local macOS arm64, including after moving it outside the repository; clean-machine compatibility and other platforms remain unverified, with the runtime restrictions described above.

See the [Developer Guide](docs/development.md) for toolchain requirements, reproducible checks, dependency sources and licenses, and CI details. The [Validation Record](docs/hardware-validation.md) separates verified software and selected-port checks from remaining validation.


A later [read-only channel audit](docs/hardware-validation.md#read-only-channel-audit-on-november-10-2026)
found eight matching A/B 16-byte key representations without consuming the inbox
or sending RF data. Its two initial USB timeouts remain recorded. The separate
development WS adapter cleanup correction waits for receive EOF; the later CLI
suite passed 84 tests. Those counts and the original dev.2 binary/archive remain
historical. Basic Direct acceptance subsequently completed on the selected
A slot 1/B slot 3 zero-hop path, including the authorized H2/H7 follow-up linked
above. This dev.3 delivery adds no new RF acceptance.


The macOS app now has an [offline draft list and explicit-save editor](apps/meshchan_app/README.md#offline-drafts-1d4).
See the [1D.4 validation record](docs/validation/phase-1d4-drafts.md) for tested
runtime, persistence, input and quit behavior and the handoff to presets/settings.
