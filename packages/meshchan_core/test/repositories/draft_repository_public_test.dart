import 'dart:convert';
import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

// This file deliberately uses only the public package entry for business work.
void main() {
  test('public CRUD commits exact text and deletion to a real file', () async {
    final directory = Directory.systemTemp.createTempSync(
      'meshchan-drafts-public-',
    );
    CoreStorage? storage;
    try {
      storage = await CoreStorage.open(dataDirectory: directory);
      final repository = storage.drafts;
      expect(identical(repository, storage.drafts), isTrue);
      final empty = await repository.create(const DraftContent());
      expect(empty.title, '');
      expect(empty.bodyUtf8ByteLength, 0);
      expect(empty.revision, 1);
      expect(empty.createdAt.isUtc, isTrue);
      expect(empty.updatedAt, empty.createdAt);
      expect(empty.id.value, matches(RegExp(r'^[0-9a-f]{32}$')));
      final content = DraftContent(
        title: ' \t中文 🚀 e\u0301 \uFFFD\r\n ',
        body: ' \t😀 e\u0301\r\n\r\n\n尾部  ' * 2048,
      );
      final saved = await repository.update(
        empty.id,
        content,
        expectedRevision: empty.revision,
      );
      expect(saved.revision, 2);
      expect(saved.id, empty.id);
      expect(saved.createdAt, empty.createdAt);
      expect(saved.bodyUtf8ByteLength, utf8.encode(content.body).length);
      expect(saved.bodyUtf8ByteLength, greaterThan(content.body.length));
      expect((await repository.list()).items.single.body, content.body);
      await storage.close();
      storage = await CoreStorage.open(dataDirectory: directory);
      final read = await storage.drafts.read(saved.id);
      expect(read.title, content.title);
      expect(read.body, content.body);
      expect(read.updatedAt, saved.updatedAt);
      expect(read.createdAt, empty.createdAt);
      expect(read.revision, 2);
      await storage.drafts.delete(read.id, expectedRevision: read.revision);
      await storage.close();
      storage = await CoreStorage.open(dataDirectory: directory);
      expect((await storage.drafts.list()).items, isEmpty);
      await expectLater(
        storage.drafts.read(read.id),
        throwsA(
          isA<CoreException>().having(
            (e) => e.code,
            'code',
            CoreErrorCode.notFound,
          ),
        ),
      );
    } finally {
      await storage?.close();
      directory.deleteSync(recursive: true);
    }
  });
}
