import 'package:cliente_mobile/data/models/catalog_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/catalog_format.dart';
import 'package:cliente_mobile/ui/features/catalog/views/catalog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_catalog_backend.dart';

({CatalogController controller, FakeCatalogBackend backend}) _build() {
  final backend = FakeCatalogBackend();
  return (
    controller: CatalogController(
      api: CatalogApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
    ),
    backend: backend,
  );
}

Future<void> _pumpCatalog(
  WidgetTester tester,
  CatalogController controller, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: CatalogScreen(controller: controller)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _setNarrowViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('formatting', () {
    test('formats COP amounts without floating point', () {
      expect(formatCop('2500000.00'), 'COP 2.500.000,00');
      expect(formatCop('999.5'), 'COP 999,50');
      expect(
        formatCop('12345678901234567.89'),
        'COP 12.345.678.901.234.567,89',
      );
    });
  });

  group('catalog list', () {
    testWidgets('shows published listings with their periodicity', (
      tester,
    ) async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1', city: 'Medellín', zone: 'Laureles');
      harness.backend.seed(
        id: 'rent-1',
        operation: 'rent',
        amount: '2500000.00',
        city: 'Bogotá',
        zone: 'Chapinero',
      );

      await _pumpCatalog(tester, harness.controller);

      final rent = find.byKey(const ValueKey('catalog-listing-rent-1'));
      expect(
        find.descendant(of: rent, matching: find.text('Bogotá, Chapinero')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rent, matching: find.text('Alquiler')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rent,
          matching: find.text('COP 2.500.000,00 por mes'),
        ),
        findsOneWidget,
      );
      final sale = find.byKey(const ValueKey('catalog-listing-sale-1'));
      expect(
        find.descendant(of: sale, matching: find.text('COP 350.000.000,00')),
        findsOneWidget,
      );
      expect(find.textContaining('por mes'), findsOneWidget);
      expect(find.textContaining('sintética'), findsNothing);
    });

    testWidgets('says when nothing is published yet', (tester) async {
      final harness = _build();

      await _pumpCatalog(tester, harness.controller);

      expect(find.byKey(const ValueKey('catalog-empty')), findsOneWidget);
      expect(find.text('Todavía no hay inmuebles publicados.'), findsOneWidget);
      expect(find.byKey(const ValueKey('catalog-clear-filters')), findsNothing);
    });

    testWidgets('offers to clear filters that match nothing', (tester) async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1');
      await harness.controller.search(
        const CatalogFilters(operation: ListingOperation.rent),
      );

      await _pumpCatalog(tester, harness.controller);
      expect(find.text('No hay inmuebles con esos filtros.'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('catalog-clear-filters')));

      expect(harness.controller.filters.isEmpty, isTrue);
      expect(
        find.byKey(const ValueKey('catalog-listing-sale-1')),
        findsOneWidget,
      );
    });

    testWidgets('retries after a connection failure', (tester) async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1');
      harness.backend.offline = true;

      await _pumpCatalog(tester, harness.controller);
      expect(find.byKey(const ValueKey('catalog-error')), findsOneWidget);
      expect(find.textContaining('conexión'), findsOneWidget);

      harness.backend.offline = false;
      await _tap(tester, find.byKey(const ValueKey('catalog-retry')));

      expect(
        find.byKey(const ValueKey('catalog-listing-sale-1')),
        findsOneWidget,
      );
    });

    testWidgets('loads more listings on request', (tester) async {
      final harness = _build();
      for (var index = 0; index < 21; index++) {
        harness.backend.seed(id: 'listing-$index');
      }

      await _pumpCatalog(tester, harness.controller);
      expect(
        find.byKey(const ValueKey('catalog-listing-listing-0')),
        findsNothing,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('catalog-load-more')),
        300,
      );
      await _tap(tester, find.byKey(const ValueKey('catalog-load-more')));

      expect(harness.controller.items, hasLength(21));
      expect(find.byKey(const ValueKey('catalog-load-more')), findsNothing);
    });
  });

  group('filters', () {
    testWidgets('applies the approved filters to the search', (tester) async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1');
      harness.backend.seed(id: 'rent-1', operation: 'rent', city: 'Bogotá');

      await _pumpCatalog(tester, harness.controller);
      await _tap(tester, find.byKey(const ValueKey('catalog-filter-button')));

      for (final label in [
        'Ciudad',
        'Zona',
        'Operación',
        'Precio mínimo (COP)',
        'Precio máximo (COP)',
        'Dormitorios mínimos',
        'Baños mínimos',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.enterText(
        find.byKey(const ValueKey('filter-city')),
        ' Bogotá ',
      );
      await _tap(tester, find.byKey(const ValueKey('filter-operation')));
      await tester.tap(find.text('Alquiler').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('filter-min-price')),
        '1000000,5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('filter-bedrooms')),
        '2',
      );
      await _tap(tester, find.byKey(const ValueKey('filter-apply')));

      final filters = harness.controller.filters;
      expect(filters.city, 'Bogotá');
      expect(filters.zone, isNull);
      expect(filters.operation, ListingOperation.rent);
      expect(filters.minBasePrice, '1000000.5');
      expect(filters.minBedrooms, 2);
      expect(
        find.byKey(const ValueKey('catalog-listing-rent-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-listing-sale-1')),
        findsNothing,
      );
    });

    testWidgets('rejects values the API would reject', (tester) async {
      final harness = _build();

      await _pumpCatalog(tester, harness.controller);
      await _tap(tester, find.byKey(const ValueKey('catalog-filter-button')));
      await tester.enterText(
        find.byKey(const ValueKey('filter-min-price')),
        '500.123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('filter-max-price')),
        '100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('filter-bathrooms')),
        '1.5',
      );
      await _tap(tester, find.byKey(const ValueKey('filter-apply')));

      expect(
        find.text('Usá hasta 16 dígitos enteros y 2 decimales.'),
        findsOneWidget,
      );
      expect(find.text('Ingresá un número entero.'), findsOneWidget);
      expect(harness.controller.filters.isEmpty, isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('filter-min-price')),
        '500',
      );
      await tester.enterText(
        find.byKey(const ValueKey('filter-bathrooms')),
        '',
      );
      await _tap(tester, find.byKey(const ValueKey('filter-apply')));

      expect(
        find.text('El mínimo no puede superar al máximo.'),
        findsOneWidget,
      );
      expect(harness.controller.filters.isEmpty, isTrue);
    });
  });

  group('detail', () {
    testWidgets('shows the base price, rooms, extras and honest notices', (
      tester,
    ) async {
      final harness = _build();
      harness.backend.seed(
        id: 'rent-1',
        operation: 'rent',
        amount: '2500000.00',
        bedrooms: 3,
        bathrooms: 1,
        extras: const [(id: 'extra-1', name: 'Sofá en L', amount: '150000.00')],
      );

      await _pumpCatalog(tester, harness.controller);
      await _tap(tester, find.byKey(const ValueKey('catalog-listing-rent-1')));

      final detail = find.byKey(const ValueKey('property-detail-content'));
      for (final text in [
        'Medellín, El Poblado',
        'COP 2.500.000,00 por mes',
        'Precio base mensual. No incluye los opcionales.',
        '3 dormitorios · 1 baño',
        'Sofá en L',
        'COP 150.000,00 por mes',
        'Recorrido 3D no disponible.',
        'Disponibilidad no consultada ni confirmada.',
      ]) {
        expect(
          find.descendant(of: detail, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        find.descendant(of: detail, matching: find.text('Reservar')),
        findsNothing,
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Explorar inmuebles'), findsOneWidget);
    });

    testWidgets('a sale has a one-time base price and may have no extras', (
      tester,
    ) async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1', bedrooms: 1, bathrooms: 2);

      await _pumpCatalog(tester, harness.controller);
      await _tap(tester, find.byKey(const ValueKey('catalog-listing-sale-1')));

      expect(
        find.text('Precio base de pago único. No incluye los opcionales.'),
        findsOneWidget,
      );
      expect(find.text('1 dormitorio · 2 baños'), findsOneWidget);
      expect(find.text('Este inmueble no tiene opcionales.'), findsOneWidget);
      expect(find.textContaining('por mes'), findsNothing);
    });

    testWidgets('explains a listing that was withdrawn meanwhile', (
      tester,
    ) async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1');

      await _pumpCatalog(tester, harness.controller);
      harness.backend.failWithStatus = 404;
      await _tap(tester, find.byKey(const ValueKey('catalog-listing-sale-1')));

      expect(find.text('Este inmueble ya no está publicado.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('property-detail-content')),
        findsNothing,
      );
    });
  });

  testWidgets('list and detail fit 320 pixels with larger text', (
    tester,
  ) async {
    _setNarrowViewport(tester);
    final harness = _build();
    harness.backend.seed(
      id: 'rent-1',
      operation: 'rent',
      amount: '123456789012.00',
      city: 'San José de Cúcuta',
      zone: 'Barrio Quinta Oriental',
      extras: const [
        (id: 'extra-1', name: 'Comedor de seis puestos', amount: '1.00'),
      ],
    );

    await _pumpCatalog(tester, harness.controller, textScale: 1.5);
    expect(tester.takeException(), isNull);

    await _tap(tester, find.byKey(const ValueKey('catalog-filter-button')));
    expect(tester.takeException(), isNull);
    // At this size the sheet covers the screen; dismiss it like the back key.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const ValueKey('catalog-listing-rent-1')));
    expect(
      find.byKey(const ValueKey('property-detail-content')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
