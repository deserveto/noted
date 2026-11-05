import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/services/supabase_service.dart';
import 'package:noted/viewmodels/connection_viewmodel.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/views/connections_page.dart';
import 'package:noted/widgets/activity_sheet.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Use the SDK's injectable JSON worker synchronously in fake widget time.
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

const _recipient = '11111111-1111-4111-8111-111111111111';

class _InlineJson extends YAJsonIsolate {
  @override
  Future<dynamic> decode(String json) async => jsonDecode(json);

  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
}

class _HttpOnlyClient extends SupabaseClient {
  _HttpOnlyClient(http.Client transport)
      : super(
          'https://example.invalid',
          'fake',
          httpClient: transport,
          isolate: _InlineJson(),
          postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );

  @override
  RealtimeChannel channel(
    String name, {
    RealtimeChannelConfig opts = const RealtimeChannelConfig(),
  }) =>
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

class _RecordingConnections extends ChangeNotifier
    implements ConnectionViewModel {
  int refreshCalls = 0;
  List<ConnectionModel> _requests = const [];

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    _requests = [_pendingConnection()];
    await Future<void>.delayed(Duration.zero);
    notifyListeners();
    return true;
  }

  @override
  List<ConnectionModel> get incomingRequests => _requests;

  @override
  List<ConnectionModel> get connections => _requests;

  @override
  List<ConnectionModel> get acceptedConnections => const [];

  @override
  List<ConnectionModel> get outgoingRequests => const [];

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  UserModel? get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNotes extends ChangeNotifier implements NoteViewModel {
  @override
  List<NoteModel> get liveNotes => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConnectionModel _pendingConnection() {
  return ConnectionModel(
    connectionId: 'pending-connection',
    fromUserId: '22222222-2222-4222-8222-222222222222',
    fromName: 'Alex',
    fromEmail: 'alex@example.com',
    toUserId: _recipient,
    toName: 'Recipient',
    toEmail: 'recipient@example.com',
    status: ConnectionStatus.pending,
    createdAt: DateTime(2026, 11, 5),
    updatedAt: DateTime(2026, 11, 5),
  );
}

Future<void> _setSession(SupabaseClient client) {
  return client.auth.setInitialSession(jsonEncode({
    'access_token': 'test-token',
    'refresh_token': 'test-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': _recipient,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  }));
}

http.Response _reply(http.BaseRequest request, Object? data) {
  return http.Response(
    jsonEncode(data),
    200,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

Future<http.Response> _handleActivityRequest(http.Request request) async {
  if (request.method == 'GET' && request.url.path.endsWith('/notifications')) {
    return _reply(request, [
      {
        'id': 'connection-activity',
        'user_id': _recipient,
        'type': 'request',
        'title': 'Alex wants to connect',
        'body': 'Open Connections to accept or decline.',
        'actor_id': '22222222-2222-4222-8222-222222222222',
        'actor_name': 'Alex',
        'read': true,
        'created_at': '2026-11-05T00:00:00Z',
      }
    ]);
  }
  if (request.method == 'PATCH' &&
      request.url.path.endsWith('/notifications')) {
    return http.Response('', 204, request: request);
  }
  throw StateError('Unexpected request: ${request.method} ${request.url}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _HttpOnlyClient client;
  late _RecordingConnections connections;
  late _NoNotes notes;
  var openedConnections = false;

  setUp(() async {
    openedConnections = false;
    client = _HttpOnlyClient(MockClient(_handleActivityRequest));
    await _setSession(client);
    SupabaseService.setTestClient(client);
    connections = _RecordingConnections();
    notes = _NoNotes();
  });

  tearDown(() async {
    connections.dispose();
    notes.dispose();
    SupabaseService.setTestClient(null);
    await client.dispose();
  });

  testWidgets('connection activity immediately shows the pending request',
      (tester) async {
    final showConnections = ValueNotifier(false);
    addTearDown(showConnections.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectionViewModel>.value(value: connections),
          ChangeNotifierProvider<NoteViewModel>.value(value: notes),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showConnections,
            builder: (context, show, _) => show
                ? const Scaffold(body: ConnectionsPage())
                : Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => SizedBox(
                            height: 600,
                            child: ActivitySheet(
                              uid: _recipient,
                              onConnections: () {
                                openedConnections = true;
                                showConnections.value = true;
                              },
                            ),
                          ),
                        ),
                        child: const Text('Open activity'),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex wants to connect'));
    await tester.pumpAndSettle();

    expect(openedConnections, isTrue);
    expect(connections.refreshCalls, 1);
    expect(find.text('Requests · 1'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.byTooltip('Decline Alex'), findsOneWidget);
  });

  testWidgets('entering Connections directly refreshes missed requests',
      (tester) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);

    await tester.pumpWidget(_connectionsHarness(
      active,
      connections: connections,
      notes: notes,
    ));
    await tester.pumpAndSettle();

    expect(connections.refreshCalls, 0);
    expect(find.text('Requests · 1'), findsNothing);

    active.value = true;
    await tester.pumpAndSettle();

    expect(connections.refreshCalls, 1);
    expect(find.text('Requests · 1'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('an active Connections page refreshes after resume',
      (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);

    await tester.pumpWidget(_connectionsHarness(
      active,
      connections: connections,
      notes: notes,
    ));
    await tester.pumpAndSettle();
    expect(connections.refreshCalls, 1);

    connections.refreshCalls = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(connections.refreshCalls, 1);
  });
}

Widget _connectionsHarness(
  ValueListenable<bool> active, {
  required ConnectionViewModel connections,
  required NoteViewModel notes,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ConnectionViewModel>.value(value: connections),
      ChangeNotifierProvider<NoteViewModel>.value(value: notes),
    ],
    child: MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (context, isActive, _) => Scaffold(
          body: isActive
              ? ConnectionsPage(active: isActive)
              : const Center(child: Text('Inactive')),
        ),
      ),
    ),
  );
}
