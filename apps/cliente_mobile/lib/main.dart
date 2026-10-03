import 'package:flutter/material.dart';

import 'data/services/catalog_api.dart';
import 'data/services/customer_auth_api.dart';
import 'data/services/customer_token_store.dart';
import 'domain/catalog_controller.dart';
import 'domain/customer_session_controller.dart';
import 'ui/features/auth/views/customer_account_screen.dart';
import 'ui/features/catalog/views/catalog_screen.dart';

/// Backend used by the running app. Override it per environment with
/// `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.
const _apiBaseUrl = String.fromEnvironment(
  'ROOMFORGE_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

void main() => runApp(
  RoomForgeApp(
    sessionController: CustomerSessionController(
      api: CustomerAuthApi(baseUrl: _apiBaseUrl),
      tokenStore: SecureCustomerTokenStore(),
    ),
    catalogApi: CatalogApi(baseUrl: _apiBaseUrl),
  ),
);

class RoomForgeApp extends StatelessWidget {
  const RoomForgeApp({
    super.key,
    required this.sessionController,
    required this.catalogApi,
  });

  final CustomerSessionController sessionController;
  final CatalogApi catalogApi;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomForge',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      useMaterial3: true,
    ),
    home: CustomerShell(
      sessionController: sessionController,
      catalogApi: catalogApi,
    ),
  );
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({
    super.key,
    required this.sessionController,
    required this.catalogApi,
  });

  final CustomerSessionController sessionController;
  final CatalogApi catalogApi;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;
  late final _catalog = CatalogController(api: widget.catalogApi);

  @override
  void initState() {
    super.initState();
    widget.sessionController.restore();
  }

  @override
  void dispose() {
    _catalog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RoomForge')),
    body: IndexedStack(
      index: _selectedIndex,
      children: [
        CatalogScreen(controller: _catalog),
        _placeholder(
          context,
          'Prototipo de reservas',
          'No hay reservas reales ni datos conectados.',
          Icons.event_note_outlined,
        ),
        CustomerAccountScreen(controller: widget.sessionController),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore),
          label: 'Explorar',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note),
          label: 'Reservas',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Cuenta',
        ),
      ],
    ),
  );

  Widget _placeholder(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) => _content(
    ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        _messageCard(context, '', message, icon),
      ],
    ),
  );

  Widget _messageCard(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 36, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            if (title.isNotEmpty)
              Text(title, style: theme.textTheme.titleLarge),
            if (title.isNotEmpty && message.isNotEmpty)
              const SizedBox(height: 8),
            if (message.isNotEmpty)
              Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );
}
