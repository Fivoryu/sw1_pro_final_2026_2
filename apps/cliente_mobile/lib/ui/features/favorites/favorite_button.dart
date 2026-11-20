import 'package:flutter/material.dart';

import '../../../data/models/catalog_models.dart';
import '../../../domain/customer_favorites_controller.dart';
import '../../theme/andean_theme.dart';

/// Heart that marks or unmarks a listing as favorite.
///
/// It only shows while a customer's favorites are loaded: signed out, the
/// catalog looks and behaves as without the feature.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.controller,
    required this.listingId,
    this.listing,
    this.onSurface = false,
  });

  final CustomerFavoritesController controller;
  final String listingId;

  /// Summary shown in the favorites list until the next load.
  final CatalogListing? listing;

  /// Draws a light circle behind the heart, for use over a photo.
  final bool onSurface;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.state != FavoritesLoadState.ready) {
        return const SizedBox.shrink();
      }
      final favorite = controller.isFavorite(listingId);
      final button = IconButton(
        key: ValueKey('favorite-toggle-$listingId'),
        tooltip: favorite ? 'Quitar de favoritos' : 'Guardar en favoritos',
        isSelected: favorite,
        onPressed: controller.isPending(listingId)
            ? null
            : () async {
                final messenger = ScaffoldMessenger.maybeOf(context);
                final failure = await controller.toggle(
                  listingId,
                  listing: listing,
                );
                if (failure != null) {
                  messenger?.showSnackBar(SnackBar(content: Text(failure)));
                }
              },
        icon: const Icon(Icons.favorite_border),
        selectedIcon: const Icon(Icons.favorite, color: Color(0xFFB3261E)),
      );
      if (!onSurface) return button;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AndeanColors.surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: button,
      );
    },
  );
}
