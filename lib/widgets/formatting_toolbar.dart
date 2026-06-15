import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/markdown_formatter.dart';

class FormattingToolbar extends StatefulWidget {
  const FormattingToolbar({
    required this.controller,
    super.key,
  });

  final TextEditingController controller;

  @override
  State<FormattingToolbar> createState() => _FormattingToolbarState();
}

class _FormattingToolbarState extends State<FormattingToolbar> {
  bool _bulletActive = false;
  bool _numberedActive = false;
  bool _isApplyingEdit = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_continueActiveList);
  }

  @override
  void didUpdateWidget(covariant FormattingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_continueActiveList);
      widget.controller.addListener(_continueActiveList);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_continueActiveList);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerTheme.color ?? AppColors.border;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _FormatButton(
            tooltip: 'Bold',
            label: 'B',
            style: const TextStyle(fontWeight: FontWeight.w900),
            onPressed: () => _applyInline(MarkdownFormat.bold),
          ),
          _FormatButton(
            tooltip: 'Italic',
            label: 'I',
            style: const TextStyle(fontStyle: FontStyle.italic),
            onPressed: () => _applyInline(MarkdownFormat.italic),
          ),
          _FormatButton(
            tooltip: 'Underline',
            label: 'U',
            style: const TextStyle(decoration: TextDecoration.underline),
            onPressed: () => _applyInline(MarkdownFormat.underline),
          ),
          _IconFormatButton(
            tooltip: 'Bullets',
            isActive: _bulletActive,
            onPressed: () => _toggleList(MarkdownFormat.bullet),
            icon: Icons.format_list_bulleted_rounded,
          ),
          _IconFormatButton(
            tooltip: 'Numbering',
            isActive: _numberedActive,
            onPressed: () => _toggleList(MarkdownFormat.numbered),
            icon: Icons.format_list_numbered_rounded,
          ),
        ],
      ),
    );
  }

  void _applyInline(MarkdownFormat format) {
    final selection = widget.controller.selection;
    final start =
        selection.start < 0 ? widget.controller.text.length : selection.start;
    final end =
        selection.end < 0 ? widget.controller.text.length : selection.end;
    final collapsed = start == end;
    final edit = collapsed
        ? MarkdownFormatter.activateInlineTypingZone(
            widget.controller.text,
            start,
            format,
          )
        : MarkdownFormatter.apply(widget.controller.text, start, end, format);
    _applyEdit(edit);
  }

  void _toggleList(MarkdownFormat format) {
    final active =
        format == MarkdownFormat.bullet ? _bulletActive : _numberedActive;
    final selection = widget.controller.selection;
    final start =
        selection.start < 0 ? widget.controller.text.length : selection.start;
    final end =
        selection.end < 0 ? widget.controller.text.length : selection.end;
    final edit = active
        ? MarkdownFormatter.removeCurrentListMarker(
            widget.controller.text, start)
        : MarkdownFormatter.apply(widget.controller.text, start, end, format);
    _applyEdit(edit);

    setState(() {
      if (format == MarkdownFormat.bullet) {
        _bulletActive = !active;
        _numberedActive = false;
      } else {
        _numberedActive = !active;
        _bulletActive = false;
      }
    });
  }

  void _continueActiveList() {
    if (_isApplyingEdit || (!_bulletActive && !_numberedActive)) {
      return;
    }
    final value = widget.controller.value;
    final cursor = value.selection.baseOffset;
    if (cursor < 1) {
      return;
    }
    final nextText = MarkdownFormatter.continueListAfterNewline(
      value.text,
      cursor,
      _bulletActive,
    ) as String;
    if (nextText == value.text) {
      return;
    }
    final insertedLength = nextText.length - value.text.length;
    _isApplyingEdit = true;
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: cursor + insertedLength),
    );
    _isApplyingEdit = false;
  }

  void _applyEdit(MarkdownEdit edit) {
    _isApplyingEdit = true;
    widget.controller.value = TextEditingValue(
      text: edit.text,
      selection: edit.selection,
    );
    _isApplyingEdit = false;
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.tooltip,
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final TextStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: _buttonStyle(context, false),
        child: Tooltip(
          message: tooltip,
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

class _IconFormatButton extends StatelessWidget {
  const _IconFormatButton({
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      isSelected: isActive,
      onPressed: onPressed,
      style: _buttonStyle(context, isActive),
      icon: Icon(icon),
    );
  }
}

ButtonStyle _buttonStyle(BuildContext context, bool isActive) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    padding: EdgeInsets.zero,
    backgroundColor: isActive ? scheme.primary : scheme.surfaceContainerHighest,
    foregroundColor: isActive ? scheme.onPrimary : scheme.onSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
