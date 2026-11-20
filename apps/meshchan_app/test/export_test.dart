import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/drafts/editor.dart';
import 'package:meshchan_app/export/coordinator.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'support/draft_runtime.dart';

class Panel implements ExportPlatform {
  Completer<String?>? pending;
  int panels = 0, cancels = 0, publishes = 0;
  int? canceledJob;
  String? target = '/owned/new.json';
  ExportFailure? failure;
  Future<void>? publication;
  Future<void>? cancellation;
  @override
  Future<String?> choose(int job, String name) async {
    panels++;
    if (canceledJob == job) throw StateError('Panel was already canceled.');
    return pending == null ? target : pending!.future;
  }

  @override
  Future<void> cancelPanel(int job) async {
    cancels++;
    canceledJob = job;
    if (pending?.isCompleted == false) pending!.complete(null);
    await cancellation;
  }

  @override
  Future<void> publish(int job, String staging, String target) async {
    publishes++;
    await publication;
    if (failure != null) throw ExportOutputException(failure!);
  }
}

class Files implements ExportFiles {
  int creates = 0, writes = 0, cleanups = 0;
  List<int>? bytes;
  Completer<ExportStaging>? creation;
  Future<void>? writing;
  bool cleanupFails = false, writeFails = false;
  @override
  Future<ExportStaging> create(String target) async {
    creates++;
    return creation == null
        ? const ExportStaging('/owned/temp', '/owned/temp/summary.json')
        : creation!.future;
  }

  @override
  Future<void> write(ExportStaging staging, List<int> bytes) {
    writes++;
    this.bytes = bytes;
    if (writeFails) throw StateError('private');
    return writing ?? Future.value();
  }

  @override
  Future<void> cleanup(ExportStaging staging) async {
    cleanups++;
    if (cleanupFails) throw StateError('private');
  }
}

const original =
    '{"diagnosticSummaryFormatVersion":1,"exportedAt":"2026-11-14T20:00:00.000000Z","runs":[]}';
Future<void> turn() => Future<void>.delayed(Duration.zero);
void main() {
  for (final stage in ['summary', 'panel', 'staging']) {
    test('real controller blocks ordinary work before ACK while $stage drains', () async {
      final root = await Directory.systemTemp.createTemp(
        'meshchan-quit-admission-',
      );
      final r = RuntimeController(resolveDirectory: () async => root.path);
      await r.start();
      final panel = Panel(), files = Files();
      if (stage == 'panel') panel.pending = Completer<String?>();
      if (stage == 'staging') files.creation = Completer<ExportStaging>();
      final output = ExportCoordinator(r, platform: panel, files: files);
      final q = DraftQuitCoordinator(r, output: output);
      await q.editor.newDraft(
        ({required unknown}) async => LeaveChoice.discard,
      );
      q.editor.body.text = 'dirty';
      var prompts = 0;
      q.prompt = ({required unknown}) async {
        prompts++;
        return LeaveChoice.continueEditing;
      };
      final work = output.start(const HistorySelection());
      if (stage != 'summary') {
        while (stage == 'panel' ? panel.panels == 0 : files.creates == 0) {
          await turn();
        }
      }
      final quitting = q.requestQuit();
      // No event-loop turn after Begin: the real host has not received an ACK.
      expect(r.ordinaryAdmissionOpen, false);
      final parameters = PingParameterRequest();
      for (final request in <RuntimeRequest>[
        const RefreshDevicePorts(1),
        StartDeviceCheck(1, '/never', const DeviceCheckOptions()),
        StartRecordedDiagnostic(1, '/never', parameters),
        const ListDrafts(),
        const ListProfiles(),
        const ReadSettings(),
        const ReadMaintenanceStatus(),
      ]) {
        await expectLater(r.request(request), throwsA(isA<RuntimeFault>()));
      }
      await r.request(const GetStatus());
      if (stage == 'staging') {
        expect(prompts, 0);
        files.creation!.complete(
          const ExportStaging('/owned/temp', '/owned/temp/summary.json'),
        );
      }
      expect(await quitting, false);
      await work;
      expect(prompts, 1);
      expect(files.writes, 0);
      expect(r.ordinaryAdmissionOpen, true);
      expect(output.job!.canceled, true);
      expect((await r.shutdown()).canExit, true);
      q.disposeEditors();
      await root.delete(recursive: true);
    });
  }
  test('async writer failure settles cleanup without publication', () async {
    final runtime = DraftRuntime(), panel = Panel(), files = Files();
    final writer = Completer<void>();
    files.writing = writer.future;
    runtime.onHistory = (_) async =>
        const HistoryExportValue(DiagnosticSummaryPage(json: original));
    final output = ExportCoordinator(runtime, platform: panel, files: files);
    final work = output.start(const HistorySelection());
    await turn();
    writer.completeError(StateError('private IO failure'));
    await work;
    expect(output.job!.failure, ExportFailure.write);
    expect(output.job!.published, false);
    expect(files.cleanups, 1);
    expect(panel.publishes, 0);
    output.dispose();
    await runtime.states.close();
  });
  test(
    'real controller Stop intent blocks writer before worker snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'meshchan-export-stop-',
      );
      final runtime = RuntimeController(
        resolveDirectory: () async => root.path,
      );
      await runtime.start();
      final panel = Panel(), files = Files();
      files.creation = Completer<ExportStaging>();
      final output = ExportCoordinator(runtime, platform: panel, files: files);
      final work = output.start(const HistorySelection());
      while (files.creates == 0) {
        await turn();
      }
      final stopping = runtime.stop();
      files.creation!.complete(
        const ExportStaging('/owned/temp', '/owned/temp/summary.json'),
      );
      await work;
      await stopping;
      expect(files.writes, 0);
      expect(files.cleanups, 1);
      expect(output.job!.canceled, true);
      expect((await runtime.shutdown()).canExit, true);
      output.dispose();
      await root.delete(recursive: true);
    },
  );
  test('fresh selection captured, exact UTF8, one job, published fact survives cleanup warning', () async {
    final r = DraftRuntime(),
        panel = Panel(),
        files = Files()..cleanupFails = true;
    final pending = Completer<ReplyValue>();
    HistorySelection? actual;
    r.onHistory = (q) {
      actual = (q as ExportHistoryPage).selection;
      return pending.future;
    };
    final out = ExportCoordinator(r, platform: panel, files: files);
    final s = HistorySelection(
      size: 200,
      after: HistoryCursor(
        preparedAt: DateTime.utc(2026),
        runId: LocalId('1' * 32),
      ),
    );
    final work = out.start(s);
    await out.start(const HistorySelection());
    pending.complete(
      const HistoryExportValue(DiagnosticSummaryPage(json: original)),
    );
    await work;
    expect(identical(actual, s), true);
    expect(panel.panels, 1);
    expect(files.bytes, utf8.encode(original));
    expect(out.job!.published, true);
    expect(out.job!.cleanupWarning, true);
    expect(out.job!.count, 0);
    expect(out.job!.more, false);
    expect(out.settled, true);
    out.dispose();
    await r.states.close();
  });
  for (final stage in ['summary', 'panel', 'staging']) {
    test(
      'cancel during $stage observes accepted work with zero writer calls',
      () async {
        final r = DraftRuntime(), panel = Panel(), files = Files();
        final summary = Completer<ReplyValue>();
        r.onHistory = (_) => summary.future;
        if (stage == 'panel') {
          panel.pending = Completer<String?>();
        }
        if (stage == 'staging') files.creation = Completer<ExportStaging>();
        final out = ExportCoordinator(r, platform: panel, files: files);
        final work = out.start(const HistorySelection());
        if (stage != 'summary') {
          summary.complete(
            const HistoryExportValue(DiagnosticSummaryPage(json: original)),
          );
          await turn();
        }
        out.cancel();
        if (stage == 'summary') {
          summary.complete(
            const HistoryExportValue(DiagnosticSummaryPage(json: original)),
          );
        }
        if (stage == 'staging') {
          expect(out.settled, false);
          files.creation!.complete(
            const ExportStaging('/owned/temp', '/owned/temp/summary.json'),
          );
        }
        await work;
        await out.drain();
        expect(files.writes, 0);
        expect(panel.publishes, 0);
        expect(out.job!.canceled, true);
        expect(out.settled, true);
        expect(files.cleanups, stage == 'staging' ? 1 : 0);
        out.dispose();
        await r.states.close();
      },
    );
  }
  test('cancel from a choosing listener reaches the opened panel', () async {
    final runtime = DraftRuntime();
    runtime.onHistory = (_) async =>
        const HistoryExportValue(DiagnosticSummaryPage(json: original));
    final panel = Panel()..pending = Completer<String?>();
    final files = Files();
    final output = ExportCoordinator(runtime, platform: panel, files: files);
    output.addListener(() {
      final job = output.job!;
      if (job.phase == ExportPhase.choosing && !job.canceled) output.cancel();
    });

    await output.start(const HistorySelection());
    await output.drain();

    expect(panel.cancels, 1);
    expect(output.job!.canceled, isTrue);
    expect(output.job!.failure, isNull);
    expect(files.creates, 0);
    output.dispose();
    await runtime.states.close();
  });

  for (final phase in [ExportPhase.generating, ExportPhase.staging]) {
    test('synchronous cancel during $phase prevents new work', () async {
      final runtime = DraftRuntime();
      var queries = 0;
      runtime.onHistory = (_) async {
        queries++;
        return const HistoryExportValue(DiagnosticSummaryPage(json: original));
      };
      final panel = Panel(), files = Files();
      final output = ExportCoordinator(runtime, platform: panel, files: files);
      output.addListener(() {
        if (output.job!.phase == phase) output.cancel();
      });

      await output.start(const HistorySelection());

      expect(output.job!.canceled, isTrue);
      expect(output.job!.failure, isNull);
      expect(queries, phase == ExportPhase.generating ? 0 : 1);
      expect(panel.panels, queries);
      expect(files.creates, 0);
      expect(output.settled, isTrue);
      output.dispose();
      await runtime.states.close();
    });
  }

  test(
    'pending native cancellation keeps the current export job owned',
    () async {
      final runtime = DraftRuntime();
      runtime.onHistory = (_) async =>
          const HistoryExportValue(DiagnosticSummaryPage(json: original));
      final cancelAck = Completer<void>();
      final panel = Panel()
        ..pending = Completer<String?>()
        ..cancellation = cancelAck.future;
      final output = ExportCoordinator(
        runtime,
        platform: panel,
        files: Files(),
      );

      final first = output.start(const HistorySelection());
      await turn();
      final canceled = output.job;
      output.cancel();
      await first;
      expect(output.busy, isTrue);
      await output.start(const HistorySelection());
      expect(output.job, same(canceled));
      expect(panel.panels, 1);

      cancelAck.complete();
      await output.drain();
      panel.pending = null;
      await output.start(const HistorySelection());
      expect(panel.panels, 2);
      expect(output.job!.published, isTrue);
      output.dispose();
      await runtime.states.close();
    },
  );

  for (final failure in [
    ExportFailure.targetExists,
    ExportFailure.unsupported,
    ExportFailure.publish,
  ]) {
    test('publish $failure is controlled without fallback', () async {
      final r = DraftRuntime(),
          panel = Panel()..failure = failure,
          files = Files();
      r.onHistory = (_) async =>
          const HistoryExportValue(DiagnosticSummaryPage(json: original));
      final out = ExportCoordinator(r, platform: panel, files: files);
      await out.start(const HistorySelection());
      expect(out.job!.failure, failure);
      expect(out.job!.published, false);
      expect(panel.publishes, 1);
      expect(files.cleanups, 1);
      out.dispose();
      await r.states.close();
    });
  }
  test('generation fails without panel or IO; write sync error is observed and cleaned', () async {
    final r = DraftRuntime(),
        panel = Panel(),
        files = Files()..writeFails = true;
    r.onHistory = (_) async =>
        throw const CoreException(CoreErrorCode.storageReadFailed);
    final out = ExportCoordinator(r, platform: panel, files: files);
    await out.start(const HistorySelection());
    expect(panel.panels, 0);
    expect(files.creates, 0);
    expect(out.job!.failure, ExportFailure.generation);
    r.onHistory = (_) async =>
        const HistoryExportValue(DiagnosticSummaryPage(json: original));
    await out.start(const HistorySelection());
    expect(out.job!.failure, ExportFailure.write);
    expect(files.cleanups, 1);
    expect(panel.publishes, 0);
    out.dispose();
    await r.states.close();
  });
  test('first and reentrant Quit wait for writer after runtime closes; live composition veto has no cancellation', () async {
    final r = DraftRuntime(), panel = Panel(), files = Files();
    final writer = Completer<void>();
    files.writing = writer.future;
    r.onHistory = (_) async =>
        const HistoryExportValue(DiagnosticSummaryPage(json: original));
    final out = ExportCoordinator(r, platform: panel, files: files);
    final q = DraftQuitCoordinator(r, output: out);
    final work = out.start(const HistorySelection());
    await turn();
    expect(files.writes, 1);
    q.history.from.value = const TextEditingValue(
      text: 'zhong',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    expect(await q.requestQuit(), false);
    expect(out.job!.canceled, false);
    expect(r.shutdowns, 0);
    q.history.from.clear();
    var quitDone = false;
    final quit = q.requestQuit().then((v) {
      quitDone = true;
      return v;
    });
    await turn();
    expect(r.shutdowns, 1);
    expect(quitDone, false);
    final again = q.requestQuit();
    expect(identical(quit, again), false);
    expect(out.job!.canceled, false);
    writer.complete();
    expect(await quit, true);
    expect(await again, true);
    await work;
    expect(await q.requestQuit(), true);
    expect(out.job!.published, true);
    expect(out.settled, true);
    q.disposeEditors();
    await r.states.close();
  });
  test(
    'Quit requested during export cancellation shares the active attempt',
    () async {
      final r = DraftRuntime();
      final panel = Panel()..pending = Completer<String?>();
      r.onHistory = (_) async =>
          const HistoryExportValue(DiagnosticSummaryPage(json: original));
      final out = ExportCoordinator(r, platform: panel, files: Files());
      final q = DraftQuitCoordinator(r, output: out);
      addTearDown(r.states.close);
      addTearDown(q.disposeEditors);
      final work = out.start(const HistorySelection());
      await turn();
      expect(panel.panels, 1);

      Future<bool>? reentrant;
      out.addListener(() {
        if (out.job!.canceled) reentrant ??= q.requestQuit();
      });
      final quit = q.requestQuit();
      final concurrentQuit = reentrant;
      expect(await quit, true);
      await work;
      expect(concurrentQuit, same(quit));
      expect(r.begins, 1);
      expect(r.shutdowns, 1);
      expect(panel.cancels, 1);
    },
  );
  test(
    'History observers can start exports again only after Quit is canceled',
    () async {
      final r = DraftRuntime();
      final out = ExportCoordinator(r, platform: Panel(), files: Files());
      final q = DraftQuitCoordinator(r, output: out);
      addTearDown(r.states.close);
      addTearDown(q.disposeEditors);
      await q.editor.newDraft(
        ({required unknown}) async => LeaveChoice.discard,
      );
      q.editor.body.text = 'dirty';
      q.prompt = ({required unknown}) async => LeaveChoice.continueEditing;

      var requests = 0;
      r.onHistory = (_) async {
        requests++;
        return const HistoryExportValue(DiagnosticSummaryPage(json: original));
      };
      Future<void>? duringQuit, afterCancel;
      q.history.addListener(() {
        if (q.history.blocked) {
          duringQuit ??= out.start(const HistorySelection());
        } else if (duringQuit != null) {
          afterCancel ??= out.start(const HistorySelection());
        }
      });

      expect(await q.requestQuit(), false);
      expect(duringQuit, isNotNull);
      expect(afterCancel, isNotNull);
      await afterCancel;
      expect(requests, 1);
      expect(out.job?.published, isTrue);
    },
  );
  test(
    'Quit cancels summary; Continue never regenerates or reopens panel',
    () async {
      final r = DraftRuntime(),
          panel = Panel(),
          files = Files(),
          summary = Completer<ReplyValue>();
      r.onHistory = (_) => summary.future;
      final out = ExportCoordinator(r, platform: panel, files: files),
          q = DraftQuitCoordinator(r);
      q.disposeEditors();
      final coordinator = DraftQuitCoordinator(r, output: out);
      await coordinator.editor.newDraft(
        ({required unknown}) async => LeaveChoice.discard,
      );
      coordinator.editor.body.text = 'dirty';
      coordinator.prompt = ({required unknown}) async =>
          LeaveChoice.continueEditing;
      final work = out.start(const HistorySelection());
      final quit = coordinator.requestQuit();
      expect(
        r.begins,
        1,
        reason: 'Freeze ordinary admission before summary drain',
      );
      expect(r.snapshot.admissionPaused, true);
      summary.complete(
        const HistoryExportValue(DiagnosticSummaryPage(json: original)),
      );
      expect(await quit, false);
      await work;
      expect(panel.panels, 0);
      expect(files.writes, 0);
      expect(out.job!.canceled, true);
      coordinator.disposeEditors();
      await r.states.close();
    },
  );
  test('real staging writes exact bytes and cleanup does not recurse over unknown content', () async {
    final root = await Directory.systemTemp.createTemp(
      'meshchan-export-files-',
    );
    const io = LocalExportFiles();
    final s = await io.create('${root.path}/new.json');
    expect(Directory(s.directory).parent.path, root.path);
    await io.write(s, utf8.encode(original));
    expect(await File(s.file).readAsBytes(), utf8.encode(original));
    await File('${s.directory}/unknown').writeAsString('keep');
    await expectLater(io.cleanup(s), throwsA(isA<FileSystemException>()));
    expect(await File('${s.directory}/unknown').readAsString(), 'keep');
    await root.delete(recursive: true); // Test owns the complete fixture.
  });
}
