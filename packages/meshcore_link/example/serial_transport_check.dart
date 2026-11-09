import 'dart:async';
import 'dart:io';

import 'package:meshcore_link/meshcore_link.dart';

/// Opt-in observation only. Never enumerate or send Companion commands.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || arguments.single.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run example/serial_transport_check.dart <port>',
    );
    exitCode = 64;
    return;
  }
  stdout.writeln(
    'Opening/configuring a port may reset some boards. '
    'This read-only check does not verify MeshCore identity, TX, or LoRa.',
  );
  final transport = SerialTransport(portPath: arguments.single);
  final finished = Completer<void>();
  void finish() {
    if (!finished.isCompleted) finished.complete();
  }

  var count = 0;
  var failed = false;
  final subscription = transport.frames.listen(
    (content) {
      count++;
      stdout.writeln('Frame $count: ${content.length} content bytes.');
    },
    onError: (Object error) {
      failed = true;
      stderr.writeln('Serial observation failed: $error');
      finish();
    },
    onDone: finish,
  );
  final signals = <StreamSubscription<ProcessSignal>>[];
  if (!Platform.isWindows) {
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signals.add(
        signal.watch().listen((_) {
          finish();
          // Closing also interrupts a connection attempt that is still opening.
          unawaited(transport.close().catchError((Object _) {}));
        }),
      );
    }
  }
  Timer? observation;
  try {
    await transport.open();
    stdout.writeln('Local serial port opened; observing for 3 seconds.');
    observation = Timer(const Duration(seconds: 3), finish);
    await finished.future;
  } catch (error) {
    failed = true;
    stderr.writeln('Could not observe the serial connection: $error');
  } finally {
    observation?.cancel();
    try {
      await transport.close();
    } catch (error) {
      failed = true;
      stderr.writeln('Serial cleanup failed: $error');
    }
    await subscription.cancel();
    for (final signal in signals) {
      await signal.cancel();
    }
  }
  stdout.writeln('Observation ended: $count frames. Zero frames is valid.');
  if (failed) exitCode = 69;
}
