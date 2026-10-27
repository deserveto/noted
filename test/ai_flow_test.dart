import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/repositories/ai_repository.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/ai_page.dart';
import 'package:noted/widgets/ai_blocks.dart';
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
      String? selectionNoteId}) {
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
      String? selectionNoteId}) {
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
}
