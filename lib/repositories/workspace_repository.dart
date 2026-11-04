import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workspace_model.dart';
import '../services/supabase_service.dart';
import '../services/workspace_cache_store.dart';
import 'paginated_query.dart';

class WorkspaceRepository {
  WorkspaceRepository({
    SupabaseClient? client,
    WorkspaceCacheStore? cacheStore,
  })  : _clientOverride = client,
        _cacheStore = cacheStore ?? const WorkspaceCacheStore();

  final SupabaseClient? _clientOverride;
  final WorkspaceCacheStore _cacheStore;
  static final StreamController<void> _localRefresh =
      StreamController<void>.broadcast();

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  String get _uid =>
      _client.auth.currentUser?.id ?? (throw StateError('Sign in required'));

  void refresh() => _localRefresh.add(null);

  Future<List<PersonalWorkspace>> list({String? userId}) async {
    final client = _maybeClient;
    final uid = userId ?? _uid;
    if (client == null || client.auth.currentUser?.id != uid) {
      throw StateError('Sign in required');
    }
    final rows = await fetchAllPages<Map<String, dynamic>>((start, end) =>
        client
            .from('personal_workspaces')
            .select('id, name')
            .eq('user_id', uid)
            .order('name')
            .order('id')
            .range(start, end));
    final workspaces = rows
        .map(PersonalWorkspace.fromMap)
        .where((workspace) => workspace.id.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return workspaces;
  }

  Future<String> assignment(String noteId) async {
    final row = await _client
        .from('personal_workspace_notes')
        .select('workspace_id')
        .eq('user_id', _uid)
        .eq('note_id', noteId)
        .maybeSingle();
    return row?['workspace_id'] as String? ??
        WorkspaceSelection.defaultWorkspaceId;
  }

  Future<void> assign(String noteId, String workspaceId) async {
    final uid = _uid;
    if (workspaceId == WorkspaceSelection.defaultWorkspaceId) {
      await _client
          .from('personal_workspace_notes')
          .delete()
          .eq('user_id', uid)
          .eq('note_id', noteId);
    } else {
      await _client.from('personal_workspace_notes').upsert(
        {
          'user_id': uid,
          'note_id': noteId,
          'workspace_id': workspaceId,
        },
        onConflict: 'user_id,note_id',
      );
    }
    refresh();
  }

  Future<void> create(String name) async {
    await _client.from('personal_workspaces').insert({
      'user_id': _uid,
      'name': name.trim(),
    });
    refresh();
  }

  Future<void> rename(String id, String name) async {
    final rows = await _client
        .from('personal_workspaces')
        .update({'name': name.trim()})
        .eq('user_id', _uid)
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('This workspace no longer exists.');
    }
    refresh();
  }

  Future<void> delete(String id) async {
    final rows = await _client
        .from('personal_workspaces')
        .delete()
        .eq('user_id', _uid)
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('This workspace no longer exists.');
    }
    refresh();
  }

  Future<WorkspaceLibrarySnapshot> loadLibrary(String userId) async {
    final client = _maybeClient;
    if (client == null) {
      throw StateError('Workspace data requires a connection.');
    }
    if (userId.isEmpty || client.auth.currentUser?.id != userId) {
      throw StateError('Workspace data belongs to another account.');
    }

    final results = await Future.wait<dynamic>([
      fetchAllPages<Map<String, dynamic>>((start, end) => client
          .from('personal_workspaces')
          .select('id, name')
          .eq('user_id', userId)
          .order('name')
          .order('id')
          .range(start, end)),
      fetchAllPages<Map<String, dynamic>>((start, end) => client
          .from('personal_workspace_notes')
          .select('note_id, workspace_id')
          .eq('user_id', userId)
          .order('note_id')
          .range(start, end)),
    ]);

    if (client.auth.currentUser?.id != userId) {
      throw StateError('The active account changed while loading workspaces.');
    }

    final workspaces = (results[0] as List<Map<String, dynamic>>)
        .map(PersonalWorkspace.fromMap)
        .where((workspace) => workspace.id.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    final workspaceIds = workspaces.map((workspace) => workspace.id).toSet();
    final assignments = <String, String>{};
    for (final row in results[1] as List<Map<String, dynamic>>) {
      final noteId = row['note_id']?.toString() ?? '';
      final workspaceId = row['workspace_id']?.toString() ?? '';
      if (noteId.isNotEmpty && workspaceIds.contains(workspaceId)) {
        assignments[noteId] = workspaceId;
      }
    }
    return WorkspaceLibrarySnapshot(
      workspaces: workspaces,
      assignments: assignments,
      loadedAt: DateTime.now(),
    );
  }

  Stream<WorkspaceLibrarySnapshot> watchLibrary(String userId) {
    final client = _maybeClient;
    if (client == null || userId.isEmpty) {
      return Stream.value(WorkspaceLibrarySnapshot.unavailable(
        'Workspace assignments are unavailable.',
      ));
    }

    late final StreamController<WorkspaceLibrarySnapshot> controller;
    StreamSubscription<void>? localSub;
    StreamSubscription<AuthState>? authSub;
    Timer? pollTimer;
    var generation = 0;
    var cancelled = false;

    Future<void> refresh() async {
      final request = ++generation;
      try {
        final snapshot = await loadLibrary(userId);
        if (request != generation ||
            client.auth.currentUser?.id != userId ||
            controller.isClosed) {
          return;
        }
        await _cacheStore.saveSnapshot(userId, snapshot);
        if (request == generation &&
            client.auth.currentUser?.id == userId &&
            !controller.isClosed) {
          controller.add(snapshot);
        }
      } catch (error) {
        if (request != generation ||
            client.auth.currentUser?.id != userId ||
            controller.isClosed) {
          return;
        }
        WorkspaceLibrarySnapshot? cached;
        try {
          cached = await _cacheStore.loadSnapshot(userId);
        } catch (_) {
          cached = null;
        }
        if (request != generation ||
            client.auth.currentUser?.id != userId ||
            controller.isClosed) {
          return;
        }
        controller.add(cached?.copyWith(
              fromCache: true,
              errorMessage: 'Using saved workspace assignments.',
            ) ??
            WorkspaceLibrarySnapshot.unavailable(
              'Workspace assignments could not be loaded.',
            ));
      }
    }

    controller = StreamController<WorkspaceLibrarySnapshot>(
      onListen: () async {
        WorkspaceLibrarySnapshot? cached;
        try {
          cached = await _cacheStore.loadSnapshot(userId);
        } catch (_) {
          cached = null;
        }
        if (client.auth.currentUser?.id == userId &&
            cached != null &&
            !cancelled &&
            !controller.isClosed) {
          controller.add(cached.copyWith(fromCache: true));
        }
        await refresh();
        if (cancelled || controller.isClosed) return;
        localSub = _localRefresh.stream.listen((_) => refresh());
        authSub = client.auth.onAuthStateChange.listen((state) {
          if (client.auth.currentUser?.id == userId) refresh();
        });
        pollTimer =
            Timer.periodic(const Duration(seconds: 30), (_) => refresh());
      },
      onCancel: () async {
        cancelled = true;
        await localSub?.cancel();
        await authSub?.cancel();
        pollTimer?.cancel();
        generation++;
      },
    );
    return controller.stream;
  }

  Future<WorkspaceSelection> loadSelection(String userId) async {
    if (userId.isEmpty) return WorkspaceSelection.all;
    try {
      return await _cacheStore.loadSelection(userId);
    } catch (_) {
      return WorkspaceSelection.all;
    }
  }

  Future<void> saveSelection(
    String userId,
    WorkspaceSelection selection,
  ) async {
    if (userId.isEmpty) return;
    await _cacheStore.saveSelection(userId, selection);
  }
}
