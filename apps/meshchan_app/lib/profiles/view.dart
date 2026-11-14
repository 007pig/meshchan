import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../drafts/editor.dart';
import '../runtime/protocol.dart';
import 'editor.dart';
import 'choice.dart';
import 'parameter_form.dart';
import 'preview.dart';

class SaveProfileIntent extends Intent {
  const SaveProfileIntent();
}

class ProfilesView extends StatefulWidget {
  const ProfilesView({
    super.key,
    required this.editor,
    required this.preview,
    required this.prompt,
  });
  final ProfilesEditor editor;
  final ParameterPreview preview;
  final LeavePrompt prompt;
  @override
  State<ProfilesView> createState() => _ProfilesViewState();
}

class _ProfilesViewState extends State<ProfilesView> {
  int page = 0;
  ProfilesEditor get e => widget.editor;
  ParameterPreview get p => widget.preview;
  @override
  void initState() {
    super.initState();
    page = e.target == EditorTarget.settings ? 1 : 0;
    unawaited(e.refresh());
  }

  Future<void> switchPage(int next) async {
    if (next == page ||
        e.quitting ||
        e.deciding ||
        e.deferDepartureForComposition() ||
        p.composing) {
      return;
    }
    if (next == 1) {
      if (!await e.openSettings(widget.prompt)) return;
    } else if (!await e.leave(widget.prompt)) {
      return;
    }
    if (next == 0 && e.target != EditorTarget.profile) {
      if (!await e.newProfile(widget.prompt)) return;
    }
    if (mounted) setState(() => page = next);
    if (next == 2) unawaited(p.select(p.profileId));
  }

  Future<bool> confirm(String title, String text) async {
    if (e.pending || !e.canOperate || e.deferDepartureForComposition()) {
      return false;
    }
    final generation = e.session;
    e.confirming = true;
    e.notify();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    e.confirming = false;
    e.notify();
    return result == true && generation == e.session;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([e, p]),
    builder: (context, _) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            SaveProfileIntent(),
      },
      child: Actions(
        actions: {
          SaveProfileIntent: CallbackAction<SaveProfileIntent>(
            onInvoke: (_) {
              if (page != 2 &&
                  e.canOperate &&
                  ModalRoute.of(context)?.isCurrent == true) {
                unawaited(e.save());
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                children: [
                  for (final (i, label) in [
                    'Profiles',
                    'Settings',
                    'Offline preview',
                  ].indexed)
                    TextButton(
                      onPressed: () => switchPage(i),
                      child: Text(label),
                    ),
                ],
              ),
              Expanded(
                child: page == 2
                    ? preview()
                    : page == 1
                    ? settings()
                    : profiles(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget scroll({required List<Widget> children}) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget textField(
    String key,
    String label,
    TextEditingController c, {
    String? helper,
    bool readOnly = false,
  }) => Padding(
    key: ValueKey('$key-container'),
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      key: ValueKey(key),
      controller: c,
      onTapOutside: (_) {},
      readOnly: readOnly,
      minLines: 1,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget status() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(e.status),
      if (e.notice != null) Text(e.notice!),
      if (e.readError != null)
        Text(
          'Read failed: ${e.readError}. Explicit full settings or Restore defaults remain available.',
        ),
      if (e.listError != null)
        Text(
          'Refresh failed: ${e.listError}. Confirmed commits remain committed.',
        ),
    ],
  );
  Widget profiles() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: e.canOperate ? () => e.newProfile(widget.prompt) : null,
            child: const Text('New preset'),
          ),
          TextButton(
            onPressed: e.canOperate ? () => e.refresh() : null,
            child: const Text('Refresh presets'),
          ),
          if (e.nextCursor != null)
            TextButton(
              onPressed: e.canOperate ? () => e.refresh(more: true) : null,
              child: const Text('Load more'),
            ),
        ],
      ),
      Text('${e.items.length} loaded; pages are separate snapshots'),
      SizedBox(
        height: 130,
        child: ListView(
          children: [
            for (final item in e.items)
              ListTile(
                key: ValueKey(item.id.value),
                title: Text(item.name, maxLines: 1),
                subtitle: Text('${item.operation.name} • ${item.id.value}'),
                selected: e.baseline?.id.value == item.id.value,
                onTap: e.canOperate
                    ? () => e.select(item.id.value, widget.prompt)
                    : null,
              ),
          ],
        ),
      ),
      Expanded(
        child: KeyedSubtree(
          key: ValueKey('profile-${e.session}-${e.fieldGeneration}'),
          child: scroll(
            children: [
              status(),
              if (e.hasDocument) ...[
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: e.canOperate ? () => e.save() : null,
                      child: const Text('Save preset'),
                    ),
                    TextButton(
                      onPressed: e.canOperate && !e.pending
                          ? () async {
                              if (await confirm(
                                e.baseline == null
                                    ? 'Discard new preset?'
                                    : 'Delete saved preset?',
                                e.baseline == null
                                    ? 'Discard this local preset. Nothing has been stored.'
                                    : 'Delete the stored preset and discard local edits. A matching default reference is cleared in the same transaction. History and its limit remain unchanged.',
                              )) {
                                await e.delete();
                              }
                            }
                          : null,
                      child: Text(
                        e.baseline == null
                            ? 'Discard new preset'
                            : 'Delete preset',
                      ),
                    ),
                  ],
                ),
                textField('profile-name', 'Name', e.name, readOnly: e.locked),
                CheckboxListTile(
                  title: const Text('Include port hint (reference only)'),
                  value: e.hintEnabled,
                  onChanged: e.locked
                      ? null
                      : (v) {
                          if (!e.deferDepartureForComposition()) {
                            e.hintEnabled = v!;
                            e.edited();
                          }
                        },
                ),
                if (e.hintEnabled)
                  textField(
                    'profile-hint',
                    'Port hint',
                    e.hint,
                    readOnly: e.locked,
                  ),
                GuardedChoice<DiagnosticOperation>(
                  key: const ValueKey('profile-operation-choice'),
                  label: e.form.operation.name,
                  choices: [
                    for (final op in DiagnosticOperation.values)
                      (value: op, label: op.name),
                  ],
                  enabled: e.canOperate && !e.pending,
                  allowOpen: () => !e.deferDepartureForComposition(),
                  onSelected: (op) async {
                    if (op == e.form.operation) return;
                    if (await confirm(
                      'Change preset operation?',
                      'Keep name, port hint and budgets. Replace all operation-specific input, including incompatible unsaved fields. Missing required fields must be filled before saving.',
                    )) {
                      e.changeType(op);
                    }
                  },
                ),
                const Text(
                  'Test endpoint IDs are local labels, not authenticated identities. Invocation payload/content is never saved in a preset.',
                ),
                ...parameterFields(e.form, e.edited, locked: e.locked),
                Text(e.form.routeHint),
              ],
            ],
          ),
        ),
      ),
    ],
  );
  Widget settings() => KeyedSubtree(
    key: ValueKey('settings-${e.session}'),
    child: scroll(
      children: [
        status(),
        const Text(
          'Saving replaces both settings. A lower history limit may clean old history that core considers eligible; active and unsettled records are protected.',
        ),
        GuardedChoice<String>(
          key: const ValueKey('settings-default-choice'),
          expanded: true,
          label: profileLabel(e.defaultId.text, 'No default (clear selection)'),
          choices: [
            (value: '', label: 'No default (clear selection)'),
            for (final item in e.items)
              (
                value: item.id.value,
                label:
                    '${item.name} • ${item.operation.name} • ${item.id.value}',
              ),
          ],
          enabled: !e.locked,
          allowOpen: () => !e.deferDepartureForComposition(),
          onSelected: (id) {
            if (!e.locked && !e.deferDepartureForComposition()) {
              e.defaultId.text = id;
            }
          },
        ),
        textField(
          'default-id',
          'Default profile ID (empty clears)',
          e.defaultId,
          helper: 'Any saved operation may be the global default. A saved default outside the current page is retained by ID.',
          readOnly: e.locked,
        ),
        textField(
          'history-limit',
          'Diagnostic history limit',
          e.history,
          helper: 'Decimal integer 1–100000; no clamping.',
          readOnly: e.locked,
        ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: e.canOperate ? () => e.save() : null,
              child: const Text('Save settings'),
            ),
            TextButton(
              onPressed: e.canOperate && !e.pending
                  ? () async {
                      if (await confirm(
                        'Restore both settings?',
                        'Restore no default preset and history limit 1000, discarding local settings edits. This does not delete presets or drafts. If 1000 is lower than the saved limit, subsequent maintenance may clean eligible old history.',
                      )) {
                        await e.restore();
                      }
                    }
                  : null,
              child: const Text('Restore defaults'),
            ),
          ],
        ),
      ],
    ),
  );
  List<Widget> parameterFields(
    ParameterForm form,
    VoidCallback changed, {
    bool locked = false,
    Map<ParameterField, String> inherited = const {},
  }) => [
    for (final f in form.fields) ...[
      if (form.overrides)
        CheckboxListTile(
          title: Text('Override ${f.name}'),
          subtitle: Text(
            'Inherited display: ${inherited[f] ?? 'program default or required; Preview validates'}',
          ),
          value: form.explicit.contains(f),
          onChanged: locked
              ? null
              : (v) {
                  if (form.composing) return;
                  if (v!) {
                    form.explicit.add(f);
                  } else {
                    form.explicit.remove(f);
                  }
                  changed();
                },
        ),
      if (f == ParameterField.dataType &&
          form.operation == DiagnosticOperation.listen &&
          (!form.overrides || form.explicit.contains(f)))
        CheckboxListTile(
          title: const Text('Receive all data types'),
          value: form.listenAll,
          onChanged: locked
              ? null
              : (v) {
                  if (form.composing) return;
                  form.listenAll = v!;
                  changed();
                },
        ),
      if ((!form.overrides || form.explicit.contains(f)) &&
          !(f == ParameterField.dataType &&
              form.operation == DiagnosticOperation.listen &&
              form.listenAll))
        textField(
          'field-${f.name}',
          f.name,
          form.inputs[f]!,
          helper: f == ParameterField.path
              ? 'Even-length ASCII hex; empty is explicitly zero bytes.'
              : protocolNumber(f)
              ? 'Decimal or 0x-prefixed hexadecimal integer.'
              : 'Decimal whole number. Seconds except startup delay in milliseconds.',
          readOnly: locked,
        ),
    ],
  ];
  String profileLabel(String? id, String fallback) {
    if (id == null || id.isEmpty) return fallback;
    for (final item in e.items) {
      if (item.id.value == id) {
        return '${item.name} • ${item.operation.name} • ${item.id.value}';
      }
    }
    return id;
  }

  Widget preview() => scroll(
    children: [
      const Text(
        'Offline preview uses saved presets only. It does not save, connect, check a device, transmit or record. Explicit overrides → saved/default preset → existing program defaults.',
      ),
      GuardedChoice<DiagnosticOperation>(
        key: const ValueKey('preview-operation-choice'),
        label: p.form.operation.name,
        choices: [
          for (final op in DiagnosticOperation.values)
            (value: op, label: op.name),
        ],
        allowOpen: () => !p.deferChangeForComposition(),
        onSelected: (op) {
          p.form.changeType(op);
          p.fieldGeneration++;
          p.invalidate();
        },
      ),
      GuardedChoice<String>(
        key: const ValueKey('preview-profile-choice'),
        expanded: true,
        label: profileLabel(
          p.profileId,
          'Use settings default (may be no preset)',
        ),
        choices: [
          (value: '', label: 'Use settings default (may be no preset)'),
          for (final item in e.items)
            (
              value: item.id.value,
              label: '${item.name} • ${item.operation.name} • ${item.id.value}',
            ),
        ],
        allowOpen: () => !p.deferChangeForComposition(),
        onSelected: (id) => p.select(id.isEmpty ? null : id),
      ),
      if (p.notice != null) Text(p.notice!),
      if (p.selectionError != null)
        Text(
          'Selection display read failed: ${p.selectionError}. Explicit selection and Preview remain independent.',
        ),
      if (p.inherited != null)
        Text(
          'Saved selection: ${p.inherited!.operation.name} • ${p.inherited!.id.value}',
        ),
      const Text(
        'Overrides remain explicit when the selected preset changes. Operation never changes with preset selection.',
      ),
      KeyedSubtree(
        key: ValueKey('preview-${p.fieldGeneration}'),
        child: Column(
          children: parameterFields(
            p.form,
            p.invalidate,
            inherited: p.inherited == null
                ? const {}
                : p.form.values(p.inherited!.parameters),
          ),
        ),
      ),
      Text(p.form.routeHint),
      if (p.form.operation == DiagnosticOperation.send ||
          p.form.operation == DiagnosticOperation.ping) ...[
        GuardedChoice<ContentMode>(
          key: const ValueKey('preview-content-choice'),
          label: switch (p.mode) {
            ContentMode.notProvided => 'Not provided',
            ContentMode.text => 'Text (UTF-8)',
            ContentMode.hex => 'Hex',
          },
          choices: const [
            (value: ContentMode.notProvided, label: 'Not provided'),
            (value: ContentMode.text, label: 'Text (UTF-8)'),
            (value: ContentMode.hex, label: 'Hex'),
          ],
          allowOpen: () => !p.deferChangeForComposition(),
          onSelected: (mode) {
            p.mode = mode;
            p.invalidate();
          },
        ),
        if (p.mode != ContentMode.notProvided)
          textField(
            'invocation-content',
            'Invocation content',
            p.content,
            helper: p.mode == ContentMode.hex
                ? 'Even-length ASCII hex; empty is explicitly zero bytes.'
                : 'Exact UTF-8 text; empty is explicitly zero bytes.',
          ),
      ],
      FilledButton(
        onPressed: p.pending ? null : p.preview,
        child: const Text('Preview parameters'),
      ),
      if (p.pending) const Text('Resolving…'),
      if (p.error != null) Text('Preview failed: ${p.error}'),
      if (p.result case final r?) ...[
        Text(
          'Resolved ${r.operation.name} • profile ${r.profileId?.value ?? 'none'} • content ${r.content?.length ?? 0} bytes',
        ),
        for (final entry in p.form.values(r.parameters).entries)
          SelectableText('${entry.key.name}: ${entry.value}'),
      ],
    ],
  );
}
