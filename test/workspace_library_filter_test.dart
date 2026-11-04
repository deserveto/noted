import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/models/workspace_model.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/repositories/workspace_repository.dart';
import 'package:noted/utils/app_theme.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/notes_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '11111111-1111-4111-8111-111111111111';

NoteModel _note(
  String id, {
  String title = 'Note',
  String category = 'Projects',
  bool favorite = false,
  bool live = false,
  DateTime? createdAt,
}) =>
    NoteModel.empty(_uid).copyWith(
      noteId: id,
      title: title,
      category: category,
      isFavorite: favorite,
      liveMemberIds: live ? const ['collaborator'] : const [],
      liveRoles: live ? const {'collaborator': 'view'} : const {},
      createdAt: createdAt ?? DateTime(2026, 11, 5, 9),
      updatedAt: DateTime(2026, 11, 5, 10),
    );

class _LibraryRepository extends Fake implements NoteRepository {
  _LibraryRepository(this.notes);

  final List<NoteModel> notes;

  @override
  Stream<List<NoteModel>> watchNotes(String userId) => Stream.value(notes);

  @override
  Stream<List<NoteModel>> watchPendingSharedNotes(String userId) =>
      const Stream.empty();
}

class _Settings extends SettingsViewModel {
  _Settings() : super(SettingsRepository());

  @override
  SettingsModel get settings => const SettingsModel(reduceMotion: true);
}

class _Workspaces extends Fake implements WorkspaceRepository {
  final _controller = StreamController<WorkspaceLibrarySnapshot>.broadcast();
  WorkspaceSelection savedSelection = WorkspaceSelection.all;
  int refreshes = 0;

  void emit(WorkspaceLibrarySnapshot snapshot) => _controller.add(snapshot);

  @override
  Stream<WorkspaceLibrarySnapshot> watchLibrary(String userId) =>
      _controller.stream;

  @override
  Future<WorkspaceSelection> loadSelection(String userId) async =>
      savedSelection;

  @override
  Future<void> saveSelection(
    String userId,
    WorkspaceSelection selection,
  ) async {
    savedSelection = selection;
  }

  @override
  void refresh() => refreshes++;

  Future<void> close() => _controller.close();
}

WorkspaceLibrarySnapshot _workspaceSnapshot({
  List<PersonalWorkspace> workspaces = const [
    PersonalWorkspace(id: 'alpha', name: 'Alpha'),
    PersonalWorkspace(id: 'beta', name: 'Beta'),
    PersonalWorkspace(id: 'empty', name: 'Empty'),
  ],
  Map<String, String> assignments = const {
    'project': 'alpha',
    'other': 'beta',
  },
  bool fromCache = false,
  String? errorMessage,
}) =>
    WorkspaceLibrarySnapshot(
      workspaces: workspaces,
      assignments: assignments,
      loadedAt: DateTime(2026, 11, 5),
      fromCache: fromCache,
      errorMessage: errorMessage,
    );

Widget _harness(NoteViewModel notes) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteViewModel>.value(value: notes),
        ChangeNotifierProvider<SettingsViewModel>(create: (_) => _Settings()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: NotesPage()),
      ),
    );

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Library exposes an assignment-aware workspace selector',
      (tester) async {
    final workspaces = _Workspaces();
    final notes = NoteViewModel(
      _LibraryRepository([
        _note('project', title: 'Project note'),
        _note('default', title: 'Default note'),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      notes.dispose();
      await workspaces.close();
    });
    await tester.pumpWidget(_harness(notes));
    await tester.pump();
    workspaces.emit(_workspaceSnapshot());

    await tester.pump();

    expect(find.byKey(const ValueKey('workspace-filter')), findsOneWidget);
    expect(find.text('All workspaces'), findsOneWidget);
  });

  test(
      'workspace selection composes with search category favorites live and sort',
      () async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([
        _note(
          'project',
          title: 'Roadmap',
          category: 'Projects',
          favorite: true,
          live: true,
          createdAt: DateTime(2026, 11, 2),
        ),
        _note(
          'database',
          title: 'Database notes',
          category: 'Database',
          createdAt: DateTime(2026, 11, 4),
        ),
        _note('default', title: 'Default note', category: 'Projects'),
        _note('other', title: 'Other note', category: 'Projects', live: true),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await _flushAsync();
    workspaces.emit(_workspaceSnapshot(assignments: const {
      'project': 'alpha',
      'database': 'alpha',
      'other': 'beta',
    }));
    await _flushAsync();

    expect(vm.filteredNotes.map((note) => note.noteId),
        ['project', 'database', 'default', 'other']);
    vm.updateWorkspaceSelection(WorkspaceSelection.named('alpha'));
    vm.updateSort(NoteSort.title);
    expect(
        vm.filteredNotes.map((note) => note.noteId), ['database', 'project']);
    expect(vm.visibleAllCount, 2);
    expect(vm.visibleFavoriteCount, 1);
    expect(vm.visibleLiveCount, 1);

    vm.updateCategory('Projects');
    vm.updateSearch('road');
    vm.updateLibraryFilter(LibraryFilter.favorites);
    vm.updateSort(NoteSort.title);
    expect(vm.filteredNotes.single.noteId, 'project');
    expect(vm.visibleAllCount, 1);
    expect(vm.visibleFavoriteCount, 1);
    expect(vm.visibleLiveCount, 1);

    vm.updateLibraryFilter(LibraryFilter.all);
    vm.updateSort(NoteSort.dateCreated);
    vm.updateSearch('');
    expect(vm.filteredNotes.map((note) => note.noteId), ['project']);
  });

  test('all default named empty and reset workspace filters use the mappings',
      () async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([
        _note('project', title: 'Project'),
        _note('default', title: 'Default'),
        _note('other', title: 'Other'),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await _flushAsync();
    workspaces.emit(_workspaceSnapshot());
    await _flushAsync();

    expect(vm.filteredNotes, hasLength(3));
    vm.updateWorkspaceSelection(WorkspaceSelection.defaultWorkspace);
    expect(vm.filteredNotes.single.noteId, 'default');
    vm.updateWorkspaceSelection(WorkspaceSelection.named('alpha'));
    expect(vm.filteredNotes.single.noteId, 'project');
    vm.updateWorkspaceSelection(WorkspaceSelection.named('empty'));
    expect(vm.filteredNotes, isEmpty);
    expect(vm.workspaceScopedCount, 0);
    vm.resetWorkspaceSelection();
    expect(vm.workspaceSelection, WorkspaceSelection.all);
    expect(vm.filteredNotes, hasLength(3));
  });

  test(
      'assignment changes rename and deletion keep selected workspace coherent',
      () async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([
        _note('project', title: 'Project'),
        _note('other', title: 'Other'),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await _flushAsync();
    workspaces.emit(_workspaceSnapshot());
    await _flushAsync();
    vm.updateWorkspaceSelection(WorkspaceSelection.named('alpha'));
    expect(vm.filteredNotes.single.noteId, 'project');

    workspaces.emit(_workspaceSnapshot(
      workspaces: const [
        PersonalWorkspace(id: 'alpha', name: 'Alpha Renamed'),
        PersonalWorkspace(id: 'beta', name: 'Beta'),
      ],
      assignments: const {'project': 'beta', 'other': 'beta'},
    ));
    await _flushAsync();
    expect(vm.workspaceSelectionLabel, 'Alpha Renamed');
    expect(vm.filteredNotes, isEmpty);

    workspaces.emit(_workspaceSnapshot(
      workspaces: const [
        PersonalWorkspace(id: 'beta', name: 'Beta'),
        PersonalWorkspace(id: 'empty', name: 'Empty'),
      ],
      assignments: const {'other': 'beta'},
    ));
    await _flushAsync();
    expect(vm.workspaceSelection, WorkspaceSelection.all);
    expect(vm.filteredNotes.map((note) => note.noteId), ['project', 'other']);
    vm.updateWorkspaceSelection(WorkspaceSelection.defaultWorkspace);
    expect(vm.filteredNotes.single.noteId, 'project');
  });

  test('stale workspace responses cannot apply another account selection',
      () async {
    final workspaces = _SwitchWorkspaces();
    final vm = NoteViewModel(
      _LibraryRepository([_note('project')]),
      workspaceRepository: workspaces,
    );
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });

    vm.bindUser('account-a');
    await _flushAsync();
    vm.bindUser('account-b');
    await _flushAsync();
    workspaces.emit('account-b', _workspaceSnapshot());
    await _flushAsync();
    expect(vm.boundUserId, 'account-b');
    expect(vm.workspaces.map((workspace) => workspace.name),
        ['Alpha', 'Beta', 'Empty']);

    workspaces.emit(
      'account-a',
      _workspaceSnapshot(
        workspaces: const [
          PersonalWorkspace(id: 'leaked', name: 'Leaked'),
        ],
        assignments: const {'project': 'leaked'},
      ),
    );
    workspaces.completeSelection(
      'account-a',
      WorkspaceSelection.named('leaked'),
    );
    await _flushAsync();
    expect(vm.boundUserId, 'account-b');
    expect(vm.workspaceSelection, WorkspaceSelection.all);
    expect(vm.workspaces.map((workspace) => workspace.name),
        isNot(contains('Leaked')));
  });

  test('restart restores an account selection onto cached assignments',
      () async {
    final workspaces = _Workspaces()
      ..savedSelection = WorkspaceSelection.named('alpha');
    final vm = NoteViewModel(
      _LibraryRepository([
        _note('project', title: 'Project'),
        _note('default', title: 'Default'),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await _flushAsync();

    workspaces.emit(_workspaceSnapshot(fromCache: true));
    await _flushAsync();

    expect(vm.workspaceStatus, WorkspaceLibraryStatus.cached);
    expect(vm.workspaceSelection, WorkspaceSelection.named('alpha'));
    expect(vm.filteredNotes.single.noteId, 'project');
  });

  test('two users can organize the same shared note independently', () async {
    final shared = _note('shared', title: 'Shared plan', live: true);
    final aWorkspaces = _Workspaces();
    final bWorkspaces = _Workspaces();
    final a = NoteViewModel(
      _LibraryRepository([shared]),
      workspaceRepository: aWorkspaces,
    )..bindUser('account-a');
    final b = NoteViewModel(
      _LibraryRepository([shared]),
      workspaceRepository: bWorkspaces,
    )..bindUser('account-b');
    addTearDown(() async {
      a.dispose();
      b.dispose();
      await aWorkspaces.close();
      await bWorkspaces.close();
    });
    await _flushAsync();
    aWorkspaces
        .emit(_workspaceSnapshot(assignments: const {'shared': 'alpha'}));
    bWorkspaces.emit(_workspaceSnapshot(assignments: const {'shared': 'beta'}));
    await _flushAsync();

    a.updateWorkspaceSelection(WorkspaceSelection.named('alpha'));
    b.updateWorkspaceSelection(WorkspaceSelection.named('beta'));

    expect(a.filteredNotes.single.noteId, 'shared');
    expect(b.filteredNotes.single.noteId, 'shared');
    expect(shared.canEdit('account-a'), isFalse);
    expect(shared.canEdit('account-b'), isFalse);
  });

  testWidgets('workspace picker filters results and reset restores all',
      (tester) async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([
        _note('project', title: 'Project note'),
        _note('default', title: 'Default note'),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await tester.pumpWidget(_harness(vm));
    await tester.pump();
    workspaces.emit(_workspaceSnapshot());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('workspace-filter-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-option-all')), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-option-alpha')));
    await tester.pumpAndSettle();

    expect(find.text('Project note'), findsOneWidget);
    expect(find.text('Default note'), findsNothing);
    expect(find.text('1 note'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('workspace-filter-reset')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-filter-reset')));
    await tester.pump();
    expect(find.text('Project note'), findsOneWidget);
    expect(find.text('Default note'), findsOneWidget);
    expect(vm.workspaceSelection, WorkspaceSelection.all);
  });

  testWidgets('empty workspace offers a reset to all', (tester) async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([_note('project', title: 'Project note')]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await tester.pumpWidget(_harness(vm));
    await tester.pump();
    workspaces.emit(_workspaceSnapshot());
    await tester.pump();
    vm.updateWorkspaceSelection(WorkspaceSelection.named('empty'));
    await tester.pump();

    expect(find.text('No notes in Empty'), findsOneWidget);
    await tester.ensureVisible(find.text('Show all workspaces'));
    await tester.pump();
    await tester.tap(find.text('Show all workspaces'));
    await tester.pump();
    expect(find.text('Project note'), findsOneWidget);
  });

  testWidgets('favorite empty state names the selected workspace',
      (tester) async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([_note('project', title: 'Project note')]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await tester.pumpWidget(_harness(vm));
    await tester.pump();
    workspaces.emit(_workspaceSnapshot());
    await tester.pump();
    vm.updateWorkspaceSelection(WorkspaceSelection.named('alpha'));
    vm.updateLibraryFilter(LibraryFilter.favorites);
    await tester.pump();

    expect(find.text('No favorites in Alpha'), findsOneWidget);
    await tester.ensureVisible(find.text('Show all workspaces'));
    await tester.pump();
    await tester.tap(find.text('Show all workspaces'));
    await tester.pump();
    expect(vm.workspaceSelection, WorkspaceSelection.all);
    expect(vm.libraryFilter, LibraryFilter.favorites);
  });

  testWidgets('workspace read failure is explicit and retryable',
      (tester) async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([_note('project')]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await tester.pumpWidget(_harness(vm));
    await tester.pump();
    workspaces.emit(WorkspaceLibrarySnapshot.unavailable(
      'Workspace assignments could not be loaded.',
    ));
    await tester.pump();

    expect(find.text('Workspace assignments could not be loaded.'),
        findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(workspaces.refreshes, 1);
  });

  testWidgets('cached workspace read failure keeps assignments and retry',
      (tester) async {
    final workspaces = _Workspaces();
    final vm = NoteViewModel(
      _LibraryRepository([
        _note('project', title: 'Project note'),
        _note('default', title: 'Default note'),
      ]),
      workspaceRepository: workspaces,
    )..bindUser(_uid);
    addTearDown(() async {
      vm.dispose();
      await workspaces.close();
    });
    await tester.pumpWidget(_harness(vm));
    await tester.pump();
    workspaces.emit(_workspaceSnapshot(
      fromCache: true,
      errorMessage: 'Workspace refresh failed.',
    ));
    await tester.pump();

    expect(vm.workspaceStatus, WorkspaceLibraryStatus.cached);
    expect(find.text('Project note'), findsOneWidget);
    expect(find.text('Default note'), findsOneWidget);
    expect(find.textContaining('Showing saved workspace data'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(workspaces.refreshes, 1);
  });

  for (final width in [360.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('workspace filter fits $width ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final workspaces = _Workspaces();
        final vm = NoteViewModel(
          _LibraryRepository([
            _note('project', title: 'Project note'),
            _note('default', title: 'Default note'),
          ]),
          workspaceRepository: workspaces,
        )..bindUser(_uid);
        addTearDown(() async {
          vm.dispose();
          await workspaces.close();
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<NoteViewModel>.value(value: vm),
              ChangeNotifierProvider<SettingsViewModel>(
                  create: (_) => _Settings()),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: const Scaffold(body: NotesPage()),
            ),
          ),
        );
        await tester.pump();
        workspaces.emit(_workspaceSnapshot());
        await tester.pump();
        expect(tester.takeException(), isNull);
        final button = tester
            .getSize(find.byKey(const ValueKey('workspace-filter-button')));
        expect(button.height, greaterThanOrEqualTo(44));
      });
    }
  }
}

class _SwitchWorkspaces extends Fake implements WorkspaceRepository {
  final _controllers = <String, StreamController<WorkspaceLibrarySnapshot>>{};
  final _selections = <String, Completer<WorkspaceSelection>>{};

  StreamController<WorkspaceLibrarySnapshot> _controller(String uid) =>
      _controllers.putIfAbsent(
        uid,
        () => StreamController<WorkspaceLibrarySnapshot>.broadcast(),
      );

  Completer<WorkspaceSelection> _selection(String uid) =>
      _selections.putIfAbsent(uid, Completer<WorkspaceSelection>.new);

  void emit(String uid, WorkspaceLibrarySnapshot snapshot) =>
      _controller(uid).add(snapshot);

  void completeSelection(String uid, WorkspaceSelection selection) {
    final completer = _selection(uid);
    if (!completer.isCompleted) completer.complete(selection);
  }

  @override
  Stream<WorkspaceLibrarySnapshot> watchLibrary(String userId) =>
      _controller(userId).stream;

  @override
  Future<WorkspaceSelection> loadSelection(String userId) async {
    if (userId == 'account-b') return WorkspaceSelection.all;
    return _selection(userId).future;
  }

  @override
  Future<void> saveSelection(
    String userId,
    WorkspaceSelection selection,
  ) async {}

  @override
  void refresh() {}

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
