# Companion initialization messages

Phase 1 / 1A / Step 5 provides synchronous, stateless, in-memory command encoding
and response parsing. It does not execute initialization or access hardware.

## Sources and checked layout

The following fixed sources were read online on November 9, 2026. The field table
was established before implementing the codec:

- MeshCore [`MyMesh.cpp` at `81dbae592ffad40b4212bc0b37e82b38da08f4bc`](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp):
  `handleCmdFrame()` command branches, response write order, `writeErrFrame()`,
  response codes, and error codes are the primary wire-layout evidence.
- MeshCore [`BaseSerialInterface.h` at the same commit](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h):
  the existing content limit is 176 bytes.
- Official [`meshcore_py/reader.py` at `c5ffc383730db311ac91b5ef5067e2808584ef92`](https://github.com/meshcore-dev/meshcore_py/blob/c5ffc383730db311ac91b5ef5067e2808584ef92/src/meshcore/reader.py):
  cross-checks DEVICE_INFO version gates at 3, 9, and 10, and nonzero repeat flags.

All offsets and minimum lengths below include the command/response byte at 0 and
exclude the three-byte serial header. Integer radio fields use little-endian
order. This small Dart adapter is independently written from protocol facts; no
upstream implementation code is copied.

| Content | Offsets and interpretation | Minimum bytes |
| --- | --- | --- |
| APP_START (`01`) | 1..7 reserved zeroes; 8 onward UTF-8 application name, no added NUL | 8 |
| DEVICE_QUERY (`16`) | 1: caller-supplied uint8 `appTargetVersion` | 2 |
| SELF_INFO (`05`) | 1: raw advert type; 2: signed TX dBm; 3: unsigned maximum TX dBm; 4..35: public key | 58 |
| SELF_INFO continued | 36..43: skipped coordinates; 44..47: skipped settings; 48..51: uint32 frequency in kHz; 52..55: uint32 bandwidth in Hz; 56: SF; 57: CR; 58 onward: name | 58 |
| DEVICE_INFO (`0D`), protocol 3..8 | 1: protocol code; 2: contact capacity / 2; 3: channel capacity; 4..7: skipped BLE PIN; 8..19: build text; 20..59: model text; 60..79: firmware version text | 80 |
| DEVICE_INFO, protocol 9 | Same basic fields; 80: repeat flag | 81 |
| DEVICE_INFO, protocol 10+ | Same fields; 81: raw path-hash mode | 82 |
| Device error (`01`, device to app) | 1: raw error code; any extra tail is ignored | 2 |

The fixed firmware writes these fields in this order; the official reader
provides the historical version gates. Rejecting early layouts, enforcing
complete prefixes, and the text/input/privacy rules below are Meshchan policies,
not claims that every historical firmware uses this layout.

## API and layer boundary

Import `package:meshcore_link/meshcore_link.dart` for:

```dart
Uint8List encodeAppStart({String appName = 'Meshchan'});
Uint8List encodeDeviceQuery({required int appTargetVersion});
CompanionResponse decodeCompanionResponse(Uint8List content);
```

Encoders return fresh inner content. They do not add `<`, a length header, or a
NUL terminator. A future caller can pass content directly to `sendFrame()`, which
already applies [serial framing](serial-framing.md) once. The parser accepts one
complete content buffer, including its response code, as delivered by `frames`.
It does not search for `>`, buffer partial responses, or use transport internals.
The codec imports only Dart typed data, UTF-8, and the existing content limit.

APP_START produces `01 00 00 00 00 00 00 00 4D 65 73 68 63 68 61 6E` by default
and `01 00 00 00 00 00 00 00` for an empty name. DEVICE_QUERY with target 3 produces
`16 03`; 3 is an example, not a fixed protocol constant. The target is required
and must be `0..255`; out-of-range values throw `RangeError` without truncation.

`appTargetVersion` is the caller's declared target. Sending DEVICE_QUERY updates
the firmware's `app_target_ver`, so it has session-state effects. The returned
`DeviceInfoResponse.protocolVersion` is the device's raw protocol code, while
`firmwareVersion` is its full version text, including suffixes. None is inferred
from Meshchan's semver, Dart, Flutter, or another field. Choosing a target for an
actual session is outside this step; parsing these messages does not implement
every feature of any protocol version.

## Compatibility and failure policy

- SELF_INFO requires all 58 prefix bytes, even with an empty name. There is no
  partial 36-byte or guessed historical layout. Its remaining bytes are the name
  region, not a separately identified extension. Advert type, SF, and CR stay raw
  uint8 values; current TX power is signed, and maximum TX power stays unsigned.
  Frequency uses kHz and bandwidth uses Hz. The codec validates no radio settings,
  regulations, geographic values, or device identity.
- DEVICE_INFO first requires two bytes to read its version. Versions below 3
  throw `unsupportedDeviceInfoVersion`, even if their body is long. Versions 3..8
  require 80 bytes and return null for both later fields; version 9 requires 81
  and returns null for path-hash mode; version 10 and later require 82. Missing
  version-gated bytes cause `truncatedResponse`; length never overrides a version
  gate or supplies a default. Repeat is true for any nonzero flag. Path-hash mode
  stays raw. Extra tails within the 176-byte limit are ignored, with only their
  count saved in `ignoredTailLength`. Future versions preserve their raw code and
  use the known prefix under an explicit prefix-compatibility assumption, without
  claiming support for their other features. Earlier layouts are unsupported by
  project choice, not proof that they cannot be implemented.
- Device-to-app `01` is an error response, despite sharing APP_START's value in
  the other direction. It returns `DeviceErrorResponse` with a raw `errorCode`;
  `knownName` covers 1..6 (unsupported command, not found, table full, bad state,
  file I/O error, illegal argument), and is null for other valid codes. A lone
  `01` is truncated. Extra bytes are ignored; no previous command is inferred.
- The [1B.2 datagram codec](channel-datagrams.md#1b2-implementation-and-validation)
  also recognizes OK (`00`), waiting (`83`), empty queue (`0A`), channel datagrams,
  and ordinary queue messages. They do not satisfy initialization or trigger
  queue polling. Other codes return `UnhandledCompanionResponse` with only
  opcode and complete content length, including unimplemented responses such
  as `0F` and future codes. They are neither parsing failures nor evidence of
  initialization success.
- Empty or oversized input throws `invalidContentLength`; a short known prefix
  throws `truncatedResponse`. These and the unsupported-layout kind are exposed
  through `CompanionProtocolExceptionKind`. `CompanionProtocolException` retains
  only kind, opcode, lengths, and version where available. It never wraps input
  bytes or UTF-8 exceptions. Native and transport errors remain separate. The
  future session layer decides whether parsing failures should end a connection.

## Text, ownership, and privacy policies

Application names use their UTF-8 byte length: at most 168 bytes, so total content
is at most 176. Meshchan rejects embedded NUL with `ArgumentError` to avoid C-string
ambiguity, and rejects overflow rather than truncating or splitting. Empty names
are valid. Names are not trimmed, case-folded, or Unicode-normalized.

Received display text is decoded independently within each field's own range,
stopping at its first NUL, or using the entire range when there is none. NULs are
not removed to concatenate text on either side. Node names use the full remainder
under the same rule; a NUL does not establish a new extension layout. Standard
`utf8.decode(..., allowMalformed: true)` replaces malformed bytes with U+FFFD,
preserving useful device information. This is a display policy, not lossless
recovery. No trimming, normalization, placeholder values, date parsing, or semver
validation is applied. Fixed prefixes must still be structurally complete.

Logical Uint8List offset views are supported. In initialization responses,
public-key bytes are copied into independent storage before exposing a read-only
view; later input mutation cannot change the parsed object. Other retained
initialization data consists of required scalar values and decoded strings.
Neither response models nor exceptions retain whole input
buffers. Unhandled messages retain no payload, since it may contain keys,
positions, or messages. BLE PIN and coordinates are skipped entirely in ordinary
models. Default response summaries and exceptions contain only structural data,
never device strings, coordinates, PIN, public keys, or raw content. This is not
a promise that the caller's original input has been securely erased. A reported
public key is not an authenticated identity or an application author account.

## In-memory example

```dart
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

void main() {
  final appStart = encodeAppStart();
  final query = encodeDeviceQuery(appTargetVersion: 3);
  assert(appStart.length == 16);
  assert(query.length == 2);

  // Synthetic protocol-10 response: capacities and three empty text fields.
  // PIN, repeat flag, and path-hash mode are zero only in this fixture.
  final fixture = Uint8List(82);
  fixture.setRange(0, 4, [0x0d, 10, 50, 8]);
  final response = decodeCompanionResponse(fixture);
  if (response is DeviceInfoResponse) {
    assert(response.protocolVersion == 10);
    assert(response.maxContacts == 100);
    assert(response.repeatEnabled == false);
  }
}
```

No transport, port, I/O, logging, or asynchronous executor is involved in this
example. A separate [user-authorized hardware probe](../hardware-validation.md#step-5-authorized-command-probe-on-november-9-2026)
validated the two command/response paths on one selected USB port; this does not
add an initialization executor to the codec. Step 6's separate
[session](companion-session.md) combines this codec with the existing
[transport](serial-transport.md), adding fixed initialization, response matching,
deadlines, and cleanup. The codec remains stateless. Session hardware acceptance,
authenticated identity, retries, reconnection, and LoRa communication remain
unverified or unimplemented.
