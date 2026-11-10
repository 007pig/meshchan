# Finite diagnostic tasks (1B.6)

The public `meshcore_link.dart` API exports `DiagnosticTaskOptions`,
`MeshchanPingTask`, `MeshchanResponderTask`, and immutable diagnostic result,
reason, stage, send-fact, failure, and cleanup types. The
[diagnostic v1 contract](channel-datagrams.md#meshchan-diagnostic-pingpong-v1)
remains unchanged. These are pure Dart operations through the existing session,
FIFO, and `MeshCoreReception`; there is no extra transport listener, raw-response
stream, direct read loop, command retraction API, or CLI command.

## Configuration and ownership

Both task constructors require `session` and `options`. Options require explicit
`sendChannelIndex` and `receiveChannelIndex` (independently validated uint8 local
slots), distinct nonzero uint32 `localTestId` / `peerTestId`, `routeDescriptor`,
`path`, and positive `taskTimeout`. `maxEntries` defaults to 128 and
`maxReadsPerBatch` to 8; both must be positive. The existing route helper validates
the path and send capacity. No radio route or peer is inferred from receive data.
Path and PING content are copied into read-only storage at construction.

PING additionally requires `content` and positive `responseTimeout`; responder
requires positive `listenDuration`, with positive `maxResponses` defaulting to 1.
There is no production default for any application time budget. The overall
budget may be shorter than any other budget. Existing initialization (15 s),
device command (5 s), handshake order, and target 3 stay unchanged.

Each task needs its own **fresh idle session and unused transport**, with at
least one waiting FIFO slot (`maxQueuedCommands >= 1`). Construction and getters
do not connect, generate a nonce, subscribe, or start a timer. On first `start()`,
configuration validation and ownership claim run synchronously before connection.
A task-local claim also excludes a second task during reentrant nonce creation.
After acceptance the task exclusively owns connect/send/reception/close. Callers
must not operate the session, reuse its transport, or share it with another task.

Each handle exposes:

```dart
Future<void> start();
Future<DiagnosticPingResult> get done; // DiagnosticResponderResult for responder.
Future<DiagnosticPingResult> cancel(); // DiagnosticResponderResult for responder.
Future<DiagnosticCleanupResult> get cleanupDone;
DiagnosticCleanupState get cleanupState;
```

`start()` means acceptance, not ready or completion. First local rejection returns
`DiagnosticTaskStartError`, commits `startRejected`, and sets cleanup to
`notRequired`, without claiming/closing the session. The error object is also the
result's failure cause. Repeated start returns a local error without changing the
original result. Cancel is idempotent and returns the same `done` Future. Cancel
before start consumes the handle without a nonce or session ownership. Expected
accepted failures/cancellation are result values. Observe the start Future even
though its error is also internally observed to avoid detached errors.

## Observation, time, and settlement

Each accepted PING generates exactly one independently owned 16-byte nonce using
`Random.secure()` and bytewise `nextInt(256)`, with request ID 1. Randomness failure
or an invalid injected nonce ends as `nonceGenerationFailed` before open/send and
closes the claimed session. There is no fallback, resend, or retained prior run.
Retry requires another task, session, transport, and nonce. `nonceFactory` is a
small testing seam; production callers should omit it.

The production elapsed source is a Stopwatch started at accepted start. Tests
can inject `elapsed: () => fakeAsync.elapsed`; its value at start becomes the
origin. Timer and elapsed must share a monotonic domain. A virtual Timer with a
real Stopwatch is not a valid timing test. No wall clock is used for budgets,
cache expiry, or RTT.

Positive timer delays, including task-owned reception, are rounded up to whole
milliseconds before scheduling so VM truncation cannot discard a fractional
deadline's only wakeup or stop listening early. The absolute elapsed deadlines
keep their original precision: rounding a wakeup does not extend admission or
PONG acceptance. Timer delivery still depends on event-loop scheduling.

| Budget | Origin and end |
| --- | --- |
| Existing initialization / device command | Unchanged session registration and settlement rules. |
| Whole task | Accepted start, before nonce/connect, through logical commitment; excludes native cleanup. |
| PING remote response | Active matcher and elapsed origin immediately before high-level `sendChannelData()`, until first exact PONG. |
| Responder listen | Ready and enabling reception, through admission stop; one previously accepted PONG may settle afterward. |
| Cache TTL | First atomic request acceptance, two minutes, without refresh. |

Callbacks check absolute elapsed deadlines as well as timers. At a deadline or
later, new corresponding observations/admissions are rejected. Earlier applicable
upper-layer deadlines win; equal deadlines favor the overall budget. Input,
OK/write completion, and duplicates never extend budgets. Timers cannot preempt
a blocking native call or guarantee native cleanup duration.

PING listens before reception activation and activates its correlation context
before one send. Its entries listener is unpaused and synchronous. Only the
existing exact matcher can freeze `firstMatchingPongElapsed`; other channels,
peers, nonces, content, application data, and chat cannot satisfy it. The first
valid observation **retires the remote-response timer**. If local send is still
pending, the task waits; local success after the former remote deadline can
still succeed under the overall and device-command budgets. Duplicates cannot
replace the first elapsed value. Send failure retains the observation, but gives
no success RTT. Successful commitment also checks current session state and
`lastFailure`, covering failure events not yet delivered on the async stream.

`applicationRtt` exists only when `roundTripSucceeded` is true and equals the
first matching elapsed value. It includes FIFO waiting, host scheduling, reads,
device processing, and radio work from the high-level send call. It is not a
serial-dispatch or airtime metric. `matchingPongObserved` and
`exactContentValidated` remain available after a later failure.

`reception.done` can precede delivery of the final published entry. A PING
entry-limit outcome waits for both that result and entries `onDone`, preserving
the last eligible PONG. A matching final entry can still await send settlement.
Without a match the result is `entryLimit`, not remote timeout. Failure,
cancellation, and expired budgets close observation immediately without draining.

## Finite responder and deduplication

The responder uses one synchronous entries listener. A targeted PING passes
`createDiagnosticPong()` and a separate return-route capacity check. Oversize
return content increments `returnCapacityRejections`; it is not truncated or
rerouted. PONGs and non-target messages do not trigger replies.

Before asynchronous sending, it reserves the value key/content and one attempt,
pauses the entries subscription, and calls the existing send API once. At most
one PONG is unsettled, including a PONG waiting behind the current automatic read.
That read retains its matching/deadline. Queue admission errors terminate the
task; there is no polling or second request/response queue. Reception's hard
`maxEntries` bounds all published buffering during pause. After settlement,
resume requires a zero-duration Timer event turn. Unrelated entries also yield
after eight processed entries. One resume scheduler owns this barrier; pending
send/yield, cancellation, and expired budgets cannot be bypassed by notifications.

The internal cache implements the frozen **128 records / two minutes** policy.
Keys own values for receive channel, nonce bytes, request ID, sender, and target;
nonce equality/hash are by value. Content is separately copied. Same key/content
increments `duplicates`; same key/different content increments `conflicts`.
Neither replaces the record, refreshes TTL, nor sends again. Lazy cleanup removes
only expired **settled** records. Pending records survive TTL until settlement.
A full cache ignores unique requests and increments `cacheCapacityRejections`;
it does not evict live records. Failed sends terminate the task without retry.
Records are cleared at termination. This is neither authentication nor persistent
replay protection beyond the task/window.

`listenStopReason` and final `reason` are separate:

- `responseLimit`: the last permitted attempt is accepted before stopping new
  reception/admission; it must settle before normal completion. Attempts, not
  successful replies, consume the limit.
- `durationElapsed`: stop new admission, including buffered PINGs, while allowing
  one already reserved and submitted PONG to settle, even if still queued.
- `entryLimit`: drain the finite published entries under the same pause/yield
  rules while deadlines and attempt budget allow; do not create a new receiver.

Normal settlement waits for `reception.done` and checks its read/session failure,
even if entries `onDone` arrived earlier. Entry limit also requires entries done
unless another admission budget has closed. Duration/response limit need not
drain unaccepted entries. Session/read/send failure, overall timeout, or cancel
while settling produces a failed/canceled final result while retaining the listen
stop reason. Check current ready state/last failure before normal commitment.
`publishedEntries` and `processedEntries` are separate; discarded buffers need
not be counted as processed. `responseAttempts` and `localResponsesConfirmed`
are separate, and the latter never proves remote PONG receipt. Normal completion
with zero responses is not a wireless round trip.

## Results and actual cleanup

`DiagnosticSendFacts` describes the PING send or the responder's **last** send;
aggregate responder counts remain bounded scalar counters. `attempted`,
`pendingAtTermination`, nullable `dispatched` / `localWriteCompleted` /
`localOkObserved`, and `deviceAcceptanceConfirmed` distinguish unattempted,
unconfirmed, and failed work. Success confirms write plus OK. Failure reuses
`MeshCoreSessionCommandFailure` frozen facts. Its `matchingResponseObserved`
means local OK, not PONG. An OK followed by write failure is not confirmed
acceptance. A queued send terminated by read failure retains undispatched send
facts and the separate read root failure. A local command success remains a fact
even if its task fails before the success continuation commits normal completion.

At the single terminal gate the task locks its reason/stage, stops timers and
admission, and **immediately calls `session.close()`**. It does not await
reception stop or subscription cancellation first. Close logically invalidates
connect/send/read; `done` collects their prompt logical settlement and frozen
facts, without waiting for native cleanup. Later callbacks and the task's own
automatic-read cancellation cannot change the immutable result.

`cleanupState` progresses independently from `notStarted` to `pending` and then
`succeeded` / `failed`; unclaimed handles use `notRequired`. `cleanupDone` only
settles after the actual shared close Future and both owned application
subscription cancellations finish. Native close can remain pending indefinitely.
Every safe subscription cleanup still runs after another cleanup failure.
`DiagnosticCleanupResult.failures` retains all actual cleanup failures separately
from the first primary `DiagnosticTaskFailure`. Results include session/reception
records and explicit cause/stack access; default formatting emits structural
facts only, without recursively printing causes, content, nonce, IDs, private
port metadata, raw frames, or chat. No unbounded event/payload list is kept.

## Parameterized caller and 1B.7 handoff

All options below are supplied by the caller; the example guesses no hardware,
route, channel, peer, or wireless deadline:

```dart
Future<bool> runPing({
  required MeshCoreSession freshSession,
  required DiagnosticTaskOptions options,
  required Uint8List content,
  required Duration responseTimeout,
}) async {
  final task = MeshchanPingTask(
    session: freshSession,
    options: options,
    content: content,
    responseTimeout: responseTimeout,
  );
  // A future CLI signal handler may call task.cancel(), observing its Future.
  // The caller still waits for both logical settlement and actual cleanup.
  try {
    await task.start();
  } on DiagnosticTaskStartError {
    // First rejection also has a typed done result and notRequired cleanup.
  }
  final result = await task.done;
  final cleanup = await task.cleanupDone; // May remain pending for native exit.
  return result.roundTripSucceeded &&
      cleanup.state == DiagnosticCleanupState.succeeded;
  // A CLI must additionally confirm its output/flush succeeded before success.
}
```

A responder uses the same start/done/cleanup flow with `listenDuration` and
`maxResponses`. 1B.7 must parse explicit device, local channels, route/path,
peer labels, content and budgets; create a new transport/session; connect signal
cancellation; map structural results; and await real cleanup and output. No CLI
subcommand spelling, JSON schema, or exit-code changes are introduced here.
Software validation is recorded in the
[1B.6 dated record](channel-datagrams.md#1b6-implementation-and-validation).
Historical 1B.1–1B.5 and hardware evidence retain their original scope. These
operations have not established device compatibility, repaired USB delivery,
or demonstrated a real LoRa round trip.
