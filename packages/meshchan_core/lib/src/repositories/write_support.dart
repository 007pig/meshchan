import 'dart:math';

import '../errors.dart';
import '../values.dart';

LocalId randomLocalId() {
  final random = Random.secure();
  return LocalId(
    List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
  );
}

// Protect entropy/clock failures before row-error classification sees them.
T writeDependency<T>(T Function() action) {
  try {
    return action();
  } catch (_) {
    throw const CoreException(CoreErrorCode.storageWriteFailed);
  }
}
