import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note_model.dart';
import '../models/workspace_model.dart';
import '../repositories/note_repository.dart';
import '../repositories/workspace_repository.dart';

enum LibraryFilter { all, favorites, live }

enum NoteSort { lastEdited, dateCreated, title }

enum WorkspaceLibraryStatus { loading, ready, cached, unavailable }

class NoteViewModel extends ChangeNotifier {
  NoteViewModel(
    this._repository, {
    WorkspaceRepository? workspaceRepository,
  }) : _workspaceRepository = workspaceRepository ?? WorkspaceRepository();

  static const defaultCategories = [
    'Lecture notes',
    'Mobile Programming',
    'Database',
    'Shopping List',
    'Important',
    'To-do List',
    'For later',
  ];

  final NoteRepository _repository;
  final WorkspaceRepository _workspaceRepository;
  StreamSubscription<List<NoteModel>>? _notesSubscription;
  StreamSubscription<List<NoteModel>>? _pendingSubscription;
  StreamSubscription<WorkspaceLibrarySnapshot>? _workspaceSubscription;

  String? _boundUserId;
  List<NoteModel> _notes = [];
  List<NoteModel> _pendingSharedNotes = [];
  List<PersonalWorkspace> _workspaces = [];
  Map<String, String> _workspaceAssignments = const {};
  WorkspaceSelection _workspaceSelection = WorkspaceSelection.all;
  WorkspaceSelection? _pendingWorkspaceSelection;
  WorkspaceLibraryStatus _workspaceStatus = WorkspaceLibraryStatus.loading;
  String? _workspaceErrorMessage;
  bool _workspaceAssignmentsKnown = false;
  String _searchQuery = '';
  int _searchRevision = 0;
  String _selectedCategory = 'All';
  LibraryFilter _libraryFilter = LibraryFilter.all;
  NoteSort _sort = NoteSort.lastEdited;
  bool _isDisposed = false;
  bool _isLoading = false;
  String? _errorMessage;

  String? get boundUserId => _boundUserId;
  Future<void> prepareRemoteAccount(String uid) async {
    try {
      await _repository.prepareAccount();
    } catch (error) {
      if (_boundUserId != uid || _isDisposed) return;
      _errorMessage =
          'Couldn’t prepare shared notes. Check the connection and Supabase backend setup. $error';
      notifyListeners();
    }
  }

  LibraryFilter get libraryFilter => _libraryFilter;
  NoteSort get sort => _sort;
  List<PersonalWorkspace> get workspaces => List.unmodifiable(_workspaces);
  WorkspaceSelection get workspaceSelection => _workspaceSelection;
  WorkspaceLibraryStatus get workspaceStatus => _workspaceStatus;
  String? get workspaceErrorMessage => _workspaceErrorMessage;
  bool get workspaceAssignmentsKnown => _workspaceAssignmentsKnown;
  String get workspaceSelectionLabel {
    if (_workspaceSelection.isAll) return 'All workspaces';
    if (_workspaceSelection.isDefault) return 'Default';
    for (final workspace in _workspaces) {
      if (workspace.id == _workspaceSelection.workspaceId) {
        return workspace.name;
      }
    }
    return 'All workspaces';
  }

  List<NoteModel> get liveNotes => _notes.where((n) => n.isLive).toList();
  int get totalLive => liveNotes.length;

  List<NoteModel> get notes => List.unmodifiable(_notes);
  List<NoteModel> get pendingSharedNotes =>
      List.unmodifiable(_pendingSharedNotes);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  int get searchRevision => _searchRevision;
  String get selectedCategory => _selectedCategory;

  List<String> get categories {
    final values = <String>{...defaultCategories};
    for (final note in _notes) {
      if (note.category.trim().isNotEmpty) {
        values.add(note.category.trim());
      }
    }
    return values.toList()..sort();
  }

  List<NoteModel> get filteredNotes {
    return _notes.where((note) {
      final filterMatches = switch (_libraryFilter) {
        LibraryFilter.all => true,
        LibraryFilter.favorites => note.isFavorite,
        LibraryFilter.live => note.isLive,
      };
      return _workspaceMatches(note) &&
          _categoryMatches(note) &&
          _searchMatches(note) &&
          filterMatches;
    }).toList()
      ..sort((a, b) => switch (_sort) {
            NoteSort.lastEdited => b.updatedAt.compareTo(a.updatedAt),
            NoteSort.dateCreated => b.createdAt.compareTo(a.createdAt),
            NoteSort.title =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          });
  }

  int get visibleAllCount => _visibleBeforeStatus().length;
  int get visibleFavoriteCount =>
      _visibleBeforeStatus().where((note) => note.isFavorite).length;
  int get visibleLiveCount =>
      _visibleBeforeStatus().where((note) => note.isLive).length;
  int get workspaceScopedCount => _notes.where(_workspaceMatches).length;

  List<NoteModel> get favoriteNotes {
    return _notes.where((note) => note.isFavorite).toList();
  }

  List<NoteModel> get recentNotes {
    return _notes.take(4).toList();
  }

  int get totalNotes => _notes.length;
  int get totalFavorites => favoriteNotes.length;

  void bindUser(String? userId) {
    if (_boundUserId == userId && userId != null) {
      return;
    }

    _boundUserId = userId;
    _notesSubscription?.cancel();
    _pendingSubscription?.cancel();
    _workspaceSubscription?.cancel();
    _notes = [];
    _pendingSharedNotes = [];
    _workspaces = [];
    _workspaceAssignments = const {};
    _workspaceSelection = WorkspaceSelection.all;
    _pendingWorkspaceSelection = null;
    _workspaceStatus = WorkspaceLibraryStatus.loading;
    _workspaceErrorMessage = null;
    _workspaceAssignmentsKnown = false;
    _searchQuery = '';
    _searchRevision++;
    _selectedCategory = 'All';
    _libraryFilter = LibraryFilter.all;
    _sort = NoteSort.lastEdited;
    _isLoading = false;
    _errorMessage = null;

    if (userId == null) {
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();
    _notesSubscription = _repository.watchNotes(userId).listen(
      (notes) {
        if (_boundUserId != userId) return;
        _notes = notes;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
      },
      onError: (Object error) {
        if (_boundUserId != userId) return;
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
    _pendingSubscription = _repository.watchPendingSharedNotes(userId).listen(
      (notes) {
        if (_boundUserId != userId) return;
        _pendingSharedNotes = notes;
        notifyListeners();
      },
      onError: (Object error) {
        if (_boundUserId != userId) return;
        _errorMessage = error.toString();
        notifyListeners();
      },
    );
    _bindWorkspaceState(userId);
  }

  void _bindWorkspaceState(String userId) {
    _workspaceSubscription = _workspaceRepository.watchLibrary(userId).listen(
      (snapshot) {
        if (_boundUserId != userId) return;
        _applyWorkspaceSnapshot(snapshot);
      },
      onError: (Object error) {
        if (_boundUserId != userId) return;
        _workspaceStatus = WorkspaceLibraryStatus.unavailable;
        _workspaceErrorMessage = error.toString();
        notifyListeners();
      },
    );
    _workspaceRepository.loadSelection(userId).then((selection) {
      if (_boundUserId != userId) return;
      _pendingWorkspaceSelection = selection;
      _resolvePendingWorkspaceSelection();
      notifyListeners();
    }).catchError((Object _) {});
  }

  void _applyWorkspaceSnapshot(WorkspaceLibrarySnapshot snapshot) {
    _workspaces = snapshot.workspaces;
    _workspaceAssignments = snapshot.assignments;
    _workspaceAssignmentsKnown = snapshot.hasAssignmentData;
    _workspaceErrorMessage = snapshot.errorMessage;
    if (!snapshot.hasAssignmentData) {
      _workspaceStatus = WorkspaceLibraryStatus.unavailable;
    } else {
      _workspaceStatus = snapshot.fromCache
          ? WorkspaceLibraryStatus.cached
          : WorkspaceLibraryStatus.ready;
    }
    _resolvePendingWorkspaceSelection();
    _ensureWorkspaceSelectionExists();
    notifyListeners();
  }

  void _resolvePendingWorkspaceSelection() {
    final pending = _pendingWorkspaceSelection;
    if (pending == null) return;
    if (!_workspaceAssignmentsKnown && !pending.isAll) return;
    _pendingWorkspaceSelection = null;
    if (pending.isNamed &&
        !_workspaces.any((workspace) => workspace.id == pending.workspaceId)) {
      _workspaceSelection = WorkspaceSelection.all;
      _persistWorkspaceSelection();
      return;
    }
    _workspaceSelection = pending;
  }

  void _ensureWorkspaceSelectionExists() {
    if (!_workspaceSelection.isNamed) return;
    if (_workspaces
        .any((workspace) => workspace.id == _workspaceSelection.workspaceId)) {
      return;
    }
    _workspaceSelection = WorkspaceSelection.all;
    _persistWorkspaceSelection();
  }

  void updateWorkspaceSelection(WorkspaceSelection selection) {
    if (!selection.isAll) {
      if (!_workspaceAssignmentsKnown) return;
      if (selection.isNamed &&
          !_workspaces
              .any((workspace) => workspace.id == selection.workspaceId)) {
        return;
      }
    }
    _workspaceSelection = selection;
    _pendingWorkspaceSelection = null;
    _persistWorkspaceSelection();
    notifyListeners();
  }

  void resetWorkspaceSelection() =>
      updateWorkspaceSelection(WorkspaceSelection.all);

  void retryWorkspaces() {
    if (_boundUserId == null) return;
    _workspaceStatus = WorkspaceLibraryStatus.loading;
    _workspaceErrorMessage = null;
    notifyListeners();
    _workspaceRepository.refresh();
  }

  void _persistWorkspaceSelection() {
    final userId = _boundUserId;
    if (userId == null) return;
    _workspaceRepository
        .saveSelection(userId, _workspaceSelection)
        .catchError((Object _) {});
  }

  void updateLibraryFilter(LibraryFilter filter) {
    _libraryFilter = filter;
    notifyListeners();
  }

  void updateSort(NoteSort sort) {
    _sort = sort;
    notifyListeners();
  }

  void retry() {
    final uid = _boundUserId;
    _boundUserId = null;
    bindUser(uid);
  }

  Future<String?> saveNoteAndReturnId(NoteModel note) async {
    String? id;
    await _runAction(() async {
      if (note.noteId.isEmpty) {
        id = await _repository.createNote(note);
      } else {
        await _repository.updateNote(note);
        id = note.noteId;
      }
    });
    return id;
  }

  Future<void> restoreNote(String noteId) =>
      _runAction(() => _repository.restoreNote(noteId));

  void updateSearch(String query) {
    _searchQuery = query;
    _searchRevision++;
    notifyListeners();
  }

  void updateCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  Future<void> saveNote(NoteModel note) async {
    await _runAction(() async {
      if (note.noteId.isEmpty) {
        await _repository.addNote(note);
      } else {
        await _repository.updateNote(note);
      }
    });
  }

  Future<void> deleteNote(String noteId) async {
    await _runAction(() => _repository.deleteNote(noteId));
  }

  Future<void> toggleFavorite(NoteModel note) async {
    await _runAction(() => _repository.toggleFavorite(note));
  }

  Future<void> shareNote(
    NoteModel note,
    String targetUserId, {
    String? ownerName,
    String? ownerEmail,
  }) async {
    if (targetUserId.trim().isEmpty ||
        note.pendingSharedWithUserIds.contains(targetUserId)) {
      return;
    }
    await _runAction(
      () => _repository.shareNote(
        note: note,
        targetUserId: targetUserId,
        ownerName: ownerName,
        ownerEmail: ownerEmail,
      ),
    );
  }

  Future<void> acceptShare(
    String noteId, {
    String ownerName = '',
    String ownerEmail = '',
  }) async {
    final userId = _boundUserId;
    if (userId == null) return;
    await _runAction(() => _repository.acceptShare(
          noteId,
          userId,
          ownerName: ownerName,
          ownerEmail: ownerEmail,
        ));
  }

  /// Server-only authorization and content; never an offline invitation snapshot.
  Stream<NoteModel?> watchSharedPreview(String noteId) =>
      _repository.watchSharedPreview(noteId);

  Future<void> declineShare(String noteId) async {
    final userId = _boundUserId;
    if (userId == null) return;
    await _runAction(() => _repository.declineShare(noteId, userId));
  }

  Future<void> _runAction(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _notesSubscription?.cancel();
    _pendingSubscription?.cancel();
    _workspaceSubscription?.cancel();
    super.dispose();
  }

  bool _workspaceMatches(NoteModel note) {
    if (_workspaceSelection.isAll) return true;
    if (!_workspaceAssignmentsKnown) return false;
    final workspaceId = _workspaceAssignments[note.noteId] ??
        WorkspaceSelection.defaultWorkspaceId;
    return workspaceId == _workspaceSelection.workspaceId;
  }

  bool _categoryMatches(NoteModel note) =>
      _selectedCategory == 'All' || note.category == _selectedCategory;

  bool _searchMatches(NoteModel note) => note.matches(_searchQuery);

  List<NoteModel> _visibleBeforeStatus() => _notes
      .where((note) =>
          _workspaceMatches(note) &&
          _categoryMatches(note) &&
          _searchMatches(note))
      .toList();
}
