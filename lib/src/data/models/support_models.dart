import 'package:DriveForme/src/data/utils/date_utils.dart';

class SupportTicket {
  SupportTicket(this.json);
  final Map<String, dynamic> json;
  String get id => json['_id']?.toString() ?? '';
  String get code => json['ticketId']?.toString() ?? '';
  String get subject => json['subject']?.toString() ?? '';
  String get description => json['description']?.toString() ?? '';
  String get status => json['status']?.toString() ?? '';
  bool get isOpen => status == 'pending';
  int get unread => (json['unreadForUser'] as num?)?.toInt() ?? 0;
  String get preview => json['lastMessagePreview']?.toString() ?? '';
  String? get assignedName {
    final admin = json['assignedTo'];
    return admin is Map ? admin['fullName']?.toString() : null;
  }
}

class SupportMessage {
  SupportMessage(this.json);
  final Map<String, dynamic> json;
  String get id => json['_id']?.toString() ?? '';
  String get content => json['content']?.toString() ?? '';
  String get senderType => json['senderType']?.toString() ?? '';
  bool get isUser => senderType == 'user';
  bool get isSystem => senderType == 'system';
  String get senderName {
    final sender = json['sender'];
    return sender is Map
        ? sender['fullName']?.toString() ?? 'Support'
        : 'Support';
  }

  DateTime? get createdAt => parseApiDateTime(json['createdAt']);
  bool get isRead => json['readAt'] != null;
}
