import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/auth_repository.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/services/analytics_service.dart';
import 'package:noted/services/media_url_resolver.dart';
import 'package:noted/services/offline_note_store.dart';
import 'package:noted/utils/document_codec.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthRepository extends Fake implements AuthRepository {
  final uidController = StreamController<String?>.broadcast();
  final recoveryController = StreamController<bool>.broadcast();
  UserModel? activeUser;
  String? completedPassword;
  bool signedOut = false;

  @override
  Stream<String?> authUidChanges() => uidController.stream;

  @override
  Stream<bool> passwordRecoveryChanges() => recoveryController.stream;

  @override
  Future<UserModel?> loadCurrentUser() async => activeUser;

  @override
  Future<void> completePasswordRecovery(String newPassword) async {
    completedPassword = newPassword;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    MediaUrlResolver.clearCache();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MediaUrlResolver.setSignerForTesting(null);
    MediaUrlResolver.clearCache();
    AnalyticsService.instance.resetForTesting();
  });

  group('PostgreSQL snake_case & rich-text model fidelity', () {
    test('NoteModel maps PostgreSQL rows and preserves Quill Delta + Markdown verbatim', () {
      const quillJson =
          '{"notedDocument":1,"ops":[{"insert":"Sprint Review"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Ship migration"},{"insert":"\\n","attributes":{"list":"checked"}}]}';

      final pgRow = <String, dynamic>{
        'note_id': 'note-deep-link-42',
        'user_id': '8f14e45f-ceea-567a-a8f1-4e45fceea567',
        'owner_name': 'Alya',
        'owner_email': 'alya@example.com',
        'title': 'Sprint Review',
        'content': quillJson,
        'category': 'Projects',
        'color': 'mint',
        'is_favorite': true,
        'live_member_ids': ['11111111-2222-4333-8444-555555555555'],
        'live_roles': {
          '11111111-2222-4333-8444-555555555555': 'edit',
        },
        'shared_with_user_ids': ['22222222-3333-4444-8555-666666666666'],
        'pending_shared_with_user_ids': ['33333333-4444-4555-8666-777777777777'],
        'source_owner_id': '99999999-8888-4777-8666-555555555555',
        'source_note_id': 'source-note-9',
        'attachments': [
          {
            'type': 'image',
            'path': 'users/8f14e45f-ceea-567a-a8f1-4e45fceea567/notes/note-deep-link-42/img_1.jpg',
            'url': 'noted-media://note-media/users/8f14e45f-ceea-567a-a8f1-4e45fceea567/notes/note-deep-link-42/img_1.jpg',
          }
        ],
        'revision': 7,
        'created_at': '2026-10-20T09:00:00.000Z',
        'updated_at': '2026-10-26T12:30:00.000Z',
        'deleted_at': null,
      };

      final model = NoteModel.fromMap(pgRow);
      expect(model.noteId, 'note-deep-link-42');
      expect(model.userId, '8f14e45f-ceea-567a-a8f1-4e45fceea567');
      expect(model.content, quillJson);
      expect(DocumentCodec.toPlainText(model.content), contains('Sprint Review'));
      expect(model.revision, 7);
      expect(model.canEdit('11111111-2222-4333-8444-555555555555'), isTrue);
      expect(model.sourceOwnerId, '99999999-8888-4777-8666-555555555555');
      expect(model.sourceNoteId, 'source-note-9');

      expect(model.toMap()['revision'], 7);

      final insertRow = model.toInsertRow();
      expect(insertRow['note_id'], 'note-deep-link-42');
      expect(insertRow['content'], quillJson);
      // Client INSERT rows intentionally initialize at revision 0 per RLS policy
      expect(insertRow['revision'], 0);

      const legacyMarkdown = '**Architecture** notes\n- [x] Verify RLS';
      final legacyModel = NoteModel.fromMap({
        ...pgRow,
        'content': legacyMarkdown,
      });
      expect(legacyModel.content, legacyMarkdown);
    });

    test('UserModel and ConnectionModel map PostgreSQL snake_case rows', () {
      final user = UserModel.fromMap({
        'id': 'aaaa1111-bbbb-4ccc-8ddd-eeeeffff0000',
        'name': 'Jordan Lee',
        'email': 'jordan@example.com',
        'field_of_study': 'Product Design',
        'avatar_path': 'users/aaaa1111-bbbb-4ccc-8ddd-eeeeffff0000/avatar.jpg',
        'created_at': '2026-08-01T00:00:00.000Z',
      });
      expect(user.uid, 'aaaa1111-bbbb-4ccc-8ddd-eeeeffff0000');
      expect(user.fieldOfStudy, 'Product Design');
      expect(
        user.avatarUrl,
        'noted-media://avatars/users/aaaa1111-bbbb-4ccc-8ddd-eeeeffff0000/avatar.jpg',
      );
      expect(user.toProfileRow()['field_of_study'], 'Product Design');

      final conn = ConnectionModel.fromMap({
        'connection_id': 'conn-1',
        'from_user_id': user.uid,
        'from_name': user.name,
        'from_email': user.email,
        'to_user_id': 'bbbb2222-cccc-4ddd-8eee-ffff00001111',
        'to_name': 'Taylor',
        'to_email': 'taylor@example.com',
        'status': 'accepted',
        'created_at': '2026-08-02T00:00:00.000Z',
        'updated_at': '2026-08-03T00:00:00.000Z',
      });
      expect(conn.status, ConnectionStatus.accepted);
      expect(conn.otherName(user.uid), 'Taylor');
      expect(conn.toMap()['fromUserId'], user.uid);
    });
  });

  group('Collaborative OT merge & favorite ownership isolation', () {
    test('rebases concurrent Quill edits, unions attachments, and isolates collaborator favorite', () {
      String encodeOps(List<Map<String, dynamic>> ops) =>
          jsonEncode({'notedDocument': 1, 'ops': ops});

      final now = DateTime.utc(2026, 10, 26, 12);
      final base = NoteModel.empty(
        'owner-uuid',
        ownerName: 'Owner',
        ownerEmail: 'owner@example.com',
      ).copyWith(
        noteId: 'live-note-1',
        title: 'Roadmap',
        content: encodeOps([
          {'insert': 'Hello world\n'},
        ]),
        category: 'Projects',
        isFavorite: true,
        attachments: const [
          {'type': 'image', 'path': 'users/owner-uuid/notes/live-note-1/base.jpg'},
        ],
        revision: 3,
        createdAt: now,
        updatedAt: now,
      );

      final localEditorDraft = base.copyWith(
        content: encodeOps([
          {'insert': 'Hello brave world\n'},
        ]),
        // Collaborator toggled personal favorite locally; must not clobber owner's note.isFavorite
        isFavorite: false,
        attachments: const [
          {'type': 'image', 'path': 'users/owner-uuid/notes/live-note-1/base.jpg'},
          {'type': 'audio', 'path': 'users/editor-uuid/notes/live-note-1/memo.m4a'},
        ],
      );

      final remoteCommitted = base.copyWith(
        content: encodeOps([
          {'insert': 'Hello world!\n'},
        ]),
        isFavorite: true,
        attachments: const [
          {'type': 'image', 'path': 'users/owner-uuid/notes/live-note-1/base.jpg'},
          {'type': 'drawing', 'path': 'users/owner-uuid/notes/live-note-1/sketch.png'},
        ],
        revision: 4,
      );

      final merged = NoteRepository.mergeCollaborativeDraft(
        local: localEditorDraft,
        base: base,
        remote: remoteCommitted,
        isOwner: false,
      );

      expect(DocumentCodec.toPlainText(merged.content).trim(), 'Hello brave world!');
      expect(merged.isFavorite, isTrue);
      expect(merged.revision, 5);
      expect(merged.attachments.length, 3);
    });

    test('throws NoteConflictException on competing title edits', () {
      final now = DateTime.utc(2026, 10, 26);
      final base = NoteModel.empty('owner-uuid').copyWith(
        noteId: 'n1',
        title: 'Original',
        createdAt: now,
        updatedAt: now,
      );
      final local = base.copyWith(title: 'Draft Title A');
      final remote = base.copyWith(title: 'Remote Title B', revision: 2);

      expect(
        () => NoteRepository.mergeCollaborativeDraft(
          local: local,
          base: base,
          remote: remote,
          isOwner: true,
        ),
        throwsA(isA<NoteConflictException>()),
      );
    });
  });

  group('OfflineNoteStore per-account isolation & outbox coalescing', () {
    test('isolates caches per user and coalesces consecutive offline edits preserving earliest base', () async {
      const store = OfflineNoteStore();
      final t0 = DateTime.utc(2026, 10, 26, 10);

      final serverNote = NoteModel.empty('user-a').copyWith(
        noteId: 'n-1',
        title: 'Initial',
        content: 'Line 1',
        revision: 2,
        createdAt: t0,
        updatedAt: t0,
      );
      await store.saveCachedNotes('user-a', [serverNote]);
      await store.saveCachedNotes('user-b', [
        NoteModel.empty('user-b').copyWith(noteId: 'n-b', title: 'User B Private'),
      ]);

      final edit1 = serverNote.copyWith(content: 'Line 1\nLine 2');
      final redated = DateTime.utc(2026, 10, 12, 9);
      final edit2 = edit1.copyWith(
        content: 'Line 1\nLine 2\nLine 3',
        createdAt: redated,
      );

      await store.enqueue(
        'user-a',
        PendingNoteOperation(
          opId: 'op-1',
          kind: PendingNoteOpKind.saveCollaborative,
          noteId: 'n-1',
          queuedAt: t0.add(const Duration(seconds: 5)),
          local: edit1,
          base: serverNote,
        ),
      );
      await store.enqueue(
        'user-a',
        PendingNoteOperation(
          opId: 'op-2',
          kind: PendingNoteOpKind.saveCollaborative,
          noteId: 'n-1',
          queuedAt: t0.add(const Duration(seconds: 10)),
          local: edit2,
          // Intermediate base must NOT overwrite earliest server base!
          base: edit1,
        ),
      );

      final outboxA = await store.loadOutbox('user-a');
      expect(outboxA, hasLength(1));
      expect(outboxA.single.local!.content, 'Line 1\nLine 2\nLine 3');
      expect(outboxA.single.base!.content, 'Line 1');
      expect(outboxA.single.base!.revision, 2);

      final overlaidA = store.applyOutboxOverlay(
        await store.loadCachedNotes('user-a'),
        outboxA,
      );
      expect(overlaidA.single.content, 'Line 1\nLine 2\nLine 3');
      expect(overlaidA.single.createdAt, redated);

      // Clearing user-a leaves user-b untouched
      await store.clearUser('user-a');
      expect(await store.loadCachedNotes('user-a'), isEmpty);
      expect(await store.loadOutbox('user-a'), isEmpty);
      expect((await store.loadCachedNotes('user-b')).single.title, 'User B Private');
    });
  });

  group('MediaUrlResolver private bucket signing & sign-out invalidation', () {
    test('signs private noted-media URIs, caches TTL, and clears on sign-out', () async {
      var signCalls = 0;
      MediaUrlResolver.setSignerForTesting((bucket, path) async {
        signCalls++;
        return 'https://example.supabase.co/storage/v1/object/sign/$bucket/$path?token=t$signCalls';
      });

      const privateRef =
          'noted-media://note-media/users/u1/notes/n1/img_100.jpg';
      expect(MediaUrlResolver.peekResolved(privateRef), isNull);

      final first = await MediaUrlResolver.resolve(privateRef);
      expect(first, contains('token=t1'));
      expect(signCalls, 1);

      // Cached synchronously and asynchronously
      expect(MediaUrlResolver.peekResolved(privateRef), first);
      final second = await MediaUrlResolver.resolve(privateRef);
      expect(second, first);
      expect(signCalls, 1);

      // External https URL bypasses signer
      expect(
        MediaUrlResolver.peekResolved('https://images.example.com/pic.png'),
        'https://images.example.com/pic.png',
      );

      // Sign-out / account switch clears cached signed URLs immediately
      MediaUrlResolver.clearCache();
      expect(MediaUrlResolver.peekResolved(privateRef), isNull);
      final afterClear = await MediaUrlResolver.resolve(privateRef);
      expect(afterClear, contains('token=t2'));
      expect(signCalls, 2);
    });
  });

  group('Consent-gated Analytics & Password Recovery', () {
    test('AnalyticsService drops events by default and clears buffer when disabled', () async {
      final analytics = AnalyticsService.instance;
      expect(analytics.isEnabled, isFalse);

      await analytics.logEvent('note_opened');
      expect(analytics.recordedEvents, isEmpty);

      await analytics.setCollectionEnabled(true);
      await analytics.logEvent('note_opened', {'view': 'grid'});
      expect(analytics.recordedEvents, hasLength(1));

      await analytics.setCollectionEnabled(false);
      expect(analytics.isEnabled, isFalse);
      expect(analytics.recordedEvents, isEmpty);
    });

    test('AuthViewModel handles Supabase password recovery deep link lifecycle', () async {
      final repo = _FakeAuthRepository();
      final vm = AuthViewModel(repo);
      await vm.initialize();

      repo.activeUser = UserModel(
        uid: 'u-1',
        name: 'Alya',
        email: 'alya@example.com',
        createdAt: DateTime.utc(2026),
      );
      repo.uidController.add('u-1');
      repo.recoveryController.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(vm.isAuthenticated, isTrue);
      expect(vm.isPasswordRecovery, isTrue);

      final ok = await vm.completePasswordRecovery('StrongPass!9');
      expect(ok, isTrue);
      expect(repo.completedPassword, 'StrongPass!9');
      expect(vm.isPasswordRecovery, isFalse);

      vm.dispose();
      await repo.uidController.close();
      await repo.recoveryController.close();
    });
  });
}
