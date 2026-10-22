import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';
import '../../../../data/services/quote_api.dart';
import '../../quote/views/listing_quote_screen.dart';
import '../../catalog/views/catalog_format.dart';

/// Commercial hotspot for a tapped scene object (F06.5): the object id is the
/// only truth the scene carries, so the sheet matches it against the listing
/// extras and says honestly when the object has no published price.
Future<void> showObjectHotspotSheet(
  BuildContext context, {
  required String objectId,
  required CatalogListingDetail detail,
  required QuoteApi quoteApi,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => _ObjectHotspotSheet(
      objectId: objectId,
      detail: detail,
      quoteApi: quoteApi,
    ),
  );
}

class _ObjectHotspotSheet extends StatelessWidget {
  const _ObjectHotspotSheet({
    required this.objectId,
    required this.detail,
    required this.quoteApi,
  });

  final String objectId;
  final CatalogListingDetail detail;
  final QuoteApi quoteApi;

  CatalogExtra? _matchingExtra() {
    for (final extra in detail.extras) {
      if (extra.extraId == objectId) return extra;
    }
    return null;
  }

  void _openQuote(BuildContext context, String? preselectedExtraId) {
    Navigator.of(context).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingQuoteScreen(
          quoteApi: quoteApi,
          detail: detail,
          preselectedExtraId: preselectedExtraId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extra = _matchingExtra();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Objeto de la escena', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(objectId, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (extra != null) ...[
              Text(extra.name),
              Text(formatMoney(extra.price.amount, extra.price.currency)),
            ] else
              const Text(
                'Este objeto es parte del recorrido; no tiene precio publicado.',
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('hotspot-quote'),
              onPressed: () => _openQuote(context, extra?.extraId),
              child: const Text('Cotizar este inmueble'),
            ),
          ],
        ),
      ),
    );
  }
}
