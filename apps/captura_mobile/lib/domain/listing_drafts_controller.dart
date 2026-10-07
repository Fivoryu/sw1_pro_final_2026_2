import 'package:flutter/foundation.dart';

import '../data/models/staff_listing.dart';
import '../data/services/photo_source.dart';
import '../data/services/staff_auth_failure.dart';
import '../data/services/staff_listing_photos_api.dart';
import '../data/services/staff_listings_api.dart';
import 'listing_photos_controller.dart';
import 'staff_session_controller.dart';

/// Loading state of the agent's listing list.
enum ListingsLoadState { loading, ready, failed }

/// Owns the agent's F04 listings: one review status at a time, saving a draft,
/// submitting it for review and reading why it was last rejected.
///
/// The access token and the agency come from the staff session on every call,
/// so a renewed session is picked up without rebuilding this controller.
class ListingDraftsController extends ChangeNotifier {
  ListingDraftsController({
    required StaffListingsApi api,
    required StaffSessionController session,
    required StaffListingPhotosApi photosApi,
    required PhotoSource photoSource,
  }) : _api = api,
       _session = session,
       _photosApi = photosApi,
       _photoSource = photoSource;

  static const String _noAgencyMessage =
      'Tu cuenta no pertenece a una inmobiliaria con sesión activa. Volvé a '
      'ingresar.';

  final StaffListingsApi _api;
  final StaffSessionController _session;
  final StaffListingPhotosApi _photosApi;
  final PhotoSource _photoSource;

  ListingStatus _tab = ListingStatus.draft;
  ListingsLoadState _loadState = ListingsLoadState.loading;
  List<StaffListing> _listings = const [];
  String? _message;

  ListingStatus get tab => _tab;
  ListingsLoadState get loadState => _loadState;
  List<StaffListing> get listings => _listings;

  /// User-facing notice for the last failure, if any.
  String? get message => _message;

  /// Loads the listings of [status], or of the current tab when omitted.
  Future<void> load([ListingStatus? status]) async {
    _tab = status ?? _tab;
    _loadState = ListingsLoadState.loading;
    _message = null;
    notifyListeners();

    final credentials = _credentials();
    if (credentials == null) {
      _fail(_noAgencyMessage);
      return;
    }
    final requested = _tab;
    try {
      final listings = await _api.listListings(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        status: requested,
      );
      if (requested != _tab) return;
      _listings = listings;
      _loadState = ListingsLoadState.ready;
      notifyListeners();
    } on StaffAuthFailure catch (failure) {
      if (requested != _tab) return;
      _fail(messageFor(failure));
    }
  }

  /// Creates a draft, or replaces [listingId]; returns null on failure.
  Future<StaffListing?> save({
    String? listingId,
    required ListingDraftInput input,
  }) => _write((token, agencyId) {
    if (listingId == null) {
      return _api.createListing(
        accessToken: token,
        agencyId: agencyId,
        input: input,
      );
    }
    return _api.updateListing(
      accessToken: token,
      agencyId: agencyId,
      listingId: listingId,
      input: input,
    );
  });

  /// Sends a draft to the agency's review queue.
  Future<bool> submit(String listingId) async {
    final submitted = await _write(
      (token, agencyId) => _api.submitListing(
        accessToken: token,
        agencyId: agencyId,
        listingId: listingId,
      ),
    );
    return submitted != null;
  }

  /// Photos of one saved listing (F04.2), sharing this controller's session.
  ListingPhotosController photosFor(
    String listingId, {
    VoidCallback? onListingChanged,
  }) => ListingPhotosController(
    api: _photosApi,
    session: _session,
    source: _photoSource,
    listingId: listingId,
    onListingChanged: onListingChanged,
  );

  /// Reads the observation of the most recent rejection, if any.
  Future<String?> latestRejectionReason(String listingId) async {
    final credentials = _credentials();
    if (credentials == null) return null;
    try {
      final history = await _api.listTransitions(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
      );
      for (final entry in history.reversed) {
        if (entry.action == 'reject') return entry.observation;
      }
      return null;
    } on StaffAuthFailure {
      return null;
    }
  }

  Future<StaffListing?> _write(
    Future<StaffListing> Function(String token, String agencyId) call,
  ) async {
    _message = null;
    final credentials = _credentials();
    if (credentials == null) {
      _message = _noAgencyMessage;
      notifyListeners();
      return null;
    }
    try {
      return await call(credentials.token, credentials.agencyId);
    } on StaffAuthFailure catch (failure) {
      _message = messageFor(failure);
      notifyListeners();
      return null;
    }
  }

  ({String token, String agencyId})? _credentials() {
    final token = _session.accessToken;
    final agencyId = _session.account?.tenantId;
    if (token == null || agencyId == null) return null;
    return (token: token, agencyId: agencyId);
  }

  void _fail(String message) {
    _listings = const [];
    _loadState = ListingsLoadState.failed;
    _message = message;
    notifyListeners();
  }

  /// Spanish, user-facing text for a failed listing call.
  static String messageFor(StaffAuthFailure failure) {
    if (failure.isNetworkFailure) return failure.detail;
    return switch (failure.statusCode) {
      401 => 'Tu sesión expiró. Cerrá sesión y volvé a ingresar.',
      403 =>
        'Tu cuenta no tiene permisos sobre los inmuebles de esta '
            'inmobiliaria.',
      404 => 'El inmueble ya no existe.',
      // The API rejects a submission without a confirmed photo (F04.2).
      409 when failure.detail.contains('photo') =>
        'Agregá al menos una foto antes de enviar el inmueble a revisión.',
      409 =>
        'El inmueble cambió de estado mientras lo editabas. Actualizá '
            'la lista.',
      422 => 'Revisá los datos del inmueble.',
      _ => 'Ocurrió un error inesperado. Intentá de nuevo.',
    };
  }
}
