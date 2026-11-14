import 'package:flutter/material.dart';

/// Check live editing values before pushing a menu route. A dropdown's
/// onChanged runs after focus has moved and marked text may already be gone.
class GuardedChoice<T> extends StatelessWidget {
  const GuardedChoice({
    super.key,
    required this.label,
    required this.choices,
    required this.allowOpen,
    required this.onSelected,
    this.enabled = true,
    this.expanded = false,
  });
  final String label;
  final List<({T value, String label})> choices;
  final bool Function() allowOpen;
  final ValueChanged<T> onSelected;
  final bool enabled, expanded;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => TextButton(
      onPressed: !enabled
          ? null
          : () async {
              if (!allowOpen()) return;
              final button = context.findRenderObject()! as RenderBox;
              final overlay =
                  Overlay.of(context).context.findRenderObject()! as RenderBox;
              final origin = button.localToGlobal(
                Offset(0, button.size.height),
                ancestor: overlay,
              );
              final selected = await showMenu<T>(
                context: context,
                position: RelativeRect.fromRect(
                  Rect.fromLTWH(origin.dx, origin.dy, button.size.width, 0),
                  Offset.zero & overlay.size,
                ),
                items: [
                  for (final choice in choices)
                    PopupMenuItem<T>(
                      value: choice.value,
                      child: Text(choice.label),
                    ),
                ],
              );
              if (selected != null && context.mounted && allowOpen()) {
                onSelected(selected);
              }
            },
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );
}
