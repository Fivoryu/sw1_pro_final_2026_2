import 'package:flutter/services.dart';

/// Whether the device can run the ARCore capture.
enum ArAvailability { supported, supportedNotInstalled, unsupported, unknown }

/// How the agent captures a room.
enum CaptureMode {
  /// Walk around the room; walls are proposed from detected planes (S11).
  walkthrough('walkthrough'),

  /// Mark two floor points at the base of each wall (fallback).
  walls('walls');

  const CaptureMode(this.wire);

  final String wire;
}

/// Result of one native room capture.
sealed class ArCaptureResult {
  const ArCaptureResult();
}

/// The agent finished the capture. [payload] follows the channel contract in
/// `odd/tasks/f07-spatial-capture.md` (ARCore world metres, y up).
class ArCaptured extends ArCaptureResult {
  const ArCaptured(this.payload);

  final Map<String, Object?> payload;
}

class ArCaptureCancelled extends ArCaptureResult {
  const ArCaptureCancelled();
}

/// The capture could not run; [message] is safe to show to the agent.
class ArCaptureFailed extends ArCaptureResult {
  const ArCaptureFailed(this.code, this.message);

  final String code;
  final String message;
}

/// Native AR capture of one room.
abstract interface class ArCapture {
  Future<ArAvailability> availability();

  Future<ArCaptureResult> captureRoom(
    String roomName, {
    CaptureMode mode = CaptureMode.walls,
  });
}

/// [ArCapture] backed by `ArCaptureActivity` through `roomforge/ar_capture`.
class MethodChannelArCapture implements ArCapture {
  MethodChannelArCapture({
    MethodChannel channel = const MethodChannel('roomforge/ar_capture'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<ArAvailability> availability() async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'checkAvailability',
      );
      return switch (reply?['status']) {
        'supported' => ArAvailability.supported,
        'supported_not_installed' => ArAvailability.supportedNotInstalled,
        'unsupported' => ArAvailability.unsupported,
        _ => ArAvailability.unknown,
      };
    } on MissingPluginException {
      return ArAvailability.unsupported;
    } on PlatformException {
      return ArAvailability.unknown;
    }
  }

  @override
  Future<ArCaptureResult> captureRoom(
    String roomName, {
    CaptureMode mode = CaptureMode.walls,
  }) async {
    final Map<String, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<String, Object?>('captureRoom', {
        'roomName': roomName,
        'mode': mode.wire,
      });
    } on MissingPluginException {
      return ArCaptureFailed(
        'arcore_unavailable',
        messageFor('arcore_unavailable'),
      );
    } on PlatformException catch (error) {
      return ArCaptureFailed(error.code, messageFor(error.code));
    }
    return switch (reply?['outcome']) {
      'captured' => ArCaptured(_plain(reply!) as Map<String, Object?>),
      'cancelled' => const ArCaptureCancelled(),
      _ => () {
        final code = reply?['code'];
        final wire = code is String ? code : 'session_failed';
        return ArCaptureFailed(wire, messageFor(wire));
      }(),
    };
  }

  /// Spanish, agent-facing text for a native failure code.
  static String messageFor(String code) => switch (code) {
    'camera_permission_denied' =>
      'Sin permiso de cámara no podemos medir el ambiente. Podés seguir '
          'usando el resto de la app y habilitarlo desde los ajustes.',
    'arcore_unavailable' =>
      'Este teléfono no admite la captura espacial (ARCore).',
    'arcore_install_declined' =>
      'Para medir hace falta instalar Servicios de Google Play para RA.',
    _ => 'No pudimos abrir la sesión de captura. Intentá de nuevo.',
  };

  /// Platform maps arrive as `Map<Object?, Object?>`; the domain wants
  /// string-keyed JSON-like values.
  static Object? _plain(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _plain(entry.value),
    },
    final List<Object?> list => [for (final item in list) _plain(item)],
    _ => value,
  };
}
