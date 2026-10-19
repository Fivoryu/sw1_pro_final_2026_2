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
  'version': '2.0',
  'unit': 'meters',
  'walls': <Object?>[
    {
      'id': 'wall-north',
      'start': {'x': 0.0, 'z': 0.0},
      'end': {'x': 4.0, 'z': 0.0},
      'height': 2.4,
      'thickness': 0.15,
    },
  ],
  'openings': <Object?>[
    {
      'id': 'door_1',
      'wallId': 'wall-north',
      'position': 0.5,
      'width': 0.9,
      'height': 2.1,
      'type': 'door',
    },
  ],
  'rooms': <Object?>[],
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
      expect(ready.document['version'], '2.0');
      final request = requests.single;
      expect(request.url.path, '/api/v1/listings/listing-1/scene');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Authorization'], isNull);
    });

    test('keeps numbers as numbers when parsing the document', () async {
      final api = _build((_) async => _json(_sceneDocument(), 200));

      final result = await api.getScene('listing-1') as SceneReady;

      final walls = result.document['walls']! as List<Object?>;
      final wall = walls.single! as Map<String, Object?>;
      expect(wall['height'], 2.4);
      final openings = result.document['openings']! as List<Object?>;
      final door = openings.single! as Map<String, Object?>;
      expect(door['position'], 0.5);
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
