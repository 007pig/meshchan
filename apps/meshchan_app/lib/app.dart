import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'probe_request.dart';
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
  });
  final ProbeRequest? request;
  final PlatformProbe probe;
  final AppRuntime? runtime;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meshchan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff326b61),
      useMaterial3: true,
    ),
    home: request == null
        ? _Navigation(runtime: runtime)
        : _ProbeView(request: request!, probe: probe),
  );
}

class _Navigation extends StatefulWidget {
  const _Navigation({required this.runtime});
  final AppRuntime? runtime;
  @override
  State<_Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<_Navigation> {
  var selected = 0;
  StreamSubscription<RuntimeSnapshot>? states;
  StreamSubscription<OfflineSnapshot>? reads;
  RuntimeSnapshot? state;
  OfflineSnapshot? offline;
  String? readError;
  AppLifecycleListener? lifecycle;
  @override
  void initState() {
    super.initState();
    final runtime = widget.runtime;
    if (runtime == null) return;
    state = runtime.snapshot;
    states = runtime.changes.listen((v) {
      if (mounted) setState(() => state = v);
    });
    reads = runtime.offlineChanges.listen((v) {
      if (mounted) setState(() => offline = v);
    });
    lifecycle = AppLifecycleListener(
      onExitRequested: () async => (await runtime.shutdown()).canExit
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
    unawaited(_start(runtime));
  }

  Future<void> _start(AppRuntime runtime) async {
    try {
      await runtime.start();
      if (runtime.snapshot.phase == RuntimePhase.ready) await runtime.refresh();
    } catch (_) {
      if (mounted) setState(() => readError = 'Initial offline read failed.');
    }
  }

  @override
  void dispose() {
    // The application owns shutdown. Navigation/dispose only remove observers.
    unawaited(states?.cancel());
    unawaited(reads?.cancel());
    lifecycle?.dispose();
    super.dispose();
  }

  static const titles = ['Drafts', 'Device', 'Diagnostics'];
  static const messages = [
    'Draft editing is not connected yet. Offline storage belongs to the application runtime.',
    'Device access is not connected yet. No ports have been listed or opened.',
    'Diagnostics are not connected yet. No checks have been started.',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        NavigationRail(
          labelType: NavigationRailLabelType.all,
          leading: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Meshchan'),
          ),
          selectedIndex: selected,
          onDestinationSelected: (value) => setState(() => selected = value),
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
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[selected],
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                Text(_status(state)),
                if (state?.error case final error?)
                  Text('Runtime error: ${error.code}'),
                if ((state?.maintenance?.failureCount ?? 0) > 0)
                  const Text(
                    'Maintenance warning: an unacknowledged failure is retained.',
                  ),
                if (offline != null)
                  Text(
                    'Offline settings loaded. History limit: ${offline!.historyLimit}. '
                    'Drafts in this page: ${offline!.drafts.length}.',
                  ),
                if (readError != null) Text(readError!),
                const SizedBox(height: 16),
                Text(messages[selected]),
                if (selected == 2) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'History is not connected yet. Saved results are not loaded.',
                  ),
                ],
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
