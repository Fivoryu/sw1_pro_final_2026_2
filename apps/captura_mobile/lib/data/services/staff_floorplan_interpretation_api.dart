import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../domain/spatial/geometry.dart';
import '../../domain/spatial/wall_measurement_candidate.dart';
import 'local_floorplan_analyzer.dart';
import 'staff_auth_failure.dart';

enum FloorplanInterpretationStatus {
  success,
  partial,
  needsReview,
  lowConfidence,
  providerUnavailable,
  invalidInput,
}

class InterpretedOpeningProposal {
  const InterpretedOpeningProposal({
    required this.edgeIndex,
    required this.type,
    this.position,
    this.normalizedWidth,
    this.confidence,
  });

  final int edgeIndex;
  final FloorplanOpeningCandidateType type;

  /// Normalized opening geometry. Null means the provider did not supply it
  /// and the value must remain unknown until human review.
  final double? position;
  final double? normalizedWidth;
  final double? confidence;

  bool get hasGeometry => position != null && normalizedWidth != null;

  /// Canonical geometry is only produced when both spatial facts are known.
  FloorplanOpeningCandidate? toCanonicalCandidate() {
    final position = this.position;
    final normalizedWidth = this.normalizedWidth;
    if (position == null || normalizedWidth == null) return null;
    return FloorplanOpeningCandidate(
      edgeIndex: edgeIndex,
      position: position,
      normalizedWidth: normalizedWidth,
      type: type,
    );
  }
}

class InterpretedRoomCandidate {
  const InterpretedRoomCandidate({
    required this.id,
    required this.contour,
    required this.measurements,
    required this.openings,
    this.label,
  });

  final String id;
  final String? label;
  final List<FloorPoint> contour;
  final List<WallMeasurementCandidate> measurements;
  final List<InterpretedOpeningProposal> openings;
}

class FloorplanInterpretationResult {
  const FloorplanInterpretationResult({
    required this.status,
    this.rooms = const [],
    this.warnings = const [],
    this.informationStillNeeded = const [],
  });

  final FloorplanInterpretationStatus status;
  final List<InterpretedRoomCandidate> rooms;
  final List<String> warnings;
  final List<String> informationStillNeeded;
  bool get hasCandidate => rooms.isNotEmpty;
}

abstract interface class FloorplanInterpretationApi {
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  });
}

class StaffFloorplanInterpretationApi implements FloorplanInterpretationApi {
  StaffFloorplanInterpretationApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 40),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/v1/staff/agencies/${Uri.encodeComponent(agencyId)}'
      '/listings/${Uri.encodeComponent(listingId)}/floorplan-interpretations',
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'floorplan.${_extension(contentType)}',
          contentType: _mediaType(contentType),
        ),
      );
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw failureFromResponse(statusCode: response.statusCode, body: text);
    }
    try {
      return _parse(jsonDecode(text) as Map<String, Object?>);
    } on Object {
      throw malformedResponseFailure();
    }
  }
}

FloorplanInterpretationResult _parse(Map<String, Object?> json) {
  final status = switch (json['status']) {
    'success' => FloorplanInterpretationStatus.success,
    'partial' => FloorplanInterpretationStatus.partial,
    'needs_review' => FloorplanInterpretationStatus.needsReview,
    'low_confidence' => FloorplanInterpretationStatus.lowConfidence,
    'provider_unavailable' => FloorplanInterpretationStatus.providerUnavailable,
    'invalid_input' => FloorplanInterpretationStatus.invalidInput,
    _ => throw const FormatException('Unknown interpretation status'),
  };
  final roomsJson = json['rooms'];
  final rooms = <InterpretedRoomCandidate>[];
  if (roomsJson is List) {
    for (final (roomIndex, raw) in roomsJson.indexed) {
      if (raw is! Map<String, Object?>) throw const FormatException();
      final points = (raw['contour'] as List)
          .map((point) {
            final map = point as Map<String, Object?>;
            return FloorPoint(
              (map['x'] as num).toDouble(),
              (map['y'] as num).toDouble(),
            );
          })
          .toList(growable: false);
      if (points.length < 3 || raw['wallCount'] != points.length) {
        throw const FormatException('Invalid contour');
      }
      final dimensions = <WallMeasurementCandidate>[];
      for (final (index, value)
          in ((raw['dimensions'] as List?) ?? const []).indexed) {
        final item = value as Map<String, Object?>;
        final numeric = item['value'];
        final edge = item['edgeIndex'];
        if (numeric is! num || numeric <= 0) continue;
        final literalValue = numeric.toDouble();
        if (!literalValue.isFinite) {
          throw const FormatException('Invalid dimension value');
        }
        // Provider status is authoritative for review state; never infer
        // "proposed" from a metric value alone.
        final providerStatus = switch (item['status']) {
          'proposed' => 'proposed',
          'unresolved' => 'unresolved',
          'conflict' => 'conflict',
          _ => throw const FormatException('Unknown dimension status'),
        };
        // An unknown unit is textual evidence only: it never becomes metres.
        final meters = _metres(literalValue, item['unit']);
        final associated = edge is int && edge >= 0 && edge < points.length;
        final status = switch (providerStatus) {
          'conflict' => WallMeasurementCandidateStatus.ambiguous,
          'unresolved' => WallMeasurementCandidateStatus.unresolved,
          _ when !associated => WallMeasurementCandidateStatus.ambiguous,
          _ when meters == null => WallMeasurementCandidateStatus.unresolved,
          _ => WallMeasurementCandidateStatus.proposed,
        };
        dimensions.add(
          WallMeasurementCandidate(
            id: 'ai-$roomIndex-$index',
            literalText: item['literalText'] as String? ?? numeric.toString(),
            meters: meters,
            rawValue: literalValue,
            edgeIndex: associated ? edge : null,
            explicitUnit: meters != null,
            ambiguityReason: switch (providerStatus) {
              'conflict' =>
                'El proveedor marcó esta medida como conflictiva; requiere revisión humana.',
              'unresolved' =>
                'El proveedor marcó esta medida como no resuelta; solo es evidencia.',
              _ when !associated =>
                'La IA no pudo asociar esta medida con una pared.',
              _ when meters == null =>
                'La IA leyó una medida sin una unidad métrica confirmada; solo es evidencia textual.',
              _ => null,
            },
            status: status,
          ),
        );
      }
      final openings = <InterpretedOpeningProposal>[];
      for (final value in ((raw['openings'] as List?) ?? const [])) {
        final item = value as Map<String, Object?>;
        final edge = item['edgeIndex'];
        if (edge is! int || edge < 0 || edge >= points.length) {
          throw const FormatException('Opening references an invalid wall');
        }
        openings.add(
          InterpretedOpeningProposal(
            edgeIndex: edge,
            position: _optionalNormalizedValue(
              item['position'],
              field: 'opening position',
            ),
            normalizedWidth: _optionalNormalizedValue(
              item['normalizedWidth'],
              field: 'opening width',
              exclusiveMinimum: true,
            ),
            confidence: _optionalNormalizedValue(
              item['confidence'],
              field: 'opening confidence',
            ),
            type: switch (item['type']) {
              'door' => FloorplanOpeningCandidateType.door,
              'window' => FloorplanOpeningCandidateType.window,
              _ => FloorplanOpeningCandidateType.unknown,
            },
          ),
        );
      }
      rooms.add(
        InterpretedRoomCandidate(
          id: raw['id'] as String? ?? 'room-$roomIndex',
          label: raw['label'] as String?,
          contour: points,
          measurements: dimensions,
          openings: openings,
        ),
      );
    }
  }
  return FloorplanInterpretationResult(
    status: status,
    rooms: rooms,
    warnings: _strings(json['warnings']),
    informationStillNeeded: _strings(json['informationStillNeeded']),
  );
}

List<String> _strings(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is String) item,
      ]
    : const [];

double? _metres(double value, Object? unit) => switch (unit) {
  'm' => value,
  'cm' => value / 100,
  'mm' => value / 1000,
  _ => null,
};

/// Provider values are validated, not clamped: an out-of-range or non-finite
/// proposal is a malformed response and must be rejected. Missing geometry
/// stays null so it can never become fabricated canonical geometry.
double? _optionalNormalizedValue(
  Object? value, {
  required String field,
  bool exclusiveMinimum = false,
}) {
  if (value == null) return null;
  if (value is! num) throw const FormatException('Invalid normalized value');
  final parsed = value.toDouble();
  final valid =
      parsed.isFinite &&
      (exclusiveMinimum
          ? parsed > 0 && parsed <= 1
          : parsed >= 0 && parsed <= 1);
  if (!valid) throw FormatException('Invalid $field');
  return parsed;
}

String _extension(String contentType) => switch (contentType) {
  'image/png' => 'png',
  'image/webp' => 'webp',
  _ => 'jpg',
};

MediaType _mediaType(String value) {
  final parts = value.split('/');
  return MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg');
}
