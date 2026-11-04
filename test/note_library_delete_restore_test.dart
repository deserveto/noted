import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/services/offline_note_store.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/notes_page.dart';
import 'package:noted/utils/app_theme.dart';

const _uid = '11111111-1111-4111-8111-111111111111';

// This regression exercises repository-driven local refresh, not server push.
// Prevent real WebSocket connections to the mock HTTP server in fake time.
class _HttpOnlyClient extends SupabaseClient {
  _HttpOnlyClient(http.Client transport)
      : super('https://example.invalid', 'fake',
            httpClient: transport,
            authOptions: const AuthClientOptions(autoRefreshToken: false));

  @override
  RealtimeChannel channel(String name,
          {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) =>
      _SilentChannel(name, realtime);
}

class _SilentChannel extends RealtimeChannel {
  _SilentChannel(super.topic, super.socket);

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus, Object?)? callback,
    Duration? timeout,
  ]) =>
      this;

  @override
  Future<String> unsubscribe([Duration? timeout]) async => 'ok';
}

NoteModel _note(String id, String title) =>
    NoteModel.empty(_uid).copyWith(noteId: id, title: title);

Future<void> _auth(SupabaseClient client) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'test-token',
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': _uid,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

class _FakeServer {
  _FakeServer(this.notes);
  final Map<String, NoteModel> notes;

  Future<http.Response> handle(http.BaseRequest req) async {
    final r = req as http.Request;
    final path = r.url.path;
    if (r.method == 'GET' && path.contains('user_favorites')) {
      return http.Response('[]', 200,
          request: r, headers: {'content-type': 'application/json'});
    }
    if (r.method == 'GET' && path.contains('/notes')) {
      final url = r.url.toString();
      if (url.contains('live_member_ids') || url.contains('pending_shared')) {
        return http.Response('[]', 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      final isTrash = url.contains('deleted_at') && url.contains('not.is');
      Map<String, dynamic> row(NoteModel n) => {
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
          };
      final rows = notes.values
          .where((n) => isTrash ? n.deletedAt != null : n.deletedAt == null)
          .map(row)
          .toList();
      return http.Response(jsonEncode(rows), 200,
          request: r, headers: {'content-type': 'application/json'});
    }
    if (r.method == 'PATCH' && path.contains('/notes')) {
      final eq = r.url.queryParameters['note_id'] ?? '';
      final id = eq.startsWith('eq.') ? eq.substring(3) : '';
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      if (id.isEmpty || !notes.containsKey(id)) {
        return http.Response('[]', 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      final current = notes[id]!;
      notes[id] = body['deleted_at'] == null
          ? current.copyWith(clearDeletedAt: true)
          : current.copyWith(
              deletedAt: DateTime.parse(body['deleted_at'] as String));
      return http.Response(
          jsonEncode([
            {'note_id': id}
          ]),
          200,
          request: r,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('[]', 200,
        request: r, headers: {'content-type': 'application/json'});
  }
}

class _Settings extends SettingsViewModel {
  _Settings() : super(SettingsRepository());
  @override
  SettingsModel get settings => const SettingsModel(reduceMotion: true);
}

Widget _harness(NoteViewModel vm) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteViewModel>.value(value: vm),
        ChangeNotifierProvider<SettingsViewModel>(create: (_) => _Settings()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: NotesPage()),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final f in [
      ('DM Sans', 'assets/fonts/DMSans.ttf'),
      ('Newsreader', 'assets/fonts/Newsreader-Italic.ttf'),
    ]) {
      await (FontLoader(f.$1)..addFont(rootBundle.load(f.$2))).load();
    }
  });

  // Render a bounded number of frames without advancing repository poll timers.
  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Library delete removes the card and count; Undo restores it',
      (tester) async {
    final server = _FakeServer({
      'n1': _note('n1', 'Untitled'),
      'n2': _note('n2', 'Second'),
      'n3': _note('n3', 'Third'),
      'n4': _note('n4', 'Fourth'),
    });
    // The SDK starts a JSON worker isolate. Create and dispose it in real
    // async time so its platform messages are not trapped by the fake clock.
    final client = (await tester
        .runAsync(() async => _HttpOnlyClient(MockClient(server.handle))))!;
    await _auth(client);
    final repo = NoteRepository(client: client);
    final vm = NoteViewModel(repo)..bindUser(_uid);
    try {
      await tester.pumpWidget(_harness(vm));
      await pumpLibrary(tester);

      expect(find.text('Untitled'), findsOneWidget);
      expect(find.text('4 notes · 0 favorites'), findsOneWidget);
      expect(find.text('4 notes'), findsOneWidget);

      await vm.deleteNote('n1');
      await pumpLibrary(tester);

      expect(find.text('Untitled'), findsNothing,
          reason: 'deleted card must disappear from the Library');
      expect(find.text('3 notes · 0 favorites'), findsOneWidget,
          reason: 'visible note count must update on delete');
      expect(find.text('3 notes'), findsOneWidget);

      const store = OfflineNoteStore();
      expect((await store.loadCachedNotes(_uid)).map((n) => n.noteId),
          isNot(contains('n1')));
      expect(server.notes['n1']!.deletedAt, isNotNull);
      final trash =
          (await tester.runAsync(() => repo.watchDeletedNotes(_uid).first))!;
      expect(trash.map((n) => n.noteId), contains('n1'));
      expect(trash, hasLength(1));

      await vm.restoreNote('n1');
      await pumpLibrary(tester);

      expect(find.text('Untitled'), findsOneWidget,
          reason: 'Undo must restore that same note card');
      expect(find.text('4 notes · 0 favorites'), findsOneWidget);
      expect(find.text('4 notes'), findsOneWidget);
      expect(server.notes['n1']!.deletedAt, isNull);
      final trashAfter =
          await tester.runAsync(() => repo.watchDeletedNotes(_uid).first);
      expect(trashAfter, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      // Dispose before the binding checks pending timers, not in addTearDown.
      await tester.runAsync(client.dispose);
    }
  });
}
