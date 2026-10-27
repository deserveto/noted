import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../utils/document_codec.dart';
import '../utils/markdown_formatter.dart';
import 'rich_note_embed.dart';

class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    required this.content,
    this.style,
    this.maxLines,
    this.onChanged,
    super.key,
  });

  final String content;
  final TextStyle? style;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ??
        Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16) ??
        const TextStyle(fontSize: 16);
    if (DocumentCodec.isRich(content)) {
      if (maxLines != null) {
        return Text(MarkdownFormatter.toPlainText(content),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: baseStyle);
      }
      return _RichDocumentContent(content: content);
    }
    final lines = content.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < lines.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _MarkdownLine(
              line: lines[index],
              style: baseStyle,
              maxLines: maxLines,
              onCheck: onChanged == null
                  ? null
                  : () {
                      final updated = [...lines];
                      updated[index] = lines[index].replaceFirst(
                        RegExp(r'^- \[([ xX])\]'),
                        lines[index].startsWith('- [ ]') ? '- [x]' : '- [ ]',
                      );
                      onChanged!(updated.join('\n'));
                    },
            ),
          ),
      ],
    );
  }
}

class _RichDocumentContent extends StatefulWidget {
  const _RichDocumentContent({required this.content});
  final String content;
  @override
  State<_RichDocumentContent> createState() => _RichDocumentContentState();
}

class _RichDocumentContentState extends State<_RichDocumentContent> {
  late quill.QuillController _controller;
  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
        document: DocumentCodec.decode(widget.content),
        selection: const TextSelection.collapsed(offset: 0))
      ..readOnly = true;
  }

  @override
  void didUpdateWidget(covariant _RichDocumentContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) {
      _controller.document = DocumentCodec.decode(widget.content);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => quill.QuillEditor.basic(
      controller: _controller,
      config: const quill.QuillEditorConfig(
          embedBuilders: [RichNoteEmbed()],
          unknownEmbedBuilder: RichNoteEmbed(),
          scrollable: false,
          showCursor: false,
          padding: EdgeInsets.zero));
}

class _MarkdownLine extends StatelessWidget {
  const _MarkdownLine({
    required this.line,
    required this.style,
    this.maxLines,
    this.onCheck,
  });

  final String line;
  final TextStyle style;
  final int? maxLines;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    for (final tag in ['center', 'right']) {
      if (line.startsWith('<$tag>') && line.endsWith('</$tag>')) {
        return SizedBox(
            width: double.infinity,
            child: Align(
              alignment:
                  tag == 'center' ? Alignment.center : Alignment.centerRight,
              child: _RichMarkdownText(
                  text: line.substring(
                      tag.length + 2, line.length - tag.length - 3),
                  style: style),
            ));
      }
    }
    final checklist = RegExp(r'^- \[([ xX])\]\s?(.*)$').firstMatch(line);
    if (checklist != null) {
      final done = checklist.group(1) != ' ';
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
                value: done,
                onChanged: onCheck == null ? null : (_) => onCheck!(),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)))),
        const SizedBox(width: 8),
        Expanded(
            child: _RichMarkdownText(
                text: checklist.group(2)!,
                style: style.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : style.color))),
      ]);
    }
    if (line.startsWith('### ')) {
      return _RichMarkdownText(
          text: line.substring(4),
          style: style.copyWith(fontSize: 19, fontWeight: FontWeight.w600));
    }
    if (line.startsWith('> ')) {
      return Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
            border: Border(
                left: BorderSide(
                    color: Theme.of(context).colorScheme.primary, width: 3))),
        child: _RichMarkdownText(
            text: line.substring(2),
            style: style.copyWith(
                fontFamily: 'Newsreader',
                fontStyle: FontStyle.italic,
                fontSize: 19)),
      );
    }
    final numbered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
    final bullet = line.startsWith('- ') ? line.substring(2) : null;

    if (numbered != null || bullet != null) {
      final marker = numbered == null ? '•' : '${numbered.group(1)}.';
      final text = bullet ?? numbered!.group(2)!;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(marker,
                style: style.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: _RichMarkdownText(text: text, style: style)),
        ],
      );
    }

    return _RichMarkdownText(
      text: line,
      style: style,
      maxLines: maxLines,
    );
  }
}

class _RichMarkdownText extends StatelessWidget {
  const _RichMarkdownText({
    required this.text,
    required this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      text: TextSpan(style: style, children: _parse(text, style)),
    );
  }

  List<InlineSpan> _parse(String input, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    var index = 0;
    final pattern = RegExp(
        r'(\*\*.*?\*\*|_.*?_|<u>.*?<\/u>|<mark>.*?<\/mark>|<big>.*?<\/big>|<small>.*?<\/small>)');

    for (final match in pattern.allMatches(input)) {
      if (match.start > index) {
        spans.add(TextSpan(text: input.substring(index, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.w900),
        ));
      } else if (token.startsWith('_')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (token.startsWith('<mark>')) {
        spans.add(TextSpan(
            text: token.substring(6, token.length - 7),
            style:
                baseStyle.copyWith(backgroundColor: const Color(0x8cffd66b))));
      } else if (token.startsWith('<big>')) {
        spans.add(TextSpan(
            text: token.substring(5, token.length - 6),
            style:
                baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 16) + 2)));
      } else if (token.startsWith('<small>')) {
        spans.add(TextSpan(
            text: token.substring(7, token.length - 8),
            style:
                baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 16) - 2)));
      } else if (token.startsWith('<u>')) {
        spans.add(TextSpan(
          text: token.substring(3, token.length - 4),
          style: baseStyle.copyWith(decoration: TextDecoration.underline),
        ));
      }
      index = match.end;
    }

    if (index < input.length) {
      spans.add(TextSpan(text: input.substring(index)));
    }
    return spans;
  }
}
