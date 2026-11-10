import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/diagnostics/diagnostic_cache.dart';
import 'package:test/test.dart';

MeshchanDiagnosticMessage ping(int id) => MeshchanDiagnosticMessage(
  kind: DiagnosticKind.ping,
  runNonce: Uint8List(16),
  requestId: id,
  senderTestId: 1,
  targetTestId: 2,
  content: Uint8List.fromList([9]),
);

void main() {
  test(
    'keys compare by value, own bytes, and scope every correlation field',
    () {
      final cache = DiagnosticRequestCache();
      final bytes = Uint8List.fromList([9]);
      final key = DiagnosticRequestKey(2, ping(1));
      expect(
        cache.reserve(key, bytes, Duration.zero),
        DiagnosticCacheAdmission.accepted,
      );
      bytes[0] = 8;
      expect(
        cache.reserve(
          DiagnosticRequestKey(2, ping(1)),
          Uint8List.fromList([9]),
          const Duration(seconds: 119),
        ),
        DiagnosticCacheAdmission.duplicate,
      );
      expect(
        cache.reserve(key, bytes, Duration.zero),
        DiagnosticCacheAdmission.conflict,
      );
      expect(
        cache.reserve(DiagnosticRequestKey(3, ping(1)), bytes, Duration.zero),
        DiagnosticCacheAdmission.accepted,
      );
      expect(
        cache.reserve(DiagnosticRequestKey(2, ping(2)), bytes, Duration.zero),
        DiagnosticCacheAdmission.accepted,
      );
      cache.settle(key);
      expect(
        cache.reserve(key, bytes, const Duration(minutes: 2)),
        DiagnosticCacheAdmission.accepted,
      ); // Duplicates did not refresh TTL.
    },
  );

  test(
    '128 records, lazy expired settlement, and pending retention at TTL',
    () {
      final cache = DiagnosticRequestCache();
      for (var i = 1; i <= 128; i++) {
        final key = DiagnosticRequestKey(2, ping(i));
        expect(
          cache.reserve(key, Uint8List(0), Duration.zero),
          DiagnosticCacheAdmission.accepted,
        );
        if (i != 1) cache.settle(key);
      }
      final next = DiagnosticRequestKey(2, ping(129));
      expect(
        cache.reserve(next, Uint8List(0), const Duration(seconds: 119)),
        DiagnosticCacheAdmission.capacity,
      );
      expect(cache.length, 128);
      expect(
        cache.reserve(next, Uint8List(0), const Duration(minutes: 2)),
        DiagnosticCacheAdmission.accepted,
      );
      expect(cache.length, 2);
      final pending = DiagnosticRequestKey(2, ping(1));
      expect(
        cache.reserve(pending, Uint8List(0), const Duration(minutes: 3)),
        DiagnosticCacheAdmission.duplicate,
      );
      cache.settle(pending);
      expect(
        cache.reserve(pending, Uint8List(0), const Duration(minutes: 3)),
        DiagnosticCacheAdmission.accepted,
      );
      cache.clear();
      expect(cache.length, 0);
    },
  );
}
