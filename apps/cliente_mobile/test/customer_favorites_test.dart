import 'dart:convert';

import 'package:cliente_mobile/data/models/catalog_models.dart';
import 'package:cliente_mobile/data/models/favorite_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/customer_favorites_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/domain/customer_favorites_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/catalog_screen.dart';
import 'package:cliente_mobile/ui/features/favorites/favorites_screen.dart';
import 'package:cliente_mobile/ui/features/favorites/saved_searches_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_catalog_backend.dart';

Map<String, Object?> _listingJson(String id) => {
  'listing_id': id,
  'offer_version': 1,
  'operation': 'sale',
  'base_price': {'amount': '100000.00', 'currency': 'BOB'},
  'city': 'Santa Cruz',
  'zone': 'Equipetrol',
  'cover_photo_url': null,
  'latitude': null,
  'longitude': null,
};

/// Stand-in for `/api/v1/customer/favorites` and `/saved-searches`, with the
/// server's rules: idempotent favorites, unique names and the limits.
class _FakeFavoritesBackend {
  final Map<String, Map<String, Object?>> favorites = {};
  final Set<String> unpublished = {};
  final List<Map<String, Object?>> searches = [];
  final List<String> requests = [];
  final List<Object?> createdBodies = [];
  bool offline = false;
  int? failNextWrite;
  String failDetail = 'conflict';
  int _ids = 0;

  CustomerFavoritesApi get api => CustomerFavoritesApi(
    baseUrl: 'https://api.example.test',
    accessTokenProvider: () async => 'token',
    client: MockClient(_handle),
  );

  http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: const {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (offline) throw http.ClientException('offline');
    if (request.headers['Authorization'] != 'Bearer token') {
      return http.Response('', 401);
    }
    if (request.method != 'GET' && failNextWrite != null) {
      final status = failNextWrite!;
      failNextWrite = null;
      return _json({'detail': failDetail, 'code': 'conflict'}, status);
    }
    const favoritesRoot = '/api/v1/customer/favorites';
    const searchesRoot = '/api/v1/customer/saved-searches';
    final path = request.url.path;
    if (path == favoritesRoot && request.method == 'GET') {
      return _json({
        'items': [
          for (final entry in favorites.entries)
            {
              'listing_id': entry.key,
              'favorited_at': '2026-11-01T10:00:00Z',
              'available': !unpublished.contains(entry.key),
              'listing': unpublished.contains(entry.key) ? null : entry.value,
            },
        ],
      }, 200);
    }
    if (path.startsWith('$favoritesRoot/')) {
      final id = path.substring(favoritesRoot.length + 1);
      if (request.method == 'PUT') {
        favorites[id] = _listingJson(id);
      } else {
        favorites.remove(id);
      }
      return http.Response('', 204);
    }
    if (path == searchesRoot && request.method == 'GET') {
      return _json({'items': searches}, 200);
    }
    if (path == searchesRoot && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      createdBodies.add(body);
      final filters = body['filters']! as Map<String, Object?>;
      final saved = {
        'id': 'search-${++_ids}',
        'name': body['name'],
        'filters': {
          for (final key in const [
            'city',
            'zone',
            'operation',
            'min_base_price',
            'max_base_price',
            'min_rooms',
            'min_bathrooms',
          ])
            key: filters[key],
        },
        'created_at': '2026-11-01T10:00:00Z',
      };
      searches.insert(0, saved);
      return _json(saved, 201);
    }
    if (path.startsWith('$searchesRoot/') && request.method == 'DELETE') {
      final id = path.substring(searchesRoot.length + 1);
      final before = searches.length;
      searches.removeWhere((search) => search['id'] == id);
      return http.Response('', before == searches.length ? 404 : 204);
    }
    return http.Response('', 404);
  }
}

CustomerFavoritesController _controller(_FakeFavoritesBackend backend) {
  final controller = CustomerFavoritesController(api: backend.api);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('favorite models', () {
    test('parses an available and an unavailable favorite', () {
      final available = FavoriteEntry.fromJson({
        'listing_id': 'l1',
        'favorited_at': '2026-11-01T10:00:00Z',
        'available': true,
        'listing': _listingJson('l1'),
      });
      final gone = FavoriteEntry.fromJson({
        'listing_id': 'l2',
        'favorited_at': '2026-11-01T10:00:00Z',
        'available': false,
        'listing': null,
      });
      expect(available.listing!.city, 'Santa Cruz');
      expect(gone.listing, isNull);
    });

    test('rejects inconsistent or malformed data', () {
      expect(
        () => FavoriteEntry.fromJson({
          'listing_id': 'l1',
          'favorited_at': '2026-11-01T10:00:00Z',
          'available': true,
          'listing': null,
        }),
        throwsFormatException,
      );
      expect(
        () => SavedSearch.fromJson({
          'id': 's1',
          'name': 'Casas',
          'filters': {'min_rooms': '2'},
          'created_at': '2026-11-01T10:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('saved filters never include the zone point', () {
      const filters = CatalogFilters(
        city: 'Santa Cruz',
        operation: ListingOperation.rent,
        minBasePrice: '100',
        minBedrooms: 2,
        latitude: -17.78,
        longitude: -63.18,
      );
      expect(savedFiltersToJson(filters), {
        'city': 'Santa Cruz',
        'operation': 'rent',
        'min_base_price': '100',
        'min_rooms': 2,
      });
      expect(hasSavableFilters(const CatalogFilters()), isFalse);
      expect(
        hasSavableFilters(
          const CatalogFilters(latitude: -17.78, longitude: -63.18),
        ),
        isFalse,
      );
    });
  });

  group('CustomerFavoritesController', () {
    test('load reads favorites and searches; clear forgets them', () async {
      final backend = _FakeFavoritesBackend()
        ..favorites['l1'] = _listingJson('l1')
        ..searches.add({
          'id': 's1',
          'name': 'Casas',
          'filters': {'city': 'Santa Cruz'},
          'created_at': '2026-11-01T10:00:00Z',
        });
      final controller = _controller(backend);

      await controller.load();
      expect(controller.state, FavoritesLoadState.ready);
      expect(controller.isFavorite('l1'), isTrue);
      expect(controller.savedSearches.single.filters.city, 'Santa Cruz');

      controller.clear();
      expect(controller.state, FavoritesLoadState.idle);
      expect(controller.isFavorite('l1'), isFalse);
      expect(controller.savedSearches, isEmpty);
    });

    test('a failed load says why', () async {
      final backend = _FakeFavoritesBackend()..offline = true;
      final controller = _controller(backend);

      await controller.load();

      expect(controller.state, FavoritesLoadState.failed);
      expect(controller.message, contains('conexión'));
    });

    test('toggle marks and unmarks a favorite', () async {
      final backend = _FakeFavoritesBackend();
      final controller = _controller(backend);
      await controller.load();

      expect(await controller.toggle('l1'), isNull);
      expect(controller.isFavorite('l1'), isTrue);
      expect(backend.favorites.keys, ['l1']);

      expect(await controller.toggle('l1'), isNull);
      expect(controller.isFavorite('l1'), isFalse);
      expect(backend.favorites, isEmpty);
    });

    test('a refused toggle rolls back and explains the limit', () async {
      final backend = _FakeFavoritesBackend()
        ..failNextWrite = 409
        ..failDetail = 'favorite_limit';
      final controller = _controller(backend);
      await controller.load();

      final failure = await controller.toggle('l1');

      expect(failure, contains('máximo de favoritos'));
      expect(controller.isFavorite('l1'), isFalse);
    });

    test('saving a search with a taken name explains it', () async {
      final backend = _FakeFavoritesBackend()
        ..failNextWrite = 409
        ..failDetail = 'saved_search_name_taken';
      final controller = _controller(backend);
      await controller.load();

      final failure = await controller.saveSearch(
        'Casas',
        const CatalogFilters(city: 'Santa Cruz'),
      );

      expect(failure, 'Ya tenés una búsqueda guardada con ese nombre.');
      expect(controller.savedSearches, isEmpty);
    });

    test('saves and deletes a search', () async {
      final backend = _FakeFavoritesBackend();
      final controller = _controller(backend);
      await controller.load();

      expect(
        await controller.saveSearch(
          '  Casas  ',
          const CatalogFilters(city: 'Santa Cruz', minBedrooms: 2),
        ),
        isNull,
      );
      expect(backend.createdBodies.single, {
        'name': 'Casas',
        'filters': {'city': 'Santa Cruz', 'min_rooms': 2},
      });
      final saved = controller.savedSearches.single;
      expect(saved.filters.minBedrooms, 2);

      expect(await controller.deleteSearch(saved), isNull);
      expect(controller.savedSearches, isEmpty);
      expect(backend.searches, isEmpty);
    });
  });

  group('favorites in the catalog', () {
    Future<
      ({
        CatalogController catalog,
        CustomerFavoritesController favorites,
        _FakeFavoritesBackend backend,
      })
    >
    pumpCatalog(WidgetTester tester, {required bool signedIn}) async {
      final catalogBackend = FakeCatalogBackend()
        ..seed(id: 'listing-1', city: 'Santa Cruz', zone: 'Equipetrol');
      final catalog = CatalogController(
        api: CatalogApi(
          baseUrl: 'https://api.example.test',
          client: catalogBackend.client,
        ),
      );
      addTearDown(catalog.dispose);
      final backend = _FakeFavoritesBackend();
      final favorites = _controller(backend);
      if (signedIn) await tester.runAsync(favorites.load);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogScreen(
              controller: catalog,
              favoritesController: favorites,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (catalog: catalog, favorites: favorites, backend: backend);
    }

    testWidgets('signed out, the catalog shows no favorites controls', (
      tester,
    ) async {
      await pumpCatalog(tester, signedIn: false);

      expect(find.byKey(const ValueKey('catalog-listing-listing-1')), findsOne);
      expect(
        find.byKey(const ValueKey('favorite-toggle-listing-1')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('catalog-save-search')), findsNothing);
      expect(
        find.byKey(const ValueKey('catalog-saved-searches')),
        findsNothing,
      );
    });

    testWidgets('signed in, the heart marks the listing as favorite', (
      tester,
    ) async {
      final built = await pumpCatalog(tester, signedIn: true);

      await tester.tap(find.byKey(const ValueKey('favorite-toggle-listing-1')));
      await tester.pumpAndSettle();

      expect(built.backend.favorites.keys, ['listing-1']);
      expect(built.favorites.isFavorite('listing-1'), isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('saving a search needs filters and applies it later', (
      tester,
    ) async {
      final built = await pumpCatalog(tester, signedIn: true);
      final save = find.byKey(const ValueKey('catalog-save-search'));
      expect(tester.widget<OutlinedButton>(save).onPressed, isNull);

      await tester.runAsync(
        () => built.catalog.search(const CatalogFilters(city: 'Santa Cruz')),
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('save-search-name')),
        'Santa Cruz',
      );
      await tester.tap(find.byKey(const ValueKey('save-search-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Búsqueda guardada.'), findsOneWidget);
      expect(built.backend.searches.single['name'], 'Santa Cruz');

      await tester.runAsync(() => built.catalog.search(const CatalogFilters()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalog-saved-searches')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Santa Cruz').last);
      await tester.pumpAndSettle();

      expect(built.catalog.filters.city, 'Santa Cruz');
    });
  });

  group('FavoritesScreen', () {
    testWidgets('lists available favorites and lets the customer remove one '
        'that is no longer published', (tester) async {
      final backend = _FakeFavoritesBackend()
        ..favorites['l1'] = _listingJson('l1')
        ..favorites['l2'] = _listingJson('l2')
        ..unpublished.add('l2');
      final controller = _controller(backend);
      await tester.runAsync(controller.load);
      final opened = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: FavoritesScreen(
            controller: controller,
            onOpenListing: opened.add,
          ),
        ),
      );

      expect(find.text('Santa Cruz, Equipetrol'), findsOneWidget);
      expect(find.text('Este inmueble ya no está publicado.'), findsOneWidget);

      await tester.tap(find.text('Santa Cruz, Equipetrol'));
      expect(opened, ['l1']);

      await tester.tap(find.byKey(const ValueKey('favorite-remove-l2')));
      await tester.pumpAndSettle();
      expect(backend.favorites.keys, ['l1']);
      expect(find.text('Este inmueble ya no está publicado.'), findsNothing);
    });

    testWidgets('an empty list explains how to add favorites', (tester) async {
      final controller = _controller(_FakeFavoritesBackend());
      await tester.runAsync(controller.load);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoritesScreen(controller: controller, onOpenListing: (_) {}),
        ),
      );

      expect(find.byKey(const ValueKey('favorites-empty')), findsOneWidget);
    });
  });
}
