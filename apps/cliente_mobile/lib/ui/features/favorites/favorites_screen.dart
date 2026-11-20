import 'package:flutter/material.dart';

import '../../../data/models/favorite_models.dart';
import '../../../domain/customer_favorites_controller.dart';
import '../../theme/andean_theme.dart';
import '../catalog/views/catalog_format.dart';
import 'favorite_button.dart';

/// The signed-in customer's favorites, newest first.
///
/// A favorite whose listing is no longer published stays in the list without
/// any detail of the listing, and can be removed.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    super.key,
    required this.controller,
    required this.onOpenListing,
  });

  final CustomerFavoritesController controller;
  final void Function(String listingId) onOpenListing;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis favoritos')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _body(context),
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    switch (controller.state) {
      case FavoritesLoadState.idle:
        return _notice(
          context,
          'Iniciá sesión en Cuenta para ver tus favoritos.',
          key: 'favorites-signed-out',
        );
      case FavoritesLoadState.loading:
        return const Center(
          child: CircularProgressIndicator(key: ValueKey('favorites-loading')),
        );
      case FavoritesLoadState.failed:
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              controller.message ?? '',
              key: const ValueKey('favorites-error'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                key: const ValueKey('favorites-retry'),
                onPressed: controller.load,
                child: const Text('Reintentar'),
              ),
            ),
          ],
        );
      case FavoritesLoadState.ready:
        if (controller.favorites.isEmpty) {
          return _notice(
            context,
            'Todavía no guardaste favoritos. Tocá el corazón de un inmueble '
            'para encontrarlo acá.',
            key: 'favorites-empty',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final entry in controller.favorites) _tile(context, entry),
          ],
        );
    }
  }

  Widget _notice(BuildContext context, String text, {required String key}) =>
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            text,
            key: ValueKey(key),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      );

  Widget _tile(BuildContext context, FavoriteEntry entry) {
    final listing = entry.listing;
    return Card(
      key: ValueKey('favorite-${entry.listingId}'),
      margin: const EdgeInsets.only(bottom: 12),
      color: AndeanColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AndeanColors.border),
      ),
      child: listing == null
          ? ListTile(
              title: const Text('Este inmueble ya no está publicado.'),
              subtitle: Text('ID #${entry.listingId}'),
              trailing: TextButton(
                key: ValueKey('favorite-remove-${entry.listingId}'),
                onPressed: controller.isPending(entry.listingId)
                    ? null
                    : () => _remove(context, entry.listingId),
                child: const Text('Quitar'),
              ),
            )
          : ListTile(
              onTap: () => onOpenListing(entry.listingId),
              title: Text(locationLabel(listing)),
              subtitle: Text(
                '${operationLabel(listing.operation)} · '
                '${chargeLabel(listing.basePrice, listing.operation)}',
              ),
              trailing: FavoriteButton(
                controller: controller,
                listingId: entry.listingId,
                listing: listing,
              ),
            ),
    );
  }

  Future<void> _remove(BuildContext context, String listingId) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = await controller.toggle(listingId);
    if (failure != null) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    }
  }
}
