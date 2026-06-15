import 'package:flutter/widgets.dart';

enum MarkdownFormat {
  bold,
  italic,
  underline,
  bullet,
  numbered,
}

class MarkdownEdit {
  const MarkdownEdit({
    required this.text,
    required this.selection,
  });

  final String text;
  final TextSelection selection;
}

class MarkdownFormatter {
  static const _boldMarker = '**';
  static const _italicMarker = '_';
  static const _underlineStart = '<u>';
  static const _underlineEnd = '</u>';

  static String toPlainText(String input) {
    return input
        .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (match) => match.group(1)!)
        .replaceAllMapped(RegExp(r'_(.*?)_'), (match) => match.group(1)!)
        .replaceAllMapped(RegExp(r'<u>(.*?)<\/u>'), (match) => match.group(1)!);
  }

  static MarkdownEdit apply(
    String text,
    int selectionStart,
    int selectionEnd,
    MarkdownFormat format,
  ) {
    final start = selectionStart.clamp(0, text.length);
    final end = selectionEnd.clamp(start, text.length);
    final selected = text.substring(start, end);

    return switch (format) {
      MarkdownFormat.bold =>
        _toggleWrap(text, start, end, _boldMarker, _boldMarker),
      MarkdownFormat.italic =>
        _toggleWrap(text, start, end, _italicMarker, _italicMarker),
      MarkdownFormat.underline =>
        _toggleWrap(text, start, end, _underlineStart, _underlineEnd),
      MarkdownFormat.bullet => _toggleBulletLines(text, start, end, selected),
      MarkdownFormat.numbered => _toggleNumberLines(text, start, end, selected),
    };
  }

  static MarkdownEdit activateInlineTypingZone(
    String text,
    int cursorOffset,
    MarkdownFormat format,
  ) {
    final offset = cursorOffset.clamp(0, text.length);
    final (prefix, suffix) = _inlineMarkers(format);
    final replacement = '$prefix$suffix';
    return _replace(text, offset, offset, replacement, offset + prefix.length);
  }

  static MarkdownEdit activateInlineTyping(
    String text,
    int cursorOffset,
    MarkdownFormat format,
  ) {
    return activateInlineTypingZone(text, cursorOffset, format);
  }

  static MarkdownEdit leaveInlineTypingZone(
    String text,
    int cursorOffset,
    MarkdownFormat format,
  ) {
    final offset = cursorOffset.clamp(0, text.length);
    final (_, suffix) = _inlineMarkers(format);
    final suffixEnd = offset + suffix.length;
    if (suffix.isNotEmpty &&
        suffixEnd <= text.length &&
        text.substring(offset, suffixEnd) == suffix) {
      return MarkdownEdit(
        text: text,
        selection: TextSelection.collapsed(offset: suffixEnd),
      );
    }
    return MarkdownEdit(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  static MarkdownEdit deactivateInlineTyping(
    String text,
    int cursorOffset,
    MarkdownFormat format,
  ) {
    return leaveInlineTypingZone(text, cursorOffset, format);
  }

  static dynamic continueListAfterNewline(
    String text,
    int cursorOffset,
    Object format,
  ) {
    final bullet = switch (format) {
      MarkdownFormat.bullet => true,
      MarkdownFormat.numbered => false,
      bool value => value,
      _ => true,
    };
    final cursor = cursorOffset.clamp(0, text.length);
    if (cursor == 0 || text[cursor - 1] != '\n') {
      return format is bool
          ? text
          : MarkdownEdit(
              text: text,
              selection: TextSelection.collapsed(offset: cursor),
            );
    }

    final previousLineStart = text.lastIndexOf('\n', cursor - 2) + 1;
    final previousLine = text.substring(previousLineStart, cursor - 1);
    final prefix = bullet ? '- ' : _nextNumberPrefix(previousLine);
    if (prefix == null) {
      return format is bool
          ? text
          : MarkdownEdit(
              text: text,
              selection: TextSelection.collapsed(offset: cursor),
            );
    }
    final updated = text.replaceRange(cursor, cursor, prefix);
    return format is bool
        ? updated
        : MarkdownEdit(
            text: updated,
            selection: TextSelection.collapsed(offset: cursor + prefix.length),
          );
  }

  static MarkdownEdit removeCurrentListMarker(String text, int cursorOffset) {
    final cursor = cursorOffset.clamp(0, text.length);
    final lineStart = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final lineEnd = text.indexOf('\n', cursor);
    final end = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(lineStart, end);
    final marker = RegExp(r'^((?:- )|(?:\d+\. ))').firstMatch(line);
    if (marker == null) {
      return MarkdownEdit(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      );
    }

    final markerLength = marker.group(1)!.length;
    final nextCursor = (cursor - markerLength).clamp(lineStart, text.length);
    return _replace(
      text,
      lineStart,
      lineStart + markerLength,
      '',
      nextCursor,
    );
  }

  static MarkdownEdit _toggleWrap(
    String text,
    int start,
    int end,
    String prefix,
    String suffix,
  ) {
    if (start == end) {
      return activateInlineTypingZone(
        text,
        start,
        _formatForMarkers(prefix, suffix),
      );
    }

    final suffixStart = end - suffix.length;
    final alreadyWrapped = end - start >= prefix.length + suffix.length &&
        text.substring(start, start + prefix.length) == prefix &&
        text.substring(suffixStart, end) == suffix;
    if (alreadyWrapped) {
      final inner = text.substring(start + prefix.length, suffixStart);
      return _replace(text, start, end, inner, start + inner.length);
    }

    final selected = text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    return _replace(text, start, end, replacement, start + replacement.length);
  }

  static MarkdownEdit _toggleBulletLines(
    String text,
    int start,
    int end,
    String selected,
  ) {
    final range =
        selected.isEmpty ? _currentLineRange(text, start) : (start, end);
    final selection =
        selected.isEmpty ? text.substring(range.$1, range.$2) : selected;
    final lines = selection.split('\n');
    final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty);
    final allBulleted = nonEmptyLines.isNotEmpty &&
        nonEmptyLines.every((line) => line.startsWith('- '));
    final replacement = lines.map((line) {
      if (line.trim().isEmpty) {
        return allBulleted ? line : '- ';
      }
      return allBulleted ? line.substring(2) : '- $line';
    }).join('\n');
    return _replace(
      text,
      range.$1,
      range.$2,
      replacement,
      range.$1 + replacement.length,
    );
  }

  static MarkdownEdit _toggleNumberLines(
    String text,
    int start,
    int end,
    String selected,
  ) {
    final range =
        selected.isEmpty ? _currentLineRange(text, start) : (start, end);
    final selection =
        selected.isEmpty ? text.substring(range.$1, range.$2) : selected;
    final lines = selection.split('\n');
    final marker = RegExp(r'^\d+\. ');
    final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty);
    final allNumbered =
        nonEmptyLines.isNotEmpty && nonEmptyLines.every(marker.hasMatch);
    var index = 0;
    final replacement = lines.map((line) {
      index += 1;
      if (line.trim().isEmpty) {
        return allNumbered ? line : '$index. ';
      }
      return allNumbered ? line.replaceFirst(marker, '') : '$index. $line';
    }).join('\n');
    return _replace(
      text,
      range.$1,
      range.$2,
      replacement,
      range.$1 + replacement.length,
    );
  }

  static (int, int) _currentLineRange(String text, int cursorOffset) {
    final cursor = cursorOffset.clamp(0, text.length);
    final start = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final nextNewline = text.indexOf('\n', cursor);
    final end = nextNewline == -1 ? text.length : nextNewline;
    return (start, end);
  }

  static String? _nextNumberPrefix(String previousLine) {
    final numbered = RegExp(r'^(\d+)\. ').firstMatch(previousLine);
    if (numbered == null) {
      return previousLine.startsWith('- ') ? null : '1. ';
    }
    final number = int.parse(numbered.group(1)!);
    return '${number + 1}. ';
  }

  static MarkdownFormat _formatForMarkers(String prefix, String suffix) {
    if (prefix == _boldMarker && suffix == _boldMarker) {
      return MarkdownFormat.bold;
    }
    if (prefix == _italicMarker && suffix == _italicMarker) {
      return MarkdownFormat.italic;
    }
    return MarkdownFormat.underline;
  }

  static (String, String) _inlineMarkers(MarkdownFormat format) {
    return switch (format) {
      MarkdownFormat.bold => (_boldMarker, _boldMarker),
      MarkdownFormat.italic => (_italicMarker, _italicMarker),
      MarkdownFormat.underline => (_underlineStart, _underlineEnd),
      MarkdownFormat.bullet || MarkdownFormat.numbered => ('', ''),
    };
  }

  static MarkdownEdit _replace(
    String text,
    int start,
    int end,
    String replacement,
    int cursorOffset,
  ) {
    return MarkdownEdit(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}
