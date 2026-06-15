import 'package:cloud_firestore/cloud_firestore.dart';

enum ConnectionStatus {
  pending,
  accepted,
  rejected;

  static ConnectionStatus fromString(String value) {
    return ConnectionStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ConnectionStatus.pending,
    );
  }
}

class ConnectionModel {
  const ConnectionModel({
    required this.connectionId,
    required this.fromUserId,
    required this.fromName,
    required this.fromEmail,
    required this.toUserId,
    required this.toName,
    required this.toEmail,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String connectionId;
  final String fromUserId;
  final String fromName;
  final String fromEmail;
  final String toUserId;
  final String toName;
  final String toEmail;
  final ConnectionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ConnectionModel.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return ConnectionModel.fromMap(
        {...document.data(), 'connectionId': document.id});
  }

  factory ConnectionModel.fromMap(Map<String, dynamic> map) {
    return ConnectionModel(
      connectionId: map['connectionId'] as String? ?? '',
      fromUserId: map['fromUserId'] as String? ?? '',
      fromName: map['fromName'] as String? ?? '',
      fromEmail: map['fromEmail'] as String? ?? '',
      toUserId: map['toUserId'] as String? ?? '',
      toName: map['toName'] as String? ?? '',
      toEmail: map['toEmail'] as String? ?? '',
      status:
          ConnectionStatus.fromString(map['status'] as String? ?? 'pending'),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'connectionId': connectionId,
      'fromUserId': fromUserId,
      'fromName': fromName,
      'fromEmail': fromEmail,
      'toUserId': toUserId,
      'toName': toName,
      'toEmail': toEmail,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  bool involves(String userId) => fromUserId == userId || toUserId == userId;

  bool isIncomingFor(String userId) {
    return toUserId == userId && status == ConnectionStatus.pending;
  }

  bool isOutgoingFor(String userId) {
    return fromUserId == userId && status == ConnectionStatus.pending;
  }

  String otherUserId(String currentUserId) {
    return fromUserId == currentUserId ? toUserId : fromUserId;
  }

  String otherName(String currentUserId) {
    return fromUserId == currentUserId ? toName : fromName;
  }

  String otherEmail(String currentUserId) {
    return fromUserId == currentUserId ? toEmail : fromEmail;
  }

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.now();
  }
}
