import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/utils/collaborative_document.dart';
import 'package:noted/utils/document_codec.dart';

String rich(List<Map<String, dynamic>> ops) =>
    jsonEncode({'notedDocument': 1, 'ops': ops});
void main() {
  test('concurrent insertions preserve both writers', () {
    final result = mergeContent(
        base: 'Hello', local: 'Hello local', remote: 'Remote Hello');
    expect(DocumentCodec.toPlainText(result), 'Remote Hello local');
  });
  test('same-position insertions both survive with stable remote priority', () {
    final result =
        mergeContent(base: 'word', local: 'A word', remote: 'B word');
    expect(DocumentCodec.toPlainText(result), 'B A word');
  });
  test('concurrent formatting and insertion both survive', () {
    final base = rich([
      {'insert': 'Hello\n'}
    ]);
    final local = rich([
      {
        'insert': 'Hello',
        'attributes': {'bold': true}
      },
      {'insert': '\n'}
    ]);
    final remote = rich([
      {'insert': 'Hello world\n'}
    ]);
    final result = mergeContent(base: base, local: local, remote: remote);
    final ops = DocumentCodec.decode(result).toDelta().toJson();
    expect(DocumentCodec.toPlainText(result), 'Hello world');
    expect(
        ops.any((op) =>
            op['insert'] == 'Hello' && op['attributes']?['bold'] == true),
        isTrue);
  });
  test('delete and distant insertion merge without restoring deleted text', () {
    final result = mergeContent(
        base: 'First middle last',
        local: 'First last',
        remote: 'First middle last added');
    expect(DocumentCodec.toPlainText(result), 'First last added');
  });
  test('unchanged writer preserves original storage exactly', () {
    expect(
        mergeContent(base: '**Hello**', local: '**Hello**', remote: 'Remote'),
        'Remote');
  });
}
