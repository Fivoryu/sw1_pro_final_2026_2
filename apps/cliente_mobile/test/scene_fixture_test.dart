import 'dart:convert';
import 'dart:io';

import 'package:cliente_mobile/data/services/scene_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The canonical scene document lives beside the contract (`docs/api`), not in
/// this package: the customer app must accept the same bytes the panel saves
/// and the backend serves. This test fails the moment either side drifts (S13).
const _fixturePath = '../../docs/api/f06-scene-fixture.json';

Map<String, Object?> _canonicalScene() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

void main() {
  test('the canonical fixture parses as a v1 scene without retyping numbers', () async {
    final fixture = _canonicalScene();
    final api = SceneApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/listings/listing-1/scene');
        return http.Response.bytes(
          utf8.encode(jsonEncode(fixture)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getScene('listing-1');

    expect(result, isA<SceneReady>());
    final document = (result as SceneReady).document;
    expect(document['version'], '1.0');
    expect(document['unit'], 'meters');

    final rooms = document['rooms']! as List<Object?>;
    expect(rooms, hasLength(1));
    final room = rooms.single! as Map<String, Object?>;
    expect(room['id'], 'room_main');
    expect(room['height'], 2.4, reason: 'a distance must stay a number, never a string');
    final contours = room['contours']! as List<Object?>;
    expect(contours, hasLength(4));
    expect(contours.first, {'x': 0, 'z': 0});
    final openings = room['openings']! as List<Object?>;
    expect(openings, hasLength(1));
    expect((openings.single! as Map<String, Object?>)['type'], 'door');

    final objects = document['objects']! as List<Object?>;
    final objectIds = [
      for (final object in objects) (object! as Map<String, Object?>)['id'],
    ];
    expect(objectIds, ['ref_cube_1', 'ref_cube_2', 'ref_cube_3']);
    expect(
      objectIds.toSet(),
      hasLength(objectIds.length),
      reason: 'the walkthrough selects objects by id, so ids must be unique',
    );
  });
}
