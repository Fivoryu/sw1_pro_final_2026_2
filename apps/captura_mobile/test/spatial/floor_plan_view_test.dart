import 'package:captura_mobile/ui/spatial/floor_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('door and window use distinct architectural primitives', () {
    const start = Offset(10, 30);
    const end = Offset(50, 30);
    final door = openingSymbolGeometry(start, end, isDoor: true);
    final window = openingSymbolGeometry(start, end, isDoor: false);

    expect(door.doorLeafEnd, isNotNull);
    expect(door.doorArc, isNotNull);
    expect(door.windowLines, isEmpty);
    expect(window.doorLeafEnd, isNull);
    expect(window.doorArc, isNull);
    expect(window.windowLines, hasLength(4));
  });

  test('wall label collision policy deterministically rejects overlap', () {
    final occupied = <Rect>[const Rect.fromLTWH(20, 20, 48, 14)];
    expect(
      acceptsWallLabel(const Rect.fromLTWH(24, 22, 48, 14), occupied),
      isFalse,
    );
    expect(
      acceptsWallLabel(const Rect.fromLTWH(90, 20, 48, 14), occupied),
      isTrue,
    );
  });

  testWidgets('multi-room floor plan renders without throwing', (tester) async {
    final document = <String, Object?>{
      'walls': [
        for (var index = 0; index < 8; index++)
          {
            'id': 'wall-$index',
            'start': {'x': (index % 4).toDouble(), 'z': (index ~/ 4) * 0.2},
            'end': {'x': (index % 4).toDouble() + 0.8, 'z': (index ~/ 4) * 0.2},
            'thickness': 0.15,
          },
      ],
      'rooms': [
        {
          'wallIds': ['wall-0', 'wall-1', 'wall-2', 'wall-3'],
        },
        {
          'wallIds': ['wall-4', 'wall-5', 'wall-6', 'wall-7'],
        },
      ],
      'openings': const [],
      'objects': const [],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FloorPlanView(document: document)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
