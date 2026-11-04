import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/utils/document_codec.dart';
import 'package:noted/utils/markdown_formatter.dart';

void main() {
  test('mixed legacy checklist states migrate independently', () {
    final ops =
        DocumentCodec.fromMarkdown('- [x] Done\n- [ ] Next').toDelta().toJson();
    final states = ops
        .where((op) => op['attributes']?['list'] != null)
        .map((op) => op['attributes']['list'])
        .toList();
    expect(states, ['checked', 'unchecked']);
  });
  test('legacy formatting imports into editable document without markers', () {
    final document = DocumentCodec.fromMarkdown(
        '### Plan\n\n**Bold** and _italic_ and <u>underlined</u>\n\n- First');
    expect(document.toPlainText(), contains('Bold and italic and underlined'));
    final operations = document.toDelta().toJson();
    expect(operations.any((op) => op['attributes']?['bold'] == true), isTrue);
    expect(
        operations.any((op) => op['attributes']?['underline'] == true), isTrue);
  });
  test('rich styles roundtrip losslessly and export to portable HTML', () {
    final value = jsonEncode({
      'notedDocument': 1,
      'ops': [
        {
          'insert': 'Done',
          'attributes': {'bold': true, 'background': '#ffd66b'}
        },
        {
          'insert': '\n',
          'attributes': {'list': 'checked'}
        },
        {'insert': 'Centered'},
        {
          'insert': '\n',
          'attributes': {'align': 'center'}
        },
      ]
    });
    final decoded = DocumentCodec.decode(value);
    expect(DocumentCodec.encode(decoded), value);
    expect(MarkdownFormatter.toPlainText(value), 'Done\nCentered');
    expect(DocumentCodec.toHtml(value), contains('<strong>Done</strong>'));
    expect(DocumentCodec.toHtml(value),
        contains('type="checkbox" disabled checked'));
    expect(DocumentCodec.toHtml(value), contains('text-align:center'));
  });
  test('HTML export keeps inline private image references', () {
    const value =
        '{"notedDocument":1,"ops":[{"insert":"Before "},{"insert":{"image":"noted-media://note-media/users/u/notes/n/photo.png"}},{"insert":" after\\n"},{"insert":"<unsafe>"},{"insert":"\\n"}]}';
    final html = DocumentCodec.toHtml(value);
    expect(html, contains('Before '));
    expect(
        html,
        contains(
            '<img src="noted-media://note-media/users/u/notes/n/photo.png" alt="Note image">'));
    expect(html, contains('&lt;unsafe&gt;'));
    expect(html, isNot(contains('<unsafe>')));

    const unsafeImage =
        '{"notedDocument":1,"ops":[{"insert":{"image":"https://example.test/\\" onerror=\\"alert(1)"}},{"insert":"\\n"}]}';
    final unsafeHtml = DocumentCodec.toHtml(unsafeImage);
    expect(unsafeHtml, isNot(contains('onerror="')));
    expect(unsafeHtml, contains('&quot;'));
  });
  test('HTML export escapes note text', () {
    final value = jsonEncode({
      'notedDocument': 1,
      'ops': [
        {'insert': '<script>alert(1)</script>\n'}
      ]
    });
    expect(DocumentCodec.toHtml(value), contains('&lt;script&gt;'));
    expect(DocumentCodec.toHtml(value), isNot(contains('<script>')));
  });
}
