import 'dart:convert';
import 'dart:typed_data';

import 'serial_framing.dart' show maxSerialFrameContentLength;

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

/// An unimplemented response or push, including ordinary OK (0x00).
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
    0x05 => _decodeSelfInfo(content),
    0x0d => _decodeDeviceInfo(content),
    0x01 => _decodeDeviceError(content),
    _ => UnhandledCompanionResponse._(
      opcode: content[0],
      contentLength: content.length,
    ),
  };
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
