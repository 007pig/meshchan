import 'errors.dart';

void requireValid(bool condition) {
  if (!condition) throw const CoreException(CoreErrorCode.invalidInput);
}

DateTime requireUtc(DateTime value) {
  requireValid(value.isUtc);
  return value;
}

/// Reject lossy UTF-8 encoding while preserving all valid input verbatim.
void validateUnicode(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      requireValid(++i < text.length);
      final low = text.codeUnitAt(i);
      requireValid(low >= 0xdc00 && low <= 0xdfff);
    } else {
      requireValid(unit < 0xdc00 || unit > 0xdfff);
    }
  }
}
