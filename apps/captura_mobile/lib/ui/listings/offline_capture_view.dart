import 'package:flutter/material.dart';

import '../../data/services/video_capture_channel.dart';
import '../../domain/listing_drafts_controller.dart';
import '../../domain/spatial/capture_upload.dart';
import '../../domain/staff_session_controller.dart';
import '../../domain/video_capture_controller.dart';
import '../spatial/video_capture_screen.dart';

const _actionMinSize = Size.fromHeight(48);

/// Narrow offline mode (S10): the app opened without network but with a
/// session already stored on this phone.
///
/// It shows only the listings downloaded before, lets the agent record a
/// walkthrough for one of them and lists the pending-upload queue. It reads no
/// server data and calls no API: the session has no access token until the
/// real refresh succeeds.
class OfflineCaptureView extends StatefulWidget {
  const OfflineCaptureView({
    super.key,
    required this.session,
    required this.drafts,
    this.videoCapture,
  });

  final StaffSessionController session;
  final ListingDraftsController drafts;

  /// Native recorder; the production channel when null.
  final VideoCapture? videoCapture;

  static const String notice =
      'Modo sin conexión: podés grabar; el envío se hará cuando vuelva la '
      'red.';

  @override
  State<OfflineCaptureView> createState() => _OfflineCaptureViewState();
}

class _OfflineCaptureViewState extends State<OfflineCaptureView> {
  late Future<List<PendingCaptureUpload>> _pending = widget.drafts
      .pendingUploads();

  Future<void> _record(String listingId) async {
    final uploads = widget.drafts.uploadsFor(listingId);
    if (uploads == null) return;
    await uploads.load();
    final recording = VideoCaptureController(
      listingId: listingId,
      capture: widget.videoCapture ?? MethodChannelVideoCapture(),
      uploads: uploads,
    );
    if (!mounted) {
      recording.dispose();
      uploads.dispose();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoCaptureScreen(controller: recording),
      ),
    );
    recording.dispose();
    uploads.dispose();
    if (mounted) {
      setState(() => _pending = widget.drafts.pendingUploads());
    }
  }

  String _label(String listingId) {
    for (final listing in widget.session.offlineListings) {
      if (listing.listingId == listingId) return listing.label;
    }
    return 'Inmueble guardado en el teléfono';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listings = widget.session.offlineListings;
    final canRecord = widget.drafts.supportsUploads;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Card(
          key: ValueKey('offline-notice'),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.cloud_off),
                SizedBox(width: 12),
                Expanded(child: Text(OfflineCaptureView.notice)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Inmuebles en este teléfono', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (listings.isEmpty)
          const Text(
            'Todavía no hay inmuebles guardados en este teléfono. Conectate '
            'a la red una vez y abrí tus inmuebles para poder grabar sin '
            'conexión.',
            key: ValueKey('offline-no-listings'),
          )
        else
          for (final listing in listings)
            Card(
              key: ValueKey('offline-listing-${listing.listingId}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(listing.label)),
                    if (canRecord) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        height: 48,
                        child: FilledButton.icon(
                          key: ValueKey('offline-record-${listing.listingId}'),
                          onPressed: () => _record(listing.listingId),
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text('Grabar'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text('Pendientes de envío', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<PendingCaptureUpload>>(
          future: _pending,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <PendingCaptureUpload>[];
            if (items.isEmpty) {
              return const Text(
                'No hay recorridos pendientes.',
                key: ValueKey('offline-queue-empty'),
              );
            }
            return Column(
              children: [
                for (final upload in items)
                  Card(
                    child: ListTile(
                      key: ValueKey('offline-pending-${upload.captureId}'),
                      leading: const Icon(Icons.schedule_send_outlined),
                      title: Text(_label(upload.listingId)),
                      subtitle: Text(
                        upload.stage == UploadStage.local
                            ? 'Guardado en el teléfono; se envía cuando '
                                  'vuelva la red.'
                            : 'En proceso de envío; se retoma cuando vuelva '
                                  'la red.',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('offline-retry'),
          style: FilledButton.styleFrom(minimumSize: _actionMinSize),
          onPressed: widget.session.restore,
          child: const Text('Reintentar conexión'),
        ),
      ],
    );
  }
}
