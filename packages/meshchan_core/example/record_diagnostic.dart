import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

// This host's actual example version, independent of database/summary/wire versions.
const exampleVersion = 'meshchan-recording-example-1';

/// Run with a host-selected local directory. This example uses synthetic
/// responses only; it never enumerates or connects to a real device.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run example/record_diagnostic.dart <data-directory>',
    );
    exitCode = 64;
    return;
  }
  final storage = await CoreStorage.open(dataDirectory: Directory(args.single));
  RecordedOperation? operation;
  try {
    // open has already completed exclusive startup recovery.
    final parameters = await storage.resolveParameters(
      SendParameterRequest(
        overrides: SendOverrides(
          budgets: const BudgetOverrides(taskTimeoutSeconds: 5),
          sendChannelIndex: 3,
          dataType: 99,
          route: RouteOverrides(routeDescriptor: 0xff),
        ),
        payload: [0, 128, 255],
      ),
    );
    operation = storage.record(
      parameters: parameters,
      appVersion: exampleVersion,
      createTransport: _ExampleTransport.new,
    );
    final prepared = await operation.prepared;
    stdout.writeln('Registration: ${prepared.state.name}');
    final logical = await operation.logical;
    stdout.writeln('Logical reason: ${logical?.reason?.code ?? 'unknown'}');
    final logicalSave = await operation.logicalSaved;
    stdout.writeln('Logical persistence: ${logicalSave.state.name}');
    // These awaits can remain pending after logical and logicalSaved complete.
    final cleanup = await operation.cleanupDone;
    final result = await operation.done;
    stdout.writeln('Actual cleanup: ${cleanup.aggregate.code}');
    stdout.writeln(
      'Final cleanup persistence: ${result.cleanupSave.state.name}',
    );
    stdout.writeln(
      'Recorded operation fully successful: ${result.fullySuccessful}',
    );
    stdout.writeln('Local acceptance does not confirm wireless delivery.');
  } finally {
    // An external cancellation source can call operation.cancel immediately;
    // it must not wait for any database save to do so.
    if (operation != null) {
      operation.cancel().ignore();
      await operation.done;
    }
    await storage.close();
  }
}

final class _ExampleTransport implements CompanionTransport {
  final _frames = StreamController<Uint8List>(sync: true);
  @override
  Stream<Uint8List> get frames => _frames.stream;
  @override
  Future<void> open() async {}
  @override
  Future<void> sendFrame(Uint8List content) async {
    final response = switch (content[0]) {
      0x16 => Uint8List(82)..setRange(0, 8, [0x0d, 14, 25, 8, 0, 0, 0, 0]),
      0x01 => Uint8List.fromList([
        0x05,
        1,
        20,
        22,
        ...List.filled(44, 0),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        11,
        7,
      ]),
      0x3e => Uint8List.fromList([0]),
      _ => throw StateError('Unexpected example command.'),
    };
    scheduleMicrotask(() => _frames.add(response));
  }

  @override
  Future<void> close() => _frames.close();
}
