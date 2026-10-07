import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/main.dart';

import 'support/fake_listings_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/fake_staff_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StaffListingsApi fakeListingsApi() => StaffListingsApi(
  baseUrl: 'https://api.example.test',
  client: FakeListingsBackend().client,
);

StaffListingPhotosApi fakePhotosApi() => StaffListingPhotosApi(
  baseUrl: 'https://api.example.test',
  client: FakeListingsBackend().client,
);

/// Builds a controller backed by the fake staff API. When [signedIn] is true the
/// session is opened first.
Future<StaffSessionController> captureController({
  bool signedIn = false,
}) async {
  final controller = StaffSessionController(
    api: StaffAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeStaffBackend().client,
    ),
    credentialStore: InMemoryStaffCredentialStore(),
  );
  await controller.restore();
  if (signedIn) {
    await controller.startLogin(
      email: 'agent@example.test',
      password: 'password123',
    );
    await controller.submitCode('123456');
  }
  return controller;
}

Future<StaffSessionController> pumpCaptureApp(
  WidgetTester tester, {
  bool signedIn = false,
}) async {
  final controller = await captureController(signedIn: signedIn);
  await tester.pumpWidget(
    CaptureApp(
      controller: controller,
      listingsApi: fakeListingsApi(),
      photosApi: fakePhotosApi(),
      photoSource: FakePhotoSource(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('starts on the access step and states what is available', (
    tester,
  ) async {
    await pumpCaptureApp(tester, signedIn: false);

    expect(find.text('Acceso del agente'), findsOneWidget);
    expect(find.byKey(const ValueKey('access-email-field')), findsOneWidget);
    expect(
      find.textContaining('La captura con cámara todavía no está disponible'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('access-continue-button')), findsNothing);
  });

  testWidgets('access step requires credentials and the second factor', (
    tester,
  ) async {
    await pumpCaptureApp(tester, signedIn: false);

    expect(find.text('Acceso del agente'), findsOneWidget);
    expect(find.byKey(const ValueKey('access-continue-button')), findsNothing);
    expect(find.byKey(const ValueKey('access-email-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('access-password-field')), findsOneWidget);
  });

  testWidgets('continues from access to the agent listings', (tester) async {
    await pumpCaptureApp(tester, signedIn: true);

    await tester.tap(find.byKey(const ValueKey('access-continue-button')));
    await tester.pumpAndSettle();

    expect(find.text('Mis inmuebles'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-listing-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('listings-empty')), findsOneWidget);
  });

  /// Opens the first future-phase prototype step directly; it is no longer part
  /// of the agent's real flow (F04 ends at submitting the listing for review).
  Future<void> openRoomsPhotosPrototype(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoomsPhotosScreen()));
    await tester.pumpAndSettle();
  }

  /// Scrolls a prototype step to its end so its final action is fully visible.
  Future<void> tapScreenEndAction(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    // Lazily built steps grow with the text scale, so scroll until the action
    // exists instead of by a fixed distance.
    await tester.dragUntilVisible(
      target,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('navigates between two local prototype steps and back', (
    tester,
  ) async {
    await openRoomsPhotosPrototype(tester);
    expect(find.byKey(const ValueKey('rooms-photos-screen')), findsOneWidget);
    expect(find.text('Ambientes y fotos'), findsOneWidget);
    expect(find.textContaining('No se guardan'), findsOneWidget);

    await tapScreenEndAction(tester, 'rooms-photos-continue');
    expect(
      find.byKey(const ValueKey('geometry-objects-screen')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('geometry-objects-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rooms-photos-screen')), findsOneWidget);
  });

  testWidgets('flow remains scroll-safe at a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openRoomsPhotosPrototype(tester);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('rooms-photos-continue')))
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(const ValueKey('rooms-photos-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Corregir geometría y objetos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes simulated permission, offline, error and retry states', (
    tester,
  ) async {
    await openRoomsPhotosPrototype(tester);

    expect(find.text('Permiso de fotos: requerido (simulado)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simulate-photo-denied')));
    await tester.pumpAndSettle();
    expect(find.text('Permiso de fotos: rechazado (simulado)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simulate-photo-granted')));
    await tester.pumpAndSettle();
    expect(find.text('Permiso de fotos: concedido (simulado)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('simulate-offline')));
    await tester.pumpAndSettle();
    expect(find.text('Estado sin conexión (simulado)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simulate-offline')));
    await tester.pumpAndSettle();
    expect(
      find.text('Estado conectado (simulado, sin red real)'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('simulate-error')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('simulated-error-state')), findsOneWidget);
    expect(find.byKey(const ValueKey('simulated-retry')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('simulated-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('simulated-error-state')), findsNothing);
    expect(find.text('Reintento completado (simulado)'), findsOneWidget);
  });

  testWidgets('simulates a photo capture without using a device camera', (
    tester,
  ) async {
    await openRoomsPhotosPrototype(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('simulate-camera-capture')),
    );
    await tester.tap(find.byKey(const ValueKey('simulate-camera-capture')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(
      find.text('Captura de foto simulada (sin cámara real)'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('simulated-photo-placeholder')),
      findsOneWidget,
    );
  });

  Future<void> openGeometryPrototype(WidgetTester tester) async {
    await openRoomsPhotosPrototype(tester);
    await tapScreenEndAction(tester, 'rooms-photos-continue');
  }

  testWidgets('geometry step marks every shape as illustrative, not measured', (
    tester,
  ) async {
    await openGeometryPrototype(tester);

    expect(
      find.byKey(const ValueKey('geometry-objects-screen')),
      findsOneWidget,
    );
    expect(find.text('Corregir geometría y objetos'), findsOneWidget);
    expect(find.textContaining('Forma ilustrativa'), findsWidgets);
    expect(find.textContaining('sin medición real'), findsWidgets);
    expect(find.textContaining(RegExp(r'\d+([.,]\d+)? ?m\b')), findsNothing);
    expect(
      find.textContaining(RegExp(r'medición (automática|de fotos)')).evaluate(),
      isEmpty,
    );
  });

  testWidgets('shape correction only changes local prototype state', (
    tester,
  ) async {
    await openGeometryPrototype(tester);
    final summary = find.byKey(const ValueKey('geometry-correction-summary'));

    await tester.scrollUntilVisible(summary, 200);
    expect(find.text('Formas corregidas: 0 de 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shape-room-correction')),
      -200,
    );
    await tester.tap(find.byKey(const ValueKey('shape-room-correction')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(summary, 200);
    expect(find.text('Formas corregidas: 1 de 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shape-object-correction')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('shape-object-correction')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(summary, 200);
    expect(find.text('Formas corregidas: 2 de 2'), findsOneWidget);
  });

  Future<void> openOfferPrototype(WidgetTester tester) async {
    await openGeometryPrototype(tester);
    await tapScreenEndAction(tester, 'geometry-continue');
  }

  testWidgets('offer step stays conceptual without commercial values', (
    tester,
  ) async {
    await openOfferPrototype(tester);

    expect(find.byKey(const ValueKey('offer-screen')), findsOneWidget);
    expect(find.text('Preparar oferta'), findsOneWidget);
    expect(find.textContaining('pendiente de definir'), findsNWidgets(2));
    expect(find.textContaining('Sin moneda definida'), findsOneWidget);
    expect(find.textContaining(RegExp(r'USD|EUR|\$|€')), findsNothing);
    expect(find.textContaining(RegExp(r'\d+[.,]\d{2}')), findsNothing);
  });

  testWidgets(
    'summary states object, consequence and action before a simulated submit',
    (tester) async {
      await openOfferPrototype(tester);
      await tapScreenEndAction(tester, 'offer-continue');

      expect(
        find.byKey(const ValueKey('review-summary-screen')),
        findsOneWidget,
      );
      expect(find.text('Objeto:'), findsOneWidget);
      expect(find.text('Consecuencia:'), findsOneWidget);
      expect(find.text('Acción elegida:'), findsOneWidget);
      expect(find.byKey(const ValueKey('submission-result')), findsNothing);

      await tapScreenEndAction(tester, 'confirm-submit');

      expect(find.byKey(const ValueKey('submission-result')), findsOneWidget);
      expect(
        find.textContaining('pendiente de revisión (simulado)'),
        findsOneWidget,
      );
      expect(find.textContaining('no se envió nada real'), findsOneWidget);
      expect(find.textContaining('no hay persistencia'), findsOneWidget);
    },
  );

  testWidgets('new capture steps meet touch target guidelines', (tester) async {
    await openGeometryPrototype(tester);
    final semantics = tester.ensureSemantics();
    try {
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(find.byKey(const ValueKey('shape-room-correction')));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tapScreenEndAction(tester, 'geometry-continue');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('new capture steps survive 320 px and larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: const RoomsPhotosScreen(),
          ),
        ),
      ),
    );
    for (final key in [
      'rooms-photos-continue',
      'geometry-continue',
      'offer-continue',
    ]) {
      await tapScreenEndAction(tester, key);
      expect(tester.takeException(), isNull, reason: 'after $key');
    }
    expect(find.byKey(const ValueKey('review-summary-screen')), findsOneWidget);
  });

  testWidgets('walks credentials, the second factor and the private drafts', (
    tester,
  ) async {
    await pumpCaptureApp(tester, signedIn: false);

    await tester.enterText(
      find.byKey(const ValueKey('access-email-field')),
      'agent@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('access-password-field')),
      'password123',
    );
    await tester.tap(find.byKey(const ValueKey('access-credentials-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('access-code-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('access-code-field')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('access-code-submit')));
    await tester.pumpAndSettle();

    expect(find.text('agent@example.test'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('access-continue-button')),
      findsOneWidget,
    );
  });

  testWidgets('reports rejected credentials without opening a session', (
    tester,
  ) async {
    final backend = FakeStaffBackend()..loginRejected = true;
    final controller = StaffSessionController(
      api: StaffAuthApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
      credentialStore: InMemoryStaffCredentialStore(),
    );
    await controller.restore();
    await tester.pumpWidget(
      CaptureApp(
        controller: controller,
        listingsApi: fakeListingsApi(),
        photosApi: fakePhotosApi(),
        photoSource: FakePhotoSource(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('access-email-field')),
      'agent@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('access-password-field')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const ValueKey('access-credentials-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('access-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('access-continue-button')), findsNothing);
  });

  testWidgets('offers a retry when the stored session cannot be validated', (
    tester,
  ) async {
    final backend = FakeStaffBackend()..offline = true;
    final controller = StaffSessionController(
      api: StaffAuthApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
      credentialStore: InMemoryStaffCredentialStore(
        refreshCookie: 'refresh-cookie',
        csrfToken: 'csrf-1',
      ),
    );
    await controller.restore();
    await tester.pumpWidget(
      CaptureApp(
        controller: controller,
        listingsApi: fakeListingsApi(),
        photosApi: fakePhotosApi(),
        photoSource: FakePhotoSource(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('access-retry')), findsOneWidget);

    backend.offline = false;
    await tester.tap(find.byKey(const ValueKey('access-retry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('access-continue-button')),
      findsOneWidget,
    );
  });

  testWidgets('logs out and returns to the credentials step', (tester) async {
    await pumpCaptureApp(tester, signedIn: true);

    await tester.tap(find.byKey(const ValueKey('access-logout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('access-email-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('access-continue-button')), findsNothing);
  });
}
