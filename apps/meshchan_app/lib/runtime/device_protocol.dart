import 'package:meshcore_link/meshcore_link.dart';

/// Session-only host policy, independent of diagnostic/profile parameters.
final class DeviceCheckOptions {
  const DeviceCheckOptions({
    this.requestSeconds = 5,
    this.initializationSeconds = 15,
    this.startupMilliseconds = 0,
  });
  final int requestSeconds, initializationSeconds, startupMilliseconds;
  bool get valid =>
      requestSeconds >= 1 &&
      requestSeconds <= 86400 &&
      initializationSeconds >= 1 &&
      initializationSeconds <= 86400 &&
      startupMilliseconds >= 0 &&
      startupMilliseconds <= 86399999 &&
      startupMilliseconds < initializationSeconds * 1000;
}

enum DeviceCleanup { notRequired, pending, succeeded, failed }

/// No cause, stack, device text, frames or key material crosses this boundary.
final class DeviceFailure {
  const DeviceFailure(
    this.kind, {
    this.stage,
    this.commandOpcode,
    this.expectedResponseOpcode,
    this.deviceErrorCode,
    this.deviceErrorName,
  });
  factory DeviceFailure.from(Object error) => error is MeshCoreSessionFailure
      ? DeviceFailure(
          error.kind.name,
          stage: error.stage.name,
          commandOpcode: error.commandOpcode,
          expectedResponseOpcode: error.expectedResponseOpcode,
          deviceErrorCode: error.deviceErrorCode,
          deviceErrorName: error.deviceErrorName,
        )
      : const DeviceFailure('observationFailed');
  final String kind;
  final String? stage, deviceErrorName;
  final int? commandOpcode, expectedResponseOpcode, deviceErrorCode;
}

/// Historical display data only. Deliberately excludes the public key.
final class DeviceInformation {
  DeviceInformation(MeshCoreSessionInfo info, this.port, this.observedAt)
    : nodeName = info.selfInfo.nodeName,
      hardwareModel = info.deviceInfo.hardwareModel,
      firmwareVersion = info.deviceInfo.firmwareVersion,
      firmwareBuildDate = info.deviceInfo.firmwareBuildDate,
      protocolVersion = info.deviceInfo.protocolVersion,
      appTargetVersion = info.appTargetVersion,
      maxContacts = info.deviceInfo.maxContacts,
      maxChannels = info.deviceInfo.maxChannels,
      repeatEnabled = info.deviceInfo.repeatEnabled,
      pathHashMode = info.deviceInfo.pathHashMode,
      advertType = info.selfInfo.advertType,
      txPowerDbm = info.selfInfo.txPowerDbm,
      maxTxPowerDbm = info.selfInfo.maxTxPowerDbm,
      radioFrequencyKhz = info.selfInfo.radioFrequencyKhz,
      radioBandwidthHz = info.selfInfo.radioBandwidthHz,
      radioSpreadingFactor = info.selfInfo.radioSpreadingFactor,
      radioCodingRate = info.selfInfo.radioCodingRate;
  final String port,
      nodeName,
      hardwareModel,
      firmwareVersion,
      firmwareBuildDate;
  final DateTime observedAt;
  final int protocolVersion,
      appTargetVersion,
      maxContacts,
      maxChannels,
      advertType,
      txPowerDbm,
      maxTxPowerDbm,
      radioFrequencyKhz,
      radioBandwidthHz,
      radioSpreadingFactor,
      radioCodingRate;
  final bool? repeatEnabled;
  final int? pathHashMode;
}

final class DeviceCheckSnapshot {
  const DeviceCheckSnapshot({
    required this.id,
    required this.port,
    required this.options,
    this.state = MeshCoreSessionState.idle,
    this.cancelApplied = false,
    this.sessionCleanup = DeviceCleanup.notRequired,
    this.observerCleanup = DeviceCleanup.notRequired,
    this.failure,
    this.cleanupFailure,
    this.observerFailure,
    this.info,
    this.settled = false,
  });
  final int id;
  final String port;
  final DeviceCheckOptions options;
  final MeshCoreSessionState state;
  final bool cancelApplied, settled;
  final DeviceCleanup sessionCleanup, observerCleanup;
  final DeviceFailure? failure, cleanupFailure, observerFailure;
  final DeviceInformation? info;
  bool get released =>
      settled && _released(sessionCleanup) && _released(observerCleanup);
  static bool _released(DeviceCleanup value) =>
      value == DeviceCleanup.notRequired || value == DeviceCleanup.succeeded;
}

final class DeviceCheckHandle {
  const DeviceCheckHandle(this.id, this.accepted);
  final int id;

  /// Admission only; initialization/cleanup are observed through snapshots.
  final Future<void> accepted;
}
