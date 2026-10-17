import 'dart:convert';

import 'package:cliente_mobile/data/services/scene_api.dart';
import 'package:cliente_mobile/data/services/customer_auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

SceneApi _build(Future<http.Response> Function(http.Request request) handler) =>
  SceneApi(
    baseUrl: '$_baseUrl/',
    client: MockClient(handler),
  );

Map<String, Object?> _sceneDocument() => {
  'version': '1.0',
  'unit': 'meters',
  'rooms': [
    {
      'id': 'room_main',
      'height': 2.4,
      'contours': [
        {'x': 0.0, 'z': 0.0},
        {'x': 4.0, 'z': 0.0},
        {'x': 4.0, 'z': 3.0},
        {'x': 0.0, 'z': 3.0},
      ],
      'openings': <Object?>[],
    },
  ],
  'objects': <Object?>[],
};

void main() {
  group('SceneApi success', () {
    test('returns the document for a published listing without credentials', () async {
      final requests = <http.Request>[];
      final api = SceneApi(
        baseUrl: '$_baseUrl/',
        client: MockClient((request) async {
          requests.add(request);
          return _json(_sceneDocument(), 200);
        }),
      );

      final result = await api.getScene('listing-1');

      expect(result, isA<SceneReady>());
      final ready = result as SceneReady;
      expect(ready.document['version'], '1.0');
      final request = requests.single;
      expect(request.url.path, '/api/v1/listings/listing-1/scene');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Authorization'], isNull);
    });

    test('keeps numbers as numbers when parsing the document', () async {
      final api = _build((_) async => _json(_sceneDocument(), 200));

      final result = await api.getScene('listing-1') as SceneReady;

      final rooms = result.document['rooms']! as List<Object?>;
      final room = rooms.single! as Map<String, Object?>;
      expect(room['height'], 2.4);
    });
  });

  group('SceneApi honest fallbacks', () {
    test('a listing without a scene reports SceneNotDefined', () async {
      final api = _build(
        (_) async => _json({
          'detail': 'Scene is not defined for this listing',
          'code': 'scene_not_defined',
        }, 404),
      );

      final result = await api.getScene('listing-1');

      expect(result, isA<SceneNotDefined>());
    });

    test('another 404 stays unavailable with the not-found code', () async {
      final api = _build((_) async => _json({'detail': 'x'}, 404));

      final result = await api.getScene('listing-1') as SceneUnavailable;

      expect(result.failure.code, kNotFound);
    });

    test('a malformed success body is unavailable, never a scene', () async {
      final api = SceneApi(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) async => http.Response('not json', 200),
        ),
      );

      final result = await api.getScene('listing-1') as SceneUnavailable;

      expect(result.failure.code, kInternalError);
    });

    test('a non-object success body is unavailable', () async {
      final api = _build((_) async => _json(['not', 'a', 'scene'], 200));

      final result = await api.getScene('listing-1');

      expect(result, isA<SceneUnavailable>());
    });

    test('a transport failure is unavailable and safe to retry', () async {
      final api = SceneApi(
        baseUrl: _baseUrl,
        client: MockClient((_) async => throw http.ClientException('closed')),
      );

      final result = await api.getScene('listing-1') as SceneUnavailable;

      expect(result.failure.isNetworkFailure, isTrue);
    });
  });
}
