import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note_model.dart';
import '../services/offline_note_store.dart';
import '../services/supabase_service.dart';
import '../utils/collaborative_document.dart';
import 'paginated_query.dart';

class NoteRepository {
  NoteRepository({
    SupabaseClient? client,
    OfflineNoteStore? offlineStore,
  })  : _clientOverride = client,
        _offlineStore = offlineStore ?? const OfflineNoteStore();

  final SupabaseClient? _clientOverride;
  final OfflineNoteStore _offlineStore;
  static final StreamController<void> _localRefresh =
      StreamController<void>.broadcast();
  static final Map<String, Future<void>> _outboxFlushes = {};

  /// Refreshes all active note streams after foreground/session recovery.
  void refresh() => _localRefresh.add(null);

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  static String _randomId([int length = 20]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  static bool _isTransientOfflineError(Object error) {
    if (error is SocketException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('clientexception') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused');
  }

  Future<void> prepareAccount() async {
    final client = _maybeClient;
    if (client == null) return;
    await SupabaseService.invokeFunction(
      'account',
      const {'action': 'prepareAccount'},
      clientOverride: client,
    );
  }

  /// Flushes any durable offline operations queued while disconnected, replaying
  /// collaborative saves through OT merge so concurrent edits are never clobbered.
  Future<void> flushOfflineOutbox(String userId) {
    final active = _outboxFlushes[userId];
    if (active != null) return active;
    late final Future<void> pending;
    pending = _replayOfflineOutbox(userId).whenComplete(() {
      if (identical(_outboxFlushes[userId], pending)) {
        _outboxFlushes.remove(userId);
      }
    });
    _outboxFlushes[userId] = pending;
    return pending;
  }

  Future<void> _replayOfflineOutbox(String userId) async {
    final client = _maybeClient;
    if (client == null ||
        userId.isEmpty ||
        client.auth.currentUser?.id != userId) {
      return;
    }

    final outbox = await _offlineStore.loadOutbox(userId);
    if (outbox.isEmpty) return;

    var rejected = 0;
    Object? rejectionCause;
    for (final op in outbox) {
      if (client.auth.currentUser?.id != userId) break;
      try {
        switch (op.kind) {
          case PendingNoteOpKind.create:
            if (op.local != null) {
              try {
                await client.from('notes').insert(
                      op.local!.toInsertRow(assignedNoteId: op.noteId),
                    );
              } on PostgrestException catch (error) {
                if (error.code != '23505') rethrow;
                // An earlier attempt may have committed before its response
                // was lost. Rebase later queued edits rather than overwrite it.
                await _commitCollaborativeOnline(
                  client: client,
                  local: op.local!,
                  base: op.base ?? op.local!,
                );
              }
            }
          case PendingNoteOpKind.saveCollaborative:
            if (op.local != null && op.base != null) {
              await _commitCollaborativeOnline(
                client: client,
                local: op.local!,
                base: op.base!,
              );
            }
          case PendingNoteOpKind.softDelete:
            await client.from('notes').update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('note_id', op.noteId);
          case PendingNoteOpKind.restore:
            await client.from('notes').update({
              'deleted_at': null,
            }).eq('note_id', op.noteId);
          case PendingNoteOpKind.toggleFavorite:
            if (op.local != null && op.favoriteValue != null) {
              await _applyFavoriteOnline(
                client: client,
                uid: userId,
                note: op.local!,
                targetFavorite: op.favoriteValue!,
              );
            }
        }
        await _offlineStore.removeOp(userId, op.opId);
      } catch (err) {
        if (_isTransientOfflineError(err)) {
          // Stop replay and preserve remaining queue for next reconnect.
          break;
        }
        if (err is NoteConflictException &&
            op.local != null &&
            op.local!.attachments.isEmpty &&
            !op.local!.content.contains('noted-media://') &&
            client.auth.currentUser?.id == userId) {
          // Preserve the user's offline draft as a recovery copy before clearing outbox.
          // Stable identity also makes recovery idempotent after response loss.
          final recoveryId = 'offline-${op.opId}';
          final baseTitle = op.local!.title.trim().isEmpty
              ? 'Untitled'
              : op.local!.title.trim();
          final recoveryTitle = '$baseTitle (Offline conflict copy)';
          final recoveryNote = op.local!.copyWith(
            noteId: recoveryId,
            userId: userId,
            title: recoveryTitle.length > 1000
                ? recoveryTitle.substring(0, 1000)
                : recoveryTitle,
            isFavorite: false,
            liveMemberIds: const [],
            liveRoles: const {},
            sharedWithUserIds: const [],
            pendingSharedWithUserIds: const [],
            sourceOwnerId: '',
            sourceNoteId: '',
            ownerName: '',
            ownerEmail: '',
            revision: 0,
            clearDeletedAt: true,
            updatedAt: DateTime.now(),
          );
          try {
            await client.from('notes').upsert(
                recoveryNote.toInsertRow(assignedNoteId: recoveryId),
                onConflict: 'note_id',
                ignoreDuplicates: true);
            await _offlineStore.removeOp(userId, op.opId);
            continue;
          } catch (copyErr) {
            if (_isTransientOfflineError(copyErr)) {
              break;
            }
          }
        }
        // Preserve the sole durable draft on every rejected write, including
        // failed recovery and media drafts that cannot be copied independently.
        rejectionCause = err;
        rejected++;
      }
    }
    if (rejected > 0) throw OfflineSyncException(rejected, rejectionCause);
  }

  Stream<List<NoteModel>> watchNotes(String userId) {
    final client = _maybeClient;
    if (client == null || userId.isEmpty) {
      return Stream<List<NoteModel>>.value(const []);
    }

    late final StreamController<List<NoteModel>> controller;
    RealtimeChannel? channel;
    StreamSubscription<void>? localSub;
    StreamSubscription<AuthState>? authSub;
    Timer? pollTimer;
    var generation = 0;

    Future<void> emitCachedIfAvailable() async {
      final cached = await _offlineStore.loadCachedNotes(userId);
      final outbox = await _offlineStore.loadOutbox(userId);
      if (client.auth.currentUser?.id == userId &&
          (cached.isNotEmpty || outbox.isNotEmpty) &&
          !controller.isClosed) {
        controller.add(_offlineStore.applyOutboxOverlay(cached, outbox));
      }
    }

    Future<void> refresh() async {
      final request = ++generation;
      OfflineSyncException? syncError;
      try {
        if (client.auth.currentUser?.id != userId) {
          if (!controller.isClosed) controller.add(const []);
          return;
        }
        try {
          await flushOfflineOutbox(userId);
        } on OfflineSyncException catch (error) {
          // Keep rejected drafts visible while still refreshing authorized rows.
          syncError = error;
        }

        final results = await Future.wait<dynamic>([
          fetchAllPages((start, end) => client
              .from('notes')
              .select()
              .eq('user_id', userId)
              .isFilter('deleted_at', null)
              .order('note_id')
              .range(start, end)),
          fetchAllPages((start, end) => client
              .from('notes')
              .select()
              .contains('live_member_ids', [userId])
              .isFilter('deleted_at', null)
              .order('note_id')
              .range(start, end)),
          fetchAllPages((start, end) => client
              .from('user_favorites')
              .select('note_id')
              .eq('user_id', userId)
              .order('note_id')
              .range(start, end)),
        ]);

        final ownedRows = results[0] as List<dynamic>;
        final liveRows = results[1] as List<dynamic>;
        final favRows = results[2] as List<dynamic>;

        final favSet = favRows
            .whereType<Map>()
            .map((r) => r['note_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        final merged = <String, NoteModel>{};
        for (final raw in [...ownedRows, ...liveRows]) {
          final map = Map<String, dynamic>.from(raw as Map);
          final note = NoteModel.fromMap(map);
          if (note.deletedAt != null) continue;
          merged[note.noteId] = note.userId == userId
              ? note
              : note.copyWith(isFavorite: favSet.contains(note.noteId));
        }

        final sorted = merged.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        if (request != generation || client.auth.currentUser?.id != userId) {
          return;
        }
        await _offlineStore.saveCachedNotes(userId, sorted);
        final outbox = await _offlineStore.loadOutbox(userId);
        final authorizedIds = merged.keys.toSet();
        final visibleOutbox = outbox
            .where((op) =>
                op.kind == PendingNoteOpKind.create ||
                authorizedIds.contains(op.noteId))
            .toList();
        if (request == generation &&
            client.auth.currentUser?.id == userId &&
            !controller.isClosed) {
          controller
              .add(_offlineStore.applyOutboxOverlay(sorted, visibleOutbox));
          if (syncError != null) controller.addError(syncError);
        }
      } catch (err) {
        if (_isTransientOfflineError(err)) {
          await emitCachedIfAvailable();
          return;
        }
        if (request == generation &&
            client.auth.currentUser?.id == userId &&
            !controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<List<NoteModel>>(
      onListen: () {
        emitCachedIfAvailable().then((_) => refresh());
        localSub = _localRefresh.stream.listen((_) => refresh());
        authSub = client.auth.onAuthStateChange.listen((_) => refresh());
        pollTimer =
            Timer.periodic(const Duration(seconds: 30), (_) => refresh());
        channel = client
            .channel('notes-library-$userId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notes',
              callback: (_) => refresh(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'user_favorites',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) refresh();
        });
      },
      onCancel: () async {
        await localSub?.cancel();
        await authSub?.cancel();
        pollTimer?.cancel();
        generation++;
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> addNote(NoteModel note) async {
    await createNote(note);
  }

  Future<String> createNote(NoteModel note) async {
    final assignedId = note.noteId.isNotEmpty ? note.noteId : _randomId();
    final now = DateTime.now();
    final savedNote = note.copyWith(
      noteId: assignedId,
      createdAt: note.createdAt,
      updatedAt: now,
      revision: 0,
    );

    try {
      await _client
          .from('notes')
          .insert(savedNote.toInsertRow(assignedNoteId: assignedId));
      _localRefresh.add(null);
      return assignedId;
    } catch (err) {
      if (_isTransientOfflineError(err) && note.userId.isNotEmpty) {
        await _offlineStore.enqueue(
          note.userId,
          PendingNoteOperation(
            opId: _randomId(16),
            kind: PendingNoteOpKind.create,
            noteId: assignedId,
            queuedAt: now,
            local: savedNote,
          ),
        );
        _localRefresh.add(null);
        return assignedId;
      }
      rethrow;
    }
  }

  Future<void> updateNote(NoteModel note) async {
    await saveCollaborative(note, note);
  }

  /// Pure collaborative rebase + metadata conflict detector used by `saveCollaborative`.
  static NoteModel mergeCollaborativeDraft({
    required NoteModel local,
    required NoteModel base,
    required NoteModel remote,
    required bool isOwner,
  }) {
    if (remote.deletedAt != null) {
      throw StateError('This note was deleted.');
    }

    T choose<T>(T original, T draft, T current) {
      if (draft == original) return current;
      if (current == original || current == draft) return draft;
      throw NoteConflictException(remote);
    }

    final String mergedContent;
    try {
      mergedContent = mergeContent(
        base: base.content,
        local: local.content,
        remote: remote.content,
      );
    } catch (_) {
      throw NoteConflictException(remote);
    }

    final mergedAttachments = _mergeAttachments(
      base.attachments,
      local.attachments,
      remote.attachments,
      remote,
    );

    return remote.copyWith(
      title: choose(base.title, local.title, remote.title),
      content: mergedContent,
      category: choose(base.category, local.category, remote.category),
      color: choose(base.color, local.color, remote.color),
      createdAt: choose(base.createdAt, local.createdAt, remote.createdAt),
      isFavorite: isOwner
          ? choose(base.isFavorite, local.isFavorite, remote.isFavorite)
          : remote.isFavorite,
      attachments: mergedAttachments,
      revision: remote.revision + 1,
      updatedAt: DateTime.now(),
    );
  }

  Future<NoteModel> _commitCollaborativeOnline({
    required SupabaseClient client,
    required NoteModel local,
    required NoteModel base,
  }) async {
    final currentUid = client.auth.currentUser?.id ?? local.userId;
    var candidate = local;
    var expectedRevision = base.revision;

    for (var attempt = 0; attempt < 5; attempt++) {
      final raw = await client.rpc(
        'commit_note_revision',
        params: {
          'p_note_id': local.noteId,
          'p_expected_revision': expectedRevision,
          'p_title': candidate.title,
          'p_content': candidate.content,
          'p_category': candidate.category,
          'p_color': candidate.color,
          'p_is_favorite': candidate.isFavorite,
          'p_attachments': candidate.attachments,
          'p_created_at': candidate.createdAt.toUtc().toIso8601String(),
        },
      );

      final response = raw is Map
          ? Map<String, dynamic>.from(raw)
          : throw StateError('Unexpected revision response.');

      if (response['committed'] == true && response['note'] is Map) {
        final committed = NoteModel.fromMap(
          Map<String, dynamic>.from(response['note'] as Map),
        );
        final isOwner = committed.userId == currentUid;
        return isOwner
            ? committed
            : committed.copyWith(isFavorite: local.isFavorite);
      }

      if (response['remote'] is! Map) {
        throw StateError('This note no longer exists.');
      }

      final remote = NoteModel.fromMap(
        Map<String, dynamic>.from(response['remote'] as Map),
      );
      final isOwner = remote.userId == currentUid;
      candidate = mergeCollaborativeDraft(
        local: local,
        base: base,
        remote: remote,
        isOwner: isOwner,
      );
      expectedRevision = remote.revision;
    }

    throw StateError(
      'High collaborative activity on this note. Please save again.',
    );
  }

  /// Rebases local document operations onto the latest committed document via
  /// atomic revision-checked CAS RPC (`commit_note_revision`). Concurrent
  /// metadata conflicts throw `NoteConflictException` for user review.
  Future<NoteModel> saveCollaborative(NoteModel local, NoteModel base) async {
    if (local.noteId != base.noteId || local.noteId.isEmpty) {
      throw ArgumentError('A saved note and matching base are required.');
    }

    final uid = _maybeClient?.auth.currentUser?.id ?? local.userId;
    final pending = await _offlineStore.loadOutbox(uid);
    if (pending.any((op) => op.noteId == local.noteId)) {
      final optimistic = local.copyWith(updatedAt: DateTime.now());
      await _offlineStore.enqueue(
          uid,
          PendingNoteOperation(
            opId: _randomId(16),
            kind: PendingNoteOpKind.saveCollaborative,
            noteId: local.noteId,
            queuedAt: DateTime.now(),
            local: optimistic,
            base: base,
          ));
      _localRefresh.add(null);
      return optimistic;
    }
    try {
      final saved = await _commitCollaborativeOnline(
        client: _client,
        local: local,
        base: base,
      );
      _localRefresh.add(null);
      return saved;
    } catch (err) {
      final uid = _maybeClient?.auth.currentUser?.id ?? local.userId;
      if (_isTransientOfflineError(err) && uid.isNotEmpty) {
        final optimistic = local.copyWith(updatedAt: DateTime.now());
        await _offlineStore.enqueue(
          uid,
          PendingNoteOperation(
            opId: _randomId(16),
            kind: PendingNoteOpKind.saveCollaborative,
            noteId: local.noteId,
            queuedAt: DateTime.now(),
            local: optimistic,
            base: base,
          ),
        );
        _localRefresh.add(null);
        return optimistic;
      }
      rethrow;
    }
  }

  static List<Map<String, dynamic>> _mergeAttachments(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
    NoteModel current,
  ) {
    String key(Map<String, dynamic> value) =>
        (value['path'] ?? value['url'] ?? jsonEncode(value)).toString();
    final original = {for (final item in base) key(item): item};
    final draft = {for (final item in local) key(item): item};
    final merged = {for (final item in remote) key(item): item};
    for (final id in original.keys) {
      if (!draft.containsKey(id)) merged.remove(id);
    }
    for (final entry in draft.entries) {
      if (jsonEncode(entry.value) == jsonEncode(original[entry.key])) continue;
      final currentValue = merged[entry.key];
      if (currentValue != null &&
          original.containsKey(entry.key) &&
          jsonEncode(currentValue) != jsonEncode(original[entry.key]) &&
          jsonEncode(currentValue) != jsonEncode(entry.value)) {
        throw NoteConflictException(current);
      }
      merged[entry.key] = entry.value;
    }
    return merged.values.toList();
  }

  Future<void> deleteNote(String noteId) async {
    final uid = _maybeClient?.auth.currentUser?.id ?? '';
    try {
      await _client.from('notes').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('note_id', noteId);
      _localRefresh.add(null);
    } catch (err) {
      if (_isTransientOfflineError(err) && uid.isNotEmpty) {
        await _offlineStore.enqueue(
          uid,
          PendingNoteOperation(
            opId: _randomId(16),
            kind: PendingNoteOpKind.softDelete,
            noteId: noteId,
            queuedAt: DateTime.now(),
          ),
        );
        _localRefresh.add(null);
        return;
      }
      rethrow;
    }
  }

  Future<void> restoreNote(String noteId) async {
    final uid = _maybeClient?.auth.currentUser?.id ?? '';
    try {
      await _client.from('notes').update({
        'deleted_at': null,
      }).eq('note_id', noteId);
      _localRefresh.add(null);
    } catch (err) {
      if (_isTransientOfflineError(err) && uid.isNotEmpty) {
        final cached = await _offlineStore.loadCachedNotes(uid);
        final localMatch = cached.where((n) => n.noteId == noteId).firstOrNull;
        await _offlineStore.enqueue(
          uid,
          PendingNoteOperation(
            opId: _randomId(16),
            kind: PendingNoteOpKind.restore,
            noteId: noteId,
            queuedAt: DateTime.now(),
            local: localMatch,
          ),
        );
        _localRefresh.add(null);
        return;
      }
      rethrow;
    }
  }

  Future<void> permanentlyDeleteNote(String noteId) async {
    await SupabaseService.invokeFunction(
      'note-sharing',
      {
        'action': 'deleteNote',
        'noteId': noteId,
      },
      clientOverride: _clientOverride,
    );
    _localRefresh.add(null);
  }

  Stream<List<NoteModel>> watchDeletedNotes(String userId) {
    final client = _maybeClient;
    if (client == null || userId.isEmpty) {
      return Stream<List<NoteModel>>.value(const []);
    }

    late final StreamController<List<NoteModel>> controller;
    RealtimeChannel? channel;
    StreamSubscription<void>? localSub;

    Future<void> refresh() async {
      try {
        final rows = await fetchAllPages((start, end) => client
            .from('notes')
            .select()
            .eq('user_id', userId)
            .not('deleted_at', 'is', null)
            .order('note_id')
            .range(start, end));

        final list = rows
            .map((r) => NoteModel.fromMap(Map<String, dynamic>.from(r)))
            .where((n) => n.deletedAt != null)
            .toList()
          ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

        if (!controller.isClosed) {
          controller.add(list);
        }
      } catch (err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<List<NoteModel>>(
      onListen: () {
        refresh();
        localSub = _localRefresh.stream.listen((_) => refresh());
        channel = client
            .channel('notes-trash-$userId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notes',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        await localSub?.cancel();
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<NoteModel?> getNoteById(String noteId) async {
    final client = _maybeClient;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null || noteId.isEmpty) return null;

    final row =
        await client.from('notes').select().eq('note_id', noteId).maybeSingle();
    if (row == null) return null;
    final model = NoteModel.fromMap(Map<String, dynamic>.from(row));
    if (model.userId != uid &&
        !model.liveMemberIds.contains(uid) &&
        !model.pendingSharedWithUserIds.contains(uid)) {
      return null;
    }
    if (model.userId == uid) return model;
    final fav = await client
        .from('user_favorites')
        .select('note_id')
        .eq('user_id', uid)
        .eq('note_id', noteId)
        .maybeSingle();
    return model.copyWith(isFavorite: fav != null);
  }

  Stream<NoteModel?> watchNote(String noteId) {
    final client = _maybeClient;
    final uid = client?.auth.currentUser?.id;
    if (client == null || noteId.isEmpty) {
      return Stream<NoteModel?>.value(null);
    }

    late final StreamController<NoteModel?> controller;
    RealtimeChannel? channel;
    StreamSubscription<void>? localSub;
    StreamSubscription<AuthState>? authSub;
    Timer? pollTimer;
    var generation = 0;

    Future<void> refresh() async {
      final request = ++generation;
      try {
        final activeUid = client.auth.currentUser?.id;
        if (activeUid == null || activeUid != uid) {
          if (!controller.isClosed) controller.add(null);
          return;
        }
        final note = await getNoteById(noteId);
        if (request != generation || client.auth.currentUser?.id != uid) return;
        if (note == null || note.deletedAt != null) {
          final outbox = await _offlineStore.loadOutbox(uid!);
          final pendingCreate = outbox.where((op) =>
              op.noteId == noteId && op.kind == PendingNoteOpKind.create);
          final draft = pendingCreate.isEmpty ? null : pendingCreate.last.local;
          if (request == generation &&
              client.auth.currentUser?.id == uid &&
              !controller.isClosed) {
            controller.add(draft);
          }
          return;
        }
        final outbox = await _offlineStore.loadOutbox(uid!);
        final overlay = _offlineStore.applyOutboxOverlay([note], outbox);
        if (request == generation &&
            client.auth.currentUser?.id == uid &&
            !controller.isClosed) {
          controller.add(overlay.where((n) => n.noteId == noteId).firstOrNull);
        }
      } catch (err) {
        if (_isTransientOfflineError(err) && uid != null) {
          final cached = await _offlineStore.loadCachedNotes(uid);
          final outbox = await _offlineStore.loadOutbox(uid);
          final overlay = _offlineStore.applyOutboxOverlay(cached, outbox);
          if (request == generation &&
              client.auth.currentUser?.id == uid &&
              !controller.isClosed) {
            final note = overlay.where((n) => n.noteId == noteId).firstOrNull;
            if (note == null) {
              controller.addError(err);
            } else {
              controller.add(note);
            }
          }
          return;
        }
        if (request == generation &&
            client.auth.currentUser?.id == uid &&
            !controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<NoteModel?>(
      onListen: () {
        refresh();
        localSub = _localRefresh.stream.listen((_) => refresh());
        authSub = client.auth.onAuthStateChange.listen((_) => refresh());
        pollTimer =
            Timer.periodic(const Duration(seconds: 30), (_) => refresh());
        channel = client
            .channel('note-doc-$noteId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notes',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'note_id',
                value: noteId,
              ),
              callback: (_) => refresh(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'user_favorites',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'note_id',
                value: noteId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) refresh();
        });
      },
      onCancel: () async {
        await localSub?.cancel();
        await authSub?.cancel();
        pollTimer?.cancel();
        generation++;
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Stream<List<Map<String, dynamic>>> watchPresence(String noteId) {
    final client = _maybeClient;
    if (client == null || noteId.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }

    late final StreamController<List<Map<String, dynamic>>> controller;
    RealtimeChannel? channel;
    Timer? expiryTimer;
    var cached = <Map<String, dynamic>>[];

    void emitActive() {
      if (controller.isClosed) return;
      final now = DateTime.now();
      controller.add(
        cached.where((entry) {
          final exp = entry['expiresAt'];
          return exp is DateTime && exp.isAfter(now);
        }).toList(),
      );
    }

    Future<void> refresh() async {
      try {
        final rows =
            await client.from('note_presence').select().eq('note_id', noteId);
        cached = rows.map((raw) {
          final r = Map<String, dynamic>.from(raw);
          return <String, dynamic>{
            'userId': r['user_id']?.toString() ?? '',
            'name': r['name']?.toString() ?? '',
            'typing': r['typing'] == true,
            'expiresAt': DateTime.tryParse(r['expires_at']?.toString() ?? ''),
          };
        }).toList();
        emitActive();
      } catch (_) {
        cached = const [];
        emitActive();
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        refresh();
        expiryTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => emitActive(),
        );
        channel = client
            .channel('note-presence-$noteId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'note_presence',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'note_id',
                value: noteId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        expiryTimer?.cancel();
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> updatePresence(
    String noteId,
    String userId,
    String name, {
    bool typing = false,
  }) async {
    final client = _maybeClient;
    if (client == null || noteId.isEmpty || userId.isEmpty) return;
    await client.from('note_presence').upsert(
      {
        'note_id': noteId,
        'user_id': userId,
        'name': name,
        'typing': typing,
        'expires_at': DateTime.now()
            .add(const Duration(seconds: 45))
            .toUtc()
            .toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'note_id,user_id',
    );
  }

  Future<void> leavePresence(String noteId, String userId) async {
    final client = _maybeClient;
    if (client == null || noteId.isEmpty || userId.isEmpty) return;
    await client
        .from('note_presence')
        .delete()
        .eq('note_id', noteId)
        .eq('user_id', userId);
  }

  Future<void> _applyFavoriteOnline({
    required SupabaseClient client,
    required String uid,
    required NoteModel note,
    required bool targetFavorite,
  }) async {
    if (note.userId == uid) {
      await client
          .from('notes')
          .update({'is_favorite': targetFavorite}).eq('note_id', note.noteId);
    } else {
      if (!targetFavorite) {
        await client
            .from('user_favorites')
            .delete()
            .eq('user_id', uid)
            .eq('note_id', note.noteId);
      } else {
        await client.from('user_favorites').upsert(
          {
            'user_id': uid,
            'note_id': note.noteId,
          },
          onConflict: 'user_id,note_id',
        );
      }
    }
  }

  Future<void> toggleFavorite(NoteModel note) async {
    final uid = _maybeClient?.auth.currentUser?.id;
    if (uid == null) throw StateError('Sign in to favorite a note.');
    final target = !note.isFavorite;

    try {
      await _applyFavoriteOnline(
        client: _client,
        uid: uid,
        note: note,
        targetFavorite: target,
      );
      _localRefresh.add(null);
    } catch (err) {
      if (_isTransientOfflineError(err)) {
        await _offlineStore.enqueue(
          uid,
          PendingNoteOperation(
            opId: _randomId(16),
            kind: PendingNoteOpKind.toggleFavorite,
            noteId: note.noteId,
            queuedAt: DateTime.now(),
            local: note,
            favoriteValue: target,
          ),
        );
        _localRefresh.add(null);
        return;
      }
      rethrow;
    }
  }

  Future<void> shareNote({
    required NoteModel note,
    required String targetUserId,
    String? ownerName,
    String? ownerEmail,
  }) async {
    await SupabaseService.invokeFunction(
      'note-sharing',
      {
        'action': 'queueNoteCopy',
        'noteId': note.noteId,
        'targetUserId': targetUserId,
      },
      clientOverride: _clientOverride,
    );
    _localRefresh.add(null);
  }

  Future<void> setLiveRole(
    String noteId,
    String targetUserId,
    String? role,
  ) async {
    await SupabaseService.invokeFunction(
      'note-sharing',
      {
        'action': 'setLiveRole',
        'noteId': noteId,
        'targetUserId': targetUserId,
        'role': role ?? 'none',
      },
      clientOverride: _clientOverride,
    );
    _localRefresh.add(null);
  }

  Stream<List<NoteModel>> watchPendingSharedNotes(String userId) {
    final client = _maybeClient;
    if (client == null || userId.isEmpty) {
      return Stream<List<NoteModel>>.value(const []);
    }

    late final StreamController<List<NoteModel>> controller;
    RealtimeChannel? channel;
    StreamSubscription<void>? localSub;

    Future<void> refresh() async {
      try {
        final rows = await fetchAllPages((start, end) => client
            .from('notes')
            .select()
            .contains('pending_shared_with_user_ids', [userId])
            .isFilter('deleted_at', null)
            .order('note_id')
            .range(start, end));

        final notes = rows
            .map((r) => NoteModel.fromMap(Map<String, dynamic>.from(r)))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        await _offlineStore.saveCachedPendingShares(userId, notes);
        if (!controller.isClosed) {
          controller.add(notes);
        }
      } catch (err) {
        if (_isTransientOfflineError(err)) {
          final cached = await _offlineStore.loadCachedPendingShares(userId);
          if (!controller.isClosed) controller.add(cached);
          return;
        }
        if (!controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<List<NoteModel>>(
      onListen: () {
        refresh();
        localSub = _localRefresh.stream.listen((_) => refresh());
        channel = client
            .channel('notes-pending-$userId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notes',
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        await localSub?.cancel();
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> acceptShare(
    String noteId,
    String userId, {
    String ownerName = '',
    String ownerEmail = '',
  }) async {
    await SupabaseService.invokeFunction(
      'note-sharing',
      {
        'action': 'acceptNoteCopy',
        'noteId': noteId,
      },
      clientOverride: _clientOverride,
    );
    _localRefresh.add(null);
  }

  Future<void> declineShare(String noteId, String userId) async {
    await _client.rpc(
      'decline_note_share',
      params: {'p_note_id': noteId},
    );
    _localRefresh.add(null);
  }
}

class NoteConflictException implements Exception {
  const NoteConflictException(this.currentNote);
  final NoteModel currentNote;
  @override
  String toString() =>
      'This note changed on another device. Review the latest version before saving your draft.';
}

class OfflineSyncException implements Exception {
  const OfflineSyncException(this.pendingCount, [this.cause]);
  final int pendingCount;
  final Object? cause;

  @override
  String toString() =>
      '$pendingCount offline change(s) need review. Your drafts are kept on this device; restore access or resolve the conflict before syncing again.';
}
