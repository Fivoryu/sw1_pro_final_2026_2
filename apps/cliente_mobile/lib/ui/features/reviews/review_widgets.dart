import 'package:flutter/material.dart';

import '../../../data/models/review_models.dart';
import '../../theme/andean_theme.dart';

/// Wording of a rating summary. Fewer than three reviews show no average,
/// and the count and the verified count always appear next to it.
String ratingSummaryText(RatingSummary summary) {
  if (summary.count == 0) return 'Sin calificaciones todavía';
  final counts =
      '${summary.count} ${summary.count == 1 ? 'calificación' : 'calificaciones'}'
      ', ${summary.verifiedCount} ${summary.verifiedCount == 1 ? 'verificada' : 'verificadas'}';
  if (summary.fewRatings || summary.average == null) {
    return 'Pocas calificaciones ($counts)';
  }
  return '★ ${summary.average!.toStringAsFixed(1)} · $counts';
}

/// Five stars with [rating] filled in.
class StarsRow extends StatelessWidget {
  const StarsRow({super.key, required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$rating de 5',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= rating ? Icons.star : Icons.star_border,
              size: 16,
              color: AndeanColors.primary,
            ),
        ],
      ),
    ),
  );
}

/// One review: both ratings, the comment, the verified badge and the
/// agency's reply. The customer is never identified.
class ReviewTile extends StatelessWidget {
  const ReviewTile({
    super.key,
    required this.review,
    this.showListingRating = true,
  });

  final Review review;
  final bool showListingRating;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('review-${review.id}'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showListingRating) ...[
                const Text('Inmueble', style: AndeanTypography.labelMd),
                StarsRow(rating: review.listingRating),
              ],
              const Text('Atención', style: AndeanTypography.labelMd),
              StarsRow(rating: review.agencyRating),
              if (review.verified)
                Chip(
                  key: ValueKey('verified-${review.id}'),
                  label: const Text('Verificada'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (review.comment != null) ...[
            const SizedBox(height: 8),
            Text(review.comment!),
          ],
          if (review.agencyReply != null) ...[
            const SizedBox(height: 8),
            Container(
              key: ValueKey('reply-${review.id}'),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: AndeanColors.surfaceContainerLow,
              child: Text(
                'Respuesta de la inmobiliaria: ${review.agencyReply}',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
