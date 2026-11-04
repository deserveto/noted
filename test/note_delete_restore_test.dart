import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:noted/models/note_model.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/services/offline_note_store.dart';

const _uid = '11111111-1111-4111-8111-111111111111';
const _uidB = '22222222-2222-4222-8222-222222222222';
const _store = OfflineNoteStore();

NoteModel _note(String id, String title, {String uid = _uid}) =>
    NoteModel.empty(uid).copyWith(noteId: id, title: title);

Future<void> _auth(SupabaseClient client, String uid) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'test-token',
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': uid,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

/// In-memory PostgREST stand-in for `notes` + `user_favorites`.
class _FakeNotesServer {
  _FakeNotesServer(this.notes);

  final Map<String, NoteModel> notes;
  bool offline = false;

  /// Block PATCH writes deterministically.
  Completer<void>? blockPatch;
  int patchCalls = 0;
  final List<String?> patchDeletedAt = [];

  /// When true, PATCH returns zero rows (definitive denial / missing row).
  bool denyWrites = false;

  /// Block GET reads deterministically (slow refresh).
  Completer<void>? blockGet;
  bool failGetTransient = false;

  Future<http.Response> handle(http.BaseRequest req) async {
    final r = req as http.Request;
    final url = r.url.toString();
    final path = r.url.path;

    if (offline) throw const SocketException('offline');

    if (r.method == 'GET' && path.contains('user_favorites')) {
      return http.Response('[]', 200,
          request: r, headers: {'content-type': 'application/json'});
    }

    if (r.method == 'GET' && path.contains('/notes')) {
      if (failGetTransient) throw const SocketException('offline');
      if (blockGet != null) await blockGet!.future;
      final noteIdEq = r.url.queryParameters['note_id'];
      if (noteIdEq != null && noteIdEq.startsWith('eq.')) {
        final id = noteIdEq.substring(3);
        final note = notes[id];
        if (note == null) {
          return http.Response('[]', 200,
              request: r, headers: {'content-type': 'application/json'});
        }
        return http.Response(
            jsonEncode([
              note.toInsertRow()
                ..addAll({
                  'note_id': note.noteId,
                  'user_id': note.userId,
                  'title': note.title,
                  'deleted_at': note.deletedAt?.toUtc().toIso8601String(),
                  'updated_at': note.updatedAt.toUtc().toIso8601String(),
                  'created_at': note.createdAt.toUtc().toIso8601String(),
                })
            ]),
            200,
            request: r,
            headers: {'content-type': 'application/json'});
      }
      final isTrash = url.contains('deleted_at') &&
          (url.contains('not.is') || url.contains('not%2Eis'));
      final rows = notes.values
          .where((n) => isTrash ? n.deletedAt != null : n.deletedAt == null)
          .where((n) => n.userId == _uid || url.contains(n.userId))
          .map((n) => {
                'note_id': n.noteId,
                'user_id': n.userId,
                'owner_name': n.ownerName,
                'owner_email': n.ownerEmail,
                'title': n.title,
                'content': n.content,
                'category': n.category,
                'color': n.color,
                'is_favorite': n.isFavorite,
                'live_member_ids': n.liveMemberIds,
                'live_roles': n.liveRoles,
                'shared_with_user_ids': n.sharedWithUserIds,
                'pending_shared_with_user_ids': n.pendingSharedWithUserIds,
                'attachments': n.attachments,
                'revision': n.revision,
                'deleted_at': n.deletedAt?.toUtc().toIso8601String(),
                'created_at': n.createdAt.toUtc().toIso8601String(),
                'updated_at': n.updatedAt.toUtc().toIso8601String(),
              })
          .toList();
      // Live-member fetch in watchNotes carries live_member_ids; keep empty.
      if (url.contains('live_member_ids')) {
        return http.Response('[]', 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(rows), 200,
          request: r, headers: {'content-type': 'application/json'});
    }

    if (r.method == 'PATCH' && path.contains('/notes')) {
      patchCalls++;
      if (blockPatch != null) await blockPatch!.future;
      final noteIdEq = r.url.queryParameters['note_id'] ?? '';
      final id = noteIdEq.startsWith('eq.') ? noteIdEq.substring(3) : '';
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      patchDeletedAt.add(body['deleted_at'] as String?);
      if (denyWrites || id.isEmpty || !notes.containsKey(id)) {
        return http.Response('[]', 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      final current = notes[id]!;
      final rawDeleted = body['deleted_at'];
      notes[id] = rawDeleted == null
          ? current.copyWith(clearDeletedAt: true)
          : current.copyWith(deletedAt: DateTime.parse(rawDeleted as String));
      return http.Response(
          jsonEncode([
            {'note_id': id}
          ]),
          200,
          request: r,
          headers: {'content-type': 'application/json'});
    }

    if (r.url.path.contains('/rpc/commit_note_revision')) {
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      final id = body['p_note_id']?.toString() ?? '';
      final current = notes[id];
      if (current == null) {
        return http.Response(
            jsonEncode({'committed': false, 'remote': null}), 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      final updated = current.copyWith(
        title: body['p_title']?.toString() ?? current.title,
        content: body['p_content']?.toString() ?? current.content,
        category: body['p_category']?.toString() ?? current.category,
        color: body['p_color']?.toString() ?? current.color,
        revision: current.revision + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      notes[id] = updated;
      return http.Response(
          jsonEncode({
            'committed': true,
            'note': {
              'note_id': updated.noteId,
              'user_id': updated.userId,
              'owner_name': updated.ownerName,
              'owner_email': updated.ownerEmail,
              'title': updated.title,
              'content': updated.content,
              'category': updated.category,
              'color': updated.color,
              'is_favorite': updated.isFavorite,
              'live_member_ids': updated.liveMemberIds,
              'live_roles': updated.liveRoles,
              'shared_with_user_ids': updated.sharedWithUserIds,
              'pending_shared_with_user_ids': updated.pendingSharedWithUserIds,
              'attachments': updated.attachments,
              'revision': updated.revision,
              'deleted_at': updated.deletedAt?.toUtc().toIso8601String(),
              'created_at': updated.createdAt.toUtc().toIso8601String(),
              'updated_at': updated.updatedAt.toUtc().toIso8601String(),
            }
          }),
          200,
          request: r,
          headers: {'content-type': 'application/json'});
    }

    if (r.url.path.contains('/rpc/')) {
      return http.Response('[]', 200,
          request: r, headers: {'content-type': 'application/json'});
    }
    return http.Response('[]', 200,
        request: r, headers: {'content-type': 'application/json'});
  }
}

SupabaseClient _client(_FakeNotesServer server) {
  final client = SupabaseClient('https://example.invalid', 'fake',
      httpClient: MockClient(server.handle));
  addTearDown(client.dispose);
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('online delete removes card/count promptly; Undo restores', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
      'n2': _note('n2', 'Second'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);

    // Prime the durable active projection as the Library would.
    await _store
        .saveCachedNotes(_uid, [server.notes['n1']!, server.notes['n2']!]);

    await repo.deleteNote('n1');

    final cached = await _store.loadCachedNotes(_uid);
    expect(cached.map((n) => n.noteId), isNot(contains('n1')),
        reason: 'deleted card must leave the active projection immediately');
    expect(cached, hasLength(1));
    expect(await _store.loadOutbox(_uid), isEmpty,
        reason: 'online delete must not leave a stale queued op behind');
    expect(server.notes['n1']!.deletedAt, isNotNull);
    expect(server.notes['n2']!.deletedAt, isNull);

    final active = await repo.watchNotes(_uid).first;
    expect(active.map((n) => n.noteId), contains('n2'));
    expect(active.map((n) => n.noteId), isNot(contains('n1')));
    expect(active, hasLength(1));

    final trash = await repo.watchDeletedNotes(_uid).first;
    expect(trash.map((n) => n.noteId), contains('n1'));
    expect(trash, hasLength(1));

    await repo.restoreNote('n1');

    final cachedAfterUndo = await _store.loadCachedNotes(_uid);
    expect(cachedAfterUndo.map((n) => n.noteId), contains('n1'));
    expect(server.notes['n1']!.deletedAt, isNull);

    final activeAfterUndo = await repo.watchNotes(_uid).first;
    expect(activeAfterUndo, hasLength(2));
    final trashAfterUndo = await repo.watchDeletedNotes(_uid).first;
    expect(trashAfterUndo, isEmpty);
  });

  test('offline delete then online Undo survives replay/refresh/restart',
      () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);

    server.offline = true;
    await repo.deleteNote('n1');
    expect(await _store.loadOutbox(_uid), hasLength(1));
    expect(
        _store.applyOutboxOverlay(
            await _store.loadCachedNotes(_uid), await _store.loadOutbox(_uid)),
        isEmpty);

    server.offline = false;
    await repo.restoreNote('n1');
    // The obsolete queued delete must not be able to delete again.
    await repo.flushOfflineOutbox(_uid);

    expect(server.notes['n1']!.deletedAt, isNull,
        reason: 'restored note must stay restored after outbox replay');
    expect(await _store.loadOutbox(_uid), isEmpty);

    final active = await repo.watchNotes(_uid).first;
    expect(active.map((n) => n.noteId), contains('n1'));

    // Simulate process restart: new store/repository over same prefs.
    final restartedRepo = NoteRepository(client: client);
    final restartedActive = await restartedRepo.watchNotes(_uid).first;
    expect(restartedActive.map((n) => n.noteId), contains('n1'));
    expect(server.notes['n1']!.deletedAt, isNull);
  });

  test('Undo while delete replay is in flight stays restored', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);

    server.offline = true;
    await repo.deleteNote('n1');
    server.offline = false;

    server.blockPatch = Completer<void>();
    final flushing = repo.flushOfflineOutbox(_uid);
    // Let the replay start and block inside the delete PATCH.
    await Future<void>.delayed(Duration.zero);
    final restore = repo.restoreNote('n1');
    server.blockPatch!.complete();
    await flushing;
    await restore;
    await repo.flushOfflineOutbox(_uid);

    expect(server.notes['n1']!.deletedAt, isNull);
    expect(await _store.loadOutbox(_uid), isEmpty);
    final active = await repo.watchNotes(_uid).first;
    expect(active.map((n) => n.noteId), contains('n1'));
  });

  test('delayed delete acknowledgement after restore intent keeps restore',
      () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);

    server.blockPatch = Completer<void>();
    final deleting = repo.deleteNote('n1');
    await Future<void>.delayed(Duration.zero);
    final restoring = repo.restoreNote('n1');
    server.blockPatch!.complete();
    await Future.wait([deleting, restoring]);
    await repo.flushOfflineOutbox(_uid);

    expect(server.patchDeletedAt.length, greaterThanOrEqualTo(2),
        reason: 'both intents must reach the server in order');
    expect(server.patchDeletedAt.last, isNull,
        reason: 'restore intent must win over the earlier delete');
    expect(server.notes['n1']!.deletedAt, isNull);
  });

  test('slow refresh still projects delete promptly; failed refresh keeps it',
      () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
      'n2': _note('n2', 'Second'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store
        .saveCachedNotes(_uid, [server.notes['n1']!, server.notes['n2']!]);

    server.blockGet = Completer<void>();
    final emissions = <List<NoteModel>>[];
    final sub = repo.watchNotes(_uid).listen(emissions.add);
    // Initial cached emission happens before the blocked fetch.
    await Future<void>.delayed(Duration.zero);
    await repo.deleteNote('n1');
    await Future<void>.delayed(Duration.zero);

    expect(emissions, isNotEmpty);
    expect(emissions.last.map((n) => n.noteId), isNot(contains('n1')),
        reason: 'optimistic projection must not wait for a slow refresh');
    expect(emissions.last.map((n) => n.noteId), contains('n2'));
    server.blockGet!.complete();
    await sub.cancel();

    server.failGetTransient = true;
    final fallback = await repo.watchNotes(_uid).first;
    expect(fallback.map((n) => n.noteId), isNot(contains('n1')));
  });

  test('zero-row delete is not reported as success', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
    });
    server.denyWrites = true;
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);

    await expectLater(repo.deleteNote('n1'), throwsA(anything),
        reason: 'a zero-row write must surface instead of silent success');
    expect(await _store.loadOutbox(_uid), isNotEmpty,
        reason: 'recovery data must be preserved on definitive denial');
  });

  test('rapid delete/restore/delete ends deleted; duplicate replay is safe',
      () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);

    await repo.deleteNote('n1');
    await repo.restoreNote('n1');
    await repo.deleteNote('n1');
    await repo.flushOfflineOutbox(_uid);
    await repo.flushOfflineOutbox(_uid);
    expect(server.notes['n1']!.deletedAt, isNotNull);

    await repo.restoreNote('n1');
    await repo.deleteNote('n1');
    await repo.restoreNote('n1');
    await repo.flushOfflineOutbox(_uid);
    expect(server.notes['n1']!.deletedAt, isNull);
  });

  test('unrelated edits and other notes survive delete/restore', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'First'),
      'n2': _note('n2', 'Second'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    const store = OfflineNoteStore();
    await store
        .saveCachedNotes(_uid, [server.notes['n1']!, server.notes['n2']!]);
    final base = server.notes['n2']!;
    await store.enqueue(
        _uid,
        PendingNoteOperation(
          opId: 'edit-n2',
          kind: PendingNoteOpKind.saveCollaborative,
          noteId: 'n2',
          queuedAt: DateTime.utc(2026),
          local: base.copyWith(title: 'Second edited'),
          base: base,
        ));
    final repo = NoteRepository(client: client);
    await repo.deleteNote('n1');
    // The queued edit for n2 must survive the delete of n1; after the
    // ordered replay both intents reach the server.
    expect(server.notes['n1']!.deletedAt, isNotNull);
    expect(server.notes['n2']!.title, 'Second edited');
    expect(await _store.loadOutbox(_uid), isEmpty);
  });

  test('account switching never applies one account ops to another', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'A-note', uid: _uid),
    });
    final client = _client(server);
    await _auth(client, _uid);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);
    server.offline = true;
    await NoteRepository(client: client).deleteNote('n1');
    expect(await _store.loadOutbox(_uid), hasLength(1));

    await _auth(client, _uidB);
    await NoteRepository(client: client).flushOfflineOutbox(_uid);
    // Flushing user-A queue while signed in as user-B must be a no-op.
    expect(await _store.loadOutbox(_uid), hasLength(1));
    expect(server.notes['n1']!.deletedAt, isNull);
  });

  test('failed restore preserves recovery data and surfaces', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'Untitled'),
    });
    server.denyWrites = true;
    final client = _client(server);
    await _auth(client, _uid);
    final repo = NoteRepository(client: client);
    await _store.saveCachedNotes(_uid, [server.notes['n1']!]);

    await expectLater(repo.restoreNote('missing-or-denied'), throwsA(anything));
    expect(await _store.loadOutbox(_uid), isNotEmpty,
        reason: 'failed restore must preserve recovery data');
  });

  test('same-note queued edit is applied before the delete', () async {
    final server = _FakeNotesServer({
      'n1': _note('n1', 'First'),
    });
    final client = _client(server);
    await _auth(client, _uid);
    const store = OfflineNoteStore();
    final base = server.notes['n1']!;
    await store.saveCachedNotes(_uid, [base]);
    await store.enqueue(
        _uid,
        PendingNoteOperation(
          opId: 'edit-n1',
          kind: PendingNoteOpKind.saveCollaborative,
          noteId: 'n1',
          queuedAt: DateTime.utc(2026),
          local: base.copyWith(title: 'First edited'),
          base: base,
        ));
    await NoteRepository(client: client).deleteNote('n1');
    expect(server.notes['n1']!.title, 'First edited');
    expect(server.notes['n1']!.deletedAt, isNotNull);
    expect(await _store.loadOutbox(_uid), isEmpty);
  });
}
