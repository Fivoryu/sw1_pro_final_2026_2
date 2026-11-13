/// What a staff notice is about. The API sends ids and a kind only; the app
/// words each notice itself.
enum StaffNotificationKind {
  chatMessage,
  chatAssigned,
  chatNeedsAdmin,
  chatOverdue,
  reservationStatus,
  other,
}

class StaffNotification {
  const StaffNotification({
    required this.id,
    required this.kind,
    required this.conversationId,
    required this.reservationId,
    required this.detail,
    required this.createdAt,
    required this.read,
  });

  factory StaffNotification.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['kind'] is! String ||
        json['read'] is! bool ||
        json['created_at'] is! String ||
        (json['conversation_id'] != null &&
            json['conversation_id'] is! String) ||
        (json['reservation_id'] != null && json['reservation_id'] is! String) ||
        (json['detail'] != null && json['detail'] is! String)) {
      throw const FormatException('Notification fields are invalid');
    }
    return StaffNotification(
      id: json['id']! as String,
      kind: switch (json['kind']! as String) {
        'chat_message' => StaffNotificationKind.chatMessage,
        'chat_assigned' => StaffNotificationKind.chatAssigned,
        'chat_needs_admin' => StaffNotificationKind.chatNeedsAdmin,
        'chat_overdue' => StaffNotificationKind.chatOverdue,
        'reservation_status' => StaffNotificationKind.reservationStatus,
        _ => StaffNotificationKind.other,
      },
      conversationId: json['conversation_id'] as String?,
      reservationId: json['reservation_id'] as String?,
      detail: json['detail'] as String?,
      createdAt: DateTime.parse(json['created_at']! as String),
      read: json['read']! as bool,
    );
  }

  final String id;
  final StaffNotificationKind kind;
  final String? conversationId;
  final String? reservationId;
  final String? detail;
  final DateTime createdAt;
  final bool read;

  bool get opensConversation => conversationId != null;

  StaffNotification asRead() => StaffNotification(
    id: id,
    kind: kind,
    conversationId: conversationId,
    reservationId: reservationId,
    detail: detail,
    createdAt: createdAt,
    read: true,
  );
}

class StaffNotificationInbox {
  const StaffNotificationInbox({required this.unread, required this.items});

  factory StaffNotificationInbox.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['unread'] is! int ||
        json['items'] is! List<Object?>) {
      throw const FormatException('Notification inbox is invalid');
    }
    return StaffNotificationInbox(
      unread: json['unread']! as int,
      items: (json['items']! as List<Object?>)
          .map(StaffNotification.fromJson)
          .toList(growable: false),
    );
  }

  final int unread;
  final List<StaffNotification> items;
}
