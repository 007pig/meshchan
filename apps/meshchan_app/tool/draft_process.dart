import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/worker.dart';

const title = ' \n中文🙂\r\n';
final body = 'A\rB\nC\r\n e\u0301 �${'长正文🙂' * 200}';
void check(bool condition) {
  if (!condition) throw StateError('Product draft process check failed');
}

/// Test-side send boundary loses only the committed create response. Core,
/// dispatcher, ownership and shutdown remain production implementations.
void lostReplyEntry(WorkerBootstrap bootstrap) {
  final commands = ReceivePort();
  var lost = false;
  final dispatcher = WorkerDispatcher(
    bootstrap,
    send: (event) {
      if (!lost && event is RequestReply && event.value is DraftValue) {
        lost = true;
        return;
      }
      bootstrap.events.send(event);
    },
    finish: commands.close,
  );
  commands.listen(dispatcher.receive);
  bootstrap.events.send(WorkerHello(bootstrap.generation, commands.sendPort));
  dispatcher.start();
}

Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !args[1].startsWith('/') ||
      !const {
        'write',
        'read',
        'unknown',
        'unknown-read',
        'contend',
      }.contains(args[0])) {
    exitCode = 64;
    return;
  }
  final mode = args[0], dir = args[1];
  final runtime = RuntimeController(
    resolveDirectory: () async => dir,
    entry: mode == 'unknown' ? lostReplyEntry : runtimeWorkerEntry,
    deadline: Duration(seconds: mode == 'unknown' ? 2 : 30),
  );
  await runtime.start();
  if (mode == 'contend') {
    check(runtime.snapshot.phase == RuntimePhase.busy);
    check((await runtime.shutdown()).canExit);
    stdout.writeln(jsonEncode({'passed': true, 'busy': true}));
    return;
  }
  check(runtime.snapshot.phase == RuntimePhase.ready);
  final receipt = File('$dir/product-receipt.json');
  if (mode == 'write') {
    check((await runtime.listDrafts()).items.isEmpty);
    final created = await runtime.saveDraft(title: title, body: body);
    final noOp = await runtime.saveDraft(
      id: created.id,
      expectedRevision: 1,
      title: title,
      body: body,
    );
    check(noOp.updatedAt == created.updatedAt && noOp.revision == 1);
    final updated = await runtime.saveDraft(
      id: created.id,
      expectedRevision: 1,
      title: title,
      body: '${body}Saved',
    );
    final deleted = await runtime.saveDraft(title: '', body: '');
    await runtime.deleteDraft(deleted.id, expectedRevision: 1);
    receipt.writeAsStringSync(
      jsonEncode({
        'id': updated.id,
        'deletedId': deleted.id,
        'created': updated.createdAt.microsecondsSinceEpoch,
        'updated': updated.updatedAt.microsecondsSinceEpoch,
      }),
    );
    stdout.writeln(
      jsonEncode({'ready': true, 'fixtureWrites': runtime.fixtureWrites}),
    );
    await stdout.flush();
    await stdin.first;
  } else if (mode == 'read') {
    final facts =
        jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
    final saved = await runtime.readDraft(facts['id'] as String);
    check(
      saved.title == title &&
          saved.body == '${body}Saved' &&
          saved.revision == 2,
    );
    check(
      saved.createdAt.microsecondsSinceEpoch == facts['created'] &&
          saved.updatedAt.microsecondsSinceEpoch == facts['updated'],
    );
    check(saved.bodyUtf8Bytes == utf8.encode(saved.body).length);
    check((await runtime.listDrafts()).items.length == 1);
    try {
      await runtime.readDraft(facts['deletedId'] as String);
      throw StateError('Deleted record returned');
    } on RuntimeFault catch (e) {
      check(e.code == 'not_found');
    }
  } else if (mode == 'unknown') {
    check((await runtime.listDrafts()).items.isEmpty);
    RuntimeFault? failure;
    try {
      await runtime.saveDraft(title: title, body: body);
    } on RuntimeFault catch (e) {
      failure = e;
    }
    check(failure?.host == CoordinationFault.requestUnknown);
    try {
      await runtime.saveDraft(title: title, body: body);
      throw StateError('Retry admitted');
    } on RuntimeFault catch (e) {
      check(e.host == CoordinationFault.requestUnknown);
    }
    check((await runtime.shutdown()).canExit);
    // Resource release never changes the captured unknown mutation result.
    check(failure?.host == CoordinationFault.requestUnknown);
  } else if (mode == 'unknown-read') {
    final page = await runtime.listDrafts();
    // This fresh fixture admitted exactly one create. Identity was never inferred
    // by content in the faulted client; the new process inspects actual records.
    check(page.items.length == 1 && page.items.single.revision == 1);
    check(page.items.single.title == title && page.items.single.body == body);
  }
  final close = await runtime.shutdown();
  check(
    close.canExit && runtime.pendingCount == 0 && runtime.openPortCount == 0,
  );
  stdout.writeln(
    jsonEncode({
      'passed': true,
      'mode': mode,
      'released': close.resourcesReleased,
      'workerExited': close.workerExited,
      'pending': runtime.pendingCount,
      'ports': runtime.openPortCount,
    }),
  );
}
