import 'package:material_ui/material_ui.dart';

import '../widgets/selectable_label.dart';

import 'package:meshchan_core/meshchan_core.dart';

import '../profiles/choice.dart';
import '../profiles/editor.dart';
import '../profiles/parameter_form.dart';
import '../profiles/preview.dart';
import '../runtime/protocol.dart';
import 'model.dart';
import 'outcomes.dart';

class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({
    super.key,
    required this.model,
    required this.profiles,
    required this.chooseDevice,
  });
  final DiagnosticsModel model;
  final ProfilesEditor profiles;
  final VoidCallback chooseDevice;

  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView> {
  late final _overrides = _GuardedExpansionController(
    () => !widget.model.deferChangeForComposition(),
  );

  @override
  void dispose() {
    _overrides.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.model, widget.profiles]),
    builder: (context, _) {
      final m = widget.model;
      final a = m.attempt;
      String bytesLabel() {
        try {
          return m.bytes == null
              ? 'Content: Not provided'
              : 'Content: ${m.bytes!.length} bytes';
        } catch (_) {
          return 'Content: invalid UTF-8 or hex input';
        }
      }

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PING sends diagnostic data and waits for a response. Responder receives within a finite window and may send PONG. Both save safe diagnostic summaries.',
            ),
            SelectableLabel(
              'Selected session port: ${m.device.selected ?? 'None'}',
            ),
            if (m.device.stale)
              const Text(
                'Port metadata is stale. Refresh on Device before starting.',
              ),
            TextButton(
              onPressed: () {
                if (!m.deferChangeForComposition()) widget.chooseDevice();
              },
              child: const Text('Choose or refresh on Device'),
            ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: m.canStart ? m.startDiagnostic : null,
                  child: const Text('Start and record'),
                ),
                TextButton(
                  onPressed:
                      m.handle != null && (m.starting || a?.done == false)
                      ? m.cancelDiagnostic
                      : null,
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: !m.locked && !m.pending ? m.preview : null,
                  child: const Text('Preview parameters'),
                ),
              ],
            ),
            if (m.starting && a?.attemptId != m.handle?.id)
              const Text('Start requested; awaiting admission.'),
            if (m.cancelRequested != null || a?.cancelRequested == true)
              const Text(
                'Cancel requested. Waiting for actual task, cleanup and save settlement.',
              ),
            if (a != null)
              Text(
                a.done
                    ? 'Observation ended; review independent outcomes.'
                    : a.preparation == DiagnosticPreparation.resolving
                    ? 'Resolving captured parameters.'
                    : a.registration?.state == RecordingSaveState.committed
                    ? 'Record created; finite task or settlement in progress.'
                    : 'Creating record.',
              ),
            if (a?.summary != null && a?.done == false)
              const Text(
                'Logical result available; cleanup and saves settle independently.',
              ),
            if (m.actionFailure != null)
              Text('Request failed: ${m.actionFailure!.code}'),
            if (!m.starting && m.handle != null && a?.attemptId != m.handle!.id)
              Text(
                'Latest Start request ${m.handle!.id}: no matching operation observed.',
              ),
            if (m.notice != null) Text(m.notice!),
            GuardedChoice<DiagnosticOperation>(
              key: const ValueKey('diagnostic-operation'),
              label: m.form.operation.name,
              choices: const [
                (value: DiagnosticOperation.ping, label: 'PING'),
                (value: DiagnosticOperation.respond, label: 'Finite Responder'),
              ],
              enabled: !m.locked,
              allowOpen: m.allowChange,
              onSelected: m.changeOperation,
            ),
            GuardedChoice<String>(
              key: const ValueKey('diagnostic-profile'),
              label: m.profileId ?? 'Use settings default (may be no preset)',
              expanded: true,
              choices: [
                (value: '', label: 'Use settings default (may be no preset)'),
                for (final p in widget.profiles.items)
                  (
                    value: p.id.value,
                    label: '${p.name} • ${p.operation.name} • ${p.id.value}',
                  ),
              ],
              enabled: !m.locked,
              allowOpen: m.allowChange,
              onSelected: (id) => m.select(id.isEmpty ? null : id),
            ),
            TextButton(
              onPressed: !m.locked
                  ? () {
                      if (m.allowChange()) widget.profiles.refresh();
                    }
                  : null,
              child: const Text('Refresh preset choices'),
            ),
            if (m.selectionError != null)
              Text('Selection display read failed: ${m.selectionError}'),
            const Text(
              'Explicit overrides → saved/default preset → core defaults. Test IDs are labels, not authentication. Channels are local slots and do not establish matching radio configuration. Device check options do not set diagnostic budgets.',
            ),
            if (m.form.operation == DiagnosticOperation.ping) ...[
              GuardedChoice<ContentMode>(
                key: const ValueKey('diagnostic-content-mode'),
                label: m.mode.name,
                choices: const [
                  (value: ContentMode.notProvided, label: 'Not provided'),
                  (value: ContentMode.text, label: 'Text (UTF-8)'),
                  (value: ContentMode.hex, label: 'Hex'),
                ],
                enabled: !m.locked,
                allowOpen: m.allowChange,
                onSelected: (mode) {
                  m.mode = mode;
                  m.invalidate();
                },
              ),
              if (m.mode != ContentMode.notProvided)
                TextField(
                  key: const ValueKey('diagnostic-content'),
                  controller: m.content,
                  readOnly: m.locked,
                  onTapOutside: (_) {},
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'PING content',
                    helperText: 'Exact input. Explicit empty content is valid; missing content is different.',
                  ),
                ),
              Text(bytesLabel()),
            ],
            ExpansionTile(
              controller: _overrides,
              title: const Text('Invocation field overrides'),
              children: [
                for (final f in m.form.fields) ...[
                  CheckboxListTile(
                    title: Text('Override ${f.name}'),
                    subtitle: Text(
                      'Inherited display: ${m.inherited == null ? 'core default or required' : m.form.values(m.inherited!.parameters)[f] ?? 'required'}',
                    ),
                    value: m.form.explicit.contains(f),
                    onChanged: m.locked
                        ? null
                        : (v) {
                            if (!m.allowChange()) return;
                            if (v!) {
                              m.form.explicit.add(f);
                            } else {
                              m.form.explicit.remove(f);
                            }
                            m.invalidate();
                          },
                  ),
                  if (m.form.explicit.contains(f))
                    TextField(
                      key: ValueKey('diagnostic-${f.name}'),
                      controller: m.form.inputs[f],
                      readOnly: m.locked,
                      onTapOutside: (_) {},
                      decoration: InputDecoration(
                        labelText: f.name,
                        helperText: f == ParameterField.path
                            ? 'Even-length ASCII hex. Empty explicitly clears the path.'
                            : protocolNumber(f)
                            ? 'Decimal or 0x hexadecimal integer.'
                            : 'Decimal integer. Seconds; startup delay uses milliseconds.',
                      ),
                    ),
                ],
              ],
            ),
            Text(m.form.routeHint),
            if (m.pending)
              const Text('Resolving preview without device access…'),
            if (m.error != null) Text('Preview failed: ${m.error}'),
            if (m.result case final r?) ...[
              Text(
                'Preview ${r.operation.name} • profile ${r.profileId?.value ?? 'none'} • content ${r.content?.length ?? 0} bytes',
              ),
              for (final e in m.form.values(r.parameters).entries)
                SelectableLabel('${e.key.name}: ${e.value}'),
              const Text(
                'Start resolves the captured request again in the worker.',
              ),
            ],
            if (a != null) ...[
              SelectableLabel(
                'Captured attempt port (local session context): ${m.attemptPort ?? 'Unavailable'}',
              ),
              DiagnosticOutcomes(value: a),
            ],
            if (m.runtime.snapshot.maintenance case final h?)
              SelectableLabel(
                'History maintenance: ${observed(h.latest)}\nUnacknowledged maintenance failures: ${h.failureCount}\nMaintenance error: ${h.failure?.code ?? 'None observed'}',
              ),
          ],
        ),
      );
    },
  );
}

/// The header and accessibility actions reach this public controller before
/// expansion changes. Read live composition here, before any editor is removed.
class _GuardedExpansionController extends ExpansibleController {
  _GuardedExpansionController(this.allowCollapse);
  final bool Function() allowCollapse;

  @override
  void collapse() {
    if (isExpanded && !allowCollapse()) return;
    super.collapse();
  }
}
