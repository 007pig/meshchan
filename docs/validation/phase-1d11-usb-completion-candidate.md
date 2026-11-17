# USB completion-query compatibility candidate

Status: **bounded hardware feasibility PASS; mitigation effectiveness not yet
established**. The separately authorized standard/probe/probe/standard comparison
completed on November 16, 2026: both probe cases and both standard cases passed.
This solution prototype responds to the operator's consecutive-request proposal.
That comparison used the source-only diagnostic. The operator later explicitly
requested app integration before further hardware tests; build 4's separate
integration and GUI evidence are recorded in the
[beta validation record](phase-1d11-hardware-beta.md). The four diagnostic
successes do not establish a repaired GUI. Beta acceptance remains incomplete.

## Fixed bounded sequence

The source-only native diagnostic accepts an explicit final
`--completion-probe` flag. Without it the original sequence remains unchanged.

| Mode | Exact initialization control frames | Maximum framed bytes |
| --- | --- | --- |
| Standard | DEVICE_QUERY, APP_START | 24 |
| Completion probe | DEVICE_QUERY, DEVICE_QUERY, APP_START, DEVICE_QUERY | 34 |

All queries use the same target 3. APP_START is sent once with the same Meshchan
name/reserved bytes. No other command is allowed: no GET_MSG, radio application
send, reset, channel/firmware change or reconnect. The native byte guard enforces
the selected plan before I/O. Each underlying write retains its two-second
budget. The owning session's request/init deadlines remain **15/30 seconds**,
startup delay zero; neither duplicates nor progress renew them.

The extra queries solicit subsequent device output, following the observed
[delayed-body delivery with later data](phase-1d11-usb-posix-controls.md#delayed-delivery-without-any-extra-host-command).
This is a possible finite compatibility mechanism, not proof that every held
transfer will complete or an attempt to label a late response as success.

## Complete the probe as well as the original reply

`InitializationCompletionProbe` uses the public CompanionTransport/session
APIs and one mapped receive stream, with no second reader or private session
getter. The first send waits for two complete DEVICE_INFO replies; the second
waits for the extra query's complete DEVICE_INFO. The original session still
requires its original matching DEVICE_INFO/SELF_INFO before reaching ready.
Thus an incomplete final probe reply cannot be hidden behind an otherwise
complete SELF_INFO. Closure settles a pending probe and prevents later writes.

Duplicate DEVICE_INFO never satisfies SELF_INFO. Public protocol errors and
device errors still reach the owning session; the candidate does not suppress
or relax them. It refuses further/overlapping commands and cannot become a
general send/listen transport. No new timer or unlimited retry loop exists.

These checks matter because simply obtaining the first response and abandoning
a second partial response can leave the serial decoder waiting for that tail.
The candidate deliberately remains a failure if the extra reply also stalls.

## Executed software checks

The initial source candidate passed analysis, 195 link tests and native build.
The final stricter candidate also waits for its extra replies and passed
analysis, the complete **196-test** link suite and a separate complete native
bundle build. Seven candidate tests cover:

- Standard behavior still failing for a simulated held response.
- Completion of both simulated held replies with exactly four frames/34 bytes.
- Failure retained when more queries do not release the body.
- Wrong-type duplicates not establishing ready or renewing a deadline.
- Post-initialization commands refused before inner writes.
- Close during a pending write preventing a subsequent probe write.
- Complete original SELF_INFO not hiding an incomplete final probe reply.

The held-device cases are explicit software mechanism models, not hardware
evidence. Built-entry help and missing-execute/duplicate-flag rejection passed
without any device access. The product libraries, public exports, app/CLI
arguments, dependencies, firmware and delivered beta binaries are unchanged.
Original native and ten-attempt POSIX source/bundle cuts remain preserved.

## Prepared hardware check and subsequent authorization

When this candidate was prepared, the prior ten-attempt allowance was exhausted
and no candidate hardware action had occurred. The proposal was four additional A-only initializations
in fixed order **standard, probe, probe, standard**, using the same new complete
candidate bundle, unchanged explicit selected port and 15/30/0 budgets, B closed,
zero application sends/inbox reads and no firmware change. Each case runs once.
Known initialization failure may continue only after zero-send/read, known write
and actual cleanup/OS release verification; any uncertain write/owner/cleanup
stops the sequence. Maximum **12 control frames / 116 serial bytes** across four
cases, excluding partial-write API calls, and no retry inside a case.

The operator subsequently explicitly authorized exactly these four cases, in
this order, with the selected USB A, B closed, unchanged budgets and stop rules.
That new authorization was recorded independently of the exhausted ten-attempt
cohort. Product integration still requires the
affected regression/build checks and a newly bound complete Release/CLI before
claiming the GUI problem repaired. No source-only success substitutes for U02.

Owned candidate bundle, inventories, exact proposed argv, software receipts and
scope are under
`/private/tmp/meshchan-1d11-20261116-01/hardware/usb-init-completion-candidate-01/`.
The final bundle is `build-final/bundle/`. Its help describes both bounded modes.

## Executed four-case comparison

All four cases used the same complete native diagnostic bundle. Its executable
SHA-256 is
`a2397fa38e7326dcef5d78b7af9ba13f0811820510d2cd3fef29d76b719bf77a`;
the complete bundle inventory SHA-256 is
`26bb29e9bf79fe1718d67a720ac1aec0bfd31f4d999515d0c9caa036007f12fd`.
The source cut is the final 196-test candidate, on actual PR #37 merge
`0fd49a3495d972c88dee35fc709501db78a16d16` plus the recorded dirty source.
Python was `/opt/homebrew/bin/python3` 3.15.2. No source or binary was changed
between cases. Each preflight rechecked the complete diagnostic and delivered
product inventories, source hashes, selected USB metadata and absence of other
app/source-peer clients or a port owner.

| Attempt | Mode | Start UTC, November 16 | Result | Accepted control frames / bytes | Native RX chunks, bytes | Complete DEVICE_INFO / SELF_INFO |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Standard | 15:14:18.992107 | PASS | 2 / 24 | 341, 67 | 1 / 1 |
| 2 | Completion probe | 15:14:22.597094 | PASS | 4 / 34 | 170, 152 | 3 / 1 |
| 3 | Completion probe | 15:14:25.415823 | PASS | 4 / 34 | 170, 152 | 3 / 1 |
| 4 | Standard | 15:14:28.006816 | PASS | 2 / 24 | 85, 67 | 1 / 1 |

Both probe cases received two complete 85-byte framed DEVICE_INFO responses in
the first 170-byte native read, then complete 67-byte SELF_INFO and 85-byte
DEVICE_INFO frames in the 152-byte read. All original and extra replies were
complete before ready, and the final parser projection was complete in every
case. Native read chunks are not USB packet boundaries. This observation shows
that the bounded consecutive-query sequence can finish without leaving an
incomplete extra reply; it does not prove that a query released an otherwise
stalled transfer in these particular cases.

Every write returned its full requested byte count. The actual total was the
approved maximum **12 control frames / 116 serial bytes**, with **zero
application-send attempts, zero inbox reads and zero B sessions**. Request/init
budgets remained 15/30 seconds, startup delay zero and native write budget two
seconds. There was no retry inside a case, firmware change, flush, line toggle,
reconnect, forced process termination or additional device Check.

After each case, reader stop, port close, native disposal and session cleanup
were confirmed, followed by natural process exit/reap, OS PID absence and no
port owner. Only then did the next preflight proceed. The process IDs were
32217, 32270, 32304 and 32357. All four postconditions passed, and the cohort
stopped after the authorized fourth case at 15:14:29.340443 UTC. The four-case
allowance is exhausted; all task consumers are closed.

## Solution decision and evidence limits

The compatibility candidate passed both real-device trials and the software
held-response model. It is a usable bounded prototype for a later product
integration decision. However, the standard controls also both passed, so this
cohort did not reproduce a baseline failure or establish a comparative reduction
in intermittent timeouts. Two successful probe initializations do not establish
a reliability percentage or justify declaring the GUI defect fixed. The earlier
standard/native/POSIX failures remain unchanged and separately traceable.

At the end of this four-case comparison, the candidate remained in source
tooling. The subsequently requested app integration retains one APP_START,
finite extra queries, original
deadlines, complete extra-reply checks and the single owner/reader contract, then
rebuilds affected complete products and validates the actual GUI. This record adds
no GUI PING/PONG, Cancel, active Quit or physical unplug/replug acceptance.

Owned executed evidence is
`/private/tmp/meshchan-1d11-20261116-01/hardware/usb-init-completion-abba-01/`:
authorization, fixed case plan, pre/post verification scripts and receipts,
per-attempt trace/result/OS observations, cohort state and final evidence index.
The separate pre-hardware candidate scope and summary are preserved with their
original NOT_RUN status; they describe that earlier source/time cut.
