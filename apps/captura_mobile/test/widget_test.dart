import 'package:captura_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on the access step and declares the prototype', (
    tester,
  ) async {
    await tester.pumpWidget(const CaptureApp());

    expect(find.text('Acceso del agente'), findsOneWidget);
    expect(find.textContaining('no pide credenciales'), findsOneWidget);
    expect(find.textContaining('Prototipo de interfaz'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('access-continue-button')),
      findsOneWidget,
    );
  });

  testWidgets('access step offers no credential fields', (tester) async {
    await tester.pumpWidget(const CaptureApp());

    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Form), findsNothing);
  });

  testWidgets('continues from access to the drafts shell', (tester) async {
    await tester.pumpWidget(const CaptureApp());

    await tester.tap(find.byKey(const ValueKey('access-continue-button')));
    await tester.pumpAndSettle();

    expect(find.text('Borradores de inmuebles'), findsOneWidget);
    expect(find.byKey(const ValueKey('drafts-empty-state')), findsOneWidget);
    expect(find.textContaining('Todavía no hay borradores'), findsOneWidget);
    expect(
      find.textContaining('no se guardan ni se sincronizan'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('new-property-button')), findsOneWidget);
  });

  testWidgets('drafts shell shows no property fixture', (tester) async {
    await tester.pumpWidget(const CaptureApp());
    await tester.tap(find.byKey(const ValueKey('access-continue-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drafts-empty-state')), findsOneWidget);
    expect(find.textContaining(RegExp(r'USD|EUR|\$ |Vivienda')), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  Future<void> openNewPropertyPrototype(WidgetTester tester) async {
    await tester.pumpWidget(const CaptureApp());
    await tester.tap(find.byKey(const ValueKey('access-continue-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-property-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('Nuevo inmueble opens the basic operation step', (tester) async {
    await openNewPropertyPrototype(tester);

    expect(
      find.byKey(const ValueKey('basic-operation-screen')),
      findsOneWidget,
    );
    expect(find.text('Datos básicos y operación'), findsOneWidget);
    expect(find.textContaining('no define campos F04'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('basic-operation-continue')),
      findsOneWidget,
    );
  });

  testWidgets('navigates between both local prototype steps and back', (
    tester,
  ) async {
    await openNewPropertyPrototype(tester);

    await tester.tap(find.byKey(const ValueKey('basic-operation-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rooms-photos-screen')), findsOneWidget);
    expect(find.text('Ambientes y fotos'), findsOneWidget);
    expect(find.textContaining('No se guardan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rooms-photos-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('basic-operation-screen')),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Borradores de inmuebles'), findsOneWidget);
    expect(find.byKey(const ValueKey('drafts-empty-state')), findsOneWidget);
  });

  testWidgets('flow remains scroll-safe at a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openNewPropertyPrototype(tester);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('basic-operation-continue')))
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(const ValueKey('basic-operation-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Ambientes y fotos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes simulated permission, offline, error and retry states', (
    tester,
  ) async {
    await openNewPropertyPrototype(tester);
    await tester.tap(find.byKey(const ValueKey('basic-operation-continue')));
    await tester.pumpAndSettle();

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
    await openNewPropertyPrototype(tester);
    await tester.tap(find.byKey(const ValueKey('basic-operation-continue')));
    await tester.pumpAndSettle();

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
}
