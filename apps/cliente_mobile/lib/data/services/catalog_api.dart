import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/catalog_models.dart';
import 'customer_auth_failure.dart';

export 'customer_auth_failure.dart';

/// HTTP client for the public catalog, `/api/v1/listings`.
///
/// The catalog needs no session: it only exposes approved and published
/// listings, so no credentials are sent.
class CatalogApi {
  CatalogApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  /// Page size requested from the API, its documented default.
  static const int pageLimit = 20;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<CatalogPage> searchListings({
    CatalogFilters filters = const CatalogFilters(),
    String? cursor,
  }) async {
    final query = {
      ...filters.toQuery(),
      'cursor': ?cursor,
      'limit': '$pageLimit',
    };
    final body = await _get('/api/v1/listings', query);
    return _parse(() => CatalogPage.fromJson(body));
  }

  Future<CatalogListingDetail> getListing(String listingId) async {
    final body = await _get(
      '/api/v1/listings/${Uri.encodeComponent(listingId)}',
      const {},
    );
    return _parse(() => CatalogListingDetail.fromJson(body));
  }

  Future<Object?> _get(String path, Map<String, String> query) async {
    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: query.isEmpty ? null : query);
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      // FastAPI sends `application/json` without a charset; decode UTF-8
      // explicitly so accented city and zone names survive.
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw failureFromResponse(statusCode: response.statusCode, body: text);
      }
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
