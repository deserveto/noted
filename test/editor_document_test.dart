import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/widgets/markdown_content.dart';
import 'package:noted/utils/markdown_formatter.dart';
import 'package:noted/utils/document_codec.dart';
import 'package:noted/utils/inline_ai_edit.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

void main() {
  test(
      'inline AI inserts below the selected line and rejects changed selection',
      () {
    final controller = quill.QuillController.basic();
    controller.replaceText(0, 0, 'First line\nNext line',
        const TextSelection.collapsed(offset: 0));
    const selection = TextSelection(baseOffset: 0, extentOffset: 5);
    controller.updateSelection(selection, quill.ChangeSource.local);
    final snapshot = DocumentCodec.encode(controller.document);
    expect(
        applyInlineAiEdit(controller, selection, snapshot, 'Added',
            replace: false),
        isTrue);
    expect(controller.document.toPlainText(), 'First line\nAdded\nNext line\n');
    expect(
        applyInlineAiEdit(controller, selection, snapshot, 'Late',
            replace: true),
        isFalse);
  });
  test('inline AI checklist keeps checklist formatting and surrounding text',
      () {
    final controller = quill.QuillController.basic();
    controller.replaceText(0, 0, 'Before\nselected\nAfter',
        const TextSelection.collapsed(offset: 0));
    const selection = TextSelection(baseOffset: 7, extentOffset: 15);
    controller.updateSelection(selection, quill.ChangeSource.local);
    final snapshot = DocumentCodec.encode(controller.document);
    expect(
        applyInlineAiEdit(controller, selection, snapshot, '- [ ] Task',
            replace: true),
        isTrue);
    final operations = controller.document.toDelta().toJson();
    expect(operations.any((op) => op['attributes']?['list'] == 'unchecked'),
        isTrue);
    expect(controller.document.toPlainText(), contains('Before\nTask\nAfter'));
    expect(
        applyInlineAiEdit(controller, selection, snapshot, 'stale',
            replace: true),
        isFalse);
  });
  testWidgets('imported image embed keeps the rich document readable',
      (tester) async {
    final document = DocumentCodec.fromMarkdown(
        'Before\n\n![Image](file:///private.png)\n\nAfter');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarkdownContent(
      content: DocumentCodec.encode(document),
    ))));
    expect(find.text('Image unavailable'), findsOneWidget);
    expect(find.textContaining('After', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('checklist toggles only the selected document line',
      (tester) async {
    String? changed;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarkdownContent(
                content: '- [ ] First\n- [x] Second',
                onChanged: (value) => changed = value))));
    await tester.tap(find.byType(Checkbox).first);
    expect(changed, '- [x] First\n- [x] Second');
  });
  testWidgets('heading and quote render without source markers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: MarkdownContent(content: '### Plan\n> Remember'))));
    expect(find.text('Plan', findRichText: true), findsOneWidget);
    expect(find.text('Remember', findRichText: true), findsOneWidget);
  });
  test('plain preview strips editor markup and checklist markers', () {
    expect(MarkdownFormatter.toPlainText('### Plan\n- [x] <mark>Done</mark>'),
        'Plan\nDone');
  });
}
