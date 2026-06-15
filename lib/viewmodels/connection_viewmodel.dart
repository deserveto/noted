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
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;
  bool _notifyQueued = false;

  UserModel? get user => _boundUser;
  List<ConnectionModel> get connections => List.unmodifiable(_connections);
  bool get isLoading => _isLoading;
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
    _subscription?.cancel();
    _connections = [];
    _errorMessage = null;
    _isLoading = false;

    if (user == null) {
      _notifyListenersIfActive(notifyOnBind);
      return;
    }

    _isLoading = true;
    _notifyListenersIfActive(notifyOnBind);
    _subscription = _repository.watchConnections(user.uid).listen(
      (connections) {
        _connections = connections;
        _isLoading = false;
        _notifyListenersIfActive();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        _isLoading = false;
        _notifyListenersIfActive();
      },
    );
  }

  Future<bool> sendRequest(String email) async {
    final user = _boundUser;
    if (user == null) {
      return false;
    }
    _errorMessage = null;
    try {
      await _repository.sendRequest(fromUser: user, targetEmail: email);
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      _notifyListenersIfActive();
      return false;
    }
  }

  Future<bool> accept(ConnectionModel connection) {
    return _runAction(() => _repository.acceptRequest(connection.connectionId));
  }

  Future<bool> reject(ConnectionModel connection) {
    return _runAction(() => _repository.rejectRequest(connection.connectionId));
  }

  Future<bool> removeConnection(ConnectionModel connection) {
    return _runAction(
        () => _repository.removeConnection(connection.connectionId));
  }

  void clearError() {
    _errorMessage = null;
    _notifyListenersIfActive();
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    _notifyListenersIfActive();
    try {
      await action();
      _isLoading = false;
      _notifyListenersIfActive();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      _isLoading = false;
      _notifyListenersIfActive();
      return false;
    }
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
    _subscription?.cancel();
    super.dispose();
  }
}
