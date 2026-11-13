import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import 'customer_auth_failure.dart';
import 'customer_booking_api.dart' show AccessTokenProvider;

/// Client for `/api/v1/customer/chat`. Every call uses the customer session
/// supplied by [accessTokenProvider]. Failures reuse [CustomerAuthFailure]:
/// 403 means the agency blocked the customer, 409 means read-only.
class CustomerChatApi {
  CustomerChatApi({
    required String baseUrl,
    required this.accessTokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const _root = '/api/v1/customer/chat';

  final String _baseUrl;
  final AccessTokenProvider accessTokenProvider;
  final http.Client _client;
  final Duration timeout;

  Future<ChatConversation> openConversation(String listingId) async {
    final body = await _send(
      'POST',
      '$_root/listings/${Uri.encodeComponent(listingId)}/conversation',
    );
    return _parse(() => ChatConversation.fromJson(body));
  }

  Future<List<ChatConversation>> listConversations() async {
    final body = await _send('GET', '$_root/conversations');
    return _parse(() {
      if (body is! Map<String, Object?> ||
          body['conversations'] is! List<Object?>) {
        throw const FormatException('Conversation list is invalid');
      }
      return (body['conversations']! as List<Object?>)
          .map(ChatConversation.fromJson)
          .toList(growable: false);
    });
  }

  Future<ChatMessagePage> listMessages(
    String conversationId, {
    int after = 0,
    int limit = 50,
  }) async {
    final body = await _send(
      'GET',
      '$_root/conversations/${Uri.encodeComponent(conversationId)}/messages'
      '?after=$after&limit=$limit',
    );
    return _parse(() => ChatMessagePage.fromJson(body));
  }

  Future<ChatMessage> sendMessage(String conversationId, String text) async {
    final body = await _send(
      'POST',
      '$_root/conversations/${Uri.encodeComponent(conversationId)}/messages',
      body: {'body': text},
    );
    return _parse(() => ChatMessage.fromJson(body));
  }

  Future<void> reportConversation(String conversationId, String reason) async {
    await _send(
      'POST',
      '$_root/conversations/${Uri.encodeComponent(conversationId)}/report',
      body: {'body': reason},
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final token = await accessTokenProvider();
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    try {
      final response = method == 'GET'
          ? await _client.get(uri, headers: headers).timeout(timeout)
          : await _client
                .post(
                  uri,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body),
                )
                .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw failureFromResponse(
          statusCode: response.statusCode,
          body: utf8.decode(response.bodyBytes, allowMalformed: true),
        );
      }
      if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on CustomerAuthFailure {
      rethrow;
    } on FormatException {
      throw malformedResponseFailure();
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
  }

  T _parse<T>(T Function() build) {
    try {
      return build();
    } on FormatException {
      throw malformedResponseFailure();
    } on TypeError {
      throw malformedResponseFailure();
    }
  }
}
