import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

CapturedRoom _room(String id, RoomOpening opening) =>
    buildManualRectangularRoom(
      id: id,
      name: id,
      length: 4,
      width: 3,
      height: 2.65,
    ).copyWith(openings: [opening]);

const _visualDoor = RoomOpening(
  id: 'door-a2',
  wallId: 'top-b',
  edgeIndex: 0,
  position: 0.5,
  width: 0.8,
  height: 2.1,
  type: OpeningType.door,
);

const _externalDoor = RoomOpening(
  id: 'door-external',
  edgeIndex: 0,
  position: 0.5,
  width: 0.8,
  height: 2.1,
  type: OpeningType.door,
);

void main() {
  group('canonical wall opening resolution', () {
    test('uses projected edge when canonical measurements are still pending', () {
      final fixed = _room('visual', _visualDoor);
      final moving = _room('external', _externalDoor);
      expect(fixed.wallDimensions, isEmpty);
      expect(fixed.edgeIndexForOpening(_visualDoor), 0);

      final placement = placementForConnection(
        fixed: fixed,
        fixedOpeningId: 'door-a2',
        moving: moving,
        movingOpeningId: 'door-external',
        wallThickness: 0.12,
      );
      expect(placement.x.isFinite, isTrue);
      expect(placement.z.isFinite, isTrue);
      expect(placement.rotationDegrees.isFinite, isTrue);
    });

    test('canonical wall id overrides an outdated projected edge', () {
      final room = _room('measured', _visualDoor).copyWith(
        wallDimensions: const [
          CapturedWallDimension(wallId: 'left', lengthM: 4, heightM: 2.65),
          CapturedWallDimension(wallId: 'top-b', lengthM: 3, heightM: 2.65),
          CapturedWallDimension(wallId: 'right', lengthM: 4, heightM: 2.65),
          CapturedWallDimension(wallId: 'bottom', lengthM: 3, heightM: 2.65),
        ],
      );
      expect(room.edgeIndexForOpening(_visualDoor), 1);
    });

    test('rejects unknown canonical walls when measurements exist', () {
      final room = _room('measured', _visualDoor).copyWith(
        wallDimensions: const [
          CapturedWallDimension(wallId: 'a', lengthM: 4, heightM: 2.65),
          CapturedWallDimension(wallId: 'b', lengthM: 3, heightM: 2.65),
          CapturedWallDimension(wallId: 'c', lengthM: 4, heightM: 2.65),
          CapturedWallDimension(wallId: 'd', lengthM: 3, heightM: 2.65),
        ],
      );
      expect(room.edgeIndexForOpening(_visualDoor), isNull);
      expect(
        () => placementForConnection(
          fixed: room,
          fixedOpeningId: 'door-a2',
          moving: _room('external', _externalDoor),
          movingOpeningId: 'door-external',
          wallThickness: 0.12,
        ),
        throwsArgumentError,
      );
    });

    test('does not invent an edge when the projection has no index', () {
      const unresolved = RoomOpening(
        id: 'no-edge',
        wallId: 'top-b',
        position: 0.5,
        width: 0.8,
        height: 2.1,
        type: OpeningType.door,
      );
      final fixed = _room('visual', unresolved);
      expect(fixed.edgeIndexForOpening(unresolved), isNull);
      expect(
        () => placementForConnection(
          fixed: fixed,
          fixedOpeningId: 'no-edge',
          moving: _room('external', _externalDoor),
          movingOpeningId: 'door-external',
          wallThickness: 0.12,
        ),
        throwsArgumentError,
      );
    });
  });
}
