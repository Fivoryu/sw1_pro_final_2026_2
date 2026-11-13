import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/staff_notification.dart';
import 'staff_auth_failure.dart';

/// HTTP client for the F14.7 staff notification routes
/// (`/api/v1/staff/notifications`). Every call carries the in-memory access
/// token of the staff session.
class StaffNotificationsApi {
  StaffNotificationsApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const String _path = '/api/v1/staff/notifications';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<StaffNotificationInbox> list({
    required String accessToken,
    int limit = 50,
  }) async {
    final json = await _send(
      'GET',
      _path,
      accessToken: accessToken,
      query: {'limit': '$limit'},
    );
    try {
      return StaffNotificationInbox.fromJson(json);
    } on FormatException {
      throw malformedResponseFailure();
    }
  }

  Future<void> markRead({
    required String accessToken,
    required String id,
  }) => _send('POST', '$_path/$id/read', accessToken: accessToken);

  Future<void> markAllRead({required String accessToken}) =>
      _send('POST', '$_path/read-all', accessToken: accessToken);

  Future<Object?> _send(
    String method,
    String path, {
    required String accessToken,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      });

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
    if (response.statusCode == 204 || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      throw malformedResponseFailure();
    }
  }
}
