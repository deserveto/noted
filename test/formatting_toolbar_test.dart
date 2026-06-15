import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/widgets/formatting_toolbar.dart';

void main() {
  testWidgets('bold button is a one-shot inline formatter', (tester) async {
    final controller = TextEditingController(text: 'Hello ');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FormattingToolbar(controller: controller)),
      ),
    );

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(controller.text, 'Hello ****');
    expect(controller.selection.baseOffset, 8);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(controller.text, 'Hello ********');
    expect(controller.selection.baseOffset, 10);
  });

  testWidgets('bullet mode continues after new lines until toggled off',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FormattingToolbar(controller: controller)),
      ),
    );

    await tester.tap(find.byTooltip('Bullets'));
    await tester.pump();

    expect(controller.text, '- ');

    controller.value = const TextEditingValue(
      text: '- first\n',
      selection: TextSelection.collapsed(offset: 8),
    );
    await tester.pump();

    expect(controller.text, '- first\n- ');

    await tester.tap(find.byTooltip('Bullets'));
    await tester.pump();
    controller.value = const TextEditingValue(
      text: '- first\n- second\n',
      selection: TextSelection.collapsed(offset: 17),
    );
    await tester.pump();

    expect(controller.text, '- first\n- second\n');
  });
}
