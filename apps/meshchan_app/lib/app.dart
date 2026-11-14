import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'probe_request.dart';
import 'drafts/editor.dart';
import 'device/view.dart';
import 'profiles/view.dart';
import 'drafts/view.dart';
import 'drafts/quit_coordinator.dart';
import 'runtime/controller.dart';
import 'runtime/protocol.dart';

typedef PlatformProbe = Future<Map<String, Object?>> Function(
  ProbeRequest request,
);

/// Navigation owns no core resources. The injected boundary is invoked once,
/// only for an explicitly validated developer request.
class MeshchanApp extends StatelessWidget {
  const MeshchanApp({
    super.key,
    this.request,
    required this.probe,
    this.runtime,
    this.quitCoordinator,
  });
  final ProbeRequest? request;
  final PlatformProbe probe;
  final AppRuntime? runtime;
  final DraftQuitCoordinator? quitCoordinator;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meshchan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff326b61),
      useMaterial3: true,
    ),
    home: request == null
        ? _Navigation(runtime: runtime, quitCoordinator: quitCoordinator)
        : _ProbeView(request: request!, probe: probe),
  );
}

class _Navigation extends StatefulWidget {
  const _Navigation({required this.runtime, this.quitCoordinator});
  final AppRuntime? runtime;
  final DraftQuitCoordinator? quitCoordinator;
  @override
  State<_Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<_Navigation> {
  var selected = 0;
  StreamSubscription<RuntimeSnapshot>? states;
  RuntimeSnapshot? state;
  AppLifecycleListener? lifecycle;
  DraftQuitCoordinator? quit;
  LeavePrompt get prompt =>
      ({required bool unknown}) => showDraftLeaveDialog(
        context,
        unknown: unknown,
        subject: quit?.auxiliaryActive == true ? 'editor' : 'draft',
      );
  @override
  void initState() {
    super.initState();
    final runtime = widget.runtime;
    if (runtime == null) return;
    quit = widget.quitCoordinator ?? DraftQuitCoordinator(runtime);
    quit!.prompt = prompt;
    state = runtime.snapshot;
    states = runtime.changes.listen((v) {
      if (mounted) setState(() => state = v);
    });
    lifecycle = AppLifecycleListener(
      onExitRequested: () async => await quit!.requestQuit()
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
    unawaited(_start(runtime));
  }

  Future<void> _start(AppRuntime runtime) async {
    await runtime.start();
    if (runtime.snapshot.phase == RuntimePhase.ready) {
      await quit!.editor.refresh();
    }
  }

  Future<void> navigate(int value) async {
    final editor = quit?.editor;
    if (selected == value ||
        editor?.deciding == true ||
        editor?.quitting == true) {
      return;
    }
    if (editor != null && !await quit!.leaveCurrent(prompt)) return;
    if (quit != null) quit!.auxiliaryActive = value == 3;
    if (mounted) setState(() => selected = value);
  }

  @override
  void dispose() {
    unawaited(states?.cancel());
    lifecycle?.dispose();
    quit?.prompt = null;
    // No owner/worker cleanup belongs to a Widget's dispose.
    if (widget.quitCoordinator == null) quit?.disposeEditors();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        NavigationRail(
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: () => navigate(3),
              child: const Text('Profiles and settings'),
            ),
          ),
          selectedIndex: selected == 3 ? null : selected,
          onDestinationSelected: navigate,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.edit_note),
              label: Text('Drafts'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.usb),
              label: Text('Device'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              label: Text('Diagnostics'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  const [
                    'Drafts',
                    'Device',
                    'Diagnostics',
                    'Profiles and settings',
                  ][selected],
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(_status(state)),
                if (state != null) Text('Owner: ${state!.owner.name}'),
                if (state?.deviceCheck case final check?)
                  Text(
                    'Device check ${check.id}: ${check.state.name} · session cleanup ${check.sessionCleanup.name} · host cleanup ${check.observerCleanup.name}',
                  ),
                if (state?.error case final error?)
                  Text(
                    '${state!.phase == RuntimePhase.fault ? 'Runtime fault' : 'Last request error'}: ${error.code}',
                  ),
                if ((state?.maintenance?.failureCount ?? 0) > 0)
                  const Text(
                    'Maintenance warning: an unacknowledged failure is retained.',
                  ),
                const SizedBox(height: 12),
                if (selected == 0 && quit != null)
                  Expanded(
                    child: DraftsView(editor: quit!.editor, prompt: prompt),
                  )
                else if (selected == 3 && quit != null)
                  Expanded(
                    child: ProfilesView(
                      editor: quit!.profiles,
                      preview: quit!.preview,
                      prompt: prompt,
                    ),
                  )
                else if (selected == 1 && quit != null)
                  Expanded(child: DeviceView(model: quit!.device))
                else
                  Text(
                    selected == 1
                        ? 'Device access is not connected yet. No ports have been listed or opened.'
                        : selected == 2
                        ? 'Diagnostics are not connected yet. No checks have been started.'
                        : 'Storage is unavailable.',
                  ),
                if (selected == 2)
                  const Text(
                    'History is not connected yet. Saved results are not loaded.',
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

String _status(RuntimeSnapshot? state) => switch (state?.phase) {
  RuntimePhase.starting || null => 'Starting',
  RuntimePhase.opening => 'Opening storage…',
  RuntimePhase.ready => 'Storage ready',
  RuntimePhase.busy => 'Directory in use',
  RuntimePhase.stopping => 'Stopping',
  RuntimePhase.closing => 'Closing',
  RuntimePhase.closed => 'Closed',
  RuntimePhase.fault => 'Runtime fault — resource release may be unknown',
};

class _ProbeView extends StatefulWidget {
  const _ProbeView({required this.request, required this.probe});
  final ProbeRequest request;
  final PlatformProbe probe;
  @override
  State<_ProbeView> createState() => _ProbeViewState();
}

class _ProbeViewState extends State<_ProbeView> {
  Map<String, Object?>? result;
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    Map<String, Object?> report;
    try {
      report = await widget.probe(widget.request);
    } catch (_) {
      report = {'passed': false, 'error': 'probe_boundary_failed'};
    }
    if (mounted) setState(() => result = report);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Developer platform verification')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SelectableText(
        result == null
            ? 'Running the finite fixture probe…'
            : const JsonEncoder.withIndent('  ').convert(result),
      ),
    ),
  );
}
