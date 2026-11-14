import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

void main() {
  test('product CRUD uses one real worker, revisions, cursor, scoped quit save and drain', () async {
    final dir = Directory.systemTemp.createTempSync('meshchan-draft-worker-');
    final runtime = RuntimeController(resolveDirectory: () async => dir.path);
    await runtime.start();
    expect(runtime.fixtureWrites, false);
    final a = await runtime.saveDraft(
      title: ' \n中文\r\n🙂 ',
      body: ' A\rB\nC\r\n e\u0301 �',
    );
    final b = await runtime.saveDraft(title: '', body: '');
    expect(a.revision, 1);
    expect(a.createdAt, a.updatedAt);
    expect(a.createdAt.isUtc, true);
    expect(a.bodyUtf8Bytes, DraftContent(body: a.body).bodyUtf8ByteLength);
    final read = await runtime.readDraft(a.id);
    expect(read.title, a.title);
    expect(read.body, a.body);
    expect(
      read.createdAt.microsecondsSinceEpoch,
      a.createdAt.microsecondsSinceEpoch,
    );
    final noOp = await runtime.saveDraft(
      id: a.id,
      expectedRevision: 1,
      title: a.title,
      body: a.body,
    );
    expect(noOp.revision, 1);
    expect(noOp.updatedAt, a.updatedAt);
    final changed = await runtime.saveDraft(
      id: a.id,
      expectedRevision: 1,
      title: a.title,
      body: '${a.body}Changed',
    );
    expect(changed.revision, 2);
    expect(changed.createdAt, a.createdAt);
    Future<void> code(Future<Object?> action, CoreErrorCode code) =>
        expectLater(
          action,
          throwsA(isA<RuntimeFault>().having((e) => e.core, 'core code', code)),
        );
    await code(
      runtime.saveDraft(
        id: a.id,
        expectedRevision: 1,
        title: changed.title,
        body: changed.body,
      ),
      CoreErrorCode.conflict,
    );
    await code(
      runtime.deleteDraft(a.id, expectedRevision: 1),
      CoreErrorCode.conflict,
    );
    await code(
      runtime.saveDraft(title: '', body: String.fromCharCode(0xd800)),
      CoreErrorCode.invalidInput,
    );
    for (final size in [0, 51]) {
      await code(runtime.listDrafts(size: size), CoreErrorCode.invalidInput);
    }
    final page = await runtime.listDrafts(size: 1);
    expect(page.items.length, 1);
    expect(page.nextCursor, isNotNull);
    expect(page.nextCursor!.id, page.items.last.id);
    expect(page.nextCursor!.updatedAt, page.items.last.updatedAt);
    final next = await runtime.listDrafts(size: 1, after: page.nextCursor);
    expect({page.items.single.id, next.items.single.id}, {a.id, b.id});
    expect(next.nextCursor, null);
    final permit = await runtime.beginDraftDecision(7, targetId: a.id);
    await expectLater(
      runtime.saveDraft(title: 'ordinary', body: ''),
      throwsA(isA<RuntimeFault>()),
    );
    final finalSave = await runtime.saveDraft(
      id: a.id,
      expectedRevision: 2,
      title: a.title,
      body: changed.body,
      decision: permit,
      session: 7,
    );
    expect(finalSave.revision, 2);
    await expectLater(
      runtime.saveDraft(
        id: a.id,
        expectedRevision: 2,
        title: '',
        body: '',
        decision: permit,
        session: 7,
      ),
      throwsA(isA<RuntimeFault>()),
    );
    await runtime.endDraftDecision(permit);
    expect(await runtime.deleteDraft(b.id, expectedRevision: 1), b.id);
    await code(runtime.readDraft(b.id), CoreErrorCode.notFound);
    await code(
      runtime.deleteDraft(b.id, expectedRevision: 1),
      CoreErrorCode.notFound,
    );
    await expectLater(
      CoreStorage.open(dataDirectory: dir),
      throwsA(isA<CoreException>()),
    );
    final accepted = runtime.saveDraft(
      id: a.id,
      expectedRevision: 2,
      title: a.title,
      body: 'last',
    );
    final close = runtime.shutdown();
    expect((await accepted).revision, 3);
    expect((await close).canExit, true);
    expect(runtime.pendingCount, 0);
    expect(runtime.openPortCount, 0);
    final reopened = RuntimeController(resolveDirectory: () async => dir.path);
    await reopened.start();
    expect((await reopened.readDraft(a.id)).body, 'last');
    expect((await reopened.listDrafts()).items.length, 1);
    expect((await reopened.shutdown()).canExit, true);
    dir.deleteSync(recursive: true);
  });
}
