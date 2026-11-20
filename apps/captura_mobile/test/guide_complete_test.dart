import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_reviews_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_reviews_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/guide/contextual_guide.dart';
import 'package:captura_mobile/ui/reviews/staff_reviews_screen.dart';
import 'package:captura_mobile/ui/spatial/spatial_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/in_memory_capture_draft_store.dart';

/// English UI words that must never reach the person reading the guide.
final _englishWords = RegExp(
  r'\b(click|button|login|log in|logout|sign in|upload|download|scan|tap|'
  r'swipe|settings|submit|next|back|save|cancel|loading|online|offline|'
  r'app|feedback|email|password|screen|room|draft|listing|wifi|wi-fi|'
  r'the|and|please|retry|undo|delete|open|close)\b',
  caseSensitive: false,
);

Iterable<String> _allText(GuideScreen screen) sync* {
  yield guideTitle(screen);
  yield guidePurpose(screen);
  for (final w in guideWalkthroughs(screen)) {
    yield w.title;
    yield* w.steps;
  }
  for (final m in guideMistakes(screen)) {
    yield m.problem;
    yield m.solution;
  }
  for (final t in guideGlossary(screen)) {
    yield t.term;
    yield t.definition;
  }
}

void main() {
  group('guide content', () {
    test('covers every screen of the agent app', () {
      expect(
        GuideScreen.values.map((s) => s.name),
        containsAll(<String>[
          'welcome',
          'access',
          'listingsList',
          'listingEditor',
          'spatialCapture',
          'roomEditor',
          'floorplanTrace',
          'chatInbox',
          'chatConversation',
          'notifications',
          'reviews',
        ]),
      );
    });

    test('every screen has purpose, walkthroughs of 3+ steps and mistakes', () {
      for (final screen in GuideScreen.values) {
        expect(guidePurpose(screen).trim(), isNotEmpty, reason: '$screen');
        final walkthroughs = guideWalkthroughs(screen);
        expect(walkthroughs, isNotEmpty, reason: '$screen');
        for (final w in walkthroughs) {
          expect(w.title.trim(), isNotEmpty);
          expect(w.steps.length, greaterThanOrEqualTo(3), reason: w.title);
        }
        expect(guideMistakes(screen), isNotEmpty, reason: '$screen');
        expect(guideGlossary(screen), isNotEmpty, reason: '$screen');
      }
    });

    test('the welcome guide defines every domain term', () {
      final terms = guideGlossary(GuideScreen.welcome).map((t) => t.term);
      for (final required in [
        'Inmueble',
        'Borrador',
        'Captura espacial',
        'Ambiente',
        'Escena 3D',
        'Subida pendiente',
        'Moneda',
        'Revisión',
      ]) {
        expect(terms, contains(required));
      }
    });

    test('all guide text is Spanish, without English interface words', () {
      for (final screen in GuideScreen.values) {
        for (final text in _allText(screen)) {
          expect(
            _englishWords.hasMatch(text),
            isFalse,
            reason: '$screen: $text',
          );
        }
      }
    });
  });

  group('guide sheet', () {
    testWidgets('shows every section of its screen and runs nothing', (
      tester,
    ) async {
      var actionRuns = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                ContextualGuideButton(screen: GuideScreen.spatialCapture),
              ],
            ),
            body: FilledButton(
              onPressed: () => actionRuns++,
              child: const Text('Acción'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('guide-button')));
      await tester.pumpAndSettle();
      // The guide opens as a chat; the structured guide is one tap away.
      await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Para qué sirve'), findsOneWidget);
      expect(find.text('Paso a paso'), findsOneWidget);
      expect(find.text('Errores comunes'), findsOneWidget);
      expect(find.text('Glosario'), findsOneWidget);
      expect(
        find.text(guidePurpose(GuideScreen.spatialCapture)),
        findsOneWidget,
      );
      expect(actionRuns, 0);
    });
  });

  group('integration without side effects', () {
    testWidgets('reviews screen opens its guide', (tester) async {
      final client = MockClient(
        (_) async => http.Response(
          '{"summary":{"average":null,"count":0,"verified_count":0,'
          '"few_ratings":true},"reviews":[]}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      late StaffReviewsController controller;
      await tester.runAsync(() async {
        final session = await _session();
        controller = StaffReviewsController(
          api: StaffReviewsApi(
            baseUrl: 'https://api.example.test',
            client: client,
          ),
          session: session,
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: StaffReviewsScreen(controller: controller)),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('guide-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
      expect(find.text(guideTitle(GuideScreen.reviews)), findsOneWidget);
    });

    testWidgets('capture screen guide does not start a capture', (
      tester,
    ) async {
      final backend = FakeSceneBackend();
      final ar = FakeArCapture();
      late SpatialCaptureController controller;
      await tester.runAsync(() async {
        controller = SpatialCaptureController(
          listingId: 'listing-1',
          session: await _session(),
          sceneApi: StaffSceneApi(
            baseUrl: 'https://api.example.test',
            client: backend.client,
          ),
          store: InMemoryCaptureDraftStore(),
          ar: ar,
        );
        await controller.load();
      });
      await tester.pumpWidget(
        MaterialApp(home: SpatialCaptureScreen(controller: controller)),
      );
      await tester.pump();
      final roomsBefore = controller.rooms.length;

      await tester.tap(find.byKey(const ValueKey('guide-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
      expect(find.text('Crear ambiente'), findsNothing);

      await tester.ensureVisible(find.text('Entendido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-sheet')), findsNothing);
      expect(controller.rooms.length, roomsBefore);
    });
  });
}

Future<StaffSessionController> _session() async {
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
  return session;
}
