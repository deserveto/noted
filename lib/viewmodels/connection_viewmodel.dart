import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/connection_model.dart';
import '../models/user_model.dart';
import '../repositories/connection_repository.dart';

class ConnectionViewModel extends ChangeNotifier {
  ConnectionViewModel(this._repository);

  final ConnectionRepository _repository;
  StreamSubscription<List<ConnectionModel>>? _subscription;

  UserModel? _boundUser;
  List<ConnectionModel> _connections = [];
  bool _isRefreshing = false;
  bool _isActing = false;
  String? _errorMessage;
  bool _isDisposed = false;
  bool _notifyQueued = false;
  bool _errorFromRefresh = false;
  int _accountGeneration = 0;
  int _watchGeneration = 0;
  Completer<bool>? _refreshCompleter;
  String? _refreshUserId;

  UserModel? get user => _boundUser;
  List<ConnectionModel> get connections => List.unmodifiable(_connections);
  bool get isLoading => _isRefreshing || _isActing;
  String? get errorMessage => _errorMessage;

  List<ConnectionModel> get acceptedConnections {
    return _connections
        .where((connection) => connection.status == ConnectionStatus.accepted)
        .toList();
  }

  List<ConnectionModel> get incomingRequests {
    final userId = _boundUser?.uid;
    if (userId == null) {
      return const [];
    }
    return _connections
        .where((connection) => connection.isIncomingFor(userId))
        .toList();
  }

  List<ConnectionModel> get outgoingRequests {
    final userId = _boundUser?.uid;
    if (userId == null) {
      return const [];
    }
    return _connections
        .where((connection) => connection.isOutgoingFor(userId))
        .toList();
  }

  void bindUser(UserModel? user, {bool notifyOnBind = true}) {
    if (_boundUser?.uid == user?.uid && user != null) {
      return;
    }

    _boundUser = user;
    _accountGeneration++;
    _replaceWatch();
    _connections = [];
    _errorMessage = null;
    _errorFromRefresh = false;
    _isRefreshing = false;
    _isActing = false;

    if (user == null) {
      _notifyListenersIfActive(notifyOnBind);
      return;
    }

    _isRefreshing = true;
    _notifyListenersIfActive(notifyOnBind);
    _startWatching(user.uid);
  }

  Future<bool> refresh() {
    final user = _boundUser;
    final pending = _refreshCompleter;
    if (_isDisposed || user == null) {
      return Future<bool>.value(false);
    }
    if (pending != null && !pending.isCompleted && _refreshUserId == user.uid) {
      return pending.future;
    }

    _replaceWatch();
    _isRefreshing = true;
    _errorMessage = null;
    _errorFromRefresh = false;
    _notifyListenersIfActive();
    return _startWatching(user.uid);
  }

  Future<bool> _startWatching(String userId) {
    final accountGeneration = _accountGeneration;
    final watchGeneration = _watchGeneration;
    final completer = Completer<bool>();
    _refreshCompleter = completer;
    _refreshUserId = userId;

    bool isCurrent() =>
        !_isDisposed &&
        accountGeneration == _accountGeneration &&
        watchGeneration == _watchGeneration;

    void finish(bool success) {
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
        _refreshUserId = null;
      }
      if (!completer.isCompleted) {
        completer.complete(success);
      }
    }

    _subscription = _repository.watchConnections(userId).listen(
      (connections) {
        if (!isCurrent()) return;
        _connections = connections;
        _isRefreshing = false;
        if (_errorFromRefresh) {
          _errorMessage = null;
          _errorFromRefresh = false;
        }
        finish(true);
        _notifyListenersIfActive();
      },
      onError: (Object error) {
        if (!isCurrent()) return;
        _errorMessage = error.toString();
        _errorFromRefresh = true;
        _isRefreshing = false;
        finish(false);
        _notifyListenersIfActive();
      },
      onDone: () {
        if (!isCurrent()) return;
        _errorMessage ??= 'Connection updates stopped.';
        _errorFromRefresh = true;
        _isRefreshing = false;
        finish(false);
        _notifyListenersIfActive();
      },
    );
    return completer.future;
  }

  void _replaceWatch() {
    _watchGeneration++;
    _subscription?.cancel();
    _subscription = null;
    final pending = _refreshCompleter;
    _refreshCompleter = null;
    _refreshUserId = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(false);
    }
  }

  Future<bool> sendRequest(String email) async {
    final user = _boundUser;
    if (user == null) {
      return false;
    }
    final accountGeneration = _accountGeneration;
    bool isCurrent() => !_isDisposed && accountGeneration == _accountGeneration;
    _errorMessage = null;
    _errorFromRefresh = false;
    try {
      await _repository.sendRequest(fromUser: user, targetEmail: email);
      return isCurrent();
    } catch (error) {
      if (!isCurrent()) return false;
      _errorMessage = error.toString();
      _errorFromRefresh = false;
      _notifyListenersIfActive();
      return false;
    }
  }

  Future<bool> invite(String email) async {
    final user = _boundUser;
    if (user == null) return false;
    return _runAction(() async {
      try {
        await _repository.sendRequest(fromUser: user, targetEmail: email);
      } on ConnectionException catch (error) {
        if (error.code != 'not-found') rethrow;
        await _repository.inviteByEmail(email);
      }
    });
  }

  Future<bool> resend(ConnectionModel connection) =>
      _runAction(() => _repository.resendRequest(connection.connectionId));

  Future<bool> accept(ConnectionModel connection) {
    return _runAction(
      () => _repository.acceptRequest(connection.connectionId),
      onSuccess: () => _replaceConnection(
        connection.copyWith(
          status: ConnectionStatus.accepted,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<bool> reject(ConnectionModel connection) {
    return _runAction(
      () => _repository.rejectRequest(connection.connectionId),
      onSuccess: () => _replaceConnection(
        connection.copyWith(
          status: ConnectionStatus.rejected,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<bool> removeConnection(ConnectionModel connection) {
    return _runAction(
      () => _repository.removeConnection(connection.connectionId),
      onSuccess: () => _connections = _connections
          .where((item) => item.connectionId != connection.connectionId)
          .toList(),
    );
  }

  void retry() {
    unawaited(refresh());
  }

  void clearError() {
    _errorMessage = null;
    _errorFromRefresh = false;
    _notifyListenersIfActive();
  }

  Future<bool> _runAction(
    Future<void> Function() action, {
    void Function()? onSuccess,
  }) async {
    final accountGeneration = _accountGeneration;
    bool isCurrent() => !_isDisposed && accountGeneration == _accountGeneration;

    if (!isCurrent() || _boundUser == null || _isActing) return false;
    _isActing = true;
    _errorMessage = null;
    _errorFromRefresh = false;
    _notifyListenersIfActive();
    try {
      await action();
      if (!isCurrent()) return false;
      onSuccess?.call();
      _isActing = false;
      _notifyListenersIfActive();
      return true;
    } catch (error) {
      if (!isCurrent()) return false;
      _errorMessage = error.toString();
      _errorFromRefresh = false;
      _isActing = false;
      _notifyListenersIfActive();
      return false;
    }
  }

  void _replaceConnection(ConnectionModel replacement) {
    _connections = [
      for (final connection in _connections)
        if (connection.connectionId == replacement.connectionId)
          replacement
        else
          connection,
    ];
  }

  void _notifyListenersIfActive([bool shouldNotify = true]) {
    if (_isDisposed || !shouldNotify || _notifyQueued) {
      return;
    }
    _notifyQueued = true;
    Future.microtask(() {
      _notifyQueued = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _accountGeneration++;
    _replaceWatch();
    super.dispose();
  }
}
