import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cliente_mobile/main.dart';

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('catalog-filter-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('has exactly three customer tabs', (tester) async {
    await tester.pumpWidget(const RoomForgeApp());
    final nav = find.byType(NavigationBar);
    for (final label in ['Explorar', 'Reservas', 'Cuenta']) {
      expect(find.descendant(of: nav, matching: find.text(label)), findsOneWidget);
    }
    expect(find.descendant(of: nav, matching: find.byType(Text)), findsNWidgets(3));
  });

  testWidgets('shows an honest empty catalog', (tester) async {
    await tester.pumpWidget(const RoomForgeApp());
    expect(find.text('Catálogo sin conexión'), findsOneWidget);
    expect(find.text(
      'La aplicación todavía no está conectada a un catálogo de inmuebles.',
    ), findsOneWidget);
  });

  testWidgets('offers only approved filters and keeps entries local', (
    tester,
  ) async {
    await tester.pumpWidget(const RoomForgeApp());
    await openFilters(tester);
    expect(find.text('Filtros del catálogo'), findsOneWidget);
    for (final label in [
      'Ciudad/zona', 'Operación', 'Precio base', 'Habitaciones', 'Baños',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Buscar'), findsNothing);
    expect(find.text(
      'Los filtros son una demostración local; no hay API ni resultados conectados.',
    ), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('catalog-filter-button'))).height,
        greaterThanOrEqualTo(48));

    await tester.enterText(find.byKey(const ValueKey('filter-city-zone')), 'Centro');
    await tester.tap(find.text('Guardar filtros'));
    await tester.pumpAndSettle();
    await openFilters(tester);
    expect(tester.widget<TextFormField>(
      find.byKey(const ValueKey('filter-city-zone')),
    ).controller!.text, 'Centro');
  });

  testWidgets('reservations and account remain prototypes', (tester) async {
    await tester.pumpWidget(const RoomForgeApp());
    await tester.tap(find.text('Reservas'));
    await tester.pumpAndSettle();
    expect(find.text('Prototipo de reservas'), findsOneWidget);
    expect(find.text('No hay reservas reales ni datos conectados.'), findsOneWidget);
    await tester.tap(find.text('Cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Prototipo de cuenta'), findsOneWidget);
    expect(find.text('No hay datos de cuenta conectados.'), findsOneWidget);
  });

  testWidgets('fits at 320 pixels wide', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RoomForgeApp());
    expect(tester.takeException(), isNull);
    await openFilters(tester);
    expect(find.text('Filtros del catálogo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
