import 'package:cliente_mobile/data/models/catalog_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/device_location.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/catalog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_catalog_backend.dart';
import 'support/fake_tile_provider.dart';

class _FakeDeviceLocation implements DeviceLocation {
  _FakeDeviceLocation(this.result);

  DeviceLocationResult result;
  int reads = 0;

  @override
  Future<DeviceLocationResult> current() async {
    reads++;
    return result;
  }
}

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

Future<void> _pump(
  WidgetTester tester,
  CatalogController controller,
  _FakeDeviceLocation location,
  FakeTileProvider tiles,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CatalogScreen(
          controller: controller,
          deviceLocation: location,
          mapConfig: tiles.config,
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

Future<void> _openFilters(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('catalog-filter-button')));

void main() {
  group('filters model', () {
    test('sends no zone parameters without a point', () {
      const filters = CatalogFilters(radiusKm: 20);

      expect(filters.hasZone, isFalse);
      expect(filters.toQuery(), isEmpty);
      expect(filters.isEmpty, isTrue);
    });

    test('sends the point and the default 5 km radius', () {
      const filters = CatalogFilters(latitude: -17.78, longitude: -63.18);

      expect(filters.toQuery(), {
        'latitude': '-17.78',
        'longitude': '-63.18',
        'radius_km': '5',
      });
      expect(filters.isEmpty, isFalse);
    });

    test('keeps other filters when the zone is replaced or removed', () {
      const filters = CatalogFilters(city: 'Santa Cruz', minBedrooms: 2);

      final zoned = filters.withZone(latitude: 1, longitude: 2, radiusKm: 12.5);
      expect(zoned.toQuery()['city'], 'Santa Cruz');
      expect(zoned.toQuery()['min_rooms'], '2');
      expect(zoned.toQuery()['radius_km'], '12.5');
      expect(zoned.withZone().toQuery(), {
        'city': 'Santa Cruz',
        'min_rooms': '2',
      });
    });

    test('documents the radius bounds the API accepts', () {
      expect(CatalogFilters.minRadiusKm, 1);
      expect(CatalogFilters.maxRadiusKm, 50);
      expect(CatalogFilters.defaultRadiusKm, 5);
    });
  });

  group('listing coordinates', () {
    Map<String, Object?> json({Object? latitude, Object? longitude}) => {
      'listing_id': 'listing-1',
      'offer_version': 1,
      'operation': 'sale',
      'base_price': {'amount': '100.00', 'currency': 'BOB'},
      'city': 'Santa Cruz',
      'zone': 'Equipetrol',
      'cover_photo_url': null,
      'latitude': latitude,
      'longitude': longitude,
    };

    test('reads the public point', () {
      final listing = CatalogListing.fromJson(
        json(latitude: -17.78, longitude: -63),
      );

      expect(listing.latitude, -17.78);
      expect(listing.longitude, -63.0);
    });

    test('accepts a listing without a point', () {
      final listing = CatalogListing.fromJson(json());

      expect(listing.latitude, isNull);
      expect(listing.longitude, isNull);
    });

    test('rejects a point that is not a number', () {
      expect(
        () => CatalogListing.fromJson(json(latitude: 'x', longitude: 1)),
        throwsFormatException,
      );
    });
  });

  group('zone search screen', () {
    testWidgets('uses my location, applies the radius and shows the zone', (
      tester,
    ) async {
      final harness = _build();
      final location = _FakeDeviceLocation(
        const DeviceLocationResult.found(-17.78, -63.18),
      );

      await _pump(tester, harness.controller, location, FakeTileProvider());
      await _openFilters(tester);
      await _tap(tester, find.byKey(const ValueKey('zone-use-location')));

      expect(location.reads, 1);
      expect(find.text('Radio: 5 km'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('zone-radius')),
      );
      expect(slider.min, 1);
      expect(slider.max, 50);
      slider.onChanged!(10);
      await tester.pumpAndSettle();
      expect(find.text('Radio: 10 km'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('filter-apply')));

      final query = harness.backend.requests.last.url.queryParameters;
      expect(query['latitude'], '-17.78');
      expect(query['longitude'], '-63.18');
      expect(query['radius_km'], '10');
      expect(find.byKey(const ValueKey('catalog-zone-chip')), findsOneWidget);
      expect(
        find.text(
          'No hay inmuebles publicados dentro de ese radio. Probá ampliarlo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a denied permission explains and offers the map', (
      tester,
    ) async {
      final harness = _build();
      final location = _FakeDeviceLocation(
        const DeviceLocationResult.failed(DeviceLocationFailure.denied),
      );

      await _pump(tester, harness.controller, location, FakeTileProvider());
      await _openFilters(tester);
      await _tap(tester, find.byKey(const ValueKey('zone-use-location')));

      expect(
        find.byKey(const ValueKey('zone-location-message')),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('filter-apply')));
      expect(
        harness.backend.requests.last.url.queryParameters.containsKey(
          'latitude',
        ),
        isFalse,
      );
    });

    testWidgets('picks the centre on the map and sends it', (tester) async {
      final harness = _build();
      final location = _FakeDeviceLocation(
        const DeviceLocationResult.failed(DeviceLocationFailure.unavailable),
      );

      await _pump(tester, harness.controller, location, FakeTileProvider());
      await _openFilters(tester);
      await _tap(tester, find.byKey(const ValueKey('zone-toggle-map')));
      expect(find.byKey(const ValueKey('zone-attribution')), findsOneWidget);
      expect(location.reads, 0);

      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('zone-marker')), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('filter-apply')));
      final query = harness.backend.requests.last.url.queryParameters;
      expect(double.parse(query['latitude']!), closeTo(-17.78, 0.5));
      expect(query['radius_km'], '5');
    });

    testWidgets('shows a retry when the map tiles fail', (tester) async {
      final harness = _build();
      final tiles = FakeTileProvider(failing: true);

      await _pump(
        tester,
        harness.controller,
        _FakeDeviceLocation(
          const DeviceLocationResult.failed(DeviceLocationFailure.denied),
        ),
        tiles,
      );
      await _openFilters(tester);
      await _tap(tester, find.byKey(const ValueKey('zone-toggle-map')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('zone-map-error')), findsOneWidget);
      tiles.failing = false;
      await _tap(tester, find.byKey(const ValueKey('zone-map-retry')));
      expect(find.byKey(const ValueKey('zone-map-error')), findsNothing);
    });

    testWidgets('clearing filters removes the zone', (tester) async {
      final harness = _build();
      final location = _FakeDeviceLocation(
        const DeviceLocationResult.found(-17.78, -63.18),
      );

      await _pump(tester, harness.controller, location, FakeTileProvider());
      await _openFilters(tester);
      await _tap(tester, find.byKey(const ValueKey('zone-use-location')));
      await _tap(tester, find.byKey(const ValueKey('filter-apply')));
      expect(harness.controller.filters.hasZone, isTrue);

      await _tap(tester, find.byKey(const ValueKey('catalog-clear-filters')));

      expect(harness.controller.filters.hasZone, isFalse);
      expect(find.byKey(const ValueKey('catalog-zone-chip')), findsNothing);
      expect(
        harness.backend.requests.last.url.queryParameters.containsKey(
          'latitude',
        ),
        isFalse,
      );
    });

    testWidgets('a failed zone search keeps the retry state', (tester) async {
      final harness = _build();
      harness.backend.failWithStatus = 500;
      final location = _FakeDeviceLocation(
        const DeviceLocationResult.found(-17.78, -63.18),
      );

      await _pump(tester, harness.controller, location, FakeTileProvider());
      expect(find.byKey(const ValueKey('catalog-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('catalog-retry')), findsOneWidget);
    });
  });
}
