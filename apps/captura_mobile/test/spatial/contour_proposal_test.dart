import 'dart:math' as math;

import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rotates [p] by [degrees] around the origin and shifts it, as ARCore world
/// coordinates are arbitrary.
FloorPoint _world(FloorPoint p, {double degrees = 20}) {
  final r = degrees * math.pi / 180;
  return FloorPoint(
    p.x * math.cos(r) - p.z * math.sin(r) + 3,
    p.x * math.sin(r) + p.z * math.cos(r) - 2,
  );
}

ObservedWall _wall(double x1, double z1, double x2, double z2) => ObservedWall(
  start: _world(FloorPoint(x1, z1)),
  end: _world(FloorPoint(x2, z2)),
  area: 2,
  minY: -1.2,
  maxY: 0.6,
);

WalkthroughObservations _observations(List<ObservedWall> walls) =>
    WalkthroughObservations(
      floorY: -1.3,
      walls: walls,
      floors: [
        [
          _world(const FloorPoint(0.5, 0.5)),
          _world(const FloorPoint(3.5, 0.5)),
          _world(const FloorPoint(3.5, 2.5)),
          _world(const FloorPoint(0.5, 2.5)),
        ],
      ],
      trajectory: [
        _world(const FloorPoint(1, 1)),
        _world(const FloorPoint(3, 1)),
        _world(const FloorPoint(3, 2)),
        _world(const FloorPoint(1, 2)),
      ],
    );

List<double> _sortedLengths(List<FloorPoint> corners) =>
    edgeLengths(corners)..sort();

void main() {
  test('proposes a 4 × 3 room from walls seen only in part', () {
    // Each wall is observed away from the corners, as ARCore rarely reaches them.
    final proposal = proposeContour(
      _observations([
        _wall(0.6, 0, 3.2, 0),
        _wall(4, 0.4, 4, 2.5),
        _wall(3.5, 3, 0.8, 3),
        _wall(0, 2.6, 0, 0.3),
      ]),
    );

    expect(proposal, isA<ProposedContour>());
    final contour = proposal as ProposedContour;
    expect(contour.corners, hasLength(4));
    final lengths = _sortedLengths(contour.corners);
    expect(lengths[0], closeTo(3, 0.01));
    expect(lengths[3], closeTo(4, 0.01));
    expect(contour.inferredEdges, 0);
    expect(contour.observedWalls, 4);
  });

  test('snaps slightly crooked observations to square walls', () {
    final proposal =
        proposeContour(
              _observations([
                _wall(0.6, 0.02, 3.2, -0.03),
                _wall(4.03, 0.4, 3.98, 2.5),
                _wall(3.5, 3.02, 0.8, 2.99),
                _wall(-0.01, 2.6, 0.02, 0.3),
              ]),
            )
            as ProposedContour;

    final lengths = _sortedLengths(proposal.corners);
    expect(lengths[0], closeTo(3, 0.03));
    expect(lengths[3], closeTo(4, 0.03));
    expect(polygonArea(proposal.corners), closeTo(12, 0.15));
  });

  test('merges a wall that ARCore split into two planes', () {
    final proposal =
        proposeContour(
              _observations([
                _wall(0.4, 0, 1.6, 0),
                _wall(2.2, 0.01, 3.6, 0.01),
                _wall(4, 0.4, 4, 2.5),
                _wall(3.5, 3, 0.8, 3),
                _wall(0, 2.6, 0, 0.3),
              ]),
            )
            as ProposedContour;

    expect(proposal.corners, hasLength(4));
    expect(proposal.observedWalls, 4);
  });

  test('ignores a furniture face standing in front of a wall', () {
    final proposal =
        proposeContour(
              _observations([
                _wall(0.6, 0, 3.2, 0),
                _wall(4, 0.4, 4, 2.5),
                _wall(3.5, 3, 0.8, 3),
                // Wardrobe front 0.6 m inside the far wall.
                _wall(3.2, 2.4, 1.4, 2.4),
                _wall(0, 2.6, 0, 0.3),
              ]),
            )
            as ProposedContour;

    expect(proposal.corners, hasLength(4));
    expect(polygonArea(proposal.corners), closeTo(12, 0.05));
  });

  test('infers the side of a wall that was never detected', () {
    // The left wall is plain white: ARCore found no plane there.
    final proposal =
        proposeContour(
              _observations([
                _wall(0.6, 0, 3.2, 0),
                _wall(4, 0.4, 4, 2.5),
                _wall(3.5, 3, 0.8, 3),
              ]),
            )
            as ProposedContour;

    expect(proposal.corners, hasLength(4));
    expect(proposal.inferredEdges, 1);
    expect(proposal.observedWalls, 3);
  });

  test('follows an L-shaped room', () {
    final proposal =
        proposeContour(
              WalkthroughObservations(
                floorY: -1.3,
                walls: [
                  _wall(0.5, 0, 5.5, 0),
                  _wall(6, 0.3, 6, 2.7),
                  _wall(5.6, 3, 3.4, 3),
                  _wall(3, 3.4, 3, 4.6),
                  _wall(2.6, 5, 0.4, 5),
                  _wall(0, 4.6, 0, 0.4),
                ],
                floors: [
                  [
                    _world(const FloorPoint(0.5, 0.5)),
                    _world(const FloorPoint(5.5, 0.5)),
                    _world(const FloorPoint(5.5, 2.5)),
                    _world(const FloorPoint(0.5, 2.5)),
                  ],
                ],
                trajectory: [
                  _world(const FloorPoint(1, 1)),
                  _world(const FloorPoint(4, 1.5)),
                  _world(const FloorPoint(1.5, 4)),
                ],
              ),
            )
            as ProposedContour;

    expect(proposal.corners, hasLength(6));
    expect(polygonArea(proposal.corners), closeTo(6 * 3 + 3 * 2, 0.05));
  });

  test('explains when too few walls were observed', () {
    final proposal = proposeContour(
      _observations([_wall(0.6, 0, 3.2, 0), _wall(4, 0.4, 4, 2.5)]),
    );

    expect(proposal, isA<ProposalFailed>());
    expect((proposal as ProposalFailed).message, contains('Marcar paredes'));
  });

  test('reads the native observations payload', () {
    final observations = WalkthroughObservations.fromJson({
      'floorY': -1.3,
      'walls': [
        {
          'start': {'x': 0.0, 'z': 0.0},
          'end': {'x': 4.0, 'z': 0.0},
          'area': 3.5,
          'minY': -1.2,
          'maxY': 0.7,
        },
      ],
      'floors': [
        [
          {'x': 0.0, 'z': 0.0},
          {'x': 1.0, 'z': 0.0},
          {'x': 1.0, 'z': 1.0},
        ],
      ],
      'trajectory': [
        {'x': 0.5, 'z': 0.5},
      ],
    });

    expect(observations.walls.single.end, const FloorPoint(4, 0));
    expect(observations.floors.single, hasLength(3));
    expect(observations.trajectory.single, const FloorPoint(0.5, 0.5));
  });
}
