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
  String? target = '/owned/new.json';
  ExportFailure? failure;
  Future<void>? publication;
  @override
  Future<String?> choose(int job, String name) async {
    panels++;
    return pending == null ? target : pending!.future;
  }

  @override
  Future<void> cancelPanel(int job) async {
    cancels++;
    if (pending?.isCompleted == false) pending!.complete(null);
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
