import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/widgets/ai_blocks.dart';
import 'package:noted/repositories/ai_repository.dart';

void main() {
  test('flashcard decks preserve structured questions and answers', () {
    expect(
        extractFlashcards([
          {'t': 'p', 'x': 'Introduction'},
          {
            't': 'cards',
            'items': [
              {'q': 'Question', 'a': 'Answer'},
              {'q': '', 'a': 'Invalid'}
            ]
          }
        ]),
        [
          {'q': 'Question', 'a': 'Answer'}
        ]);
  });
  test('saving action items preserves completion state', () {
    final markdown = blocksMarkdown([
      {
        't': 'todo',
        'items': [
          {'x': 'Finished', 'done': true},
          {'x': 'Pending', 'done': false}
        ]
      }
    ]);
    expect(markdown, contains('- [x] Finished'));
    expect(markdown, contains('- [ ] Pending'));
  });
  testWidgets('service flashcards can be revealed and navigated',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AiBlocks(blocks: [
      {
        't': 'cards',
        'items': [
          {'q': 'First question', 'a': 'First answer'},
          {'q': 'Second question', 'a': 'Second answer'}
        ]
      }
    ]))));
    expect(find.text('First question'), findsOneWidget);
    await tester.tap(find.text('First question'));
    await tester.pumpAndSettle();
    expect(find.text('First answer'), findsOneWidget);
    await tester.tap(find.byTooltip('Next card'));
    await tester.pumpAndSettle();
    expect(find.text('Second question'), findsOneWidget);
  });
}
