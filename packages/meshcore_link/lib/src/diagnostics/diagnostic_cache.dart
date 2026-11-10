import 'dart:typed_data';

import 'ping_pong.dart';

// Library-internal policy, intentionally not exported from meshcore_link.dart.
enum DiagnosticCacheAdmission { accepted, duplicate, conflict, capacity }

final class DiagnosticRequestKey {
  DiagnosticRequestKey(int channel, MeshchanDiagnosticMessage ping)
    : _values = List.unmodifiable([
        channel,
        ...ping.runNonce,
        ping.requestId,
        ping.senderTestId,
        ping.targetTestId,
      ]);
  final List<int> _values;
  @override
  int get hashCode => Object.hashAll(_values);
  @override
  bool operator ==(Object other) =>
      other is DiagnosticRequestKey && _equal(_values, other._values);
}

final class _Record {
  _Record(this.acceptedAt, Uint8List content)
    : content = Uint8List.fromList(content).asUnmodifiableView();
  final Duration acceptedAt;
  final Uint8List content;
  bool settled = false;
}

final class DiagnosticRequestCache {
  static const capacity = 128;
  static const ttl = Duration(minutes: 2);
  final _records = <DiagnosticRequestKey, _Record>{};
  int get length => _records.length;

  DiagnosticCacheAdmission reserve(
    DiagnosticRequestKey key,
    Uint8List content,
    Duration now,
  ) {
    _records.removeWhere(
      (_, record) => record.settled && now - record.acceptedAt >= ttl,
    );
    final old = _records[key];
    if (old != null) {
      return _equal(old.content, content)
          ? DiagnosticCacheAdmission.duplicate
          : DiagnosticCacheAdmission.conflict;
    }
    if (_records.length == capacity) return DiagnosticCacheAdmission.capacity;
    _records[key] = _Record(now, content);
    return DiagnosticCacheAdmission.accepted;
  }

  void settle(DiagnosticRequestKey key) => _records[key]!.settled = true;
  void clear() => _records.clear();
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
