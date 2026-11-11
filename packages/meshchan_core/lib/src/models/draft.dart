import 'dart:convert';

import '../validation.dart';
import '../values.dart';

/// Exact user text: no trimming, normalization, truncation, or radio byte cap.
final class DraftContent {
  const DraftContent({this.title = '', this.body = ''});
  final String title;
  final String body;
  int get bodyUtf8ByteLength => utf8.encode(body).length;
}

/// A saved version. Construction does not generate an ID or save anything.
final class Draft {
  Draft({
    required this.id,
    required this.content,
    required DateTime createdAt,
    DateTime? updatedAt,
    this.revision = 1,
  }) : createdAt = requireUtc(createdAt),
       updatedAt = requireUtc(updatedAt ?? createdAt) {
    requireValid(revision >= 1);
  }

  final LocalId id;
  final DraftContent content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  String get title => content.title;
  String get body => content.body;
  int get bodyUtf8ByteLength => content.bodyUtf8ByteLength;
}
