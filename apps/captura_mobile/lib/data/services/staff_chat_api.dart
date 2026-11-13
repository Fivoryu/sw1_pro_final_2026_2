import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/staff_chat.dart';
import 'staff_auth_failure.dart';

/// HTTP client for the F14.6 staff chat routes (`/api/v1/staff/chat`) and the
/// agency's agent list used to pick a reassignment target.
///
/// Every call carries the in-memory access token of the staff session. Bodies
/// are decoded as UTF-8 explicitly, like the other staff clients.
class StaffChatApi {
  StaffChatApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const String _chatPath = '/api/v1/staff/chat';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<List<StaffConversation>> listConversations({
    required String accessToken,
  }) async {
    final json = await _send(
      'GET',
      '$_chatPath/conversations',
      accessToken: accessToken,
    );
    return _parse(() => parseConversationList(json));
  }

  Future<StaffMessagePage> listMessages({
    required String accessToken,
    required String conversationId,
    int after = 0,
  }) async {
    final json = await _send(
      'GET',
      '$_chatPath/conversations/$conversationId/messages',
      accessToken: accessToken,
      query: {'after': '$after', 'limit': '100'},
    );
    return _parse(() => StaffMessagePage.fromJson(_object(json)));
  }

  Future<StaffChatMessage> sendMessage({
    required String accessToken,
    required String conversationId,
    required String body,
  }) async {
    final json = await _send(
      'POST',
      '$_chatPath/conversations/$conversationId/messages',
      accessToken: accessToken,
      body: {'body': body},
    );
    return _parse(() => StaffChatMessage.fromJson(_object(json)));
  }

  /// Reassigns to [agentId], or to the least busy agent when it is null.
  Future<StaffConversation> reassign({
    required String accessToken,
    required String conversationId,
    String? agentId,
  }) async {
    final json = await _send(
      'POST',
      '$_chatPath/conversations/$conversationId/reassign',
      accessToken: accessToken,
      body: {if (agentId != null) 'agent_id': agentId},
    );
    return _parse(() => StaffConversation.fromJson(_object(json)));
  }

  Future<void> reportCustomer({
    required String accessToken,
    required String conversationId,
    required String reason,
  }) async {
    await _send(
      'POST',
      '$_chatPath/conversations/$conversationId/report',
      accessToken: accessToken,
      body: {'body': reason},
    );
  }

  Future<List<ChatAgent>> listAgents({required String accessToken}) async {
    final json = await _send(
      'GET',
      '/api/v1/agencies/agents',
      accessToken: accessToken,
      query: {'limit': '100'},
    );
    return _parse(() => parseAgentList(json));
  }

  static Map<String, Object?> _object(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object');
    }
    return json;
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw malformedResponseFailure();
    }
  }

  Future<Object?> _send(
    String method,
    String path, {
    required String accessToken,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw failureFromResponse(statusCode: response.statusCode, body: text);
    }
    if (text.isEmpty) throw malformedResponseFailure();
    try {
      return jsonDecode(text);
    } on FormatException {
      throw malformedResponseFailure();
    }
  }
}
