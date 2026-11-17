# One real B-only delayed-confirmation policy check

Status: **PASS for local acceptance followed by the planned no-responder
timeout. A real OK delay beyond 15 seconds was not reproduced.** This is not
a PING/PONG or GUI hardware acceptance pass. The beta remains prepared /
acceptance incomplete.

## Authorization and source

The operator approved B's new explicit timing policy and instructed continuation.
The reviewed first case was one B-only TCP 5050 session and one PING, with A/USB
closed, no responder, at most 512 consumed entries, no retry or fallback, and
normal abnormal-stop rules. Existing B selection/exclusive-client assertion and
shared-inbox consent remained. Cumulative application sends have no ceiling.
No openHop code, service, firmware, duty-cycle/radio/Fabric configuration or
credential changed. No server access or deployment was requested.

The actual baseline is PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16`, tree
`e59fd975aeecdd72152424d1446683b3b647827f`, branch
`codex/phase-1d11-hardware-beta`, with manifested uncommitted client work.
Python is `/opt/homebrew/bin/python3` 3.15.2. The traced native peer was compiled
with Flutter 3.50.0's bundled Dart 3.14.0 from the
[client implementation](phase-1d11-delayed-ok-client.md), whose compilation
source-manifest SHA-256 is
`2150d8bcde63e5490457e6b5fc61133a62c37469045ac1e93010a70192b01d84`.
The complete bundle inventory includes the executable and both native assets;
the executable SHA-256 is
`cd1646d2fbfbf38951e3a1511ed6f007da4f41f5832cf77303be50d711eb4885`.

Owned evidence is
`/private/tmp/meshchan-1d11-20261116-01/hardware/run-07-proposed/`.
That directory and the original plan retain their preparation names; appended
authorization, actual gate receipts, `evaluation/`, trace and execution state
establish that this attempt was executed. Earlier preparation facts are not
rewritten. Private endpoint equality was checked in memory against the current
owner-only local configuration; values were not printed or added to Git.

## Finite case and actual observations

| Parameter | Actual value |
| --- | --- |
| B / mode | Selected independent B, direct TCP 5050; no WS fallback |
| A | Closed throughout; no USB enumeration/open or GUI launch |
| Control / send confirmation / initialization / whole task | 15 / 60 / 30 / 90 seconds |
| PONG response window | 15 seconds from local write plus actual OK |
| Startup delay | Zero |
| Send / receive slot | B local slot 3 / 3 |
| Route / payload | Direct descriptor 0, empty path; fixed non-sensitive 18 content bytes / 52 diagnostic payload bytes |
| Correlation | Fresh distinct nonzero test IDs and runtime secure nonce; no matching responder started |
| Entries / attempts | maxEntries 512; one send; one session; no automatic replay |

Both `D11-hw07-approved-preflight` and
`D11-hw07-B-only-delayed-OK-01` passed. The actual native child exited 69 for
the planned task response timeout; the assertion wrapper exited 0 because local
acceptance, waiting-stage timeout and cleanup met the case contract. Exit 69
was not hidden or relabeled as a successful round trip.

| UTC observation | Fact |
| --- | --- |
| 20:28:01.514817 | One SEND_CHANNEL_DATA written to the selected TCP connection |
| 20:28:05.680702 | Actual complete standard OK parsed; local write had already completed |
| 20:28:20.683027 | Client requested normal close at the response deadline |
| 20:28:20.683109 | Owned receive stream EOF observed |
| 20:28:20.702963 | Actual native child reaped after exit 69 |

The monotonic send-to-OK interval is **4165858 microseconds**. OK-to-close-request
is **15002226 microseconds**. The task retained the full post-acceptance response
window instead of spending it on the send wait. This interval is local command
confirmation timing, not application RTT or pure airtime.

Terminal public facts are `responseTimeout / waiting`, attempted/dispatched/
localWriteCompleted/localOkObserved/deviceAcceptanceConfirmed all true, and
pendingAtTermination false. There was no matching PONG, exact content success,
round-trip success or application RTT. This is the intended task failure and a
PASS for this case's expected-result assertions.

The trace proves one Socket receive subscription, one SEND, one OK and 76
GET_MSG commands. Exactly 75 ordinary-message summaries were consumed and
processed, then an empty response; these were real shared-inbox consumption,
not a test-channel-only peek. Ordinary message bodies were discarded by the
existing codec. Trace data retains opcode/length/chunk information and public
OK bytes only, not raw messages, keys or private endpoint strings. All 5088
received bytes account for complete frames, with no partial OK left over.

Cleanup succeeded. The runner sent no termination signal and recorded native
child reap plus natural process-tree exit. Independent OS checks found both
owned PIDs absent and no selected USB owner. No database consumer was opened;
the previous closed GUI fixture and complete app/CLI inventories remain at their
original source cuts. No new app/runtime/XCTest/physical-cycle pass is inferred.

## Limits and accounting

The observed OK arrived before the old 15-second command limit. Consequently
this one real run validates the explicit policy, acceptance, post-OK timer and
normal cleanup, **not real tolerance of an OK arriving after that old limit**.
The 19.1-second OK / 33.1-second exact-PONG path retains its software-test scope.
The older real missing-OK failure and server deferral evidence remain separate.
No repeated RF was added to obtain a slow response, and no remote load or
configuration was changed to manufacture one.

This case adds one application-send attempt, 75 consumed entries and 76 reads:
cumulative **8 attempts**, **357 B entries / 364 B reads**, with no cumulative
send ceiling. Attempts are not an airtime, firmware-retry or Fabric-forward count.
The approved first case is complete; no further B or A session was started.
Current GUI exact PONG and physical unplug/replug remain unestablished. 1D.11
and final beta acceptance remain incomplete.
