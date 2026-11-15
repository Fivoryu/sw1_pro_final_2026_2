import 'package:flutter/material.dart';

import '../../../data/services/customer_reviews_api.dart';
import '../../../domain/listing_reviews_controller.dart';
import 'review_widgets.dart';

/// The agency's profile: its rating across all listings and every review.
class AgencyReviewsScreen extends StatefulWidget {
  const AgencyReviewsScreen({
    super.key,
    required this.api,
    required this.agencyId,
    required this.agencyName,
  });

  final CustomerReviewsApi api;
  final String agencyId;
  final String agencyName;

  @override
  State<AgencyReviewsScreen> createState() => _AgencyReviewsScreenState();
}

class _AgencyReviewsScreenState extends State<AgencyReviewsScreen> {
  late final AgencyReviewsController _controller = AgencyReviewsController(
    api: widget.api,
    agencyId: widget.agencyId,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.agencyName)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final reviews = _controller.reviews;
            if (_controller.loading && reviews == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (reviews == null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _controller.message ?? 'No pudimos cargar las reseñas.',
                  key: const ValueKey('agency-reviews-error'),
                ),
              );
            }
            return ListView(
              key: const ValueKey('agency-reviews-content'),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Atención: ${ratingSummaryText(reviews.summary)}',
                  key: const ValueKey('agency-profile-summary'),
                ),
                const SizedBox(height: 12),
                for (final review in reviews.reviews)
                  ReviewTile(review: review, showListingRating: false),
              ],
            );
          },
        ),
      ),
    ),
  );
}
