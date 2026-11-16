import 'package:flutter/foundation.dart';

import '../data/services/video_capture_channel.dart';
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
      'Sin objeto de referencia el modelo quedará sin escala métrica: las '
      'medidas no serán reales hasta que alguien las corrija.';

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
    _set(VideoCaptureStatus.recording);
    final result = await _capture.record(
      listingId: listingId,
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
            message: MethodChannelVideoCapture.messageFor('package_too_large'),
          );
          return;
        }
        await _uploads.enqueue(package);
        _set(
          VideoCaptureStatus.sent,
          message: reachedTimeLimit
              ? '$_timeLimitMessage $_sentMessage'
              : _sentMessage,
          warning: hasReference ? null : noReferenceWarning,
        );
    }
  }
}
