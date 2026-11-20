import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/catalog_screen.dart';
import 'package:cliente_mobile/ui/features/catalog/views/listing_detail_screen.dart';
import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_catalog_backend.dart';

CatalogController _controller(FakeCatalogBackend backend) => CatalogController(
  api: CatalogApi(baseUrl: 'https://api.example.test', client: backend.client),
);

void main() {
  testWidgets('catalog guide opens, lists steps and runs no screen action', (
    tester,
  ) async {
    final backend = FakeCatalogBackend()..seed(id: 'listing-1');
    final controller = _controller(backend);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CatalogScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final requestsBefore = backend.requests.length;

    await tester.tap(find.byKey(const ValueKey('guide-help-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
    // The sheet opens as a chat; the full guide is behind the toggle.
    await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
    await tester.pumpAndSettle();
    for (final step in GuideContent.forScreen(GuideScreen.catalog).steps) {
      expect(find.text(step), findsOneWidget);
    }
    // Only indicates: no filters sheet, no detail screen, no new requests.
    expect(find.byType(ListingDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('catalog-clear-filters')), findsNothing);
    expect(backend.requests.length, requestsBefore);
  });

  testWidgets('detail guide shows its own steps', (tester) async {
    final backend = FakeCatalogBackend()..seed(id: 'listing-1');
    await tester.pumpWidget(
      MaterialApp(
        home: ListingDetailScreen(
          controller: _controller(backend),
          listingId: 'listing-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guide-help-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
    await tester.pumpAndSettle();
    for (final step in GuideContent.forScreen(
      GuideScreen.listingDetail,
    ).steps) {
      expect(find.text(step), findsOneWidget);
    }
  });

  testWidgets('catalog still lists listings and opens the filters sheet', (
    tester,
  ) async {
    final backend = FakeCatalogBackend()..seed(id: 'listing-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CatalogScreen(controller: _controller(backend))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-filter-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-sheet')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('catalog-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Filtros del catálogo'), findsOneWidget);
  });
}
