import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:noted/utils/document_codec.dart';
import 'package:noted/utils/note_image_document.dart';

quill.Document _document(String value) => DocumentCodec.decode(value);

String _content(List<Map<String, dynamic>> ops) =>
    DocumentCodec.encode(quill.Document.fromJson(ops));

String _paragraphs() => _content([
      {'insert': 'Alpha\n'},
      {'insert': 'Beta\n'},
      {'insert': 'Gamma\n'},
    ]);

void main() {
  test('image insertion before, between and after paragraphs is exact', () {
    for (final (offset, expected) in [
      (
        0,
        [
          {
            'insert': {'image': 'private://image'}
          },
          {'insert': 'Alpha\nBeta\nGamma\n'},
        ]
      ),
      (
        6,
        [
          {'insert': 'Alpha\n'},
          {
            'insert': {'image': 'private://image'}
          },
          {'insert': 'Beta\nGamma\n'},
        ]
      ),
      (
        11,
        [
          {'insert': 'Alpha\nBeta\n'},
          {
            'insert': {'image': 'private://image'}
          },
          {'insert': 'Gamma\n'},
        ]
      ),
      (
        16,
        [
          {'insert': 'Alpha\nBeta\nGamma'},
          {
            'insert': {'image': 'private://image'}
          },
          {'insert': '\n'},
        ]
      ),
    ]) {
      final controller = quill.QuillController(
        document: _document(_paragraphs()),
        selection: TextSelection.collapsed(offset: offset),
      );
      expect(
        NoteImageDocument.insertImage(controller, offset, 'private://image'),
        isTrue,
      );
      expect(controller.document.toDelta().toJson(), expected);
      expect(
          NoteImageDocument.images(controller.document).single.index, offset);
      expect(controller.selection.baseOffset, offset + 1);
      controller.dispose();
    }
  });

  test('moving an image is one atomic change and undo/redo preserves text', () {
    final controller = quill.QuillController(
      document: _document(_paragraphs()),
      selection: const TextSelection.collapsed(offset: 0),
    );
    NoteImageDocument.insertImage(controller, 0, 'private://image');
    final original = controller.document.toDelta().toJson();
    controller.document.history.lastRecorded = 0;

    expect(NoteImageDocument.moveImage(controller, from: 0, to: 12), isTrue);
    expect(NoteImageDocument.images(controller.document), hasLength(1));
    expect(NoteImageDocument.images(controller.document).single.index, 11);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', ''),
        'Alpha\nBeta\nGamma\n');

    controller.undo();
    expect(controller.document.toDelta().toJson(), original);
    controller.redo();
    expect(NoteImageDocument.images(controller.document).single.index, 11);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', ''),
        'Alpha\nBeta\nGamma\n');
    controller.dispose();
  });

  test('insertion anchor follows local edits and remote document replacement',
      () {
    var document = _document(_paragraphs());
    final anchor = DocumentInsertionAnchor(document: document, offset: 6);

    document.replace(0, 0, 'Intro ');
    anchor.update(document);
    expect(anchor.offset, 12);

    // Text typed exactly at the anchor keeps the original insertion intent.
    document.replace(anchor.offset, 0, 'typed ');
    anchor.update(document);
    expect(anchor.offset, 12);

    // Remote replacement shifts the anchor by the inserted prefix.
    document = _document(_content([
      {'insert': 'Remote\n'},
      {'insert': 'Intro Alpha\n'},
      {'insert': 'Beta\n'},
      {'insert': 'Gamma\n'},
    ]));
    anchor.update(document);
    expect(anchor.offset, 19);
    expect(anchor.offset, inInclusiveRange(0, document.length - 1));
    expect(document.toPlainText().substring(anchor.offset).startsWith('Beta'),
        isTrue);
  });

  test('image source anchor follows shifts and becomes invalid after deletion',
      () {
    var document = _document(_paragraphs());
    NoteImageDocument.insertImage(
      quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      ),
      0,
      'private://image',
    );
    final imageIndex = NoteImageDocument.images(document).single.index;
    final anchor = DocumentImageAnchor(
      document: document,
      reference: 'private://image',
      index: imageIndex,
    );
    expect(anchor.isValid, isTrue);

    document.replace(0, 0, 'Intro ');
    anchor.update(document);
    expect(anchor.index, 6);
    expect(anchor.isValid, isTrue);

    document.replace(anchor.index, 1, '');
    anchor.update(document);
    expect(anchor.isValid, isFalse);
  });
}
