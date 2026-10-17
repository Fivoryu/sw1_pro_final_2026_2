import 'package:flutter/foundation.dart';

import '../data/services/scene_api.dart';
import '../data/services/customer_auth_failure.dart';

/// Loading state of one listing's scene.
enum ViewerLoadState { loading, ready, notDefined, failed }

/// Owns the scene document of the walkthrough: it loads the scene from the
/// public API and exposes honest states when there is nothing to walk.
class ViewerController extends ChangeNotifier {
  ViewerController({required SceneApi api}) : _api = api;

  final SceneApi _api;

  ViewerLoadState _state = ViewerLoadState.loading;
  Map<String, Object?>? _document;
  String? _message;
  int _generation = 0;

  ViewerLoadState get state => _state;

  /// Scene document matching the v1 contract; only when [state] is ready.
  Map<String, Object?>? get document => _document;

  /// User-facing notice when the load failed.
  String? get message => _message;

  /// Loads the scene of [listingId]; a superseded load is discarded.
  Future<void> load(String listingId) async {
    final generation = ++_generation;
    _state = ViewerLoadState.loading;
    _document = null;
    _message = null;
    notifyListeners();

    final result = await _api.getScene(listingId);
    if (generation != _generation) return;
    switch (result) {
      case SceneReady(:final document):
        _document = document;
        _state = ViewerLoadState.ready;
      case SceneNotDefined():
        _state = ViewerLoadState.notDefined;
      case SceneUnavailable(:final failure):
        _state = ViewerLoadState.failed;
        _message = messageFor(failure);
    }
    notifyListeners();
  }

  /// Spanish, user-facing text for a failed scene load. The server detail is
  /// not shown: it is an English code such as `scene_not_defined`.
  static String messageFor(CustomerAuthFailure failure) {
    if (failure.isNetworkFailure) return failure.detail;
    return switch (failure.statusCode) {
      404 => 'Este inmueble ya no está publicado.',
      _ => 'No pudimos cargar el recorrido. Intentá de nuevo.',
    };
  }
}
