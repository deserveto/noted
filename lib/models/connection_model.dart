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

  factory ConnectionModel.fromMap(Map<String, dynamic> map) {
    return ConnectionModel(
      connectionId:
          (map['connectionId'] ?? map['connection_id']) as String? ?? '',
      fromUserId: (map['fromUserId'] ?? map['from_user_id']) as String? ?? '',
      fromName: (map['fromName'] ?? map['from_name']) as String? ?? '',
      fromEmail: (map['fromEmail'] ?? map['from_email']) as String? ?? '',
      toUserId: (map['toUserId'] ?? map['to_user_id']) as String? ?? '',
      toName: (map['toName'] ?? map['to_name']) as String? ?? '',
      toEmail: (map['toEmail'] ?? map['to_email']) as String? ?? '',
      status:
          ConnectionStatus.fromString(map['status'] as String? ?? 'pending'),
      createdAt: _readDate(map['createdAt'] ?? map['created_at']),
      updatedAt: _readDate(map['updatedAt'] ?? map['updated_at']),
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
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
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
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }
}
