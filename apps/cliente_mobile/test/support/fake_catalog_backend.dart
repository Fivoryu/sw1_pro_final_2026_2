import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the public catalog routes.
///
/// It mirrors the API rules the app depends on: only seeded (published)
/// listings are returned, newest first, filtered like the server and paged
/// with an opaque cursor.
class FakeCatalogBackend {
  bool offline = false;

  /// When set, every request answers with this status and the common envelope.
  int? failWithStatus;
  final List<http.Request> requests = [];
  final List<Map<String, Object?>> _listings = [];

  http.Client get client => MockClient(_handle);

  static const photoBaseUrl = 'http://127.0.0.1:4566/roomforge-local-assets';

  /// Publishes a listing; later seeds are newer and come first. The currency
  /// is echoed exactly as the API sends it: the app never converts prices.
  void seed({
    required String id,
    String operation = 'sale',
    String amount = '350000000.00',
    String currency = 'BOB',
    String city = 'Medellín',
    String zone = 'El Poblado',
    int bedrooms = 3,
    int bathrooms = 2,
    List<({String id, String name, String amount})> extras = const [],
    List<String> photoIds = const [],
  }) {
    final photos = [
      for (final photoId in photoIds)
        {'photo_id': photoId, 'url': '$photoBaseUrl/$photoId?download=600'},
    ];
    _listings.insert(0, {
      'listing_id': id,
      'offer_version': 1,
      'operation': operation,
      'base_price': {'amount': amount, 'currency': currency},
      'city': city,
      'zone': zone,
      'cover_photo_url': photos.isEmpty ? null : photos.first['url'],
      'photos': photos,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'extras': [
        for (final extra in extras)
          {
            'extra_id': extra.id,
            'name': extra.name,
            'price': {'amount': extra.amount, 'currency': currency},
          },
      ],
    });
  }

  static http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  static http.Response _failure(int status, String code) =>
      _json({'detail': 'Rejected by the API.', 'code': code}, status);

  static Map<String, Object?> _item(Map<String, Object?> listing) => {
    for (final key in const [
      'listing_id',
      'offer_version',
      'operation',
      'base_price',
      'city',
      'zone',
      'cover_photo_url',
    ])
      key: listing[key],
  };

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final failure = failWithStatus;
    if (failure != null) {
      return _failure(failure, failure == 404 ? 'not_found' : 'internal_error');
    }

    final path = request.url.path;
    if (path == '/api/v1/listings') return _search(request.url);
    const prefix = '/api/v1/listings/';
    if (path.startsWith(prefix)) {
      final id = Uri.decodeComponent(path.substring(prefix.length));
      for (final listing in _listings) {
        if (listing['listing_id'] == id) return _json(listing, 200);
      }
    }
    return _failure(404, 'not_found');
  }

  http.Response _search(Uri url) {
    final query = url.queryParameters;
    String key(Object? value) => '$value'.trim().toLowerCase();
    double price(Map<String, Object?> listing) => double.parse(
      (listing['base_price']! as Map<String, Object?>)['amount']! as String,
    );
    final matches = _listings.where((listing) {
      final city = query['city'];
      final zone = query['zone'];
      final operation = query['operation'];
      final minPrice = query['min_base_price'];
      final maxPrice = query['max_base_price'];
      final minRooms = query['min_rooms'];
      final minBathrooms = query['min_bathrooms'];
      return (city == null || key(listing['city']) == key(city)) &&
          (zone == null || key(listing['zone']) == key(zone)) &&
          (operation == null || listing['operation'] == operation) &&
          (minPrice == null || price(listing) >= double.parse(minPrice)) &&
          (maxPrice == null || price(listing) <= double.parse(maxPrice)) &&
          (minRooms == null ||
              (listing['bedrooms']! as int) >= int.parse(minRooms)) &&
          (minBathrooms == null ||
              (listing['bathrooms']! as int) >= int.parse(minBathrooms));
    }).toList();

    final limit = int.parse(query['limit'] ?? '20');
    final start = int.parse(query['cursor'] ?? '0');
    final end = start + limit < matches.length ? start + limit : matches.length;
    return _json({
      'items': [
        for (final listing in matches.sublist(start, end)) _item(listing),
      ],
      'next_cursor': end < matches.length ? '$end' : null,
    }, 200);
  }
}
