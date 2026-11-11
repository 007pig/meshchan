import 'errors.dart';

void requireValid(bool condition) {
  if (!condition) throw const CoreException(CoreErrorCode.invalidInput);
}

DateTime requireUtc(DateTime value) {
  requireValid(value.isUtc);
  return value;
}
