class PersonalWorkspace {
  const PersonalWorkspace({required this.id, required this.name});

  final String id;
  final String name;

  factory PersonalWorkspace.fromMap(Map<String, dynamic> map) {
    return PersonalWorkspace(
      id: map['id']?.toString() ?? '',
      name: (map['name']?.toString() ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}

class WorkspaceSelection {
  const WorkspaceSelection._(this.workspaceId);

  static const String defaultWorkspaceId = 'default';
  static const String _allStorageValue = '__all__';

  static const all = WorkspaceSelection._(null);
  static const defaultWorkspace = WorkspaceSelection._(defaultWorkspaceId);

  final String? workspaceId;

  bool get isAll => workspaceId == null;
  bool get isDefault => workspaceId == defaultWorkspaceId;
  bool get isNamed => workspaceId != null && !isDefault;

  factory WorkspaceSelection.named(String workspaceId) {
    final value = workspaceId.trim();
    if (value.isEmpty || value == defaultWorkspaceId) {
      throw ArgumentError.value(workspaceId, 'workspaceId');
    }
    return WorkspaceSelection._(value);
  }

  factory WorkspaceSelection.fromStorage(String? value) {
    if (value == null || value.isEmpty || value == _allStorageValue) {
      return all;
    }
    if (value == defaultWorkspaceId) return defaultWorkspace;
    return WorkspaceSelection.named(value);
  }

  String toStorage() => workspaceId ?? _allStorageValue;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceSelection && other.workspaceId == workspaceId;

  @override
  int get hashCode => workspaceId.hashCode;
}

class WorkspaceLibrarySnapshot {
  WorkspaceLibrarySnapshot({
    required List<PersonalWorkspace> workspaces,
    required Map<String, String> assignments,
    required this.loadedAt,
    this.fromCache = false,
    this.errorMessage,
  })  : workspaces = List.unmodifiable(workspaces),
        assignments = Map.unmodifiable(assignments);

  factory WorkspaceLibrarySnapshot.unavailable([String? errorMessage]) {
    return WorkspaceLibrarySnapshot(
      workspaces: const [],
      assignments: const {},
      loadedAt: null,
      errorMessage: errorMessage,
    );
  }

  final List<PersonalWorkspace> workspaces;

  /// Note ID to workspace ID. A missing note has no row and is in Default.
  final Map<String, String> assignments;
  final DateTime? loadedAt;
  final bool fromCache;
  final String? errorMessage;

  bool get hasAssignmentData => loadedAt != null;

  String workspaceIdFor(String noteId) =>
      assignments[noteId] ?? WorkspaceSelection.defaultWorkspaceId;

  WorkspaceLibrarySnapshot copyWith({
    List<PersonalWorkspace>? workspaces,
    Map<String, String>? assignments,
    DateTime? loadedAt,
    bool? fromCache,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WorkspaceLibrarySnapshot(
      workspaces: workspaces ?? this.workspaces,
      assignments: assignments ?? this.assignments,
      loadedAt: loadedAt ?? this.loadedAt,
      fromCache: fromCache ?? this.fromCache,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
