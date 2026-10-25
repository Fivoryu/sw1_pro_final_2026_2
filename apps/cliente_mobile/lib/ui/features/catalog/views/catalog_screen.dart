import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';
import '../../../../data/services/quote_api.dart';
import '../../../../data/services/scene_api.dart';
import '../../../../domain/catalog_controller.dart';
import '../../../../domain/customer_reservations_controller.dart';
import '../../../../domain/customer_session_controller.dart';
import 'catalog_filters_sheet.dart';
import 'catalog_format.dart';
import 'listing_detail_screen.dart';
import 'listing_photo.dart';
import '../../../theme/andean_theme.dart';
import '../../../theme/andean_widgets.dart';

/// The "Explorar" tab: published listings with filters, paging and honest
/// loading, empty and error states.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.controller,
    this.reservationsController,
    this.sessionController,
    this.sceneApi,
    this.quoteApi,
  });

  final CatalogController controller;
  final CustomerReservationsController? reservationsController;
  final CustomerSessionController? sessionController;

  /// When provided, the detail can offer the 3D walkthrough of a listing.
  final SceneApi? sceneApi;

  /// When provided, scene objects open their commercial hotspot.
  final QuoteApi? quoteApi;

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
          reservationsController: widget.reservationsController,
          sessionController: widget.sessionController,
          sceneApi: widget.sceneApi,
          quoteApi: widget.quoteApi,
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
            const AndeanSectionHeading(
              'Explorar inmuebles',
              subtitle: 'Encontrá un espacio que se sienta propio.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<DisplayCurrency>(
              key: const ValueKey('catalog-currency-selector'),
              initialValue: _controller.displayCurrency,
              decoration: const InputDecoration(
                labelText: 'Moneda de visualización',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final currency in DisplayCurrency.values)
                  DropdownMenuItem(value: currency, child: Text(currency.code)),
              ],
              onChanged: (currency) {
                if (currency != null) {
                  _controller.setDisplayCurrency(currency);
                }
              },
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
    return Card(
      key: ValueKey('catalog-listing-${listing.listingId}'),
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AndeanColors.border, width: 1),
      ),
      color: AndeanColors.surfaceContainerLowest,
      child: InkWell(
        onTap: () => _openListing(listing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: listing.coverPhotoUrl == null
                      ? PhotoPlaceholder(
                          key: ValueKey(
                            'catalog-cover-placeholder-${listing.listingId}',
                          ),
                          message: 'Sin fotos oficiales',
                        )
                      : ListingPhoto(
                          key: ValueKey('catalog-cover-${listing.listingId}'),
                          url: listing.coverPhotoUrl!,
                          semanticLabel: 'Portada de ${locationLabel(listing)}',
                        ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AndeanColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(27, 59, 54, 0.08),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'ID #${listing.listingId}',
                      style: AndeanTypography.monoData.copyWith(
                        color: AndeanColors.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AndeanColors.secondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          locationLabel(listing),
                          style: AndeanTypography.headlineSm.copyWith(
                            fontSize: 17,
                          ),
                        ),
                      ),
                      AndeanPillChip(
                        label: operationLabel(listing.operation),
                        backgroundColor: AndeanColors.surfaceContainerHigh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chargeLabel(listing.basePrice, listing.operation),
                    style: AndeanTypography.headlineMd.copyWith(
                      color: AndeanColors.primaryContainer,
                      fontWeight: FontWeight.bold,
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
