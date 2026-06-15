import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note_model.dart';
import '../services/firebase_service.dart';

class NoteRepository {
  NoteRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseService.firestore;

  final FirebaseFirestore _firestore;

  Stream<List<NoteModel>> watchNotes(String userId) {
    return _notes
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final notes = snapshot.docs.map(NoteModel.fromDocument).toList();
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notes;
    });
  }

  Future<void> addNote(NoteModel note) async {
    final doc = _notes.doc();
    final now = DateTime.now();
    final savedNote = note.copyWith(
      noteId: doc.id,
      createdAt: now,
      updatedAt: now,
    );
    await doc.set(savedNote.toMap());
  }

  Future<void> updateNote(NoteModel note) async {
    await _notes.doc(note.noteId).update(
          note.copyWith(updatedAt: DateTime.now()).toMap(),
        );
  }

  Future<void> deleteNote(String noteId) {
    return _notes.doc(noteId).delete();
  }

  Future<void> toggleFavorite(NoteModel note) {
    return _notes.doc(note.noteId).update({
      'isFavorite': !note.isFavorite,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> shareNote({
    required NoteModel note,
    required String targetUserId,
    String? ownerName,
    String? ownerEmail,
  }) {
    final Map<String, dynamic> data = {
      'pendingSharedWithUserIds': FieldValue.arrayUnion([targetUserId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    final finalName =
        note.ownerName.isNotEmpty ? note.ownerName : (ownerName ?? '');
    final finalEmail =
        note.ownerEmail.isNotEmpty ? note.ownerEmail : (ownerEmail ?? '');

    if (finalName.isNotEmpty) data['ownerName'] = finalName;
    if (finalEmail.isNotEmpty) data['ownerEmail'] = finalEmail;

    return _notes.doc(note.noteId).update(data);
  }

  Stream<List<NoteModel>> watchPendingSharedNotes(String userId) {
    return _notes
        .where('pendingSharedWithUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final notes = snapshot.docs.map(NoteModel.fromDocument).toList();
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notes;
    });
  }

  /// Accepts a pending share by creating an independent copy of the note
  /// owned by [userId], then removes them from the original's pending list.
  Future<void> acceptShare(
    String noteId,
    String userId, {
    String ownerName = '',
    String ownerEmail = '',
  }) async {
    // 1. Read the original note.
    final doc = await _notes.doc(noteId).get();
    if (!doc.exists) return;
    final data = doc.data()!;

    // 2. Create a new independent copy owned by the accepting user.
    final newDoc = _notes.doc();
    final now = DateTime.now();
    final copiedData = <String, dynamic>{
      'noteId': newDoc.id,
      'userId': userId,
      'ownerName': ownerName,
      'ownerEmail': ownerEmail,
      'title': data['title'] ?? '',
      'content': data['content'] ?? '',
      'category': data['category'] ?? 'Lecture notes',
      'isFavorite': false,
      'sharedWithUserIds': <String>[],
      'pendingSharedWithUserIds': <String>[],
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };
    await newDoc.set(copiedData);

    // 3. Remove the user from the original note's pending list.
    await _notes.doc(noteId).update({
      'pendingSharedWithUserIds': FieldValue.arrayRemove([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> declineShare(String noteId, String userId) {
    return _notes.doc(noteId).update({
      'pendingSharedWithUserIds': FieldValue.arrayRemove([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  CollectionReference<Map<String, dynamic>> get _notes {
    return _firestore.collection('notes');
  }
}
