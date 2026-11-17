# Delayed OK compatibility in the Meshchan client

Status: **Software/native loopback passed; the later
[one real B-only case](phase-1d11-delayed-ok-rf.md) passed local acceptance and
its planned no-responder timeout. Real OK delay beyond 15 seconds was not
reproduced; the GUI/RF matrix remains incomplete.** The operator explicitly
excludes modifying openHop. The previous
server patch proposal is withdrawn and removed from the current repository;
its prior owned research/source snapshots remain historical evidence only.
No remote code, service, firmware or configuration was changed. No deployment
access or service restart is requested.

## Problem and client policy

The [preceding real investigation](phase-1d11-openhop-ok-investigation.md)
recorded a 19.1-second server duty-cycle deferral beyond the original 15-second
request budget. PING also started its response clock before calling send.
A software reproduction preserves the legacy `responseTimeout / sending`
result at 15 seconds, before implementation. Historical failures remain.

Meshchan now offers an explicit policy for its source-only openHop peer:

1. Optional positive `MeshCoreSession.sendTimeout` independently bounds
   SEND_CHANNEL_DATA write plus matching OK from dispatch. It defaults to
   `requestTimeout`. Initialization and GET_MSG retain their ordinary command
   timeout. The same FIFO slot remains occupied, with no extra query or reader.
2. `MeshchanPingTask.responseTimeoutFromAcceptance` defaults to false. When
   enabled, the PONG window starts after successful local write **and actual
   OK**. Matcher and RTT origins still precede the one send, including the
   scheduling delay in successful application RTT.
3. Early exact PONG is retained, but cannot establish success until acceptance
   settles. ERR, write/transport failure, Cancel, send timeout or task timeout
   preserve that observation without a success RTT.
4. Whole-task time still starts before connect and is never extended. No
   unrelated frame/duplicate renews a budget. There is no terminal grace period,
   automatic retry/reconnect, fallback or second consuming session.

The peer opts in with optional `session.sendConfirmationSeconds`, an integer
between `commandSeconds` and `taskSeconds`. Omission preserves previous timing;
explicit invalid/null values are rejected before network access. Enabled runs
emit `peer_timing_policy` with budgets and clock origins, without private values.
For a future reviewed B operation, this fragment retains the 90-second task:

```json
{
  "session": {
    "commandSeconds": 15,
    "sendConfirmationSeconds": 60,
    "initializationSeconds": 30,
    "startupDelayMilliseconds": 0,
    "taskSeconds": 90
  }
}
```

A 15-second PONG window begins at acceptance. If the original whole-task
deadline arrives sooner, it wins; no full extra window is promised after a
late OK. This is a new explicit client policy, not an unchanged-parameter RF
rerun. Delay past the task deadline still fails. Cancel/close cannot retract
work already queued remotely; missing OK never proves zero RF.

No TCP product transport, GUI flag, profile/database/summary field or CLI schema
was added. USB/recording callers omit the new options and retain their defaults.
A GUI PING's response window still must cover its end-to-end operation; the B
mode does not silently enlarge A's window or establish the GUI hardware matrix.

## Fresh software and native validation

Evidence is in
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-06-client-delay/`.
Baseline remains actual PR #37 merge `0fd49a3495d972c88dee35fc709501db78a16d16`,
branch `codex/phase-1d11-hardware-beta`, with manifested uncommitted work.
Toolchain: `/opt/homebrew/bin/python3` 3.15.2; Flutter 3.50.0 / bundled Dart
3.14.0. Product versions, root lock and third-party graph were not changed.

| Fresh check | Result |
| --- | --- |
| Legacy timing reproduction | PASS assertion of original sending timeout, before implementation |
| Link session/task focused subset | PASS 67 tests, then full suite |
| TCP/peer/observer focused subset | PASS 37 tests |
| Full app/core/CLI/link suites | PASS 262 / 362 / 286 / 207 |
| `flutter analyze --no-pub --fatal-infos` | PASS |
| Device / Diagnostics process gates | PASS four Device cases / five Diagnostics cases; no hardware |
| Native CLI, observation, acceptance and source-only peer | PASS four new complete bundles with native assets |
| Source / AOT / whole-bundle relocation smoke | PASS 101 process checks, including beta recording/History and five datagram scenarios |
| Native peer localhost TCP fixtures | PASS four cases: delayed split OK + exact PONG; accepted no-PONG timeout at waiting; delayed ERR; Responder settlement |
| Real USB / B RF / GUI / physical action for this change | NOT_RUN |

Virtual-time tests reproduce a 19.1-second OK delay and exact PONG at 33.1
seconds, retaining the entire interval as RTT. They cover early PONG through
OK/error/cancel/send/task deadlines, unchanged initialization/read budgets,
unrelated input without renewal, and no resurrection after termination.
Real localhost TCP tests cross the original command/response limits, split OK
across chunks and assert one send with only the original finite reads. Native
fixtures invoke the newly compiled peer; their synthetic server is not a radio
or independent protocol oracle.

Two fixture/build-input failures are preserved: the first invalid-config test
used a Map inferred as integer-only and failed before validation; the corrected
fixture uses a dynamic JSON Map. One observation build used the CLI member cwd
for the link example; the corrected build uses the link cwd and distinct output.
Neither involved hardware. No assertion, timeout, skip or retry hid either
result. Software/native gates ran sequentially.

## Artifacts and remaining real comparison

`peer-native/bundle/` is the new complete source-only peer, outside product
distribution. `native-bundles.json` binds it and three software-test bundles to
all files/symlinks/modes. Gate source manifests bind compilation inputs; the
final snapshot/audit bind the later documentation cut.

The previous `delivery-beta1-build4/` app/CLI inventories remain frozen at their
hardware cutoff. Two shared link source files changed here: current bytes are
not retroactively attributed to that app. No new app/runtime/XCTest/RF pass or
final beta acceptance is inferred. Prior external snapshots, including the
withdrawn server proposal, remain historical cuts, not current work to apply.
Before final product delivery from this source, rebuild and verify affected
complete products at that actual source cut.

The software continuation above opens no USB, real B session or management endpoint and
consumes no real inbox. Actual cumulative attempts remain seven without a
cumulative ceiling; prior B consumption remains 282 entries / 288 reads. The
six-row GUI fixture and Chinese/emoji draft are unchanged. 1D.11 remains
incomplete. The next real comparison needs a reviewed explicit timing policy,
new peer inventory, selected/exclusive B, fresh IDs and existing stop rules.
No server modification or deployment permission belongs to that plan.

The operator subsequently approved that explicit timing policy. The linked
real B-only case used one send, received OK after 4.165858 seconds, then waited
15.002226 seconds to close with `responseTimeout / waiting`. It added 75
entries / 76 reads: current totals are eight application attempts and 357 B
entries / 364 reads, without a cumulative send ceiling. A remained closed.
This validates the policy's real post-OK clock and cleanup; an OK beyond the old
15-second command limit was not reproduced. Prior software counts and artifact
cuts above remain unchanged.
