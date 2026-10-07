import 'dart:convert';
import 'dart:typed_data';

import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the F04 staff listing routes of one agency, its
/// F04.2 photo routes and the object storage behind the signed links.
///
/// It mirrors the API rules the app depends on: Bearer authorization, the
/// agency in the path, edit returning any listing to `draft`, `submit` allowed
/// only from `draft` with at least one confirmed photo, at most ten photos, and
/// confirmed photo changes returning the listing to `draft`.
class FakeListingsBackend {
  FakeListingsBackend({this.agencyId = 'agency-1'});

  static const storageHost = 'storage.example.test';

  final String agencyId;
  bool offline = false;

  /// When set, every API request answers with this status and the envelope.
  int? failWithStatus;

  /// When set, the next confirmation answers with this status instead.
  int? failNextConfirmWithStatus;

  /// When true, uploads to the storage fail at the transport level.
  bool storageOffline = false;

  final List<http.Request> requests = [];
  final Map<String, Map<String, Object?>> listings = {};
  final Map<String, List<Map<String, Object?>>> transitions = {};

  /// Photos by listing: `id`, `status`, `content_type`, `size_bytes`.
  final Map<String, List<Map<String, Object?>>> photos = {};

  /// Objects in the storage by photo id.
  final Map<String, Uint8List> storage = {};
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

  /// Seeds a confirmed photo of [listingId].
  void seedPhoto(String listingId, {String? photoId}) {
    final id = photoId ?? 'photo-${_sequence++}';
    photos.putIfAbsent(listingId, () => []).add({
      'id': id,
      'status': 'confirmed',
      'content_type': 'image/jpeg',
      'size_bytes': 3,
    });
    storage[id] = Uint8List.fromList(const [0xFF, 0xD8, 0xFF]);
  }

  List<Map<String, Object?>> confirmedPhotos(String listingId) => [
    for (final photo in photos[listingId] ?? const <Map<String, Object?>>[])
      if (photo['status'] == 'confirmed') photo,
  ];

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

  static http.Response _failure(int status, String code, [String? detail]) =>
      _json({'detail': detail ?? 'Rejected by the API.', 'code': code}, status);

  static String _codeFor(int status) => switch (status) {
    401 => 'unauthorized',
    403 => 'forbidden',
    404 => 'not_found',
    409 => 'conflict',
    422 => 'validation_error',
    503 => 'dependency_unavailable',
    _ => 'internal_error',
  };

  Map<String, Object?> _photoJson(Map<String, Object?> photo) => {
    'photo_id': photo['id'],
    'content_type': photo['content_type'],
    'size_bytes': photo['size_bytes'],
    'url': 'https://$storageHost/photos/${photo['id']}?download=600',
    'created_at': '2026-10-06T12:00:00Z',
  };

  void _reopen(String listingId) {
    listings[listingId]!
      ..['approval_status'] = 'draft'
      ..['is_published'] = false;
    transitions[listingId]!.add(
      _transition(listingId, 'edit', 'draft', null, 'agent'),
    );
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (request.url.host == storageHost) return _handleStorage(request);
    if (offline) throw http.ClientException('offline');
    final failure = failWithStatus;
    if (failure != null) return _failure(failure, _codeFor(failure));
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

    final listingId = rest.first;
    final listing = listings[listingId];
    if (listing == null) return _failure(404, 'not_found');
    if (rest.length >= 2 && rest[1] == 'photos') {
      return _handlePhotos(request, listingId, rest.sublist(2));
    }
    if (rest.length == 1 && request.method == 'GET') return _json(listing, 200);
    if (rest.length == 1 && request.method == 'PUT') {
      listing
        ..addAll(jsonDecode(request.body) as Map<String, Object?>)
        ..['approval_status'] = 'draft'
        ..['is_published'] = false;
      transitions[listingId]!.add(
        _transition(listingId, 'edit', 'draft', null, 'agent'),
      );
      return _json(listing, 200);
    }
    if (rest.length == 2 && rest[1] == 'submit' && request.method == 'POST') {
      if (listing['approval_status'] != 'draft') {
        return _failure(409, 'conflict');
      }
      if (confirmedPhotos(listingId).isEmpty) {
        return _failure(
          409,
          'conflict',
          'Listing needs at least one confirmed photo',
        );
      }
      listing['approval_status'] = 'pending';
      transitions[listingId]!.add(
        _transition(listingId, 'submit', 'pending', null, 'agent'),
      );
      return _json(listing, 200);
    }
    if (rest.length == 2 && rest[1] == 'transitions') {
      return _json(transitions[listingId]!, 200);
    }
    return _failure(404, 'not_found');
  }

  http.Response _handlePhotos(
    http.Request request,
    String listingId,
    List<String> rest,
  ) {
    final listingPhotos = photos.putIfAbsent(listingId, () => []);
    if (rest.isEmpty && request.method == 'GET') {
      return _json({
        'photos': [
          for (final photo in confirmedPhotos(listingId)) _photoJson(photo),
        ],
      }, 200);
    }
    if (rest.isEmpty && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (listingPhotos.length >= 10) {
        return _failure(409, 'conflict', 'Listing photo limit reached');
      }
      final id = 'photo-${_sequence++}';
      listingPhotos.add({
        'id': id,
        'status': 'pending',
        'content_type': body['content_type'],
        'size_bytes': body['size_bytes'],
      });
      return _json({
        'photo_id': id,
        'upload_url': 'https://$storageHost/upload/$id?X-Amz-Signature=fake',
        'upload_method': 'PUT',
        'upload_headers': {'Content-Type': body['content_type']},
        'expires_at': '2099-01-01T00:00:00Z',
      }, 201);
    }

    final photoIndex = listingPhotos.indexWhere(
      (photo) => photo['id'] == rest.first,
    );
    if (photoIndex < 0) return _failure(404, 'not_found', 'Photo not found');
    final photo = listingPhotos[photoIndex];
    if (rest.length == 2 && rest[1] == 'confirm' && request.method == 'POST') {
      final forced = failNextConfirmWithStatus;
      if (forced != null) {
        failNextConfirmWithStatus = null;
        return _failure(forced, _codeFor(forced));
      }
      if (photo['status'] == 'confirmed') return _json(_photoJson(photo), 200);
      final bytes = storage[photo['id']];
      if (bytes == null) {
        return _failure(409, 'conflict', 'Photo has not been uploaded');
      }
      if (detectPhotoContentType(bytes) != photo['content_type']) {
        storage.remove(photo['id']);
        listingPhotos.removeAt(photoIndex);
        return _failure(422, 'validation_error');
      }
      photo
        ..['status'] = 'confirmed'
        ..['size_bytes'] = bytes.length;
      _reopen(listingId);
      return _json(_photoJson(photo), 200);
    }
    if (rest.length == 1 && request.method == 'DELETE') {
      storage.remove(photo['id']);
      listingPhotos.removeAt(photoIndex);
      if (photo['status'] == 'confirmed') _reopen(listingId);
      return http.Response('', 204);
    }
    return _failure(404, 'not_found');
  }

  http.Response _handleStorage(http.Request request) {
    if (storageOffline) throw http.ClientException('storage offline');
    final segments = request.url.pathSegments;
    if (request.method == 'PUT' && segments.first == 'upload') {
      storage[segments[1]] = request.bodyBytes;
      return http.Response('', 200);
    }
    return http.Response('<Error/>', 403);
  }
}
