import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_app/drafts/editor.dart';
import 'package:meshchan_app/drafts/quit_coordinator.dart';
import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../tool/diagnostic_fixture.dart';
import '../tool/device_scenario.dart';
import '../tool/profile_fixture.dart';

void main() {
  for (final resolveStage in [true, false]) {
    for (final target in EditorTarget.values) {
      for (final choice in LeaveChoice.values) {
        test(
          'recording resolve=$resolveStage + dirty $target + quit $choice',
          () async {
            final dir = Directory.systemTemp.createTempSync(
              'meshchan-diagnostic-quit-',
            );
            final port = ReceivePort();
            final ready = port.first;
            final runtime = RuntimeController(
              resolveDirectory: () async => dir.path,
              entry: diagnosticFixtureEntry(
                port.sendPort,
                holdResolve: resolveStage,
                holdCleanup: true,
              ),
            );
            await runtime.start();
            final commands = ((await ready) as DiagnosticReady).port;
            port.close();
            final quit = DraftQuitCoordinator(runtime)
              ..auxiliaryActive = target != EditorTarget.draft;
            Future<LeaveChoice> discard({required bool unknown}) async =>
                LeaveChoice.discard;
            if (target == EditorTarget.draft) {
              await quit.editor.newDraft(discard);
              quit.editor.body.text = 'saved during check';
            } else if (target == EditorTarget.profile) {
              await quit.profiles.newProfile(discard);
              quit.profiles.form.load(
                fixtureProfile(DiagnosticOperation.send).parameters,
              );
              quit.profiles.name.text = 'saved during check';
            } else {
              await quit.profiles.openSettings(discard);
              quit.profiles.history.text = '1234';
            }
            final handle = runtime.startRecordedDiagnostic(
              ' explicit fixture ',
              diagnosticRequest(),
            );
            await handle.accepted;
            await deviceState(
              runtime,
              (s) => resolveStage
                  ? s.operation?.preparation == DiagnosticPreparation.resolving
                  : s.operation?.summary != null,
            );
            final prompted = Completer<void>();
            var prompts = 0;
            quit.prompt = ({required unknown}) async {
              prompts++;
              if (!prompted.isCompleted) prompted.complete();
              return choice;
            };
            final a = quit.requestQuit(), b = quit.requestQuit();
            await prompted.future;
            commands.send(DiagnosticControl.releaseResolve);
            if (choice == LeaveChoice.continueEditing) {
              expect(await a, false);
              expect(await b, false);
              expect(runtime.snapshot.gate, DeviceGateState.occupied);
              expect(runtime.snapshot.admissionPaused, false);
              await runtime.listDrafts();
              quit.prompt = discard;
              final finishing = quit.requestQuit();
              commands.send(DiagnosticControl.releaseResolve);
              commands.send(DiagnosticControl.releaseCleanup);
              expect(await finishing, true);
            } else {
              await deviceState(runtime, (s) => s.stopReceived);
              expect(runtime.snapshot.owner, OwnerFact.held);
              expect(runtime.snapshot.operation!.resourcesReleased, false);
              commands.send(DiagnosticControl.releaseResolve);
              commands.send(DiagnosticControl.releaseCleanup);
              expect(await a, true);
              expect(await b, true);
            }
            expect(prompts, 1);
            expect(runtime.pendingCount, 0);
            expect(runtime.openPortCount, 0);
            quit.disposeEditors();
            final storage = await CoreStorage.open(dataDirectory: dir);
            final saved = choice == LeaveChoice.save;
            if (target == EditorTarget.draft) {
              expect((await storage.drafts.list()).items.length, saved ? 1 : 0);
            }
            if (target == EditorTarget.profile) {
              expect(
                (await storage.profiles.list()).items.length,
                saved ? 1 : 0,
              );
            }
            if (target == EditorTarget.settings) {
              expect(
                (await storage.settings.read()).diagnosticHistoryLimit,
                saved ? 1234 : 1000,
              );
            }
            expect(
              (await storage.history.query()).items.length,
              resolveStage ? inInclusiveRange(0, 1) : 1,
            );
            await storage.close();
            dir.deleteSync(recursive: true);
          },
        );
      }
    }
  }
}
