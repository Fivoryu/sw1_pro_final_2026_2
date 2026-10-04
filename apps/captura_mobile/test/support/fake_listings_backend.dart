import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the F04 staff listing routes of one agency.
///
/// It mirrors the API rules the app depends on: Bearer authorization, the
/// agency in the path, edit returning any listing to `draft`, and `submit`
/// allowed only from `draft`.
class FakeListingsBackend {
  FakeListingsBackend({this.agencyId = 'agency-1'});

  final String agencyId;
  bool offline = false;

  /// When set, every request answers with this status and the common envelope.
  int? failWithStatus;
  final List<http.Request> requests = [];
  final Map<String, Map<String, Object?>> listings = {};
  final Map<String, List<Map<String, Object?>>> transitions = {};
  int _sequence = 0;

  http.Client get client => MockClient(_handle);

  /// Seeds a listing directly, as if created earlier through the API.
  void seed({
    required String id,
    String status = 'draft',
    String city = 'Medellín',
    String zone = 'El Poblado',
    String? rejectionReason,
  }) {
    listings[id] = _body(
      id: id,
      status: status,
      fields: {
        'operation': 'sale',
        'base_price': '350000000.00',
        'city': city,
        'zone': zone,
        'bedrooms': 3,
        'bathrooms': 2,
        'description': 'Casa luminosa',
        'exact_address': 'Calle privada 123',
      },
    );
    transitions[id] = [
      _transition(id, 'create', 'draft', null, 'agent'),
      if (rejectionReason != null) ...[
        _transition(id, 'submit', 'pending', null, 'agent'),
        _transition(id, 'reject', 'rejected', rejectionReason, 'agency_admin'),
      ],
    ];
  }

  Map<String, Object?> _body({
    required String id,
    required String status,
    required Map<String, Object?> fields,
  }) => {
    'listing_id': id,
    'agency_id': agencyId,
    ...fields,
    'approval_status': status,
    'is_published': false,
    'offer_version': 1,
    'created_at':
        '2026-10-01T12:00:${(_sequence++).toString().padLeft(2, '0')}Z',
  };

  Map<String, Object?> _transition(
    String listingId,
    String action,
    String toStatus,
    String? observation,
    String actorRole,
  ) => {
    'id': 't-${_sequence++}',
    'agency_id': agencyId,
    'listing_id': listingId,
    'action': action,
    'from_status': null,
    'from_published': null,
    'to_status': toStatus,
    'to_published': false,
    'observation': observation,
    'actor_id': 'actor',
    'actor_role': actorRole,
    'created_at': '2026-10-01T12:00:00Z',
  };

  static http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  static http.Response _failure(int status, String code) =>
      _json({'detail': 'Rejected by the API.', 'code': code}, status);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final failure = failWithStatus;
    if (failure != null) {
      return _failure(failure, failure == 409 ? 'conflict' : 'internal_error');
    }
    if (request.headers['Authorization'] != 'Bearer access-token') {
      return _failure(401, 'unauthorized');
    }

    final prefix = '/api/v1/staff/agencies/$agencyId/listings';
    final path = request.url.path;
    if (!path.startsWith(prefix)) return _failure(403, 'forbidden');
    final rest = path.substring(prefix.length).split('/')
      ..removeWhere((part) => part.isEmpty);

    if (rest.isEmpty && request.method == 'GET') {
      final status = request.url.queryParameters['status'];
      final page = listings.values
          .where((listing) => listing['approval_status'] == status)
          .toList()
          .reversed
          .toList();
      return _json({
        'listings': page,
        'pagination': {'limit': 100, 'offset': 0, 'total': page.length},
      }, 200);
    }
    if (rest.isEmpty && request.method == 'POST') {
      final id = 'listing-${listings.length + 1}';
      listings[id] = _body(
        id: id,
        status: 'draft',
        fields: jsonDecode(request.body) as Map<String, Object?>,
      );
      transitions[id] = [_transition(id, 'create', 'draft', null, 'agent')];
      return _json(listings[id]!, 201);
    }

    final listing = listings[rest.first];
    if (listing == null) return _failure(404, 'not_found');
    if (rest.length == 1 && request.method == 'GET') return _json(listing, 200);
    if (rest.length == 1 && request.method == 'PUT') {
      listing
        ..addAll(jsonDecode(request.body) as Map<String, Object?>)
        ..['approval_status'] = 'draft'
        ..['is_published'] = false;
      transitions[rest.first]!.add(
        _transition(rest.first, 'edit', 'draft', null, 'agent'),
      );
      return _json(listing, 200);
    }
    if (rest.length == 2 && rest[1] == 'submit' && request.method == 'POST') {
      if (listing['approval_status'] != 'draft') {
        return _failure(409, 'conflict');
      }
      listing['approval_status'] = 'pending';
      transitions[rest.first]!.add(
        _transition(rest.first, 'submit', 'pending', null, 'agent'),
      );
      return _json(listing, 200);
    }
    if (rest.length == 2 && rest[1] == 'transitions') {
      return _json(transitions[rest.first]!, 200);
    }
    return _failure(404, 'not_found');
  }
}
