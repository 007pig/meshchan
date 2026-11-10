import 'dart:convert';
import 'dart:typed_data';

import 'serial_framing.dart' show maxSerialFrameContentLength;

/// Global channel-data payload limit at the pinned MeshCore baseline.
/// A send route can impose a smaller limit; use
/// [maxChannelDataPayloadLengthForRoute] before choosing application content.
const int maxChannelDataPayloadLength = 165;
const _maxPathByteLength = 64;
const _sendChannelDataPrefixLength = 5;
const _channelDataResponsePrefixLength = 9;

/// Returns the payload byte capacity after validating the complete send route.
///
/// Flood (0xFF) requires an empty [path]. Direct descriptors require exactly
/// their encoded path length, 1..3-byte hashes, and at most 64 path bytes.
/// Invalid arguments throw [ArgumentError] or [RangeError] without retaining
/// path storage. Receive-only route metadata cannot supply a return path.
int maxChannelDataPayloadLengthForRoute({
  required int routeDescriptor,
  required Uint8List path,
}) {
  RangeError.checkValueInInterval(routeDescriptor, 0, 255, 'routeDescriptor');
  // Handle the Flood sentinel before applying the Direct descriptor formula.
  final pathBytes = routeDescriptor == 0xff
      ? 0
      : _directPathByteLength(routeDescriptor);
  if (pathBytes == null) {
    throw ArgumentError('routeDescriptor has a reserved or oversized path.');
  }
  if (path.length != pathBytes) {
    throw ArgumentError('path must contain exactly $pathBytes bytes.');
  }
  final serialBudget =
      maxSerialFrameContentLength - _sendChannelDataPrefixLength - pathBytes;
  return serialBudget < maxChannelDataPayloadLength
      ? serialBudget
      : maxChannelDataPayloadLength;
}

/// Encodes APP_START inner content, without a serial header or I/O.
///
/// The name is preserved verbatim as UTF-8. Meshchan rejects NUL and names over
/// 168 encoded bytes with [ArgumentError]; it never truncates or fragments them.
Uint8List encodeAppStart({String appName = 'Meshchan'}) {
  if (appName.contains('\u0000')) {
    throw ArgumentError('appName must not contain NUL.');
  }
  final name = utf8.encode(appName);
  if (8 + name.length > maxSerialFrameContentLength) {
    throw ArgumentError(
      'appName must fit within ${maxSerialFrameContentLength - 8} UTF-8 bytes.',
    );
  }
  final content = Uint8List(8 + name.length);
  content[0] = 0x01;
  // Bytes 1..7 remain zero: all seven are reserved in the pinned firmware.
  content.setRange(8, content.length, name);
  return content;
}

/// Encodes DEVICE_QUERY inner content with an explicit uint8 target version.
///
/// This selects no session policy. Sending it would update firmware session
/// state; this function only allocates bytes. Invalid values throw [RangeError].
Uint8List encodeDeviceQuery({required int appTargetVersion}) {
  RangeError.checkValueInInterval(appTargetVersion, 0, 255, 'appTargetVersion');
  return Uint8List.fromList([0x16, appTargetVersion]);
}

/// Encodes SEND_CHANNEL_DATA inner content, with independently owned bytes.
///
/// [channelIndex] is a local uint8 slot; configured channels are not checked.
/// [dataType] must be 1..65535. [routeDescriptor] is a uint8: 0xFF selects
/// Flood with an empty [path]; other values encode a Direct hash count/size.
/// Direct paths must match the descriptor, use 1..3-byte hashes, and fit 64
/// bytes. Zero-count descriptors 0x00, 0x40, and 0x80 are preserved verbatim.
///
/// [payload] is opaque binary, including empty content. Its limit is the smaller
/// of 165 and `maxSerialFrameContentLength - 5 - path.length`. Invalid arguments
/// throw [ArgumentError] or [RangeError] without retaining path/payload storage.
/// No serial header, length byte, terminator, or application header is added.
Uint8List encodeSendChannelData({
  required int channelIndex,
  required int dataType,
  required int routeDescriptor,
  required Uint8List path,
  required Uint8List payload,
}) {
  RangeError.checkValueInInterval(channelIndex, 0, 255, 'channelIndex');
  RangeError.checkValueInInterval(dataType, 1, 65535, 'dataType');
  final maxPayload = maxChannelDataPayloadLengthForRoute(
    routeDescriptor: routeDescriptor,
    path: path,
  );
  RangeError.checkValueInInterval(
    payload.length,
    0,
    maxPayload,
    'payload.length',
  );

  final typeOffset = 3 + path.length;
  final content = Uint8List(typeOffset + 2 + payload.length);
  content[0] = 0x3e;
  content[1] = channelIndex;
  content[2] = routeDescriptor;
  content.setRange(3, typeOffset, path);
  ByteData.sublistView(content).setUint16(typeOffset, dataType, Endian.little);
  content.setRange(typeOffset + 2, content.length, payload);
  return content;
}

/// Encodes a fresh SYNC_NEXT_MESSAGE command without reading or performing I/O.
Uint8List encodeSyncNextMessage() => Uint8List.fromList([0x0a]);

// Callers handle direction-specific 0xFF semantics and uint8 validation first.
// A null result lets receive parsing report a protocol exception, never an
// argument exception or a retained input buffer.
int? _directPathByteLength(int descriptor) {
  final hashSize = (descriptor >> 6) + 1;
  final pathBytes = (descriptor & 0x3f) * hashSize;
  return hashSize > 3 || pathBytes > _maxPathByteLength ? null : pathBytes;
}

/// The small response family recognized by this codec, without request matching.
sealed class CompanionResponse {
  const CompanionResponse._({
    required this.opcode,
    required this.contentLength,
  });

  final int opcode;
  final int contentLength;

  /// Structural summary only: no device text, keys, or payload bytes.
  @override
  String toString() =>
      '$runtimeType(opcode: $opcode, contentLength: $contentLength)';
}

/// SELF_INFO with the checked 58-byte prefix and a variable-length node name.
/// Coordinates and bytes 44..47 are skipped rather than retained.
final class SelfInfoResponse extends CompanionResponse {
  SelfInfoResponse._({
    required super.contentLength,
    required this.advertType,
    required this.txPowerDbm,
    required this.maxTxPowerDbm,
    required Uint8List publicKey,
    required this.radioFrequencyKhz,
    required this.radioBandwidthHz,
    required this.radioSpreadingFactor,
    required this.radioCodingRate,
    required this.nodeName,
  }) : publicKey = Uint8List.fromList(publicKey).asUnmodifiableView(),
       super._(opcode: 0x05);

  /// Raw uint8; unknown advert types are preserved.
  final int advertType;

  /// Signed int8 current transmit power in dBm.
  final int txPowerDbm;

  /// The distinct unsigned byte reported for maximum transmit power.
  final int maxTxPowerDbm;

  /// Independently owned, read-only bytes. This is reported data, not an
  /// authenticated device identity or an application author identity.
  final Uint8List publicKey;
  final int radioFrequencyKhz;
  final int radioBandwidthHz;
  final int radioSpreadingFactor;
  final int radioCodingRate;
  final String nodeName;
}

/// DEVICE_INFO using version-gated prefixes. BLE PIN is never retained.
final class DeviceInfoResponse extends CompanionResponse {
  const DeviceInfoResponse._({
    required super.contentLength,
    required this.protocolVersion,
    required this.maxContacts,
    required this.maxChannels,
    required this.firmwareBuildDate,
    required this.hardwareModel,
    required this.firmwareVersion,
    required this.repeatEnabled,
    required this.pathHashMode,
    required this.ignoredTailLength,
  }) : super._(opcode: 0x0d);

  /// Raw Companion protocol code, distinct from [firmwareVersion] text and the
  /// application's declared target version in DEVICE_QUERY.
  final int protocolVersion;
  final int maxContacts;
  final int maxChannels;
  final String firmwareBuildDate;
  final String hardwareModel;
  final String firmwareVersion;

  /// Nonzero means true from protocol 9 onward; null before protocol 9.
  final bool? repeatEnabled;

  /// Raw byte from protocol 10 onward; null before protocol 10.
  final int? pathHashMode;

  /// Count only; unknown trailing bytes are not retained or interpreted.
  final int ignoredTailLength;

  @override
  String toString() =>
      'DeviceInfoResponse(protocolVersion: $protocolVersion, '
      'contentLength: $contentLength)';
}

/// A valid device error, with no inferred association to a previous command.
final class DeviceErrorResponse extends CompanionResponse {
  const DeviceErrorResponse._({
    required super.contentLength,
    required this.errorCode,
  }) : super._(opcode: 0x01);

  final int errorCode;

  /// Unknown codes remain valid and have no known name.
  String? get knownName => switch (errorCode) {
    1 => 'unsupported command',
    2 => 'not found',
    3 => 'table full',
    4 => 'bad state',
    5 => 'file I/O error',
    6 => 'illegal argument',
    _ => null,
  };
}

/// Local OK only; no command association or remote delivery is implied.
final class OkResponse extends CompanionResponse {
  const OkResponse._() : super._(opcode: 0x00, contentLength: 1);
}

/// Queue waiting notice only; this performs no read and acknowledges no send.
final class MessageWaitingResponse extends CompanionResponse {
  const MessageWaitingResponse._() : super._(opcode: 0x83, contentLength: 1);
}

/// Empty-queue result, distinct from the host command with the same opcode.
final class NoMoreMessagesResponse extends CompanionResponse {
  const NoMoreMessagesResponse._() : super._(opcode: 0x0a, contentLength: 1);
}

/// One structurally valid channel datagram, without application filtering.
final class ChannelDataResponse extends CompanionResponse {
  ChannelDataResponse._({
    required super.contentLength,
    required this.snrQuarterDb,
    required this.channelIndex,
    required this.routeMetadata,
    required this.dataType,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload).asUnmodifiableView(),
       super._(opcode: 0x1b);

  /// Signed int8, in quarter-dB units.
  final int snrQuarterDb;
  double get snrDb => snrQuarterDb / 4.0;
  final int channelIndex;

  /// Receive-only metadata: 0xFF means Direct arrival; otherwise an observed
  /// Flood path descriptor. No path bytes are present or inferred from it.
  final int routeMetadata;
  bool get isDirect => routeMetadata == 0xff;

  /// Raw uint16, including zero and types unknown to this application.
  final int dataType;

  /// Independently owned, read-only bytes, available for explicit caller use.
  final Uint8List payload;
}

enum QueuedMessageKind {
  legacyContact,
  contactV3,
  legacyChannelText,
  channelTextV3,
}

/// An ordinary shared-queue entry. Only its prefix is checked; no body,
/// contact extras, or other input storage is parsed or retained.
final class QueuedMessageResponse extends CompanionResponse {
  const QueuedMessageResponse._({
    required super.opcode,
    required super.contentLength,
    required this.kind,
  }) : super._();

  final QueuedMessageKind kind;
}

/// An unimplemented response or push.
/// This retains only opcode and content length, and implies no startup success.
final class UnhandledCompanionResponse extends CompanionResponse {
  const UnhandledCompanionResponse._({
    required super.opcode,
    required super.contentLength,
  }) : super._();
}

enum CompanionProtocolExceptionKind {
  invalidContentLength,
  truncatedResponse,
  unsupportedDeviceInfoVersion,
  unexpectedResponseLength,
  invalidPayloadLength,
  invalidRouteDescriptor,
}

/// Parsing failure containing only structural metadata, never input storage,
/// device strings, native errors, or FormatException source bytes.
final class CompanionProtocolException implements Exception {
  const CompanionProtocolException._(
    this.kind, {
    required this.contentLength,
    this.opcode,
    this.requiredLength,
    this.protocolVersion,
  });

  final CompanionProtocolExceptionKind kind;
  final int contentLength;
  final int? opcode;
  final int? requiredLength;
  final int? protocolVersion;

  @override
  String toString() =>
      'CompanionProtocolException(${kind.name}, opcode: $opcode, '
      'contentLength: $contentLength, requiredLength: $requiredLength, '
      'protocolVersion: $protocolVersion)';
}

/// Parses exactly one complete device-to-app inner content buffer.
///
/// Accepts logical offset views and lengths 1..176, without searching for a
/// serial marker. Known prefixes must be complete. DEVICE_INFO below protocol 3
/// throws a distinct unsupported-layout exception, even if its body is long.
/// Malformed display UTF-8 is replaced with U+FFFD within each field's range.
/// No whole input buffer is retained. Errors do not close a transport or log.
CompanionResponse decodeCompanionResponse(Uint8List content) {
  if (content.isEmpty || content.length > maxSerialFrameContentLength) {
    throw CompanionProtocolException._(
      CompanionProtocolExceptionKind.invalidContentLength,
      contentLength: content.length,
      opcode: content.isEmpty ? null : content[0],
    );
  }
  return switch (content[0]) {
    0x00 => _decodeControl(content, const OkResponse._()),
    0x83 => _decodeControl(content, const MessageWaitingResponse._()),
    0x0a => _decodeControl(content, const NoMoreMessagesResponse._()),
    0x1b => _decodeChannelData(content),
    0x07 => _decodeQueuedMessage(content, QueuedMessageKind.legacyContact, 13),
    0x10 => _decodeQueuedMessage(content, QueuedMessageKind.contactV3, 16),
    0x08 => _decodeQueuedMessage(
      content,
      QueuedMessageKind.legacyChannelText,
      8,
    ),
    0x11 => _decodeQueuedMessage(content, QueuedMessageKind.channelTextV3, 11),
    0x05 => _decodeSelfInfo(content),
    0x0d => _decodeDeviceInfo(content),
    0x01 => _decodeDeviceError(content),
    _ => UnhandledCompanionResponse._(
      opcode: content[0],
      contentLength: content.length,
    ),
  };
}

CompanionResponse _decodeControl(
  Uint8List content,
  CompanionResponse response,
) {
  _requireExactLength(content, 1);
  return response;
}

void _requireExactLength(Uint8List content, int expected) {
  if (content.length != expected) {
    throw CompanionProtocolException._(
      CompanionProtocolExceptionKind.unexpectedResponseLength,
      contentLength: content.length,
      opcode: content[0],
      requiredLength: expected,
    );
  }
}

ChannelDataResponse _decodeChannelData(Uint8List content) {
  _requireLength(content, _channelDataResponsePrefixLength);
  final payloadLength = content[8];
  if (payloadLength > maxChannelDataPayloadLength) {
    throw CompanionProtocolException._(
      CompanionProtocolExceptionKind.invalidPayloadLength,
      contentLength: content.length,
      opcode: content[0],
    );
  }
  _requireExactLength(
    content,
    _channelDataResponsePrefixLength + payloadLength,
  );
  final routeMetadata = content[5];
  if (routeMetadata != 0xff && _directPathByteLength(routeMetadata) == null) {
    throw CompanionProtocolException._(
      CompanionProtocolExceptionKind.invalidRouteDescriptor,
      contentLength: content.length,
      opcode: content[0],
    );
  }
  final data = ByteData.sublistView(content);
  return ChannelDataResponse._(
    contentLength: content.length,
    snrQuarterDb: data.getInt8(1),
    channelIndex: content[4],
    routeMetadata: routeMetadata,
    dataType: data.getUint16(6, Endian.little),
    payload: Uint8List.sublistView(content, _channelDataResponsePrefixLength),
  );
}

QueuedMessageResponse _decodeQueuedMessage(
  Uint8List content,
  QueuedMessageKind kind,
  int minimum,
) {
  _requireLength(content, minimum);
  return QueuedMessageResponse._(
    opcode: content[0],
    contentLength: content.length,
    kind: kind,
  );
}

void _requireLength(Uint8List content, int minimum, {int? protocolVersion}) {
  if (content.length < minimum) {
    throw CompanionProtocolException._(
      CompanionProtocolExceptionKind.truncatedResponse,
      contentLength: content.length,
      opcode: content[0],
      requiredLength: minimum,
      protocolVersion: protocolVersion,
    );
  }
}

SelfInfoResponse _decodeSelfInfo(Uint8List content) {
  _requireLength(content, 58);
  final data = ByteData.sublistView(content);
  return SelfInfoResponse._(
    contentLength: content.length,
    advertType: content[1],
    txPowerDbm: data.getInt8(2),
    maxTxPowerDbm: content[3],
    publicKey: Uint8List.sublistView(content, 4, 36),
    radioFrequencyKhz: data.getUint32(48, Endian.little),
    radioBandwidthHz: data.getUint32(52, Endian.little),
    radioSpreadingFactor: content[56],
    radioCodingRate: content[57],
    nodeName: _displayText(content, 58, content.length),
  );
}

DeviceInfoResponse _decodeDeviceInfo(Uint8List content) {
  _requireLength(content, 2);
  final version = content[1];
  if (version < 3) {
    throw CompanionProtocolException._(
      CompanionProtocolExceptionKind.unsupportedDeviceInfoVersion,
      contentLength: content.length,
      opcode: content[0],
      protocolVersion: version,
    );
  }
  final minimum = version >= 10 ? 82 : (version >= 9 ? 81 : 80);
  _requireLength(content, minimum, protocolVersion: version);
  return DeviceInfoResponse._(
    contentLength: content.length,
    protocolVersion: version,
    maxContacts: content[2] * 2,
    maxChannels: content[3],
    firmwareBuildDate: _displayText(content, 8, 20),
    hardwareModel: _displayText(content, 20, 60),
    firmwareVersion: _displayText(content, 60, 80),
    repeatEnabled: version >= 9 ? content[80] != 0 : null,
    pathHashMode: version >= 10 ? content[81] : null,
    ignoredTailLength: content.length - minimum,
  );
}

DeviceErrorResponse _decodeDeviceError(Uint8List content) {
  _requireLength(content, 2);
  return DeviceErrorResponse._(
    contentLength: content.length,
    errorCode: content[1],
  );
}

String _displayText(Uint8List content, int start, int end) {
  final field = Uint8List.sublistView(content, start, end);
  final nul = field.indexOf(0);
  return utf8.decode(
    nul < 0 ? field : Uint8List.sublistView(field, 0, nul),
    allowMalformed: true,
  );
}
