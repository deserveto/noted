import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/views/notes_page.dart';
import 'package:noted/widgets/calendar_sheet.dart';
import 'package:noted/utils/app_theme.dart';

class LayoutNotes extends ChangeNotifier implements NoteViewModel {
  String query = '', category = 'All';
  int revision = 0;
  LibraryFilter filter = LibraryFilter.all;
  NoteSort sorting = NoteSort.lastEdited;
  @override
  final notes = [
    NoteModel.empty('fixture').copyWith(
        noteId: 'one',
        title: 'Weekly Project Notes',
        content:
            'Draft the user flow. Review the next steps with the team and prepare a clear outline.',
        category: 'Projects',
        color: 'yellow',
        isFavorite: true,
        createdAt: DateTime(2026, 10, 26)),
    NoteModel.empty('fixture').copyWith(
        noteId: 'two',
        title: 'A quiet place for ideas',
        content:
            'Write something worth remembering. Keep the little details close.',
        category: 'Personal',
        color: 'pink',
        createdAt: DateTime(2026, 10, 26)),
    NoteModel.empty('fixture').copyWith(
        noteId: 'three',
        title: 'Research notes',
        content: 'Record observations and the questions that follow.',
        category: 'Research',
        color: 'blue',
        createdAt: DateTime(2026, 10, 24)),
  ];
  @override
  List<NoteModel> get filteredNotes => notes
      .where((n) =>
          (filter != LibraryFilter.favorites || n.isFavorite) &&
          (filter != LibraryFilter.live || n.isLive) &&
          (category == 'All' || n.category == category) &&
          n.matches(query))
      .toList();
  @override
  List<NoteModel> get pendingSharedNotes => [];
  @override
  List<String> get categories => ['Personal', 'Projects', 'Research'];
  @override
  int get totalNotes => notes.length;
  @override
  int get totalFavorites => 1;
  @override
  int get totalLive => 0;
  @override
  LibraryFilter get libraryFilter => filter;
  @override
  NoteSort get sort => sorting;
  @override
  String get selectedCategory => category;
  @override
  String get searchQuery => query;
  @override
  int get searchRevision => revision;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  void updateSearch(String q) {
    query = q;
    revision++;
    notifyListeners();
  }

  @override
  void updateCategory(String c) {
    category = c;
    notifyListeners();
  }

  @override
  void updateLibraryFilter(LibraryFilter f) {
    filter = f;
    notifyListeners();
  }

  @override
  void updateSort(NoteSort s) {
    sorting = s;
    notifyListeners();
  }

  @override
  Future<void> toggleFavorite(NoteModel n) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LayoutSettings extends SettingsViewModel {
  LayoutSettings(this.value) : super(SettingsRepository());
  final SettingsModel value;
  @override
  SettingsModel get settings => value;
}

Widget harness(Widget child, LayoutNotes vm, bool dark) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NoteViewModel>.value(value: vm),
          ChangeNotifierProvider<SettingsViewModel>(
              create: (_) =>
                  LayoutSettings(const SettingsModel(reduceMotion: true)))
        ],
        child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!),
            home: RepaintBoundary(
                key: const ValueKey('screen'), child: Scaffold(body: child))));
void main() {
  setUpAll(() async {
    for (final f in [
      ('DM Sans', 'assets/fonts/DMSans.ttf'),
      ('Newsreader', 'assets/fonts/Newsreader-Italic.ttf')
    ]) {
      await (FontLoader(f.$1)..addFont(rootBundle.load(f.$2))).load();
    }
  });
  testWidgets('external library reset clears the visible search',
      (tester) async {
    final vm = LayoutNotes();
    await tester.pumpWidget(harness(const NotesPage(), vm, false));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'quiet');
    await tester.pump(const Duration(milliseconds: 221));
    expect(vm.filteredNotes.single.noteId, 'two');
    vm.updateSearch('');
    vm.updateLibraryFilter(LibraryFilter.favorites);
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(vm.filteredNotes.single.noteId, 'one');
    expect(tester.takeException(), isNull);
  });
  testWidgets('external reset cancels a search before its debounce fires',
      (tester) async {
    final vm = LayoutNotes();
    await tester.pumpWidget(harness(const NotesPage(), vm, false));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'quiet');
    expect(vm.searchQuery, isEmpty);
    vm.updateSearch('');
    vm.updateCategory('All');
    vm.updateLibraryFilter(LibraryFilter.favorites);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(vm.searchQuery, isEmpty);
    expect(vm.filteredNotes.single.noteId, 'one');
    expect(tester.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('library and calendar fit $width ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final vm = LayoutNotes();
        await tester.pumpWidget(harness(const NotesPage(), vm, dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width == 390) {
          await expectLater(
              find.byKey(const ValueKey('screen')),
              matchesGoldenFile(
                  'goldens/library_390_${dark ? 'dark' : 'light'}.png'));
        }
        await tester.tap(find.text('Favorites'));
        await tester.pumpAndSettle();
        expect(vm.filteredNotes.length, 1);
        await tester.tap(find.text('All').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'quiet');
        await tester.pump(const Duration(milliseconds: 221));
        expect(vm.filteredNotes.single.noteId, 'two');
        await tester.pumpWidget(harness(
            CalendarSheet(
                initial: DateTime(2026, 10, 26), today: DateTime(2026, 10, 26)),
            vm,
            dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('3 notes · 2 active days'), findsOneWidget);
        if (width == 390) {
          await expectLater(
              find.byKey(const ValueKey('screen')),
              matchesGoldenFile(
                  'goldens/calendar_390_${dark ? 'dark' : 'light'}.png'));
        }
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(find.text('0 notes · 0 active days'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
