import 'dart:convert';

import 'package:captura_mobile/data/models/staff_listing.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/domain/listing_drafts_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/listings/listing_format.dart';
import 'package:captura_mobile/ui/listings/listings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_listings_backend.dart';
import 'support/fake_staff_backend.dart';

Future<FakeListingsBackend> _pumpListings(
  WidgetTester tester, {
  void Function(FakeListingsBackend backend)? seed,
}) async {
  final session = StaffSessionController(
    api: StaffAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeStaffBackend().client,
    ),
    credentialStore: InMemoryStaffCredentialStore(),
  );
  await session.restore();
  await session.startLogin(email: 'agent@example.test', password: 'x');
  await session.submitCode('123456');
  final backend = FakeListingsBackend();
  seed?.call(backend);
  final controller = ListingDraftsController(
    api: StaffListingsApi(
      baseUrl: 'https://api.example.test',
      client: backend.client,
    ),
    session: session,
  );
  await tester.pumpWidget(
    MaterialApp(home: ListingsScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
  return backend;
}

/// Scrolls the visible list until [key] is built, then taps it. Lazily built
/// list children do not exist until they scroll into view.
Future<void> _tapVisible(WidgetTester tester, String key) async {
  // A focused text field keeps scrolling its caret back into view, which would
  // undo the scroll to the target; release focus as a user tapping away does.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      target,
      find.byType(ListView),
      const Offset(0, -200),
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _fillValidListing(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('listing-price-field')),
    '350000000,5',
  );
  await tester.enterText(
    find.byKey(const ValueKey('listing-city-field')),
    '  Medellín ',
  );
  await tester.enterText(
    find.byKey(const ValueKey('listing-zone-field')),
    'El Poblado',
  );
  await tester.enterText(
    find.byKey(const ValueKey('listing-bedrooms-field')),
    '3',
  );
  await tester.enterText(
    find.byKey(const ValueKey('listing-bathrooms-field')),
    '2',
  );
}

void main() {
  group('formatMoney', () {
    test('labels the amount with the currency of the listing', () {
      expect(
        formatMoney('350000000.00', ListingCurrency.bob),
        'BOB 350.000.000,00',
      );
      expect(formatMoney('1234.5', ListingCurrency.usd), 'USD 1.234,50');
      expect(
        formatMoney('9999999999999999.99', ListingCurrency.usdt),
        'USDT 9.999.999.999.999.999,99',
      );
    });
  });

  group('ListingsScreen', () {
    testWidgets('shows the agency drafts with their summary', (tester) async {
      await _pumpListings(tester, seed: (backend) => backend.seed(id: 'd-1'));

      expect(find.text('Mis inmuebles'), findsOneWidget);
      final item = find.byKey(const ValueKey('listing-item-d-1'));
      expect(item, findsOneWidget);
      expect(
        find.descendant(of: item, matching: find.textContaining('Medellín')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: item,
          matching: find.textContaining('BOB 350.000.000,00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the listing currency next to the price', (tester) async {
      await _pumpListings(
        tester,
        seed: (backend) => backend.seed(id: 'u-1', currency: 'USD'),
      );

      final item = find.byKey(const ValueKey('listing-item-u-1'));
      expect(item, findsOneWidget);
      expect(
        find.descendant(
          of: item,
          matching: find.textContaining('USD 350.000.000,00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('explains an empty tab and offers a new listing', (
      tester,
    ) async {
      await _pumpListings(tester);

      expect(find.byKey(const ValueKey('listings-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-listing-button')), findsOneWidget);
    });

    testWidgets('reports a failure and retries on demand', (tester) async {
      late FakeListingsBackend backend;
      backend = await _pumpListings(
        tester,
        seed: (fake) {
          fake
            ..seed(id: 'd-1')
            ..offline = true;
        },
      );

      expect(find.byKey(const ValueKey('listings-error')), findsOneWidget);
      backend.offline = false;
      await _tapVisible(tester, 'listings-retry');

      expect(find.byKey(const ValueKey('listing-item-d-1')), findsOneWidget);
    });

    testWidgets('shows the rejection reason of a rejected listing', (
      tester,
    ) async {
      await _pumpListings(
        tester,
        seed: (backend) => backend.seed(
          id: 'r-1',
          status: 'rejected',
          rejectionReason: 'Faltan datos de la zona',
        ),
      );

      await _tapVisible(tester, 'listings-tab-rejected');
      await _tapVisible(tester, 'listing-item-r-1');

      expect(
        find.byKey(const ValueKey('listing-rejection-reason')),
        findsOneWidget,
      );
      expect(find.textContaining('Faltan datos de la zona'), findsOneWidget);
    });
  });

  group('ListingEditorScreen', () {
    testWidgets('validates the fields like the API before saving', (
      tester,
    ) async {
      final backend = await _pumpListings(tester);
      await _tapVisible(tester, 'new-listing-button');

      await tester.enterText(
        find.byKey(const ValueKey('listing-price-field')),
        '0',
      );
      await _tapVisible(tester, 'listing-save-button');

      expect(find.text('Ingresá un precio mayor que cero.'), findsOneWidget);
      expect(find.text('Ingresá la ciudad.'), findsOneWidget);
      expect(find.text('Ingresá la zona.'), findsOneWidget);
      expect(find.text('Ingresá un número entero.'), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const ValueKey('listing-price-field')),
        '12.345',
      );
      await _tapVisible(tester, 'listing-save-button');
      expect(
        find.text('Usá hasta 16 dígitos enteros y 2 decimales.'),
        findsOneWidget,
      );
      expect(
        backend.requests.where((request) => request.method == 'POST'),
        isEmpty,
      );
    });

    testWidgets('saves a draft, then submits it after confirmation', (
      tester,
    ) async {
      final backend = await _pumpListings(tester);
      await _tapVisible(tester, 'new-listing-button');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('listing-submit-button')),
            )
            .onPressed,
        isNull,
      );

      await _fillValidListing(tester);
      await _tapVisible(tester, 'listing-save-button');

      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body), {
        'operation': 'sale',
        'base_price': '350000000.5',
        'currency': 'BOB',
        'city': 'Medellín',
        'zone': 'El Poblado',
        'bedrooms': 3,
        'bathrooms': 2,
        'description': null,
        'exact_address': null,
      });
      expect(find.text('Borrador guardado.'), findsOneWidget);
      // The snack bar sits over the bottom actions until it times out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Borrador guardado.'), findsNothing);

      await _tapVisible(tester, 'listing-submit-button');
      expect(find.text('Enviar a revisión'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('listing-submit-cancel')));
      await tester.pumpAndSettle();
      expect(backend.listings['listing-1']!['approval_status'], 'draft');

      await _tapVisible(tester, 'listing-submit-button');
      await tester.tap(find.byKey(const ValueKey('listing-submit-confirm')));
      await tester.pumpAndSettle();

      expect(backend.listings['listing-1']!['approval_status'], 'pending');
      expect(find.text('Mis inmuebles'), findsOneWidget);
      expect(find.text('Inmueble enviado a revisión.'), findsOneWidget);
    });

    testWidgets('requires saving pending edits before submitting', (
      tester,
    ) async {
      await _pumpListings(tester, seed: (backend) => backend.seed(id: 'd-1'));
      await _tapVisible(tester, 'listing-item-d-1');

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('listing-submit-button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('listing-zone-field')),
        'Laureles',
      );
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('listing-submit-button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Guardá los cambios'), findsOneWidget);
    });

    testWidgets('warns that editing a listing under review reopens it', (
      tester,
    ) async {
      final backend = await _pumpListings(
        tester,
        seed: (fake) => fake.seed(id: 'p-1', status: 'pending'),
      );
      await _tapVisible(tester, 'listings-tab-pending');
      await _tapVisible(tester, 'listing-item-p-1');

      expect(
        find.byKey(const ValueKey('listing-status-warning')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('listing-zone-field')),
        'Laureles',
      );
      await _tapVisible(tester, 'listing-save-button');

      expect(backend.listings['p-1']!['approval_status'], 'draft');
      expect(backend.listings['p-1']!['zone'], 'Laureles');
    });

    testWidgets(
      'defaults the currency to BOB and offers exactly three choices',
      (tester) async {
        final backend = await _pumpListings(tester);
        await _tapVisible(tester, 'new-listing-button');

        final field = find.byKey(const ValueKey('listing-currency-field'));
        expect(field, findsOneWidget);
        expect(find.text('Boliviano (BOB)'), findsOneWidget);

        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(find.text('Boliviano (BOB)'), findsNWidgets(2));
        expect(find.text('Dólar estadounidense (USD)'), findsOneWidget);
        expect(find.text('Tether (USDT)'), findsOneWidget);

        await tester.tap(find.text('Boliviano (BOB)').last);
        await tester.pumpAndSettle();
        await _fillValidListing(tester);
        await _tapVisible(tester, 'listing-save-button');

        final post = backend.requests.lastWhere((r) => r.method == 'POST');
        expect(jsonDecode(post.body)['currency'], 'BOB');
      },
    );

    testWidgets('sends the selected currency when creating a listing', (
      tester,
    ) async {
      final backend = await _pumpListings(tester);
      await _tapVisible(tester, 'new-listing-button');

      await tester.tap(find.byKey(const ValueKey('listing-currency-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dólar estadounidense (USD)').last);
      await tester.pumpAndSettle();
      expect(find.text('Precio base (USD)'), findsOneWidget);

      await _fillValidListing(tester);
      await _tapVisible(tester, 'listing-save-button');

      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body)['currency'], 'USD');
    });

    testWidgets('shows the currency read-only when editing and echoes it', (
      tester,
    ) async {
      final backend = await _pumpListings(
        tester,
        seed: (backend) => backend.seed(id: 'u-1', currency: 'USDT'),
      );
      await _tapVisible(tester, 'listing-item-u-1');

      final field = find.byKey(const ValueKey('listing-currency-field'));
      expect(
        tester
            .widget<DropdownButtonFormField<ListingCurrency>>(field)
            .onChanged,
        isNull,
      );
      expect(find.text('Tether (USDT)'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('listing-zone-field')),
        'Laureles',
      );
      await _tapVisible(tester, 'listing-save-button');

      final put = backend.requests.lastWhere((r) => r.method == 'PUT');
      expect(jsonDecode(put.body)['currency'], 'USDT');
    });

    testWidgets('meets touch target guidelines', (tester) async {
      await _pumpListings(tester, seed: (backend) => backend.seed(id: 'd-1'));
      final semantics = tester.ensureSemantics();
      try {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await _tapVisible(tester, 'listing-item-d-1');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    });
  });
}
