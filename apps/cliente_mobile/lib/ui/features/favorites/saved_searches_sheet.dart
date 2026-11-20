import 'package:flutter/material.dart';

import '../../../data/models/catalog_models.dart';
import '../../../data/models/favorite_models.dart';
import '../../../domain/customer_favorites_controller.dart';
import '../catalog/views/catalog_format.dart';

/// Whether [filters] has anything a saved search keeps: the zone point never
/// counts, because the customer's location is not stored.
bool hasSavableFilters(CatalogFilters filters) =>
    savedFiltersToJson(filters).isNotEmpty;

/// One line summarizing the saved filters, in the catalog's words.
String describeFilters(CatalogFilters filters) {
  final parts = <String>[
    ?filters.city,
    ?filters.zone,
    if (filters.operation != null) operationLabel(filters.operation!),
    if (filters.minBasePrice != null) 'desde ${filters.minBasePrice}',
    if (filters.maxBasePrice != null) 'hasta ${filters.maxBasePrice}',
    if (filters.minBedrooms != null) '${filters.minBedrooms}+ dormitorios',
    if (filters.minBathrooms != null) '${filters.minBathrooms}+ baños',
  ];
  return parts.isEmpty ? 'Todo el catálogo' : parts.join(' · ');
}

/// Asks for a name and saves [filters]; shows the outcome in a snack bar.
Future<void> showSaveSearchDialog(
  BuildContext context, {
  required CustomerFavoritesController controller,
  required CatalogFilters filters,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _SaveSearchDialog(controller: controller, filters: filters),
  );
  if (saved == true) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Búsqueda guardada.')),
    );
  }
}

class _SaveSearchDialog extends StatefulWidget {
  const _SaveSearchDialog({required this.controller, required this.filters});

  final CustomerFavoritesController controller;
  final CatalogFilters filters;

  @override
  State<_SaveSearchDialog> createState() => _SaveSearchDialogState();
}

class _SaveSearchDialogState extends State<_SaveSearchDialog> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribí un nombre para la búsqueda.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await widget.controller.saveSearch(name, widget.filters);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Guardar búsqueda'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(describeFilters(widget.filters)),
        if (widget.filters.hasZone) ...[
          const SizedBox(height: 8),
          const Text(
            'La zona elegida en el mapa no se guarda: tu ubicación no se '
            'almacena.',
            key: ValueKey('save-search-zone-note'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('save-search-name'),
          controller: _name,
          maxLength: 80,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saving ? null : _save(),
          decoration: InputDecoration(
            labelText: 'Nombre',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('save-search-confirm'),
        onPressed: _saving ? null : _save,
        child: const Text('Guardar'),
      ),
    ],
  );
}

/// The customer's saved searches. Tapping one closes the sheet with its
/// filters so the catalog can apply them.
class SavedSearchesSheet extends StatelessWidget {
  const SavedSearchesSheet({super.key, required this.controller});

  final CustomerFavoritesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final searches = controller.savedSearches;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Mis búsquedas',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (searches.isEmpty)
            const Text(
              'Todavía no guardaste búsquedas. Filtrá el catálogo y tocá '
              '«Guardar búsqueda».',
              key: ValueKey('saved-searches-empty'),
            )
          else
            for (final search in searches) _tile(context, search),
        ],
      );
    },
  );

  Widget _tile(BuildContext context, SavedSearch search) => ListTile(
    key: ValueKey('saved-search-${search.id}'),
    contentPadding: EdgeInsets.zero,
    title: Text(search.name),
    subtitle: Text(describeFilters(search.filters)),
    onTap: () => Navigator.of(context).pop(search.filters),
    trailing: IconButton(
      key: ValueKey('saved-search-delete-${search.id}'),
      tooltip: 'Borrar búsqueda',
      icon: const Icon(Icons.delete_outline),
      onPressed: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final failure = await controller.deleteSearch(search);
        if (failure != null) {
          messenger?.showSnackBar(SnackBar(content: Text(failure)));
        }
      },
    ),
  );
}
