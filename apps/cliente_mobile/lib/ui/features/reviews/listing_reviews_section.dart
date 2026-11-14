import 'package:flutter/material.dart';

import '../../../data/models/review_models.dart';
import '../../../data/services/customer_reviews_api.dart';
import '../../../domain/customer_session_controller.dart';
import '../../../domain/listing_reviews_controller.dart';
import '../../theme/andean_theme.dart';
import 'agency_reviews_screen.dart';
import 'review_form_dialog.dart';
import 'review_widgets.dart';

const _maxShown = 5;

/// Reviews block of the listing detail: ratings of the listing and of the
/// agency, the latest reviews, and the form for who may rate.
class ListingReviewsSection extends StatefulWidget {
  const ListingReviewsSection({
    super.key,
    required this.api,
    required this.listingId,
    this.sessionController,
  });

  final CustomerReviewsApi api;
  final String listingId;
  final CustomerSessionController? sessionController;

  @override
  State<ListingReviewsSection> createState() => _ListingReviewsSectionState();
}

class _ListingReviewsSectionState extends State<ListingReviewsSection> {
  late final ListingReviewsController _controller = ListingReviewsController(
    api: widget.api,
    listingId: widget.listingId,
    isSignedIn: () =>
        widget.sessionController?.status == CustomerSessionStatus.signedIn,
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openForm() async {
    final existing = _controller.mine?.review;
    final listing = _controller.reviews;
    await showReviewForm(
      context,
      controller: _controller,
      existing: existing,
      verified: existing?.verified ?? false,
      agencyName: listing?.agencyName ?? 'la inmobiliaria',
    );
  }

  void _openAgency(ListingReviews reviews) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AgencyReviewsScreen(
          api: widget.api,
          agencyId: reviews.agencyId,
          agencyName: reviews.agencyName,
        ),
      ),
    );
  }

  String? _blockText(MyReview mine) {
    if (mine.canReview) return null;
    return switch (mine.block) {
      ReviewBlock.noConversation =>
        'Chateá con la inmobiliaria sobre este inmueble para poder calificarlo.',
      ReviewBlock.awaitingReply =>
        'Podrás calificar cuando la inmobiliaria te responda o pasen 24 horas sin respuesta.',
      _ => 'Todavía no podés calificar este inmueble.',
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final reviews = _controller.reviews;
      final mine = _controller.mine;
      return Column(
        key: const ValueKey('reviews-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calificaciones', style: AndeanTypography.headlineMd),
          const SizedBox(height: 8),
          if (_controller.loading && reviews == null)
            const LinearProgressIndicator()
          else if (reviews == null)
            Text(
              _controller.message ?? 'No pudimos cargar las calificaciones.',
              key: const ValueKey('reviews-error'),
            )
          else ...[
            Text(
              'Inmueble: ${ratingSummaryText(reviews.listing)}',
              key: const ValueKey('listing-rating-summary'),
            ),
            const SizedBox(height: 4),
            Text(
              'Atención de ${reviews.agencyName}: ${ratingSummaryText(reviews.agency)}',
              key: const ValueKey('agency-rating-summary'),
            ),
            const SizedBox(height: 8),
            for (final review in reviews.reviews.take(_maxShown))
              ReviewTile(review: review),
            if (reviews.reviews.length > _maxShown)
              Text('Y ${reviews.reviews.length - _maxShown} más.'),
            TextButton(
              key: const ValueKey('open-agency-reviews'),
              onPressed: () => _openAgency(reviews),
              child: const Text('Ver todas las reseñas de la inmobiliaria'),
            ),
          ],
          if (mine != null) ...[
            const SizedBox(height: 8),
            if (_blockText(mine) != null)
              Text(_blockText(mine)!, key: const ValueKey('review-blocked'))
            else
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const ValueKey('open-review-form'),
                  onPressed: _openForm,
                  icon: const Icon(Icons.star_outline),
                  label: Text(
                    mine.review == null
                        ? 'Calificar'
                        : 'Editar mi calificación',
                  ),
                ),
              ),
          ] else if (widget.sessionController?.status !=
              CustomerSessionStatus.signedIn)
            const Text(
              'Iniciá sesión en Cuenta para calificar.',
              key: ValueKey('review-sign-in'),
            ),
        ],
      );
    },
  );
}
