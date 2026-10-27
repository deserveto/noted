import 'dart:convert';

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
    this.sourceOwnerId = '',
    this.sourceNoteId = '',
    this.color = 'blue',
    this.liveMemberIds = const [],
    this.liveRoles = const {},
    this.revision = 0,
    this.deletedAt,
    this.attachments = const [],
  });

  final String sourceOwnerId;
  final String sourceNoteId;
  final String color;
  final List<String> liveMemberIds;
  final Map<String, String> liveRoles;
  final int revision;
  final DateTime? deletedAt;
  final List<Map<String, dynamic>> attachments;
  bool get isLive => liveMemberIds.isNotEmpty;
  bool canEdit(String uid) =>
      isOwner(uid) || (liveMemberIds.contains(uid) && liveRoles[uid] == 'edit');
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

  /// Supports both camelCase domain maps (local cache/tests) and PostgreSQL snake_case rows.
  factory NoteModel.fromMap(Map<String, dynamic> map) {
    final rawDeleted = map.containsKey('deletedAt')
        ? map['deletedAt']
        : map['deleted_at'];
    final rawRoles = map['liveRoles'] ?? map['live_roles'];
    final rawAttachments = map['attachments'];

    return NoteModel(
      sourceOwnerId:
          (map['sourceOwnerId'] ?? map['source_owner_id']) as String? ?? '',
      sourceNoteId:
          (map['sourceNoteId'] ?? map['source_note_id']) as String? ?? '',
      color: map['color'] as String? ?? 'blue',
      liveMemberIds:
          _readStringList(map['liveMemberIds'] ?? map['live_member_ids']),
      liveRoles: rawRoles is Map
          ? rawRoles.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      deletedAt: rawDeleted == null ? null : _readDate(rawDeleted),
      attachments: (rawAttachments is List ? rawAttachments : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      noteId: (map['noteId'] ?? map['note_id']) as String? ?? '',
      userId: (map['userId'] ?? map['user_id']) as String? ?? '',
      ownerName: (map['ownerName'] ?? map['owner_name']) as String? ?? '',
      ownerEmail: (map['ownerEmail'] ?? map['owner_email']) as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      category: map['category'] as String? ?? 'Lecture notes',
      isFavorite:
          (map['isFavorite'] ?? map['is_favorite']) as bool? ?? false,
      sharedWithUserIds: _readStringList(
          map['sharedWithUserIds'] ?? map['shared_with_user_ids']),
      pendingSharedWithUserIds: _readStringList(map['pendingSharedWithUserIds'] ??
          map['pending_shared_with_user_ids']),
      createdAt: _readDate(map['createdAt'] ?? map['created_at']),
      updatedAt: _readDate(map['updatedAt'] ?? map['updated_at']),
    );
  }

  factory NoteModel.fromRow(Map<String, dynamic> row, {bool? personalFavorite}) {
    final model = NoteModel.fromMap(row);
    if (personalFavorite != null) {
      return model.copyWith(isFavorite: personalFavorite);
    }
    return model;
  }

  Map<String, dynamic> toMap() {
    return {
      'sourceOwnerId': sourceOwnerId,
      'sourceNoteId': sourceNoteId,
      'color': color,
      'liveMemberIds': liveMemberIds,
      'liveRoles': liveRoles,
      'revision': revision,
      'deletedAt': deletedAt?.toIso8601String(),
      'attachments': attachments,
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
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertRow({String? assignedNoteId}) {
    final id = (assignedNoteId != null && assignedNoteId.isNotEmpty)
        ? assignedNoteId
        : noteId;
    return {
      if (id.isNotEmpty) 'note_id': id,
      'user_id': userId,
      'owner_name': ownerName,
      'owner_email': ownerEmail,
      'title': title,
      'content': content,
      'category': category,
      'color': color,
      'is_favorite': isFavorite,
      'live_member_ids': const <String>[],
      'live_roles': const <String, String>{},
      'shared_with_user_ids': const <String>[],
      'pending_shared_with_user_ids': const <String>[],
      if (sourceOwnerId.isNotEmpty) 'source_owner_id': sourceOwnerId,
      if (sourceNoteId.isNotEmpty) 'source_note_id': sourceNoteId,
      'attachments': attachments,
      'revision': 0,
      'last_edited_by': userId,
      'deleted_at': null,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  NoteModel copyWith({
    String? sourceOwnerId,
    String? sourceNoteId,
    String? color,
    List<String>? liveMemberIds,
    Map<String, String>? liveRoles,
    int? revision,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    List<Map<String, dynamic>>? attachments,
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
      sourceOwnerId: sourceOwnerId ?? this.sourceOwnerId,
      sourceNoteId: sourceNoteId ?? this.sourceNoteId,
      color: color ?? this.color,
      liveMemberIds: liveMemberIds ?? this.liveMemberIds,
      liveRoles: liveRoles ?? this.liveRoles,
      revision: revision ?? this.revision,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      attachments: attachments ?? this.attachments,
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

  String get plainText {
    try {
      final value = jsonDecode(content);
      if (value is Map && value['notedDocument'] == 1 && value['ops'] is List) {
        return (value['ops'] as List)
            .whereType<Map>()
            .map((op) => op['insert'] is String ? op['insert'] as String : '')
            .join();
      }
    } catch (_) {/* Legacy notes contain Markdown. */}
    return content;
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    return title.toLowerCase().contains(normalized) ||
        plainText.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized);
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is Map) {
      final secs = value['_seconds'] ?? value['seconds'];
      if (secs is num) {
        return DateTime.fromMillisecondsSinceEpoch((secs * 1000).round());
      }
    }
    return DateTime.now();
  }

  static List<String> _readStringList(Object? value) {
    if (value is Iterable) {
      return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}
