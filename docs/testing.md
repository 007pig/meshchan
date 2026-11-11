# Hardware-free testing

The historical Phase 1 / 1A / Step 8 audit is retained below. Phase 1B.8 adds
datagram serial-byte acceptance shared by ordinary tests and a source/AOT
development probe, without changing product behavior.
Run commands from the repository root unless noted. Use the latest installed
stable Python 3.15 or newer for local Python scripts, as described in the
[local toolchain selection](development.md#local-python-toolchain). Python is a
development tool only; the distributed CLI does not require it.

## Historical behavior audit (1A.8)

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

## Datagram cross-layer coverage audit (1B.8)

This audit extends the historical 1A.8 audit above. Its conclusion about no
missing behavior groups applied to 1A only, before datagram implementation.
The five shared scenarios live in
`apps/meshctl/test/support/datagram_acceptance_scenarios.dart`; ordinary tests
and the development source/AOT probe call the same always-active checks.

| Behavior | Existing tests | New 1B.8 evidence | Still to validate |
| --- | --- | --- | --- |
| Raw binary send and local acceptance | `datagram_cli_test.dart`; core codec/transport short-write tests | `raw_send`: independent complete serial vector, successful short write, ordered initialization/send, no queue reads, awaited cleanup | Real native TX and firmware acceptance |
| Bounded shared inbox | Core reception tests; CLI consumption/filter/final-entry tests | `bounded_listen`: three consumed items, ordinary/filtered/matching counts, split and coalesced serial input, last event before end, no extra read | Real shared inbox and device behavior |
| Diagnostic correlation and RTT | Core diagnostic codec/tasks; CLI exact match and early-PONG failure tests | `ping_round_trip`: fixed request-1 bytes, independent local slots, queued PONG, controlled microsecond RTT | Two-device LoRa round trip |
| Finite responder and return configuration | Core deduplication/tasks; CLI cumulative/zero-response tests | `responder_reply`: fixed independent PING, exact PONG bytes, local return slot/path, one confirmed response | Real peer receipt and explicit return route |
| Partial PONG, deadline and release | Core deadline/cleanup tests; existing 16 info/watch serial combinations | `partial_pong_timeout`: partial outer frame, response timeout, late tail, pending reader stop and done gates, one failure after real cleanup | Historical USB delivery cause and ready-state H10 |
| Source/AOT/process boundary | Existing shared smoke: help, rejection, broken pipe, product relocation | Same five scenarios in source and separate native development bundle; strict JSON report validation | Other hosts and observed CI for this change |

Existing algorithm/parameter/failure-priority matrices and every framing split
point remain in their original tests. This adds five representative wiring
scenarios, not another Cartesian product. All native connections are synthetic;
no scenario enumerates, selects, or opens hardware.

## Reproduce acceptance on the existing Mac SDK

The subshell stops at the first failure. It creates fresh output, prints its path,
and retains it for inspection; do not substitute an older bundle after a failed
build. No command here supplies a valid port or enumerates on macOS.

```bash
(
  set -eu
  export PATH="/opt/homebrew/share/flutter/bin:/opt/homebrew/opt/python@3.15/bin:/usr/bin:$PATH"
  MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
  "$MESHCHAN_DART" --version
  python3 --version
  python3 -c 'import sys; assert sys.version_info >= (3, 15)'
  "$MESHCHAN_DART" pub get --enforce-lockfile
  "$MESHCHAN_DART" format --output=none --set-exit-if-changed .
  "$MESHCHAN_DART" analyze --fatal-infos
  (cd packages/meshcore_link && "$MESHCHAN_DART" test)
  (cd apps/meshctl && "$MESHCHAN_DART" test)
  CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meshchan-1b8.XXXXXX")"
  printf 'Fresh build output: %s\n' "$CHECK_DIR"
  (cd apps/meshctl && "$MESHCHAN_DART" build cli \
    --target=bin/meshctl.dart --output="$CHECK_DIR/meshctl")
  (cd packages/meshcore_link && "$MESHCHAN_DART" build cli \
    --target=example/serial_transport_check.dart --output="$CHECK_DIR/observation")
  (cd apps/meshctl && "$MESHCHAN_DART" build cli \
    --target=tool/datagram_acceptance.dart --output="$CHECK_DIR/datagram-acceptance")
  python3 tool/smoke_cli.py \
    --dart "$MESHCHAN_DART" \
    --cli-bundle "$CHECK_DIR/meshctl/bundle" \
    --observation-bundle "$CHECK_DIR/observation/bundle" \
    --datagram-acceptance-bundle "$CHECK_DIR/datagram-acceptance/bundle"
  git diff --check
)
```

Use only the installed Homebrew Flutter SDK and its bundled Dart. The direct Dart
path avoids the Flutter wrapper's cache-stamp writes under a restricted sandbox;
it does not validate the Flutter CLI. No SDK upgrade or cache modification is
part of this procedure. Native build hooks still require a compiler/platform SDK.
`git diff --check` checks tracked patch whitespace, not every untracked file or
historical commit. See the [1B.8 dated execution record](development.md#1b8-software-validation-on-november-10-2026)
and the retained [1A.8 record](development.md#step-8-software-validation-on-november-9-2026).

## Shared smoke contract and CI

`python3 tool/smoke_cli.py --help` describes the four required paths. Paths are
resolved before execution, including paths containing spaces. The script locates
the checkout from its own file, fixes source working directories to the two
packages, and rejects missing/empty executables or native libraries. It does not
install dependencies, build artifacts, accept arbitrary commands, or contact
GitHub. Prepare all three bundles before calling it. Keep the product CLI
bundle separate from the observation and development acceptance bundles.

The retained process cases cover source/native no-argument help, help/version,
all four original command help option sets, datagram group/four leaf help,
group-without-operation help, 16 invalid argument cases per CLI entry,
source/native observation usage with absent/blank input, a native broken pipe,
and four relocated entry checks. Two additional process cases execute the fixed
datagram probe in source and AOT: 69 checks on macOS, 73 on Linux for the current
script. The script counts actual completed checks; its success line is not a
fixed historical count. No real hardware command is executed. The version
expectation comes from the existing `lib/src/version.dart` constant. Linux adds
four actual `ports` / `ports --json` source/native refusal cases: exit 69, empty stdout, the exact pinned backend safety
diagnostic, and no unhandled exception/application stack. macOS prints an
explicit Linux-only non-applicability notice and never runs `ports`.

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
checkout, uses that directory as cwd, and checks version, info help, datagram ping
help, and missing port rejection. Executables and `lib/liblibserialport_plus.dylib` (macOS) or
`lib/liblibserialport_plus.so` (Linux) must be nonempty in both original bundles;
the relocated CLI assets are checked again. The separate development bundle's
asset is also checked. No library path is redirected to a
pub cache. Only the script-owned relocation copy is removed automatically.

CI retains one Ubuntu job, fixed Flutter/action versions, locked dependencies,
format/analyze, both full suites, and the two existing native builds. It builds a
third, separate development bundle with
`dart build cli --target=tool/datagram_acceptance.dart --output=build/datagram-acceptance`
from `apps/meshctl`, then passes it as `--datagram-acceptance-bundle` to this same
script after builds and has a 20-minute job limit for resource protection. Child
watchdogs also apply to Linux refusal and broken pipes. Failures are propagated;
there are no retries, skipped failed cases, or `continue-on-error`.

## Finite datagram CLI regression (1B.7)

`apps/meshctl/test/datagram_cli_test.dart` uses real codec/session/reception/tasks
and the existing fake transport/sink, with a narrow elapsed/nonce injection in
`runCli`. Production omits both seams. Table-driven pure validation asserts no
transport/enumeration/signal side effects. Wiring tests cover all four leaves,
post-consumption filtering and final-entry/read settlement, early PONG with
failed local send, nullable facts/microseconds, finite zero-response completion,
signal/output/core-failure races, cleanup pending/failure, and private-data
omission. The existing serial cross-layer matrix is retained unchanged.

After locked resolution, format, and analysis, run the focused CLI file before
the complete core and CLI suites; keep every test process/build serial:

```bash
(cd apps/meshctl && "$MESHCHAN_DART" test test/datagram_cli_test.dart)
```

This software validation does not select a port, run a wireless command, or
replace the separate 1B.8 serial-byte/AOT evidence or 1B.9 device acceptance.

## Shared datagram scenarios and development probe (1B.8)

Run just the shared scenarios or the development source entry from `apps/meshctl`:

```bash
"$MESHCHAN_DART" test --reporter expanded test/datagram_acceptance_test.dart
"$MESHCHAN_DART" run tool/datagram_acceptance.dart
```

The thin test and tool call the same five scenarios. Support imports no
`*_test.dart` or `package:test` code and uses checks that remain active in AOT.
Only `NativeSerialConnection` is replaced through the existing internal
`serialTransportForTest` seam. Every RX chunk enters the saved reader callback
with its outer serial header; every accepted TX prefix is checked against fixed
complete frames. The raw-send vector is independent of production encoders.
Queue scripts return datagrams only after complete `0x0A` commands. Splitting
and coalescing occur at a few representative boundaries; the exhaustive framing
matrix remains in the core tests.

Short-write retries use a per-frame `SerialWriteClock` origin and delays from
the same FakeAsync domain as task elapsed time. Initialization deliberately
advances that domain by three seconds before the next frame. Reader stop
acknowledgement and reader done are separate gates; final JSON/CLI completion
and port release must wait for both. The partial-PONG case locks the task failure
before cleanup, ignores the late tail/notice, and expects CLI 69 while the
acceptance scenario itself passes. One zero-duration external event turn settles
SDK cancellation Futures, followed by an explicit microtask barrier for the
raw runner's sequential cancellation continuation and completion checks. There
is no conditional pumping, real deadline sleep, or retry loop.

The probe has no hardware/argument/stdin mode. Its bounded JSON contains a fixed
probe ID, schema version, scenario IDs, pass flags, actual CLI exit codes, and
completed/passed/failed counts. Shared smoke parses JSON and validates types,
the exact unique five-ID set, all flags, expected CLI codes (including 69), and
counts. It runs source in the CLI package and AOT with a checkout-external cwd.
The AOT executable needs no source files at runtime and compiles no test runner.
Keep the entire product bundle for 1B.9; the development probe is not product
distribution content.

## Evidence limits

| Evidence | What it establishes | What it does not establish |
| --- | --- | --- |
| Dart unit tests | Asserted protocol, state and output behavior | Device compatibility or stability |
| Synthetic cross-layer cases | Production codec/transport/session/CLI wiring at a replaced native boundary | Actual USB driver, reader isolate or radio behavior |
| AOT synthetic probe | Independently compiled production Dart CLI/tasks/session/reception/serial framing execute all five shared scenarios | Production native constructor, FFI symbol loading, reader isolate, USB or LoRa I/O |
| Source/native process checks | Checked entry points, arguments, exit status and stdio | Handshake or native TX |
| Builds and nonempty assets | Host compilation and asset organization | Every native function loads/works or other platforms run |
| Complete bundle relocation | Checked entries execute outside the checkout on the same host | Clean-machine installation, native library loading, device I/O or hardware session AOT |
| Linux enumeration refusal | Unsafe enumeration remains blocked | Linux serial hardware support or loaded native library |
| Observed remote CI | Results for that event and commit | Uncommitted changes, future commits or hardware acceptance |

No 1A.8 or 1B.8 check opens or selects hardware. Historical incomplete 64-byte USB
response bodies remain an unresolved device/USB/driver investigation, not a
proven firmware, ZLP, or flush diagnosis. Synthetic split-body tests establish
waiting, timeout, cleanup and rejection of late results; passing them does not
repair USB delivery. No retry, reset, extra query, timeout/default-delay change,
signed release or LoRa round trip is included. Step 9 hardware acceptance remains
separate; see [hardware evidence](hardware-validation.md).


## openHop development boundary tests (1B.9)

`apps/meshctl/test/openhop_peer_test.dart` adds 15 tests to the existing CLI suite.
They cover inert configuration/URI/secret-reference validation, restricted REST
selection and redaction, real SDK WS split/coalesced binary frames, an independent
complete TX vector, text/oversized input, authentication close, normal close,
partial EOF, redirect rejection, and cancellation with late successful connection
cleanup. Real loopback session/PING cases insert current-time notifications;
separate initialization/response timeout cases prove they do not replace the
response or renew its budget. Raw listening compares actual consumed bytes and
ends at the entry quota; responder cancellation releases the signal subscription
and WS connection. The existing diagnostic algorithm matrix is reused.

These use 127.0.0.1 ephemeral sockets, synthetic JWT strings, and event/Completer
coordination. Only the short notification injection/deadline checks use real VM
timers. A local sandbox must allow loopback binding; `fake_async` cannot advance
real sockets. No default test or CI reads real credentials, opens USB, or contacts
openHop. The current single CI job automatically includes these tests and still
builds exactly three bundles. No fourth peer AOT product or new platform is added.

The [finite tool/matrix guide](openhop-acceptance.md) describes separately
authorized hardware execution. The 1B.9 full gate passed 180 core and 72 CLI
tests, followed serially by three fresh builds and 69 shared macOS smoke checks.
Source and AOT each passed all five existing datagram synthetic scenarios.
These are software observations, not RF acceptance. See the
[dated execution record](development.md#1b9-software-validation-on-november-10-2026).


## Read-only channel audit follow-up

`test/channel_audit_test.dart` adds 11 CLI-suite tests for inert config/slot
validation, serialized metadata queries, empty/zero-key filtering, duplicate-key
ambiguity, private frame wiping, wrong-index/extended-key/write failures,
finite timeout, cancellation while actual cleanup remains pending, unsupported
capacity, and explicit A-only/B-only operation without false comparison claims.
The fixtures assert exact host opcode sequences and no consuming/RF writes.
The separate held-EOF openHop regression proves WS cleanup waits beyond the
outgoing sink close and retains its input subscription until EOF. The full CLI
suite passed 84 tests after this follow-up. These are later results, not a change
to the historical 72-test candidate gate above. See
[actual device attempts](hardware-validation.md#read-only-channel-audit-on-november-10-2026).

## Passive-window and finite RF driver follow-up

`openhop_idle_probe_test.dart` adds two bounded lifecycle tests. A real loopback
probe case checks actual session ready, a passive window, no queue/RF/heartbeat
writes, and actual cleanup. The peer config test additionally rejects an unknown
idle timeout without a sufficient explicit measured lower bound. The complete
CLI suite now passes **88 tests**; core remains the separately recorded 180-test
run because its implementation did not change. No actual deployment credential
or device is accessed by these tests.

The Python driver is validated without hardware against real retained structural
results: H6 rejects a different timeout cause, H2 rejects wrong length/type/slot,
and H7 requires an exact PONG plus a still-active A before SIGINT. Hardware
results remain separately retained and include failures; these predicate checks
are not additional RF trials. The [Direct matrix record](hardware-validation.md#direct-rf-matrix-on-november-10-2026)
contains all actual exits, cleanup, send/matching facts and known limits.

The November 11 authorized hardware comparison is separate from the above
software tests: H2/H7 now have passing records with B command 15 s/A 5 s, and
all preceding failures remain. The summary accounts for every retained trial,
checks the cumulative 15-attempt cap and the comparison's individual H2 <=1 and
H7 <=3 allocations, and records actual cumulative attempts 14. No new Dart test
run or native rebuild is inferred from these hardware/metadata changes. See
[the actual comparison](hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026).

## Review regressions on November 11, 2026

Three later CLI regressions first reproduced the reported defects, then passed:
closing a never-opened WS transport without installing a frames listener;
pausing public frame delivery while keeping receive EOF as the real resource
cleanup gate; and a real loopback raw-read timeout after one exact datagram.
The last case checks retained reception counts, opcode 0x0A failure evidence,
no invented send fact, and actual cleanup. It does not duplicate diagnostic
matching algorithms or contact a deployment. The complete CLI suite now passes
**91 tests**. The previous held-EOF, late-open cancellation and real loopback
cases remain in that suite.

Six stdlib Python tests in `tool/run_openhop_acceptance_test.py` cover actual
A/B operation and response-limit validation, full/follow-up derived allocations,
B limits read from the real referenced config, duplicate/implicit/oversized
limits, role/route mismatches, rejection before execution-directory creation,
and read-only legacy failure accounting. They generate synthetic plans in a
temporary directory and never read credentials, bind a socket, open USB or run
a device process. Run from the checkout root:

```bash
python3 -m unittest discover -s tool -p '*_test.py' -v
```

The existing CI job now includes this command before the Dart suites. No new
platform or dependency was added. These are local results; no new remote CI
execution is claimed. Recorded core/native-build/smoke results retain their
original dates because production inputs and native bytes did not change.

## Settlement and captured-build regressions on November 11, 2026

The later Python suite passes **17 tests** (11 added to the earlier six).
Synthetic process tests exercise failed cleanup, an unfinished sender,
unexpected orchestration errors, retained pending snapshots, repeated waits on
a failed cleanup, and metadata failure after process creation. They assert that
other started finite peers are awaited, partial case records and known sends
are saved before STOPPED, unknown sends remain null with reserved bounds, and no
extra process, resend or signal is introduced. No real child device process is
started by these tests.

Summary tests use synthetic candidate bytes and execution-plan captures. They
check captured-hash provenance, rejection of replaced bytes or mixed/missing
captures, preservation of an existing summary on rejection, blocked unknown
accounting, legacy stopped trials without results, and failure of cached PASS
records with unsuccessful cleanup. The unchanged CI discovery command includes
both Python test files automatically. Dart source did not change in this follow-up;
the prior 91-test CLI result is retained with its source hashes rather than
reported as a new execution. No hardware/API credential is used.

## Interrupted-run and input-schema regressions on November 11, 2026

The Python suite now passes **25 tests**, adding eight groups to the earlier
17. Interrupted-run regressions keep an existing completed case in results.json
and add unrepresented pending/completed process metadata or a later retry in
the same case. Summary generation must reject these incomplete totals. Matching
metadata is accepted and hashed; changed PID/argv/final/cleanup facts reject.

Channel regressions cover decimal leading zeros, explicit hexadecimal values,
preflight rejection of invalid uint8 values, and a complete synthetic H2 execution
with `--receive-channel=01` that must save PASS and one send after settlement.
Probe regressions pass the flat emitted report and legacy execution wrapper
through actual plan generation, including omission of the optional exact timeout.
Failed exit/status/cleanup, insufficient window, nonpassive activity and malformed
window values reject before creating plan output. The summary accepts both probe
shapes through the same validator.

The full CLI suite was also rerun with local loopback access: **91 passed**,
including the 16 socket cases blocked by the review environment. Format checked
56 files with zero changes; fatal-info analysis was clean. Real USB and the
openHop deployment were not accessed. Existing CI discovery includes all 25
Python tests; no remote CI result is claimed.

## Ledger, session-race and archive-provenance regressions on November 11, 2026

The Python suite passes **31 tests**, adding six groups to the earlier 25.
Unknown output-directory regressions cover execution-plan, results, STOPPED and
pending-process evidence alongside a completed registered run. Generation must
reject before replacing an existing summary. Synthetic archive tests regenerate
a sibling delivery directory and its checksum/native manifests while leaving the
verified tar.gz unchanged. Only original archived bytes and notices may be copied;
incompatible RF hashes, changed archive bytes and changed external native bindings
reject. Temporary extraction cleanup is verified. Fake native fixtures never run.

The complete CLI suite passes **92 tests**, including all loopback socket cases.
One added synchronous-transport test commits a raw send OK then immediately emits
an error before the awaiting continuation resumes. The final report must keep
completed write/OK/acceptance facts, record transport/session failure, exit 69,
complete cleanup and leave no frame listener. Format checked 56 files with zero
changes and fatal-info analysis was clean. These are local offline results;
hardware and remote CI were not run. Existing CI discovery includes the new
archive test file automatically. The [dated software record](development.md#ledger-raw-session-and-archive-provenance-fixes-on-november-11-2026)
links the logs and evidence checks.

The subsequent [Python 3.15 follow-up](development.md#python-315-toolchain-follow-up-on-november-11-2026)
reran all **31 Python and 92 CLI tests** with Python 3.15.2 selected, including
all local loopback cases. Format and fatal-info analysis also passed. New source,
summary and final-archive verification records include the actual interpreter;
future local scripts use the latest installed stable Python 3.15 or newer.

## Channel-audit final-query regressions on November 11, 2026

The complete local suite now passes **95 CLI tests**, including the loopback
tests blocked by the review sandbox. Three added synthetic audit cases cover
final channel reply followed by an immediate transport error for A-only and
A-then-B, and an error while final cleanup waits on a Completer. Before the fix,
both same-turn cases produced PASS. They now require FAIL/69, a retained read
summary, successful actual cleanup, no listener leak, no B open/comparison and
no secret-bearing output. The held-cleanup case also requires that the report
remain pending until release. Existing successful readback and signal cases
still pass. Python 3.15.2 ran all 31 Python tests successfully; format checked
56 files without changes and fatal-info analysis was clean. See the
[dated source/log record](development.md#channel-audit-final-query-failure-fix-on-november-11-2026).

## Protocol-input and evaluation-accounting regressions on November 11, 2026

The full local suite passes **97 CLI tests**, including every loopback case,
and **34 Python tests** under Python 3.15.2. Two new Dart cases deliver a valid
final channel reply then malformed SELF_INFO [0x05] over synchronous and
asynchronous underlying streams. Before the fix both passed; now they require
FAIL/69, protocolFailed, retained read summaries, real cleanup, no B open/key
comparison, wiped private frames and no extra queue/RF commands. Existing valid
notices, cancellation and transport-failure tests still pass.

Three new Python groups reject missing post-execution metadata in both CLI modes
before output/process creation, reject invalid byte counts/types/expected exits,
and inject an evaluator RuntimeError after a completed synthetic H2 send. The
last case must persist both settled records, one known application send and a
STOPPED record with only the exception type. Existing leading-zero success and
unknown-send/cleanup accounting tests remain. No hardware child process or real
credential is used. Fatal-info analysis and 56-file zero-change formatting pass;
see the [dated verification](development.md#protocol-input-and-evaluation-accounting-fixes-on-november-11-2026).

## Content and invocation-ledger regressions on November 11, 2026

The Python suite passes **41 tests** with seven groups added to the previous 34.
Plan regressions shorten every actual A/B initiating content option without
changing metadata, shorten H5 and its count together, and exercise UTF-8 byte
counts plus malformed hex. All inconsistent plans reject before device work.
Summary regressions retain contradictory zero/over/unknown totals, unknown send
facts with zero reserved bounds, multiple responder invocations and misleading
legacy read-only send fields. Counts must agree with all invocation facts;
rejection preserves an existing output. Captured H5 argv is independently checked
against the 131-byte boundary rather than accepting its cached contentBytes.

The test subprocesses use sys.executable. The suite was run through Homebrew
Python 3.15.2 with Apple Clang's PATH first; although bare python3 resolves to
/usr/bin/python3, all 35 observed Python children used the selected Homebrew
interpreter. Logs and hashes are in the
[dated follow-up](development.md#content-invocation-ledger-and-interpreter-fixes-on-november-11-2026).
Dart/core/native inputs did not change, so their prior complete gate retains its
original date rather than being presented as a new execution. No real device,
deployment, credential or RF send is used by these regressions.

## Runner cancellation and acceptance exits on November 11, 2026

The Python suite passes **46 tests** under 3.15.2, adding five groups. H4 rejects
a one-byte B content option even when its metadata is edited to match; direct
evaluation accepts zero and rejects one. Mocked driver tests interrupt the A
settlement wait with KeyboardInterrupt or two self-delivered SIGINTs. They require
both peers observed, unchanged send count, actual cleanup facts, saved results/
STOPPED, exit 130 and restoration of the original handler. Resuming the same wait
does not start a new process or reset its deadline.

Separate tests require exit 69 for a failed cleanly settled selected case and
for two synthetic cases where FAIL is followed by PASS. The latter confirms
continued authorized execution cannot reset the aggregate status. Existing
passing-case, failed/pending cleanup and evaluator-error tests still pass.
All 40 observed Python child calls use the selected 3.15.2 interpreter. Dart and
native inputs did not change, so their prior complete gate was not rerun. See the
[dated software record](development.md#runner-cancellation-exits-and-empty-content-fixes-on-november-11-2026).
