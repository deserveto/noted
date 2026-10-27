class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
    this.fieldOfStudy = '',
    this.avatarUrl = '',
    this.avatarPath = '',
  });

  final String uid;
  final String name;
  final String email;
  final DateTime createdAt;
  final String fieldOfStudy;
  final String avatarUrl;
  final String avatarPath;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final rawAvatarPath =
        (map['avatarPath'] ?? map['avatar_path']) as String? ?? '';
    final rawAvatarUrl =
        (map['avatarUrl'] ?? map['avatar_url']) as String? ?? '';
    final effectiveAvatarUrl = rawAvatarUrl.isNotEmpty
        ? rawAvatarUrl
        : (rawAvatarPath.isNotEmpty
            ? 'noted-media://avatars/$rawAvatarPath'
            : '');

    return UserModel(
      uid: (map['uid'] ?? map['id']) as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      fieldOfStudy:
          (map['fieldOfStudy'] ?? map['field_of_study']) as String? ?? '',
      avatarUrl: effectiveAvatarUrl,
      avatarPath: rawAvatarPath,
      createdAt: _readDate(map['createdAt'] ?? map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'fieldOfStudy': fieldOfStudy,
      'avatarUrl': avatarUrl,
      if (avatarPath.isNotEmpty) 'avatarPath': avatarPath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toProfileRow() {
    return {
      'id': uid,
      'name': name,
      'email': email,
      'field_of_study': fieldOfStudy,
      'avatar_url': avatarUrl,
      if (avatarPath.isNotEmpty) 'avatar_path': avatarPath,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    DateTime? createdAt,
    String? fieldOfStudy,
    String? avatarUrl,
    String? avatarPath,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarPath: avatarPath ?? this.avatarPath,
    );
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
    return DateTime.now();
  }
}
