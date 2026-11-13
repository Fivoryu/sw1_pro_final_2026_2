/// Who wrote a chat message, as the staff API names it.
enum ChatSender {
  customer('customer'),
  agent('agent'),
  admin('admin');

  const ChatSender(this.wireName);

  final String wireName;

  static ChatSender fromWire(Object? value) => ChatSender.values.firstWhere(
    (sender) => sender.wireName == value,
    orElse: () {
      throw FormatException('Unknown chat sender: $value');
    },
  );
}

/// Ownership of a conversation: nobody answered yet, or an agent took it.
enum ConversationStatus {
  unclaimed('unclaimed'),
  claimed('claimed');

  const ConversationStatus(this.wireName);

  final String wireName;

  static ConversationStatus fromWire(Object? value) =>
      ConversationStatus.values.firstWhere(
        (status) => status.wireName == value,
        orElse: () {
          throw FormatException('Unknown conversation status: $value');
        },
      );
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Missing string "$key"');
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid string "$key"');
  return value;
}

bool _bool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Missing bool "$key"');
  return value;
}

Map<String, Object?> _map(Object? value, String what) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Invalid $what object');
  }
  return value;
}

/// A conversation as the agency staff sees it (F14.6).
///
/// [agentId] and [agentEmail] are only present for the agency admin; the app
/// renders exactly what the API returns.
class StaffConversation {
  const StaffConversation({
    required this.id,
    required this.listingId,
    required this.customerEmail,
    required this.status,
    required this.mine,
    required this.readOnly,
    required this.needsAdmin,
    required this.overdue,
    required this.createdAt,
    required this.lastMessageAt,
    this.agentId,
    this.agentEmail,
  });

  factory StaffConversation.fromJson(Map<String, Object?> json) {
    final lastMessageAt = _optionalString(json, 'last_message_at');
    return StaffConversation(
      id: _string(json, 'id'),
      listingId: _string(json, 'listing_id'),
      customerEmail: _string(json, 'customer_email'),
      status: ConversationStatus.fromWire(json['status']),
      mine: _bool(json, 'mine'),
      readOnly: _bool(json, 'read_only'),
      needsAdmin: _bool(json, 'needs_admin'),
      overdue: _bool(json, 'overdue'),
      createdAt: DateTime.parse(_string(json, 'created_at')),
      lastMessageAt: lastMessageAt == null
          ? null
          : DateTime.parse(lastMessageAt),
      agentId: _optionalString(json, 'agent_id'),
      agentEmail: _optionalString(json, 'agent_email'),
    );
  }

  final String id;
  final String listingId;
  final String customerEmail;
  final ConversationStatus status;
  final bool mine;
  final bool readOnly;
  final bool needsAdmin;
  final bool overdue;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final String? agentId;
  final String? agentEmail;

  StaffConversation copyWith({
    ConversationStatus? status,
    bool? mine,
    bool? readOnly,
  }) => StaffConversation(
    id: id,
    listingId: listingId,
    customerEmail: customerEmail,
    status: status ?? this.status,
    mine: mine ?? this.mine,
    readOnly: readOnly ?? this.readOnly,
    needsAdmin: needsAdmin,
    overdue: overdue,
    createdAt: createdAt,
    lastMessageAt: lastMessageAt,
    agentId: agentId,
    agentEmail: agentEmail,
  );
}

/// One chat message; [authorEmail] is present only for the agency admin.
class StaffChatMessage {
  const StaffChatMessage({
    required this.id,
    required this.sender,
    required this.mine,
    required this.body,
    required this.createdAt,
    this.authorEmail,
  });

  factory StaffChatMessage.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! int) throw const FormatException('Missing int "id"');
    return StaffChatMessage(
      id: id,
      sender: ChatSender.fromWire(json['sender']),
      mine: _bool(json, 'mine'),
      body: _string(json, 'body'),
      createdAt: DateTime.parse(_string(json, 'created_at')),
      authorEmail: _optionalString(json, 'author_email'),
    );
  }

  final int id;
  final ChatSender sender;
  final bool mine;
  final String body;
  final DateTime createdAt;
  final String? authorEmail;
}

/// A page of messages plus the conversation's read-only flag.
class StaffMessagePage {
  const StaffMessagePage({required this.messages, required this.readOnly});

  factory StaffMessagePage.fromJson(Map<String, Object?> json) {
    final messages = json['messages'];
    if (messages is! List<Object?>) {
      throw const FormatException('Missing list "messages"');
    }
    return StaffMessagePage(
      messages: [
        for (final item in messages)
          StaffChatMessage.fromJson(_map(item, 'message')),
      ],
      readOnly: _bool(json, 'read_only'),
    );
  }

  final List<StaffChatMessage> messages;
  final bool readOnly;
}

/// An agent of the agency, as `GET /api/v1/agencies/agents` lists them.
class ChatAgent {
  const ChatAgent({
    required this.id,
    required this.email,
    required this.active,
  });

  factory ChatAgent.fromJson(Map<String, Object?> json) => ChatAgent(
    id: _string(json, 'id'),
    email: _string(json, 'email'),
    active: _bool(json, 'active'),
  );

  final String id;
  final String email;
  final bool active;
}

/// Parses `{"conversations": [...]}`.
List<StaffConversation> parseConversationList(Object? json) {
  final list = _map(json, 'conversation list')['conversations'];
  if (list is! List<Object?>) {
    throw const FormatException('Missing list "conversations"');
  }
  return [
    for (final item in list)
      StaffConversation.fromJson(_map(item, 'conversation')),
  ];
}

/// Parses `{"agents": [...]}`.
List<ChatAgent> parseAgentList(Object? json) {
  final list = _map(json, 'agent list')['agents'];
  if (list is! List<Object?>) {
    throw const FormatException('Missing list "agents"');
  }
  return [for (final item in list) ChatAgent.fromJson(_map(item, 'agent'))];
}
