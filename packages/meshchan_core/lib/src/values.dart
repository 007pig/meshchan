import 'validation.dart';

/// An opaque local 128-bit identifier, not an article or protocol identifier.
/// Generation and insertion uniqueness checks belong to later storage work.
final class LocalId {
  LocalId(this.value) {
    requireValid(RegExp(r'^[0-9a-f]{32}$').hasMatch(value));
  }

  final String value;

  @override
  bool operator ==(Object other) => other is LocalId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

enum DiagnosticOperation {
  send('send'),
  listen('listen'),
  ping('ping'),
  respond('respond');

  const DiagnosticOperation(this.code);
  final String code;
}

/// Bounded queries default to 50; callers cannot request an unlimited list.
final class PageSize {
  PageSize([this.value = 50]) {
    requireValid(value >= 1 && value <= 200);
  }
  final int value;
}

/// Draft/profile ordering is updatedAt DESC, id DESC.
final class UpdatedCursor {
  UpdatedCursor({required DateTime updatedAt, required this.id})
    : updatedAt = requireUtc(updatedAt);
  final DateTime updatedAt;
  final LocalId id;
}

/// History ordering is preparedAt DESC, runId DESC.
final class HistoryCursor {
  HistoryCursor({required DateTime preparedAt, required this.runId})
    : preparedAt = requireUtc(preparedAt);
  final DateTime preparedAt;
  final LocalId runId;
}

/// A continuation is absent at the end. Separate calls are not a snapshot.
final class Page<T, C> {
  Page({required Iterable<T> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<T> items;
  final C? nextCursor;
}
