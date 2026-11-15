import 'package:captura_mobile/domain/spatial/floorplan_trace_editor.dart';
import 'package:captura_mobile/domain/spatial/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const _rectangle = [
  FloorPoint(0, 0),
  FloorPoint(1, 0),
  FloorPoint(1, 1),
  FloorPoint(0, 1),
];

void main() {
  test('moving a vertex keeps a simple closed trace', () {
    final moved = moveTraceVertex(_rectangle, 1, const FloorPoint(0.8, 0.1));
    expect(moved, isNotNull);
    expect(moved![1], const FloorPoint(0.8, 0.1));
    expect(isSimpleTraceContour(moved), isTrue);
  });

  test('split adds exactly one perimeter vertex', () {
    final split = splitTraceWall(_rectangle, 0, const FloorPoint(0.5, 0));
    expect(split, hasLength(5));
    expect(split![1], const FloorPoint(0.5, 0));
    expect(isSimpleTraceContour(split), isTrue);
  });

  test('only near-collinear adjacent walls can merge', () {
    const collinear = [
      FloorPoint(0, 0),
      FloorPoint(0.5, 0),
      FloorPoint(1, 0),
      FloorPoint(1, 1),
      FloorPoint(0, 1),
    ];
    expect(canMergeTraceWalls(collinear, 1), isTrue);
    expect(mergeTraceWalls(collinear, 1), hasLength(4));
    expect(canMergeTraceWalls(_rectangle, 1), isFalse);
    expect(mergeTraceWalls(_rectangle, 1), isNull);
  });

  test('opening projection follows the selected wall direction', () {
    expect(
      projectTracePosition(
        const FloorPoint(0.25, 0),
        const FloorPoint(0, 0),
        const FloorPoint(1, 0),
      ),
      closeTo(0.25, 1e-9),
    );
    expect(
      projectTracePosition(
        const FloorPoint(0.25, 0),
        const FloorPoint(1, 0),
        const FloorPoint(0, 0),
      ),
      closeTo(0.75, 1e-9),
    );
  });
}
