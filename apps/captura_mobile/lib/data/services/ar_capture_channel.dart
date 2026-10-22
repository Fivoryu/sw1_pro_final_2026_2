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
///
/// For a walkthrough the native side also builds the capture package
/// (`docs/api/f07-capture-package.md`): [capturePackage] describes the local
/// ZIP, or [packageProblem] says why there is none.
class ArCaptured extends ArCaptureResult {
  const ArCaptured(this.payload, {this.capturePackage, this.packageProblem});

  final Map<String, Object?> payload;
  final CapturePackageInfo? capturePackage;
  final String? packageProblem;
}

/// A room of the walkthrough session, as named on the phone.
class CapturePackageRoom {
  const CapturePackageRoom({required this.id, required this.name});

  final String id;
  final String name;
}

/// The finished capture package on the phone's storage.
class CapturePackageInfo {
  const CapturePackageInfo({
    required this.zipPath,
    required this.captureId,
    required this.sizeBytes,
    required this.keyframeCount,
    required this.droppedKeyframes,
    required this.failedKeyframes,
    required this.rooms,
  });

  /// Throws [FormatException] when [json] is not a valid package description.
  factory CapturePackageInfo.fromJson(Map<String, Object?> json) {
    String string(String key) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
      throw FormatException('Capture package "$key" must be a non-empty string');
    }

    int integer(String key, {required int min}) {
      final value = json[key];
      if (value is int && value >= min) return value;
      throw FormatException('Capture package "$key" must be an integer >= $min');
    }

    final rooms = json['rooms'];
    if (rooms is! List || rooms.isEmpty) {
      throw const FormatException('Capture package "rooms" must not be empty');
    }
    return CapturePackageInfo(
      zipPath: string('zipPath'),
      captureId: string('captureId'),
      sizeBytes: integer('sizeBytes', min: 1),
      keyframeCount: integer('keyframeCount', min: 0),
      droppedKeyframes: integer('droppedKeyframes', min: 0),
      failedKeyframes: integer('failedKeyframes', min: 0),
      rooms: [
        for (final room in rooms)
          if (room is Map && room['id'] is String && room['name'] is String)
            CapturePackageRoom(
              id: room['id']! as String,
              name: room['name']! as String,
            )
          else
            throw const FormatException(
              'Capture package room needs a string id and name',
            ),
      ],
    );
  }

  final String zipPath;
  final String captureId;
  final int sizeBytes;
  final int keyframeCount;

  /// Keyframes the phone could not write fast enough (dropped, not blocked).
  final int droppedKeyframes;
  final int failedKeyframes;
  final List<CapturePackageRoom> rooms;
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
    String? listingId,
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
    String? listingId,
  }) async {
    final Map<String, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<String, Object?>('captureRoom', {
        'roomName': roomName,
        'mode': mode.wire,
        'listingId': ?listingId,
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
      'captured' => _captured(_plain(reply!) as Map<String, Object?>),
      'cancelled' => const ArCaptureCancelled(),
      _ => () {
        final code = reply?['code'];
        final wire = code is String ? code : 'session_failed';
        return ArCaptureFailed(wire, messageFor(wire));
      }(),
    };
  }

  /// The room result plus, when present, the capture package. A malformed
  /// package never discards the room: it becomes a [ArCaptured.packageProblem].
  static ArCaptured _captured(Map<String, Object?> payload) {
    final raw = payload['capturePackage'];
    final error = payload['capturePackageError'];
    var problem = error is String ? error : null;
    CapturePackageInfo? info;
    if (raw != null) {
      try {
        if (raw is! Map<String, Object?>) {
          throw const FormatException('Capture package must be a map');
        }
        info = CapturePackageInfo.fromJson(raw);
      } on FormatException {
        problem = 'El paquete de captura llegó incompleto.';
      }
    }
    return ArCaptured(payload, capturePackage: info, packageProblem: problem);
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
