import 'package:flutter/foundation.dart';

import '../data/models/catalog_models.dart';
import '../data/services/catalog_api.dart';

/// Loading state of the first page of a catalog search.
enum CatalogLoadState { loading, ready, failed }

/// Owns the public catalog search: the active filters, the loaded pages and
/// the detail of one listing.
class CatalogController extends ChangeNotifier {
  CatalogController({required CatalogApi api}) : _api = api;

  final CatalogApi _api;

  CatalogFilters _filters = const CatalogFilters();
  CatalogLoadState _loadState = CatalogLoadState.loading;
  List<CatalogListing> _items = const [];
  String? _nextCursor;
  bool _loadingMore = false;
  String? _message;
  String? _loadMoreMessage;
  int _generation = 0;

  CatalogFilters get filters => _filters;
  CatalogLoadState get loadState => _loadState;
  List<CatalogListing> get items => _items;
  bool get hasMore => _nextCursor != null;
  bool get isLoadingMore => _loadingMore;

  /// User-facing notice when the first page failed.
  String? get message => _message;

  /// User-facing notice when a later page failed; loaded items are kept.
  String? get loadMoreMessage => _loadMoreMessage;

  /// Loads the first page for [filters], or again for the current filters.
  Future<void> search([CatalogFilters? filters]) async {
    final generation = ++_generation;
    _filters = filters ?? _filters;
    _loadState = CatalogLoadState.loading;
    _items = const [];
    _nextCursor = null;
    _loadingMore = false;
    _message = null;
    _loadMoreMessage = null;
    notifyListeners();

    try {
      final page = await _api.searchListings(filters: _filters);
      if (generation != _generation) return;
      _items = page.items;
      _nextCursor = page.nextCursor;
      _loadState = CatalogLoadState.ready;
    } on CustomerAuthFailure catch (failure) {
      if (generation != _generation) return;
      _loadState = CatalogLoadState.failed;
      _message = messageFor(failure);
    }
    notifyListeners();
  }

  /// Appends the next page of the current search, if any.
  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    _loadMoreMessage = null;
    notifyListeners();

    try {
      final page = await _api.searchListings(filters: _filters, cursor: cursor);
      if (generation != _generation) return;
      _items = [..._items, ...page.items];
      _nextCursor = page.nextCursor;
    } on CustomerAuthFailure catch (failure) {
      if (generation != _generation) return;
      _loadMoreMessage = messageFor(failure);
    }
    _loadingMore = false;
    notifyListeners();
  }

  /// Reads the public detail of [listingId], or why it could not be read.
  Future<({CatalogListingDetail? detail, String? message})> loadDetail(
    String listingId,
  ) async {
    try {
      return (detail: await _api.getListing(listingId), message: null);
    } on CustomerAuthFailure catch (failure) {
      return (detail: null, message: messageFor(failure));
    }
  }

  /// Spanish, user-facing text for a failed catalog call. The server detail
  /// is not shown: it is an English code such as `invalid_filter`.
  static String messageFor(CustomerAuthFailure failure) {
    if (failure.isNetworkFailure) return failure.detail;
    return switch (failure.statusCode) {
      400 => 'La lista cambió mientras la recorrías. Volvé a buscar.',
      404 => 'Este inmueble ya no está publicado.',
      422 => 'Revisá los filtros del catálogo.',
      _ => 'Ocurrió un error inesperado. Intentá de nuevo.',
    };
  }
}
