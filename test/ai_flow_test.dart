import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/repositories/ai_repository.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/ai_page.dart';
import 'package:noted/widgets/ai_blocks.dart';
import 'package:noted/widgets/noted_ui.dart';
import 'package:noted/widgets/reference_icon.dart';
import 'package:noted/utils/app_theme.dart';

class TestAi extends Fake implements AiRepository {
  int ids = 0, stops = 0;
  Map<String, dynamic>? scope;
  final answer = Completer<Map<String, dynamic>>();
  @override
  String newId() => 'id${ids++}';
  @override
  Future<Map<String, dynamic>> ask(
      {required String prompt,
      required Map<String, dynamic> scope,
      required String chatId,
      required String requestId,
      String? selection,
      String? selectionNoteId,
      bool selectionOnly = false}) {
    this.scope = scope;
    return answer.future;
  }

  @override
  Future<void> stop(String requestId) async {
    stops++;
  }
}

class DelayedStopAi extends TestAi {
  final cancellation = Completer<void>();
  final secondAnswer = Completer<Map<String, dynamic>>();
  int requests = 0;
  @override
  Future<Map<String, dynamic>> ask(
      {required String prompt,
      required Map<String, dynamic> scope,
      required String chatId,
      required String requestId,
      String? selection,
      String? selectionNoteId,
      bool selectionOnly = false}) {
    return requests++ == 0 ? answer.future : secondAnswer.future;
  }

  @override
  Future<void> stop(String requestId) => cancellation.future;
}

class AiNotes extends ChangeNotifier implements NoteViewModel {
  @override
  List<NoteModel> get notes =>
      [NoteModel.empty('user').copyWith(noteId: 'one', title: 'Project ideas')];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AiSettings extends ChangeNotifier implements SettingsViewModel {
  AiSettings({this.history = false});
  final bool history;
  int _epoch = 0;
  @override
  int get aiHistoryEpoch => _epoch;
  @override
  void invalidateAiHistory() {
    _epoch++;
    notifyListeners();
  }

  @override
  SettingsModel get settings =>
      SettingsModel(aiHistory: history, reduceMotion: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget harness(TestAi repo, {AiSettings? preferences}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NoteViewModel>(create: (_) => AiNotes()),
          ChangeNotifierProvider<SettingsViewModel>(
              create: (_) => preferences ?? AiSettings())
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: AiPage(
                repository: repo,
                initialNoteIds: const ['one'],
                initialPrompt: 'Summarize this note')));
void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'selected AI scope label has accessible contrast in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final theme = dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NoteViewModel>(create: (_) => AiNotes()),
          ChangeNotifierProvider<SettingsViewModel>(
              create: (_) => AiSettings()),
        ],
        child: MaterialApp(theme: theme, home: AiPage(repository: TestAi())),
      ));
      final label = find.text('All notes').first;
      final color = DefaultTextStyle.of(tester.element(label)).style.color!;
      final bg = theme.chipTheme.selectedColor!;
      final contrast =
          (color.computeLuminance() + .05) / (bg.computeLuminance() + .05);
      expect(contrast > 1 ? contrast : 1 / contrast, greaterThanOrEqualTo(4.5));
    });
  }
  testWidgets(
      'flashcard answers are saved as decks instead of inserted as text',
      (tester) async {
    final repo = TestAi();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteViewModel>(create: (_) => AiNotes()),
        ChangeNotifierProvider<SettingsViewModel>(create: (_) => AiSettings()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: AiPage(
            repository: repo,
            compact: true,
            initialNoteIds: const ['one'],
            initialPrompt: 'Make flashcards',
            onInsert: (_) {}),
      ),
    ));
    await tester.pump();
    repo.answer.complete({
      'blocks': [
        {
          't': 'cards',
          'items': [
            {'q': 'Question', 'a': 'Answer'}
          ]
        }
      ],
      'sources': <String>[]
    });
    await tester.pumpAndSettle();
    expect(find.text('Save to study decks'), findsOneWidget);
    expect(find.text('Insert into note'), findsNothing);
    expect(find.text('Save as note'), findsNothing);
  });
  testWidgets(
      'selected text offers inline editing with a before and after preview',
      (tester) async {
    final repo = TestAi();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteViewModel>(create: (_) => AiNotes()),
        ChangeNotifierProvider<SettingsViewModel>(create: (_) => AiSettings()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: AiPage(
            repository: repo,
            compact: true,
            initialNoteIds: const ['one'],
            selection: 'Original text',
            selectionNoteId: 'one',
            onInlineEdit: (_, __) => true),
      ),
    ));
    await tester.tap(find.text('Rewrite'));
    await tester.pump();
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'Improved text'}
      ],
      'sources': <String>[]
    });
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('Original text'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Improved text'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Insert below'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
  testWidgets('AI landing presents the four primary actions', (tester) async {
    final repo = TestAi();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteViewModel>(create: (_) => AiNotes()),
        ChangeNotifierProvider<SettingsViewModel>(create: (_) => AiSettings()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: AiPage(repository: repo)),
    ));
    expect(find.text('Ask Noted'), findsWidgets);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'This note'))
            .onSelected,
        isNull);
    expect(find.text('Summarize notes'), findsOneWidget);
    expect(find.text('Extract action tasks'), findsOneWidget);
    expect(find.text('Identify key decisions'), findsOneWidget);
    expect(find.text('Generate flashcards'), findsOneWidget);
  });
  testWidgets('feedback buttons stay together on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = TestAi();
    await tester.pumpWidget(harness(repo));
    await tester.pump();
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'Answer'}
      ],
      'sources': <String>[],
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Not helpful'));
    await tester.pumpAndSettle();
    final up = tester.getRect(find.byTooltip('Helpful'));
    final down = tester.getRect(find.byTooltip('Not helpful'));
    expect(up.top, down.top);
    expect(up.right, lessThanOrEqualTo(down.left));
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact AI keeps conversation space above the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repo = TestAi();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteViewModel>(create: (_) => AiNotes()),
        ChangeNotifierProvider<SettingsViewModel>(create: (_) => AiSettings()),
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => notedSheet<void>(context,
                          label: 'AI',
                          tall: true,
                          builder: (_) => AiPage(
                              compact: true,
                              repository: repo,
                              initialNoteIds: const ['one'])),
                      child: const Text('Open'),
                    ),
                  ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final iconBeforeKeyboard = tester.getRect(find.descendant(
        of: find.byTooltip('Send'), matching: find.byType(ReferenceIcon)));
    expect(iconBeforeKeyboard.center.dx, greaterThan(340));
    final paintedIcon = tester.getRect(find.descendant(
        of: find.byTooltip('Send'), matching: find.byType(SvgPicture)));
    // Test the painted icon, not only the accessible button bounds.
    expect(paintedIcon.center.dx, greaterThan(340));
    await tester.tap(find.text('Summarize this note'));
    await tester.pump();
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'A useful response'}
      ],
      'sources': <String>[],
    });
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final conversation = find
        .descendant(of: find.byType(AiPage), matching: find.byType(ListView))
        .first;
    expect(tester.getSize(conversation).height, greaterThan(150));
    final send = tester.getRect(find.byTooltip('Send'));
    expect(send.right, greaterThan(340));
    final sendIcon = tester.getRect(find.descendant(
        of: find.byTooltip('Send'), matching: find.byType(ReferenceIcon)));
    expect(sendIcon.center.dx, greaterThan(340));
    expect(send.bottom, lessThanOrEqualTo(544));
    expect(tester.takeException(), isNull);
  });
  testWidgets('late cancellation cannot discard a subsequent answer',
      (tester) async {
    final repo = DelayedStopAi();
    await tester.pumpWidget(harness(repo));
    await tester.pump();
    await tester.tap(find.byTooltip('Stop generating'));
    await tester.pump();
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'First answer'}
      ],
      'sources': []
    });
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Second question');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    repo.cancellation.complete();
    await tester.pump();
    repo.secondAnswer.complete({
      'blocks': [
        {'t': 'p', 'x': 'Second answer'}
      ],
      'sources': []
    });
    await tester.pumpAndSettle();
    expect(find.text('Second answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('AI sends the selected scope and displays only returned sources',
      (tester) async {
    final repo = TestAi();
    await tester.pumpWidget(harness(repo));
    await tester.pump();
    expect(repo.scope, {
      'kind': 'notes',
      'ids': ['one']
    });
    expect(find.byTooltip('Stop generating'), findsOneWidget);
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'A response from the provider.'}
      ],
      'sources': ['one'],
      'intent': 'summary',
      'messageId': 'message'
    });
    await tester.pumpAndSettle();
    expect(find.text('A response from the provider.'), findsOneWidget);
    expect(find.text('Project ideas'), findsWidgets);
    expect(find.text('Based on 1 note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Stop aborts the request and discards a late response',
      (tester) async {
    final repo = TestAi();
    await tester.pumpWidget(harness(repo));
    await tester.pump();
    await tester.tap(find.byTooltip('Stop generating'));
    await tester.pump();
    expect(repo.stops, 1);
    expect(find.text('Stopped. Nothing was written.'), findsOneWidget);
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'Late response'}
      ],
      'sources': []
    });
    await tester.pumpAndSettle();
    expect(find.text('Late response'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'clearing history also removes the active conversation from memory',
      (tester) async {
    final repo = TestAi(), settings = AiSettings(history: true);
    await tester.pumpWidget(harness(repo, preferences: settings));
    await tester.pump();
    repo.answer.complete({
      'blocks': [
        {'t': 'p', 'x': 'Saved conversation'}
      ],
      'sources': [],
      'intent': 'summary',
      'messageId': 'message'
    });
    await tester.pumpAndSettle();
    expect(find.text('Saved conversation'), findsOneWidget);
    settings.invalidateAiHistory();
    await tester.pumpAndSettle();
    expect(find.text('Saved conversation'), findsNothing);
    expect(find.text('Summarize this note'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('flashcards reveal answers and move between cards',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
            body: Flashcards(cards: [
          {'q': 'First question', 'a': 'First answer'},
          {'q': 'Next question', 'a': 'Next answer'}
        ]))));
    expect(find.text('First question'), findsOneWidget);
    await tester.tap(find.text('Tap to reveal'));
    await tester.pumpAndSettle();
    expect(find.text('First answer'), findsOneWidget);
    await tester.tap(find.byTooltip('Next card'));
    await tester.pumpAndSettle();
    expect(find.text('Next question'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('AI prompt field does not autofocus on open', (tester) async {
    final repo = TestAi();
    await tester.pumpWidget(harness(repo));
    final textField = tester.widget<TextField>(find.byType(TextField).last);
    expect(textField.autofocus, isFalse);
  });
}
