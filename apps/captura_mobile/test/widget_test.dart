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

  testWidgets('Nuevo inmueble reveals the not-built next step', (tester) async {
    await tester.pumpWidget(const CaptureApp());
    await tester.tap(find.byKey(const ValueKey('access-continue-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('new-property-placeholder-dialog')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('new-property-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('new-property-placeholder-dialog')),
      findsOneWidget,
    );
    expect(find.text('Paso siguiente no disponible'), findsOneWidget);
    expect(find.textContaining('todavía no está construido'), findsOneWidget);
  });

  testWidgets('closing the placeholder keeps the drafts shell', (tester) async {
    await tester.pumpWidget(const CaptureApp());
    await tester.tap(find.byKey(const ValueKey('access-continue-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-property-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('new-property-placeholder-close')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('new-property-placeholder-dialog')),
      findsNothing,
    );
    expect(find.text('Borradores de inmuebles'), findsOneWidget);
    expect(find.byKey(const ValueKey('drafts-empty-state')), findsOneWidget);
  });
}
