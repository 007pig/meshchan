import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/launch_configuration.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/verification.dart';

void main() {
  test(
    'read verification preserves a truncated database and its closed receipt',
    () async {
      final parent = Directory.systemTemp.createTempSync(
        'meshchan-verify-review-',
      );
      final path = '${parent.resolveSymbolicLinksSync()}/meshchan-1d3-empty';
      LaunchConfiguration config(String mode) => LaunchConfiguration.parse([
        '--meshchan-runtime=$mode',
        '--data-dir=$path',
      ]);
      RuntimeController runtime({bool write = false}) => RuntimeController(
        resolveDirectory: () async => path,
        fixtureWrites: write,
      );
      var verified = false;
      addTearDown(() {
        if (verified) parent.deleteSync(recursive: true);
      });
      expect(await verifyRuntime(config('write'), runtime(write: true)), true);
      expect(await verifyRuntime(config('read'), runtime()), true);
      final receipt = File('$path/meshchan-1d3-receipt.json');
      final originalReceipt = receipt.readAsBytesSync();
      final database = File('$path/meshchan.sqlite');
      database.writeAsBytesSync(const [], flush: true);

      final reader = runtime();
      expect(await verifyRuntime(config('read'), reader), false);
      expect(
        database.lengthSync(),
        0,
        reason: 'Read preflight must not initialize an empty database',
      );
      expect(receipt.readAsBytesSync(), originalReceipt);
      final closed = await reader.shutdown();
      expect(closed.canExit, true);
      expect(closed.workerWasSpawned, false);
      expect(closed.workerExited, false);
      expect(reader.snapshot.owner, OwnerFact.none);
      expect(reader.pendingCount, 0);
      expect(reader.openPortCount, 0);
      verified = true;
    },
  );
}
