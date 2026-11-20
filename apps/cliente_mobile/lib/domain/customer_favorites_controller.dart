import 'package:flutter/foundation.dart';

import '../data/models/catalog_models.dart';
import '../data/models/favorite_models.dart';
import '../data/services/customer_auth_failure.dart';
import '../data/services/customer_favorites_api.dart';

/// Loading state of the favorites and saved searches of the signed-in customer.
enum FavoritesLoadState { idle, loading, ready, failed }

/// The signed-in customer's favorites and saved searches (F14.3).
///
/// [load] reads both lists after sign-in; [clear] forgets them on sign-out so
/// another customer on the same device never sees them. Marking a favorite is
/// optimistic and rolls back with a message when the server refuses it.
class CustomerFavoritesController extends ChangeNotifier {
  CustomerFavoritesController({required CustomerFavoritesApi api})
    : _api = api;

  final CustomerFavoritesApi _api;

  FavoritesLoadState _state = FavoritesLoadState.idle;
  List<FavoriteEntry> _favorites = const [];
  Set<String> _favoriteIds = const {};
  final Set<String> _pending = {};
  List<SavedSearch> _searches = const [];
  String? _message;
  int _generation = 0;
  bool _disposed = false;

  FavoritesLoadState get state => _state;
  List<FavoriteEntry> get favorites => _favorites;
  List<SavedSearch> get savedSearches => _searches;

  /// User-facing notice of the last failed load or change, if any.
  String? get message => _message;

  bool isFavorite(String listingId) => _favoriteIds.contains(listingId);

  /// Whether a change of [listingId] is still waiting for the server.
  bool isPending(String listingId) => _pending.contains(listingId);

  Future<void> load() async {
    final generation = ++_generation;
    _state = FavoritesLoadState.loading;
    _message = null;
    _notify();
    try {
      final favorites = await _api.listFavorites();
      final searches = await _api.listSavedSearches();
      if (generation != _generation) return;
      _setFavorites(favorites);
      _searches = searches;
      _state = FavoritesLoadState.ready;
    } on CustomerAuthFailure catch (failure) {
      if (generation != _generation) return;
      _state = FavoritesLoadState.failed;
      _message = messageFor(failure);
    }
    _notify();
  }

  /// Forgets everything; requests in flight are ignored when they return.
  void clear() {
    _generation++;
    _state = FavoritesLoadState.idle;
    _setFavorites(const []);
    _pending.clear();
    _searches = const [];
    _message = null;
    _notify();
  }

  /// Marks or unmarks [listing]; returns a message when the server refused.
  Future<String?> toggle(String listingId, {CatalogListing? listing}) async {
    if (_pending.contains(listingId)) return null;
    final generation = _generation;
    final wasFavorite = isFavorite(listingId);
    final previous = _favorites;
    _pending.add(listingId);
    if (wasFavorite) {
      _setFavorites([
        for (final entry in _favorites)
          if (entry.listingId != listingId) entry,
      ]);
    } else {
      _setFavorites([
        FavoriteEntry(
          listingId: listingId,
          favoritedAt: DateTime.now().toUtc(),
          available: listing != null,
          listing: listing,
        ),
        ..._favorites,
      ]);
    }
    _message = null;
    _notify();

    String? failureMessage;
    try {
      if (wasFavorite) {
        await _api.removeFavorite(listingId);
      } else {
        await _api.addFavorite(listingId);
      }
    } on CustomerAuthFailure catch (failure) {
      failureMessage = messageFor(failure);
    }
    if (generation != _generation) return null;
    _pending.remove(listingId);
    if (failureMessage != null) {
      _setFavorites(previous);
      _message = failureMessage;
    }
    _notify();
    return failureMessage;
  }

  /// Saves [filters] under [name]; returns a message when it was refused.
  Future<String?> saveSearch(String name, CatalogFilters filters) async {
    final generation = _generation;
    try {
      final saved = await _api.createSavedSearch(name.trim(), filters);
      if (generation != _generation) return null;
      _searches = [saved, ..._searches];
      _notify();
      return null;
    } on CustomerAuthFailure catch (failure) {
      return messageFor(failure);
    }
  }

  /// Deletes [search]; returns a message when it was refused.
  Future<String?> deleteSearch(SavedSearch search) async {
    final generation = _generation;
    try {
      await _api.deleteSavedSearch(search.id);
    } on CustomerAuthFailure catch (failure) {
      // Already gone on the server: the outcome the customer asked for.
      if (failure.statusCode != 404) return messageFor(failure);
    }
    if (generation != _generation) return null;
    _searches = [
      for (final item in _searches)
        if (item.id != search.id) item,
    ];
    _notify();
    return null;
  }

  void _setFavorites(List<FavoriteEntry> favorites) {
    _favorites = favorites;
    _favoriteIds = {for (final entry in favorites) entry.listingId};
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Spanish, user-facing text; the server detail is an English code.
  static String messageFor(CustomerAuthFailure failure) {
    if (failure.isNetworkFailure) return failure.detail;
    return switch ((failure.statusCode, failure.detail)) {
      (409, 'favorite_limit') =>
        'Llegaste al máximo de favoritos. Quitá alguno para agregar otro.',
      (409, 'saved_search_limit') =>
        'Llegaste al máximo de búsquedas guardadas. Borrá alguna para guardar otra.',
      (409, 'saved_search_name_taken') =>
        'Ya tenés una búsqueda guardada con ese nombre.',
      (401, _) => 'Tu sesión expiró. Iniciá sesión de nuevo en Cuenta.',
      (404, _) => 'Este inmueble ya no está publicado.',
      (422, _) => 'Revisá el nombre y los filtros de la búsqueda.',
      _ => 'Ocurrió un error inesperado. Intentá de nuevo.',
    };
  }
}
