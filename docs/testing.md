# Hardware-free testing

Phase 1 / 1A / Step 8 consolidates process acceptance without changing product
behavior. Run commands from the repository root unless noted. Python 3 is a
development tool only; the distributed CLI does not require it.

## Behavior audit

Paths below are relative to each package's `test/` directory. The audit found no
missing unit/integration behavior group requiring another Dart test. Existing
assertions remain unchanged; the gaps were repeatable process and bundle checks.

| Layer | Existing tests and representative assertions | Remaining gap / Step 8 action |
| --- | --- | --- |
| Serial diagnostics | Core `serial_ports_test.dart`: platform guard before callback; exact selected path; partial-open recovery; metadata failure/disposal; private metadata omitted | No additional unit group needed. |
| Serial framing | Core `serial_framing_test.dart`: independent vectors; every two-part split/coalescing; 1..176 lengths; bounded noise; failure lock; owned buffers | No gap identified. Independent vectors retained. |
| Transport | Core `serial_transport_test.dart`: partial writes and total test-clock deadline; receive/send error races; stop gate; natural reader done before release; unconfirmed stop never frees | No gap identified. No new cleanup timeout. |
| Message codecs | Core `companion_messages_test.dart`: independent bytes, version/length gates, signed power/radio units, sensitive fields skipped | No gap identified. |
| Session | Core `meshcore_session_test.dart`: two ordered commands; early/late responses; send completion; timeout/cancel; shared awaited cleanup | No gap identified. |
| CLI | CLI `meshctl_test.dart`, `session_cli_test.dart`: zero side effects for invalid arguments/help; parsed JSON/NDJSON; exit codes; signal cancellation; sync/done/flush/queue failures; deduplication; privacy | No duplicate tests added. Negative assertions check no transport creation, enumeration, unexpected sends, or sensitive output. |
| Cross-layer wiring | CLI `session_serial_cli_test.dart`: real codec/transport/session/CLI, replacing only the native boundary; 16 info/watch × response stage × body arrival × blocked-output combinations | Retained as one parameterized group. Checks late input cannot revive failure, exact sends, cleanup order, final parsed output and no remaining timers. |
| Processes and artifacts | Existing CI covered help/version, invalid parameters, builds and Linux refusal; historical local checks covered example usage, broken pipe and relocation | `tool/smoke_cli.py` now shares all of these checks between local runs and CI; adds JSON enumeration refusal, strict watchdogs and complete-bundle asset checks. |

Session/CLI timing uses `fake_async` and controlled Futures/sinks. Transport write
deadlines use its existing injected test clock: virtual timers do not control a
normal Stopwatch or native I/O. Cross-zone stream completion in the integration
group retains its zero-duration event turn, without sleeping through a request
budget. Existing tests observe cleanup and asynchronous errors rather than
retrying until green. Keep separate `dart test` processes and native builds
serial because native-asset build state is shared within the workspace.

## Reproduce acceptance on the existing Mac SDK

The subshell stops at the first failure. It creates fresh output, prints its path,
and retains it for inspection; do not substitute an older bundle after a failed
build. No command here supplies a valid port or enumerates on macOS.

```bash
(
  set -eu
  export PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH"
  MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
  "$MESHCHAN_DART" --version
  python3 --version
  "$MESHCHAN_DART" pub get --enforce-lockfile
  "$MESHCHAN_DART" format --output=none --set-exit-if-changed .
  "$MESHCHAN_DART" analyze --fatal-infos
  (cd packages/meshcore_link && "$MESHCHAN_DART" test)
  (cd apps/meshctl && "$MESHCHAN_DART" test)
  CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meshchan-step8.XXXXXX")"
  printf 'Fresh build output: %s\n' "$CHECK_DIR"
  (cd apps/meshctl && "$MESHCHAN_DART" build cli \
    --target=bin/meshctl.dart --output="$CHECK_DIR/meshctl")
  (cd packages/meshcore_link && "$MESHCHAN_DART" build cli \
    --target=example/serial_transport_check.dart --output="$CHECK_DIR/observation")
  python3 tool/smoke_cli.py \
    --dart "$MESHCHAN_DART" \
    --cli-bundle "$CHECK_DIR/meshctl/bundle" \
    --observation-bundle "$CHECK_DIR/observation/bundle"
  git diff --check
)
```

Use only the installed Homebrew Flutter SDK and its bundled Dart. The direct Dart
path avoids the Flutter wrapper's cache-stamp writes under a restricted sandbox;
it does not validate the Flutter CLI. No SDK upgrade or cache modification is
part of this procedure. Native build hooks still require a compiler/platform SDK.
`git diff --check` checks tracked patch whitespace, not every untracked file or
historical commit. See the [dated execution record](development.md#step-8-software-validation-on-november-9-2026).

## Shared smoke contract and CI

`python3 tool/smoke_cli.py --help` describes the three required paths. Paths are
resolved before execution, including paths containing spaces. The script locates
the checkout from its own file, fixes source working directories to the two
packages, and rejects missing/empty executables or native libraries. It does not
install dependencies, build artifacts, accept arbitrary commands, or contact
GitHub. Prepare both bundles before calling it.

On macOS, 46 process cases cover source/native no-argument help, help/version,
all four command help option sets, 12 invalid argument cases per CLI entry,
source/native observation usage with absent/blank input, a native broken pipe,
and three relocated entry checks. The version expectation comes from the existing
`lib/src/version.dart` constant. Linux adds four actual `ports` / `ports --json`
source/native refusal cases (50 total): exit 69, empty stdout, the exact pinned
backend safety diagnostic, and no unhandled exception/application stack. macOS
prints an explicit Linux-only non-applicability notice and never runs `ports`.

Every child runs serially with closed stdin, captured/drained output, and a
60-second watchdog. A timeout fails the script and kills/reaps only the child's
new process group, including its build-hook descendants. The script never adds a
timeout to production cleanup. Usage failures require 64 and empty stdout;
source build-hook stderr may coexist with the required specific diagnostic.

The native broken-pipe case closes the OS pipe's read end **before** child
startup, connects stdout to the write end, and closes the parent's write copy.
It requires exit 74 and `Error: CLI output failed.` with no stack. There is no
sleep, shell pipeline, live watch, or simulated production dependency. Existing
sink tests separately prove session cleanup on output failure.

Relocation copies the **whole** CLI bundle into a temporary directory outside the
checkout, uses that directory as cwd, and checks version, info help, and missing
port rejection. Executables and `lib/liblibserialport_plus.dylib` (macOS) or
`lib/liblibserialport_plus.so` (Linux) must be nonempty in both original bundles;
the relocated CLI assets are checked again. No library path is redirected to a
pub cache. Only the script-owned relocation copy is removed automatically.

CI retains one Ubuntu job, fixed Flutter/action versions, locked dependencies,
format/analyze, both full suites, and both native builds. It invokes this same
script after builds and has a 20-minute job limit for resource protection. Child
watchdogs also apply to Linux refusal and broken pipes. Failures are propagated;
there are no retries, skipped failed cases, or `continue-on-error`.

## Evidence limits

| Evidence | What it establishes | What it does not establish |
| --- | --- | --- |
| Dart unit tests | Asserted protocol, state and output behavior | Device compatibility or stability |
| Synthetic cross-layer cases | Production codec/transport/session/CLI wiring at a replaced native boundary | Actual USB driver, reader isolate or radio behavior |
| Source/native process checks | Checked entry points, arguments, exit status and stdio | Handshake or native TX |
| Builds and nonempty assets | Host compilation and asset organization | Every native function loads/works or other platforms run |
| Complete bundle relocation | Checked entries execute outside the checkout on the same host | Clean-machine installation, native library loading, device I/O or successful session AOT |
| Linux enumeration refusal | Unsafe enumeration remains blocked | Linux serial hardware support or loaded native library |
| Observed remote CI | Results for that event and commit | Uncommitted changes, future commits or hardware acceptance |

No Step 8 check opens or selects hardware. Historical incomplete 64-byte USB
response bodies remain an unresolved device/USB/driver investigation, not a
proven firmware, ZLP, or flush diagnosis. Synthetic split-body tests establish
waiting, timeout, cleanup and rejection of late results; passing them does not
repair USB delivery. No retry, reset, extra query, timeout/default-delay change,
signed release or LoRa round trip is included. Step 9 hardware acceptance remains
separate; see [hardware evidence](hardware-validation.md).
