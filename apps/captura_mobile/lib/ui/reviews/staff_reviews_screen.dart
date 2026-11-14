import 'package:flutter/material.dart';

import '../../data/models/staff_review.dart';
import '../../domain/staff_reviews_controller.dart';

/// Wording of the agency's rating summary. With fewer than three reviews
/// there is no average; the counts always appear next to it.
String staffRatingSummaryText(StaffRatingSummary summary) {
  if (summary.count == 0) return 'Sin calificaciones todavía';
  final counts =
      '${summary.count} ${summary.count == 1 ? 'calificación' : 'calificaciones'}, '
      '${summary.verifiedCount} ${summary.verifiedCount == 1 ? 'verificada' : 'verificadas'}';
  if (summary.fewRatings || summary.average == null) {
    return 'Pocas calificaciones ($counts)';
  }
  return '★ ${summary.average!.toStringAsFixed(1)} · $counts';
}

/// The agency's reviews. Agents read them; agency administrators also reply
/// (once per review) and report.
class StaffReviewsScreen extends StatefulWidget {
  const StaffReviewsScreen({super.key, required this.controller});

  final StaffReviewsController controller;

  @override
  State<StaffReviewsScreen> createState() => _StaffReviewsScreenState();
}

class _StaffReviewsScreenState extends State<StaffReviewsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  Future<void> _ask(
    StaffReview review, {
    required String title,
    required String action,
    required Future<bool> Function(String text) submit,
  }) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _TextDialog(title: title, action: action, submit: submit),
    );
    if (done != true && mounted && widget.controller.message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.controller.message!)));
    }
  }

  Widget _card(StaffReview review) => Card(
    key: ValueKey('review-${review.id}'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('Inmueble ${review.listingRating}/5'),
              Text('Atención ${review.agencyRating}/5'),
              if (review.verified)
                Chip(
                  key: ValueKey('verified-${review.id}'),
                  label: const Text('Verificada'),
                  visualDensity: VisualDensity.compact,
                ),
              if (review.reported)
                Chip(
                  key: ValueKey('reported-${review.id}'),
                  label: const Text('Reportada'),
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
            Text(
              'Tu respuesta: ${review.agencyReply}',
              key: ValueKey('reply-${review.id}'),
            ),
          ],
          if (widget.controller.canModerate)
            Wrap(
              spacing: 8,
              children: [
                if (review.agencyReply == null)
                  TextButton(
                    key: ValueKey('reply-button-${review.id}'),
                    onPressed: () => _ask(
                      review,
                      title: 'Responder reseña',
                      action: 'Responder',
                      submit: (text) => widget.controller.reply(review, text),
                    ),
                    child: const Text('Responder'),
                  ),
                if (!review.reported)
                  TextButton(
                    key: ValueKey('report-button-${review.id}'),
                    onPressed: () => _ask(
                      review,
                      title: 'Reportar reseña',
                      action: 'Reportar',
                      submit: (text) => widget.controller.report(review, text),
                    ),
                    child: const Text('Reportar'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reseñas')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            if (controller.state == ReviewsLoadState.loading &&
                controller.list == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = controller.list;
            if (list == null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  controller.message ?? 'No pudimos cargar las reseñas.',
                  key: const ValueKey('reviews-error'),
                ),
              );
            }
            return ListView(
              key: const ValueKey('reviews-content'),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Atención de la inmobiliaria: ${staffRatingSummaryText(list.summary)}',
                  key: const ValueKey('reviews-summary'),
                ),
                const SizedBox(height: 12),
                if (list.reviews.isEmpty)
                  const Text(
                    'Todavía no hay reseñas.',
                    key: ValueKey('reviews-empty'),
                  ),
                for (final review in list.reviews) _card(review),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// A dialog with one text field; it owns its controller so the field is not
/// disposed while the closing animation still draws it.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.action,
    required this.submit,
  });

  final String title;
  final String action;
  final Future<bool> Function(String text) submit;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('review-text'),
      controller: _field,
      maxLength: 1000,
      maxLines: 3,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('review-text-submit'),
        onPressed: () async {
          final ok = await widget.submit(_field.text);
          if (context.mounted) Navigator.of(context).pop(ok);
        },
        child: Text(widget.action),
      ),
    ],
  );
}
