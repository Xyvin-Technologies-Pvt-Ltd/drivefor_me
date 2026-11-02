import 'package:DriveForme/src/data/utils/date_utils.dart';

class ChatMessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime? createdAt;
  final bool isMine;

  const ChatMessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.createdAt,
    this.isMine = false,
  });

  factory ChatMessageModel.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final senderId = _userId(json['sender']) ??
        json['senderId']?.toString() ??
        '';
    return ChatMessageModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      senderId: senderId,
      receiverId: _userId(json['receiver']) ??
          json['receiverId']?.toString() ??
          '',
      content: json['content']?.toString() ?? json['message']?.toString() ?? '',
      createdAt: _parseDate(json['createdAt']),
      isMine: currentUserId != null && senderId == currentUserId,
    );
  }

  static String? _userId(dynamic user) {
    if (user is Map) {
      final id = user['_id'] ?? user['id'] ?? user['userId'];
      if (id != null) return id.toString();
    }
    if (user != null) return user.toString();
    return null;
  }

  static DateTime? _parseDate(dynamic value) => parseApiDateTime(value);
}
