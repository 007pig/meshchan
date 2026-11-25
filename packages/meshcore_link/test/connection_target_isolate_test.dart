import 'dart:isolate';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

typedef _TargetFields = (CompanionTransportKind, String, int?);
typedef _ProbeResult = ({
  List<ConnectionTarget> targets,
  List<_TargetFields> fields,
  bool equalValues,
  bool usableAsKeys,
});

const _expectedFields = <_TargetFields>[
  (CompanionTransportKind.usbSerial, '  ~/Serial Ports/Fixture  ', null),
  (CompanionTransportKind.tcp, 'Companion.test.', 65535),
  (CompanionTransportKind.ble, 'Host Selection:Fixture/A', null),
];

List<ConnectionTarget> _createTargets() => [
  UsbSerialTarget(portPath: _expectedFields[0].$2),
  TcpTarget(host: _expectedFields[1].$2, port: _expectedFields[1].$3!),
  BleTarget(selectionId: _expectedFields[2].$2),
];

_TargetFields _fields(ConnectionTarget target) => switch (target) {
  UsbSerialTarget(:final kind, :final portPath) => (kind, portPath, null),
  TcpTarget(:final kind, :final host, :final port) => (kind, host, port),
  BleTarget(:final kind, :final selectionId) => (kind, selectionId, null),
};

void _echoTargets((SendPort, List<ConnectionTarget>) message) {
  final (replyTo, received) = message;
  final local = _createTargets();
  final localByTarget = {for (final target in local) target: target.kind};
  final _ProbeResult result = (
    targets: received,
    fields: received.map(_fields).toList(),
    equalValues: Iterable<int>.generate(local.length)
        .every((index) => received[index] == local[index]),
    usableAsKeys:
        {...local, ...received}.length == local.length &&
        received.every((target) => localByTarget[target] == target.kind),
  );
  replyTo.send(result);
}

void main() {
  test('targets survive a same-code isolate round trip', () async {
    final original = _createTargets();
    final response = ReceivePort();
    final stopped = ReceivePort();
    Isolate? worker;
    var observedExit = false;

    try {
      worker = await Isolate.spawn(
        _echoTargets,
        (response.sendPort, original),
        onError: response.sendPort,
        onExit: stopped.sendPort,
      );
      final [reply, exit] = await Future.wait([response.first, stopped.first])
          .timeout(const Duration(seconds: 5));
      observedExit = true;
      expect(exit, isNull);
      expect(reply, isA<_ProbeResult>());
      final result = reply as _ProbeResult;
      expect(result.fields, _expectedFields);
      expect(result.equalValues, isTrue);
      expect(result.usableAsKeys, isTrue);
      expect(result.targets.map(_fields), _expectedFields);
      expect(result.targets, original);
    } finally {
      if (!observedExit) worker?.kill(priority: Isolate.immediate);
      response.close();
      stopped.close();
    }
  }, timeout: Timeout(Duration(seconds: 15)));
}
