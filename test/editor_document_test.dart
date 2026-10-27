import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/widgets/markdown_content.dart';
import 'package:noted/utils/markdown_formatter.dart';
import 'package:noted/utils/document_codec.dart';

void main() {
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
