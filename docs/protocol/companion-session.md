# Companion session

Phase 1 / 1A / Step 6 adds callable initialization through
`package:meshcore_link/meshcore_link.dart`. `MeshCoreSession` uses only
`CompanionTransport`, the existing [Companion codecs](companion-initialization.md),
and Dart asynchronous primitives. It passes complete inner content directly to
the transport and decoder; it never adds or searches for serial framing.

Step 7 exposes this unchanged session through the [info/watch CLI](../cli.md).
The CLI owns one fresh transport/session per invocation, sends no extra commands,
and awaits the shared cleanup result before returning.

## API and ownership

Construct a session with an unused transport and call `connect()` once:

```dart
MeshCoreSession(
  transport: transport,
  appName: 'Meshchan',
  requestTimeout: const Duration(seconds: 5),
  initializationTimeout: const Duration(seconds: 15),
  startupDelay: Duration.zero,
);
```

Construction validates the application name using `encodeAppStart`, positive
timeouts, and a nonnegative startup delay. Invalid local arguments throw
`ArgumentError` or `RangeError` without I/O. Construction, getters, and event
subscriptions never open the transport.

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
There is no flush, reset, DTR/RTS toggle, contact/channel polling, clock setting,
message synchronization, or automatic response to a `0x83` push.

## Matching and failures

There is one private pending slot. It records a local token, command and expected
response codes, the first matching response, send completion, and one timer. The
slot and timer are registered **before** calling `sendFrame()`. A response arriving
inside the send call or before its Future completes is retained. It cannot advance
the sequence until the send succeeds. Later matching duplicates cannot replace the
first response. A subsequent send failure still terminates initialization.

All reception uses the same long-lived subscription and the real decoder:

| Input | Action |
| --- | --- |
| Pending expected response type | Retain the first result; require successful send too. |
| Device error while pending | Fail as deviceRejected with raw error code and known name if available; no retry. |
| Device error without pending | Publish an unassociated structural event. |
| OK, `0x83`, unknown or unimplemented opcode | Publish a structural event; do not complete or extend the request. |
| Valid wrong-type or duplicate response | Publish an unassociated summary; never cache it for another request. |
| `CompanionProtocolException` | Fail as protocol, retaining the original exception and stack. |
| Stream/open/send error | Fail as transport, retaining the original cause and stack. |
| Unexpected active stream done | Fail as disconnected immediately. |
| Callback after closing, closed, or failed | Discard content without parsing or advancement; observe asynchronous errors. |

SELF_INFO arriving before APP_START never supplies that later step. Repeated
startup responses after ready do not replace the published snapshot. The first
terminal reason wins, including when a single `SerialTransportFailure` is reported
by both the stream and a send Future. `lastFailure` preserves it. Failures use
`MeshCoreSessionFailureKind`: transport, protocol, deviceRejected, requestTimeout,
initializationTimeout, disconnected, canceled, and cleanup. Necessary stage,
command/expected response codes, raw device error, cause, and stack are available.

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

On fault or cancellation, the session invalidates pending work and cancels all
session timers immediately. It completes an unfinished `connect()` with a
classified failure **before awaiting cleanup**. Explicit close during opening or
initializing completes it as canceled; cancellation itself does not set
`lastFailure`. Late open/send success or error cannot send another command or
restore ready. Every started asynchronous operation has an error observer.

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
cleanup succeeds, it does not rethrow the earlier initialization fault.

`cleanupFailures` retains classified cleanup details without replacing a prior
`lastFailure`. If close is the first fault, cleanup becomes `lastFailure`. Automatic
cleanup observes its own failing Future; explicit `close()` still returns the
same result. Logical failure and resource release are deliberately separate:
`connect()` may already have failed while `close()` remains pending indefinitely.

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
complete short session and returns a historical snapshot after explicit close.
The optional observer prints only safe structural summaries.

```dart
import 'package:meshcore_link/meshcore_link.dart';

Future<MeshCoreSessionInfo> initializeAndClose(
  CompanionTransport transport,
) async {
  final session = MeshCoreSession(transport: transport);
  final observer = session.events.listen((event) => print(event));
  var operationFailed = false;
  try {
    final info = await session.connect();
    print('App target: ${info.appTargetVersion}; '
        'reported protocol code: ${info.deviceInfo.protocolVersion}.');
    return info;
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
