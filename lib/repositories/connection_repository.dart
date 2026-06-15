import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/connection_model.dart';
import '../models/user_model.dart';
import '../services/firebase_service.dart';

class ConnectionRepository {
  ConnectionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseService.firestore;

  final FirebaseFirestore _firestore;

  Stream<List<ConnectionModel>> watchConnections(String userId) {
    final controller = StreamController<List<ConnectionModel>>();
    var fromConnections = <ConnectionModel>[];
    var toConnections = <ConnectionModel>[];

    void emit() {
      final byId = <String, ConnectionModel>{};
      for (final connection in [...fromConnections, ...toConnections]) {
        byId[connection.connectionId] = connection;
      }
      final values = byId.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!controller.isClosed) {
        controller.add(values);
      }
    }

    final fromSub = _connections
        .where('fromUserId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      fromConnections =
          snapshot.docs.map(ConnectionModel.fromDocument).toList();
      emit();
    }, onError: controller.addError);

    final toSub = _connections
        .where('toUserId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      toConnections = snapshot.docs.map(ConnectionModel.fromDocument).toList();
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await fromSub.cancel();
      await toSub.cancel();
    };

    return controller.stream;
  }

  Future<void> sendRequest({
    required UserModel fromUser,
    required String targetEmail,
  }) async {
    final normalizedEmail = targetEmail.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw const ConnectionException('Enter a connection email.');
    }
    if (normalizedEmail == fromUser.email.trim().toLowerCase()) {
      throw const ConnectionException('You cannot connect with yourself.');
    }

    final targetUser = await findUserByEmail(normalizedEmail);
    if (targetUser == null) {
      throw const ConnectionException('No user found with that email.');
    }

    final sent = await _connections
        .where('fromUserId', isEqualTo: fromUser.uid)
        .where('toUserId', isEqualTo: targetUser.uid)
        .get();

    final received = await _connections
        .where('fromUserId', isEqualTo: targetUser.uid)
        .where('toUserId', isEqualTo: fromUser.uid)
        .get();

    final allDocs = [...sent.docs, ...received.docs];
    for (final doc in allDocs) {
      final connection = ConnectionModel.fromDocument(doc);
      if (connection.status != ConnectionStatus.rejected) {
        throw const ConnectionException('A connection already exists.');
      }
    }

    final doc = _connections.doc();
    final now = DateTime.now();
    final connection = ConnectionModel(
      connectionId: doc.id,
      fromUserId: fromUser.uid,
      fromName: fromUser.name,
      fromEmail: fromUser.email,
      toUserId: targetUser.uid,
      toName: targetUser.name,
      toEmail: targetUser.email,
      status: ConnectionStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    await doc.set(connection.toMap());
  }

  Future<void> acceptRequest(String connectionId) {
    return _connections.doc(connectionId).update({
      'status': ConnectionStatus.accepted.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> rejectRequest(String connectionId) {
    return _connections.doc(connectionId).update({
      'status': ConnectionStatus.rejected.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> removeConnection(String connectionId) {
    return _connections.doc(connectionId).delete();
  }

  Future<UserModel?> findUserByEmail(String email) async {
    final snapshot = await _firestore
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return UserModel.fromMap(snapshot.docs.first.data());
  }

  CollectionReference<Map<String, dynamic>> get _connections {
    return _firestore.collection('connectionRequests');
  }
}

class ConnectionException implements Exception {
  const ConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
