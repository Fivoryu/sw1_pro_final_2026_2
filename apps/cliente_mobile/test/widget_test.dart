import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:cliente_mobile/main.dart';

import 'support/fake_catalog_backend.dart';
import 'support/fake_customer_backend.dart';

/// The shell needs a session controller; the fake backends keep these shell
/// tests independent from the network.
CustomerSessionController testSession() => CustomerSessionController(
  api: CustomerAuthApi(
    baseUrl: 'https://api.example.test',
    client: FakeCustomerBackend().client,
  ),
  tokenStore: InMemoryCustomerTokenStore(),
);

CatalogApi testCatalog([FakeCatalogBackend? backend]) => CatalogApi(
  baseUrl: 'https://api.example.test',
  client: (backend ?? FakeCatalogBackend()).client,
);

RoomForgeApp app([FakeCatalogBackend? catalog]) => RoomForgeApp(
  sessionController: testSession(),
  catalogApi: testCatalog(catalog),
);

/// A catalog with one published listing, as the API would return it.
FakeCatalogBackend publishedCatalog() =>
    FakeCatalogBackend()..seed(id: 'listing-1', operation: 'rent');

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('catalog-filter-button')));
  await tester.pumpAndSettle();
}

void setNarrowViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('has exactly three customer tabs', (tester) async {
    await tester.pumpWidget(app());
    final nav = find.byType(NavigationBar);
    for (final label in ['Explorar', 'Reservas', 'Cuenta']) {
      expect(
        find.descendant(of: nav, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: nav, matching: find.byType(Text)),
      findsNWidgets(3),
    );
  });

  testWidgets('explores the published catalog without signing in', (
    tester,
  ) async {
    await tester.pumpWidget(app(publishedCatalog()));
    await tester.pumpAndSettle();
    expect(find.text('Explorar inmuebles'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('catalog-listing-listing-1')),
      findsOneWidget,
    );
    expect(find.textContaining('sintética'), findsNothing);
    expect(find.text('Catálogo sin conexión'), findsNothing);
  });

  testWidgets('offers only approved filters and keeps the applied ones', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openFilters(tester);
    expect(find.text('Filtros del catálogo'), findsOneWidget);
    for (final label in [
      'Ciudad',
      'Zona',
      'Operación',
      'Precio mínimo',
      'Precio máximo',
      'Dormitorios mínimos',
      'Baños mínimos',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('catalog-filter-button')))
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.enterText(find.byKey(const ValueKey('filter-city')), 'Centro');
    await tester.ensureVisible(find.byKey(const ValueKey('filter-apply')));
    await tester.tap(find.byKey(const ValueKey('filter-apply')));
    await tester.pumpAndSettle();
    await openFilters(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('filter-city')))
          .controller!
          .text,
      'Centro',
    );
  });

  testWidgets(
    'reservations remain a prototype and the account offers sign-in',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('Reservas'));
      await tester.pumpAndSettle();
      expect(find.text('Prototipo de reservas'), findsOneWidget);
      expect(
        find.text('No hay reservas reales ni datos conectados.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-submit')), findsOneWidget);
    },
  );

  testWidgets('fits at 320 pixels wide', (tester) async {
    setNarrowViewport(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await openFilters(tester);
    expect(find.text('Filtros del catálogo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all customer tabs remain usable at 320 pixels wide', (
    tester,
  ) async {
    setNarrowViewport(tester);
    await tester.pumpWidget(app());
    for (final (label, content) in [
      ('Explorar', 'Explorar inmuebles'),
      ('Reservas', 'Prototipo de reservas'),
      ('Cuenta', 'Iniciar sesión'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text(content), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('catalog and filter controls meet accessibility guidelines', (
    tester,
  ) async {
    await tester.pumpWidget(app(publishedCatalog()));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('Filtrar catálogo'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await openFilters(tester);
      for (final label in [
        'Ciudad',
        'Zona',
        'Operación',
        'Precio mínimo',
        'Precio máximo',
        'Dormitorios mínimos',
        'Baños mínimos',
        'Aplicar filtros',
      ]) {
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(label))),
          findsOneWidget,
        );
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('opens a published listing and returns to the catalog', (
    tester,
  ) async {
    await tester.pumpWidget(app(publishedCatalog()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('catalog-listing-listing-1')));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del inmueble'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('property-detail-content')),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Explorar inmuebles'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('catalog-listing-listing-1')),
      findsOneWidget,
    );
  });

  testWidgets('detail is accessible and fits a 320 pixel viewport', (
    tester,
  ) async {
    setNarrowViewport(tester);
    await tester.pumpWidget(app(publishedCatalog()));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      final listing = find.descendant(
        of: find.byKey(const ValueKey('catalog-listing-listing-1')),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(listing).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getSemantics(listing)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tester.tap(listing);
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('filter sheet handles keyboard insets at larger text scale', (
    tester,
  ) async {
    setNarrowViewport(tester);
    final session = testSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
          useMaterial3: true,
        ),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: CustomerShell(
              sessionController: session,
              catalogApi: testCatalog(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'catalog at 320 px');
    await openFilters(tester);
    expect(tester.takeException(), isNull, reason: 'filter sheet at 320 px');
    await tester.tap(find.byKey(const ValueKey('filter-city')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-city')), 'Centro');
    await tester.ensureVisible(find.text('Aplicar filtros'));
    expect(find.text('Filtros del catálogo'), findsOneWidget);
    expect(find.text('Aplicar filtros'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
