import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';

/// Host policy only. Core owns canonical identity, creation, locks and recovery.
String dataDirectoryPath({
  String? explicit,
  String? operatingSystem,
  Map<String, String>? environment,
}) {
  if (explicit != null) {
    if (explicit.trim().isEmpty || explicit.contains('\u0000')) {
      throw const FormatException(
        '--data-dir must be a nonblank path without NUL.',
      );
    }
    return explicit;
  }
  final os = operatingSystem ?? Platform.operatingSystem;
  final env = environment ?? Platform.environment;
  bool usable(String? path) =>
      path != null &&
      path.trim().isNotEmpty &&
      !path.contains('\u0000') &&
      (os == 'windows'
          ? RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)')
                .hasMatch(path)
          : path.startsWith('/'));
  String requiredBase(String? path) {
    if (!usable(path)) {
      throw const FormatException(
        'No absolute application data base is available; provide --data-dir.',
      );
    }
    return path!;
  }

  return switch (os) {
    'macos' =>
      '${requiredBase(env['HOME'])}/Library/Application Support/meshchan',
    'linux' =>
      usable(env['XDG_DATA_HOME'])
          ? '${env['XDG_DATA_HOME']}/meshchan'
          : '${requiredBase(env['HOME'])}/.local/share/meshchan',
    'windows' => '${requiredBase(env['LOCALAPPDATA'])}\\meshchan',
    _ => throw const FormatException(
      'This platform requires an explicit --data-dir.',
    ),
  };
}

int coreExitCode(CoreException error) => switch (error.code) {
  CoreErrorCode.invalidInput || CoreErrorCode.notFound => 64,
  CoreErrorCode.conflict || CoreErrorCode.dataDirectoryBusy => 69,
  CoreErrorCode.storageOpenFailed ||
  CoreErrorCode.storageReadFailed ||
  CoreErrorCode.storageWriteFailed ||
  CoreErrorCode.unsupportedDatabaseVersion ||
  CoreErrorCode.databaseCorrupt => 74,
};

Map<String, Object?> coreErrorFields(CoreException error, String source) => {
  'domain': 'storage',
  'source': source,
  'code': error.code.code,
  'cleanupUnconfirmed': error.cleanupUnconfirmed,
};

Map<String, Object?>? maintenanceFields(HistoryMaintenanceReport? report) =>
    report == null
    ? null
    : {
        'state': report.state.name,
        'deletedCount': report.deletedCount,
        'historyLimit': report.historyLimit,
        'deferredCount': report.deferredCount,
        'error': report.error == null
            ? null
            : coreErrorFields(report.error!, 'maintenance'),
      };

/// Finalize once, while retaining only getter access after close starts. Close
/// also drains recording's post-done unpin/maintenance continuation.
final class BusinessStorage {
  BusinessStorage(this.storage) : history = storage.history;
  final CoreStorage storage;
  final DiagnosticHistory history;
  Map<String, Object?>? maintenance;
  Map<String, Object?>? closeResult;
  final failures = <Map<String, Object?>>[];
  Future<void>? _finishing;
  bool get failed => failures.isNotEmpty;

  Future<void> finish() => _finishing ??= _finish();
  Future<void> _finish() async {
    Object? unexpected;
    StackTrace? stack;
    try {
      await history.waitForMaintenance();
    } on CoreException catch (e) {
      failures.add(coreErrorFields(e, 'maintenance_wait'));
    } catch (e, s) {
      unexpected = e;
      stack = s;
    } finally {
      try {
        await storage.close();
        closeResult = {'state': storage.state.name, 'error': null};
        if (storage.state != StorageState.closed) {
          failures.add({
            'domain': 'storage',
            'source': 'close',
            'code': 'cleanup_unconfirmed',
            'cleanupUnconfirmed': true,
          });
        }
      } on CoreException catch (e) {
        final failure = coreErrorFields(e, 'close');
        failures.add(failure);
        closeResult = {'state': storage.state.name, 'error': failure};
      } catch (e, s) {
        unexpected ??= e;
        stack ??= s;
        closeResult = {
          'state': storage.state.name,
          'error': {'domain': 'internal', 'source': 'close'},
        };
      }
      maintenance = {
        'latest': maintenanceFields(history.latestMaintenance),
        'unacknowledgedFailure': maintenanceFields(
          history.unacknowledgedFailure,
        ),
        'unacknowledgedFailureCount': history.unacknowledgedFailureCount,
      };
      final sticky = history.unacknowledgedFailure?.error;
      if (sticky != null) failures.add(coreErrorFields(sticky, 'maintenance'));
    }
    if (unexpected != null) Error.throwWithStackTrace(unexpected, stack!);
  }
}
