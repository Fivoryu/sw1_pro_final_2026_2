import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:cliente_mobile/main.dart';

void main() {
  testWidgets('shows that catalog integration is pending', (tester) async {
    await tester.pumpWidget(const RoomForgeApp());

    expect(find.text('RoomForge'), findsOneWidget);
    expect(find.text('Catálogo pendiente de integración'), findsOneWidget);
    expect(
      find.text(
        'La aplicación todavía no está conectada a un catálogo de inmuebles.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps the pending state readable on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const RoomForgeApp());

    expect(find.text('Catálogo pendiente de integración'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
