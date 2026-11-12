import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

import 'profile_fixtures.dart';

// Business work uses only the public package entry, including fixture values.
void main() {
  test(
    'four profiles, settings and resolution survive real-file reopen',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'meshchan-profiles-public-',
      );
      CoreStorage? storage;
      try {
        storage = await CoreStorage.open(dataDirectory: directory);
        expect(identical(storage.profiles, storage.profiles), isTrue);
        expect(identical(storage.settings, storage.settings), isTrue);
        final saved = <ConnectionProfile>[];
        for (final p in validParameters()) {
          saved.add(
            await storage.profiles.save(
              profileContent(p, ' 中文 😀 e\u0301 \uFFFD '),
            ),
          );
        }
        for (final p in saved) {
          expect(p.id.value, matches(RegExp(r'^[0-9a-f]{32}$')));
          expect(p.updatedAt.isUtc, isTrue);
        }
        await storage.settings.save(
          AppSettings(
            defaultProfileId: saved[2].id,
            diagnosticHistoryLimit: 37,
          ),
        );
        final result = await storage.resolveParameters(
          PingParameterRequest(content: [0, 255, 128]),
        );
        expect(result.profileId, saved[2].id);
        expect(result.content, [0, 255, 128]);
        await storage.close();
        storage = await CoreStorage.open(dataDirectory: directory);
        for (final p in saved) {
          final read = await storage.profiles.read(p.id);
          expect(read.name, p.name);
          expect(read.portHint, p.portHint);
          expect(read.operation, p.operation);
          expect(read.updatedAt, p.updatedAt);
        }
        expect((await storage.settings.read()).defaultProfileId, saved[2].id);
        expect((await storage.settings.read()).diagnosticHistoryLimit, 37);
        expect((await storage.profiles.list()).items, hasLength(4));
        await storage.profiles.delete(saved[2].id);
        expect((await storage.settings.read()).defaultProfileId, isNull);
        expect((await storage.settings.read()).diagnosticHistoryLimit, 37);
        expect(
          (await storage.settings.restoreDefaults()).diagnosticHistoryLimit,
          1000,
        );
        for (final p in [saved[0], saved[1], saved[3]]) {
          await storage.profiles.delete(p.id);
        }
        await storage.close();
        storage = await CoreStorage.open(dataDirectory: directory);
        expect((await storage.profiles.list()).items, isEmpty);
        expect((await storage.settings.read()).defaultProfileId, isNull);
        expect((await storage.settings.read()).diagnosticHistoryLimit, 1000);
      } finally {
        await storage?.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
