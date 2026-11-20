import 'package:captura_mobile/ui/guide/contextual_guide.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/domain/listing_drafts_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/listings/listings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_listings_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/fake_staff_backend.dart';

void main() {
  group('ContextualGuideButton', () {
    testWidgets('opens a sheet with the steps of its screen and runs nothing', (
      tester,
    ) async {
      var actionRuns = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                ContextualGuideButton(screen: GuideScreen.listingsList),
              ],
            ),
            body: FilledButton(
              key: const ValueKey('screen-action'),
              onPressed: () => actionRuns++,
              child: const Text('Acción'),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('guide-sheet')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('guide-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
      // The guide opens as a chat; the structured guide is one tap away.
      await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
      await tester.pumpAndSettle();
      final steps = guideSteps(GuideScreen.listingsList);
      expect(steps, isNotEmpty);
      for (var i = 0; i < steps.length; i++) {
        expect(find.byKey(ValueKey('guide-step-$i')), findsOneWidget);
        expect(find.text(steps[i]), findsOneWidget);
      }
      expect(actionRuns, 0);
    });

    test('every screen has deterministic, distinct steps', () {
      for (final screen in GuideScreen.values) {
        expect(guideSteps(screen), isNotEmpty);
        expect(guideSteps(screen), guideSteps(screen));
      }
      expect(
        guideSteps(GuideScreen.listingsList),
        isNot(guideSteps(GuideScreen.listingEditor)),
      );
    });
  });

  group('drafts screens integration', () {
    Future<void> pumpListings(WidgetTester tester) async {
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
      final controller = ListingDraftsController(
        api: StaffListingsApi(
          baseUrl: 'https://api.example.test',
          client: backend.client,
        ),
        session: session,
        photosApi: StaffListingPhotosApi(
          baseUrl: 'https://api.example.test',
          client: backend.client,
        ),
        photoSource: FakePhotoSource(),
      );
      await tester.pumpWidget(
        MaterialApp(home: ListingsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the guide opens without opening the editor', (tester) async {
      await pumpListings(tester);

      await tester.tap(find.byKey(const ValueKey('guide-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
      expect(find.text('Cómo preparar un borrador'), findsOneWidget);
      // Guidance only indicates: the editor screen was not pushed.
      expect(find.byKey(const ValueKey('listing-price-field')), findsNothing);
    });

    testWidgets('the new-listing action still opens the editor', (
      tester,
    ) async {
      await pumpListings(tester);

      await tester.tap(find.byKey(const ValueKey('new-listing-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('listing-price-field')), findsOneWidget);
    });
  });
}
