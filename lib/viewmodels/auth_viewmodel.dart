import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/media_url_resolver.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._repository);

  final AuthRepository _repository;
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<bool>? _recoverySubscription;

  UserModel? _user;
  bool _isInitializing = true;
  bool _isLoading = false;
  bool _isPasswordRecovery = false;
  String? _errorMessage;
  int _syncGeneration = 0;
  int _sessionEpoch = 0;
  String? _sessionUid;
  bool _disposed = false;

  bool _canApplyUser(int epoch, UserModel user) =>
      !_disposed &&
      epoch == _sessionEpoch &&
      (_sessionUid == null || _sessionUid == user.uid);

  UserModel? get user => _user;
  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get isPasswordRecovery => _isPasswordRecovery;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _authSubscription = _repository.authUidChanges().listen(_syncUser);
    _recoverySubscription =
        _repository.passwordRecoveryChanges().listen((recovering) {
      if (recovering) {
        _isPasswordRecovery = true;
        notifyListeners();
      }
    });
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final epoch = _sessionEpoch;
    return _runAuthAction(() async {
      final user = await _repository.signUp(
        name: name,
        email: email,
        password: password,
      );
      if (_canApplyUser(epoch, user)) _user = user;
    });
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    final epoch = _sessionEpoch;
    return _runAuthAction(() async {
      final user = await _repository.signIn(email: email, password: password);
      if (_canApplyUser(epoch, user)) _user = user;
    });
  }

  Future<void> signOut() async {
    final uid = _user?.uid ?? _sessionUid;
    final epoch = ++_sessionEpoch;
    _syncGeneration++;
    _isLoading = true;
    notifyListeners();
    await _repository.signOut();
    if (_disposed ||
        (_sessionUid != null &&
            (_sessionUid != uid || epoch != _sessionEpoch))) {
      return;
    }
    ProfileRepository.clearCache();
    MediaUrlResolver.clearCache();
    _user = null;
    _isPasswordRecovery = false;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> resetPassword(String email) =>
      _runAuthAction(() => _repository.resetPassword(email));

  Future<String> uploadAvatar(Uint8List bytes) async {
    final current = _user;
    if (current == null) {
      throw const AuthException('Sign in to update your profile photo.');
    }
    return _repository.uploadAvatar(uid: current.uid, bytes: bytes);
  }

  Future<bool> updateProfile({
    required String name,
    required String fieldOfStudy,
    String? avatarUrl,
  }) {
    final epoch = _sessionEpoch;
    return _runAuthAction(() async {
      final user = await _repository.updateProfile(
        name: name,
        fieldOfStudy: fieldOfStudy,
        avatarUrl: avatarUrl,
      );
      if (_canApplyUser(epoch, user)) {
        _user = user;
        ProfileRepository.clearCache();
      }
    });
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _runAuthAction(() => _repository.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ));

  Future<bool> completePasswordRecovery(String newPassword) =>
      _runAuthAction(() async {
        await _repository.completePasswordRecovery(newPassword);
        _isPasswordRecovery = false;
      });

  void dismissPasswordRecovery() {
    if (!_isPasswordRecovery) return;
    _isPasswordRecovery = false;
    notifyListeners();
  }

  Future<bool> deleteAccount(String password) {
    final uid = _user?.uid ?? _sessionUid;
    final epoch = ++_sessionEpoch;
    _syncGeneration++;
    return _runAuthAction(() async {
      await _repository.deleteAccount(password);
      if (_disposed ||
          (_sessionUid != null &&
              (_sessionUid != uid || epoch != _sessionEpoch))) {
        return;
      }
      ProfileRepository.clearCache();
      MediaUrlResolver.clearCache();
      _user = null;
      _isPasswordRecovery = false;
    });
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _runAuthAction(Future<void> Function() action) async {
    final epoch = _sessionEpoch;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (error) {
      if (_disposed || epoch != _sessionEpoch) return false;
      _errorMessage = error.message;
    } catch (error) {
      if (_disposed || epoch != _sessionEpoch) return false;
      _errorMessage = error.toString();
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> _syncUser(String? uid) async {
    final generation = ++_syncGeneration;
    if (_sessionUid != null && _sessionUid != uid) {
      _sessionEpoch++;
      _isPasswordRecovery = false;
      _isLoading = false;
    }
    _sessionUid = uid;
    if (uid == null) {
      if (_user != null) {
        ProfileRepository.clearCache();
        MediaUrlResolver.clearCache();
      }
      _user = null;
      _isInitializing = false;
      notifyListeners();
      return;
    }

    if (_user != null && _user!.uid != uid) {
      ProfileRepository.clearCache();
      MediaUrlResolver.clearCache();
      _user = null;
      _isInitializing = true;
      notifyListeners();
    }

    try {
      final user = await _repository.loadCurrentUser();
      if (_disposed || generation != _syncGeneration || _sessionUid != uid) {
        return;
      }
      if (user != null && user.uid != uid) return;
      _user = user;
    } catch (error) {
      if (_disposed || generation != _syncGeneration || _sessionUid != uid) {
        return;
      }
      _errorMessage = error.toString();
    }
    _isInitializing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncGeneration++;
    _sessionEpoch++;
    _authSubscription?.cancel();
    _recoverySubscription?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
