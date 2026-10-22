import 'dart:convert';
import 'dart:io';

import 'package:cliente_mobile/data/services/scene_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The canonical scene document lives beside the contract (`docs/api`), not in
/// this package: the customer app must accept the same bytes the panel saves
/// and the backend serves. This test fails the moment either side drifts.
const _fixturePath = '../../docs/api/f06-scene-fixture.json';

Map<String, Object?> _canonicalScene() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

void main() {
  test('the canonical fixture parses as a v2 scene without retyping numbers', () async {
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
    expect(document['version'], '2.0');
    expect(document['unit'], 'meters');

    // Walls are the source of truth: a closed rectangle 4 x 3 with thickness.
    final walls = document['walls']! as List<Object?>;
    expect(walls, hasLength(4));
    final wallIds = [
      for (final wall in walls) (wall! as Map<String, Object?>)['id'],
    ];
    expect(wallIds, ['wall-north', 'wall-east', 'wall-south', 'wall-west']);
    for (final wall in walls.cast<Map<String, Object?>>()) {
      expect(wall['height'], 2.4, reason: 'a distance must stay a number, never a string');
      expect(wall['thickness'], 0.15);
    }

    // Openings are parametric: wallId + position 0..1, never absolute points.
    final openings = document['openings']! as List<Object?>;
    expect(openings, hasLength(1));
    final door = openings.single! as Map<String, Object?>;
    expect(door['wallId'], 'wall-north');
    expect(door['position'], 0.5);
    expect(door['width'], 0.9);
    expect(door['type'], 'door');

    // Rooms are complement metadata referencing walls, no contours stored.
    final rooms = document['rooms']! as List<Object?>;
    expect(rooms, hasLength(1));
    final room = rooms.single! as Map<String, Object?>;
    expect(room['wallIds'], wallIds);

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
