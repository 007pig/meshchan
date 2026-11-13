import 'dart:convert';
import 'dart:io';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';

/// Hardware-free process boundary. Explicit directory only; no default path.
Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !const {'read', 'hold'}.contains(args[0]) ||
      !args[1].startsWith('/')) {
    exitCode = 64;
    return;
  }
  final runtime = RuntimeController(
    resolveDirectory: () async => args[1],
    fixtureWrites: args[0] == 'hold',
  );
  await runtime.start();
  final snapshot = runtime.snapshot;
  String? draftId;
  if (args[0] == 'hold' && snapshot.phase == RuntimePhase.ready) {
    draftId = ((await runtime.request(
      const CreateFixtureDraft(),
    )) as DraftValue).draft.id;
  }
  stdout.writeln(
    jsonEncode({
      'phase': snapshot.phase.name,
      'owner': snapshot.owner.name,
      'error': snapshot.error?.code,
      'draftId': draftId,
    }),
  );
  await stdout.flush();
  if (args[0] == 'hold' && snapshot.phase == RuntimePhase.ready) {
    await stdin.first;
  } else if (snapshot.phase == RuntimePhase.ready) {
    final read = await runtime.refresh();
    stdout.writeln(
      jsonEncode({
        'drafts': [
          for (final d in read.drafts)
            {'id': d.id, 'revision': d.revision, 'body': d.body},
        ],
      }),
    );
  }
  final close = await runtime.shutdown();
  stdout.writeln(
    jsonEncode({
      'released': close.resourcesReleased,
      'exited': close.workerExited,
      'ports': runtime.openPortCount,
      'pending': runtime.pendingCount,
    }),
  );
  exitCode = close.canExit ? 0 : 1;
}
