import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/connection_repository.dart';
import 'package:noted/viewmodels/connection_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}

UserModel _testUser() {
  return UserModel(
    uid: 'user-1',
    name: 'Sang',
    email: 'sang@example.com',
    createdAt: DateTime(2026, 6, 14),
  );
}

class _FakeConnectionRepository implements ConnectionRepository {
  _FakeConnectionRepository({this.shouldFail = false});

  final bool shouldFail;
  final List<String> sentEmails = [];

  @override
  Future<void> sendRequest({
    required UserModel fromUser,
    required String targetEmail,
  }) async {
    if (shouldFail) {
      throw const ConnectionException('No user found with that email.');
    }
    sentEmails.add(targetEmail);
  }

  @override
  Future<void> acceptRequest(String connectionId) async {}

  @override
  Future<void> rejectRequest(String connectionId) async {}

  @override
  Future<void> removeConnection(String connectionId) async {}

  @override
  Future<UserModel?> findUserByEmail(String email) async {
    return null;
  }

  @override
  Stream<List<ConnectionModel>> watchConnections(String userId) {
    return const Stream.empty();
  }
}
