import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/repositories/auth_repository.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/add_edit_note_page.dart';
import 'package:noted/utils/app_theme.dart';
import 'package:noted/utils/markdown_formatter.dart';

class _Notes extends Fake implements NoteRepository {
  _Notes(this.note);
  final NoteModel note;
  @override
  Stream<NoteModel?> watchNote(String id) => Stream.value(note);
}

class _SavingNotes extends _Notes {
  _SavingNotes(super.note);
  final first = Completer<NoteModel>();
  final saved = <NoteModel>[];
  @override
  Future<NoteModel> saveCollaborative(NoteModel local, NoteModel base) {
    saved.add(local);
    if (saved.length == 1) return first.future;
    return Future.value(local.copyWith(revision: base.revision + 1));
  }
}

class _CreatingNotes extends _Notes {
  _CreatingNotes(super.note);
  final created = Completer<String>();
  final writes = <NoteModel>[];
  final deleted = <String>[];
  @override
  Future<void> deleteNote(String id) async => deleted.add(id);
  @override
  Stream<NoteModel?> watchNote(String id) => const Stream.empty();
  @override
  Future<String> createNote(NoteModel note) {
    writes.add(note);
    return created.future;
  }

  @override
  Future<NoteModel> saveCollaborative(NoteModel local, NoteModel base) async {
    writes.add(local);
    return local.copyWith(revision: base.revision + 1);
  }
}

class _DeletingNotes extends _Notes {
  _DeletingNotes(super.note);
  int deleted = 0, restored = 0;
  @override
  Future<void> deleteNote(String id) async {
    deleted++;
  }

  @override
  Future<void> restoreNote(String id) async {
    restored++;
  }
}

class _AuthRepository extends Fake implements AuthRepository {}

class _Auth extends AuthViewModel {
  _Auth() : super(_AuthRepository());
  @override
  UserModel get user => UserModel(
      uid: 'owner',
      name: 'Alex',
      email: 'alex@example.test',
      createdAt: DateTime(2026));
}

class _Settings extends SettingsViewModel {
  _Settings() : super(SettingsRepository());
  @override
  SettingsModel get settings => const SettingsModel(reduceMotion: true);
}

void main() {
  setUpAll(() async {
    for (final f in [
      ('DM Sans', 'assets/fonts/DMSans.ttf'),
      ('Newsreader', 'assets/fonts/Newsreader-Italic.ttf')
    ]) {
      await (FontLoader(f.$1)..addFont(rootBundle.load(f.$2))).load();
    }
  });
  testWidgets('delete waits for a new note creation and removes its result',
      (tester) async {
    final note = NoteModel.empty('owner');
    final repo = _CreatingNotes(note), auth = _Auth(), settings = _Settings();
    final notes = NoteViewModel(repo);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: auth),
          ChangeNotifierProvider<NoteViewModel>.value(value: notes),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settings)
        ],
        child: MaterialApp(
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => AddEditNotePage(
                                    note: note, repository: repo))),
                        child: const Text('Open note')))))));
    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    controller.replaceText(
        0, 0, 'Draft', const TextSelection.collapsed(offset: 5));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    repo.created.complete('created-note');
    await tester.pumpAndSettle();
    expect(repo.deleted, ['created-note']);
    expect(find.text('Open note'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    notes.dispose();
    settings.dispose();
  });
  testWidgets(
      'new note creation preserves typing received while the create is in flight',
      (tester) async {
    final note = NoteModel.empty('owner');
    final repo = _CreatingNotes(note), auth = _Auth(), settings = _Settings();
    final notes = NoteViewModel(repo);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: auth),
          ChangeNotifierProvider<NoteViewModel>.value(value: notes),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settings)
        ],
        child: MaterialApp(
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            home: AddEditNotePage(note: note, repository: repo))));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    controller.replaceText(
        0, 0, 'Hello', const TextSelection.collapsed(offset: 5));
    await tester.pump(const Duration(milliseconds: 700));
    expect(repo.writes, hasLength(1));
    controller.replaceText(
        5, 0, ' world', const TextSelection.collapsed(offset: 11));
    repo.created.complete('created-note');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(controller.document.toPlainText().trimRight(), 'Hello world');
    expect(repo.writes, hasLength(2));
    expect(
        MarkdownFormatter.toPlainText(repo.writes.last.content), 'Hello world');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    notes.dispose();
    settings.dispose();
  });
  testWidgets('deleting a note offers Undo and restores only that note',
      (tester) async {
    final note =
        NoteModel.empty('owner').copyWith(noteId: 'delete-me', title: 'Draft');
    final repo = _DeletingNotes(note), auth = _Auth(), settings = _Settings();
    final notes = NoteViewModel(repo);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: auth),
          ChangeNotifierProvider<NoteViewModel>.value(value: notes),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settings)
        ],
        child: MaterialApp(
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => AddEditNotePage(
                                    note: note, repository: repo))),
                        child: const Text('Open note')))))));
    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, 1);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.restored, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    notes.dispose();
    settings.dispose();
  });
  testWidgets('typing during a merged save is preserved and saved again',
      (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', title: 'Project', content: 'Hello');
    final repo = _SavingNotes(note);
    final auth = _Auth();
    final notes = NoteViewModel(repo);
    final settings = _Settings();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: auth),
          ChangeNotifierProvider<NoteViewModel>.value(value: notes),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settings)
        ],
        child: MaterialApp(
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            home: AddEditNotePage(note: note, repository: repo))));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    controller.replaceText(
        5, 0, ' local', const TextSelection.collapsed(offset: 11));
    await tester.pump(const Duration(milliseconds: 700));
    expect(repo.saved, hasLength(1));
    controller.replaceText(
        11, 0, ' later', const TextSelection.collapsed(offset: 17));
    repo.first.complete(
        repo.saved.first.copyWith(content: 'Remote Hello local', revision: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(controller.document.toPlainText().trimRight(),
        'Remote Hello local later');
    expect(repo.saved, hasLength(2));
    expect(MarkdownFormatter.toPlainText(repo.saved.last.content),
        'Remote Hello local later');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    notes.dispose();
    settings.dispose();
  });
  for (final width in [360.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('rich editor at $width ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final note = NoteModel.empty('owner').copyWith(
            noteId: 'note',
            title: 'Weekly Project Notes',
            createdAt: DateTime(2026, 10, 26, 9),
            updatedAt: DateTime(2026, 10, 26, 9),
            content:
                '**Write together**\n\n- [x] Draft the user flow\n- [ ] Review the prototype');
        final repo = _Notes(note);
        final auth = _Auth();
        final notes = NoteViewModel(repo);
        final settings = _Settings();
        await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthViewModel>.value(value: auth),
              ChangeNotifierProvider<NoteViewModel>.value(value: notes),
              ChangeNotifierProvider<SettingsViewModel>.value(value: settings)
            ],
            child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                localizationsDelegates: const [
                  FlutterQuillLocalizations.delegate
                ],
                home: RepaintBoundary(
                    key: const ValueKey('editor-preview'),
                    child: AddEditNotePage(note: note, repository: repo)))));
        await tester.pumpAndSettle();
        if (width == 390) {
          await expectLater(
              find.byKey(const ValueKey('editor-preview')),
              matchesGoldenFile(
                  'goldens/editor_390_${dark ? 'dark' : 'light'}.png'));
        }
        expect(find.byType(QuillEditor), findsOneWidget);
        expect(find.textContaining('**'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        notes.dispose();
        settings.dispose();
      });
    }
  }
}
