enum WallMeasurementCandidateStatus { proposed, unresolved, ambiguous, ignored }

class WallMeasurementCandidate {
  const WallMeasurementCandidate({
    required this.id,
    required this.literalText,
    required this.meters,
    this.rawValue,
    this.unit,
    this.edgeIndex,
    this.explicitUnit = false,
    this.ambiguityReason,
    this.status = WallMeasurementCandidateStatus.proposed,
  });

  final String id;
  final String literalText;

  /// Canonical metres only when the unit is explicit or the reading itself
  /// establishes a metric value. Null means the evidence is textual/numeric
  /// only and must never seed metric geometry or scale.
  final double? meters;

  /// Literal numeric reading before any unit conversion. Lets consumers
  /// compare textual evidence without inventing metres.
  final double? rawValue;

  /// Unit exactly as supplied by the provider. It is retained even when it is
  /// unknown and therefore cannot be converted to metres.
  final String? unit;

  final int? edgeIndex;
  final bool explicitUnit;
  final String? ambiguityReason;
  final WallMeasurementCandidateStatus status;

  WallMeasurementCandidate copyWith({
    int? edgeIndex,
    String? ambiguityReason,
    WallMeasurementCandidateStatus? status,
  }) => WallMeasurementCandidate(
    id: id,
    literalText: literalText,
    meters: meters,
    rawValue: rawValue,
    unit: unit,
    edgeIndex: edgeIndex ?? this.edgeIndex,
    explicitUnit: explicitUnit,
    ambiguityReason: ambiguityReason ?? this.ambiguityReason,
    status: status ?? this.status,
  );
}
