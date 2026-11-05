import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/connection_repository.dart';
import 'package:noted/viewmodels/connection_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invite falls back to email only for a missing account', () async {
    final repo = _FakeConnectionRepository(failureCode: 'not-found');
    final vm = ConnectionViewModel(repo)
      ..bindUser(_testUser(), notifyOnBind: false);
    expect(await vm.invite('new@example.com'), true);
    expect(repo.invitedEmails, ['new@example.com']);
    vm.dispose();
  });
  test('invite preserves privacy denial instead of emailing around it',
      () async {
    final repo = _FakeConnectionRepository(failureCode: 'permission-denied');
    final vm = ConnectionViewModel(repo)
      ..bindUser(_testUser(), notifyOnBind: false);
    expect(await vm.invite('private@example.com'), false);
    expect(repo.invitedEmails, isEmpty);
    vm.dispose();
  });
  test('sendRequest does not eagerly notify listeners on success', () async {
    final repository = _FakeConnectionRepository();
    final viewModel = ConnectionViewModel(repository);
    var notificationCount = 0;
    viewModel.addListener(() => notificationCount++);

    viewModel.bindUser(_testUser(), notifyOnBind: false);
    final sent = await viewModel.sendRequest('friend@example.com');

    expect(sent, isTrue);
    expect(repository.sentEmails, ['friend@example.com']);
    expect(notificationCount, 0);
  });

  test('sendRequest reports repository errors', () async {
    final repository = _FakeConnectionRepository(shouldFail: true);
    final viewModel = ConnectionViewModel(repository);
    var notificationCount = 0;
    viewModel.addListener(() => notificationCount++);

    viewModel.bindUser(_testUser(), notifyOnBind: false);
    final sent = await viewModel.sendRequest('friend@example.com');
    await Future.delayed(Duration.zero);

    expect(sent, isFalse);
    expect(viewModel.errorMessage, 'No user found with that email.');
    expect(notificationCount, 1);
  });

  test('repeated refreshes share one replacement subscription', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);

    repository.emit(0, const []);
    await Future<void>.delayed(Duration.zero);

    viewModel
      ..retry()
      ..retry();

    expect(repository.watchedUserIds, ['user-1', 'user-1']);
    await Future<void>.delayed(Duration.zero);
    expect(repository.cancelledWatches, [0]);
    viewModel.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(repository.cancelledWatches, [0, 1]);
  });

  test('failed refresh ends loading and a later refresh clears the error',
      () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);

    repository.emit(0, const []);
    await Future<void>.delayed(Duration.zero);
    viewModel.retry();
    repository.emitError(1, StateError('offline'));
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, contains('offline'));

    viewModel.retry();
    repository.emit(2, const []);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    viewModel.dispose();
  });

  test('a closed refresh ends loading with a recoverable error', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);

    await repository.close(0);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNotNull);
    viewModel.dispose();
  });

  test('refresh after an invite exposes the incoming request', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);

    repository.emit(0, const []);
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.incomingRequests, isEmpty);

    viewModel.retry();
    repository.emit(1, [_incomingConnection()]);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.incomingRequests, hasLength(1));
    expect(viewModel.incomingRequests.single.connectionId, 'incoming');
    viewModel.dispose();
  });

  test('accept updates the visible state when no realtime event arrives',
      () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);

    repository.emit(0, [_incomingConnection()]);
    await Future<void>.delayed(Duration.zero);

    expect(await viewModel.accept(_incomingConnection()), isTrue);
    expect(viewModel.incomingRequests, isEmpty);
    expect(viewModel.acceptedConnections, hasLength(1));
    viewModel.dispose();
  });

  test('decline removes the request when no realtime event arrives', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);

    repository.emit(0, [_incomingConnection()]);
    await Future<void>.delayed(Duration.zero);

    expect(await viewModel.reject(_incomingConnection()), isTrue);
    expect(viewModel.incomingRequests, isEmpty);
    viewModel.dispose();
  });

  test('delayed action after account switch does not complete successfully',
      () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);
    repository.emit(0, const []);
    await Future<void>.delayed(Duration.zero);
    final action = Completer<void>();
    repository.actionGate = action;

    final accepted = viewModel.accept(_incomingConnection());
    viewModel.bindUser(_testUser(uid: 'user-2'), notifyOnBind: false);
    action.complete();

    expect(await accepted, isFalse);
    expect(viewModel.user?.uid, 'user-2');
    expect(viewModel.connections, isEmpty);
    viewModel.dispose();
  });

  test('delayed action after disposal does not report success', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);
    final action = Completer<void>();
    repository.actionGate = action;

    final accepted = viewModel.accept(_incomingConnection());
    viewModel.dispose();
    action.complete();

    expect(await accepted, isFalse);
  });

  test('a second action cannot duplicate a delayed accept', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);
    final action = Completer<void>();
    repository.actionGate = action;

    final first = viewModel.accept(_incomingConnection());
    final second = viewModel.accept(_incomingConnection());

    expect(repository.acceptedIds, ['incoming']);
    action.complete();
    expect(await first, isTrue);
    expect(await second, isFalse);
    viewModel.dispose();
  });

  test('a delayed send cannot update the next account', () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);
    final action = Completer<void>();
    repository.actionGate = action;

    final sent = viewModel.sendRequest('friend@example.com');
    viewModel.bindUser(_testUser(uid: 'user-2'), notifyOnBind: false);
    action.complete();

    expect(await sent, isFalse);
    expect(viewModel.errorMessage, isNull);
    viewModel.dispose();
  });

  test('ending an action leaves loading active while refresh is pending',
      () async {
    final repository = _FakeConnectionRepository(autoEmitInitial: false);
    final viewModel = ConnectionViewModel(repository)
      ..bindUser(_testUser(), notifyOnBind: false);
    repository.emit(0, const []);
    await Future<void>.delayed(Duration.zero);
    final action = Completer<void>();
    repository.actionGate = action;

    final accepted = viewModel.accept(_incomingConnection());
    viewModel.refresh();
    action.complete();
    expect(await accepted, isTrue);

    expect(viewModel.isLoading, isTrue);
    repository.emit(1, [_incomingConnection()]);
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.isLoading, isFalse);
    viewModel.dispose();
  });
}

UserModel _testUser({String uid = 'user-1'}) {
  return UserModel(
    uid: uid,
    name: 'Sang',
    email: 'sang@example.com',
    createdAt: DateTime(2026, 6, 14),
  );
}

ConnectionModel _incomingConnection() {
  return ConnectionModel(
    connectionId: 'incoming',
    fromUserId: 'sender',
    fromName: 'Alex',
    fromEmail: 'alex@example.com',
    toUserId: 'user-1',
    toName: 'Sang',
    toEmail: 'sang@example.com',
    status: ConnectionStatus.pending,
    createdAt: DateTime(2026, 11, 5),
    updatedAt: DateTime(2026, 11, 5),
  );
}

class _FakeConnectionRepository implements ConnectionRepository {
  @override
  Future<void> inviteByEmail(String email) async {
    invitedEmails.add(email);
  }

  _FakeConnectionRepository({
    this.shouldFail = false,
    this.failureCode,
    this.autoEmitInitial = true,
  });

  final bool shouldFail;
  final String? failureCode;
  final bool autoEmitInitial;
  final invitedEmails = <String>[];
  final List<String> sentEmails = [];
  final watchedUserIds = <String>[];
  final cancelledWatches = <int>[];
  final acceptedIds = <String>[];
  final _watches = <StreamController<List<ConnectionModel>>>[];
  Completer<void>? actionGate;

  void emit(int watch, List<ConnectionModel> connections) {
    if (!_watches[watch].isClosed) {
      _watches[watch].add(connections);
    }
  }

  void emitError(int watch, Object error) {
    if (!_watches[watch].isClosed) {
      _watches[watch].addError(error);
    }
  }

  Future<void> close(int watch) => _watches[watch].close();

  @override
  Future<void> sendRequest({
    required UserModel fromUser,
    required String targetEmail,
  }) async {
    await actionGate?.future;
    if (failureCode != null) {
      throw ConnectionException('Request denied.', code: failureCode);
    }
    if (shouldFail) {
      throw const ConnectionException('No user found with that email.');
    }
    sentEmails.add(targetEmail);
  }

  @override
  Future<void> acceptRequest(String connectionId) async {
    acceptedIds.add(connectionId);
    await actionGate?.future;
  }

  @override
  Future<void> resendRequest(String connectionId) async {}

  @override
  Future<void> rejectRequest(String connectionId) async {
    await actionGate?.future;
  }

  @override
  Future<void> removeConnection(String connectionId) async {
    await actionGate?.future;
  }

  @override
  Future<UserModel?> findUserByEmail(String email) async {
    return null;
  }

  @override
  Stream<List<ConnectionModel>> watchConnections(String userId) {
    watchedUserIds.add(userId);
    final watch = _watches.length;
    final controller = StreamController<List<ConnectionModel>>(
      onCancel: () => cancelledWatches.add(watch),
    );
    _watches.add(controller);
    if (autoEmitInitial) {
      scheduleMicrotask(() {
        if (!controller.isClosed) controller.add(const []);
      });
    }
    return controller.stream;
  }
}
