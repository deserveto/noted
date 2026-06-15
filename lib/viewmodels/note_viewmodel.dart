import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note_model.dart';
import '../repositories/note_repository.dart';

class NoteViewModel extends ChangeNotifier {
  NoteViewModel(this._repository);

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
  StreamSubscription<List<NoteModel>>? _notesSubscription;
  StreamSubscription<List<NoteModel>>? _pendingSubscription;

  String? _boundUserId;
  List<NoteModel> _notes = [];
  List<NoteModel> _pendingSharedNotes = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _isLoading = false;
  String? _errorMessage;

  List<NoteModel> get notes => List.unmodifiable(_notes);
  List<NoteModel> get pendingSharedNotes =>
      List.unmodifiable(_pendingSharedNotes);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
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
      final categoryMatches =
          _selectedCategory == 'All' || note.category == _selectedCategory;
      return categoryMatches && note.matches(_searchQuery);
    }).toList();
  }

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
    _notes = [];
    _pendingSharedNotes = [];
    _searchQuery = '';
    _selectedCategory = 'All';
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
        _notes = notes;
        _isLoading = false;
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
    _pendingSubscription = _repository.watchPendingSharedNotes(userId).listen(
      (notes) {
        _pendingSharedNotes = notes;
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        notifyListeners();
      },
    );
  }

  void updateSearch(String query) {
    _searchQuery = query;
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
  void dispose() {
    _notesSubscription?.cancel();
    _pendingSubscription?.cancel();
    super.dispose();
  }
}
