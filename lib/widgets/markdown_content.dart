import 'package:flutter/material.dart';

class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    required this.content,
    this.style,
    this.maxLines,
    super.key,
  });

  final String content;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ??
        Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16) ??
        const TextStyle(fontSize: 16);
    final lines = content.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _MarkdownLine(
              line: line,
              style: baseStyle,
              maxLines: maxLines,
            ),
          ),
      ],
    );
  }
}

class _MarkdownLine extends StatelessWidget {
  const _MarkdownLine({
    required this.line,
    required this.style,
    this.maxLines,
  });

  final String line;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
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
    final pattern = RegExp(r'(\*\*.*?\*\*|_.*?_|<u>.*?<\/u>)');

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
