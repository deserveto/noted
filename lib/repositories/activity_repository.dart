import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class ActivityRepository {
  ActivityRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  Stream<bool> watchHasUnread(String uid) {
    final client = _maybeClient;
    if (client == null || uid.isEmpty) {
      return Stream<bool>.value(false);
    }

    late final StreamController<bool> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final rows = await client
            .from('notifications')
            .select('id')
            .eq('user_id', uid)
            .eq('read', false)
            .limit(1);
        if (!controller.isClosed) {
          controller.add(rows.isNotEmpty);
        }
      } catch (_) {
        if (!controller.isClosed) {
          controller.add(false);
        }
      }
    }

    controller = StreamController<bool>(
      onListen: () {
        refresh();
        channel = client
            .channel('activity-bell-$uid-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
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

  Stream<List<Map<String, dynamic>>> watchNotifications(
    String uid, {
    int limit = 100,
  }) {
    final client = _maybeClient;
    if (client == null || uid.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }

    late final StreamController<List<Map<String, dynamic>>> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final rows = await client
            .from('notifications')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(limit);
        if (!controller.isClosed) {
          controller.add(
            rows
                .map((raw) {
                  final r = Map<String, dynamic>.from(raw);
                  return {
                    ...r,
                    'id': r['id']?.toString() ?? '',
                    'noteId': r['note_id'],
                    'actorId': r['actor_id'],
                    'actorName': r['actor_name'],
                    'createdAt': DateTime.tryParse(
                      r['created_at']?.toString() ?? '',
                    ),
                  };
                })
                .toList(),
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
            .channel('activity-feed-$uid-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
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

  Future<void> markAsRead(String uid, List<String> notificationIds) async {
    final client = _maybeClient;
    if (client == null || uid.isEmpty || notificationIds.isEmpty) return;
    await client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', uid)
        .inFilter('id', notificationIds);
  }
}
