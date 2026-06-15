import 'package:cloud_firestore/cloud_firestore.dart';

class NoteModel {
  const NoteModel({
    required this.noteId,
    required this.userId,
    required this.ownerName,
    required this.ownerEmail,
    required this.title,
    required this.content,
    required this.category,
    required this.isFavorite,
    required this.sharedWithUserIds,
    required this.pendingSharedWithUserIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String noteId;
  final String userId;
  final String ownerName;
  final String ownerEmail;
  final String title;
  final String content;
  final String category;
  final bool isFavorite;
  final List<String> sharedWithUserIds;
  final List<String> pendingSharedWithUserIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NoteModel.empty(
    String userId, {
    String ownerName = '',
    String ownerEmail = '',
  }) {
    final now = DateTime.now();
    return NoteModel(
      noteId: '',
      userId: userId,
      ownerName: ownerName,
      ownerEmail: ownerEmail,
      title: '',
      content: '',
      category: 'Lecture notes',
      isFavorite: false,
      sharedWithUserIds: const [],
      pendingSharedWithUserIds: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory NoteModel.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return NoteModel.fromMap({...data, 'noteId': document.id});
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      noteId: map['noteId'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      ownerEmail: map['ownerEmail'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      category: map['category'] as String? ?? 'Lecture notes',
      isFavorite: map['isFavorite'] as bool? ?? false,
      sharedWithUserIds: _readStringList(map['sharedWithUserIds']),
      pendingSharedWithUserIds:
          _readStringList(map['pendingSharedWithUserIds']),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'noteId': noteId,
      'userId': userId,
      'ownerName': ownerName,
      'ownerEmail': ownerEmail,
      'title': title,
      'content': content,
      'category': category,
      'isFavorite': isFavorite,
      'sharedWithUserIds': sharedWithUserIds,
      'pendingSharedWithUserIds': pendingSharedWithUserIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  NoteModel copyWith({
    String? noteId,
    String? userId,
    String? ownerName,
    String? ownerEmail,
    String? title,
    String? content,
    String? category,
    bool? isFavorite,
    List<String>? sharedWithUserIds,
    List<String>? pendingSharedWithUserIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteModel(
      noteId: noteId ?? this.noteId,
      userId: userId ?? this.userId,
      ownerName: ownerName ?? this.ownerName,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      isFavorite: isFavorite ?? this.isFavorite,
      sharedWithUserIds: sharedWithUserIds ?? this.sharedWithUserIds,
      pendingSharedWithUserIds:
          pendingSharedWithUserIds ?? this.pendingSharedWithUserIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool isOwner(String currentUserId) => userId == currentUserId;

  bool isSharedWith(String currentUserId) {
    return sharedWithUserIds.contains(currentUserId);
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    return title.toLowerCase().contains(normalized) ||
        content.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized);
  }

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.now();
  }

  static List<String> _readStringList(Object? value) {
    if (value is Iterable) {
      return value.whereType<String>().toList();
    }
    return const [];
  }
}
