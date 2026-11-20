import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/catalog_models.dart';
import '../models/favorite_models.dart';
import 'customer_auth_failure.dart';
import 'customer_booking_api.dart' show AccessTokenProvider;

/// Client for `/api/v1/customer/favorites` and
/// `/api/v1/customer/saved-searches`. Every call needs the customer session
/// from [accessTokenProvider]; failures reuse [CustomerAuthFailure].
class CustomerFavoritesApi {
  CustomerFavoritesApi({
    required String baseUrl,
    required this.accessTokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const _favorites = '/api/v1/customer/favorites';
  static const _searches = '/api/v1/customer/saved-searches';

  final String _baseUrl;
  final AccessTokenProvider accessTokenProvider;
  final http.Client _client;
  final Duration timeout;

  Future<List<FavoriteEntry>> listFavorites() async {
    final body = await _send('GET', _favorites);
    return _parse(() => _items(body).map(FavoriteEntry.fromJson).toList());
  }

  Future<void> addFavorite(String listingId) =>
      _send('PUT', '$_favorites/${Uri.encodeComponent(listingId)}');

  Future<void> removeFavorite(String listingId) =>
      _send('DELETE', '$_favorites/${Uri.encodeComponent(listingId)}');

  Future<List<SavedSearch>> listSavedSearches() async {
    final body = await _send('GET', _searches);
    return _parse(() => _items(body).map(SavedSearch.fromJson).toList());
  }

  Future<SavedSearch> createSavedSearch(
    String name,
    CatalogFilters filters,
  ) async {
    final body = await _send(
      'POST',
      _searches,
      body: {'name': name, 'filters': savedFiltersToJson(filters)},
    );
    return _parse(() => SavedSearch.fromJson(body));
  }

  Future<void> deleteSavedSearch(String searchId) =>
      _send('DELETE', '$_searches/${Uri.encodeComponent(searchId)}');

  static List<Object?> _items(Object? body) {
    if (body is! Map<String, Object?> || body['items'] is! List<Object?>) {
      throw const FormatException('Expected an item list');
    }
    return body['items']! as List<Object?>;
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await accessTokenProvider()}',
      };
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw failureFromResponse(statusCode: response.statusCode, body: text);
      }
      if (text.isEmpty) return null;
      return jsonDecode(text);
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
