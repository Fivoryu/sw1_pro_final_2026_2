import 'dart:convert';

import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _internalScene() => {
  'version': '2.0',
  'unit': 'meters',
  'walls': [
    {
      'id': 'wall-1',
      'start': {'x': 0.0, 'z': 0.0, 'internal': true},
      'end': {'x': 4.0, 'z': 0.0, 'internal': true},
      'height': 2.6,
      'thickness': 0.12,
      'heightSource': 'manual',
      'lengthM': 4.0,
      'measurementEvidence': {'source': 'user'},
    },
  ],
  'wallDimensions': [
    {'roomId': 'room-1', 'wallId': 'wall-1', 'lengthM': 4.0, 'heightM': 2.6},
  ],
  'openings': [
    {
      'id': 'door-1',
      'wallId': 'wall-1',
      'position': .5,
      'width': .9,
      'height': 2.1,
      'type': 'door',
      'internalConfidence': .9,
    },
  ],
  'rooms': [
    {
      'id': 'room-room-1',
      'name': 'Ambiente 1',
      'wallIds': ['wall-1', 'wall-2', 'wall-3'],
      'visualRoomId': 'A1',
    },
  ],
  'objects': [
    {
      'id': 'box-1',
      'type': 'occupancy',
      'position': {'x': 1.0, 'y': .5, 'z': 1.0, 'internal': true},
      'dimensions': {
        'width': 1.0,
        'height': 1.0,
        'depth': 1.0,
        'internal': true,
      },
      'color': '#9e9e9e',
      'source': 'manual',
      'confidence': .8,
      'lineage': 'local-only',
    },
  ],
  'visualDraft': {'version': 3},
};

void main() {
  test('save sends only the strict Scene v2 allowlist', () async {
    Map<String, Object?>? sent;
    final client = MockClient((request) async {
      sent = (jsonDecode(request.body) as Map).cast<String, Object?>();
      return http.Response(
        jsonEncode(sent),
        200,
        headers: {'etag': '"1"', 'content-type': 'application/json'},
      );
    });
    final api = StaffSceneApi(
      baseUrl: 'https://api.example.test',
      client: client,
    );

    final result = await api.save(
      accessToken: 'token',
      agencyId: 'agency-1',
      listingId: 'listing-1',
      document: _internalScene(),
      baseEtag: null,
    );

    expect(result, isA<SceneSaved>());
    expect(sent, isNotNull);
    expect(sent!.keys.toSet(), {'version', 'unit', 'walls', 'openings', 'rooms', 'objects'});
    expect(sent, isNot(contains('wallDimensions')));
    expect(sent, isNot(contains('visualDraft')));

    final wall = ((sent!['walls']! as List).single as Map).cast<String, Object?>();
    expect(
      wall.keys.toSet(),
      {'id', 'start', 'end', 'height', 'thickness', 'heightSource'},
    );
    expect(wall, isNot(contains('lengthM')));
    expect(wall, isNot(contains('measurementEvidence')));
    expect(
      ((wall['start']! as Map).cast<String, Object?>()).keys.toSet(),
      {'x', 'z'},
    );

    final opening =
        ((sent!['openings']! as List).single as Map).cast<String, Object?>();
    expect(
      opening.keys.toSet(),
      {'id', 'wallId', 'position', 'width', 'height', 'type'},
    );

    final room =
        ((sent!['rooms']! as List).single as Map).cast<String, Object?>();
    expect(room.keys.toSet(), {'id', 'name', 'wallIds'});

    final object =
        ((sent!['objects']! as List).single as Map).cast<String, Object?>();
    expect(
      object.keys.toSet(),
      {'id', 'type', 'position', 'dimensions', 'color', 'source', 'confidence'},
    );
    expect(
      ((object['position']! as Map).cast<String, Object?>()).keys.toSet(),
      {'x', 'y', 'z'},
    );
    expect(
      ((object['dimensions']! as Map).cast<String, Object?>()).keys.toSet(),
      {'width', 'height', 'depth'},
    );
  });

  test('FastAPI 422 details are converted to a safe validation failure', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'detail': [
            {
              'type': 'extra_forbidden',
              'loc': ['body', 'walls', 0, 'lengthM'],
              'msg': 'Extra inputs are not permitted',
              'input': 2.25,
            },
          ],
        }),
        422,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = StaffSceneApi(
      baseUrl: 'https://api.example.test',
      client: client,
    );

    await expectLater(
      api.save(
        accessToken: 'token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
        document: _internalScene(),
        baseEtag: null,
      ),
      throwsA(
        isA<StaffAuthFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 422)
            .having((failure) => failure.code, 'code', kValidationError)
            .having(
              (failure) => failure.detail,
              'detail',
              'La solicitud no es válida.',
            )
            .having(
              (failure) => failure.detail,
              'raw backend details',
              isNot(contains('lengthM')),
            ),
      ),
    );
  });
}
