import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/device_scenario.dart';

void main() {
  for (final delayed in [false, true]) {
    test(
      'real worker typed device/offline/final-save/stop barrier, delayed ack=$delayed',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'meshchan-device-worker-',
        );
        await runDeviceScenario(directory.path, delayedAck: delayed);
        directory.deleteSync(recursive: true);
      },
    );
  }
}
