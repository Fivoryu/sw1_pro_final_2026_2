import 'dart:async';
import 'dart:convert';

import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/scene_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/listing_detail_screen.dart';
import 'package:cliente_mobile/ui/features/viewer/views/listing_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_catalog_backend.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _sceneNotDefined() => _json({
  'detail': 'Scene is not defined for this listing',
  'code': 'scene_not_defined',
}, 404);

Map<String, Object?> _sceneDocument() => {
  'version': '2.0',
  'unit': 'meters',
  'walls': <Object?>[],
  'openings': <Object?>[],
  'rooms': <Object?>[],
  'objects': <Object?>[],
};

void main() {
  group('ListingViewerScreen honest states', () {
    testWidgets('a listing without a scene shows the honest fallback, never a fake walkthrough', (
      tester,
    ) async {
      final viewer = ListingViewerScreen(
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => _sceneNotDefined()),
        ),
        listingId: 'listing-1',
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('viewer-not-defined')), findsOneWidget);
      expect(find.text('Recorrido 3D no disponible.'), findsOneWidget);
    });

    testWidgets('a failed load shows the message and retrying reloads', (tester) async {
      var calls = 0;
      final viewer = ListingViewerScreen(
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async {
            calls += 1;
            return calls == 1 ? http.Response('boom', 500) : _sceneNotDefined();
          }),
        ),
        listingId: 'listing-1',
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('viewer-failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer-retry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('viewer-retry')));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byKey(const ValueKey('viewer-not-defined')), findsOneWidget);
    });

    testWidgets('while the scene is on flight it shows loading', (tester) async {
      final response = Completer<http.Response>();
      final viewer = ListingViewerScreen(
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) => response.future),
        ),
        listingId: 'listing-1',
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      await tester.pump();

      expect(find.byKey(const ValueKey('viewer-loading')), findsOneWidget);

      // Flush the pending response so the test ends without live timers.
      response.complete(_sceneNotDefined());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer-not-defined')), findsOneWidget);
    });
  });

  group('ListingViewerScreen page timeouts', () {
    ListingViewerScreen buildViewer({
      required Duration pageTimeout,
      required ViewerPageBuilder viewerBuilder,
    }) => ListingViewerScreen(
      sceneApi: SceneApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((_) async => _json(_sceneDocument(), 200)),
      ),
      listingId: 'listing-1',
      pageTimeout: pageTimeout,
      viewerBuilder: viewerBuilder,
    );

    testWidgets('a page that never boots ends in the honest error, never a blank wait', (
      tester,
    ) async {
      final viewer = buildViewer(
        pageTimeout: const Duration(milliseconds: 50),
        viewerBuilder: (context, report) =>
            const SizedBox(key: ValueKey('fake-viewer-page')),
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      // The scene arrives and the page mounts; the spinner keeps animating, so
      // this test pumps explicit frames instead of settling.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('fake-viewer-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsOneWidget);
      expect(find.text('El visor 3D no respondió.'), findsOneWidget);
    });

    testWidgets('a page that boots but never renders the scene ends in the honest error', (
      tester,
    ) async {
      var reported = false;
      final viewer = buildViewer(
        pageTimeout: const Duration(milliseconds: 50),
        viewerBuilder: (context, report) {
          if (!reported) {
            reported = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => report('{"type":"ready"}'),
            );
          }
          return const SizedBox(key: ValueKey('fake-viewer-page'));
        },
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      await tester.pump(); // the scene arrives and the page mounts
      await tester.pump(); // the page reports it booted

      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsOneWidget);
    });

    testWidgets('the scene is delivered exactly once, never on every rebuild', (
      tester,
    ) async {
      final delivered = <String>[];
      var reported = false;
      final viewer = ListingViewerScreen(
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => _json(_sceneDocument(), 200)),
        ),
        listingId: 'listing-1',
        pageTimeout: const Duration(milliseconds: 50),
        scriptRunner: delivered.add,
        viewerBuilder: (context, report) {
          if (!reported) {
            reported = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => report('{"type":"ready"}'),
            );
          }
          return const SizedBox(key: ValueKey('fake-viewer-page'));
        },
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      await tester.pump();
      await tester.pump();
      // Several rebuilds later the camera must not be reset again.
      await tester.pump();
      await tester.pump();

      expect(
        delivered,
        hasLength(1),
        reason: 're-sending loadScene resets the walkthrough camera to its spawn',
      );
      expect(delivered.single, contains('window.viewerHost.loadScene('));
    });

    testWidgets('retrying after a silent page clears the error and re-arms the timeout', (
      tester,
    ) async {
      final viewer = buildViewer(
        pageTimeout: const Duration(milliseconds: 50),
        viewerBuilder: (context, report) =>
            const SizedBox(key: ValueKey('fake-viewer-page')),
      );

      await tester.pumpWidget(MaterialApp(home: viewer));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('viewer-runtime-retry')));
      await tester.pump();

      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsNothing);

      // The new attempt still has to prove itself: silence fails again.
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('viewer-runtime-error')), findsOneWidget);
    });
  });

  group('ListingDetailScreen scene probe', () {
    testWidgets('a listing with a scene offers the walkthrough', (tester) async {
      final backend = FakeCatalogBackend()..seed(id: 'listing-1');
      final controller = CatalogController(
        api: CatalogApi(baseUrl: 'https://api.example.test', client: backend.client),
      );
      final detail = ListingDetailScreen(
        controller: controller,
        listingId: 'listing-1',
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => _json(_sceneDocument(), 200)),
        ),
      );

      await tester.pumpWidget(MaterialApp(home: detail));
      await tester.pumpAndSettle();

      // The walkthrough section sits below the fold of the test surface.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-open-viewer')),
        200,
      );

      expect(find.byKey(const ValueKey('detail-open-viewer')), findsOneWidget);
    });

    testWidgets('a listing without a scene keeps the honest catalog wording', (tester) async {
      final backend = FakeCatalogBackend()..seed(id: 'listing-1');
      final controller = CatalogController(
        api: CatalogApi(baseUrl: 'https://api.example.test', client: backend.client),
      );
      final detail = ListingDetailScreen(
        controller: controller,
        listingId: 'listing-1',
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => _sceneNotDefined()),
        ),
      );

      await tester.pumpWidget(MaterialApp(home: detail));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Recorrido 3D'), 200);

      expect(find.text('Recorrido 3D no disponible.'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-open-viewer')), findsNothing);
    });

    testWidgets('an unavailable scene probe never promises a walkthrough', (tester) async {
      final backend = FakeCatalogBackend()..seed(id: 'listing-1');
      final controller = CatalogController(
        api: CatalogApi(baseUrl: 'https://api.example.test', client: backend.client),
      );
      final detail = ListingDetailScreen(
        controller: controller,
        listingId: 'listing-1',
        sceneApi: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => http.Response('boom', 500)),
        ),
      );

      await tester.pumpWidget(MaterialApp(home: detail));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Recorrido 3D'), 200);

      expect(find.text('Recorrido 3D no disponible.'), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-open-viewer')), findsNothing);
    });
  });
}
