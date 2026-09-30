import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:cliente_mobile/ui/features/auth/views/customer_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_customer_backend.dart';

const _baseUrl = 'https://api.example.test';

({CustomerSessionController controller, FakeCustomerBackend backend, InMemoryCustomerTokenStore store})
_build({String? storedToken}) {
  final backend = FakeCustomerBackend();
  final store = InMemoryCustomerTokenStore(storedToken);
  return (
    controller: CustomerSessionController(
      api: CustomerAuthApi(baseUrl: _baseUrl, client: backend.client),
      tokenStore: store,
    ),
    backend: backend,
    store: store,
  );
}

Widget _wrap(CustomerSessionController controller) =>
    MaterialApp(home: Scaffold(body: CustomerAccountScreen(controller: controller)));

Future<void> _fillCredentials(
  WidgetTester tester, {
  String email = 'client@example.test',
  String password = 'password123',
}) async {
  await tester.enterText(find.byKey(const ValueKey('account-email-field')), email);
  await tester.enterText(find.byKey(const ValueKey('account-password-field')), password);
}

void main() {
  testWidgets('shows a restoration state while the stored session loads', (tester) async {
    final harness = _build(storedToken: 'stored-refresh');

    await tester.pumpWidget(_wrap(harness.controller));

    expect(find.byKey(const ValueKey('account-restoring')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-submit')), findsNothing);
  });

  testWidgets('signs in and then shows the customer identity', (tester) async {
    final harness = _build();
    await harness.controller.restore();
    await tester.pumpWidget(_wrap(harness.controller));

    await _fillCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(harness.controller.status, CustomerSessionStatus.signedIn);
    expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
    expect(find.text('client@example.test'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-logout')), findsOneWidget);
  });

  testWidgets('rejects incomplete credentials locally without calling the API', (tester) async {
    final harness = _build();
    await harness.controller.restore();
    await tester.pumpWidget(_wrap(harness.controller));

    await _fillCredentials(tester, email: '', password: 'short');
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Ingresá tu correo electrónico'), findsOneWidget);
    expect(find.text('La contraseña necesita al menos 8 caracteres'), findsOneWidget);
    expect(harness.backend.calls, isEmpty);
  });

  testWidgets('shows the API message when the credentials are rejected', (tester) async {
    final harness = _build();
    await harness.controller.restore();
    harness.backend.loginRejected = true;
    await tester.pumpWidget(_wrap(harness.controller));

    await _fillCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account-message')), findsOneWidget);
    expect(find.text('Rejected by the API.'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-submit')), findsOneWidget);
  });

  testWidgets('registers an account and asks the customer to sign in', (tester) async {
    final harness = _build();
    await harness.controller.restore();
    await tester.pumpWidget(_wrap(harness.controller));

    await tester.tap(find.byKey(const ValueKey('account-toggle-register')));
    await tester.pumpAndSettle();
    await _fillCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(harness.controller.status, CustomerSessionStatus.signedOut);
    expect(harness.store.token, isNull);
    expect(find.byKey(const ValueKey('account-message')), findsOneWidget);
    expect(find.textContaining('Iniciá sesión'), findsOneWidget);
  });

  testWidgets('surfaces a conflicting registration', (tester) async {
    final harness = _build();
    await harness.controller.restore();
    harness.backend.registerConflict = true;
    await tester.pumpWidget(_wrap(harness.controller));

    await tester.tap(find.byKey(const ValueKey('account-toggle-register')));
    await tester.pumpAndSettle();
    await _fillCredentials(tester);
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Rejected by the API.'), findsOneWidget);
    expect(harness.store.token, isNull);
  });

  testWidgets('logs out and returns to the form', (tester) async {
    final harness = _build(storedToken: 'stored-refresh');
    await harness.controller.restore();
    await tester.pumpWidget(_wrap(harness.controller));
    expect(find.byKey(const ValueKey('account-logout')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-logout')));
    await tester.pumpAndSettle();

    expect(harness.controller.status, CustomerSessionStatus.signedOut);
    expect(harness.store.token, isNull);
    expect(find.byKey(const ValueKey('account-submit')), findsOneWidget);
  });

  testWidgets('offers a retry when the API is unreachable', (tester) async {
    final harness = _build(storedToken: 'stored-refresh');
    harness.backend.offline = true;
    await harness.controller.restore();
    await tester.pumpWidget(_wrap(harness.controller));
    expect(find.byKey(const ValueKey('account-retry')), findsOneWidget);

    harness.backend.offline = false;
    await tester.tap(find.byKey(const ValueKey('account-retry')));
    await tester.pumpAndSettle();

    expect(harness.controller.status, CustomerSessionStatus.signedIn);
    expect(find.text('client@example.test'), findsOneWidget);
  });
}
