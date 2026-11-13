/// What a notice is about, as the customer is allowed to know it.
///
/// The API sends ids and a kind only; the app words each notice itself, so no
/// agent identity can ever reach the customer through a notice.
enum NotificationKind { chatMessage, reservationStatus, other }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.conversationId,
    required this.reservationId,
    required this.detail,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['kind'] is! String ||
        json['read'] is! bool ||
        json['created_at'] is! String ||
        (json['conversation_id'] != null && json['conversation_id'] is! String) ||
        (json['reservation_id'] != null && json['reservation_id'] is! String) ||
        (json['detail'] != null && json['detail'] is! String)) {
      throw const FormatException('Notification fields are invalid');
    }
    return AppNotification(
      id: json['id']! as String,
      kind: switch (json['kind']! as String) {
        'chat_message' => NotificationKind.chatMessage,
        'reservation_status' => NotificationKind.reservationStatus,
        _ => NotificationKind.other,
      },
      conversationId: json['conversation_id'] as String?,
      reservationId: json['reservation_id'] as String?,
      detail: json['detail'] as String?,
      createdAt: DateTime.parse(json['created_at']! as String),
      read: json['read']! as bool,
    );
  }

  final String id;
  final NotificationKind kind;
  final String? conversationId;
  final String? reservationId;
  final String? detail;
  final DateTime createdAt;
  final bool read;

  AppNotification asRead() => AppNotification(
    id: id,
    kind: kind,
    conversationId: conversationId,
    reservationId: reservationId,
    detail: detail,
    createdAt: createdAt,
    read: true,
  );
}

class NotificationInbox {
  const NotificationInbox({required this.unread, required this.items});

  factory NotificationInbox.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['unread'] is! int ||
        json['items'] is! List<Object?>) {
      throw const FormatException('Notification inbox is invalid');
    }
    return NotificationInbox(
      unread: json['unread']! as int,
      items: (json['items']! as List<Object?>)
          .map(AppNotification.fromJson)
          .toList(growable: false),
    );
  }

  final int unread;
  final List<AppNotification> items;
}
