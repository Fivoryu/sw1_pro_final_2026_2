import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';
import '../../../../domain/catalog_controller.dart';
import 'catalog_filters_sheet.dart';
import 'catalog_format.dart';
import 'listing_detail_screen.dart';
import 'listing_photo.dart';

/// The "Explorar" tab: published listings with filters, paging and honest
/// loading, empty and error states.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.controller});

  final CatalogController controller;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  CatalogController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_controller.loadState == CatalogLoadState.loading) {
      _controller.search();
    }
  }

  Future<void> _openFilters() async {
    final filters = await showModalBottomSheet<CatalogFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CatalogFiltersSheet(initialFilters: _controller.filters),
    );
    if (filters != null && mounted) await _controller.search(filters);
  }

  void _openListing(CatalogListing listing) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailScreen(
          controller: _controller,
          listingId: listing.listingId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Explorar inmuebles',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('catalog-filter-button'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _openFilters,
              icon: const Icon(Icons.tune),
              label: const Text('Filtrar catálogo'),
            ),
            if (!_controller.filters.isEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const ValueKey('catalog-clear-filters'),
                  onPressed: () => _controller.search(const CatalogFilters()),
                  child: const Text('Quitar filtros'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ..._content(context),
          ],
        ),
      ),
    ),
  );

  List<Widget> _content(BuildContext context) {
    switch (_controller.loadState) {
      case CatalogLoadState.loading:
        return const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                key: ValueKey('catalog-loading'),
              ),
            ),
          ),
        ];
      case CatalogLoadState.failed:
        return [
          Text(
            _controller.message ?? '',
            key: const ValueKey('catalog-error'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const ValueKey('catalog-retry'),
              onPressed: () => _controller.search(),
              child: const Text('Reintentar'),
            ),
          ),
        ];
      case CatalogLoadState.ready:
        if (_controller.items.isEmpty) {
          return [
            Text(
              _controller.filters.isEmpty
                  ? 'Todavía no hay inmuebles publicados.'
                  : 'No hay inmuebles con esos filtros.',
              key: const ValueKey('catalog-empty'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ];
        }
        return [
          for (final listing in _controller.items) _card(context, listing),
          if (_controller.loadMoreMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _controller.loadMoreMessage!,
                key: const ValueKey('catalog-load-more-error'),
              ),
            ),
          if (_controller.isLoadingMore)
            const Center(child: CircularProgressIndicator())
          else if (_controller.hasMore)
            SizedBox(
              height: 48,
              child: OutlinedButton(
                key: const ValueKey('catalog-load-more'),
                onPressed: _controller.loadMore,
                child: const Text('Cargar más'),
              ),
            ),
        ];
    }
  }

  Widget _card(BuildContext context, CatalogListing listing) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('catalog-listing-${listing.listingId}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openListing(listing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 160,
              child: listing.coverPhotoUrl == null
                  ? PhotoPlaceholder(
                      key: ValueKey(
                        'catalog-cover-placeholder-${listing.listingId}',
                      ),
                    )
                  : ListingPhoto(
                      key: ValueKey('catalog-cover-${listing.listingId}'),
                      url: listing.coverPhotoUrl!,
                      semanticLabel: 'Portada de ${locationLabel(listing)}',
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locationLabel(listing),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(operationLabel(listing.operation)),
                  const SizedBox(height: 4),
                  Text(
                    chargeLabel(listing.basePrice, listing.operation),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
