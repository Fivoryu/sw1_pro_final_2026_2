import 'dart:convert';

import 'package:captura_mobile/data/models/staff_listing.dart';
import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';
const _collection = '/api/v1/staff/agencies/agency-1/listings';

/// Mirrors FastAPI: UTF-8 bytes with `application/json` and no charset, so a
/// client that trusted the default Latin-1 decoding would garble "Medellín".
http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _listingBody({
  String id = 'listing-1',
  String status = 'draft',
  String city = 'Medellín',
}) => {
  'listing_id': id,
  'agency_id': 'agency-1',
  'operation': 'rent',
  'base_price': '2500000.00',
  'city': city,
  'zone': 'El Poblado',
  'bedrooms': 3,
  'bathrooms': 2,
  'description': 'Casa luminosa',
  'exact_address': 'Calle privada 123',
  'approval_status': status,
  'is_published': false,
  'offer_version': 1,
  'created_at': '2026-10-01T12:00:00Z',
};

const _input = ListingDraftInput(
  operation: ListingOperation.rent,
  basePrice: '2500000.00',
  city: 'Medellín',
  zone: 'El Poblado',
  bedrooms: 3,
  bathrooms: 2,
  description: 'Casa luminosa',
  exactAddress: null,
);

({StaffListingsApi api, List<http.Request> requests}) _build(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  return (
    api: StaffListingsApi(
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
  group('StaffListingsApi reads', () {
    test('lists the agency listings of one review status', () async {
      final harness = _build(
        (_) async => _json({
          'listings': [_listingBody()],
          'pagination': {'limit': 100, 'offset': 0, 'total': 1},
        }, 200),
      );

      final listings = await harness.api.listListings(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        status: ListingStatus.draft,
      );

      final request = harness.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, _collection);
      expect(request.url.queryParameters, {'status': 'draft', 'limit': '100'});
      expect(request.headers['Authorization'], 'Bearer access-token');
      expect(listings.single.listingId, 'listing-1');
      expect(listings.single.operation, ListingOperation.rent);
      expect(listings.single.basePrice, '2500000.00');
      expect(listings.single.city, 'Medellín');
      expect(listings.single.status, ListingStatus.draft);
      expect(listings.single.exactAddress, 'Calle privada 123');
      expect(listings.single.createdAt, DateTime.utc(2026, 10, 1, 12));
    });

    test('encodes the agency and listing identifiers in the path', () async {
      final harness = _build((_) async => _json(_listingBody(), 200));

      await harness.api.getListing(
        accessToken: 'access-token',
        agencyId: 'agency/1',
        listingId: 'listing 1',
      );

      expect(
        harness.requests.single.url.toString(),
        '$_baseUrl/api/v1/staff/agencies/agency%2F1/listings/listing%201',
      );
    });

    test('reads the transition history oldest first', () async {
      final harness = _build(
        (_) async => _json([
          {
            'id': 't-1',
            'agency_id': 'agency-1',
            'listing_id': 'listing-1',
            'action': 'submit',
            'from_status': 'draft',
            'from_published': false,
            'to_status': 'pending',
            'to_published': false,
            'observation': null,
            'actor_id': 'agent-1',
            'actor_role': 'agent',
            'created_at': '2026-10-01T12:05:00Z',
          },
          {
            'id': 't-2',
            'agency_id': 'agency-1',
            'listing_id': 'listing-1',
            'action': 'reject',
            'from_status': 'pending',
            'from_published': false,
            'to_status': 'rejected',
            'to_published': false,
            'observation': 'Faltan datos de la zona',
            'actor_id': 'admin-1',
            'actor_role': 'agency_admin',
            'created_at': '2026-10-01T13:00:00Z',
          },
        ], 200),
      );

      final history = await harness.api.listTransitions(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
      );

      expect(
        harness.requests.single.url.path,
        '$_collection/listing-1/transitions',
      );
      expect(history.map((entry) => entry.action), ['submit', 'reject']);
      expect(history.last.observation, 'Faltan datos de la zona');
      expect(history.last.actorRole, 'agency_admin');
    });
  });

  group('StaffListingsApi writes', () {
    test('creates a draft from the authoring fields only', () async {
      final harness = _build((_) async => _json(_listingBody(), 201));

      final listing = await harness.api.createListing(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        input: _input,
      );

      final request = harness.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, _collection);
      expect(request.headers['Authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {
        'operation': 'rent',
        'base_price': '2500000.00',
        'city': 'Medellín',
        'zone': 'El Poblado',
        'bedrooms': 3,
        'bathrooms': 2,
        'description': 'Casa luminosa',
        'exact_address': null,
      });
      expect(listing.status, ListingStatus.draft);
    });

    test('replaces a listing with PUT', () async {
      final harness = _build((_) async => _json(_listingBody(), 200));

      await harness.api.updateListing(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
        input: _input,
      );

      expect(harness.requests.single.method, 'PUT');
      expect(harness.requests.single.url.path, '$_collection/listing-1');
    });

    test('submits a listing for review', () async {
      final harness = _build(
        (_) async => _json(_listingBody(status: 'pending'), 200),
      );

      final listing = await harness.api.submitListing(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
      );

      expect(harness.requests.single.method, 'POST');
      expect(harness.requests.single.url.path, '$_collection/listing-1/submit');
      expect(jsonDecode(harness.requests.single.body), <String, Object?>{});
      expect(listing.status, ListingStatus.pending);
    });
  });

  group('StaffListingsApi failures', () {
    test('keeps the status and code of a rejected request', () async {
      final harness = _build(
        (_) async => _json({
          'detail': 'Listing cannot be changed from its current state',
          'code': 'conflict',
        }, 409),
      );

      await expectLater(
        harness.api.submitListing(
          accessToken: 'access-token',
          agencyId: 'agency-1',
          listingId: 'listing-1',
        ),
        throwsA(
          isA<StaffAuthFailure>()
              .having((failure) => failure.statusCode, 'statusCode', 409)
              .having((failure) => failure.code, 'code', kConflict),
        ),
      );
    });

    test('reports a transport error as a network failure', () async {
      final harness = _build(
        (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        harness.api.listListings(
          accessToken: 'access-token',
          agencyId: 'agency-1',
          status: ListingStatus.pending,
        ),
        throwsA(
          isA<StaffAuthFailure>().having(
            (failure) => failure.isNetworkFailure,
            'isNetworkFailure',
            isTrue,
          ),
        ),
      );
    });

    test('rejects a success body that does not match the contract', () async {
      final harness = _build(
        (_) async => _json({'listings': 'unexpected'}, 200),
      );

      await expectLater(
        harness.api.listListings(
          accessToken: 'access-token',
          agencyId: 'agency-1',
          status: ListingStatus.draft,
        ),
        throwsA(
          isA<StaffAuthFailure>().having(
            (failure) => failure.code,
            'code',
            kInternalError,
          ),
        ),
      );
    });
  });
}
