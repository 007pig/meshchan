# Companion session

Phase 1 / 1A / Step 6 adds callable initialization through
`package:meshcore_link/meshcore_link.dart`. `MeshCoreSession` uses only
`CompanionTransport`, the existing [Companion codecs](companion-initialization.md),
and Dart asynchronous primitives. It passes complete inner content directly to
the transport and decoder; it never adds or searches for serial framing.

Step 7 exposed initialization through the [info/watch CLI](../cli.md).
The CLI owns one fresh transport/session per invocation, sends no extra commands,
and awaits the shared cleanup result before returning.

Phase 1B.3 adds ready-state `sendChannelData()` and explicit `readNextMessage()`
through this same session. They share its single pending slot and one bounded
FIFO. Automatic reception, application PING/PONG, and new CLI commands remain
later work; existing `info/watch` still send only the initialization pair.

## API and ownership

Construct a session with an unused transport and call `connect()` once:

```dart
MeshCoreSession(
  transport: transport,
  appName: 'Meshchan',
  requestTimeout: const Duration(seconds: 5),
  initializationTimeout: const Duration(seconds: 15),
  startupDelay: Duration.zero,
  maxQueuedCommands: 8,
);
```

Construction validates the application name using `encodeAppStart`, positive
timeouts, a nonnegative startup delay, and nonnegative queue capacity. Invalid
local arguments throw `ArgumentError` or `RangeError` without I/O.
Construction, getters, and event subscriptions never open the transport.

The session exclusively owns its transport's subscription, open, send, and close
operations. The caller must not subscribe to `transport.frames`, send alongside
the session, or reuse a transport from an earlier attempt. Concurrent, repeated,
or post-close `connect()` calls return `StateError` without affecting the original
attempt. Retry requires a **new transport and new session**. There is no reconnect,
retry queue, or public generic command executor.

`connect()` returns `Future<MeshCoreSessionInfo>`. The result combines the existing
`DeviceInfoResponse` and `SelfInfoResponse`, plus `appTargetVersion`; it does not
duplicate protocol fields. `info` remains null until both steps succeed. The
successful immutable snapshot remains available after failure or close for
offline display; it is historical data then. Only `state == ready` means the
current session is usable.

## Ready commands and admission

```dart
Future<OkResponse> sendChannelData({
  required int channelIndex,
  required int dataType,
  required int routeDescriptor,
  required Uint8List path,
  required Uint8List payload,
});
Future<CompanionResponse> readNextMessage();
```

Both methods accept new work only in `ready`, without connecting implicitly.
Admission errors are delivered through the returned Future: `StateError` outside
ready, codec `ArgumentError` / `RangeError` for invalid send parameters, and
`MeshCoreSessionQueueFull` when waiting capacity is exhausted. These errors do
not fail the session, affect accepted commands, or perform transport I/O.
Constructor configuration errors still throw synchronously.

`sendChannelData()` uses `encodeSendChannelData` at admission, validating and
copying path/payload into owned inner content before asynchronous waiting. Later
caller mutations cannot alter a queued send. Its `OkResponse` proves only local
write completion and device command acceptance, not physical radio transmission,
remote delivery, application acknowledgment, or a round trip.

`readNextMessage()` sends exactly one `encodeSyncNextMessage()` command (`0x0A`)
when dispatched. Its only successful results are `ChannelDataResponse` (typed
fields and independent read-only payload), `QueuedMessageResponse` (ordinary
message kind and structural summary), or `NoMoreMessagesResponse` (empty queue).
This **consumes one shared queue entry; it is not a peek**. It can remove ordinary
chat, whose body the current codec discards. Ordinary messages and empty results
complete this read normally; neither they nor a later `0x83` cause another read.

`maxQueuedCommands` defaults to **8** and counts waiting commands only, excluding
the one active command. Zero permits a command on an idle ready session but
rejects another while it is busy. This is Meshchan's local resource policy,
unrelated to firmware inbox capacity or radio constants. Full queues reject only
the new call: no dropping, reordering, hidden waiting, or retry. Sends and reads
share strict FIFO order and one transport send at a time.

An idle admission synchronously reserves the active position, before scheduling
dispatch in a microtask. Reservation does not register a matching request or
start its timer. Input in that gap remains unassociated and cannot supply the
later command. On completion, the next waiting command is reserved before other
calls can enter, so neither FIFO nor capacity can be bypassed between microtasks.

## States and initialization policy

```text
idle -> opening -> initializing -> ready -> closing -> closed
           |             |           |
           +-------------+-----------+--> failed
```

Explicit close also works in idle, opening, and initializing. It enters closing
and, after successful cleanup, closed. An active terminal fault immediately enters
failed and starts cleanup. A cleanup fault also enters failed if there was no
earlier fault. A failed session stays failed after cleanup, preserving its reason.
**Failed does not mean native resources have been released.**

Initialization proceeds in this fixed order:

1. Subscribe once to the transport's single-subscription stream with error and
   done handlers. This subscription remains active and unpaused during cleanup.
2. Start the total initialization timer and call `transport.open()`.
3. Enter initializing after open succeeds. Wait for `startupDelay` if configured,
   continuing to consume input and allowing cancellation. Its default is zero;
   a tester can explicitly choose one second for a particular board's startup.
4. Send DEVICE_QUERY (`16 03`) and wait for DEVICE_INFO (`0D`).
5. After both that send and its response succeed, send APP_START (`01`, seven
   reserved zero bytes, then the application name) and wait for SELF_INFO (`05`).
6. After both sends and both parsed responses succeed with no terminal reason,
   publish the complete info, enter ready, and complete `connect()`.

`meshCoreSessionAppTargetVersion` is **3**, a named Meshchan policy based on the
Step 5 single-device probe. It is not configurable in this session API and is not
a claim of full protocol-3 support. The lower-level `encodeDeviceQuery` remains
parameterized. A device reporting protocol code 14 still receives target 3;
`deviceInfo.protocolVersion` retains 14 without implying full protocol-14 support.
`firmwareVersion` is separate display text, unrelated to either protocol code or
the Meshchan application version. Parsing follows the existing version/length
gates and fixed wire baseline, without guessed older layouts.

This order is the selected Meshchan policy, not a universal requirement for all
clients or firmware. DEVICE_QUERY changes the device's application-target state;
APP_START affects its connection initialization state. They have device-side
effects. Ready means only that these two commands' local sends and corresponding
parsed response types completed under this policy. It proves neither identity
authentication, wireless reachability, LoRa TX/RX, nor all firmware functionality.
Initialization performs no flush, reset, DTR/RTS toggle, contact/channel polling,
clock setting, message synchronization, or automatic response to a `0x83` push.

## Matching and failures

There is one private pending slot. It records a local token, command and expected
response codes, the first matching response, send completion, and one timer. The
slot and timer are registered **before** calling `sendFrame()`. A response arriving
inside the send call or before its Future completes is retained. It cannot advance
the sequence until the send succeeds. Later matching duplicates cannot replace the
first response. A subsequent send failure still terminates the session.

All reception uses the same long-lived subscription and the real decoder:

| Input | Action |
| --- | --- |
| Pending expected response type | Retain the first result; require successful send too. |
| Device error while pending | Fail as deviceRejected with raw error code and known name if available; no retry. |
| Device error without pending | Publish an unassociated structural event. |
| `0x83`, unknown or unimplemented opcode | Publish a structural event; do not complete or extend the request. |
| Valid wrong-type or duplicate response | Publish an unassociated summary; never cache it for another request. |
| `CompanionProtocolException` | Fail as protocol, retaining the original exception and stack. |
| Stream/open/send error | Fail as transport, retaining the original cause and stack. |
| Unexpected active stream done | Fail as disconnected immediately. |
| Callback after closing, closed, or failed | Discard content without parsing or advancement; observe asynchronous errors. |

Initialization still accepts only DEVICE_INFO for DEVICE_QUERY and SELF_INFO
for APP_START. OK cannot complete either initialization step. Ready commands use:

| Valid response | Pending send `0x3E` | Pending read `0x0A` | No dispatched request |
| --- | --- | --- | --- |
| `OkResponse` | Retain first result. | Structural summary; keep waiting. | Structural summary. |
| `ChannelDataResponse`, `QueuedMessageResponse`, `NoMoreMessagesResponse` | Structural summary; keep waiting. | Retain first result, including ordinary chat or empty queue. | Structural summary. |
| `MessageWaitingResponse` (`0x83`) | Structural summary only. | Structural summary only. | Structural summary only. |
| `DeviceErrorResponse` | Terminate as deviceRejected. | Terminate as deviceRejected. | Structural error summary. |
| Other valid type or duplicate | Structural summary. | Structural summary. | Structural summary. |

Every retained success also requires local write completion. ERROR still
terminates a command whose result arrived while its write remains pending.
`readNextMessage` has multiple permitted response types, so its session failure's
`expectedResponseOpcode` is null, while `commandOpcode` remains `0x0A`.
Unassociated datagrams are structural events without typed payload delivery;
there is no raw response stream or response pool. `0x83` never sets a drain flag
or schedules work. Explicit typed automatic reception belongs to 1B.4.

A ready command commits success by completing its internal Future before
releasing pending state and reserving its successor. Dispatch of the successor
runs outside the receive callback, with state, token, and reservation rechecked.
Close in that gap cannot change committed success; it promptly terminates the
reserved successor and all waiting commands. No accepted completion is deferred
without an owned record that cancellation can still terminate.

SELF_INFO arriving before APP_START never supplies that later step. Repeated
startup responses after ready do not replace the published snapshot. The first
terminal reason wins, including when a single `SerialTransportFailure` is reported
by both the stream and a send Future. `lastFailure` preserves it. Failures use
`MeshCoreSessionFailureKind`: transport, protocol, deviceRejected, requestTimeout,
initializationTimeout, disconnected, canceled, and cleanup. Necessary stage,
command/expected response codes, raw device error, cause, and stack are available.

Accepted ready commands fail with `MeshCoreSessionCommandFailure`. Its immutable
`commandOpcode` describes that command (`0x3E` send or `0x0A` read), alongside
three facts frozen at termination: `dispatched` means `sendFrame()` was called,
`localWriteCompleted` means its success was observed, and
`matchingResponseObserved` means its first allowed response was saved. An active
reservation alone has all three facts false. Waiting commands terminated by an
earlier failure also have all three false, even if the root failure describes
another command's device rejection or timeout. `sessionFailure` references that
shared root with its actual stage/command, raw device error, original cause and
stack. Cleanup failures remain separately available in `cleanupFailures`.

A false write-completion fact does not prove that no bytes reached the device.
An early matching response followed by write failure remains an observed response
with a failed command. Termination cannot retract a device-accepted radio send.
Default command/admission exception text contains only structural metadata and
does not format raw causes or retain path, payload, or chat bodies.

The protocol supplies **no end-to-end request ID** for these responses. Local
tokens invalidate old timers and continuations; they are not device-returned
correlation IDs. Exclusive control, no retry, and no response pool reduce
ambiguity, but a same-type frame left in firmware or driver buffers cannot be
absolutely associated using type alone. The session adds no wire fields or nonce.

## Deadlines, cancellation, and cleanup

The default request budget is **5 seconds**, from pending registration until both
send and response succeed. The default total budget is **15 seconds**, beginning
in `connect()` before open and covering open, startup delay, and both requests.
The earlier deadline wins. Neither budget restarts for write completion, unrelated
frames, duplicate responses, or partial progress. These are client defaults, not
MeshCore constants; the transport's separate native write budget is unchanged.

Each ready command uses that same 5-second default budget, starting only at
actual pending/timer registration immediately before `sendFrame()`. Queue wait
does not consume it. An early result with an unfinished write still times out.
**A device-command timeout terminates the entire session** and all accepted work;
it never frees the slot to send another command. Task-wide and remote-response
deadlines and application RTT are not implemented here. Future task callers must
include queue waiting in their total budget and close the session to stop work.

On fault or cancellation, the session invalidates pending work and cancels all
session timers immediately. It completes an unfinished `connect()` and every
accepted, uncommitted ready command **before awaiting cleanup**. Explicit close
during opening or initializing completes it as canceled; cancellation itself does
not set `lastFailure`. Ready commands canceled by close reference a canceled session
failure without creating a new primary fault. Late open/send success or error
cannot send another command or restore ready. Every started asynchronous operation
has an error observer.

Software deadlines do not cancel native I/O: a synchronous native call blocking
the Dart event loop cannot be preempted by a Timer. A pending native open or reader
stop can keep transport close pending. No guessed sleep, forced free, or shutdown
timeout converts that into successful resource release. See the unchanged
[transport shutdown limitations](serial-transport.md#reader-ownership-and-shutdown-evidence).

`close()` in every state shares one Future and invokes `transport.close()` once.
The session first stops logical work, then awaits transport cleanup while keeping
its receive subscription alive and unpaused. Only after transport close settles,
successfully or with an error, does it cancel that subscription and close its own
notification controller. A failure in one cleanup step does not skip the next safe
step. `close()` reports actual cleanup failure, even after a primary fault. If
cleanup succeeds, it does not rethrow the earlier operation fault.

`cleanupFailures` retains classified cleanup details without replacing a prior
`lastFailure`. If close is the first fault, cleanup becomes `lastFailure`. Automatic
cleanup observes its own failing Future; explicit `close()` still returns the
same result. Logical failure and resource release are deliberately separate:
`connect()` or a command may already have failed while `close()` remains pending
indefinitely. A successful command does not establish successful cleanup.

## Events and privacy

`events` is a separate, asynchronous broadcast stream of data events:
`MeshCoreSessionStateChanged`, `MeshCoreSessionUnassociatedResponse`, and
`MeshCoreSessionFailed`. No observer is required to connect. Canceling or pausing
an observer cannot cancel or pause the internal receive subscription. No history
is cached without listeners, and the session maintains no frame history. Dart
buffers events for each paused observer; cancel observers that are no longer
needed. This is not a globally bounded buffer for paused subscribers.

Closing the notification controller is observed but its completion does not hold
resource cleanup hostage to paused observers. Faults are data events and getters,
not unhandled stream error events. Asynchronous delivery avoids synchronous user
callbacks reentering the protocol state transitions.

Default `toString()` diagnostics contain only structural fields: codes, lengths,
states, failure kinds, application target, and reported protocol code. They omit
device names, model/firmware text, keys, PIN, positions, payload bytes, and recursive
cause formatting. Unknown responses retain only a summary. `info` intentionally
contains the existing parsed data for explicit caller use; `cause` and `stackTrace`
also remain available for explicit debugging and should not be blindly logged.

## Minimal call example

This function accepts an already selected, unused transport; it does not choose
or hard-code a port. Merely reading this example runs nothing. It demonstrates a
complete short session, one explicit send, and one consuming read, returning that
read result after explicit close. All channel and route inputs come from the caller.
The optional observer prints only safe structural summaries.

```dart
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

Future<CompanionResponse> sendAndReadOnce({
  required CompanionTransport transport,
  required int channelIndex,
  required int dataType,
  required int routeDescriptor,
  required Uint8List path,
  required Uint8List payload,
}) async {
  final session = MeshCoreSession(transport: transport);
  final observer = session.events.listen((event) => print(event));
  var operationFailed = false;
  try {
    await session.connect();
    await session.sendChannelData(
      channelIndex: channelIndex,
      dataType: dataType,
      routeDescriptor: routeDescriptor,
      path: path,
      payload: payload,
    );
    // This can consume ordinary chat and does not wait for an application reply.
    return await session.readNextMessage();
  } catch (_) {
    operationFailed = true;
    rethrow; // Preserve the original operation exception and stack.
  } finally {
    try {
      await session.close(); // May remain pending for native exit confirmation.
    } catch (_) {
      if (!operationFailed) rethrow;
      // The operation remains primary; cleanup details are still inspectable.
      print('Cleanup also failed; inspect session.cleanupFailures.');
    } finally {
      await observer.cancel();
    }
  }
}
```

The example awaits cleanup before returning or rethrowing. Applications that need
to display logical failure immediately can observe `connect()` separately from
their awaited cleanup workflow. Initial software acceptance used no hardware.
A subsequent [authorized Step 6 follow-up](../hardware-validation.md#authorized-session-hardware-follow-up-on-november-9-2026)
passed real source and AOT sessions with `startupDelay: const Duration(seconds: 3)`
on one selected macOS port, after zero- and one-second attempts timed out. This
is a tested caller setting for those runs, not proof of a universal startup
requirement or the sole cause of the earlier failures. The product default stays
zero. A later [timeout investigation](../hardware-validation.md#session-timeout-investigation-on-november-9-2026)
reproduced delayed delivery of a 64-byte response body outside Dart; zero- and
one-second sessions also passed. Increasing startup delay is not an established
fix. There is no automatic extra query, retry, flush, or device-name change to
force delivery. The Step 5 temporary probe remains a separate historical result.

## Software verification and references

Run `dart test test/meshcore_session_test.dart` from `packages/meshcore_link`.
The 16 focused behavior groups use a small synchronous fake transport, synthetic
content decoded by the real codec, and pub-resolved `fake_async` 1.3.3 for timers
and microtasks. They never enumerate or open hardware. See the dated
[Step 6 development record](../development.md#companion-session-step-6) for actual
full-suite and build results. At Step 6, existing CLI/example builds could
tree-shake the session away and were regressions of those products, not session
AOT execution or hardware validation. Step 7's product CLI now includes the
session; its builds and hardware-free checks are recorded in the
[Step 7 development record](../development.md#diagnostic-session-cli-step-7).
The later temporary Step 6 hardware harness
explicitly called this session and separately passed AOT execution on hardware;
it added no product CLI or change to the read-only example.

### 1B.3 software verification on November 10, 2026

The new `test/meshcore_session_commands_test.dart` adds 16 focused behavior
groups using the same synchronous fake, real codec, controlled Completers, and
virtual time. Minimal initialization fixtures and immediate Future observers
are shared through `test/support/session_test_support.dart`; the original 16
initialization groups retain their assertions. New coverage includes admission,
mixed FIFO/capacity, byte ownership, both write/response orders, single reads,
duplicates, dispatch deadlines, cancellation windows, frozen failure facts,
pending/failed cleanup, late errors, and privacy.

Checks used `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart` 3.13.7 on
macOS arm64, with Apple tools preferred in the process PATH. Installed SDK
metadata reports Flutter 3.47.9 stable; the Flutter wrapper was not invoked.

| Check | Actual result |
| --- | --- |
| `dart pub get --enforce-lockfile` | Passed; dependencies and root lockfile unchanged. |
| Format, then format check of the five changed Dart files | Passed; final check made zero changes. |
| `dart analyze --fatal-infos` | Passed; no issues. |
| `dart test test/meshcore_session_test.dart test/meshcore_session_commands_test.dart` | Passed; 32 tests. |
| Complete core suite, then complete CLI suite | Passed sequentially; 93 and 27 tests. |
| Existing CLI and observation `dart build cli` commands | Passed once each, sequentially, in fresh temporary output. |
| Existing `python3 tool/smoke_cli.py` | Passed once; all 46 macOS process checks, both native asset checks, and bundle relocation. Linux refusal checks were not applicable. |
| Patch/new-file hygiene and dependency/version/CI diff checks | Passed; UTF-8 without BOM, LF, final newlines, and no trailing whitespace. |

The initial focused run exposed two test-owned unused Completers being completed
with errors; the initial analysis found an unused import and missing braces.
Those were corrected before the passing checks. An initial format invocation
used root-relative paths from the package directory and found no files; formatting
and its final check subsequently ran from the root with the correct paths.
There were no retries around unresolved product failures. Builds/smoke validate
existing products, not ready-command AOT execution or hardware behavior. No real
port enumeration/access, LoRa operation, or remote CI run was performed. The
application remains `0.1.0-dev.1`.

The Dart asynchronous semantics were rechecked against the actual SDK and these
primary references on November 9, 2026:

- [Future.timeout](https://api.dart.dev/dart-async/Future/timeout.html): a timed-out
  source Future can still complete; this session explicitly invalidates its work.
- [StreamController.close](https://api.dart.dev/dart-async/StreamController/close.html):
  paused listeners can delay completion.
- [StreamController.broadcast](https://api.dart.dev/dart-async/StreamController/StreamController.broadcast.html):
  listener independence, no listener-free history, and per-paused-listener buffering.
- [fake_async](https://pub.dev/packages/fake_async): virtual Timer/microtask tests;
  ordinary Stopwatch and DateTime.now are not controlled. No new clock or scheduler
  is added to production code, and the transport's monotonic clock is unchanged.
