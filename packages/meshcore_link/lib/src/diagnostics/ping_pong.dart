import 'dart:typed_data';

import '../protocol/companion_messages.dart'
    show
        ChannelDataResponse,
        maxChannelDataPayloadLength,
        maxChannelDataPayloadLengthForRoute;

/// Experimental outer data type; the payload magic also has to match.
const int diagnosticDataType = 0xffff;

/// Meshchan diagnostic v1 header length, excluding all Companion fields.
/// This is not a future BBS content format.
const int diagnosticHeaderLength = 34;

const _version = 1;
const _nonceLength = 16;
const _magic = [0x4d, 0x43, 0x48, 0x50]; // ASCII MCHP.

enum DiagnosticKind {
  ping(0x01),
  pong(0x02);

  const DiagnosticKind(this.code);
  final int code;
}

/// An immutable, valid v1 message with independently owned, read-only bytes.
/// Test IDs are configured labels, not authenticated identities.
final class MeshchanDiagnosticMessage {
  /// Copies bytes only after validating all fields and the global payload limit.
  /// Nonces may contain any 16 bytes, including all zeros. No randomness, clock,
  /// request allocation, or run lifecycle is supplied here.
  factory MeshchanDiagnosticMessage({
    required DiagnosticKind kind,
    required Uint8List runNonce,
    required int requestId,
    required int senderTestId,
    required int targetTestId,
    required Uint8List content,
  }) {
    if (runNonce.length != _nonceLength) {
      throw ArgumentError('runNonce must contain exactly 16 bytes.');
    }
    _checkId(requestId, 'requestId');
    _checkEndpoints(senderTestId, targetTestId);
    RangeError.checkValueInInterval(
      content.length,
      0,
      maxChannelDataPayloadLength - diagnosticHeaderLength,
      'content.length',
    );
    return MeshchanDiagnosticMessage._(
      kind: kind,
      runNonce: runNonce,
      requestId: requestId,
      senderTestId: senderTestId,
      targetTestId: targetTestId,
      content: content,
    );
  }

  MeshchanDiagnosticMessage._({
    required this.kind,
    required Uint8List runNonce,
    required this.requestId,
    required this.senderTestId,
    required this.targetTestId,
    required Uint8List content,
  }) : runNonce = Uint8List.fromList(runNonce).asUnmodifiableView(),
       content = Uint8List.fromList(content).asUnmodifiableView();

  int get version => _version;
  final DiagnosticKind kind;
  final Uint8List runNonce;
  final int requestId;
  final int senderTestId;
  final int targetTestId;
  final Uint8List content;

  @override
  String toString() =>
      'MeshchanDiagnosticMessage(version: $version, kind: ${kind.name}, '
      'contentLength: ${content.length})';
}

enum DiagnosticDecodeStatus { unrelated, unsupported, malformed, valid }

/// Structural categories only; no private input or ID values are retained.
enum DiagnosticDecodeReason {
  differentDataType,
  differentMagic,
  unsupportedVersion,
  unsupportedKind,
  truncated,
  payloadTooLong,
  invalidId,
  identicalEndpoints,
}

/// [message] is present exactly for [DiagnosticDecodeStatus.valid]; [reason]
/// is present otherwise. Application failures are values, not Companion errors.
final class DiagnosticDecodeResult {
  const DiagnosticDecodeResult._(this.status, {this.reason, this.message});

  final DiagnosticDecodeStatus status;
  final DiagnosticDecodeReason? reason;
  final MeshchanDiagnosticMessage? message;

  @override
  String toString() =>
      'DiagnosticDecodeResult(${status.name}, reason: ${reason?.name}, '
      'message: $message)';
}

/// Encodes only the application payload into fresh storage, without I/O.
/// The model enforces the global limit. The actual outbound route must still
/// accommodate these bytes; successful encoding does not establish sendability.
Uint8List encodeDiagnosticPayload(MeshchanDiagnosticMessage message) {
  final payload = Uint8List(diagnosticHeaderLength + message.content.length);
  payload.setRange(0, _magic.length, _magic);
  payload[4] = message.version;
  payload[5] = message.kind.code;
  payload.setRange(6, 22, message.runNonce);
  final data = ByteData.sublistView(payload);
  data.setUint32(22, message.requestId, Endian.little);
  data.setUint32(26, message.senderTestId, Endian.little);
  data.setUint32(30, message.targetTestId, Endian.little);
  payload.setRange(diagnosticHeaderLength, payload.length, message.content);
  return payload;
}

/// Classifies the logical payload range, checking boundaries before field reads.
/// This cannot validate the outer data type or the local receive channel.
DiagnosticDecodeResult decodeDiagnosticPayload(Uint8List payload) {
  if (payload.length < _magic.length ||
      !_bytesEqual(Uint8List.sublistView(payload, 0, 4), _magic)) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.unrelated,
      reason: DiagnosticDecodeReason.differentMagic,
    );
  }
  if (payload.length < 5) return _truncated;
  if (payload[4] != _version) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.unsupported,
      reason: DiagnosticDecodeReason.unsupportedVersion,
    );
  }
  if (payload.length < 6) return _truncated;
  final kind = switch (payload[5]) {
    1 => DiagnosticKind.ping,
    2 => DiagnosticKind.pong,
    _ => null,
  };
  if (kind == null) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.unsupported,
      reason: DiagnosticDecodeReason.unsupportedKind,
    );
  }
  if (payload.length < diagnosticHeaderLength) return _truncated;
  if (payload.length > maxChannelDataPayloadLength) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.malformed,
      reason: DiagnosticDecodeReason.payloadTooLong,
    );
  }
  final data = ByteData.sublistView(payload);
  final requestId = data.getUint32(22, Endian.little);
  final senderTestId = data.getUint32(26, Endian.little);
  final targetTestId = data.getUint32(30, Endian.little);
  if (!_validId(requestId) ||
      !_validId(senderTestId) ||
      !_validId(targetTestId)) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.malformed,
      reason: DiagnosticDecodeReason.invalidId,
    );
  }
  if (senderTestId == targetTestId) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.malformed,
      reason: DiagnosticDecodeReason.identicalEndpoints,
    );
  }
  return DiagnosticDecodeResult._(
    DiagnosticDecodeStatus.valid,
    message: MeshchanDiagnosticMessage._(
      kind: kind,
      runNonce: Uint8List.sublistView(payload, 6, 22),
      requestId: requestId,
      senderTestId: senderTestId,
      targetTestId: targetTestId,
      content: Uint8List.sublistView(payload, diagnosticHeaderLength),
    ),
  );
}

const _truncated = DiagnosticDecodeResult._(
  DiagnosticDecodeStatus.malformed,
  reason: DiagnosticDecodeReason.truncated,
);

/// Checks the experimental outer data type before examining application bytes.
/// Ordinary queued messages must be filtered by the caller's response type.
DiagnosticDecodeResult classifyDiagnosticDatagram(
  ChannelDataResponse datagram,
) {
  if (datagram.dataType != diagnosticDataType) {
    return const DiagnosticDecodeResult._(
      DiagnosticDecodeStatus.unrelated,
      reason: DiagnosticDecodeReason.differentDataType,
    );
  }
  return decodeDiagnosticPayload(datagram.payload);
}

/// Constructs a byte-exact PONG only for a PING from the configured peer to this
/// local label and receive slot. Invalid configuration throws [ArgumentError].
/// Performs no send, deduplication, counting, or return-route capacity check.
MeshchanDiagnosticMessage? createDiagnosticPong({
  required ChannelDataResponse datagram,
  required int expectedReceiveChannelIndex,
  required int localTestId,
  required int peerTestId,
}) {
  _checkReceiveChannel(expectedReceiveChannelIndex);
  _checkEndpoints(localTestId, peerTestId);
  if (datagram.channelIndex != expectedReceiveChannelIndex) return null;
  final ping = classifyDiagnosticDatagram(datagram).message;
  if (ping == null ||
      ping.kind != DiagnosticKind.ping ||
      ping.targetTestId != localTestId ||
      ping.senderTestId != peerTestId) {
    return null;
  }
  return MeshchanDiagnosticMessage._(
    kind: DiagnosticKind.pong,
    runNonce: ping.runNonce,
    requestId: ping.requestId,
    senderTestId: ping.targetTestId,
    targetTestId: ping.senderTestId,
    content: ping.content,
  );
}

/// Checks outer type, local receive slot, and every v1 PONG correlation field.
/// True means field equality only, not active/timely/unique or round-trip success.
/// In particular, reception may precede a later local write failure. 1B.6 owns
/// commitment, deadlines, duplicate policy, and RTT.
bool matchesDiagnosticPong({
  required MeshchanDiagnosticMessage expectedPing,
  required ChannelDataResponse datagram,
  required int expectedReceiveChannelIndex,
}) {
  _checkReceiveChannel(expectedReceiveChannelIndex);
  if (expectedPing.kind != DiagnosticKind.ping) {
    throw ArgumentError('expectedPing must have PING kind.');
  }
  if (datagram.channelIndex != expectedReceiveChannelIndex) return false;
  final pong = classifyDiagnosticDatagram(datagram).message;
  return pong != null &&
      pong.kind == DiagnosticKind.pong &&
      pong.requestId == expectedPing.requestId &&
      pong.senderTestId == expectedPing.targetTestId &&
      pong.targetTestId == expectedPing.senderTestId &&
      _bytesEqual(pong.runNonce, expectedPing.runNonce) &&
      _bytesEqual(pong.content, expectedPing.content);
}

/// Content capacity for one validated outbound route. Check each direction
/// independently; receive metadata never determines the return route.
int maxDiagnosticContentLengthForRoute({
  required int routeDescriptor,
  required Uint8List path,
}) =>
    maxChannelDataPayloadLengthForRoute(
      routeDescriptor: routeDescriptor,
      path: path,
    ) -
    diagnosticHeaderLength;

bool _validId(int value) => value >= 1 && value <= 0xffffffff;

void _checkId(int value, String name) {
  if (!_validId(value)) {
    throw ArgumentError('$name must be a nonzero uint32.');
  }
}

void _checkEndpoints(int sender, int target) {
  _checkId(sender, 'senderTestId');
  _checkId(target, 'targetTestId');
  if (sender == target) {
    throw ArgumentError('Test endpoints must have different labels.');
  }
}

void _checkReceiveChannel(int channel) {
  RangeError.checkValueInInterval(
    channel,
    0,
    255,
    'expectedReceiveChannelIndex',
  );
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
