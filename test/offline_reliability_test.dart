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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const uid = '11111111-1111-4111-8111-111111111111';
  const store = OfflineNoteStore();
  final base = NoteModel.empty(uid).copyWith(noteId: 'n1', title: 'base');
  PendingNoteOperation op(String id, String noteId) => PendingNoteOperation(
        opId: id,
        kind: PendingNoteOpKind.saveCollaborative,
        noteId: noteId,
        queuedAt: DateTime.utc(2026),
        local: base.copyWith(noteId: noteId, title: 'local'),
        base: base.copyWith(noteId: noteId),
      );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> authenticate(SupabaseClient client) =>
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
          'created_at': '2026-01-01T00:00:00Z'
        },
      }));

  test('open note shows its queued draft while offline', () async {
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient:
            MockClient((r) async => throw const SocketException('offline')));
    addTearDown(client.dispose);
    await authenticate(client);
    await store.saveCachedNotes(uid, [base]);
    await store.enqueue(uid, op('op1', 'n1'));
    expect((await NoteRepository(client: client).watchNote('n1').first)!.title,
        'local');
  });

  test('library includes notes beyond the server page cap', () async {
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient: MockClient((r) async {
      final offset = int.tryParse(r.url.queryParameters['offset'] ?? '') ?? 0;
      final owned = r.url.queryParameters['user_id'] != null;
      final rows = owned && offset < 1001
          ? List.generate(offset == 0 ? 1000 : 1,
              (i) => base.copyWith(noteId: 'n${offset + i}').toInsertRow())
          : [];
      return http.Response(jsonEncode(rows), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    await authenticate(client);
    final notes = await NoteRepository(client: client).watchNotes(uid).first;
    expect(notes, hasLength(1001));
  });

  test('revoked note is hidden online while its draft remains queued',
      () async {
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient: MockClient((r) async {
      if (r.url.path.contains('/rpc/')) {
        return http.Response(
            jsonEncode({'message': 'denied', 'code': '42501'}), 403,
            request: r, headers: {'content-type': 'application/json'});
      }
      return http.Response('[]', 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    await authenticate(client);
    await store.enqueue(uid, op('op1', 'n1'));
    final notes =
        await NoteRepository(client: client).watchNotes(uid).skip(1).first;
    expect(notes, isEmpty);
    expect(await store.loadOutbox(uid), hasLength(1));
  });

  test('rejected offline edit must retain recovery data', () async {
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({'message': 'permission denied', 'code': '42501'}), 403,
            request: r, headers: {'content-type': 'application/json'})));
    await store.enqueue(uid, op('op1', 'n1'));
    await authenticate(client);
    await expectLater(NoteRepository(client: client).flushOfflineOutbox(uid),
        throwsA(isA<OfflineSyncException>()));
    expect(await store.loadOutbox(uid), isNotEmpty,
        reason: 'Do not discard the only offline draft after revocation');
    await client.dispose();
  });

  test('failed recovery copy must retain original offline draft', () async {
    final remote = base.copyWith(title: 'remote', revision: 1).toInsertRow();
    remote['revision'] = 1;
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient: MockClient((r) async {
      if (r.url.path.contains('/rpc/commit_note_revision')) {
        return http.Response(
            jsonEncode({'committed': false, 'remote': remote}), 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      return http.Response(
          jsonEncode({'message': 'copy insert failed', 'code': '23514'}), 400,
          request: r, headers: {'content-type': 'application/json'});
    }));
    await store.enqueue(uid, op('op1', 'n1'));
    await authenticate(client);
    await expectLater(NoteRepository(client: client).flushOfflineOutbox(uid),
        throwsA(isA<OfflineSyncException>()));
    expect(await store.loadOutbox(uid), isNotEmpty,
        reason: 'Retain outbox until the recovery copy succeeds');
    await client.dispose();
  });

  test('concurrent enqueues must preserve edits to both notes', () async {
    await Future.wait([
      store.enqueue(uid, op('op1', 'n1')),
      store.enqueue(uid, op('op2', 'n2')),
    ]);
    expect((await store.loadOutbox(uid)).map((o) => o.noteId).toSet(),
        {'n1', 'n2'});
  });

  test('an edit arriving during create replay survives acknowledgement',
      () async {
    final initial = PendingNoteOperation(
        opId: 'create1',
        kind: PendingNoteOpKind.create,
        noteId: 'n1',
        queuedAt: DateTime.utc(2026),
        local: base);
    await store.enqueue(uid, initial);
    await store.enqueue(uid, op('later-edit', 'n1'));
    await store.removeOp(uid, 'create1');
    final remaining = await store.loadOutbox(uid);
    expect(remaining, hasLength(1));
    expect(remaining.single.local!.title, 'local');
    expect(remaining.single.base!.title, 'base');
  });

  test('overlapping flush requests commit a queued draft once', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var commits = 0;
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient: MockClient((r) async {
      commits++;
      if (!entered.isCompleted) entered.complete();
      await release.future;
      return http.Response(
          jsonEncode({
            'committed': true,
            'note': base.copyWith(title: 'local', revision: 1).toInsertRow()
          }),
          200,
          request: r,
          headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    await authenticate(client);
    await store.enqueue(uid, op('op1', 'n1'));
    final first = NoteRepository(client: client).flushOfflineOutbox(uid);
    await entered.future;
    final second = NoteRepository(client: client).flushOfflineOutbox(uid);
    release.complete();
    try {
      await Future.wait([first, second]);
    } on OfflineSyncException catch (error) {
      fail("Offline replay failed: ${error.cause}");
    }
    expect(commits, 1);
    expect(await store.loadOutbox(uid), isEmpty);
  });
}
