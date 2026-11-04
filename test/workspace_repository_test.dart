import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noted/models/workspace_model.dart';
import 'package:noted/repositories/workspace_repository.dart';
import 'package:noted/services/workspace_cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '11111111-1111-4111-8111-111111111111';
const _otherUid = '22222222-2222-4222-8222-222222222222';

Future<void> _authenticate(SupabaseClient client, [String uid = _uid]) =>
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

http.Response _json(Object body, http.BaseRequest request,
        {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

SupabaseClient _client(http.Client transport) => SupabaseClient(
      'https://example.invalid',
      'fake',
      httpClient: transport,
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Library reads all workspace mappings in paginated set requests',
      () async {
    var requests = 0;
    final client = _client(MockClient((request) async {
      requests++;
      final path = request.url.path;
      if (path.contains('personal_workspaces')) {
        return _json([
          {'id': 'alpha', 'name': 'Alpha'},
          {'id': 'beta', 'name': 'Beta'},
        ], request);
      }
      if (path.contains('personal_workspace_notes')) {
        final offset =
            int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
        if (offset == 0) {
          return _json(
            List.generate(
              1000,
              (index) => {
                'note_id': 'note-$index',
                'workspace_id': index.isEven ? 'alpha' : 'beta',
              },
            ),
            request,
          );
        }
        return _json([
          {'note_id': 'note-1000', 'workspace_id': 'alpha'},
        ], request);
      }
      return _json([], request);
    }));
    addTearDown(client.dispose);
    await _authenticate(client);

    final snapshot =
        await WorkspaceRepository(client: client).loadLibrary(_uid);

    expect(snapshot.workspaces.map((workspace) => workspace.name),
        ['Alpha', 'Beta']);
    expect(snapshot.assignments, hasLength(1001));
    expect(requests, 3,
        reason: 'two assignment pages plus one workspace page, not per note');
  });

  test('offline restart uses cached assignments and marks them as saved data',
      () async {
    const cache = WorkspaceCacheStore();
    await cache.saveSnapshot(
      _uid,
      WorkspaceLibrarySnapshot(
        workspaces: const [
          PersonalWorkspace(id: 'alpha', name: 'Alpha'),
        ],
        assignments: const {'project': 'alpha'},
        loadedAt: DateTime(2026, 11, 5),
      ),
    );
    final client = _client(
      MockClient((request) async => throw const SocketException('offline')),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final snapshots = await WorkspaceRepository(client: client)
        .watchLibrary(_uid)
        .take(2)
        .toList();

    expect(snapshots.first.fromCache, isTrue);
    expect(snapshots.first.hasAssignmentData, isTrue);
    expect(snapshots.first.workspaceIdFor('project'), 'alpha');
    expect(snapshots.first.errorMessage, isNull);
    expect(snapshots.last.fromCache, isTrue);
    expect(snapshots.last.errorMessage, isNotNull);
  });

  test('assignment read failure with no cache is explicitly unavailable',
      () async {
    final client = _client(MockClient((request) async {
      if (request.url.path.contains('personal_workspaces')) {
        return _json([
          {'id': 'alpha', 'name': 'Alpha'},
        ], request);
      }
      return _json(
        {'message': 'workspace assignment read failed', 'code': '42501'},
        request,
        status: 403,
      );
    }));
    addTearDown(client.dispose);
    await _authenticate(client);

    final snapshot =
        await WorkspaceRepository(client: client).watchLibrary(_uid).first;

    expect(snapshot.hasAssignmentData, isFalse);
    expect(snapshot.workspaces, isEmpty);
    expect(snapshot.errorMessage, isNotNull);
  });

  test('workspace snapshots and selections cannot cross accounts', () async {
    const cache = WorkspaceCacheStore();
    await cache.saveSnapshot(
      _uid,
      WorkspaceLibrarySnapshot(
        workspaces: const [
          PersonalWorkspace(id: 'alpha', name: 'Alpha'),
        ],
        assignments: const {'shared-note': 'alpha'},
        loadedAt: DateTime(2026, 11, 5),
      ),
    );
    await cache.saveSnapshot(
      _otherUid,
      WorkspaceLibrarySnapshot(
        workspaces: const [
          PersonalWorkspace(id: 'beta', name: 'Beta'),
        ],
        assignments: const {'shared-note': 'beta'},
        loadedAt: DateTime(2026, 11, 5),
      ),
    );
    await cache.saveSelection(_uid, WorkspaceSelection.named('alpha'));
    await cache.saveSelection(
      _otherUid,
      WorkspaceSelection.named('beta'),
    );

    final first = await cache.loadSnapshot(_uid);
    final second = await cache.loadSnapshot(_otherUid);

    expect(first!.workspaceIdFor('shared-note'), 'alpha');
    expect(second!.workspaceIdFor('shared-note'), 'beta');
    expect(await cache.loadSelection(_uid), WorkspaceSelection.named('alpha'));
    expect(
        await cache.loadSelection(_otherUid), WorkspaceSelection.named('beta'));
  });

  test('active account mismatch is rejected before workspace data is returned',
      () async {
    final client = _client(MockClient((request) async => _json([], request)));
    addTearDown(client.dispose);
    await _authenticate(client, _uid);

    await expectLater(
      WorkspaceRepository(client: client).loadLibrary(_otherUid),
      throwsStateError,
    );
  });
}
