import 'package:flutter/material.dart';

import '../profiles/choice.dart';
import '../runtime/protocol.dart';
import 'model.dart';

class DeviceView extends StatelessWidget {
  const DeviceView({super.key, required this.model});
  final DeviceModel model;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final attempt = model.snapshot.deviceCheck;
      final info = model.snapshot.lastDeviceInfo;
      final unknown = model.snapshot.phase == RuntimePhase.fault;
      final released = !unknown && (attempt == null || attempt.released);
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unknown
                  ? 'Runtime fault — retained device cleanup facts below'
                  : released
                  ? 'Not connected'
                  : 'Check ${attempt!.id}: ${attempt.state.name}',
            ),
            if (!model.listed && model.refreshFailure == null)
              const Text('No ports have been listed or opened.'),
            const Text(
              'Refresh lists local metadata. Check briefly opens and initializes only the selected port, then closes it. Opening may reset some boards. No wireless test is performed.',
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: model.canAccess ? model.refresh : null,
                  child: Text(model.refreshing ? 'Refreshing…' : 'Refresh'),
                ),
                GuardedChoice<String>(
                  label: model.selected ?? 'Select a port',
                  choices: [
                    for (final p in model.ports) (value: p.path, label: p.path),
                  ],
                  allowOpen: model.allowAction,
                  onSelected: model.select,
                  enabled: model.ports.isNotEmpty && !model.refreshing,
                ),
              ],
            ),
            SelectableText('Selected port: ${model.selected ?? 'None'}'),
            if (model.stale)
              const Text(
                'Previous metadata is stale. Refresh successfully before checking.',
              ),
            if (model.refreshFailure != null)
              Text('Metadata refresh failed: ${model.refreshFailure!.kind}'),
            if (model.listed &&
                model.ports.isEmpty &&
                model.refreshFailure == null)
              const Text('No available ports were reported.'),
            for (final p in model.ports)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SelectableText(
                  '${p.path}\nDescription: ${p.description ?? 'Unavailable'} · Transport: ${p.transport ?? 'Unknown'} · USB VID: ${p.usbVid ?? 'Unknown'} · PID: ${p.usbPid ?? 'Unknown'}${p.warning == null ? '' : '\nMetadata warning: ${p.warning}'}',
                ),
              ),
            const Text(
              'Paths are not stable device identities. Metadata does not identify or authenticate MeshCore hardware.',
            ),
            const SizedBox(height: 12),
            const Text('Check options (this application session only)'),
            for (final field in [
              (model.request, 'Request timeout (seconds)'),
              (model.initialization, 'Initialization timeout (seconds)'),
              (model.startup, 'Startup delay (milliseconds)'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: field.$1,
                  // Keep marked text live until the action's composition guard.
                  onTapOutside: (_) {},
                  decoration: InputDecoration(
                    labelText: field.$2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            if (model.inputError case final error?) Text(error),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed:
                      model.canAccess &&
                          model.available &&
                          !model.stale &&
                          model.options != null
                      ? model.check
                      : null,
                  child: const Text('Check device'),
                ),
                TextButton(
                  onPressed:
                      model.starting || (attempt != null && !attempt.settled)
                      ? model.cancel
                      : null,
                  child: const Text('Cancel check'),
                ),
              ],
            ),
            if (model.starting && attempt?.id != model.handle?.id)
              const Text('Start requested; awaiting admission.'),
            if (model.cancelRequested != null)
              Text(
                'Cancel requested for check ${model.cancelRequested}. Native calls may delay application of this request.',
              ),
            if (model.actionFailure case final failure?)
              Text('Request failed: ${failure.code}'),
            if (attempt != null) ...[
              const Divider(),
              const Text('Active / last attempt'),
              SelectableText(
                'Check ${attempt.id} · ${attempt.port}\nRequest ${attempt.options.requestSeconds} s · Initialization ${attempt.options.initializationSeconds} s · Startup ${attempt.options.startupMilliseconds} ms\nSession: ${attempt.state.name}\nCancel applied: ${attempt.cancelApplied}\nSession cleanup: ${attempt.sessionCleanup.name}\nHost observer cleanup: ${attempt.observerCleanup.name}',
              ),
              if (attempt.failure != null)
                Text('Initialization: ${_failure(attempt.failure!)}'),
              if (attempt.cleanupFailure != null)
                Text(
                  'Session cleanup: ${_failure(attempt.cleanupFailure!)} (release unconfirmed)',
                ),
              if (attempt.observerFailure != null)
                Text('Host observation: ${_failure(attempt.observerFailure!)}'),
            ],
            if (info != null) ...[
              const Divider(),
              const Text(
                'Last successful information — historical, not a live connection',
              ),
              SelectableText(
                'Source port: ${info.port}\nObserved: ${info.observedAt.toLocal().toIso8601String()} ${info.observedAt.toLocal().timeZoneName} (local time)\nName: ${info.nodeName}\nModel: ${info.hardwareModel}\nFirmware: ${info.firmwareVersion}\nBuild date: ${info.firmwareBuildDate}\nReported protocol code: ${info.protocolVersion}\nInitialization app target: ${info.appTargetVersion}\nTX power: ${info.txPowerDbm} dBm · Maximum: ${info.maxTxPowerDbm} dBm\nFrequency: ${info.radioFrequencyKhz} kHz\nBandwidth: ${info.radioBandwidthHz} Hz\nSpreading factor: ${info.radioSpreadingFactor}\nCoding rate code: ${info.radioCodingRate}\nAdvert type: ${info.advertType}\nMax contacts: ${info.maxContacts} · Max channels: ${info.maxChannels}\nRepeat enabled: ${info.repeatEnabled ?? 'Unavailable'}\nPath hash mode: ${info.pathHashMode ?? 'Unavailable'}',
              ),
            ],
          ],
        ),
      );
    },
  );
}

String _failure(DeviceFailure f) =>
    '${f.kind}${f.stage == null ? '' : ' · ${f.stage}'}${f.commandOpcode == null ? '' : ' · command ${f.commandOpcode}'}${f.expectedResponseOpcode == null ? '' : ' · expected ${f.expectedResponseOpcode}'}${f.deviceErrorCode == null ? '' : ' · device error ${f.deviceErrorCode} ${f.deviceErrorName ?? ''}'}';
