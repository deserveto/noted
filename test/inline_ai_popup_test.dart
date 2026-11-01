import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/repositories/ai_repository.dart';
import 'package:noted/widgets/inline_ai_popup.dart';
import 'package:noted/utils/app_theme.dart';

class _Ai extends Fake implements AiRepository {
  final response = Completer<Map<String, dynamic>>();
  String? prompt;
  int calls = 0;
  bool? selectionOnly;
  @override
  String newId() => 'request';
  @override
  Future<Map<String, dynamic>> ask(
      {required String prompt,
      required Map<String, dynamic> scope,
      required String chatId,
      required String requestId,
      String? selection,
      String? selectionNoteId,
      bool selectionOnly = false}) {
    this.prompt = prompt;
    this.selectionOnly = selectionOnly;
    calls++;
    return response.future;
  }

  @override
  Future<void> stop(String requestId) async {}
}

void main() {
  setUpAll(() async {
    await (FontLoader('DM Sans')
          ..addFont(rootBundle.load('assets/fonts/DMSans.ttf')))
        .load();
  });
  testWidgets('tone picker sends only the selected tone and retries it',
      (tester) async {
    final ai = _Ai();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 328,
      height: 440,
      child: InlineAiPopup(
          selection: 'Hello there',
          noteId: 'note',
          repository: ai,
          onApply: (_, __) => true),
    )))));
    await tester.tap(find.text('Tone'));
    await tester.pumpAndSettle();
    expect(ai.calls, 0);
    expect(find.text('Choose a tone'), findsOneWidget);
    expect(find.text('Professional'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to edits'));
    await tester.pumpAndSettle();
    expect(find.text('Rewrite'), findsOneWidget);
    expect(ai.calls, 0);
    await tester.tap(find.text('Tone'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Casual'));
    await tester.tap(find.text('Casual'));
    await tester.pump();
    expect(ai.calls, 1);
    expect(ai.selectionOnly, isTrue);
    expect(ai.prompt, contains('casual'));
    expect(ai.prompt, contains('selected text'));
    ai.response.complete({
      'blocks': [
        {'t': 'p', 'x': 'Hey there'}
      ]
    });
    await tester.pumpAndSettle();
    expect(find.text('Hey there'), findsOneWidget);
    expect(find.text('Change tone'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(ai.calls, 2);
    expect(ai.prompt, contains('casual'));
  });
  testWidgets('tone picker scrolls to the last option', (tester) async {
    final ai = _Ai();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 300,
      height: 400,
      child: InlineAiPopup(
          selection: 'A sentence',
          noteId: 'note',
          repository: ai,
          onApply: (_, __) => true),
    )))));
    await tester.tap(find.text('Tone'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Neutral'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neutral'));
    await tester.pump();
    expect(ai.prompt, contains('neutral'));
    ai.response.complete({
      'blocks': [
        {'t': 'p', 'x': 'A sentence.'}
      ]
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change tone'));
    await tester.pumpAndSettle();
    expect(find.text('Professional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('tone picker remains usable with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 288,
                        height: 400,
                        child: InlineAiPopup(
                            selection: 'A sentence',
                            noteId: 'note',
                            repository: _Ai(),
                            onApply: (_, __) => true)))))));
    await tester.tap(find.text('Tone'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Neutral'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('tone picker preview ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
          key: const ValueKey('tone-popup'),
          child: SizedBox(
              width: 328,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: InlineAiPopup(
                    selection: 'Selected text',
                    noteId: 'note',
                    repository: _Ai(),
                    onApply: (_, __) => true),
              )),
        ))),
      ));
      await tester.tap(find.text('Tone'));
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(const ValueKey('tone-popup')),
          matchesGoldenFile(
              'goldens/inline_ai_tone_${dark ? 'dark' : 'light'}.png'));
      expect(tester.takeException(), isNull);
    });
    for (final result in [false, true]) {
      testWidgets(
          'inline popup ${result ? 'result' : 'actions'} preview ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ai = _Ai();
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
              body: Center(
                  child: RepaintBoundary(
            key: const ValueKey('inline-popup'),
            child: SizedBox(
                width: 328,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 440),
                  child: InlineAiPopup(
                      selection: 'We have a lot of things happening at once.',
                      noteId: 'note',
                      repository: ai,
                      onApply: (_, __) => true),
                )),
          ))),
        ));
        if (result) {
          await tester.tap(find.text('Rewrite'));
          await tester.pump();
          ai.response.complete({
            'blocks': [
              {'t': 'p', 'x': 'Several initiatives are underway at once.'}
            ]
          });
          await tester.pumpAndSettle();
        }
        await expectLater(
            find.byKey(const ValueKey('inline-popup')),
            matchesGoldenFile(
                'goldens/inline_ai_${result ? 'result' : 'actions'}_${dark ? 'dark' : 'light'}.png'));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('inline actions stay reachable at large text sizes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 288,
                        height: 400,
                        child: InlineAiPopup(
                            selection: 'Text',
                            noteId: 'note',
                            repository: _Ai(),
                            onApply: (_, __) => true)))))));
    await tester.ensureVisible(find.text('Checklist'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('inline result fits at large text sizes', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ai = _Ai();
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 288,
                        height: 400,
                        child: InlineAiPopup(
                            selection: 'Selected text',
                            noteId: 'note',
                            repository: ai,
                            onApply: (_, __) => true)))))));
    await tester.tap(find.text('Rewrite'));
    await tester.pump();
    ai.response.complete({
      'blocks': [
        {'t': 'p', 'x': 'A suggested revision.'}
      ]
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Insert below'), findsOneWidget);
  });
  testWidgets(
      'inline popup previews a selection and applies only on confirmation',
      (tester) async {
    final ai = _Ai();
    String? applied;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineAiPopup(
      selection: 'Original text',
      noteId: 'note',
      repository: ai,
      onApply: (value, replace) {
        applied = value;
        return true;
      },
    ))));
    await tester.tap(find.text('Rewrite'));
    await tester.pump();
    expect(ai.prompt, contains('selected text'));
    ai.response.complete({
      'blocks': [
        {'t': 'p', 'x': 'Revised text'}
      ]
    });
    await tester.pumpAndSettle();
    expect(find.text('Original text'), findsOneWidget);
    expect(find.text('Revised text'), findsOneWidget);
    expect(applied, isNull);
    await tester.tap(find.text('Replace'));
    expect(applied, 'Revised text');
  });
}
