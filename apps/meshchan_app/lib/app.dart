import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';

import 'widgets/selectable_label.dart';

import 'probe_request.dart';
import 'desktop/commands.dart';
import 'profiles/navigation.dart';

import 'package:flutter/services.dart';

import 'drafts/editor.dart';
import 'device/view.dart';
import 'history/diagnostics_panel.dart';
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
    this.desktopCommands,
  });
  final DesktopCommands? desktopCommands;
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
        ? _Navigation(
            runtime: runtime,
            quitCoordinator: quitCoordinator,
            commands: desktopCommands,
          )
        : _ProbeView(request: request!, probe: probe),
  );
}

class _Navigation extends StatefulWidget {
  const _Navigation({
    required this.runtime,
    this.quitCoordinator,
    this.commands,
  });
  final DesktopCommands? commands;
  final AppRuntime? runtime;
  final DraftQuitCoordinator? quitCoordinator;
  @override
  State<_Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<_Navigation> {
  var selected = 0;
  bool navigating = false;
  late final DesktopCommands commands;
  ProfilesNavigation? auxiliary;
  Listenable? commandSources;
  bool get current =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      !commands.sheetActive;
  bool get canNavigate =>
      current &&
      !navigating &&
      auxiliary?.busy != true &&
      quit?.editor.quitting == false &&
      quit?.editor.deciding == false &&
      quit?.editor.confirming == false &&
      quit?.profiles.confirming == false &&
      quit?.profiles.deciding == false &&
      quit?.history.confirming == false &&
      quit != null;
  bool get canSave =>
      current &&
      !navigating &&
      auxiliary?.busy != true &&
      widget.runtime?.ordinaryAdmissionOpen == true &&
      (selected == 0
          ? quit?.editor.canSave == true && !quit!.editor.composing
          : selected == 3 &&
                auxiliary?.page != 2 &&
                quit!.profiles.hasDocument &&
                quit!.profiles.canOperate &&
                !quit!.profiles.composing);
  Future<bool> save() async {
    if (!current ||
        navigating ||
        auxiliary?.busy == true ||
        widget.runtime?.ordinaryAdmissionOpen != true) {
      return false;
    }
    if (selected == 0 && quit!.editor.canSave) return quit!.editor.save();
    if (selected == 3 &&
        auxiliary?.page != 2 &&
        quit!.profiles.hasDocument &&
        quit!.profiles.canOperate) {
      return quit!.profiles.save();
    }
    return false;
  }

  Future<bool> dispatch(String command) async {
    if (command == 'save') return save();
    if (command == 'cancelDialog') {
      if (!mounted ||
          commands.sheetActive ||
          ModalRoute.of(context)?.isCurrent != false ||
          !commands.canCancelDialog) {
        return false;
      }
      Navigator.of(context)
          .pop(); // Null means Continue/Cancel in existing dialogs.
      return true;
    }
    if (command != 'settings' || !canNavigate) return false;
    navigating = true;
    commands.refresh();
    try {
      final source = selected;
      if (source != 3 && !await quit!.leaveCurrent(prompt)) return false;
      if (!mounted || !current || quit!.editor.quitting) return false;
      final document = quit!.editor.documentGeneration;
      final draftId = quit!.editor.selectedId;
      if (!await auxiliary!.open(1, prompt)) return false;
      if (!mounted || !current || quit!.editor.quitting) return false;
      if (source != 3) {
        // The source page stays editable while Settings loads. A replacement
        // document cancels this navigation; new edits/composition require a new
        // live departure decision before the visible editor can be unmounted.
        if (selected != source ||
            (source == 0 &&
                (quit!.editor.documentGeneration != document ||
                    quit!.editor.selectedId != draftId ||
                    quit!.editor.reading))) {
          return false;
        }
        if (!await quit!.leaveCurrent(prompt)) return false;
        if (!mounted || !current || quit!.editor.quitting) return false;
      }
      quit!.auxiliaryActive = true;
      setState(() => selected = 3);
      return true;
    } finally {
      navigating = false;
      commands.refresh();
    }
  }

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
    commands = widget.commands ?? DesktopCommands();
    commands.dispatch = dispatch;
    commands.saveEnabled = () => canSave;
    commands.cancelDialogEnabled = () =>
        quit != null &&
        (quit!.editor.deciding ||
            quit!.editor.confirming ||
            quit!.profiles.deciding ||
            quit!.profiles.confirming ||
            quit!.history.confirming);
    commands.settingsEnabled = () =>
        canNavigate &&
        !quit!.editor.composing &&
        !quit!.profiles.composing &&
        !quit!.preview.composing &&
        !quit!.device.composing &&
        !quit!.diagnostics.composing &&
        !quit!.history.composing;
    final runtime = widget.runtime;
    if (runtime == null) return;
    quit = widget.quitCoordinator ?? DraftQuitCoordinator(runtime);
    quit!.prompt = prompt;
    auxiliary = ProfilesNavigation(quit!.profiles, quit!.preview);
    commandSources = Listenable.merge([
      quit!.editor,
      quit!.profiles,
      quit!.preview,
      quit!.history,
      quit!.device,
      quit!.diagnostics,
      auxiliary,
    ]);
    commandSources!.addListener(commands.refresh);
    state = runtime.snapshot;
    states = runtime.changes.listen((v) {
      if (mounted) setState(() => state = v);
      commands.refresh();
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
    if (selected == value || !canNavigate) return;
    navigating = true;
    commands.refresh();
    try {
      if (!await quit!.leaveCurrent(prompt) ||
          !mounted ||
          !current ||
          quit!.editor.quitting) {
        return;
      }
      quit!.auxiliaryActive = value == 3;
      setState(() => selected = value);
    } finally {
      navigating = false;
      commands.refresh();
    }
  }

  @override
  void dispose() {
    commandSources?.removeListener(commands.refresh);
    commands.dispatch = null;
    commands.saveEnabled = commands.settingsEnabled =
        commands.cancelDialogEnabled = null;
    auxiliary?.dispose();
    if (widget.commands == null) commands.dispose();
    unawaited(states?.cancel());
    lifecycle?.dispose();
    quit?.prompt = null;
    // No owner/worker cleanup belongs to a Widget's dispose.
    if (widget.quitCoordinator == null) quit?.disposeEditors();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) commands.refresh();
    });
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveIntent(),
        SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _SettingsIntent(),
      },
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) {
              unawaited(commands.invoke('save'));
              return null;
            },
          ),
          _SettingsIntent: CallbackAction<_SettingsIntent>(
            onInvoke: (_) {
              unawaited(commands.invoke('settings'));
              return null;
            },
          ),
        },
        child: Scaffold(
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
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 156),
                        child: SingleChildScrollView(
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
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              Text(_status(state)),
                              if (state != null)
                                Text('Owner: ${state!.owner.name}'),
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
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (selected == 0 && quit != null)
                        Expanded(
                          child: DraftsView(
                            editor: quit!.editor,
                            prompt: prompt,
                            onSave: () => commands.invoke('save'),
                          ),
                        )
                      else if (selected == 3 && quit != null)
                        Expanded(
                          child: ProfilesView(
                            editor: quit!.profiles,
                            navigation: auxiliary,
                            onSave: () => commands.invoke('save'),
                            preview: quit!.preview,
                            prompt: prompt,
                          ),
                        )
                      else if (selected == 2 && quit != null)
                        Expanded(
                          child: DiagnosticsPanel(
                            coordinator: quit!,
                            chooseDevice: () => navigate(1),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
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
      child: SelectableLabel(
        result == null
            ? 'Running the finite fixture probe…'
            : const JsonEncoder.withIndent('  ').convert(result),
      ),
    ),
  );
}
