import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../services/supabase_service.dart';

class ProfileRepository {
  ProfileRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  static final Map<String, UserModel> _peerCache = {};

  static void clearCache() => _peerCache.clear();

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  Future<UserModel?> load(String uid) async {
    if (uid.isEmpty) return null;
    final cached = _peerCache[uid];
    if (cached != null) return cached;

    final client = _maybeClient;
    if (client == null) return null;

    try {
      if (client.auth.currentUser?.id == uid) {
        final own = await client
            .from('profiles')
            .select()
            .eq('id', uid)
            .maybeSingle();
        if (own != null) {
          final model = UserModel.fromMap(Map<String, dynamic>.from(own));
          _peerCache[uid] = model;
          return model;
        }
      }

      final data = await client.rpc(
        'get_peer_profile',
        params: {'p_target_id': uid},
      );
      if (data is Map) {
        final model = UserModel.fromMap(Map<String, dynamic>.from(data));
        _peerCache[uid] = model;
        return model;
      }
    } catch (_) {}
    return null;
  }
}
