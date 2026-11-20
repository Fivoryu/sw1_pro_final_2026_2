import 'dart:convert';

import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/data/services/customer_booking_api.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:cliente_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_catalog_backend.dart';
import 'support/fake_customer_backend.dart';

const _help = ValueKey('guide-help-button');
const _question = '¿Cómo reservo este inmueble?';

Future<List<String>> _openApp(WidgetTester tester) async {
  final writes = <String>[];
  final auth = FakeCustomerBackend();
  final session = CustomerSessionController(
    api: CustomerAuthApi(baseUrl: 'https://local.test', client: auth.client),
    tokenStore: InMemoryCustomerTokenStore(auth.refreshToken),
  );
  final catalog = FakeCatalogBackend()..seed(id: 'listing-1');
  await tester.pumpWidget(
    RoomForgeApp(
      sessionController: session,
      catalogApi: CatalogApi(
        baseUrl: 'https://local.test',
        client: catalog.client,
      ),
      bookingApi: CustomerBookingApi(
        baseUrl: 'https://local.test',
        accessTokenProvider: session.obtainAccessToken,
        client: MockClient((req) async {
          if (req.method == 'GET') return http.Response('[]', 200);
          writes.add('${req.method} ${req.url.path}');
          if (req.url.path != '/api/v1/quotes') return http.Response('', 400);
          const total = {'amount': '100.00', 'currency': 'USD'};
          return http.Response(
            jsonEncode({
              'quote_id': 'guide-quote',
              'listing_id': 'listing-1',
              'offer_version': 1,
              'operation': 'sale',
              'lines': [
                {'kind': 'base', ...total, 'charge_period': 'one_time'},
              ],
              'one_time_total': total,
              'monthly_total': {'amount': '0.00', 'currency': 'USD'},
              'created_at': '2026-10-01T00:00:00Z',
              'expires_at': '2099-01-01T00:00:00Z',
            }),
            201,
          );
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return writes;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('guide-chat-input')), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pumpAndSettle();
}

Future<void> _dismiss(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'guided detail stops at the real method chooser, with no reservation or payment',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final writes = await _openApp(tester);
      await _tap(
        tester,
        find.byKey(const ValueKey('catalog-listing-listing-1')),
      );
      await _tap(tester, find.byKey(_help));
      await _ask(tester, _question);
      expect(find.textContaining('Calcular cotización'), findsWidgets);
      expect(find.text('Llevame'), findsNothing);
      expect(writes, isEmpty);
      await _dismiss(tester);
      await _tap(tester, find.text('Calcular cotización'));
      await _tap(tester, find.byKey(_help));
      await _ask(tester, _question);
      expect(
        find.textContaining('Ya tenés una cotización vigente'),
        findsOneWidget,
      );
      await _dismiss(tester);
      await _tap(tester, find.text('Elegir cómo reservar'));
      expect(find.text('Elegí cómo reservar'), findsOneWidget);
      expect(find.text('Tarjeta de prueba'), findsOneWidget);
      expect(find.text('Wallet de prueba'), findsOneWidget);
      expect(writes, [
        'POST /api/v1/quotes',
      ]); // Only the user's explicit quote.
    },
  );
}
