import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor.dart';

class SaveDraftIntent extends Intent {
  const SaveDraftIntent();
}

Future<LeaveChoice> showDraftLeaveDialog(
  BuildContext context, {
  required bool unknown,
}) async =>
    await showDialog<LeaveChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(unknown ? 'Write result unknown' : 'Leave this draft?'),
        content: Text(
          unknown
              ? 'The earlier save or delete may already have committed. Discard only abandons local edits; it cannot undo that write. Safely close and inspect records in a new session.'
              : 'Save the current text, discard local edits, or continue editing. Any accepted write will finish first; Discard cannot undo a committed write.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, LeaveChoice.continueEditing),
            child: const Text('Continue editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          if (!unknown)
            FilledButton(
              onPressed: () => Navigator.pop(context, LeaveChoice.save),
              child: const Text('Save'),
            ),
        ],
      ),
    ) ??
    LeaveChoice.continueEditing;

class DraftsView extends StatelessWidget {
  const DraftsView({super.key, required this.editor, required this.prompt});
  final DraftEditor editor;
  final LeavePrompt prompt;

  Future<void> _delete(BuildContext context) async {
    if (!editor.beginConfirmation()) return;
    final generation = editor.documentGeneration, id = editor.baseline?.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved draft?'),
        content: Text(
          editor.dirty
              ? 'Permanently delete the saved draft and discard these unsaved local edits?'
              : 'Permanently delete this saved draft?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    editor.endConfirmation();
    if (confirmed == true &&
        generation == editor.documentGeneration &&
        id == editor.baseline?.id) {
      await editor.delete();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveDraftIntent(),
      },
      child: Actions(
        actions: {
          SaveDraftIntent: CallbackAction<SaveDraftIntent>(
            onInvoke: (_) {
              if (editor.canSave) unawaited(editor.save());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final list = _list(context);
              // EditableText owns its undo stack and throttled pushes. A new
              // document session must dispose that state, including its timer.
              // Ordinary saves/status updates keep this key and input state.
              final form = KeyedSubtree(
                key: ValueKey(editor.documentGeneration),
                child: _form(context),
              );
              return constraints.maxWidth >= 680
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 240, child: list),
                        const VerticalDivider(),
                        Expanded(child: form),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(height: 190, child: list),
                        const Divider(),
                        Expanded(child: form),
                      ],
                    );
            },
          ),
        ),
      ),
    ),
  );

  Widget _list(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: editor.canOperate ? () => editor.newDraft(prompt) : null,
            child: const Text('New'),
          ),
          TextButton(
            onPressed: editor.canOperate ? () => editor.refresh() : null,
            child: const Text('Refresh'),
          ),
        ],
      ),
      Text(
        '${editor.items.length} loaded • pages are separate snapshots',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (editor.loading) const LinearProgressIndicator(),
      if (editor.listError != null)
        Text(
          '${editor.items.isEmpty ? 'List read failed' : 'Refresh failed'}: ${editor.listError!.code}',
        ),
      if (!editor.loading && editor.items.isEmpty && editor.listError == null)
        const Text('No drafts in this page.'),
      Expanded(
        child: ListView(
          children: [
            for (final draft in editor.items)
              ListTile(
                key: ValueKey(draft.id),
                selected: editor.selectedId == draft.id,
                title: Text(
                  draft.title.isEmpty ? 'Untitled' : draft.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('Revision ${draft.revision}'),
                onTap: editor.canOperate
                    ? () => editor.select(draft.id, prompt)
                    : null,
              ),
          ],
        ),
      ),
      if (editor.nextCursor != null)
        TextButton(
          onPressed: editor.canOperate && !editor.loading
              ? () => editor.refresh(more: true)
              : null,
          child: const Text('Load more'),
        ),
    ],
  );

  Widget _form(BuildContext context) => ListView(
    children: [
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(
            onPressed: editor.canSave ? () => editor.save() : null,
            child: const Text('Save'),
          ),
          TextButton(
            onPressed:
                editor.canOperate &&
                    editor.baseline != null &&
                    !editor.pending &&
                    !editor.unknown &&
                    !editor.reading
                ? () => _delete(context)
                : null,
            child: const Text('Delete'),
          ),
          Text(editor.status),
        ],
      ),
      if (editor.baseline != null)
        Text('Revision ${editor.baseline!.revision}'),
      if (editor.reading) const LinearProgressIndicator(),
      if (editor.readError != null)
        Text('Document read failed: ${editor.readError!.code}'),
      if (editor.notice != null) Text(editor.notice!),
      if (editor.unknownNotice != null) Text(editor.unknownNotice!),
      if (editor.error?.code == 'conflict')
        Wrap(
          spacing: 8,
          children: [
            const Text('Version conflict. Your local text is retained.'),
            TextButton(
              onPressed: editor.canOperate ? editor.inspectStored : null,
              child: const Text('View stored version'),
            ),
          ],
        ),
      if (editor.error?.code == 'not_found')
        const Text(
          'This saved record no longer exists. Local text is retained.',
        ),
      if (editor.storedVersion case final stored?)
        TextButton(
          onPressed: () async {
            if (!editor.beginConfirmation()) return;
            final generation = editor.documentGeneration;
            final reload = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Stored revision ${stored.revision}'),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '${stored.title}\n\n${stored.body}\n\nReload replaces your local text and adopts this revision.',
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Continue editing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Reload'),
                  ),
                ],
              ),
            );
            editor.endConfirmation();
            if (reload == true && generation == editor.documentGeneration) {
              editor.reloadInspected(stored);
            }
          },
          child: Text('Inspect stored revision ${stored.revision} / Reload'),
        ),
      if (editor.hasDocument) ...[
        Text('Body UTF-8 bytes: ${editor.bodyUtf8Bytes}'),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('draft-title'),
          controller: editor.title,
          // Keep focus on outside pointer-down: buttons must check the current
          // marked text before any modal can take focus, even before a rebuild.
          onTapOutside: (_) {},
          readOnly:
              editor.deleting ||
              editor.deciding ||
              editor.quitting ||
              editor.reading,
          minLines: 1,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          key: const ValueKey('draft-body-container'),
          height: 300,
          child: TextField(
            key: const ValueKey('draft-body'),
            controller: editor.body,
            onTapOutside: (_) {},
            readOnly:
                editor.deleting ||
                editor.deciding ||
                editor.quitting ||
                editor.reading,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              labelText: 'Body',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    ],
  );
}
