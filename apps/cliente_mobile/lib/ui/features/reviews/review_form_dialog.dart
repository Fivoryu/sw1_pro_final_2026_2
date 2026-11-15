import 'package:flutter/material.dart';

import '../../../data/models/review_models.dart';
import '../../../domain/listing_reviews_controller.dart';

/// Opens the review form. [verified] tells whether the customer already
/// reserved this listing; without a reservation the form says that the
/// listing rating covers the publication and the 3D walkthrough.
Future<void> showReviewForm(
  BuildContext context, {
  required ListingReviewsController controller,
  required Review? existing,
  required bool verified,
  required String agencyName,
}) => showDialog<void>(
  context: context,
  builder: (_) => ReviewFormDialog(
    controller: controller,
    existing: existing,
    verified: verified,
    agencyName: agencyName,
  ),
);

class ReviewFormDialog extends StatefulWidget {
  const ReviewFormDialog({
    super.key,
    required this.controller,
    required this.existing,
    required this.verified,
    required this.agencyName,
  });

  final ListingReviewsController controller;
  final Review? existing;
  final bool verified;
  final String agencyName;

  @override
  State<ReviewFormDialog> createState() => _ReviewFormDialogState();
}

class _ReviewFormDialogState extends State<ReviewFormDialog> {
  late int _listingRating = widget.existing?.listingRating ?? 0;
  late int _agencyRating = widget.existing?.agencyRating ?? 0;
  late final TextEditingController _comment = TextEditingController(
    text: widget.existing?.comment ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_listingRating == 0 || _agencyRating == 0) {
      setState(() => _error = 'Elegí una nota de 1 a 5 para cada uno.');
      return;
    }
    final text = _comment.text.trim();
    final saved = await widget.controller.submit(
      listingRating: _listingRating,
      agencyRating: _agencyRating,
      comment: text.isEmpty ? null : text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.controller.message);
    }
  }

  Widget _picker({
    required String keyPrefix,
    required int value,
    required ValueChanged<int> onChanged,
  }) => Wrap(
    children: [
      for (var i = 1; i <= 5; i++)
        IconButton(
          key: ValueKey('$keyPrefix-$i'),
          tooltip: '$i de 5',
          icon: Icon(i <= value ? Icons.star : Icons.star_border),
          onPressed: () => onChanged(i),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tu calificación'),
    content: SingleChildScrollView(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inmueble'),
            if (!widget.verified)
              const Text(
                'Calificás la publicación y el recorrido 3D. La marca de verificada es para quien reservó.',
                key: ValueKey('review-unverified-note'),
              ),
            _picker(
              keyPrefix: 'listing-star',
              value: _listingRating,
              onChanged: (v) => setState(() => _listingRating = v),
            ),
            Text('Atención de ${widget.agencyName}'),
            _picker(
              keyPrefix: 'agency-star',
              value: _agencyRating,
              onChanged: (v) => setState(() => _agencyRating = v),
            ),
            TextField(
              key: const ValueKey('review-comment'),
              controller: _comment,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
              ),
            ),
            if (_error != null)
              Text(_error!, key: const ValueKey('review-error')),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => FilledButton(
          key: const ValueKey('review-submit'),
          onPressed: widget.controller.submitting ? null : _submit,
          child: const Text('Guardar'),
        ),
      ),
    ],
  );
}
