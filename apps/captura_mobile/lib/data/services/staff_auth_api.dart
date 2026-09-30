import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'staff_auth_failure.dart';

export 'staff_auth_failure.dart';

/// The first login step answer: credentials were accepted, a TOTP proof is next.
class StaffAccessChallenge {
  const StaffAccessChallenge({required this.challengeToken});

  final String challengeToken;
}

/// The staff account resolved from `/me`.
class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.email,
    required this.role,
    required this.tenantId,
  });

  final String id;
  final String email;
  final String role;
  final String? tenantId;
}

/// A completed staff session.
///
/// [refreshCookie] is the opaque value of the HttpOnly `roomforge_refresh`
/// cookie the API sets. The capture app has no cookie jar, so it carries the
/// value itself; it is null when the response exposed no cookie, in which case
/// the session simply cannot be refreshed later.
class StaffAccessGrant {
  const StaffAccessGrant({
    required this.accessToken,
    required this.csrfToken,
    required this.account,
    required this.refreshCookie,
  });

  final String accessToken;
  final String csrfToken;
  final StaffAccount account;
  final String? refreshCookie;
}

/// HTTP client for `/api/v1/auth/*`.
///
/// Refresh and logout read the HttpOnly `roomforge_refresh` cookie and require
/// an `x-csrf-token` header, so this client captures the cookie from
/// `set-cookie` and sends it back explicitly.
class StaffAuthApi {
  StaffAuthApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<StaffAccessChallenge> startLogin({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
    );
    final json = _decodeObject(response);
    final challengeToken = json['challenge_token'];
    if (challengeToken is! String || challengeToken.isEmpty) {
      throw malformedResponseFailure();
    }
    return StaffAccessChallenge(challengeToken: challengeToken);
  }

  Future<StaffAccessGrant> completeLogin({
    required String challengeToken,
    required String code,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login/totp',
      body: {'challenge_token': challengeToken, 'code': code},
    );
    return _grant(response);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
    String? csrfToken,
    String? refreshCookie,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (csrfToken != null) 'X-CSRF-Token': csrfToken,
      if (refreshCookie != null) 'Cookie': '$kRefreshCookieName=$refreshCookie',
    };
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final response = switch (method) {
        'GET' => await _client.get(uri, headers: headers).timeout(timeout),
        _ => await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(timeout),
      };
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw failureFromResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } on StaffAuthFailure {
      rethrow;
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
  }

  StaffAccessGrant _grant(http.Response response) {
    final json = _decodeObject(response);
    final accessToken = json['access_token'];
    final csrfToken = json['csrf_token'];
    final user = json['user'];
    if (accessToken is! String ||
        csrfToken is! String ||
        user is! Map<String, Object?>) {
      throw malformedResponseFailure();
    }
    return StaffAccessGrant(
      accessToken: accessToken,
      csrfToken: csrfToken,
      account: _account(user),
      refreshCookie: readRefreshCookie(response.headers),
    );
  }

  StaffAccount _account(Map<String, Object?> user) {
    final id = user['id'];
    final email = user['email'];
    final role = user['role'];
    final tenantId = user['tenant_id'];
    if (id is! String || email is! String || role is! String) {
      throw malformedResponseFailure();
    }
    return StaffAccount(
      id: id,
      email: email,
      role: role,
      tenantId: tenantId is String ? tenantId : null,
    );
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) throw malformedResponseFailure();
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw malformedResponseFailure();
    }
    if (decoded is! Map<String, Object?>) {
      throw malformedResponseFailure();
    }
    return decoded;
  }
}
