import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:supabase_flutter/supabase_flutter.dart' as sb
    show AuthException;

import '../models/user_model.dart';
import '../services/media_url_resolver.dart';
import '../services/offline_note_store.dart';
import '../services/supabase_service.dart';

class AuthRepository {
  AuthRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  String? get currentUserId => _maybeClient?.auth.currentUser?.id;

  /// Emits the active user UID whenever the Supabase auth session changes.
  /// Attaches an `onError` listener so offline background token refresh errors
  /// never crash the app or discard the locally cached session.
  Stream<String?> authUidChanges() {
    final client = _maybeClient;
    if (client == null) {
      return Stream<String?>.value(null);
    }

    late final StreamController<String?> controller;
    StreamSubscription<AuthState>? sub;

    controller = StreamController<String?>.broadcast(
      onListen: () {
        controller.add(client.auth.currentSession?.user.id);
        sub = client.auth.onAuthStateChange.listen(
          (authState) {
            if (!controller.isClosed) {
              controller.add(authState.session?.user.id);
            }
          },
          onError: (Object _) {
            // Keep existing local session active while offline; GoTrue retries on reconnect.
            if (!controller.isClosed) {
              controller.add(client.auth.currentSession?.user.id);
            }
          },
        );
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Emits `true` when the user opens a Supabase password-recovery link
  /// (`noted://app/auth-callback`), establishing a recovery session so the app
  /// can prompt for a new password without requiring the previous password.
  Stream<bool> passwordRecoveryChanges() {
    final client = _maybeClient;
    if (client == null) {
      return const Stream<bool>.empty();
    }

    late final StreamController<bool> controller;
    StreamSubscription<AuthState>? sub;

    controller = StreamController<bool>.broadcast(
      onListen: () {
        sub = client.auth.onAuthStateChange.listen(
          (authState) {
            if (!controller.isClosed &&
                authState.event == AuthChangeEvent.passwordRecovery) {
              controller.add(true);
            }
          },
          onError: (Object _) {},
        );
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> completePasswordRecovery(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    } on BackendNotConfiguredException catch (error) {
      throw AuthException(error.message);
    }
  }

  Future<UserModel?> loadCurrentUser() async {
    final client = _maybeClient;
    final authUser = client?.auth.currentUser;
    if (client == null || authUser == null) {
      return null;
    }
    return _readOrCreateUser(client, authUser);
  }

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = name.trim();
    try {
      final response = await _client.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {'name': trimmedName},
        emailRedirectTo: SupabaseService.authRedirectUrl,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthException(
          'Account created. Check your email to confirm your account before signing in.',
        );
      }
      if (user.identities != null && user.identities!.isEmpty) {
        throw const AuthException('An account already exists with this email.');
      }
      if (response.session == null) {
        throw const AuthException(
          'Account created. Check your email to confirm your account before signing in.',
        );
      }

      final model = UserModel(
        uid: user.id,
        name: trimmedName,
        email: normalizedEmail,
        createdAt: DateTime.now(),
      );

      await _client.from('profiles').upsert(
            model.toProfileRow(),
            onConflict: 'id',
          );
      return model;
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    } on BackendNotConfiguredException catch (error) {
      throw AuthException(error.message);
    }
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthException('Signed in, but no user session was found.');
      }
      return _readOrCreateUser(_client, user);
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    } on BackendNotConfiguredException catch (error) {
      throw AuthException(error.message);
    }
  }

  Future<void> signOut() async {
    MediaUrlResolver.clearCache();
    final client = _maybeClient;
    if (client != null) {
      await client.auth.signOut();
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: SupabaseService.authRedirectUrl,
      );
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    } on BackendNotConfiguredException catch (error) {
      throw AuthException(error.message);
    }
  }

  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const AuthException('Profile photos must be smaller than 5 MB.');
    }
    final objectPath = 'users/$uid/avatar.jpg';
    await _client.storage.from(MediaUrlResolver.avatarsBucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    MediaUrlResolver.clearCache();
    return MediaUrlResolver.canonicalUri(
      MediaUrlResolver.avatarsBucket,
      objectPath,
    );
  }

  Future<UserModel> updateProfile({
    required String name,
    required String fieldOfStudy,
    String? avatarUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to edit your profile.');
    }

    final parsedAvatar = avatarUrl != null
        ? MediaUrlResolver.parsePrivateRef(
            avatarUrl,
            defaultBucket: MediaUrlResolver.avatarsBucket,
          )
        : null;

    await _client.from('profiles').update({
      'name': name.trim(),
      'field_of_study': fieldOfStudy.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (parsedAvatar != null) 'avatar_path': parsedAvatar.path,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);

    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'name': name.trim(),
          'field_of_study': fieldOfStudy.trim(),
        },
      ),
    );

    final updated = await loadCurrentUser();
    if (updated == null) {
      throw const AuthException('Could not reload updated profile.');
    }
    return updated;
  }

  Future<void> reauthenticate(String password) async {
    final user = _client.auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw const AuthException('Sign in to continue.');
    }
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await reauthenticate(currentPassword);
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    }
  }

  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    await reauthenticate(currentPassword);
    try {
      await _client.auth.updateUser(
        UserAttributes(email: newEmail.trim().toLowerCase()),
        emailRedirectTo: SupabaseService.authRedirectUrl,
      );
    } on sb.AuthException catch (error) {
      throw AuthException(_mapSupabaseAuthError(error));
    }
  }

  Future<void> deleteAccount(String password) async {
    final uid = _client.auth.currentUser?.id ?? '';
    await reauthenticate(password);
    if (uid.isEmpty || _client.auth.currentUser?.id != uid) {
      throw const AuthException(
          'Your account changed. Retry from the current account.');
    }
    try {
      await SupabaseService.invokeFunction(
        'account',
        {
          'action': 'deleteAccount',
          'currentPassword': password,
        },
        clientOverride: _clientOverride,
      );
    } on BackendFunctionException catch (error) {
      throw AuthException(error.message);
    }

    if (uid.isNotEmpty) {
      await const OfflineNoteStore().clearUser(uid);
    }
    if (_client.auth.currentUser?.id == uid) {
      MediaUrlResolver.clearCache();
      await _client.auth.signOut().catchError((Object _) {});
    }
  }

  Future<UserModel> _readOrCreateUser(
      SupabaseClient client, User authUser) async {
    try {
      final row = await client
          .from('profiles')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();
      if (row != null) {
        return UserModel.fromMap(Map<String, dynamic>.from(row));
      }
    } catch (_) {
      // Fall back to auth user metadata when offline on initial session restore
    }

    final meta = authUser.userMetadata ?? const <String, dynamic>{};
    final metaName = (meta['name'] as String?)?.trim() ?? '';
    final fallback = UserModel(
      uid: authUser.id,
      name: metaName.isNotEmpty
          ? metaName
          : (authUser.email?.split('@').first ?? 'Noted user'),
      email: authUser.email?.trim().toLowerCase() ?? '',
      fieldOfStudy: (meta['field_of_study'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(authUser.createdAt) ?? DateTime.now(),
    );

    try {
      await client.from('profiles').upsert(
            fallback.toProfileRow(),
            onConflict: 'id',
          );
    } catch (_) {}

    return fallback;
  }

  static String _mapSupabaseAuthError(sb.AuthException error) {
    final msg = error.message.toLowerCase();
    final code = (error.code ?? '').toLowerCase();
    if (code == 'invalid_credentials' ||
        msg.contains('invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) {
      return 'An account already exists with this email.';
    }
    if (code == 'weak_password' ||
        msg.contains('password should be at least')) {
      return 'Choose a stronger password with at least 6 characters.';
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        msg.contains('rate limit')) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    if (msg.contains('network') || msg.contains('socketexception')) {
      return 'Network error. Check your internet connection.';
    }
    return error.message.isNotEmpty
        ? error.message
        : 'Authentication failed. Please try again.';
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
