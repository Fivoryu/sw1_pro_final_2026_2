import 'dart:convert';

import 'package:captura_mobile/data/services/local_floorplan_analyzer.dart';
import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:captura_mobile/data/services/staff_floorplan_interpretation_api.dart';
import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _rectangle = [
  FloorPoint(0, 0),
  FloorPoint(400, 0),
  FloorPoint(400, 300),
  FloorPoint(0, 300),
];

StaffFloorplanInterpretationApi _api(Map<String, Object?> body) =>
    StaffFloorplanInterpretationApi(
      baseUrl: 'http://api.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

Future<FloorplanInterpretationResult> _interpret(
  StaffFloorplanInterpretationApi api,
) => api.interpret(
  accessToken: 'token',
  agencyId: 'agency',
  listingId: 'listing',
  imageBytes: [1, 2, 3],
  contentType: 'image/png',
);

Map<String, Object?> _room({
  List<Map<String, Object?>> dimensions = const [],
  List<Map<String, Object?>> openings = const [],
}) => {
  'id': 'candidate',
  'wallCount': 4,
  'contour': [
    {'x': 0.1, 'y': 0.1},
    {'x': 0.7, 'y': 0.1},
    {'x': 0.7, 'y': 0.7},
    {'x': 0.1, 'y': 0.7},
  ],
  'dimensions': dimensions,
  'openings': openings,
};

void main() {
  test('floorplan requests allow backend provider budget plus overhead', () {
    final api = StaffFloorplanInterpretationApi(
      baseUrl: 'https://api.example.test',
    );
    expect(api.timeout, const Duration(seconds: 40));
  });

  test('an unknown unit never becomes metres', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token');
      return http.Response(
        jsonEncode({
          'status': 'partial',
          'rooms': [
            {
              'id': 'candidate-c',
              'wallCount': 5,
              'contour': [
                {'x': 0.1, 'y': 0.1},
                {'x': 0.7, 'y': 0.1},
                {'x': 0.9, 'y': 0.5},
                {'x': 0.65, 'y': 0.9},
                {'x': 0.1, 'y': 0.8},
              ],
              'dimensions': [
                {
                  'edgeIndex': 2,
                  'literalText': '419',
                  'value': 419,
                  'unit': 'unknown',
                  'status': 'proposed',
                },
              ],
              'openings': [
                {'edgeIndex': 0, 'type': 'window', 'position': 0.3},
                {'edgeIndex': 1, 'type': 'window', 'position': 0.7},
                {'edgeIndex': 3, 'type': 'door', 'position': 0.5},
              ],
            },
          ],
          'warnings': [],
          'informationStillNeeded': ['Confirmar medidas'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final result =
        await StaffFloorplanInterpretationApi(
          baseUrl: 'http://api.test',
          client: client,
        ).interpret(
          accessToken: 'token',
          agencyId: 'agency',
          listingId: 'listing',
          imageBytes: [1, 2, 3],
          contentType: 'image/png',
        );

    expect(result.status, FloorplanInterpretationStatus.partial);
    expect(result.rooms.single.contour, hasLength(5));
    expect(result.rooms.single.openings, hasLength(3));
    final proposal = result.rooms.single.measurements.single;
    expect(proposal.literalText, '419');
    expect(proposal.meters, isNull);
    expect(proposal.rawValue, 419);
    expect(proposal.explicitUnit, isFalse);
    expect(proposal.status, WallMeasurementCandidateStatus.unresolved);
    expect(proposal.edgeIndex, 2);
  });

  test('an explicit unit is converted to metres', () async {
    final api = StaffFloorplanInterpretationApi(
      baseUrl: 'http://api.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'partial',
            'rooms': [
              {
                'id': 'candidate',
                'wallCount': 4,
                'contour': [
                  {'x': 0.1, 'y': 0.1},
                  {'x': 0.4, 'y': 0.1},
                  {'x': 0.4, 'y': 0.4},
                  {'x': 0.1, 'y': 0.4},
                ],
                'dimensions': [
                  {
                    'edgeIndex': 0,
                    'literalText': '410 cm',
                    'value': 410,
                    'unit': 'cm',
                    'status': 'proposed',
                  },
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );
    final result = await api.interpret(
      accessToken: 'token',
      agencyId: 'agency',
      listingId: 'listing',
      imageBytes: [1],
      contentType: 'image/png',
    );
    final proposal = result.rooms.single.measurements.single;
    expect(proposal.meters, closeTo(4.1, 1e-9));
    expect(proposal.explicitUnit, isTrue);
    expect(proposal.status, WallMeasurementCandidateStatus.proposed);
  });

  test(
    'invalid normalized provider numbers are rejected, not clamped',
    () async {
      final api = StaffFloorplanInterpretationApi(
        baseUrl: 'http://api.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'partial',
              'rooms': [
                {
                  'id': 'candidate',
                  'wallCount': 4,
                  'contour': [
                    {'x': 0.1, 'y': 0.1},
                    {'x': 0.4, 'y': 0.1},
                    {'x': 0.4, 'y': 0.4},
                    {'x': 0.1, 'y': 0.4},
                  ],
                  'openings': [
                    {'edgeIndex': 0, 'type': 'door', 'position': 1.4},
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        api.interpret(
          accessToken: 'token',
          agencyId: 'agency',
          listingId: 'listing',
          imageBytes: [1],
          contentType: 'image/png',
        ),
        throwsA(isA<StaffAuthFailure>()),
      );
    },
  );

  test('a provider conflict keeps evidence but never proposes scale', () async {
    final result = await _interpret(
      _api({
        'status': 'partial',
        'rooms': [
          _room(
            dimensions: [
              {
                'edgeIndex': 2,
                'literalText': '4.10 m',
                'value': 4.10,
                'unit': 'm',
                'status': 'conflict',
              },
            ],
          ),
        ],
      }),
    );
    final candidate = result.rooms.single.measurements.single;

    expect(candidate.meters, closeTo(4.10, 1e-9));
    expect(candidate.rawValue, closeTo(4.10, 1e-9));
    expect(candidate.edgeIndex, 2);
    expect(candidate.status, WallMeasurementCandidateStatus.ambiguous);
    expect(candidate.ambiguityReason, contains('conflictiva'));
    final solved = solveFloorplanMetrics(
      semanticContour: _rectangle,
      measurementCandidates: [candidate],
    );
    expect(solved.hasScale, isFalse);
    expect(solved.measurements, isEmpty);
  });

  test('a provider unresolved reading stays unresolved with metres', () async {
    final result = await _interpret(
      _api({
        'status': 'partial',
        'rooms': [
          _room(
            dimensions: [
              {
                'edgeIndex': 0,
                'literalText': '4.10 m',
                'value': 4.10,
                'unit': 'm',
                'status': 'unresolved',
              },
            ],
          ),
        ],
      }),
    );
    final candidate = result.rooms.single.measurements.single;

    expect(candidate.meters, closeTo(4.10, 1e-9));
    expect(candidate.status, WallMeasurementCandidateStatus.unresolved);
    final solved = solveFloorplanMetrics(
      semanticContour: _rectangle,
      measurementCandidates: [candidate],
    );
    expect(solved.hasScale, isFalse);
    expect(solved.measurements, isEmpty);
  });

  test('a provider proposed reading still establishes scale', () async {
    final result = await _interpret(
      _api({
        'status': 'partial',
        'rooms': [
          _room(
            dimensions: [
              {
                'edgeIndex': 0,
                'literalText': '4.10 m',
                'value': 4.10,
                'unit': 'm',
                'status': 'proposed',
              },
            ],
          ),
        ],
      }),
    );
    final candidate = result.rooms.single.measurements.single;

    expect(candidate.status, WallMeasurementCandidateStatus.proposed);
    final solved = solveFloorplanMetrics(
      semanticContour: _rectangle,
      measurementCandidates: [candidate],
    );
    expect(solved.hasScale, isTrue);
    expect(solved.measurements.first.referenceMeters, closeTo(4.10, 1e-9));
  });

  test('unknown or missing provider status is rejected as malformed', () async {
    for (final status in <Object?>['guessed', null, 7]) {
      final dimension = <String, Object?>{
        'edgeIndex': 0,
        'literalText': '4.10 m',
        'value': 4.10,
        'unit': 'm',
        if (status != null) 'status': status,
      };
      await expectLater(
        _interpret(
          _api({
            'status': 'partial',
            'rooms': [
              _room(dimensions: [dimension]),
            ],
          }),
        ),
        throwsA(isA<StaffAuthFailure>()),
        reason: 'status=$status',
      );
    }
  });

  test(
    'an opening without geometry stays unresolved, never 0.5/0.15',
    () async {
      final result = await _interpret(
        _api({
          'status': 'partial',
          'rooms': [
            _room(
              openings: [
                {'edgeIndex': 2, 'type': 'door'},
              ],
            ),
          ],
        }),
      );
      final opening = result.rooms.single.openings.single;

      expect(opening.edgeIndex, 2);
      expect(opening.type, FloorplanOpeningCandidateType.door);
      expect(opening.position, isNull);
      expect(opening.normalizedWidth, isNull);
      expect(opening.hasGeometry, isFalse);
      expect(opening.toCanonicalCandidate(), isNull);
    },
  );

  test('explicit opening geometry is preserved exactly', () async {
    final result = await _interpret(
      _api({
        'status': 'partial',
        'rooms': [
          _room(
            openings: [
              {
                'edgeIndex': 1,
                'type': 'window',
                'position': 0.375,
                'normalizedWidth': 0.125,
                'confidence': 0.8,
              },
            ],
          ),
        ],
      }),
    );
    final opening = result.rooms.single.openings.single;

    expect(opening.position, 0.375);
    expect(opening.normalizedWidth, 0.125);
    expect(opening.confidence, 0.8);
    expect(opening.type, FloorplanOpeningCandidateType.window);
    expect(opening.hasGeometry, isTrue);
    final canonical = opening.toCanonicalCandidate();
    expect(canonical, isNotNull);
    expect(canonical!.edgeIndex, 1);
    expect(canonical.position, 0.375);
    expect(canonical.normalizedWidth, 0.125);
  });

  test('a known opening position keeps a missing width unresolved', () async {
    final result = await _interpret(
      _api({
        'status': 'partial',
        'rooms': [
          _room(
            openings: [
              {'edgeIndex': 0, 'type': 'door', 'position': 0.42},
            ],
          ),
        ],
      }),
    );
    final opening = result.rooms.single.openings.single;

    expect(opening.position, 0.42);
    expect(opening.normalizedWidth, isNull);
    expect(opening.hasGeometry, isFalse);
    expect(opening.toCanonicalCandidate(), isNull);
  });

  test('a zero opening width is rejected, not clamped', () async {
    await expectLater(
      _interpret(
        _api({
          'status': 'partial',
          'rooms': [
            _room(
              openings: [
                {'edgeIndex': 0, 'type': 'door', 'normalizedWidth': 0},
              ],
            ),
          ],
        }),
      ),
      throwsA(isA<StaffAuthFailure>()),
    );
  });

  test('preserves multiple candidates instead of selecting one', () async {
    Map<String, Object?> room(String id) => {
      'id': id,
      'wallCount': 4,
      'contour': [
        {'x': 0.1, 'y': 0.1},
        {'x': 0.4, 'y': 0.1},
        {'x': 0.4, 'y': 0.4},
        {'x': 0.1, 'y': 0.4},
      ],
    };
    final api = StaffFloorplanInterpretationApi(
      baseUrl: 'http://api.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'needs_review',
            'rooms': [room('a'), room('b')],
          }),
          200,
        ),
      ),
    );
    final result = await api.interpret(
      accessToken: 'token',
      agencyId: 'agency',
      listingId: 'listing',
      imageBytes: [1],
      contentType: 'image/jpeg',
    );
    expect(result.rooms.map((room) => room.id), ['a', 'b']);
  });
}

class MockClient extends http.BaseClient {
  MockClient(this.handler);
  final Future<http.Response> Function(http.BaseRequest request) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
