import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/staff_review.dart';
import 'staff_auth_failure.dart';

/// HTTP client for the F14.8 staff review routes (`/api/v1/staff/reviews`).
/// Every call carries the in-memory access token of the staff session.
class StaffReviewsApi {
  StaffReviewsApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const String _path = '/api/v1/staff/reviews';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<StaffReviewList> list({required String accessToken}) async {
    final json = await _send('GET', _path, accessToken: accessToken);
    try {
      return StaffReviewList.fromJson(json);
    } on FormatException {
      throw malformedResponseFailure();
    }
  }

  /// The agency's single answer to a review (agency administrators only).
  Future<void> reply({
    required String accessToken,
    required String reviewId,
    required String body,
  }) => _send(
    'POST',
    '$_path/$reviewId/reply',
    accessToken: accessToken,
    body: {'body': body},
  );

  /// Reports a review so the platform administrator can decide.
  Future<void> report({
    required String accessToken,
    required String reviewId,
    required String reason,
  }) => _send(
    'POST',
    '$_path/$reviewId/report',
    accessToken: accessToken,
    body: {'body': reason},
  );

  Future<Object?> _send(
    String method,
    String path, {
    required String accessToken,
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
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
    if (response.statusCode == 204 || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      throw malformedResponseFailure();
    }
  }
}
