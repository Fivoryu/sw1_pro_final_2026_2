import 'package:flutter/material.dart';

/// A listing photo behind a short-lived signed link.
///
/// A link that fails to load (for example because it expired) falls back to
/// the neutral placeholder instead of an error.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({
    super.key,
    required this.url,
    required this.semanticLabel,
  });

  final String url;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    semanticLabel: semanticLabel,
    errorBuilder: (_, _, _) => const PhotoPlaceholder(),
  );
}

/// Neutral frame shown where a listing has no photo to show.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.image_outlined,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
