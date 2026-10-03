import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/staff_listing.dart';
import 'staff_auth_failure.dart';

/// HTTP client for the F04 staff listing routes
/// (`/api/v1/staff/agencies/{agency_id}/listings`).
///
/// Every call carries the in-memory access token of the staff session. Bodies
/// are decoded as UTF-8 explicitly: the API sends `application/json` without a
/// charset, which `package:http` would otherwise read as Latin-1.
class StaffListingsApi {
  StaffListingsApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  /// Largest page the API serves; an agency's working set fits in one page.
  static const int pageLimit = 100;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<List<StaffListing>> listListings({
    required String accessToken,
    required String agencyId,
    required ListingStatus status,
  }) async {
    final json = await _send(
      'GET',
      _collectionPath(agencyId),
      accessToken: accessToken,
      query: {'status': status.wireName, 'limit': '$pageLimit'},
    );
    return _parse(() {
      final listings =
          (json as Map<String, Object?>)['listings'] as List<Object?>;
      return [
        for (final item in listings)
          StaffListing.fromJson(item as Map<String, Object?>),
      ];
    });
  }

  Future<StaffListing> getListing({
    required String accessToken,
    required String agencyId,
    required String listingId,
  }) async => _listing(
    await _send(
      'GET',
      _listingPath(agencyId, listingId),
      accessToken: accessToken,
    ),
  );

  Future<StaffListing> createListing({
    required String accessToken,
    required String agencyId,
    required ListingDraftInput input,
  }) async => _listing(
    await _send(
      'POST',
      _collectionPath(agencyId),
      accessToken: accessToken,
      body: input.toJson(),
    ),
  );

  Future<StaffListing> updateListing({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required ListingDraftInput input,
  }) async => _listing(
    await _send(
      'PUT',
      _listingPath(agencyId, listingId),
      accessToken: accessToken,
      body: input.toJson(),
    ),
  );

  Future<StaffListing> submitListing({
    required String accessToken,
    required String agencyId,
    required String listingId,
  }) async => _listing(
    await _send(
      'POST',
      '${_listingPath(agencyId, listingId)}/submit',
      accessToken: accessToken,
      body: const <String, Object?>{},
    ),
  );

  Future<List<ListingTransitionEntry>> listTransitions({
    required String accessToken,
    required String agencyId,
    required String listingId,
  }) async {
    final json = await _send(
      'GET',
      '${_listingPath(agencyId, listingId)}/transitions',
      accessToken: accessToken,
    );
    return _parse(
      () => [
        for (final item in json as List<Object?>)
          ListingTransitionEntry.fromJson(item as Map<String, Object?>),
      ],
    );
  }

  String _collectionPath(String agencyId) =>
      '/api/v1/staff/agencies/${Uri.encodeComponent(agencyId)}/listings';

  String _listingPath(String agencyId, String listingId) =>
      '${_collectionPath(agencyId)}/${Uri.encodeComponent(listingId)}';

  StaffListing _listing(Object? json) =>
      _parse(() => StaffListing.fromJson(json as Map<String, Object?>));

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw malformedResponseFailure();
    } on TypeError {
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
