import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/customer_models.dart';
import 'customer_auth_failure.dart';

export 'customer_auth_failure.dart';

/// HTTP client for `/api/v1/customer/auth/*`.
class CustomerAuthApi {
  CustomerAuthApi({
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

  Future<CustomerIdentity> register({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/customer/auth/register',
      body: {'email': email, 'password': password},
    );
    return _identity(response);
  }

  Future<CustomerTokenPair> login({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/customer/auth/login',
      body: {'email': email, 'password': password},
    );
    return _tokenPair(response);
  }

  Future<CustomerTokenPair> refresh({required String refreshToken}) async {
    final response = await _send(
      'POST',
      '/api/v1/customer/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    return _tokenPair(response);
  }

  Future<void> logout({required String refreshToken}) async {
    await _send(
      'POST',
      '/api/v1/customer/auth/logout',
      body: {'refresh_token': refreshToken},
    );
  }

  Future<CustomerIdentity> fetchIdentity({required String accessToken}) async {
    final response = await _send(
      'GET',
      '/api/v1/customer/auth/me',
      accessToken: accessToken,
    );
    return _identity(response);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
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
    } on CustomerAuthFailure {
      rethrow;
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
  }

  CustomerIdentity _identity(http.Response response) {
    final json = _decodeObject(response);
    final id = json['id'];
    final email = json['email'];
    if (id is! String || email is! String) {
      throw malformedResponseFailure();
    }
    return CustomerIdentity(id: id, email: email);
  }

  CustomerTokenPair _tokenPair(http.Response response) {
    final json = _decodeObject(response);
    final accessToken = json['access_token'];
    final refreshToken = json['refresh_token'];
    final expiresIn = json['access_expires_in'];
    if (accessToken is! String || refreshToken is! String || expiresIn is! int) {
      throw malformedResponseFailure();
    }
    return CustomerTokenPair(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresIn: Duration(seconds: expiresIn),
    );
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      throw malformedResponseFailure();
    }
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
