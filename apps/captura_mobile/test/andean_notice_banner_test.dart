import 'package:captura_mobile/ui/theme/andean_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notice banner wraps safely at 360 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AndeanNoticeBanner(
              title: 'Revisión requerida para sincronizar',
              badge: 'Pendiente de confirmación',
              message:
                  'Las medidas ingresadas todavía no permiten cerrar el ambiente. Revisá cada pared antes de continuar.',
              variant: AndeanBannerVariant.warning,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('Las medidas ingresadas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
