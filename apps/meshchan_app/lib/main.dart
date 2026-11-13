import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'host_bootstrap.dart';
import 'platform_probe.dart';
import 'probe_request.dart';
import 'launch_configuration.dart';
import 'runtime/controller.dart';
import 'runtime/verification.dart';

const _hostChannel = MethodChannel('org.meshchan.host/platform');
final _probeCompletion = Completer<bool>();

void _installQuit(
  Future<bool> Function() canQuit, {
  void Function()? onFailure,
}) {
  _hostChannel.setMethodCallHandler((call) async {
    if (call.method == 'requestQuit') return canQuit();
    throw MissingPluginException();
  });
  unawaited(
    _hostChannel
        .invokeMethod<void>('runtimeReady')
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace s) {
            onFailure?.call();
          },
        ),
  );
}

void _requestNativeQuit(RuntimeController runtime) {
  unawaited(
    _hostChannel
        .invokeMethod<void>('quitApplication')
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace s) {
            runtime.reportHostFailure();
          },
        ),
  );
}

void main(List<String> arguments) {
  try {
    final config = LaunchConfiguration.parse(
      arguments,
      nativeTestHost:
          Platform.environment.containsKey('MESHCHAN_TEST_HOST') ||
          Platform.environment.containsKey('XCTestConfigurationFilePath') ||
          Platform.environment.containsKey('XCTestBundlePath'),
    );
    WidgetsFlutterBinding.ensureInitialized();
    if (config.mode == LaunchMode.nativeTest) {
      _installQuit(() async => true);
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Native test host: storage disabled before bootstrap.',
              ),
            ),
          ),
        ),
      );
      return;
    }
    final bootstrap = HostResourceBootstrap(
      firstFrame: () => WidgetsBinding.instance.waitUntilFirstFrameRasterized,
      authorize: () async =>
          await _hostChannel.invokeMethod<bool>('authorizeResourceBootstrap') ==
          true,
    );
    if (config.mode == LaunchMode.probe) {
      var probeStarted = false;
      _installQuit(() {
        bootstrap.stop();
        if (!probeStarted && !_probeCompletion.isCompleted) {
          _probeCompletion.complete(true); // No resources can start after stop.
        }
        return _probeCompletion.future;
      });
      runApp(
        MeshchanApp(
          request: config.probe,
          probe: (request) async {
            await bootstrap.prepare();
            if (bootstrap.stopped) {
              return {'passed': false, 'error': 'probe_cancelled_before_start'};
            }
            probeStarted = true;
            return _probe(request);
          },
        ),
      );
      return;
    }
    // Explicit verification-only directory barrier. It owns no resources and
    // is released after quit intent is saved, making startup races repeatable.
    final directoryGate =
        const {'quit-starting', 'hold-startup'}.contains(config.verification)
        ? Completer<void>()
        : null;
    final runtime = RuntimeController(
      prepareForResources: bootstrap.prepare,
      resolveDirectory: () async {
        if (directoryGate != null) await directoryGate.future;
        if (config.directory != null) return config.directory!;
        final facts = await const MethodChannel('org.meshchan.host/platform')
            .invokeMapMethod<String, Object?>('directoryFacts');
        final path = facts?['cliCompatibilityTarget'];
        if (path is! String) {
          throw const FormatException('Directory resolution failed.');
        }
        LaunchConfiguration.validateDirectory(path);
        return path;
      },
      fixtureWrites: config.verification == 'write',
    );
    // Flush an AppKit quit received before Dart's handler was installed.
    var reportedShutdown = false;
    _installQuit(() async {
      final quitPhase = runtime.snapshot.phase;
      final closing = runtime.shutdown();
      bootstrap.stop(); // Runtime has saved intent before this barrier opens.
      if (directoryGate != null && !directoryGate.isCompleted) {
        directoryGate.complete();
      }
      final result = await closing;
      if (!reportedShutdown) {
        reportedShutdown = true;
        try {
          stdout.writeln(
            jsonEncode({
              'runtime': 'meshchan.shutdown.1d3',
              'quitPhase': quitPhase.name,
              'resourcesReleased': result.resourcesReleased,
              'workerExited': result.workerExited,
              'workerWasSpawned': result.workerWasSpawned,
              'owner': runtime.snapshot.owner.name,
              'error': runtime.snapshot.error?.code,
              'maintenanceFailureCount':
                  runtime.snapshot.maintenance?.failureCount,
              'pendingRequests': runtime.pendingCount,
              'receivePorts': runtime.openPortCount,
            }),
          );
          await stdout.flush();
        } catch (_) {
          // Logging cannot change the already confirmed resource conclusion.
        }
      }
      return result.canExit;
    }, onFailure: runtime.reportHostFailure);
    if (config.verification == 'quit-starting') {
      // Bounded native acceptance of quit before bootstrap has settled. The
      // ordinary owner/coordinator is used, without a delay or fake resource.
      unawaited(runtime.start());
      runApp(MeshchanApp(probe: _probe, runtime: runtime));
      _requestNativeQuit(runtime);
      return;
    }
    if (config.verification == 'quit-ready') {
      // Exercise AppKit's deferred reply with a live owner, not a runtime that
      // verification already closed. The native request starts the sole close.
      runApp(MeshchanApp(probe: _probe, runtime: runtime));
      unawaited(runtime.start().then<void>((_) => _requestNativeQuit(runtime)));
      return;
    }
    if (config.mode == LaunchMode.runtimeVerification &&
        !const {'hold', 'hold-startup'}.contains(config.verification)) {
      // The verification owns startup so receipt validation precedes any open.
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Verifying the application runtime…')),
          ),
        ),
      );
      unawaited(
        verifyRuntime(config, runtime).then<void>(
          (passed) {
            if (config.exitWhenDone) {
              // Uses the normal native/Dart shutdown barrier, never probe's exit().
              _requestNativeQuit(runtime);
            }
          },
          onError: (Object _, StackTrace s) {
            runtime.reportHostFailure();
            runApp(MeshchanApp(probe: _probe, runtime: runtime));
          },
        ),
      );
    } else {
      runApp(MeshchanApp(probe: _probe, runtime: runtime));
    }
  } on FormatException catch (error) {
    WidgetsFlutterBinding.ensureInitialized();
    _installQuit(() async => true); // Parsing failed before resources existed.
    stdout.writeln(
      jsonEncode({
        'probe': 'meshchan.macos.1d2',
        'passed': false,
        'error': 'invalid_arguments',
      }),
    );
    if (arguments.contains('--probe-exit')) exit(64);
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(error.message))),
      ),
    );
  }
}

Future<Map<String, Object?>> _probe(ProbeRequest request) async {
  Map<String, Object?> result;
  try {
    final facts = await const MethodChannel('org.meshchan.host/platform')
        .invokeMapMethod<String, Object?>('directoryFacts');
    result = {
      ...await runPlatformProbe(request),
      'platformDirectories': facts,
      'dartHome': Platform.environment['HOME'],
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    };
  } catch (_) {
    result = {
      'probe': 'meshchan.macos.1d2',
      'passed': false,
      'error': 'platform_probe_failed',
    };
  }
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
  final closes = result['closes'];
  final failures = result['failures'];
  _probeCompletion.complete(
    (closes is! List || closes.every((state) => state == 'closed')) &&
        (failures is! List ||
            failures.every(
              (failure) =>
                  failure is Map && failure['cleanupUnconfirmed'] != true,
            )),
  );
  // Probe-only exit follows the worker's actual finalization report. Failure
  // does not imply cleanup. Full desktop quit interaction remains 1D.9.
  if (request.exitWhenDone) exit(result['passed'] == true ? 0 : 1);
  return result;
}
