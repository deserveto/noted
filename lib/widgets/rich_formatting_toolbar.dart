import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'reference_icon.dart';

class RichFormattingToolbar extends StatelessWidget {
  const RichFormattingToolbar(
      {required this.controller,
      required this.focusNode,
      required this.onClose,
      super.key});
  final q.QuillController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  void _toggle(q.Attribute attribute) {
    final current = controller.getSelectionStyle().attributes[attribute.key];
    controller.formatSelection(current?.value == attribute.value
        ? q.Attribute.clone(attribute, null)
        : attribute);
    focusNode.requestFocus();
  }

  void _size(int direction) {
    final current = controller.getSelectionStyle().attributes['size']?.value;
    final size = double.tryParse('$current') ?? 16;
    controller.formatSelection(
        q.SizeAttribute((size + direction * 2).clamp(10, 36).toString()));
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final attrs = controller.getSelectionStyle().attributes;
        Widget tool(String label, Widget icon, VoidCallback action,
                {bool selected = false}) =>
            IconButton(
              tooltip: label,
              isSelected: selected,
              onPressed: action,
              style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor:
                      selected ? scheme.onSurface : Colors.transparent,
                  foregroundColor: selected
                      ? Theme.of(context).scaffoldBackgroundColor
                      : scheme.onSurface),
              icon: DefaultTextStyle.merge(
                  style: TextStyle(
                      color: selected
                          ? Theme.of(context).scaffoldBackgroundColor
                          : scheme.onSurface),
                  child: icon),
            );
        return Container(
          decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Theme.of(context).dividerColor)),
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                tool('Close formatting', const ReferenceIcon('x', size: 18),
                    onClose),
                Container(
                    height: 24,
                    width: 1,
                    color: Theme.of(context).dividerColor),
                tool('Highlight', const ReferenceIcon('marker', size: 19),
                    () => _toggle(const q.BackgroundAttribute('#ffd66b')),
                    selected: attrs['background']?.value == '#ffd66b'),
                tool(
                    'Increase font size',
                    const Text('A⁺',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 16)),
                    () => _size(1)),
                tool(
                    'Decrease font size',
                    const Text('A⁻',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
                    () => _size(-1)),
                tool(
                    'Bold',
                    const Text('B',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    () => _toggle(q.Attribute.bold),
                    selected: attrs['bold']?.value == true),
                tool(
                    'Italic',
                    const Text('I',
                        style: TextStyle(
                            fontFamily: 'Newsreader',
                            fontStyle: FontStyle.italic,
                            fontSize: 18)),
                    () => _toggle(q.Attribute.italic),
                    selected: attrs['italic']?.value == true),
                tool(
                    'Underline',
                    const Text('U',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            decoration: TextDecoration.underline)),
                    () => _toggle(q.Attribute.underline),
                    selected: attrs['underline']?.value == true),
                tool('Bullets', const ReferenceIcon('bullets', size: 19),
                    () => _toggle(q.Attribute.ul),
                    selected: attrs['list']?.value == 'bullet'),
                tool('Numbering', const ReferenceIcon('numbered', size: 19),
                    () => _toggle(q.Attribute.ol),
                    selected: attrs['list']?.value == 'ordered'),
                tool('Align center', const ReferenceIcon('alignC', size: 19),
                    () => _toggle(q.Attribute.centerAlignment),
                    selected: attrs['align']?.value == 'center'),
                tool('Align right', const ReferenceIcon('alignR', size: 19),
                    () => _toggle(q.Attribute.rightAlignment),
                    selected: attrs['align']?.value == 'right'),
              ])),
        );
      });
}
