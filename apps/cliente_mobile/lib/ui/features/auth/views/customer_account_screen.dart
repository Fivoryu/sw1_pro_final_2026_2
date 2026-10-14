import 'package:flutter/material.dart';

import '../../../../data/models/reservation_models.dart';
import '../../../../data/services/customer_booking_api.dart';
import '../../../../data/services/local_wallet_connect.dart';
import '../../../../domain/customer_session_controller.dart';

/// Account tab: renders the customer session state and drives login,
/// registration, retry, and logout.
class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({
    super.key,
    required this.controller,
    this.bookingApi,
    this.walletConnect,
  });

  final CustomerSessionController controller;
  final CustomerBookingApi? bookingApi;
  final LocalWalletConnect? walletConnect;

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _submitting = false;
  bool _walletBusy = false;
  List<CustomerWallet> _wallets = const [];
  String? _walletMessage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
    widget.walletConnect?.addListener(_walletChanged);
    _sessionChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sessionChanged);
    widget.walletConnect?.removeListener(_walletChanged);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _walletChanged() {
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (widget.controller.status == CustomerSessionStatus.signedIn &&
        widget.bookingApi != null) {
      _loadWallets();
    } else if (widget.controller.status == CustomerSessionStatus.signedOut) {
      _wallets = const [];
      _walletMessage = null;
    }
  }

  Future<void> _loadWallets() async {
    final api = widget.bookingApi;
    if (api == null || _walletBusy) return;
    _walletBusy = true;
    try {
      final wallets = await api.listWallets();
      if (mounted) setState(() => _wallets = wallets);
    } catch (_) {
      if (mounted) {
        setState(
          () => _walletMessage = 'No pudimos consultar la wallet vinculada.',
        );
      }
    } finally {
      _walletBusy = false;
    }
  }

  Future<void> _linkWallet() async {
    final api = widget.bookingApi;
    final connect = widget.walletConnect;
    if (api == null || connect == null) return;
    setState(() {
      _walletBusy = true;
      _walletMessage = null;
    });
    try {
      if (!connect.isConnected) await connect.openConnect();
      final address = connect.address;
      if (address == null) {
        setState(
          () => _walletMessage = 'Conectá una wallet EVM para continuar.',
        );
        return;
      }
      final challenge = await api.createWalletChallenge(address: address);
      final signature = await connect.signPersonalMessage(challenge.message);
      final linked = await api.linkWallet(
        challengeId: challenge.challengeId,
        signature: signature,
      );
      setState(() {
        _wallets = [linked];
        _walletMessage = 'Wallet verificada y vinculada a tu cuenta.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _walletMessage = _safeWalletMessage(error));
      }
    } finally {
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  Future<void> _connectLinkedWallet() async {
    final connect = widget.walletConnect;
    if (connect == null || _wallets.isEmpty) return;
    setState(() {
      _walletBusy = true;
      _walletMessage = null;
    });
    try {
      await connect.openConnect();
      if (!connect.isConfigured) {
        setState(
          () => _walletMessage =
              'Falta configurar el Project ID público de Reown.',
        );
        return;
      }
      final address = connect.address;
      if (!connect.isConnected || address == null) {
        setState(
          () => _walletMessage = 'Conectá la wallet vinculada para continuar.',
        );
        return;
      }
      if (address.toLowerCase() != _wallets.single.address.toLowerCase()) {
        setState(
          () => _walletMessage =
              'La cuenta conectada no coincide con la wallet verificada de RoomForge.',
        );
        return;
      }
      setState(
        () =>
            _walletMessage = 'Wallet verificada conectada y lista para operar.',
      );
    } catch (error) {
      if (mounted) setState(() => _walletMessage = _safeWalletMessage(error));
    } finally {
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  String _safeWalletMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('reject') || text.contains('user denied')) {
      return 'La firma fue rechazada. No se vinculó ninguna wallet.';
    }
    if (error is StateError) return error.message;
    return 'No se pudo verificar la wallet. Podés intentarlo de nuevo.';
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
    return _scroll(switch (status) {
      CustomerSessionStatus.restoring => _restoring(context),
      CustomerSessionStatus.unavailable => _unavailable(context),
      CustomerSessionStatus.signedIn => _signedIn(context),
      CustomerSessionStatus.signedOut => _form(context),
    });
  }

  Widget _scroll(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );

  Widget _title(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);

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
      if (widget.bookingApi != null) ...[
        const SizedBox(height: 20),
        _walletSection(context),
      ],
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

  Widget _walletSection(BuildContext context) {
    final linkedWallet = _wallets.isEmpty ? null : _wallets.single;
    final connect = widget.walletConnect;
    final linkedWalletConnected =
        linkedWallet != null &&
        connect?.isConnected == true &&
        connect?.address?.toLowerCase() == linkedWallet.address.toLowerCase();
    return Card(
      key: const ValueKey('customer-wallet-section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wallet externa',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (linkedWallet != null)
              Text(
                'Verificada: ${linkedWallet.address}',
                key: const ValueKey('linked-wallet'),
              )
            else
              const Text(
                'Vinculá una wallet EVM para firmar operaciones de reserva.',
              ),
            if (_walletMessage != null) ...[
              const SizedBox(height: 8),
              Text(_walletMessage!, key: const ValueKey('wallet-message')),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('wallet-connect'),
                onPressed: _walletBusy || linkedWalletConnected
                    ? null
                    : linkedWallet == null
                    ? _linkWallet
                    : _connectLinkedWallet,
                icon: _walletBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  _walletBusy
                      ? 'Conectando…'
                      : linkedWallet == null
                      ? 'Conectar y verificar wallet'
                      : linkedWalletConnected
                      ? 'Wallet conectada'
                      : 'Conectar wallet vinculada',
                ),
              ),
            ),
            if (connect?.isConfigured == false)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Falta configurar el Project ID público de Reown.'),
              ),
          ],
        ),
      ),
    );
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

  Widget _notice(
    BuildContext context,
    String? message, {
    bool isError = false,
  }) {
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
