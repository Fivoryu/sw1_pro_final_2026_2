import 'dart:convert';

/// Messages the WebView viewer may send through the `RoomForgeBridge`
/// JavaScript channel.
///
/// [ViewerBridgeMessage.tryParse] is strict: anything outside the agreed
/// message shapes is dropped (returns null), so a broken page can never
/// crash the host or inject unexpected state.
sealed class ViewerBridgeMessage {
  const ViewerBridgeMessage();

  /// Parses one channel payload; null when it is not a message we accept.
  static ViewerBridgeMessage? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final type = decoded['type'];
    if (type is! String) return null;
    return switch (type) {
      'ready' => const ViewerReady(),
      'scene_loaded' => _parseSceneLoaded(decoded),
      'load_error' => _parseLoadError(decoded),
      'selection' => _parseSelection(decoded),
      _ => null,
    };
  }

  static ViewerBridgeMessage? _parseSceneLoaded(Map<String, Object?> payload) {
    final objects = payload['objects'];
    if (objects is! List<Object?>) return null;
    final ids = <String>[];
    for (final object in objects) {
      if (object is! String) return null;
      ids.add(object);
    }
    return SceneLoaded(objectIds: ids);
  }

  static ViewerBridgeMessage? _parseLoadError(Map<String, Object?> payload) {
    final detail = payload['detail'];
    if (detail is! String || detail.isEmpty) return null;
    return ViewerLoadError(detail);
  }

  static ViewerBridgeMessage? _parseSelection(Map<String, Object?> payload) {
    final objectId = payload['objectId'];
    if (objectId is! String && objectId != null) return null;
    return ViewerSelection(objectId: objectId as String?);
  }
}

/// The viewer finished booting and can receive a scene document.
class ViewerReady extends ViewerBridgeMessage {
  const ViewerReady();
}

/// The scene document was rendered; [objectIds] are the selectable objects.
class SceneLoaded extends ViewerBridgeMessage {
  const SceneLoaded({required this.objectIds});

  final List<String> objectIds;
}

/// The viewer rejected or failed to render the scene document.
class ViewerLoadError extends ViewerBridgeMessage {
  const ViewerLoadError(this.detail);

  final String detail;
}

/// The customer tapped an object ([objectId] null clears the selection).
class ViewerSelection extends ViewerBridgeMessage {
  const ViewerSelection({required this.objectId});

  final String? objectId;
}
