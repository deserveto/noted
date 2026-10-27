import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/connection_model.dart';
import '../models/user_model.dart';
import '../services/supabase_service.dart';
import 'paginated_query.dart';

class ConnectionRepository {
  ConnectionRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  Stream<List<ConnectionModel>> watchConnections(String userId) {
    final client = _maybeClient;
    if (client == null || userId.isEmpty) {
      return Stream<List<ConnectionModel>>.value(const []);
    }

    late final StreamController<List<ConnectionModel>> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final rows = await fetchAllPages((start, end) => client
            .from('connection_requests')
            .select()
            .or('from_user_id.eq.$userId,to_user_id.eq.$userId')
            .order('connection_id')
            .range(start, end));

        final values = rows
            .map((r) => ConnectionModel.fromMap(Map<String, dynamic>.from(r)))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        if (!controller.isClosed) {
          controller.add(values);
        }
      } catch (err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<List<ConnectionModel>>(
      onListen: () {
        refresh();
        channel = client
            .channel('connections-$userId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'connection_requests',
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> sendRequest({
    required UserModel fromUser,
    required String targetEmail,
  }) async {
    try {
      await SupabaseService.invokeFunction(
        'connections',
        {
          'action': 'requestConnection',
          'email': targetEmail.trim().toLowerCase(),
        },
        clientOverride: _clientOverride,
      );
    } on BackendFunctionException catch (error) {
      throw ConnectionException(error.message, code: error.code);
    }
  }

  Future<void> inviteByEmail(String email) async {
    try {
      await SupabaseService.invokeFunction(
        'connections',
        {
          'action': 'inviteByEmail',
          'email': email.trim().toLowerCase(),
        },
        clientOverride: _clientOverride,
      );
    } on BackendFunctionException catch (error) {
      throw ConnectionException(error.message, code: error.code);
    }
  }

  Future<void> resendRequest(String connectionId) async {
    try {
      await SupabaseService.invokeFunction(
        'connections',
        {
          'action': 'resendConnectionRequest',
          'connectionId': connectionId,
        },
        clientOverride: _clientOverride,
      );
    } on BackendFunctionException catch (error) {
      throw ConnectionException(error.message, code: error.code);
    }
  }

  Future<void> acceptRequest(String connectionId) async {
    await _client.from('connection_requests').update({
      'status': ConnectionStatus.accepted.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('connection_id', connectionId);
  }

  Future<void> rejectRequest(String connectionId) async {
    await _client.from('connection_requests').update({
      'status': ConnectionStatus.rejected.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('connection_id', connectionId);
  }

  Future<void> removeConnection(String connectionId) async {
    await _client
        .from('connection_requests')
        .delete()
        .eq('connection_id', connectionId);
  }

  Future<UserModel?> findUserByEmail(String email) async {
    // Email lookup is intentionally restricted server-side via `requestConnection`
    // to prevent client-side email enumeration.
    return null;
  }
}

class InvitationService {
  InvitationService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  Stream<List<Map<String, dynamic>>> watchInvitations(String uid) {
    final client = _maybeClient;
    if (client == null || uid.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }

    late final StreamController<List<Map<String, dynamic>>> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final rows = await fetchAllPages((start, end) => client
            .from('user_invitations')
            .select()
            .eq('user_id', uid)
            .order('sent_at', ascending: false)
            .order('email_hash')
            .range(start, end));

        if (!controller.isClosed) {
          controller.add(
            rows.map((r) => Map<String, dynamic>.from(r)).toList(),
          );
        }
      } catch (err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        refresh();
        channel = client
            .channel('invitations-$uid-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'user_invitations',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: uid,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<void> cancelInvitation(String uid, String emailHash) async {
    final client = _maybeClient;
    if (client == null) return;
    await client
        .from('user_invitations')
        .delete()
        .eq('user_id', uid)
        .eq('email_hash', emailHash);
  }
}

class ConnectionException implements Exception {
  const ConnectionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
