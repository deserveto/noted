import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';

void main() {
  test('matches searches title content and category case-insensitively', () {
    final now = DateTime(2026, 6, 14);
    final note = NoteModel(
      noteId: 'note-1',
      userId: 'user-1',
      ownerName: 'Student',
      ownerEmail: 'student@example.com',
      title: 'Mobile Programming',
      content: 'Provider manages UI state',
      category: 'Lecture notes',
      isFavorite: true,
      sharedWithUserIds: const [],
      pendingSharedWithUserIds: const [],
      createdAt: now,
      updatedAt: now,
    );

    expect(note.matches('mobile'), isTrue);
    expect(note.matches('STATE'), isTrue);
    expect(note.matches('lecture'), isTrue);
    expect(note.matches('biology'), isFalse);
  });

  test('NoteModel toMap and fromMap parses pendingSharedWithUserIds correctly',
      () {
    final now = DateTime(2026, 6, 14);
    final note = NoteModel(
      noteId: 'note-1',
      userId: 'user-1',
      ownerName: 'Student',
      ownerEmail: 'student@example.com',
      title: 'Mobile Programming',
      content: 'Provider manages UI state',
      category: 'Lecture notes',
      isFavorite: true,
      sharedWithUserIds: const ['friend-1'],
      pendingSharedWithUserIds: const ['friend-2'],
      createdAt: now,
      updatedAt: now,
    );

    final map = note.toMap();
    expect(map['pendingSharedWithUserIds'], ['friend-2']);

    final parsed = NoteModel.fromMap(map);
    expect(parsed.pendingSharedWithUserIds, ['friend-2']);
  });

  test('clears note filters when no user is bound', () {
    final viewModel = NoteViewModel(_FakeNoteRepository());

    viewModel.updateSearch('database');
    viewModel.updateCategory('Database');
    viewModel.bindUser(null);

    expect(viewModel.searchQuery, isEmpty);
    expect(viewModel.selectedCategory, 'All');
    expect(viewModel.notes, isEmpty);
    expect(viewModel.pendingSharedNotes, isEmpty);
  });

  test(
      'ViewModel correctly binds user, watches pending shared notes, and accepts/declines shares',
      () async {
    final repository = _FakeNoteRepository();
    final viewModel = NoteViewModel(repository);

    final now = DateTime.now();
    final note = NoteModel(
      noteId: 'note-shared-1',
      userId: 'owner-id',
      ownerName: 'Owner',
      ownerEmail: 'owner@example.com',
      title: 'Shared Note',
      content: 'This note is shared with target-user',
      category: 'Lecture notes',
      isFavorite: false,
      sharedWithUserIds: const [],
      pendingSharedWithUserIds: const ['target-user'],
      createdAt: now,
      updatedAt: now,
    );

    await repository.addNote(note);

    // Bind the user 'target-user' who has a pending share
    viewModel.bindUser('target-user');

    // Wait for stream to emit
    await Future.delayed(Duration.zero);

    // Verify pending shared notes list has the note
    expect(viewModel.pendingSharedNotes.length, 1);
    expect(viewModel.pendingSharedNotes.first.noteId, 'note-shared-1');

    // Accept share — creates an independent copy
    await viewModel.acceptShare('note-shared-1');
    await Future.delayed(Duration.zero);

    // Verify it is no longer pending. The original stays (owned by 'owner-id')
    // plus a new copy (owned by 'target-user') now exists.
    expect(viewModel.pendingSharedNotes, isEmpty);
    // The fake repo now has 2 notes: original + copy. But watchNotes for
    // 'target-user' only returns notes owned by target-user, so we see the copy.
    final ownedNotes =
        viewModel.notes.where((n) => n.userId == 'target-user').toList();
    expect(ownedNotes.length, 1);
    expect(ownedNotes.first.noteId, 'copy_note-shared-1');
    expect(ownedNotes.first.title, 'Shared Note');

    // Reset and test decline
    repository.inMemoryNotes.clear();
    final note2 = NoteModel(
      noteId: 'note-shared-2',
      userId: 'owner-id',
      ownerName: 'Owner',
      ownerEmail: 'owner@example.com',
      title: 'Shared Note 2',
      content: 'This note is shared with target-user',
      category: 'Lecture notes',
      isFavorite: false,
      sharedWithUserIds: const [],
      pendingSharedWithUserIds: const ['target-user'],
      createdAt: now,
      updatedAt: now,
    );
    await repository.addNote(note2);

    // Force rebind
    viewModel.bindUser('target-user');
    await Future.delayed(Duration.zero);
    expect(viewModel.pendingSharedNotes.length, 1);

    // Decline share
    await viewModel.declineShare('note-shared-2');
    await Future.delayed(Duration.zero);

    // Verify it is no longer pending and not in main notes
    expect(viewModel.pendingSharedNotes, isEmpty);
    expect(viewModel.notes, isEmpty);
  });
}

class _FakeNoteRepository implements NoteRepository {
  final List<NoteModel> inMemoryNotes = [];
  final _updateBroadcaster = StreamController<void>.broadcast();

  void notifyListeners() {
    _updateBroadcaster.add(null);
  }

  @override
  Future<void> addNote(NoteModel note) async {
    inMemoryNotes.add(note);
    notifyListeners();
  }

  @override
  Future<void> deleteNote(String noteId) async {
    inMemoryNotes.removeWhere((n) => n.noteId == noteId);
    notifyListeners();
  }

  @override
  Future<void> toggleFavorite(NoteModel note) async {
    final index = inMemoryNotes.indexWhere((n) => n.noteId == note.noteId);
    if (index != -1) {
      inMemoryNotes[index] =
          inMemoryNotes[index].copyWith(isFavorite: !note.isFavorite);
      notifyListeners();
    }
  }

  @override
  Future<void> updateNote(NoteModel note) async {
    final index = inMemoryNotes.indexWhere((n) => n.noteId == note.noteId);
    if (index != -1) {
      inMemoryNotes[index] = note;
      notifyListeners();
    }
  }

  @override
  Future<void> shareNote({
    required NoteModel note,
    required String targetUserId,
    String? ownerName,
    String? ownerEmail,
  }) async {
    final index = inMemoryNotes.indexWhere((n) => n.noteId == note.noteId);
    if (index != -1) {
      final updated = inMemoryNotes[index].copyWith(
        pendingSharedWithUserIds: [
          ...inMemoryNotes[index].pendingSharedWithUserIds,
          targetUserId
        ],
      );
      inMemoryNotes[index] = updated;
      notifyListeners();
    }
  }

  @override
  Stream<List<NoteModel>> watchNotes(String userId) {
    late final StreamController<List<NoteModel>> controller;
    StreamSubscription? sub;

    void send() {
      if (controller.isClosed) return;
      final owned = inMemoryNotes.where((n) => n.userId == userId).toList();
      owned.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      controller.add(owned);
    }

    controller = StreamController<List<NoteModel>>(
      onListen: () {
        send();
        sub = _updateBroadcaster.stream.listen((_) => send());
      },
      onCancel: () {
        sub?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Stream<List<NoteModel>> watchPendingSharedNotes(String userId) {
    late final StreamController<List<NoteModel>> controller;
    StreamSubscription? sub;

    void send() {
      if (controller.isClosed) return;
      final pending = inMemoryNotes
          .where((n) => n.pendingSharedWithUserIds.contains(userId))
          .toList();
      pending.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      controller.add(pending);
    }

    controller = StreamController<List<NoteModel>>(
      onListen: () {
        send();
        sub = _updateBroadcaster.stream.listen((_) => send());
      },
      onCancel: () {
        sub?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<void> acceptShare(
    String noteId,
    String userId, {
    String ownerName = '',
    String ownerEmail = '',
  }) async {
    final index = inMemoryNotes.indexWhere((n) => n.noteId == noteId);
    if (index != -1) {
      final note = inMemoryNotes[index];
      // Create an independent copy owned by the accepting user.
      final copy = note.copyWith(
        noteId: 'copy_${note.noteId}',
        userId: userId,
        ownerName: ownerName,
        ownerEmail: ownerEmail,
        isFavorite: false,
        sharedWithUserIds: const [],
        pendingSharedWithUserIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      inMemoryNotes.add(copy);
      // Remove the user from the original note's pending list.
      final newPending =
          note.pendingSharedWithUserIds.where((id) => id != userId).toList();
      inMemoryNotes[index] = note.copyWith(
        pendingSharedWithUserIds: newPending,
      );
      notifyListeners();
    }
  }

  @override
  Future<void> declineShare(String noteId, String userId) async {
    final index = inMemoryNotes.indexWhere((n) => n.noteId == noteId);
    if (index != -1) {
      final note = inMemoryNotes[index];
      final newPending =
          note.pendingSharedWithUserIds.where((id) => id != userId).toList();
      inMemoryNotes[index] = note.copyWith(
        pendingSharedWithUserIds: newPending,
      );
      notifyListeners();
    }
  }
}
