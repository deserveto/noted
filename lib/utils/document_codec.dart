import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:markdown/markdown.dart' as markdown;

/// Versioned, lossless rich documents coexist with existing Markdown strings.
/// Opening a legacy note does not rewrite it. The editor writes this envelope
/// only after an actual rich document edit.
class DocumentCodec {
  static quill.Document fromDelta(List<dynamic> operations) =>
      quill.Document.fromJson(operations);
  static bool isRich(String value) => value.startsWith('{"notedDocument":1,');

  static String encode(quill.Document document) => jsonEncode({
        'notedDocument': 1,
        'ops': document.toDelta().toJson(),
      });

  static quill.Document decode(String value) {
    if (isRich(value)) {
      final map = jsonDecode(value) as Map<String, dynamic>;
      return quill.Document.fromJson(map['ops'] as List<dynamic>);
    }
    return fromMarkdown(value);
  }

  static quill.Document fromMarkdown(String value) {
    if (value.isEmpty) return quill.Document();
    final html = markdown
        .markdownToHtml(value,
            extensionSet: markdown.ExtensionSet.gitHubFlavored)
        .replaceAllMapped(
          RegExp(r'<li([^>]*)>\s*<input([^>]*)>'),
          (match) =>
              '<li${match.group(1)} data-checked="${RegExp(r"\bchecked\b").hasMatch(match.group(2)!) ? 'true' : 'false'}">',
        );
    final delta = HtmlToDelta().convert(html);
    return quill.Document.fromJson(delta.toJson());
  }

  static String toPlainText(String value) {
    if (!isRich(value)) return fromMarkdown(value).toPlainText().trimRight();
    final map = jsonDecode(value) as Map<String, dynamic>;
    return (map['ops'] as List)
        .map((op) => op['insert'] is String ? op['insert'] as String : '')
        .join()
        .trimRight();
  }

  /// Portable HTML export, including inline styles and block/list semantics.
  static String toHtml(String value) {
    if (!isRich(value)) {
      return markdown.markdownToHtml(value,
          extensionSet: markdown.ExtensionSet.gitHubFlavored);
    }
    const escape = HtmlEscape(HtmlEscapeMode.element);
    final document = decode(value);
    final output = StringBuffer();
    var line = StringBuffer();
    for (final op in document.toDelta().toJson()) {
      final insert = op['insert'];
      if (insert is! String) continue;
      final attributes =
          Map<String, dynamic>.from(op['attributes'] as Map? ?? {});
      final pieces = insert.split('\n');
      for (var i = 0; i < pieces.length; i++) {
        if (pieces[i].isNotEmpty) {
          var text = escape.convert(pieces[i]);
          if (attributes['bold'] == true) text = '<strong>$text</strong>';
          if (attributes['italic'] == true) text = '<em>$text</em>';
          if (attributes['underline'] == true) text = '<u>$text</u>';
          if (attributes['strike'] == true) text = '<s>$text</s>';
          if (attributes['background'] != null) text = '<mark>$text</mark>';
          final size = attributes['size'];
          if (size != null && RegExp(r'^\d+(\.\d+)?$').hasMatch('$size')) {
            text =
                '<span style="font-size:${escape.convert('$size')}px">$text</span>';
          }
          line.write(text);
        }
        if (i < pieces.length - 1) {
          var body = line.toString();
          var tag = 'p';
          if (attributes['header'] is int) {
            tag = 'h${(attributes['header'] as int).clamp(1, 6)}';
          }
          if (attributes['blockquote'] == true) tag = 'blockquote';
          final list = attributes['list'];
          if (list == 'bullet' || list == 'ordered') {
            final outer = list == 'bullet' ? 'ul' : 'ol';
            output.write('<$outer><li>$body</li></$outer>');
          } else if (list == 'checked' || list == 'unchecked') {
            output.write(
                '<p><input type="checkbox" disabled${list == 'checked' ? ' checked' : ''}> $body</p>');
          } else {
            final alignment = attributes['align'];
            final align = ['center', 'right', 'justify'].contains(alignment)
                ? ' style="text-align:$alignment"'
                : '';
            if (body.isEmpty) body = '<br>';
            output.write('<$tag$align>$body</$tag>');
          }
          line = StringBuffer();
        }
      }
    }
    return output.toString();
  }
}
