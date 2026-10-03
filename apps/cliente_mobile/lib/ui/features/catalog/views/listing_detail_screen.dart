import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';
import '../../../../domain/catalog_controller.dart';
import 'catalog_format.dart';

/// Public detail of one published listing.
///
/// Without a 3D model or availability data from the API, it says so instead
/// of showing a foreign scene or a guessed status.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.controller,
    required this.listingId,
  });

  final CatalogController controller;
  final String listingId;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  CatalogListingDetail? _detail;
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await widget.controller.loadDetail(widget.listingId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = result.detail;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle del inmueble')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _body(context),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: ValueKey('detail-loading')),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _message ?? '',
            key: const ValueKey('detail-error'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const ValueKey('detail-retry'),
              onPressed: _load,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final listing = detail.listing;
    return ListView(
      key: const ValueKey('property-detail-content'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(locationLabel(listing), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(operationLabel(listing.operation)),
        const SizedBox(height: 4),
        Text(roomsLabel(detail.bedrooms, detail.bathrooms)),
        const SizedBox(height: 24),
        Text('Precio base', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          chargeLabel(listing.basePrice, listing.operation),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(basePriceNote(listing.operation)),
        const SizedBox(height: 24),
        Text('Opcionales', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.extras.isEmpty)
          const Text('Este inmueble no tiene opcionales.')
        else
          for (final extra in detail.extras)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(extra.name),
                  Text(
                    chargeLabel(extra.price, listing.operation),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        const SizedBox(height: 24),
        Text('Recorrido 3D', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Recorrido 3D no disponible.'),
        const SizedBox(height: 24),
        Text('Disponibilidad', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Disponibilidad no consultada ni confirmada.'),
      ],
    );
  }
}
