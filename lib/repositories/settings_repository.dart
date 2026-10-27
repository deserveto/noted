import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/settings_model.dart';
import '../services/supabase_service.dart';

class SettingsRepository {
  SettingsRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  Stream<SettingsModel> watch(String uid) {
    final client = _maybeClient;
    if (client == null || uid.isEmpty) {
      return const Stream<SettingsModel>.empty();
    }

    late final StreamController<SettingsModel> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final row = await client
            .from('user_settings')
            .select('preferences')
            .eq('user_id', uid)
            .maybeSingle();
        final prefs = row?['preferences'];
        final model = SettingsModel.fromMap(
          prefs is Map ? Map<String, dynamic>.from(prefs) : const {},
        );
        await cache(uid, model);
        if (!controller.isClosed) {
          controller.add(model);
        }
      } catch (err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<SettingsModel>(
      onListen: () {
        refresh();
        channel = client
            .channel('user-settings-$uid-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'user_settings',
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

  Future<SettingsModel> cached(String uid) async {
    final value =
        (await SharedPreferences.getInstance()).getString('noted.settings.$uid');
    if (value == null) return const SettingsModel();
    try {
      return SettingsModel.fromMap(
          Map<String, dynamic>.from(jsonDecode(value) as Map));
    } catch (_) {
      return const SettingsModel();
    }
  }

  Future<void> cache(String uid, SettingsModel settings) async {
    await (await SharedPreferences.getInstance())
        .setString('noted.settings.$uid', jsonEncode(settings.toMap()));
  }

  Future<void> save(
    String uid,
    SettingsModel settings, {
    Map<String, dynamic>? changes,
  }) async {
    await cache(uid, settings);
    final tzOffset = DateTime.now().timeZoneOffset.inMinutes;

    if (changes != null) {
      await _client.rpc(
        'merge_user_settings',
        params: {
          'p_changes': changes,
          'p_timezone_offset_minutes': tzOffset,
        },
      );
    } else {
      await _client.from('user_settings').upsert(
        {
          'user_id': uid,
          'preferences': settings.toMap(),
          'timezone_offset_minutes': tzOffset,
          'notes_schema': 2,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    }
  }
}
