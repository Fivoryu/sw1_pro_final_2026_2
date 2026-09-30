import 'package:flutter/material.dart';

import '../../../../domain/customer_session_controller.dart';

/// Account tab: renders the customer session state and drives login,
/// registration, retry, and logout.
class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({super.key, required this.controller});

  final CustomerSessionController controller;

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final email = _email.text.trim();
    final password = _password.text;
    if (_registering) {
      await widget.controller.register(email: email, password: password);
    } else {
      await widget.controller.signIn(email: email, password: password);
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final status = widget.controller.status;
    return _scroll(
      switch (status) {
        CustomerSessionStatus.restoring => _restoring(context),
        CustomerSessionStatus.unavailable => _unavailable(context),
        CustomerSessionStatus.signedIn => _signedIn(context),
        CustomerSessionStatus.signedOut => _form(context),
      },
    );
  }

  Widget _scroll(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );

  Widget _title(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.headlineSmall,
  );

  List<Widget> _restoring(BuildContext context) => [
    _title(context, 'Cuenta'),
    const SizedBox(height: 20),
    const Center(
      key: ValueKey('account-restoring'),
      child: CircularProgressIndicator(),
    ),
    const SizedBox(height: 16),
    const Text('Restaurando tu sesión…'),
  ];

  List<Widget> _unavailable(BuildContext context) => [
    _title(context, 'Cuenta'),
    const SizedBox(height: 20),
    _notice(context, widget.controller.message, isError: true),
    const SizedBox(height: 16),
    SizedBox(
      height: 48,
      child: FilledButton(
        key: const ValueKey('account-retry'),
        onPressed: () => widget.controller.restore(),
        child: const Text('Reintentar'),
      ),
    ),
  ];

  List<Widget> _signedIn(BuildContext context) {
    final identity = widget.controller.identity;
    return [
      _title(context, 'Tu cuenta'),
      const SizedBox(height: 20),
      Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                identity?.email ?? '',
                key: const ValueKey('account-email'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Identificador: ${identity?.id ?? ''}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (widget.controller.message != null) ...[
        _notice(context, widget.controller.message, isError: true),
        const SizedBox(height: 16),
      ],
      SizedBox(
        height: 48,
        child: OutlinedButton(
          key: const ValueKey('account-logout'),
          onPressed: _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  await widget.controller.signOut();
                  if (mounted) setState(() => _submitting = false);
                },
          child: const Text('Cerrar sesión'),
        ),
      ),
    ];
  }

  List<Widget> _form(BuildContext context) => [
    _title(context, _registering ? 'Crear cuenta' : 'Iniciar sesión'),
    const SizedBox(height: 20),
    if (widget.controller.message != null) ...[
      _notice(context, widget.controller.message),
      const SizedBox(height: 16),
    ],
    Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('account-email-field'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Ingresá tu correo electrónico'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('account-password-field'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.length < 8)
                ? 'La contraseña necesita al menos 8 caracteres'
                : null,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const ValueKey('account-submit'),
              onPressed: _submitting ? null : _submit,
              child: Text(_registering ? 'Crear cuenta' : 'Entrar'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('account-toggle-register'),
            onPressed: _submitting
                ? null
                : () => setState(() => _registering = !_registering),
            child: Text(
              _registering
                  ? 'Ya tengo cuenta: iniciar sesión'
                  : 'No tengo cuenta: registrarme',
            ),
          ),
        ],
      ),
    ),
  ];

  Widget _notice(BuildContext context, String? message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('account-message'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message ?? '', style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
