import 'dart:convert';

import 'package:cliente_mobile/data/services/customer_chat_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Programmable stand-in for `/api/v1/customer/chat`.
class FakeChatBackend {
  final List<Map<String, Object?>> messages = [];
  final List<String> requests = [];
  final List<String> reports = [];
  bool readOnly = false;
  bool blocked = false;
  bool offline = false;
  bool openBlocked = false;
  int _nextId = 1;

  CustomerChatApi get api => CustomerChatApi(
    baseUrl: 'https://api.example.test',
    accessTokenProvider: () async => 'token',
    client: MockClient(_handle),
  );

  static Map<String, Object?> conversationJson({
    String id = 'conv-1',
    bool readOnly = false,
  }) => {
    'id': id,
    'listing_id': 'listing-1',
    'agency_name': 'Andina Inmuebles',
    'read_only': readOnly,
    'created_at': '2026-11-01T10:00:00Z',
    'last_message_at': null,
  };

  Map<String, Object?> add(String sender, String body) {
    final message = {
      'id': _nextId++,
      'sender': sender,
      'body': body,
      'created_at': '2026-11-01T10:00:00Z',
    };
    messages.add(message);
    return message;
  }

  static http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}'
        '${request.url.hasQuery ? '?${request.url.query}' : ''}');
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    const root = '/api/v1/customer/chat';
    if (path == '$root/listings/listing-1/conversation') {
      return openBlocked
          ? _json({'detail': 'blocked', 'code': 'forbidden'}, 403)
          : _json(conversationJson(readOnly: readOnly), 201);
    }
    if (path == '$root/conversations') {
      return _json({
        'conversations': [conversationJson(readOnly: readOnly)],
      }, 200);
    }
    if (path == '$root/conversations/conv-1/messages') {
      if (request.method == 'GET') {
        final after = int.parse(request.url.queryParameters['after'] ?? '0');
        final limit = int.parse(request.url.queryParameters['limit'] ?? '50');
        final page = messages
            .where((m) => (m['id']! as int) > after)
            .take(limit)
            .toList();
        return _json({'messages': page, 'read_only': readOnly}, 200);
      }
      if (blocked) {
        return _json({'detail': 'blocked', 'code': 'forbidden'}, 403);
      }
      if (readOnly) {
        return _json({'detail': 'read-only', 'code': 'conflict'}, 409);
      }
      final body = (jsonDecode(request.body) as Map<String, Object?>)['body'];
      return _json(add('customer', body! as String), 201);
    }
    if (path == '$root/conversations/conv-1/report') {
      reports.add((jsonDecode(request.body) as Map<String, Object?>)['body']! as String);
      return _json({'id': 'report-1'}, 201);
    }
    return http.Response('', 404);
  }
}
