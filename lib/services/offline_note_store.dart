import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/note_model.dart';

enum PendingNoteOpKind {
  create,
  saveCollaborative,
  softDelete,
  restore,
  toggleFavorite,
}

class PendingNoteOperation {
  const PendingNoteOperation({
    required this.opId,
    required this.kind,
    required this.noteId,
    required this.queuedAt,
    this.local,
    this.base,
    this.favoriteValue,
  });

  final String opId;
  final PendingNoteOpKind kind;
  final String noteId;
  final DateTime queuedAt;
  final NoteModel? local;
  final NoteModel? base;
  final bool? favoriteValue;

  factory PendingNoteOperation.fromJson(Map<String, dynamic> json) {
    return PendingNoteOperation(
      opId: json['opId'] as String? ?? '',
      kind: PendingNoteOpKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => PendingNoteOpKind.saveCollaborative,
      ),
      noteId: json['noteId'] as String? ?? '',
      queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
          DateTime.now(),
      local: json['local'] is Map
          ? NoteModel.fromMap(Map<String, dynamic>.from(json['local'] as Map))
          : null,
      base: json['base'] is Map
          ? NoteModel.fromMap(Map<String, dynamic>.from(json['base'] as Map))
          : null,
      favoriteValue: json['favoriteValue'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'opId': opId,
      'kind': kind.name,
      'noteId': noteId,
      'queuedAt': queuedAt.toUtc().toIso8601String(),
      if (local != null) 'local': local!.toMap(),
      if (base != null) 'base': base!.toMap(),
      if (favoriteValue != null) 'favoriteValue': favoriteValue,
    };
  }
}

/// Per-account local read cache and durable offline pending-write outbox.
/// Isolates cached notes and pending mutations strictly by `userId`.
class OfflineNoteStore {
  const OfflineNoteStore();

  // Shared across repository/store instances: the editor and library use the
  // same per-account preference value.
  static final Map<String, Future<void>> _mutations = {};

  Future<void> _mutate(String uid, Future<void> Function() action) {
    final previous = _mutations[uid] ?? Future<void>.value();
    final result = Completer<void>();
    late final Future<void> next;
    next = previous.then((_) async {
      try {
        await action();
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }).whenComplete(() {
      if (identical(_mutations[uid], next)) _mutations.remove(uid);
    });
    _mutations[uid] = next;
    return result.future;
  }

  String _notesKey(String uid) => 'noted.cache.notes.$uid';
  String _pendingSharesKey(String uid) => 'noted.cache.pending.$uid';
  String _outboxKey(String uid) => 'noted.outbox.notes.$uid';

  Future<List<NoteModel>> loadCachedNotes(String uid) async {
    if (uid.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey(uid));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => NoteModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedNotes(String uid, List<NoteModel> notes) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey(uid),
      jsonEncode(notes.map((n) => n.toMap()).toList()),
    );
  }

  Future<List<NoteModel>> loadCachedPendingShares(String uid) async {
    if (uid.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingSharesKey(uid));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => NoteModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedPendingShares(
      String uid, List<NoteModel> notes) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingSharesKey(uid),
      jsonEncode(notes.map((n) => n.toMap()).toList()),
    );
  }

  Future<List<PendingNoteOperation>> loadOutbox(String uid) async {
    if (uid.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxKey(uid));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) =>
              PendingNoteOperation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveOutbox(
    String uid,
    List<PendingNoteOperation> operations,
  ) =>
      _mutate(uid, () => _writeOutbox(uid, operations));

  Future<void> _writeOutbox(
    String uid,
    List<PendingNoteOperation> operations,
  ) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (operations.isEmpty) {
      await prefs.remove(_outboxKey(uid));
      return;
    }
    await prefs.setString(
      _outboxKey(uid),
      jsonEncode(operations.map((op) => op.toJson()).toList()),
    );
  }

  Future<void> enqueue(String uid, PendingNoteOperation op) =>
      _mutate(uid, () => _enqueue(uid, op));

  Future<void> _enqueue(String uid, PendingNoteOperation op) async {
    if (uid.isEmpty) return;
    final current = List<PendingNoteOperation>.from(await loadOutbox(uid));
    if (op.kind == PendingNoteOpKind.saveCollaborative) {
      // Coalesce consecutive unsent edits on the same note while preserving the earliest `base` snapshot!
      final existingIdx = current.lastIndexWhere(
        (e) =>
            e.noteId == op.noteId &&
            (e.kind == PendingNoteOpKind.saveCollaborative ||
                e.kind == PendingNoteOpKind.create),
      );
      if (existingIdx != -1) {
        final prev = current[existingIdx];
        if (prev.kind == PendingNoteOpKind.create && op.local != null) {
          current[existingIdx] = PendingNoteOperation(
            opId: op.opId,
            kind: PendingNoteOpKind.create,
            noteId: op.noteId,
            queuedAt: op.queuedAt,
            local: op.local!.copyWith(noteId: op.noteId),
            base: prev.base ?? prev.local,
          );
          await _writeOutbox(uid, current);
          return;
        } else if (prev.kind == PendingNoteOpKind.saveCollaborative) {
          current[existingIdx] = PendingNoteOperation(
            opId: op.opId,
            kind: PendingNoteOpKind.saveCollaborative,
            noteId: op.noteId,
            queuedAt: op.queuedAt,
            local: op.local,
            base: prev.base ?? op.base,
          );
          await _writeOutbox(uid, current);
          return;
        }
      }
    }
    current.add(op);
    await _writeOutbox(uid, current);
  }

  Future<void> removeOp(String uid, String opId) =>
      _mutate(uid, () => _removeOp(uid, opId));

  Future<void> _removeOp(String uid, String opId) async {
    if (uid.isEmpty) return;
    final current = await loadOutbox(uid);
    await _writeOutbox(
      uid,
      current.where((e) => e.opId != opId).toList(),
    );
  }

  /// Overlays queued local mutations onto `notes` so offline changes survive restarts.
  List<NoteModel> applyOutboxOverlay(
    List<NoteModel> notes,
    List<PendingNoteOperation> outbox,
  ) {
    if (outbox.isEmpty) return notes;
    final byId = <String, NoteModel>{
      for (final n in notes) n.noteId: n,
    };

    for (final op in outbox) {
      switch (op.kind) {
        case PendingNoteOpKind.create:
          if (op.local != null && op.noteId.isNotEmpty) {
            byId[op.noteId] = op.local!.copyWith(noteId: op.noteId);
          }
        case PendingNoteOpKind.saveCollaborative:
          if (op.local != null && op.noteId.isNotEmpty) {
            final prev = byId[op.noteId];
            byId[op.noteId] = (prev ?? op.local!).copyWith(
              title: op.local!.title,
              content: op.local!.content,
              category: op.local!.category,
              color: op.local!.color,
              isFavorite: op.local!.isFavorite,
              attachments: op.local!.attachments,
              createdAt: op.local!.createdAt,
              updatedAt: op.local!.updatedAt,
            );
          }
        case PendingNoteOpKind.softDelete:
          byId.remove(op.noteId);
        case PendingNoteOpKind.restore:
          if (op.local != null) {
            byId[op.noteId] = op.local!.copyWith(clearDeletedAt: true);
          }
        case PendingNoteOpKind.toggleFavorite:
          final prev = byId[op.noteId];
          if (prev != null && op.favoriteValue != null) {
            byId[op.noteId] = prev.copyWith(isFavorite: op.favoriteValue);
          }
      }
    }

    final result = byId.values.where((n) => n.deletedAt == null).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> clearUser(String uid) => _mutate(uid, () => _clearUser(uid));

  Future<void> _clearUser(String uid) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_notesKey(uid));
    await prefs.remove(_pendingSharesKey(uid));
    await prefs.remove(_outboxKey(uid));
  }
}
