import 'dart:async';
import 'dart:convert';
import 'dart:io';
// Use the SDK's injectable JSON worker synchronously in fake widget time.
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/services/offline_note_store.dart';
import 'package:noted/services/supabase_service.dart';
import 'package:noted/services/media_url_resolver.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/views/add_edit_note_page.dart';
import 'package:noted/views/notes_page.dart';
import 'package:noted/views/shared_note_preview_page.dart';
import 'package:noted/widgets/activity_sheet.dart';
import 'package:noted/widgets/noted_ui.dart';
import 'package:noted/utils/app_theme.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'library_calendar_layout_test.dart' show LayoutSettings;
import 'package:noted/models/settings_model.dart';

const recipient = '11111111-1111-4111-8111-111111111111';
const stranger = '22222222-2222-4222-8222-222222222222';
final invitation = NoteModel.empty('sender', ownerName: 'QA sender').copyWith(
  noteId: 'pending',
  title: 'Shared fixture',
  content:
      '{"notedDocument":1,"ops":[{"insert":"Full shared text","attributes":{"bold":true}},{"insert":"\\n"}]}',
  pendingSharedWithUserIds: [recipient],
);

class _Auth extends ChangeNotifier implements AuthViewModel {
  String uid = recipient;
  @override
  UserModel get user => UserModel(
      uid: uid,
      name: 'QA recipient',
      email: 'qa@example.com',
      createdAt: DateTime(2026));
  void switchUser(String value) {
    uid = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InlineJson extends YAJsonIsolate {
  @override
  Future<dynamic> decode(String json) async => jsonDecode(json);
  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
}

class _HttpOnlyClient extends SupabaseClient {
  _HttpOnlyClient(http.Client transport)
      : super('https://example.invalid', 'fake',
            httpClient: transport,
            isolate: _InlineJson(),
            postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
            authOptions: const AuthClientOptions(autoRefreshToken: false));
  @override
  RealtimeChannel channel(String name,
          {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) =>
      _SilentChannel(name, realtime);
}

class _SilentChannel extends RealtimeChannel {
  _SilentChannel(super.topic, super.socket);
  @override
  RealtimeChannel subscribe(
          [void Function(RealtimeSubscribeStatus, Object?)? callback,
          Duration? timeout]) =>
      this;
  @override
  Future<String> unsubscribe([Duration? timeout]) async => 'ok';
}

Future<void> _session(SupabaseClient client, [String uid = recipient]) =>
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

// HTTP is the external boundary; the real repository, VM, navigation and Quill run.
class _Server {
  NoteModel? source = invitation;
  final copies = <NoteModel>[];
  final writes = <String>[];
  int reads = 0;
  bool offline = false, failAction = false;
  Completer<void>? readGate, actionGate;
  http.Response reply(http.BaseRequest r, Object? data, [int status = 200]) =>
      http.Response(jsonEncode(data), status,
          request: r, headers: {'content-type': 'application/json'});
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    if (r.method == 'GET') {
      if (path.endsWith('/user_favorites')) return reply(r, []);
      if (path.endsWith('/personal_workspaces') ||
          path.endsWith('/personal_workspace_notes')) {
        return reply(r, []);
      }
      if (path.endsWith('/notifications')) {
        return reply(r, [
          {
            'id': 'activity',
            'title': 'QA sent a copy',
            'note_id': 'pending',
            'read': true,
            'created_at': '2026-11-04T00:00:00Z'
          }
        ]);
      }
      if (path.endsWith('/notes')) {
        if (r.url.queryParameters.containsKey('note_id')) {
          reads++;
          final result = source;
          await readGate?.future;
          if (offline) throw const SocketException('offline');
          return reply(r, result == null ? [] : [_row(result)]);
        }
        if (r.url.queryParameters.containsKey('pending_shared_with_user_ids')) {
          return reply(
              r,
              source?.pendingSharedWithUserIds.contains(recipient) == true &&
                      source?.deletedAt == null
                  ? [_row(source!)]
                  : []);
        }
        if (r.url.queryParameters.containsKey('live_member_ids')) {
          return reply(r, []);
        }
        return reply(r, copies.map(_row).toList());
      }
    }
    if (path.contains('/auth/')) return reply(r, {});
    writes.add(path);
    await actionGate?.future;
    if (failAction) return reply(r, {'message': 'Try again'}, 500);
    if (path.endsWith('/note-sharing')) {
      if (copies.isEmpty) {
        copies.add(invitation.copyWith(
            noteId: 'copy',
            userId: recipient,
            pendingSharedWithUserIds: [],
            sourceNoteId: 'pending',
            sourceOwnerId: 'sender'));
      }
      source = source?.copyWith(pendingSharedWithUserIds: []);
      return reply(r, {'noteId': 'copy'});
    }
    if (path.endsWith('/decline_note_share')) {
      source = source?.copyWith(pendingSharedWithUserIds: []);
      return reply(r, null);
    }
    throw StateError('Unexpected write: ${r.method} $path');
  }

  Map<String, dynamic> _row(NoteModel n) => {
        ...n.toInsertRow(),
        'pending_shared_with_user_ids': n.pendingSharedWithUserIds,
        'live_member_ids': n.liveMemberIds,
        'live_roles': n.liveRoles,
        'deleted_at': n.deletedAt?.toIso8601String(),
        'revision': n.revision,
        'created_at': n.createdAt.toIso8601String(),
        'updated_at': n.updatedAt.toIso8601String(),
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  late _HttpOnlyClient client;
  late NoteRepository repo;
  late NoteViewModel vm;
  late _Auth auth;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    client = _HttpOnlyClient(MockClient(server.handle));
    await _session(client);
    SupabaseService.setTestClient(client);
    repo = NoteRepository(client: client);
    vm = NoteViewModel(repo);
    auth = _Auth();
  });
  tearDown(() async {
    vm.dispose();
    auth.dispose();
    SupabaseService.setTestClient(null);
  });

  Widget app({bool dark = false, bool activity = false}) {
    vm.bindUser(recipient);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsViewModel>(
            create: (_) =>
                LayoutSettings(const SettingsModel(reduceMotion: true))),
        ChangeNotifierProvider<AuthViewModel>.value(value: auth),
        ChangeNotifierProvider<NoteViewModel>.value(value: vm)
      ],
      child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          localizationsDelegates:
              quill.FlutterQuillLocalizations.localizationsDelegates,
          home: Scaffold(
              body: activity
                  ? Builder(
                      builder: (context) => TextButton(
                          onPressed: () => notedSheet<void>(context,
                              label: 'Activity',
                              tall: true,
                              builder: (_) =>
                                  const ActivitySheet(uid: recipient)),
                          child: const Text('Activity')))
                  : const NotesPage())),
    );
  }

  Future<void> tapVisible(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
  }

  Future<void> open(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(app(dark: dark));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    await tapVisible(tester, 'Preview');
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    vm.bindUser(null);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Library preview is formatted read-only; reading and leaving do not mutate or accept',
      (tester) async {
    await open(tester);
    expect(find.byType(SharedNotePreviewPage), findsOneWidget);
    expect(find.byType(AddEditNotePage), findsNothing);
    final editor =
        tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor));
    expect(editor.controller.readOnly, isTrue);
    expect(editor.controller.document.toPlainText(), 'Full shared text\n');
    expect(editor.controller.document.toDelta().toJson().first['attributes'],
        {'bold': true});
    expect(find.byTooltip('Share note'), findsNothing);
    expect(find.text('Accept copy'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(vm.pendingSharedNotes.length, 1);
    expect(server.source!.content, invitation.content);
    expect(server.copies, isEmpty);
    expect(server.writes, isEmpty);
    expect(await const OfflineNoteStore().loadOutbox(recipient), isEmpty);
    await finish(tester);
  });

  for (final preview in [false, true]) {
    for (final accept in [false, true]) {
      testWidgets(
          '${preview ? "Preview" : "Card"} ${accept ? "accept" : "decline"} refreshes Library and prevents repeated decisions',
          (tester) async {
        if (preview) {
          await open(tester);
        } else {
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
        }
        server.actionGate = Completer<void>();
        final button = find.text(accept ? 'Accept copy' : 'Decline');
        await tester.ensureVisible(button.first);
        await tester.pump();
        await tester.tap(button);
        await tester.tap(button);
        await tester.pump();
        expect(find.text('Please wait…'), findsWidgets);
        expect(
            tester
                .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Decline').first)
                .onPressed,
            isNull);
        server.actionGate!.complete();
        await tester.pumpAndSettle();
        expect(server.writes.length, 1);
        expect(server.copies.length, accept ? 1 : 0);
        expect(server.source!.pendingSharedWithUserIds, isEmpty);
        expect(server.source!.content, invitation.content);
        expect(vm.pendingSharedNotes, isEmpty);
        if (accept) {
          expect(vm.notes.single.sourceNoteId, 'pending');
          expect(vm.notes.single.userId, recipient);
        }
        expect(find.byType(SharedNotePreviewPage), findsNothing);
        await finish(tester);
      });
    }
  }

  for (final deleted in [false, true]) {
    for (final before in [false, true]) {
      testWidgets(
          '${deleted ? "Delete" : "Revoke"} ${before ? "after listing" : "while previewing"} hides source and decisions',
          (tester) async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        if (!before) {
          await tapVisible(tester, 'Preview');
          await tester.pumpAndSettle();
        }
        server.source = deleted
            ? invitation.copyWith(deletedAt: DateTime(2026))
            : invitation.copyWith(pendingSharedWithUserIds: []);
        if (before) {
          await tapVisible(tester, 'Preview');
        } else {
          await tester.pump(const Duration(seconds: 30));
        }
        await tester.pumpAndSettle();
        expect(find.text('This shared note is no longer available.'),
            findsOneWidget);
        expect(find.byType(quill.QuillEditor), findsNothing);
        expect(find.text('Accept copy'), findsNothing);
        expect(server.writes, isEmpty);
        expect(server.copies, isEmpty);
        await finish(tester);
      });
    }
  }

  testWidgets(
      'Offline failure hides previously read content and Retry reauthorizes',
      (tester) async {
    await open(tester);
    server.offline = true;
    await tester.pump(const Duration(seconds: 30));
    // Advance the SDK's bounded network retry timers in fake time.
    for (final seconds in [1, 2, 4, 8]) {
      await tester.pump(Duration(seconds: seconds));
    }
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(find.text('Couldn’t load this shared note.'), findsOneWidget);
    server.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    expect(server.writes, isEmpty);
    await finish(tester);
  });

  testWidgets(
      'Failed acceptance keeps decisions available for retry without dismissing preview',
      (tester) async {
    await open(tester);
    server.failAction = true;
    await tapVisible(tester, 'Accept copy');
    await tester.pumpAndSettle();
    expect(find.byType(SharedNotePreviewPage), findsOneWidget);
    expect(server.copies, isEmpty);
    server.failAction = false;
    await tapVisible(tester, 'Accept copy');
    await tester.pumpAndSettle();
    expect(server.copies.length, 1);
    expect(vm.pendingSharedNotes, isEmpty);
    await finish(tester);
  });

  testWidgets(
      'Account change rejects an in-flight preview response and a stranger cannot preview',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    server.readGate = Completer<void>();
    await tapVisible(tester, 'Preview');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _session(client, stranger);
    auth.switchUser(stranger);
    vm.bindUser(stranger);
    await tester.pump();
    server.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(
        find.text('This shared note is no longer available.'), findsOneWidget);
    expect(server.writes, isEmpty);
    await finish(tester);
  });

  testWidgets('Activity opens pending notes in the same preview',
      (tester) async {
    await tester.pumpWidget(app(activity: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA sent a copy'));
    await tester.pumpAndSettle();
    expect(find.byType(SharedNotePreviewPage), findsOneWidget);
    expect(find.byType(AddEditNotePage), findsNothing);
    expect(find.text('Accept copy'), findsOneWidget);
    expect(server.writes, isEmpty);
    await finish(tester);
  });

  testWidgets('Leaving during acceptance does not pop the underlying Library',
      (tester) async {
    await open(tester);
    server.actionGate = Completer<void>();
    await tapVisible(tester, 'Accept copy');
    await tester.pump();
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 100));
    server.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NotesPage), findsOneWidget);
    expect(find.byType(SharedNotePreviewPage), findsNothing);
    expect(server.copies.length, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
      'Activity route stays a preview when rebuilt after account switch',
      (tester) async {
    await tester.pumpWidget(app(activity: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA sent a copy'));
    await tester.pumpAndSettle();
    final route =
        ModalRoute.of(tester.element(find.byType(SharedNotePreviewPage)))!;
    await _session(client, stranger);
    auth.switchUser(stranger);
    vm.bindUser(stranger);
    route.changedExternalState();
    await tester.pumpAndSettle();
    expect(find.byType(SharedNotePreviewPage), findsOneWidget);
    expect(find.byType(AddEditNotePage), findsNothing);
    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
      'Backgrounding clears content and resuming rechecks the invitation',
      (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsNothing);
    server.source = invitation.copyWith(pendingSharedWithUserIds: []);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
        find.text('This shared note is no longer available.'), findsOneWidget);
    expect(server.writes, isEmpty);
    await finish(tester);
  });

  testWidgets('Revocation disposes media before an in-flight signer completes',
      (tester) async {
    final signing = Completer<String>();
    var signs = 0;
    MediaUrlResolver.clearCache();
    MediaUrlResolver.setSignerForTesting((bucket, path) {
      signs++;
      return signing.future;
    });
    addTearDown(() {
      MediaUrlResolver.setSignerForTesting(null);
      MediaUrlResolver.clearCache();
    });
    server.source = invitation.copyWith(
        content: jsonEncode({
      'notedDocument': 1,
      'ops': [
        {
          'insert': {
            'image':
                'noted-media://note-media/users/sender/notes/pending/photo.png'
          }
        },
        {'insert': '\n'},
      ],
    }));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Preview');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(signs, 1);
    server.source = server.source!.copyWith(pendingSharedWithUserIds: []);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    signing.complete('https://example.invalid/private-photo.png');
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(
        find.text('This shared note is no longer available.'), findsOneWidget);
    expect(signs, 1);
    expect(server.writes, isEmpty);
    await finish(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('Preview labels and layout at 360px ${dark ? "dark" : "light"}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await open(tester, dark: dark);
      expect(find.bySemanticsLabel('Accept copy'), findsOneWidget);
      expect(find.bySemanticsLabel('Decline'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await finish(tester);
    });
  }
}
