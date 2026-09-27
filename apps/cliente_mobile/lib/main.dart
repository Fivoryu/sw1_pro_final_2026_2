import 'package:flutter/material.dart';

void main() => runApp(const RoomForgeApp());

class RoomForgeApp extends StatelessWidget {
  const RoomForgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomForge',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      useMaterial3: true,
    ),
    home: const CustomerShell(),
  );
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;
  final Map<String, String> _filters = {};

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CatalogFiltersSheet(
        initialFilters: Map<String, String>.of(_filters),
      ),
    );
    if (result != null && mounted) {
      setState(
        () => _filters
          ..clear()
          ..addAll(result),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RoomForge')),
    body: IndexedStack(
      index: _selectedIndex,
      children: [
        _catalog(context),
        _placeholder(
          context,
          'Prototipo de reservas',
          'No hay reservas reales ni datos conectados.',
          Icons.event_note_outlined,
        ),
        _placeholder(
          context,
          'Prototipo de cuenta',
          'No hay datos de cuenta conectados.',
          Icons.person_outline,
        ),
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

  Widget _catalog(BuildContext context) => _content(
    ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Explorar inmuebles',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('catalog-filter-button'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _openFilters,
          icon: const Icon(Icons.tune),
          label: const Text('Filtrar catálogo'),
        ),
        const SizedBox(height: 20),
        _messageCard(
          context,
          'Catálogo sin conexión',
          'La aplicación todavía no está conectada a un catálogo de inmuebles.',
          Icons.apartment_outlined,
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

class _CatalogFiltersSheet extends StatefulWidget {
  const _CatalogFiltersSheet({required this.initialFilters});
  final Map<String, String> initialFilters;

  @override
  State<_CatalogFiltersSheet> createState() => _CatalogFiltersSheetState();
}

class _CatalogFiltersSheetState extends State<_CatalogFiltersSheet> {
  late final _city = _controller('cityZone');
  late final _price = _controller('basePrice');
  late final _bedrooms = _controller('bedrooms');
  late final _bathrooms = _controller('bathrooms');
  String? _operation;

  TextEditingController _controller(String key) =>
      TextEditingController(text: widget.initialFilters[key]);

  @override
  void initState() {
    super.initState();
    _operation = widget.initialFilters['operation'];
  }

  @override
  void dispose() {
    _city.dispose();
    _price.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    super.dispose();
  }

  void _save() {
    final values = {
      'cityZone': _city.text.trim(),
      'basePrice': _price.text.trim(),
      'bedrooms': _bedrooms.text.trim(),
      'bathrooms': _bathrooms.text.trim(),
    };
    if (_operation != null) values['operation'] = _operation!;
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Filtros del catálogo',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        _field('Ciudad/zona', _city, 'filter-city-zone'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('filter-operation'),
          initialValue: _operation,
          decoration: const InputDecoration(
            labelText: 'Operación',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Venta', child: Text('Venta')),
            DropdownMenuItem(value: 'Alquiler', child: Text('Alquiler')),
          ],
          onChanged: (value) => setState(() => _operation = value),
        ),
        const SizedBox(height: 12),
        _field('Precio base', _price, 'filter-base-price', numeric: true),
        const SizedBox(height: 12),
        _field('Habitaciones', _bedrooms, 'filter-bedrooms', numeric: true),
        const SizedBox(height: 12),
        _field('Baños', _bathrooms, 'filter-bathrooms', numeric: true),
        const SizedBox(height: 12),
        Text(
          'Los filtros son una demostración local; no hay API ni resultados conectados.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _save,
            child: const Text('Guardar filtros'),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller,
    String key, {
    bool numeric = false,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}
