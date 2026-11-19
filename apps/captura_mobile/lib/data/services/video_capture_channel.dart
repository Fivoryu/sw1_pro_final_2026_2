import 'package:flutter/services.dart';

import 'ar_capture_channel.dart';

/// Largest capture package the server accepts (`MAX_PACKAGE_BYTES`, 150 MiB).
const int maxCapturePackageBytes = 150 * 1024 * 1024;

/// Result of one native video walkthrough recording.
sealed class VideoCaptureResult {
  const VideoCaptureResult();
}

/// The agent finished the walkthrough and the phone built the schema 2
/// package (`docs/api/f07-capture-package.md`).
class VideoCaptured extends VideoCaptureResult {
  const VideoCaptured({
    required this.package,
    required this.hasReference,
    required this.duration,
    required this.reachedTimeLimit,
    required this.timestampSource,
  });

  /// The local ZIP; `keyframeCount` is the number of frames in `frames.jsonl`.
  final CapturePackageInfo package;

  /// Whether the agent marked a scale reference. Without one the plan is
  /// proportional (no real measurements).
  final bool hasReference;
  final Duration duration;

  /// The recording was cut at the 5 minute limit.
  final bool reachedTimeLimit;

  /// `realtime` or `unknown` (see the package contract).
  final String timestampSource;
}

class VideoCaptureCancelled extends VideoCaptureResult {
  const VideoCaptureCancelled();
}

/// The recording could not run; [message] is safe to show to the agent.
class VideoCaptureFailed extends VideoCaptureResult {
  const VideoCaptureFailed(this.code, this.message);

  final String code;
  final String message;
}

/// Native video walkthrough recorder (Camera2 + sensors, no ARCore).
abstract interface class VideoCapture {
  Future<VideoCaptureResult> record({
    required String listingId,
    String? ownerId,
    String? firstRoomName,
  });
}

/// [VideoCapture] backed by `VideoCaptureActivity` through
/// `roomforge/video_capture`.
class MethodChannelVideoCapture implements VideoCapture {
  MethodChannelVideoCapture({
    MethodChannel channel = const MethodChannel('roomforge/video_capture'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<VideoCaptureResult> record({
    required String listingId,
    String? ownerId,
    String? firstRoomName,
  }) async {
    final Map<Object?, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<Object?, Object?>('recordVideo', {
        'listingId': listingId,
        'ownerId': ?ownerId,
        'firstRoomName': ?firstRoomName,
      });
    } on MissingPluginException {
      return VideoCaptureFailed('unsupported', messageFor('unsupported'));
    } on PlatformException catch (error) {
      return VideoCaptureFailed(error.code, messageFor(error.code));
    }
    switch (reply?['outcome']) {
      case 'captured':
        return _captured(reply!);
      case 'cancelled':
        return const VideoCaptureCancelled();
      default:
        final code = reply?['code'];
        final wire = code is String ? code : 'recording_failed';
        final message = reply?['message'];
        return VideoCaptureFailed(
          wire,
          message is String && message.isNotEmpty ? message : messageFor(wire),
        );
    }
  }

  static VideoCaptureResult _captured(Map<Object?, Object?> reply) {
    final raw = reply['capturePackage'];
    try {
      if (raw is! Map) {
        throw const FormatException('Capture package must be a map');
      }
      final package = CapturePackageInfo.fromJson({
        for (final entry in raw.entries) '${entry.key}': _plain(entry.value),
      });
      final duration = reply['durationMs'];
      return VideoCaptured(
        package: package,
        hasReference: reply['hasReference'] == true,
        duration: Duration(milliseconds: duration is int ? duration : 0),
        reachedTimeLimit: reply['reachedTimeLimit'] == true,
        timestampSource: reply['timestampSource'] == 'realtime'
            ? 'realtime'
            : 'unknown',
      );
    } on FormatException {
      return VideoCaptureFailed(
        'invalid_package',
        messageFor('invalid_package'),
      );
    }
  }

  /// Spanish, agent-facing text for a native failure code.
  static String messageFor(String code) => switch (code) {
    'camera_permission_denied' =>
      'Sin permiso de cámara no podemos grabar el recorrido. Podés '
          'habilitarlo desde los ajustes.',
    'unsupported' => 'Este teléfono no puede grabar el recorrido.',
    'package_too_large' =>
      'El recorrido pesa más de 150 MB y no se puede subir. Grabá un '
          'recorrido más corto.',
    'invalid_package' => 'El paquete del recorrido llegó incompleto.',
    _ => 'No pudimos grabar el recorrido. Intentá de nuevo.',
  };

  static Object? _plain(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _plain(entry.value),
    },
    final List<Object?> list => [for (final item in list) _plain(item)],
    _ => value,
  };
}
