import 'package:cliente_mobile/data/models/catalog_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
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

void main() {
  group('search', () {
    test('loads the first page of published listings', () async {
      final harness = _build();
      harness.backend.seed(id: 'older');
      harness.backend.seed(id: 'newer');

      await harness.controller.search();

      expect(harness.controller.loadState, CatalogLoadState.ready);
      expect(harness.controller.items.map((item) => item.listingId), [
        'newer',
        'older',
      ]);
      expect(harness.controller.hasMore, isFalse);
      expect(harness.controller.filters.isEmpty, isTrue);
    });

    test('applies the filters and keeps them for later pages', () async {
      final harness = _build();
      harness.backend.seed(id: 'sale-1');
      harness.backend.seed(id: 'rent-1', operation: 'rent');

      await harness.controller.search(
        const CatalogFilters(operation: ListingOperation.rent),
      );

      expect(harness.controller.items.single.listingId, 'rent-1');
      expect(harness.controller.filters.operation, ListingOperation.rent);
      expect(
        harness.backend.requests.single.url.queryParameters['operation'],
        'rent',
      );
    });

    test('reports an empty result as ready with no items', () async {
      final harness = _build();

      await harness.controller.search();

      expect(harness.controller.loadState, CatalogLoadState.ready);
      expect(harness.controller.items, isEmpty);
    });

    test('reports a network failure with a retryable state', () async {
      final harness = _build();
      harness.backend.offline = true;

      await harness.controller.search();

      expect(harness.controller.loadState, CatalogLoadState.failed);
      expect(harness.controller.message, contains('conexión'));
      expect(harness.controller.items, isEmpty);
    });

    test('explains a server error in Spanish', () async {
      final harness = _build();
      harness.backend.failWithStatus = 500;

      await harness.controller.search();

      expect(harness.controller.loadState, CatalogLoadState.failed);
      expect(
        harness.controller.message,
        'Ocurrió un error inesperado. '
        'Intentá de nuevo.',
      );
    });
  });

  group('load more', () {
    test('appends the next page with the same filters', () async {
      final harness = _build();
      for (var index = 0; index < 25; index++) {
        harness.backend.seed(id: 'listing-$index', operation: 'rent');
      }
      harness.backend.seed(id: 'sale-only');

      await harness.controller.search(
        const CatalogFilters(operation: ListingOperation.rent),
      );
      expect(harness.controller.items, hasLength(20));
      expect(harness.controller.hasMore, isTrue);

      await harness.controller.loadMore();

      expect(harness.controller.items, hasLength(25));
      expect(harness.controller.hasMore, isFalse);
      final second = harness.backend.requests.last.url.queryParameters;
      expect(second['cursor'], '20');
      expect(second['operation'], 'rent');
    });

    test('keeps the loaded items when the next page fails', () async {
      final harness = _build();
      for (var index = 0; index < 21; index++) {
        harness.backend.seed(id: 'listing-$index');
      }
      await harness.controller.search();
      harness.backend.offline = true;

      await harness.controller.loadMore();

      expect(harness.controller.loadState, CatalogLoadState.ready);
      expect(harness.controller.items, hasLength(20));
      expect(harness.controller.hasMore, isTrue);
      expect(harness.controller.loadMoreMessage, contains('conexión'));
    });
  });

  group('detail', () {
    test('loads one published listing', () async {
      final harness = _build();
      harness.backend.seed(id: 'listing-1', bedrooms: 4);

      final result = await harness.controller.loadDetail('listing-1');

      expect(result.detail!.bedrooms, 4);
      expect(result.message, isNull);
    });

    test('explains a listing that is no longer published', () async {
      final harness = _build();

      final result = await harness.controller.loadDetail('missing');

      expect(result.detail, isNull);
      expect(result.message, 'Este inmueble ya no está publicado.');
    });
  });
}
