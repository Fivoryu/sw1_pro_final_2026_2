import 'package:captura_mobile/ui/guide/contextual_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpCaptureApp;

void main() {
  testWidgets('the access screen offers the access guide before sign-in', (
    tester,
  ) async {
    final controller = await pumpCaptureApp(tester);
    expect(find.byKey(const ValueKey('guide-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guide-button')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(guideTitle(GuideScreen.access)), findsOneWidget);
    // The guide only explains: no session was opened by it.
    expect(controller.status.name, 'signedOut');
  });

  testWidgets('the home screen offers the welcome guide once signed in', (
    tester,
  ) async {
    await pumpCaptureApp(tester, signedIn: true);
    expect(find.byKey(const ValueKey('guide-button')), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('guide-button')).first);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(guideTitle(GuideScreen.welcome)), findsOneWidget);
  });
}
