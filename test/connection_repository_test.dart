import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/repositories/connection_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Use the SDK's injectable JSON worker synchronously in fake test time.
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
      connectionsChannel ??= _ControllableChannel(name, realtime);

  _ControllableChannel? connectionsChannel;
}

class _ControllableChannel extends RealtimeChannel {
  _ControllableChannel(super.topic, super.socket);

  int unsubscribeCalls = 0;
  void Function(RealtimeSubscribeStatus, Object?)? _subscribeCallback;
  void Function(PostgresChangePayload)? _changeCallback;

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus, Object?)? callback,
    Duration? timeout,
  ]) {
    _subscribeCallback = callback;
    return this;
  }

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
    required void Function(PostgresChangePayload payload) callback,
  }) {
    _changeCallback = callback;
    return this;
  }

  void markSubscribed() {
    _subscribeCallback?.call(RealtimeSubscribeStatus.subscribed, null);
  }

  void emitChange() {
    _changeCallback?.call(PostgresChangePayload(
      schema: 'public',
      table: 'connection_requests',
      commitTimestamp: DateTime(2026, 11, 5),
      eventType: PostgresChangeEvent.insert,
      newRecord: const {},
      oldRecord: const {},
      errors: null,
    ));
  }

  @override
  Future<String> unsubscribe([Duration? timeout]) async {
    unsubscribeCalls++;
    return 'ok';
  }
}

class _Server {
  List<Map<String, dynamic>> rows = const [];
  int reads = 0;
  Completer<void>? firstReadStarted;
  Completer<void>? holdFirstRead;

  Future<http.Response> handle(http.Request request) async {
    if (request.method != 'GET' ||
        !request.url.path.endsWith('/connection_requests')) {
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }

    final read = reads++;
    final snapshot = List<Map<String, dynamic>>.of(rows);
    if (read == 0) {
      firstReadStarted?.complete();
      await holdFirstRead?.future;
    }
    return http.Response(
      jsonEncode(snapshot),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
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

Map<String, dynamic> _pendingRow() {
  return {
    'connection_id': 'pending-connection',
    'from_user_id': '22222222-2222-4222-8222-222222222222',
    'from_name': 'Alex',
    'from_email': 'alex@example.com',
    'to_user_id': _recipient,
    'to_name': 'Recipient',
    'to_email': 'recipient@example.com',
    'status': 'pending',
    'created_at': '2026-11-05T00:00:00Z',
    'updated_at': '2026-11-05T00:00:00Z',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late _HttpOnlyClient client;
  late ConnectionRepository repository;

  setUp(() async {
    server = _Server();
    client = _HttpOnlyClient(MockClient(server.handle));
    await _setSession(client);
    repository = ConnectionRepository(client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  test('initial fetch starts only after Realtime is subscribed', () async {
    server.firstReadStarted = Completer<void>();
    final rows = <List<ConnectionModel>>[];
    final subscription =
        repository.watchConnections(_recipient).listen(rows.add);
    await Future<void>.delayed(Duration.zero);

    expect(server.reads, 0);
    expect(rows, isEmpty);

    client.connectionsChannel!.markSubscribed();
    await server.firstReadStarted!.future;
    await _waitFor(() => rows.isNotEmpty);

    expect(rows.single, isEmpty);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(client.connectionsChannel!.unsubscribeCalls, 1);
  });

  test('a delayed older refresh cannot overwrite a newer snapshot', () async {
    server
      ..firstReadStarted = Completer<void>()
      ..holdFirstRead = Completer<void>();
    final rows = <List<ConnectionModel>>[];
    final subscription =
        repository.watchConnections(_recipient).listen(rows.add);

    client.connectionsChannel!.markSubscribed();
    await server.firstReadStarted!.future;

    server.rows = [_pendingRow()];
    client.connectionsChannel!.emitChange();
    await _waitFor(() => rows.isNotEmpty);
    expect(rows.single.single.connectionId, 'pending-connection');

    server.holdFirstRead!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(rows, hasLength(1));

    await subscription.cancel();
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before the deadline.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
