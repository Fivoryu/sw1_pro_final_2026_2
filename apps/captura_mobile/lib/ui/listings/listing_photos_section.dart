import 'package:flutter/material.dart';

import '../../data/services/photo_source.dart';
import '../../domain/listing_photos_controller.dart';

const _tileSize = 112.0;

/// The «Fotos» part of the listing card (F04.2).
///
/// Without [controller] the listing is not saved yet and photos cannot be
/// added. [onAdd] and [onDelete] let the editor confirm first when the change
/// returns a reviewed listing to draft.
class ListingPhotosSection extends StatelessWidget {
  const ListingPhotosSection({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onDelete,
  });

  final ListingPhotosController? controller;
  final Future<void> Function(PhotoOrigin origin) onAdd;
  final Future<void> Function(String photoId) onDelete;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    final theme = Theme.of(context);
    if (controller == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fotos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Guardá el borrador para agregar fotos.',
            key: ValueKey('listing-photos-unsaved'),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fotos (${controller.count} de '
            '${ListingPhotosController.maxPhotos})',
            key: const ValueKey('listing-photos-title'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._content(context, controller),
        ],
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    ListingPhotosController controller,
  ) {
    final theme = Theme.of(context);
    switch (controller.loadState) {
      case PhotosLoadState.loading:
        return const [
          Center(
            child: CircularProgressIndicator(
              key: ValueKey('listing-photos-loading'),
            ),
          ),
        ];
      case PhotosLoadState.failed:
        return [
          Text(
            controller.message ?? '',
            key: const ValueKey('listing-photos-message'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('listing-photos-retry'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: controller.load,
            child: const Text('Reintentar'),
          ),
        ];
      case PhotosLoadState.ready:
        final uploads = controller.uploads;
        return [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in controller.photos)
                _PhotoTile(
                  key: ValueKey('listing-photo-${photo.photoId}'),
                  child: Image.network(
                    photo.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
                  action: IconButton.filledTonal(
                    key: ValueKey('listing-photo-delete-${photo.photoId}'),
                    tooltip: 'Borrar foto',
                    onPressed: controller.isUploading
                        ? null
                        : () => onDelete(photo.photoId),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              for (var index = 0; index < uploads.length; index++)
                _UploadTile(
                  key: ValueKey('listing-photo-upload-$index'),
                  index: index,
                  upload: uploads[index],
                  controller: controller,
                ),
              if (controller.canAdd)
                SizedBox(
                  width: _tileSize,
                  height: _tileSize,
                  child: OutlinedButton(
                    key: const ValueKey('listing-photos-add'),
                    onPressed: controller.isUploading
                        ? null
                        : () => _chooseOrigin(context),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined),
                        SizedBox(height: 4),
                        Text('Agregar foto', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'La primera foto es la portada del catálogo.',
            style: theme.textTheme.bodySmall,
          ),
          if (controller.message != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.message!,
              key: const ValueKey('listing-photos-message'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ];
    }
  }

  Future<void> _chooseOrigin(BuildContext context) async {
    final origin = await showModalBottomSheet<PhotoOrigin>(
      context: context,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('photo-origin-camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Cámara'),
            onTap: () => Navigator.of(context).pop(PhotoOrigin.camera),
          ),
          ListTile(
            key: const ValueKey('photo-origin-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galería'),
            onTap: () => Navigator.of(context).pop(PhotoOrigin.gallery),
          ),
        ],
      ),
    );
    if (origin != null) await onAdd(origin);
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({super.key, required this.child, required this.action});

  final Widget child;
  final Widget action;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _tileSize,
    height: _tileSize,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
        Positioned(top: 0, right: 0, child: action),
      ],
    ),
  );
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    super.key,
    required this.index,
    required this.upload,
    required this.controller,
  });

  final int index;
  final PhotoUpload upload;
  final ListingPhotosController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (upload.state == PhotoUploadState.uploading) {
      final percent = (upload.progress * 100).round();
      return SizedBox(
        width: _tileSize,
        height: _tileSize,
        child: Card(
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(value: upload.progress),
              const SizedBox(height: 8),
              Text('Subiendo $percent %'),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: _tileSize * 2 + 8,
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                upload.message ?? 'No pudimos subir la foto.',
                key: ValueKey('listing-photo-upload-message-$index'),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: ValueKey('listing-photo-retry-$index'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => controller.retry(upload),
                      child: const Text('Reintentar'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      key: ValueKey('listing-photo-discard-$index'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => controller.discard(upload),
                      child: const Text('Descartar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
