/// Stable business/storage categories, independent of enum order or spelling.
enum CoreErrorCode {
  invalidInput('invalid_input'),
  notFound('not_found'),
  conflict('conflict'),
  dataDirectoryBusy('data_directory_busy'),
  storageOpenFailed('storage_open_failed'),
  storageReadFailed('storage_read_failed'),
  storageWriteFailed('storage_write_failed'),
  unsupportedDatabaseVersion('unsupported_database_version'),
  databaseCorrupt('database_corrupt');

  const CoreErrorCode(this.code);
  final String code;
}

/// Safe default description; no original exception, stack, or user input.
final class CoreException implements Exception {
  const CoreException(this.code);
  final CoreErrorCode code;

  @override
  String toString() => 'CoreException(${code.code})';
}
