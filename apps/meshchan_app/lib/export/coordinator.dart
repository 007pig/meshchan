import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';

enum ExportPhase {
  generating,
  choosing,
  staging,
  writing,
  publishing,
  cleaning,
  settled,
}

enum ExportFailure {
  generation,
  invalidSummary,
  panel,
  staging,
  write,
  targetExists,
  unsupported,
  publish,
  observation,
}

final class ExportOutputException implements Exception {
  const ExportOutputException(this.failure);
  final ExportFailure failure;
}

abstract interface class ExportPlatform {
  Future<String?> choose(int job, String suggestedName);
  Future<void> cancelPanel(int job);
  Future<void> publish(int job, String staging, String target);
}

final class MacExportPlatform implements ExportPlatform {
  const MacExportPlatform();
  static const _channel = MethodChannel('org.meshchan.host/platform');
  @override
  Future<String?> choose(int job, String suggestedName) =>
      _channel.invokeMethod<String>('chooseSummaryTarget', {
        'job': job,
        'name': suggestedName,
      });
  @override
  Future<void> cancelPanel(int job) =>
      _channel.invokeMethod<void>('cancelSummaryPanel', {'job': job});
  @override
  Future<void> publish(int job, String staging, String target) async {
    final code = await _channel.invokeMethod<String>('publishSummary', {
      'job': job,
      'staging': staging,
      'target': target,
    });
    if (code != 'published') {
      throw ExportOutputException(switch (code) {
        'targetExists' => ExportFailure.targetExists,
        'unsupported' => ExportFailure.unsupported,
        _ => ExportFailure.publish,
      });
    }
  }
}

final class ExportStaging {
  const ExportStaging(this.directory, this.file);
  final String directory, file;
}

abstract interface class ExportFiles {
  Future<ExportStaging> create(String target);
  Future<void> write(ExportStaging staging, List<int> bytes);
  Future<void> cleanup(ExportStaging staging);
}

final class LocalExportFiles implements ExportFiles {
  const LocalExportFiles();
  @override
  Future<ExportStaging> create(String target) async {
    final directory = await File(target).parent
        .createTemp('.meshchan-summary-');
    return ExportStaging(directory.path, '${directory.path}/summary.json');
  }

  @override
  Future<void> write(ExportStaging staging, List<int> bytes) async {
    await File(staging.file).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> cleanup(ExportStaging staging) async {
    // Never recurse or touch the user's destination, including after publish.
    final type = await FileSystemEntity.type(staging.file, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      await File(staging.file).delete();
    }
    await Directory(staging.directory).delete();
  }
}

final class ExportJob {
  ExportJob(this.id, this.selection);
  final int id;
  final HistorySelection selection;
  ExportPhase phase = ExportPhase.generating;
  bool generated = false,
      canceled = false,
      writerAdmitted = false,
      published = false;
  bool cleanupComplete = false, cleanupWarning = false;
  int? count;
  bool? more;
  String? target;
  RuntimeFault? generationError;
  ExportFailure? failure;
  bool get settled => phase == ExportPhase.settled;
}

/// One application-owned job observes generation, panel, pre-IO, writer,
/// exclusive publication and cleanup independently of pages and DB ownership.
final class ExportCoordinator extends ChangeNotifier {
  ExportCoordinator(
    this.runtime, {
    this.platform = const MacExportPlatform(),
    this.files = const LocalExportFiles(),
  }) {
    _states = runtime.changes.listen((s) {
      if (s.stopReceived ||
          s.phase == RuntimePhase.closed ||
          s.phase == RuntimePhase.closing ||
          s.phase == RuntimePhase.fault) {
        stop();
      }
    });
  }
  final AppRuntime runtime;
  final ExportPlatform platform;
  final ExportFiles files;
  late final StreamSubscription<RuntimeSnapshot> _states;
  ExportJob? job;
  Future<void>? _work;
  final _panelWork = <Future<void>>{};
  int _next = 0;
  bool paused = false, _stopped = false, _disposed = false;
  bool get busy => _work != null || _panelWork.isNotEmpty;
  bool get settled => !busy;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get _allowed => !_stopped && !paused && runtime.ordinaryAdmissionOpen;
  Future<void> start(HistorySelection selection) {
    if (busy || !_allowed) return Future.value();
    final current = job = ExportJob(++_next, selection);
    final completion = Completer<void>();
    _work = completion.future;
    _notify();
    unawaited(
      _run(current).then<void>((_) {
        _work = null;
        completion.complete();
        _notify();
      }),
    );
    return completion.future;
  }

  void cancel() {
    final current = job;
    if (current == null ||
        current.canceled ||
        current.settled ||
        current.writerAdmitted) {
      return;
    }
    current.canceled = true;
    if (current.phase == ExportPhase.choosing) {
      final work = _cancelPanel(current);
      _panelWork.add(work);
      unawaited(
        work.then<void>((_) {
          _panelWork.remove(work);
          _notify();
        }),
      );
    }
    _notify();
  }

  Future<void> _cancelPanel(ExportJob current) async {
    try {
      await platform.cancelPanel(current.id);
    } catch (_) {
      current.failure ??= ExportFailure.panel;
    }
  }

  void stop() {
    _stopped = true;
    paused = true;
    cancel();
  }

  Future<void> drain() async {
    await _work;
    while (_panelWork.isNotEmpty) {
      await Future.wait(_panelWork.toList());
    }
  }

  bool _canProceed(ExportJob current) {
    if (!current.canceled && _allowed) return true;
    current.canceled = true;
    return false;
  }

  Future<void> _run(ExportJob current) async {
    ExportStaging? staging;
    try {
      if (!_canProceed(current)) return;
      DiagnosticSummaryPage summary;
      try {
        summary = (await runtime.historyRequest(
          ExportHistoryPage(current.selection),
        ) as HistoryExportValue).page;
      } catch (e) {
        current.generationError = RuntimeFault.from(e);
        current.failure = ExportFailure.generation;
        return;
      }
      current.generated = true;
      try {
        final data = jsonDecode(summary.json) as Map<String, dynamic>;
        current.count = (data['runs'] as List).length;
        current.more = summary.nextCursor != null;
      } catch (_) {
        current.failure = ExportFailure.invalidSummary;
        return;
      }
      if (!_canProceed(current)) return;
      current.phase = ExportPhase.choosing;
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final choosing = platform.choose(
        current.id,
        'meshchan-summary-$stamp.json',
      );
      // A listener may cancel immediately. Submit choose before exposing the
      // phase so the platform receives cancellation after the matching request.
      _notify();
      current.target = await choosing;
      if (current.target == null) {
        current.canceled = true;
        return;
      }
      if (!_canProceed(current)) return;
      current.phase = ExportPhase.staging;
      _notify();
      if (!_canProceed(current)) return;
      staging = await files.create(current.target!);
      if (!_canProceed(current)) return;
      // The last synchronous cancellation check and writer invocation have no
      // await between them. This is admission, not an OS first-byte claim.
      current.writerAdmitted = true;
      current.phase = ExportPhase.writing;
      final writing = files.write(staging, utf8.encode(summary.json));
      _notify();
      await writing;
      current.phase = ExportPhase.publishing;
      _notify();
      await platform.publish(current.id, staging.file, current.target!);
      current.published = true;
    } on ExportOutputException catch (e) {
      current.failure = e.failure;
    } catch (_) {
      current.failure = switch (current.phase) {
        ExportPhase.choosing => ExportFailure.panel,
        ExportPhase.staging => ExportFailure.staging,
        ExportPhase.writing => ExportFailure.write,
        ExportPhase.publishing => ExportFailure.publish,
        _ => ExportFailure.observation,
      };
    } finally {
      if (staging != null) {
        current.phase = ExportPhase.cleaning;
        _notify();
        try {
          await files.cleanup(staging);
          current.cleanupComplete = true;
        } catch (_) {
          current.cleanupWarning = true;
        }
      } else {
        current.cleanupComplete = true;
      }
      current.phase = ExportPhase.settled;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_states.cancel());
    // Application shutdown drains work; disposal never starts IO or cleanup.
    super.dispose();
  }
}
