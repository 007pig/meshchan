import 'dart:convert';
import 'dart:io';

import '../launch_configuration.dart';
import 'controller.dart';
import 'protocol.dart';

/// Bounded acceptance of the production dispatcher/worker. No fake devices,
/// arbitrary scripts or closures are admitted by this entry.
Future<bool> verifyRuntime(
  LaunchConfiguration config,
  RuntimeController runtime,
) async {
  final phases = <RuntimePhase>[];
  final states = runtime.changes.listen((snapshot) {
    if (phases.isEmpty || phases.last != snapshot.phase) {
      phases.add(snapshot.phase);
    }
  });
  final path = config.directory!;
  final receipt = File('$path/meshchan-1d3-receipt.json');
  Map<String, dynamic>? expected;
  var passed = false;
  try {
    final directory = Directory(path);
    if (directory.parent.resolveSymbolicLinksSync() != directory.parent.path) {
      throw const FormatException('Fixture parent must be canonical.');
    }
    if (config.verification == 'write') {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FormatException('Write requires a new fixture.');
      }
      directory.createSync();
    } else {
      if (directory.resolveSymbolicLinksSync() != path ||
          receipt.lengthSync() > 4096 ||
          FileSystemEntity.typeSync(receipt.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const FormatException('Read requires an owned closed fixture.');
      }
      final previous =
          jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
      if (previous['state'] != 'closed' ||
          previous['fixture'] != path ||
          previous['verification'] != 'meshchan.runtime.1d3') {
        throw const FormatException('Missing closed fixture receipt.');
      }
      final database = File('$path/meshchan.sqlite');
      if (FileSystemEntity.typeSync(database.path, followLinks: false) !=
              FileSystemEntityType.file ||
          database.lengthSync() == 0) {
        throw const FormatException(
          'Read requires an existing nonempty database.',
        );
      }
      expected = previous['draft'] as Map<String, dynamic>;
    }
    receipt.writeAsStringSync(jsonEncode({'state': 'incomplete'}), flush: true);
    await runtime.start();
    if (runtime.snapshot.phase != RuntimePhase.ready) {
      throw StateError('Open failed');
    }
    if (config.verification == 'write') {
      final value =
          await runtime.request(const CreateFixtureDraft()) as DraftValue;
      expected = _facts(value.draft);
    }
    // Multiple correlated requests reuse the same long-lived owner.
    final read = await runtime.refresh();
    final again = await runtime.refresh();
    final status = await runtime.request(const GetStatus()) as StatusValue;
    final draft = read.drafts.single;
    if (again.drafts.single.id != draft.id ||
        status.snapshot.owner != OwnerFact.held ||
        draft.title != runtimeFixtureTitle ||
        draft.body != runtimeFixtureBody ||
        jsonEncode(_facts(draft)) != jsonEncode(expected)) {
      throw StateError('Fixture continuity failed');
    }
    passed = true;
  } catch (_) {
    // Verification intentionally reports a controlled category, no user text.
    passed = false;
  }
  final close = await runtime.shutdown();
  await states.cancel();
  passed = passed && close.canExit;
  if (passed) {
    receipt.writeAsStringSync(
      jsonEncode({
        'verification': 'meshchan.runtime.1d3',
        'fixture': path,
        'state': 'closed',
        'draft': expected,
      }),
      flush: true,
    );
  }
  stdout.writeln(
    jsonEncode({
      'verification': 'meshchan.runtime.1d3',
      'passed': passed,
      'mode': config.verification,
      'resourcesReleased': close.resourcesReleased,
      'workerExited': close.workerExited,
      'phases': phases.map((phase) => phase.name).toList(growable: false),
      'pendingRequests': runtime.pendingCount,
      'receivePorts': runtime.openPortCount,
      'draft': expected,
      'error': runtime.snapshot.error?.code,
    }),
  );
  await stdout.flush();
  return passed;
}

Map<String, Object?> _facts(DraftSnapshot d) => {
  'id': d.id,
  'revision': d.revision,
  'bodyUtf8Bytes': d.bodyUtf8Bytes,
  'createdAt': d.createdAt.toIso8601String(),
  'updatedAt': d.updatedAt.toIso8601String(),
};
