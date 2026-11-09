# Serial transport

Phase 1 / 1A / Step 4 exposes `CompanionTransport` and `SerialTransport` through
`package:meshcore_link/meshcore_link.dart`, without Flutter. Both `frames` and
`sendFrame(content)` carry complete, opaque inner Companion content. The existing
[serial codec](serial-framing.md) owns all outer framing and its unchanged limits.
There is no command parsing, handshake, identity check, automatic discovery,
reconnection, retransmission, idle timeout, or radio operation.

## Connection and stream contract

Constructing, obtaining `frames`, and subscribing perform no hardware access.
Only `open()` acquires the exact supplied `portPath`; whitespace-only paths are
rejected, and nonblank paths are passed verbatim. No enumeration or fallback path
is used. Each instance permits one open attempt. Create a new instance for a
later attempt, including after failure or close. Repeated/concurrent opens fail.

`frames` is single-subscription. Subscribe with an error handler before opening;
otherwise open fails before hardware access. Cancellation or pause requests
shutdown. This conservative pause policy avoids an unbounded application history
or send queue; it does not provide general backpressure. Internal reader events
remain consumed during shutdown and are discarded. Already queued public events
may be delivered after resume; no new events are accepted after shutdown begins.
The public stream's done delivery does not hold native resources alive.

Each connection has its own decoder. Complete frames are delivered in order,
including frames preceding a terminal error in the same chunk. The decoder is
never reset to hide a protocol error. Receive buffers retain the codec's independent
ownership. Unexpected native EOF calls `finish()`: incomplete input becomes the
existing `truncatedFrame` error; clean EOF becomes `disconnected`. A native read
error remains primary, without a second truncation error. Intentional shutdown
discards pending partial input. Late callbacks are ignored.

```dart
import 'package:meshcore_link/meshcore_link.dart';

Future<void> observeSelectedPort(String explicitlySelectedPath) async {
  final CompanionTransport transport =
      SerialTransport(portPath: explicitlySelectedPath);
  final subscription = transport.frames.listen(
    (content) { /* Consume complete content without pausing. */ },
    onError: (Object error) { /* Record the terminal reason. */ },
  );
  try {
    await transport.open();
    // Local setup only: this is not a MeshCore handshake or startup query.
    await Future<void>.delayed(const Duration(seconds: 3));
  } finally {
    try {
      await transport.close();
    } finally {
      await subscription.cancel();
    }
  }
}
```

## Configuration and writes

Defaults are 115200 baud, 8 data bits, no parity, and 1 stop bit. The baud rate
matches the pinned [Companion initialization source](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/main.cpp).
`baudRate` and `writeTimeout` are the only optional settings. The default per-frame
write deadline is 2 seconds, a Meshchan local I/O policy rather than a protocol
or wireless response timeout.

The adapter sets `xonXoff: disabled`, `cts: ignore`, and `dsr: ignore` using the
resolved package's public configuration API. Binary `0x11`/`0x13` remain data.
RTS/DTR are null, which the installed `setConfig()` implements by skipping their
setters; Meshchan does not explicitly change output levels. The native backend
may reject CTS/DSR changes when inherited coupled flow control cannot be changed
without output-line changes. Such configuration errors terminate the attempt;
we do not claim all hardware flow control is disabled on every driver. Opening
and configuration can themselves reset some boards through driver behavior.
No break, flush, drain, control-line restoration, or external `stty` is used.

`sendFrame()` validates and copies content through `encodeSerialFrame()` before
its first asynchronous yield. Only one send may be in flight; concurrent sends
and invalid content fail before writing and leave a healthy connection usable.
Native `write(bytes, timeout: -1)` is nonblocking in 1.0.5 and returns the accepted
byte count. Short writes advance only by that count. Zero progress waits up to
5 ms before retrying; partial progress also yields to the event loop. A monotonic
`Stopwatch` bounds the entire frame, without renewing the deadline on progress.
There is no blocking timeout-zero write or `Future.timeout()` cancellation claim.

Write timeout, I/O error, or invalid native count terminates the connection,
because a partially accepted frame cannot safely be retried. The failing send
future and the public stream report the same `SerialTransportFailure` object
once each. A receive-side failure interrupting an in-flight send propagates that
same terminal reason through the send future after cleanup. Intentional close,
cancellation, or pause without a terminal failure interrupts the send with
`StateError`. `SerialTransportFailure.kind` distinguishes platform, I/O,
configuration, protocol, unexpected disconnect, write timeout, and cleanup.
`protocolError` retains the existing decoder kind; `cause` retains the original
error without including payload in transport messages. Cleanup details accumulate
in `cleanupErrors` as shutdown completes. A completed send means all framed bytes
were accepted by the local native/OS write API; it proves no physical completion,
device command execution, LoRa transmission, or remote receipt.

## Reader ownership and shutdown evidence

The actual resolved archive is `libserialport_plus` 1.0.5 (root lockfile and
`.dart_tool/package_config.json`), inspected read-only on November 9, 2026:

- `lib/src/serial_port_reader.dart` passes the port pointer to its background
  isolate. Only the isolate `onExit` callback calls `_dispose()`, which closes the
  reader controller. `close()` sends a stop signal and awaits controller `done`.
- `lib/src/serial_port.dart` confirms void open/close/dispose, explicit native
  ownership, nonblocking negative write timeout in milliseconds, and actual write
  counts. `serial_port_config.dart` and the generated enum definitions confirm the
  settings above. `hook/build.dart` supplies macOS/Linux/Android/Windows backends.
- Controller `done` can also complete on subscription cancellation, according to
  [Dart's controller close contract](https://api.dart.dev/dart-async/StreamController/close.html).
  Therefore canceling the reader subscription first is unsafe.

Shutdown first rejects further operations. It waits for any pending open/configure
operation to settle, preventing a late open result from reviving the connection.
For a started reader it keeps the internal subscription active and unpaused,
awaits `reader.close()` and natural `onDone`, then cancels that subscription,
closes the owned port, disposes it, and closes the public stream. All termination
paths share one cleanup future. Cleanup never waits for a paused public listener's
done delivery. Native ownership follows successful open, including descriptor 0;
failed opens reuse Step 2's partial-acquisition recovery.

No guessed sleep or shutdown timeout permits freeing a port still used by the
reader. If stop fails or subscription setup cannot establish exit evidence, close
fails and a process-lifetime strong reference retains the connection, preventing
native finalization while a reader may still use the port. There is no automatic
recovery of these exceptional retained resources. If the driver or library never
confirms exit, close can remain pending. A primary operation error remains primary;
cleanup failures are attached, and a direct `close()` reports cleanup failure.
Callers should await close even after a stream error.

The library provides no reader startup acknowledgment. `open()` establishes local
port/configuration/subscription setup; it does not certify later isolate activity.
In 1.0.5 the `Isolate.spawn` future is not observed by the library, so startup
failure/driver stalls can escape its normal stream error path or prevent shutdown
completion. Meshchan does not patch the cache, access private pointers, or force
free around those limitations. OS silence is not unplug detection evidence.

## Platforms and optional hardware observation

Windows is rejected before native handle construction, preserving the existing
unsafe-handle guard. Platforms without a native backend are also rejected before
native calls. Linux/Android explicit paths remain distinct from the blocked
enumeration capability; their transport hardware behavior is unverified. Step 2
macOS diagnostic open/close results do not validate this reader or configuration.
All new software tests inject Meshchan's thin boundary. One callback test exercises
the production reader subscription/stop mapping, and configuration values are
checked directly; neither test instantiates a native handle.

Only after explicitly selecting a port and authorizing observation, run:

```bash
# Run from packages/meshcore_link. Set MESHCHAN_PORT yourself first.
: "${MESHCHAN_PORT:?Set the explicitly selected port path}"
dart run example/serial_transport_check.dart "$MESHCHAN_PORT"
```

The example requires exactly one nonblank argument, subscribes before open,
observes for 3 seconds after local setup, and closes on time, error, SIGINT, or
SIGTERM. It prints status, frame counts and lengths only, never body bytes or
identifiers. It sends nothing. Zero frames is valid. A driver stall can extend
shutdown beyond the observation window. Opening/configuring may reset a board;
observation proves no MeshCore identity, TX, or LoRa capability.

Initial validation ran software tests and native builds only. A subsequent
user-authorized three-second source observation on one selected macOS port passed
configuration, reception of two complete frames, and normal shutdown after the
user released an initially busy port. No bytes were sent; native TX, forced
disconnects, device identity, command processing, and LoRa remain unverified.
See the dated [development checks](../development.md#serial-transport-step-4) and
[hardware follow-up](../hardware-validation.md#authorized-read-only-follow-up-on-november-9-2026).
