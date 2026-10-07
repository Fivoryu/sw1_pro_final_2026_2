import 'dart:convert';

import 'package:cliente_mobile/data/models/catalog_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';

/// Mirrors FastAPI: UTF-8 bytes with `application/json` and no charset, so a
/// client that trusted the default Latin-1 decoding would garble "Medellín".
http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _item({
  String id = 'listing-1',
  String operation = 'rent',
  String city = 'Medellín',
}) => {
  'listing_id': id,
  'offer_version': 2,
  'operation': operation,
  'base_price': {'amount': '2500000.00', 'currency': 'COP'},
  'city': city,
  'zone': 'El Poblado',
};

({CatalogApi api, List<http.Request> requests}) _build(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  return (
    api: CatalogApi(
      baseUrl: '$_baseUrl/',
      client: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    ),
    requests: requests,
  );
}

void main() {
  group('CatalogApi search', () {
    test('lists the first page without filters or credentials', () async {
      final harness = _build(
        (_) async => _json({
          'items': [_item()],
          'next_cursor': 'cursor-2',
        }, 200),
      );

      final page = await harness.api.searchListings();

      final request = harness.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/listings');
      expect(request.url.queryParameters, {'limit': '20'});
      expect(request.headers.containsKey('Authorization'), isFalse);
      final listing = page.items.single;
      expect(listing.listingId, 'listing-1');
      expect(listing.offerVersion, 2);
      expect(listing.operation, ListingOperation.rent);
      expect(listing.basePrice.amount, '2500000.00');
      expect(listing.basePrice.currency, 'COP');
      expect(listing.city, 'Medellín');
      expect(listing.zone, 'El Poblado');
      expect(page.nextCursor, 'cursor-2');
    });

    test('sends every active filter and the cursor', () async {
      final harness = _build(
        (_) async => _json({'items': [], 'next_cursor': null}, 200),
      );

      final page = await harness.api.searchListings(
        filters: const CatalogFilters(
          city: 'Medellín',
          zone: 'El Poblado',
          operation: ListingOperation.sale,
          minBasePrice: '100000000',
          maxBasePrice: '450000000.50',
          minBedrooms: 2,
          minBathrooms: 1,
        ),
        cursor: 'cursor-2',
      );

      expect(harness.requests.single.url.queryParameters, {
        'city': 'Medellín',
        'zone': 'El Poblado',
        'operation': 'sale',
        'min_base_price': '100000000',
        'max_base_price': '450000000.50',
        'min_rooms': '2',
        'min_bathrooms': '1',
        'cursor': 'cursor-2',
        'limit': '20',
      });
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('CatalogApi detail', () {
    test('reads rooms and optional extras of one listing', () async {
      final harness = _build(
        (_) async => _json({
          ..._item(operation: 'sale'),
          'bedrooms': 3,
          'bathrooms': 2,
          'extras': [
            {
              'extra_id': 'extra-1',
              'name': 'Sofá en L',
              'price': {'amount': '1500000.00', 'currency': 'COP'},
            },
          ],
        }, 200),
      );

      final detail = await harness.api.getListing('listing 1');

      expect(
        harness.requests.single.url.toString(),
        '$_baseUrl/api/v1/listings/listing%201',
      );
      expect(detail.listing.operation, ListingOperation.sale);
      expect(detail.bedrooms, 3);
      expect(detail.bathrooms, 2);
      expect(detail.extras.single.extraId, 'extra-1');
      expect(detail.extras.single.name, 'Sofá en L');
      expect(detail.extras.single.price.amount, '1500000.00');
    });
  });

  group('CatalogApi failures', () {
    test('keeps the status and code of a rejected request', () async {
      final harness = _build(
        (_) async =>
            _json({'detail': 'listing_not_found', 'code': 'not_found'}, 404),
      );

      await expectLater(
        harness.api.getListing('missing'),
        throwsA(
          isA<CustomerAuthFailure>()
              .having((failure) => failure.statusCode, 'statusCode', 404)
              .having((failure) => failure.code, 'code', kNotFound),
        ),
      );
    });

    test('reports a transport error as a network failure', () async {
      final harness = _build(
        (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        harness.api.searchListings(),
        throwsA(
          isA<CustomerAuthFailure>().having(
            (failure) => failure.isNetworkFailure,
            'isNetworkFailure',
            isTrue,
          ),
        ),
      );
    });

    test('rejects a success body that does not match the contract', () async {
      final harness = _build(
        (_) async => _json({
          'items': [
            {..._item(), 'operation': 'lease'},
          ],
          'next_cursor': null,
        }, 200),
      );

      await expectLater(
        harness.api.searchListings(),
        throwsA(
          isA<CustomerAuthFailure>().having(
            (failure) => failure.code,
            'code',
            kInternalError,
          ),
        ),
      );
    });
  });

  group('CatalogFilters', () {
    test('is empty when no filter is set', () {
      expect(const CatalogFilters().isEmpty, isTrue);
      expect(const CatalogFilters(minBathrooms: 0).isEmpty, isFalse);
    });
  });

  group('CatalogApi photos', () {
    test('reads the cover of each listed item', () async {
      final harness = _build(
        (_) async => _json({
          'items': [
            {
              ..._item(id: 'with-cover'),
              'cover_photo_url': 'http://s/cover.jpg',
            },
            {..._item(id: 'without-cover'), 'cover_photo_url': null},
          ],
          'next_cursor': null,
        }, 200),
      );

      final page = await harness.api.searchListings();

      expect(page.items.first.coverPhotoUrl, 'http://s/cover.jpg');
      expect(page.items.last.coverPhotoUrl, isNull);
    });

    test('reads the gallery of a listing detail in order', () async {
      final harness = _build(
        (_) async => _json({
          ..._item(),
          'cover_photo_url': 'http://s/a.jpg',
          'bedrooms': 3,
          'bathrooms': 2,
          'extras': [],
          'photos': [
            {'photo_id': 'a', 'url': 'http://s/a.jpg'},
            {'photo_id': 'b', 'url': 'http://s/b.jpg'},
          ],
        }, 200),
      );

      final detail = await harness.api.getListing('listing-1');

      expect(detail.photos.map((photo) => photo.photoId), ['a', 'b']);
      expect(detail.photos.last.url, 'http://s/b.jpg');
    });

    test('rejects a cover that is not a link', () async {
      final harness = _build(
        (_) async => _json({
          'items': [
            {..._item(), 'cover_photo_url': 42},
          ],
          'next_cursor': null,
        }, 200),
      );

      await expectLater(
        harness.api.searchListings(),
        throwsA(
          isA<CustomerAuthFailure>().having(
            (failure) => failure.code,
            'code',
            kInternalError,
          ),
        ),
      );
    });
  });
}
