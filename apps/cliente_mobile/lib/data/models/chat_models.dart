/// Who wrote a chat message, as the customer is allowed to know it.
///
/// The API never reveals which agent answered: every reply is the agency's.
enum ChatSender { customer, agency }

DateTime _parseDate(Object? value) {
  if (value is! String) throw const FormatException('Date is invalid');
  return DateTime.parse(value);
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.listingId,
    required this.agencyName,
    required this.readOnly,
    required this.createdAt,
    required this.lastMessageAt,
  });

  factory ChatConversation.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['listing_id'] is! String ||
        json['agency_name'] is! String ||
        json['read_only'] is! bool ||
        (json['last_message_at'] != null && json['last_message_at'] is! String)) {
      throw const FormatException('Conversation fields are invalid');
    }
    final last = json['last_message_at'] as String?;
    return ChatConversation(
      id: json['id']! as String,
      listingId: json['listing_id']! as String,
      agencyName: json['agency_name']! as String,
      readOnly: json['read_only']! as bool,
      createdAt: _parseDate(json['created_at']),
      lastMessageAt: last == null ? null : DateTime.parse(last),
    );
  }

  final String id;
  final String listingId;
  final String agencyName;
  final bool readOnly;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! int ||
        json['sender'] is! String ||
        json['body'] is! String) {
      throw const FormatException('Message fields are invalid');
    }
    final sender = switch (json['sender']) {
      'customer' => ChatSender.customer,
      'agency' => ChatSender.agency,
      _ => throw const FormatException('Message sender is invalid'),
    };
    return ChatMessage(
      id: json['id']! as int,
      sender: sender,
      body: json['body']! as String,
      createdAt: _parseDate(json['created_at']),
    );
  }

  final int id;
  final ChatSender sender;
  final String body;
  final DateTime createdAt;
}

class ChatMessagePage {
  const ChatMessagePage({required this.messages, required this.readOnly});

  factory ChatMessagePage.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['messages'] is! List<Object?> ||
        json['read_only'] is! bool) {
      throw const FormatException('Message page is invalid');
    }
    return ChatMessagePage(
      messages: (json['messages']! as List<Object?>)
          .map(ChatMessage.fromJson)
          .toList(growable: false),
      readOnly: json['read_only']! as bool,
    );
  }

  final List<ChatMessage> messages;
  final bool readOnly;
}
