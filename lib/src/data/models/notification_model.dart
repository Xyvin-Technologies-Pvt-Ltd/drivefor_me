import 'package:DriveForme/src/data/utils/date_utils.dart';

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    this.payload = const {},
    this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    return NotificationModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      isRead: json['isRead'] == true || json['read'] == true,
      payload: payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : const {},
      createdAt: _parseDate(json['createdAt']),
    );
  }

  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return formatLocalDateTime(createdAt!, 'd MMM');
  }

  String get dateSectionLabel {
    if (createdAt == null) return 'Recent';
    final local = createdAt!.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    return formatLocalDateTime(local, 'EEE, d MMM');
  }

  static DateTime? _parseDate(dynamic value) => parseApiDateTime(value);
}
