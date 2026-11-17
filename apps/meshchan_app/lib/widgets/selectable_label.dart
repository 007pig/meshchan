import 'package:material_ui/material_ui.dart';

/// Selectable display text with static accessibility semantics.
///
/// Updating read-only EditableText values can enter the macOS native text-field
/// bridge. SelectionArea keeps display updates out of that input path while
/// preserving selection and copy, including multiline Unicode.
class SelectableLabel extends StatelessWidget {
  const SelectableLabel(this.data, {super.key});
  final String data;

  @override
  Widget build(BuildContext context) => SelectionArea(child: Text(data));
}
