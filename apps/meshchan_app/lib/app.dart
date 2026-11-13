import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'probe_request.dart';

typedef PlatformProbe = Future<Map<String, Object?>> Function(
  ProbeRequest request,
);

/// Navigation owns no core resources. The injected boundary is invoked once,
/// only for an explicitly validated developer request.
class MeshchanApp extends StatelessWidget {
  const MeshchanApp({super.key, this.request, required this.probe});
  final ProbeRequest? request;
  final PlatformProbe probe;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meshchan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff326b61),
      useMaterial3: true,
    ),
    home: request == null
        ? const _Navigation()
        : _ProbeView(request: request!, probe: probe),
  );
}

class _Navigation extends StatefulWidget {
  const _Navigation();
  @override
  State<_Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<_Navigation> {
  var selected = 0;
  static const titles = ['Drafts', 'Device', 'Diagnostics'];
  static const messages = [
    'Draft storage is not connected yet. Saved drafts are not loaded.',
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
