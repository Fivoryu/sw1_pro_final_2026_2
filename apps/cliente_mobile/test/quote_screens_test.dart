import 'dart:convert';

import 'package:cliente_mobile/data/models/catalog_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/quote_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/listing_detail_screen.dart';
import 'package:cliente_mobile/ui/features/viewer/views/object_hotspot_sheet.dart';
import 'package:cliente_mobile/ui/features/quote/views/listing_quote_screen.dart';
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

Map<String, Object?> _snapshot() => {
  'quote_id': 'quote-9',
  'listing_id': 'listing-1',
  'offer_version': 3,
  'operation': 'sale',
  'lines': [
    {
      'kind': 'base',
      'extra_id': null,
      'amount': '350000.00',
      'currency': 'BOB',
      'charge_period': 'one_time',
    },
    {
      'kind': 'extra',
      'extra_id': 'extra-1',
      'amount': '1500.00',
      'currency': 'BOB',
      'charge_period': 'one_time',
    },
  ],
  'one_time_total': {'amount': '351500.00', 'currency': 'BOB'},
  'monthly_total': {'amount': '0.00', 'currency': 'BOB'},
  'display_totals': {
    'one_time_total': {'amount': '50510.00', 'currency': 'USD'},
    'monthly_total': {'amount': '0.00', 'currency': 'USD'},
  },
  'created_at': '2026-10-16T12:00:00Z',
  'expires_at': '2026-10-16T12:15:00Z',
};

Future<CatalogListingDetail> _pumpDetail(
  WidgetTester tester, {
  required QuoteApi quoteApi,
}) async {
  final backend = FakeCatalogBackend()..seed(
    id: 'listing-1',
    extras: const [(id: 'extra-1', name: 'Piscina', amount: '1500.00')],
  );
  final api = CatalogApi(baseUrl: 'https://api.example.test', client: backend.client);
  final detail = await api.getListing('listing-1');
  await tester.pumpWidget(
    MaterialApp(
      home: ListingDetailScreen(
        controller: CatalogController(api: api),
        listingId: 'listing-1',
        quoteApi: quoteApi,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return detail;
}

void main() {
  group('ListingQuoteScreen', () {
    testWidgets('requests a snapshot and shows the server totals verbatim', (
      tester,
    ) async {
      final detail = await _pumpDetail(
        tester,
        quoteApi: QuoteApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            expect(body['selected_extra_ids'], ['extra-1']);
            expect(body['target_currency'], 'USD');
            return _json(_snapshot(), 201);
          }),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ListingQuoteScreen(
            quoteApi: QuoteApi(
              baseUrl: 'https://api.example.test',
              client: MockClient((_) async => _json(_snapshot(), 201)),
            ),
            detail: detail,
            preselectedExtraId: 'extra-1',
            initialCurrency: DisplayCurrency.usd,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quote-create')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quote-snapshot')), findsOneWidget);
      // Display totals come from the server, already converted to USD.
      expect(find.textContaining('USD 50.510,00'), findsOneWidget);
    });

    testWidgets('a version mismatch shows the honest message and retry', (
      tester,
    ) async {
      final detail = await _pumpDetail(
        tester,
        quoteApi: QuoteApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => http.Response('x', 500)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ListingQuoteScreen(
            quoteApi: QuoteApi(
              baseUrl: 'https://api.example.test',
              client: MockClient(
                (_) async => _json({'detail': 'x', 'code': 'offer_version_mismatch'}, 409),
              ),
            ),
            detail: detail,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quote-create')));
      await tester.pumpAndSettle();

      expect(
        find.text('El precio cambió mientras cotizabas. Volvé a intentarlo.'),
        findsOneWidget,
      );
      // The button is enabled again for a retry.
      expect(
        tester.widget<FilledButton>(find.byKey(const ValueKey('quote-create'))),
        (widget) => widget.onPressed != null,
      );
    });
  });

  group('object hotspot sheet', () {
    testWidgets('a tapped extra shows its name and published price', (tester) async {
      final detail = await _pumpDetail(
        tester,
        quoteApi: QuoteApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => http.Response('x', 500)),
        ),
      );
      final extra = detail.extras.first;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showObjectHotspotSheet(
                  context,
                  objectId: extra.extraId,
                  detail: detail,
                  quoteApi: QuoteApi(
                    baseUrl: 'https://api.example.test',
                    client: MockClient((_) async => _json(_snapshot(), 201)),
                  ),
                ),
                child: const Text('tap'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(find.text(extra.name), findsOneWidget);
      expect(find.textContaining(extra.price.currency), findsOneWidget);
      expect(find.byKey(const ValueKey('hotspot-quote')), findsOneWidget);
    });

    testWidgets('an unknown scene object says it has no published price', (tester) async {
      final detail = await _pumpDetail(
        tester,
        quoteApi: QuoteApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => http.Response('x', 500)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showObjectHotspotSheet(
                  context,
                  objectId: 'ref_cube_1',
                  detail: detail,
                  quoteApi: QuoteApi(
                    baseUrl: 'https://api.example.test',
                    client: MockClient((_) async => _json(_snapshot(), 201)),
                  ),
                ),
                child: const Text('tap'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(
        find.text('Este objeto es parte del recorrido; no tiene precio publicado.'),
        findsOneWidget,
      );
      // The commercial flow stays reachable: quote the whole listing.
      expect(find.byKey(const ValueKey('hotspot-quote')), findsOneWidget);
    });

    testWidgets('the hotspot button opens the quote screen without leaving the flow', (
      tester,
    ) async {
      final detail = await _pumpDetail(
        tester,
        quoteApi: QuoteApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => http.Response('x', 500)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showObjectHotspotSheet(
                  context,
                  objectId: detail.extras.first.extraId,
                  detail: detail,
                  quoteApi: QuoteApi(
                    baseUrl: 'https://api.example.test',
                    client: MockClient((_) async => _json(_snapshot(), 201)),
                  ),
                ),
                child: const Text('tap'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hotspot-quote')));
      await tester.pumpAndSettle();

      expect(find.text('Cotización'), findsOneWidget);
    });
  });
}
