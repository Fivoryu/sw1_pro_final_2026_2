import 'package:flutter/foundation.dart';

import '../data/services/video_capture_channel.dart';
import '../data/services/ar_capture_channel.dart';
import 'spatial/capture_upload_controller.dart';

/// Where the video walkthrough of one listing stands.
enum VideoCaptureStatus {
  idle,

  /// The native recorder is on screen.
  recording,

  /// The package was handed to the upload queue.
  sent,
  failed,
}

/// Runs one video walkthrough (F07, schema 2) and hands the finished package
/// to the existing [CaptureUploadController]: registration, signed upload and
/// completion, with its resumable stage machine, are not re-implemented here.
class VideoCaptureController extends ChangeNotifier {
  VideoCaptureController({
    required this.listingId,
    required VideoCapture capture,
    required CaptureUploadController uploads,
  }) : _capture = capture,
       _uploads = uploads;

  /// Shown whenever the walkthrough has no scale reference (S5).
  static const String noReferenceWarning =
      'Sin objeto de referencia el plano será proporcional: conserva las '
      'proporciones entre ambientes, pero no tendrá medidas reales.';

  static const String _timeLimitMessage =
      'La grabación se cortó a los 5 minutos.';
  static const String _sentMessage =
      'El recorrido se sube para reconstruir el inmueble; seguí el estado en '
      'la lista de recorridos.';

  final String listingId;
  final VideoCapture _capture;
  final CaptureUploadController _uploads;

  VideoCaptureStatus _status = VideoCaptureStatus.idle;
  String? _message;
  String? _warning;
  bool _disposed = false;
  CapturePackageInfo? _pendingPackage;
  String? _pendingOwnerId;
  CapturePackageInfo? get pendingPackage => _pendingPackage;

  VideoCaptureStatus get status => _status;
  String? get message => _message;

  /// Non-blocking warning about the last package (no reference).
  String? get warning => _warning;
  bool get busy => _status == VideoCaptureStatus.recording;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(VideoCaptureStatus status, {String? message, String? warning}) {
    _status = status;
    _message = message;
    _warning = warning;
    if (!_disposed) notifyListeners();
  }

  /// Opens the native recorder and queues the resulting package.
  Future<void> start({String? firstRoomName}) async {
    if (busy) return;
    if (listingId.trim().isEmpty) {
      _set(
        VideoCaptureStatus.failed,
        message: 'Falta la publicación del recorrido.',
      );
      return;
    }
    if (_uploads.ownerId == null) {
      _set(
        VideoCaptureStatus.failed,
        message: CaptureUploadController.noSessionMessage,
      );
      return;
    }
    final recordingOwner = _uploads.ownerId;
    _set(VideoCaptureStatus.recording);
    try {
      if (_pendingPackage != null) {
        if (_pendingOwnerId != recordingOwner) {
          _set(
            VideoCaptureStatus.failed,
            message: 'La captura se conserva para su cuenta original.',
          );
          return;
        }
        final queued = await _uploads.enqueue(_pendingPackage!);
        _set(
          queued ? VideoCaptureStatus.sent : VideoCaptureStatus.failed,
          message: queued
              ? _sentMessage
              : CaptureUploadController.noSessionMessage,
        );
        if (queued) _pendingPackage = null;
        return;
      }
      final result = await _capture.record(
        listingId: listingId,
        ownerId: recordingOwner,
        firstRoomName: firstRoomName,
      );
      switch (result) {
        case VideoCaptureCancelled():
          _set(VideoCaptureStatus.idle);
        case VideoCaptureFailed(:final message):
          _set(VideoCaptureStatus.failed, message: message);
        case VideoCaptured(
          :final package,
          :final hasReference,
          :final reachedTimeLimit,
        ):
          if (package.sizeBytes > maxCapturePackageBytes) {
            // The server rejects it permanently: do not queue what cannot be sent.
            _set(
              VideoCaptureStatus.failed,
              message: MethodChannelVideoCapture.messageFor(
                'package_too_large',
              ),
            );
            return;
          }
          _pendingPackage = package;
          _pendingOwnerId = recordingOwner;
          if (_uploads.ownerId != recordingOwner) {
            _set(
              VideoCaptureStatus.failed,
              message:
                  'La sesión cambió. La captura se conserva para su cuenta original.',
            );
            return;
          }
          if (!await _uploads.enqueue(package)) {
            _set(
              VideoCaptureStatus.failed,
              message: CaptureUploadController.noSessionMessage,
            );
            return;
          }
          _pendingPackage = null;
          _set(
            VideoCaptureStatus.sent,
            message: reachedTimeLimit
                ? '$_timeLimitMessage $_sentMessage'
                : _sentMessage,
            warning: hasReference ? null : noReferenceWarning,
          );
      }
    } on Object {
      _set(
        VideoCaptureStatus.failed,
        message: _pendingPackage == null
            ? 'No se pudo iniciar o finalizar la grabacion. Reintenta.'
            : 'El archivo se conserva en el telefono. Reintenta para guardarlo en la cola.',
      );
    }
  }
}
