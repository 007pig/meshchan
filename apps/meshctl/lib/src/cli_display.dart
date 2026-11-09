import 'package:meshcore_link/meshcore_link.dart';

/// Escape terminal controls without changing model data or OS paths.
String safeText(Object? value) {
  if (value == null) return '-';
  final result = StringBuffer();
  for (final rune in value.toString().runes) {
    result.write(switch (rune) {
      10 => r'\n',
      13 => r'\r',
      9 => r'\t',
      < 32 ||
      >= 127 && <= 159 ||
      0x2028 ||
      0x2029 => '\\u${rune.toRadixString(16).padLeft(4, '0')}',
      _ => String.fromCharCode(rune),
    });
  }
  return result.toString();
}

Map<String, Object?> infoFields(
  String port,
  MeshCoreSessionInfo info, {
  required bool closed,
}) {
  final device = info.deviceInfo;
  final self = info.selfInfo;
  return {
    'port': port,
    'initializationCompleted': true,
    'sessionClosed': closed,
    'appTargetVersion': info.appTargetVersion,
    'device': {
      'protocolVersion': device.protocolVersion,
      'firmwareVersion': device.firmwareVersion,
      'firmwareBuildDate': device.firmwareBuildDate,
      'hardwareModel': device.hardwareModel,
      'maxContacts': device.maxContacts,
      'maxChannels': device.maxChannels,
      'repeatEnabled': device.repeatEnabled,
      'pathHashMode': device.pathHashMode,
    },
    'self': {
      'nodeName': self.nodeName,
      'advertType': self.advertType,
      'txPowerDbm': self.txPowerDbm,
      'maxTxPowerDbm': self.maxTxPowerDbm,
      'radioFrequencyKhz': self.radioFrequencyKhz,
      'radioBandwidthHz': self.radioBandwidthHz,
      'radioSpreadingFactor': self.radioSpreadingFactor,
      'radioCodingRate': self.radioCodingRate,
      'publicKeyPrefix': self.publicKey
          .take(8)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
    },
  };
}

String infoText(Map<String, Object?> fields) {
  final lines = <String>[];
  for (final entry in fields.entries) {
    if (entry.value case final Map<String, Object?> group) {
      lines.add('${entry.key}:');
      for (final field in group.entries) {
        lines.add('  ${field.key}: ${safeText(field.value)}');
      }
    } else {
      lines.add('${entry.key}: ${safeText(entry.value)}');
    }
  }
  return lines.join('\n');
}

Map<String, Object?> failureFields(MeshCoreSessionFailure failure) => {
  'kind': failure.kind.name,
  'stage': failure.stage.name,
  'commandOpcode': failure.commandOpcode,
  'expectedResponseOpcode': failure.expectedResponseOpcode,
  'deviceErrorCode': failure.deviceErrorCode,
  'deviceErrorName': failure.deviceErrorName,
};

Map<String, Object?> responseFields(
  MeshCoreSessionUnassociatedResponse event,
) => {
  'opcode': event.opcode,
  'contentLength': event.contentLength,
  'stage': event.stage.name,
  'deviceErrorCode': event.deviceErrorCode,
  'deviceErrorName': event.deviceErrorName,
};
