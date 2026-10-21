import 'package:flutter/foundation.dart';

import '../data/models/quote_models.dart';
import '../data/services/quote_api.dart';
import '../data/services/customer_auth_failure.dart';

/// Lifecycle of one quote request.
enum QuoteState { idle, creating, ready, failed }

/// Owns the quote request of one listing: selection of extras happens in the
/// UI; this controller only creates the snapshot and exposes honest failures.
class QuoteController extends ChangeNotifier {
  QuoteController({required QuoteApi api}) : _api = api;

  final QuoteApi _api;

  QuoteState _state = QuoteState.idle;
  QuoteSnapshot? _snapshot;
  String? _message;
  int _generation = 0;

  QuoteState get state => _state;

  /// The created snapshot; only meaningful when [state] is ready.
  QuoteSnapshot? get snapshot => _snapshot;

  /// User-facing notice when the request failed.
  String? get message => _message;

  /// Creates a snapshot quote; a superseded request is discarded.
  ///
  /// Returns the failure message, or null when the quote is ready.
  Future<String?> createQuote({
    required String listingId,
    required int offerVersion,
    List<String> extraIds = const [],
    String? displayCurrency,
  }) async {
    final generation = ++_generation;
    _state = QuoteState.creating;
    _message = null;
    notifyListeners();

    try {
      final snapshot = await _api.createQuote(
        listingId: listingId,
        offerVersion: offerVersion,
        extraIds: extraIds,
        displayCurrency: displayCurrency,
      );
      if (generation != _generation) return null;
      _snapshot = snapshot;
      _state = QuoteState.ready;
      notifyListeners();
      return null;
    } on CustomerAuthFailure catch (failure) {
      if (generation != _generation) return null;
      _state = QuoteState.failed;
      _message = messageFor(failure);
      notifyListeners();
      return _message;
    }
  }

  /// Spanish, user-facing text for a failed quote call. The server detail is
  /// not shown: it is an English code such as `offer_version_mismatch`.
  static String messageFor(CustomerAuthFailure failure) {
    if (failure.isNetworkFailure) return failure.detail;
    return switch (failure) {
      _ when failure.code == 'offer_version_mismatch' =>
        'El precio cambió mientras cotizabas. Volvé a intentarlo.',
      _ when failure.code == 'invalid_extras' =>
        'Los opcionales elegidos ya no están disponibles. Revisá la selección.',
      _ => switch (failure.statusCode) {
          404 => 'Este inmueble ya no está publicado.',
          429 => 'Estás cotizando demasiado rápido. Esperá un momento.',
          503 => 'El servicio de cotización no está disponible ahora.',
          _ => 'Ocurrió un error inesperado. Intentá de nuevo.',
        },
    };
  }
}
