import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace_model.dart';

/// Persists private workspace metadata and the selected Library workspace per
/// account. Keys include the user ID so a cache can never cross accounts.
class WorkspaceCacheStore {
  const WorkspaceCacheStore();

  String _snapshotKey(String uid) => 'noted.cache.workspaces.$uid';
  String _selectionKey(String uid) => 'noted.selection.workspace.$uid';

  Future<WorkspaceLibrarySnapshot?> loadSnapshot(String uid) async {
    if (uid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final loadedAt = DateTime.tryParse(map['loadedAt']?.toString() ?? '');
      final rawWorkspaces = map['workspaces'];
      final rawAssignments = map['assignments'];
      if (loadedAt == null ||
          rawWorkspaces is! List ||
          rawAssignments is! Map) {
        return null;
      }
      final workspaces = rawWorkspaces
          .whereType<Map>()
          .map((row) =>
              PersonalWorkspace.fromMap(Map<String, dynamic>.from(row)))
          .where((workspace) => workspace.id.isNotEmpty)
          .toList();
      final workspaceIds = workspaces.map((workspace) => workspace.id).toSet();
      final assignments = <String, String>{};
      for (final entry in rawAssignments.entries) {
        final noteId = entry.key.toString();
        final workspaceId = entry.value?.toString() ?? '';
        if (noteId.isNotEmpty && workspaceIds.contains(workspaceId)) {
          assignments[noteId] = workspaceId;
        }
      }
      return WorkspaceLibrarySnapshot(
        workspaces: workspaces,
        assignments: assignments,
        loadedAt: loadedAt,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSnapshot(
    String uid,
    WorkspaceLibrarySnapshot snapshot,
  ) async {
    if (uid.isEmpty || !snapshot.hasAssignmentData) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snapshotKey(uid),
      jsonEncode({
        'workspaces':
            snapshot.workspaces.map((workspace) => workspace.toMap()).toList(),
        'assignments': snapshot.assignments,
        'loadedAt': snapshot.loadedAt!.toUtc().toIso8601String(),
      }),
    );
  }

  Future<WorkspaceSelection> loadSelection(String uid) async {
    if (uid.isEmpty) return WorkspaceSelection.all;
    final prefs = await SharedPreferences.getInstance();
    return WorkspaceSelection.fromStorage(prefs.getString(_selectionKey(uid)));
  }

  Future<void> saveSelection(
    String uid,
    WorkspaceSelection selection,
  ) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectionKey(uid), selection.toStorage());
  }

  Future<void> clearUser(String uid) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snapshotKey(uid));
    await prefs.remove(_selectionKey(uid));
  }
}
