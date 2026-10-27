import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/auth_repository.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

UserModel account(String uid) => UserModel(
      uid: uid,
      name: uid,
      email: '$uid@example.test',
      createdAt: DateTime.utc(2026),
    );

class DelayedAuth extends AuthRepository {
  final changes = StreamController<String?>.broadcast(sync: true);
  final profiles = <String, Completer<UserModel?>>{};
  final profileUpdate = Completer<UserModel>();
  final login = Completer<UserModel>();
  Completer<void>? logout;
  Completer<void>? deletion;
  String? active;

  void emit(String? uid) {
    active = uid;
    changes.add(uid);
  }

  @override
  String? get currentUserId => active;
  @override
  Stream<String?> authUidChanges() => changes.stream;
  @override
  Stream<bool> passwordRecoveryChanges() => const Stream.empty();
  @override
  Future<UserModel?> loadCurrentUser() => profiles[active]!.future;
  @override
  Future<void> signOut() async {
    if (logout != null) {
      await logout!.future;
    } else {
      emit(null);
    }
  }

  @override
  Future<void> deleteAccount(String password) async => deletion!.future;
  @override
  Future<UserModel> signIn({required String email, required String password}) =>
      login.future;
  @override
  Future<UserModel> updateProfile(
          {required String name,
          required String fieldOfStudy,
          String? avatarUrl}) =>
      profileUpdate.future;
}

class DeletingRepository extends AuthRepository {
  DeletingRepository(SupabaseClient client) : super(client: client);
  @override
  Future<void> reauthenticate(String password) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late profile cannot restore a signed-out account', () async {
    final repo = DelayedAuth();
    final pending = repo.profiles['alice'] = Completer<UserModel?>();
    final vm = AuthViewModel(repo);
    await vm.initialize();
    repo.emit('alice');
    repo.emit(null);
    pending.complete(account('alice'));
    await Future<void>.delayed(Duration.zero);
    expect(vm.user, isNull);
    vm.dispose();
    await repo.changes.close();
  });

  test('late old-account profile cannot replace the new session', () async {
    final repo = DelayedAuth();
    final alice = repo.profiles['alice'] = Completer<UserModel?>();
    final bob = repo.profiles['bob'] = Completer<UserModel?>();
    final vm = AuthViewModel(repo);
    await vm.initialize();
    repo.emit('alice');
    repo.emit('bob');
    bob.complete(account('bob'));
    await Future<void>.delayed(Duration.zero);
    alice.complete(account('alice'));
    await Future<void>.delayed(Duration.zero);
    expect(vm.user?.uid, 'bob');
    vm.dispose();
    await repo.changes.close();
  });

  test('profile edit from old account cannot replace newly signed-in user',
      () async {
    final repo = DelayedAuth();
    repo.profiles['alice'] = Completer<UserModel?>()
      ..complete(account('alice'));
    repo.profiles['bob'] = Completer<UserModel?>()..complete(account('bob'));
    final vm = AuthViewModel(repo);
    await vm.initialize();
    repo.emit('alice');
    await Future<void>.delayed(Duration.zero);
    final edit = vm.updateProfile(name: 'Changed', fieldOfStudy: 'Design');
    repo.emit('bob');
    await Future<void>.delayed(Duration.zero);
    repo.profileUpdate.complete(account('alice'));
    await edit;
    expect(vm.user?.uid, 'bob');
    vm.dispose();
    await repo.changes.close();
  });

  test('sign-out invalidates an in-flight sign-in result', () async {
    final repo = DelayedAuth();
    final vm = AuthViewModel(repo);
    await vm.initialize();
    final login =
        vm.signIn(email: 'alice@example.test', password: 'test-password');
    await vm.signOut();
    repo.login.complete(account('alice'));
    await login;
    expect(vm.user, isNull);
    vm.dispose();
    await repo.changes.close();
  });

  for (final delete in [false, true]) {
    test('late ${delete ? 'deletion' : 'sign-out'} cannot clear a new account',
        () async {
      final repo = DelayedAuth();
      repo.profiles['alice'] = Completer<UserModel?>()
        ..complete(account('alice'));
      repo.profiles['bob'] = Completer<UserModel?>()..complete(account('bob'));
      final pending = Completer<void>();
      if (delete) {
        repo.deletion = pending;
      } else {
        repo.logout = pending;
      }
      final vm = AuthViewModel(repo);
      await vm.initialize();
      repo.emit('alice');
      await Future<void>.delayed(Duration.zero);
      final action = delete ? vm.deleteAccount('test-password') : vm.signOut();
      repo.emit('bob');
      await Future<void>.delayed(Duration.zero);
      pending.complete();
      await action;
      expect(vm.user?.uid, 'bob');
      vm.dispose();
      await repo.changes.close();
    });
  }

  test('late old-account profile error does not overwrite new session status',
      () async {
    final repo = DelayedAuth();
    repo.profiles['alice'] = Completer<UserModel?>()
      ..complete(account('alice'));
    repo.profiles['bob'] = Completer<UserModel?>()..complete(account('bob'));
    final vm = AuthViewModel(repo);
    await vm.initialize();
    repo.emit('alice');
    await Future<void>.delayed(Duration.zero);
    final edit = vm.updateProfile(name: 'Changed', fieldOfStudy: 'Design');
    repo.emit('bob');
    await Future<void>.delayed(Duration.zero);
    repo.profileUpdate.completeError(StateError('Old profile request failed'));
    await edit;
    expect(vm.user?.uid, 'bob');
    expect(vm.errorMessage, isNull);
    vm.dispose();
    await repo.changes.close();
  });

  test('account deletion repository does not sign out a replacement session',
      () async {
    SharedPreferences.setMockInitialValues({});
    const alice = '11111111-1111-4111-8111-111111111111';
    const bob = '22222222-2222-4222-8222-222222222222';
    final deleting = Completer<void>();
    final response = Completer<void>();
    var logouts = 0;
    final client = SupabaseClient('https://example.invalid', 'fake',
        httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/account')) {
        deleting.complete();
        await response.future;
      } else if (request.url.path.endsWith('/logout')) {
        logouts++;
      }
      return http.Response('{}', 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    Future<void> session(String uid) =>
        client.auth.setInitialSession(jsonEncode({
          'access_token': 'test-token',
          'refresh_token': 'test-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': uid,
            'email': '$uid@example.test',
            'app_metadata': {},
            'user_metadata': {},
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z'
          },
        }));
    await session(alice);
    final repo = DeletingRepository(client);
    final operation = repo.deleteAccount('test-password');
    await deleting.future;
    await session(bob);
    response.complete();
    await operation;
    expect(logouts, 0);
    expect(client.auth.currentUser?.id, bob);
  });
}
