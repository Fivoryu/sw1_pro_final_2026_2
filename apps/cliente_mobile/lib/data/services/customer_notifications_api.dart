import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/notification_models.dart';
import 'customer_auth_failure.dart';
import 'customer_booking_api.dart' show AccessTokenProvider;

/// Client for `/api/v1/customer/notifications`, using the customer session
/// supplied by [accessTokenProvider]. Failures reuse [CustomerAuthFailure].
class CustomerNotificationsApi {
  CustomerNotificationsApi({
    required String baseUrl,
    required this.accessTokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const _root = '/api/v1/customer/notifications';

  final String _baseUrl;
  final AccessTokenProvider accessTokenProvider;
  final http.Client _client;
  final Duration timeout;

  Future<NotificationInbox> list({int limit = 50}) async {
    final body = await _send('GET', '$_root?limit=$limit');
    try {
      return NotificationInbox.fromJson(body);
    } on FormatException {
      throw malformedResponseFailure();
    } on TypeError {
      throw malformedResponseFailure();
    }
  }

  Future<void> markRead(String id) =>
      _send('POST', '$_root/${Uri.encodeComponent(id)}/read');

  Future<void> markAllRead() => _send('POST', '$_root/read-all');

  Future<Object?> _send(String method, String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final token = await accessTokenProvider();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    try {
      final response = method == 'GET'
          ? await _client.get(uri, headers: headers).timeout(timeout)
          : await _client.post(uri, headers: headers).timeout(timeout);
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
}
