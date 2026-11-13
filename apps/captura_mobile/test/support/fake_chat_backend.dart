import 'dart:convert';

import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_chat_api.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_staff_backend.dart';

const chatBaseUrl = 'https://api.example.test';

/// Wire JSON of a staff conversation.
Map<String, Object?> conversationJson(
  String id, {
  String email = 'cliente@example.test',
  String status = 'unclaimed',
  bool mine = false,
  bool readOnly = false,
  bool needsAdmin = false,
  bool overdue = false,
  String? lastMessageAt = '2026-11-13T15:30:00Z',
  String? agentEmail,
}) => {
  'id': id,
  'listing_id': 'listing-1',
  'customer_email': email,
  'status': status,
  'mine': mine,
  'read_only': readOnly,
  'needs_admin': needsAdmin,
  'overdue': overdue,
  'created_at': '2026-11-13T10:00:00Z',
  'last_message_at': lastMessageAt,
  if (agentEmail != null) 'agent_email': agentEmail,
};

/// Wire JSON of a staff message.
Map<String, Object?> messageJson(
  int id, {
  String sender = 'customer',
  bool mine = false,
  String body = 'Hola',
  String? authorEmail,
}) => {
  'id': id,
  'sender': sender,
  'mine': mine,
  'body': body,
  'created_at': '2026-11-13T10:00:00Z',
  if (authorEmail != null) 'author_email': authorEmail,
};

/// In-memory stand-in for the staff chat routes.
class FakeChatBackend {
  bool offline = false;

  /// When set, sending answers 409 with this detail.
  String? sendConflictDetail;

  /// When true, listing messages answers 404 (conversation not visible).
  bool messagesNotFound = false;

  List<Map<String, Object?>> conversations = [];
  List<Map<String, Object?>> messages = [];
  bool readOnly = false;
  int _next = 1000;

  final List<http.Request> requests = [];
  final List<Map<String, Object?>> sentBodies = [];

  http.Client get client => MockClient(_handle);

  static http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    final method = request.method;
    if (path == '/api/v1/staff/chat/conversations' && method == 'GET') {
      return _json({'conversations': conversations}, 200);
    }
    if (path == '/api/v1/agencies/agents') {
      return _json({
        'agents': [
          {'id': 'agent-9', 'email': 'otro@example.test', 'active': true},
          {'id': 'agent-8', 'email': 'baja@example.test', 'active': false},
        ],
      }, 200);
    }
    final messagesRoute = RegExp(
      r'^/api/v1/staff/chat/conversations/([^/]+)/messages$',
    ).firstMatch(path);
    if (messagesRoute != null && method == 'GET') {
      if (messagesNotFound) {
        return _json({'detail': 'Not found', 'code': 'not_found'}, 404);
      }
      final after = int.parse(request.url.queryParameters['after'] ?? '0');
      return _json({
        'messages': [
          for (final message in messages)
            if ((message['id']! as int) > after) message,
        ],
        'read_only': readOnly,
      }, 200);
    }
    if (messagesRoute != null && method == 'POST') {
      final detail = sendConflictDetail;
      if (detail != null) {
        return _json({'detail': detail, 'code': 'conflict'}, 409);
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      sentBodies.add(body);
      final message = messageJson(
        _next++,
        sender: 'agent',
        mine: true,
        body: body['body']! as String,
      );
      messages.add(message);
      return _json(message, 201);
    }
    if (path.endsWith('/reassign') && method == 'POST') {
      sentBodies.add(jsonDecode(request.body) as Map<String, Object?>);
      return _json(
        conversationJson(
          'c1',
          status: 'claimed',
          agentEmail: 'otro@example.test',
        ),
        200,
      );
    }
    if (path.endsWith('/report') && method == 'POST') {
      sentBodies.add(jsonDecode(request.body) as Map<String, Object?>);
      return _json({'id': 'report-1'}, 201);
    }
    return http.Response('', 404);
  }
}

/// A signed-in staff session plus the chat API wired to [backend].
Future<({StaffSessionController session, StaffChatApi api})> signedInChat(
  FakeChatBackend backend, {
  String role = 'agent',
}) async {
  final session = StaffSessionController(
    api: StaffAuthApi(
      baseUrl: chatBaseUrl,
      client: FakeStaffBackend(role: role).client,
    ),
    credentialStore: InMemoryStaffCredentialStore(),
  );
  await session.restore();
  await session.startLogin(email: 'agent@example.test', password: 'x');
  await session.submitCode('123456');
  return (
    session: session,
    api: StaffChatApi(baseUrl: chatBaseUrl, client: backend.client),
  );
}
