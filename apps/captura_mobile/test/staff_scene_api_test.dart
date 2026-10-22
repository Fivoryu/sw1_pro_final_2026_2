import 'dart:convert';

import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';
const _scenePath = '/api/v1/staff/agencies/agency-1/listings/listing-1/scene';

const Map<String, Object?> _scene = {
  'version': '2.0',
  'unit': 'meters',
  'walls': <Object?>[],
  'openings': <Object?>[],
  'rooms': <Object?>[],
  'objects': <Object?>[],
};

http.Response _json(Object body, int status, {String? etag}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json', 'etag': ?etag},
    );

void main() {
  group('StaffSceneApi.fetch', () {
    test('returns the remote document with its revision tag', () async {
      late http.Request seen;
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          seen = request;
          return _json(_scene, 200, etag: '"3"');
        }),
      );

      final result = await api.fetch(
        accessToken: 'token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, _scenePath);
      expect(seen.headers['Authorization'], 'Bearer token');
      expect(result, isA<RemoteScene>());
      expect((result as RemoteScene).etag, '"3"');
      expect(result.document['version'], '2.0');
    });

    test(
      'reports a listing without scene as absent, not as a failure',
      () async {
        final api = StaffSceneApi(
          baseUrl: _baseUrl,
          client: MockClient(
            (_) async => _json({
              'detail': 'Scene is not defined for this listing',
              'code': 'scene_not_defined',
            }, 404),
          ),
        );

        final result = await api.fetch(
          accessToken: 'token',
          agencyId: 'agency-1',
          listingId: 'listing-1',
        );

        expect(result, isA<NoRemoteScene>());
      },
    );

    test('raises a typed failure when the listing is missing', () async {
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) async => _json({
            'detail': 'Listing not found',
            'code': 'listing_not_found',
          }, 404),
        ),
      );

      expect(
        () => api.fetch(
          accessToken: 'token',
          agencyId: 'agency-1',
          listingId: 'listing-1',
        ),
        throwsA(
          isA<StaffAuthFailure>().having(
            (f) => f.code,
            'code',
            'listing_not_found',
          ),
        ),
      );
    });
  });

  group('StaffSceneApi.save', () {
    test('creates only when no scene exists yet', () async {
      late http.Request seen;
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          seen = request;
          return _json(_scene, 200, etag: '"1"');
        }),
      );

      final result = await api.save(
        accessToken: 'token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
        document: _scene,
        baseEtag: null,
      );

      expect(seen.method, 'PUT');
      expect(seen.url.path, _scenePath);
      expect(seen.headers['If-None-Match'], '*');
      expect(seen.headers.containsKey('If-Match'), isFalse);
      expect(jsonDecode(seen.body), _scene);
      expect(result, isA<SceneSaved>());
      expect((result as SceneSaved).etag, '"1"');
    });

    test('replaces only the revision the capture started from', () async {
      late http.Request seen;
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          seen = request;
          return _json(_scene, 200, etag: '"5"');
        }),
      );

      final result = await api.save(
        accessToken: 'token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
        document: _scene,
        baseEtag: '"4"',
      );

      expect(seen.headers['If-Match'], '"4"');
      expect(seen.headers.containsKey('If-None-Match'), isFalse);
      expect((result as SceneSaved).etag, '"5"');
    });

    test('turns a precondition failure into a conflict', () async {
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) async => _json(
            {'detail': 'Scene revision mismatch', 'code': 'scene_conflict'},
            412,
            etag: '"7"',
          ),
        ),
      );

      final result = await api.save(
        accessToken: 'token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
        document: _scene,
        baseEtag: '"4"',
      );

      expect(result, isA<SceneConflict>());
      expect((result as SceneConflict).currentEtag, '"7"');
    });

    test('surfaces a rejected document with the server detail', () async {
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) async => _json({
            'detail': 'walls[0].height must be greater than 0',
            'code': 'scene_invalid',
          }, 422),
        ),
      );

      expect(
        () => api.save(
          accessToken: 'token',
          agencyId: 'agency-1',
          listingId: 'listing-1',
          document: _scene,
          baseEtag: null,
        ),
        throwsA(
          isA<StaffAuthFailure>()
              .having((f) => f.code, 'code', 'scene_invalid')
              .having((f) => f.statusCode, 'status', 422),
        ),
      );
    });

    test('reports a lost connection as a network failure', () async {
      final api = StaffSceneApi(
        baseUrl: _baseUrl,
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(
        () => api.save(
          accessToken: 'token',
          agencyId: 'agency-1',
          listingId: 'listing-1',
          document: _scene,
          baseEtag: '"1"',
        ),
        throwsA(
          isA<StaffAuthFailure>().having(
            (f) => f.isNetworkFailure,
            'network',
            isTrue,
          ),
        ),
      );
    });
  });
}
