# Serial framing

Phase 1 / 1A / Step 3 provides synchronous, hardware-independent byte processing
through `package:meshcore_link/meshcore_link.dart`. It does not open a port.

## Source and wire format

The protocol baseline is MeshCore commit
[`81dbae592ffad40b4212bc0b37e82b38da08f4bc`](https://github.com/meshcore-dev/MeshCore/tree/81dbae592ffad40b4212bc0b37e82b38da08f4bc).
The fixed sources were checked online on November 8, 2026:

- [ArduinoSerialInterface.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ArduinoSerialInterface.cpp)
  defines direction markers, the length field, and the send/receive state machine.
- [BaseSerialInterface.h](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h)
  defines `MAX_FRAME_SIZE` as 176 content bytes.

| Direction | Bytes |
| --- | --- |
| Host to device | `3C` (`<`), length LSB, length MSB, content |
| Device to host | `3E` (`>`), length LSB, length MSB, content |

The unsigned 16-bit little-endian length covers content only, including any opcode
the caller supplies. The header is three bytes; at the content limit, the complete
serial frame is 179 bytes. `maxSerialFrameContentLength` exposes this content limit.
It is unrelated to LoRa packet limits, channel datagram limits, or BLE MTUs.

Content is opaque binary data. Zero bytes, `<`, `>`, and control bytes are preserved.
There is no escaping, newline terminator, checksum, sequence number, text encoding,
or automatic fragmentation. An apparent marker inside content is always content.
This implementation follows the byte layout without copying firmware source code.

## In-memory use

```dart
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

void main() {
  final outgoing = encodeSerialFrame(
    Uint8List.fromList([0x01, 0x00, 0x3c, 0x3e, 0xff]),
  ); // 3C 05 00 01 00 3C 3E FF; no bytes are sent.
  assert(outgoing.length == 8);

  final decoder = SerialFrameDecoder(); // One instance per future connection.
  final first = decoder.add(Uint8List.fromList([0x3e, 0x03]));
  assert(first.frames.isEmpty && first.error == null);
  final next = decoder.add(Uint8List.fromList([0x00, 0x00, 0x80, 0xff]));
  for (final content in next.frames) {
    // Consume completed frames before handling a possible later error.
    assert(content.length == 3); // Content is 00 80 FF, without the header.
  }
  if (next.error != null) {
    throw StateError(next.error!.message);
  }
  final end = decoder.finish();
  assert(end.error == null);
}
```

`add()` accepts arbitrary splits, multiple frames, empty chunks, and offset views.
`SerialFrameDecodeResult.frames` contains complete content buffers in arrival
order. `error`, when present, describes the failure after those completed frames;
callers must process both fields. Errors use `SerialFrameDecodeErrorKind` and a
message with structural counts, without retaining or printing input bytes. They
are separate from native `SerialPortFailure` diagnostics.

## Meshchan policies and lifecycle

- Both encoding and decoding accept content lengths `1..176`. Encoding rejects
  invalid lengths with `RangeError` before allocating output. Decoding validates
  both length bytes before allocating content. Zero-length rejection is a Meshchan
  Companion-content policy; upstream does not uniformly reject zero-length sends.
  The pinned firmware rejects oversized sends and truncates oversized receives;
  Meshchan rejects them without truncation or splitting.
- Outside a frame, the decoder skips non-`>` bytes without retaining them.
  `maxDiscardedBytes` defaults to 1024 and must be nonnegative. This Meshchan
  protection is not an upstream protocol limit. The budget accumulates across
  calls: exactly 1024 skipped bytes are allowed, and the next discarded byte
  reports `noiseLimitExceeded`. Only a completed valid frame or `reset()` renews
  the budget; recognizing a marker or receiving another chunk does not.
- An invalid declared length reports `invalidLength` immediately. It preserves
  frames already completed in that call, stops parsing, and discards the rest of
  the chunk. All protocol errors lock the decoder: subsequent `add()` and
  `finish()` calls throw `StateError` until `reset()`.
- Incomplete input waits normally in `add()`. `finish()` explicitly ends input:
  a partial header or body reports `truncatedFrame` with received/expected wire
  byte counts; a clean boundary or allowed noise alone succeeds without frames.
  After either outcome, further `add()` or `finish()` calls throw `StateError`.
  There is no timer or inferred timeout.
- `reset()` safely clears partial content, header counts, noise, and failed/ended
  state, even when called repeatedly. Dropped input never reappears after reset.

The decoder retains only header counters and at most 176 content bytes across
calls. It processes chunks directly without caching whole chunks or noise.
Encoded output is a fresh copy. Partial content is copied into decoder-owned
storage; each completed buffer transfers exclusively to the caller and is never
reused. The result list is unmodifiable, but its independently owned content
buffers are mutable. Input changes, later decoding, and reset cannot change
previously returned content. Output space naturally grows with completed frames.

The format has no strong integrity check. Noise may itself look like a marker and
valid length, so reliable recovery from arbitrary garbage or content authenticity
cannot be guaranteed. A `>` within a pending body does not resynchronize parsing.
The future connection/session layer decides whether to reset or replace a failed
decoder; this codec does not close or reconnect anything.

Run the software tests from the repository root:

```bash
(cd packages/meshcore_link && dart test test/serial_framing_test.dart)
```

The codec imports only `dart:typed_data`, but the package still has a native serial
dependency whose build hook can run during Dart tests and CLI execution. See the
[Developer Guide](../development.md) for toolchain details and dated software
validation. Live serial reads/writes, Companion command parsing, device identity,
handshakes, sessions, and hardware protocol compatibility are outside this step.
