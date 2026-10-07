import 'package:flutter/foundation.dart';

import '../data/services/photo_source.dart';
import '../data/services/staff_auth_failure.dart';
import '../data/services/staff_listing_photos_api.dart';
import 'staff_session_controller.dart';

/// Loading state of a listing's confirmed photos.
enum PhotosLoadState { loading, ready, failed }

/// State of one photo that is not confirmed yet.
enum PhotoUploadState { uploading, failed }

/// A photo on its way to the listing: request, upload, confirm.
class PhotoUpload {
  PhotoUpload._(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
  PhotoUploadState state = PhotoUploadState.uploading;
  double progress = 0;
  String? message;

  /// The reserved slot and its signed link; reused on retry while valid.
  PhotoUploadGrant? _grant;
}

enum _Stage { request, upload, confirm, delete }

/// Owns the F04.2 photos of one listing in the capture app.
///
/// Each new photo is uploaded straight to the storage with a signed link and
/// then confirmed by the API. A confirmed change returns the listing to draft
/// on the server, so [onListingChanged] lets the editor reflect it.
class ListingPhotosController extends ChangeNotifier {
  ListingPhotosController({
    required StaffListingPhotosApi api,
    required StaffSessionController session,
    required PhotoSource source,
    required this.listingId,
    this.onListingChanged,
    DateTime Function()? now,
  }) : _api = api,
       _session = session,
       _source = source,
       _now = now ?? DateTime.now;

  /// Same limits as the API.
  static const int maxPhotos = 10;
  static const int maxBytes = 5 * 1024 * 1024;

  static const String _noSessionMessage =
      'Tu cuenta no tiene una sesión activa. Volvé a ingresar.';

  final StaffListingPhotosApi _api;
  final StaffSessionController _session;
  final PhotoSource _source;
  final DateTime Function() _now;
  final String listingId;
  final VoidCallback? onListingChanged;

  PhotosLoadState _loadState = PhotosLoadState.loading;
  List<ListingPhoto> _photos = const [];
  final List<PhotoUpload> _uploads = [];
  String? _message;
  bool _disposed = false;

  PhotosLoadState get loadState => _loadState;
  List<ListingPhoto> get photos => _photos;
  List<PhotoUpload> get uploads => List.unmodifiable(_uploads);

  /// Last notice for a failure outside a single upload, if any.
  String? get message => _message;

  /// Confirmed photos plus uploads in progress or failed.
  int get count => _photos.length + _uploads.length;

  bool get isUploading =>
      _uploads.any((upload) => upload.state == PhotoUploadState.uploading);

  bool get canAdd => _loadState == PhotosLoadState.ready && count < maxPhotos;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ({String token, String agencyId})? _credentials() {
    final token = _session.accessToken;
    final agencyId = _session.account?.tenantId;
    if (token == null || agencyId == null) return null;
    return (token: token, agencyId: agencyId);
  }

  Future<void> load() async {
    _loadState = PhotosLoadState.loading;
    _message = null;
    _notify();
    final credentials = _credentials();
    if (credentials == null) {
      _loadState = PhotosLoadState.failed;
      _message = _noSessionMessage;
      _notify();
      return;
    }
    try {
      _photos = await _api.listPhotos(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
      );
      _loadState = PhotosLoadState.ready;
    } on StaffAuthFailure catch (failure) {
      _loadState = PhotosLoadState.failed;
      _message = _messageFor(failure, _Stage.request);
    }
    _notify();
  }

  /// Picks a photo from [origin] and uploads it; a cancel does nothing.
  Future<void> add(PhotoOrigin origin) async {
    if (!canAdd) return;
    _message = null;
    final PickedPhoto? picked;
    try {
      picked = await _source.pick(origin);
    } on UnsupportedPhotoFormat {
      _message = 'Elegí una foto JPG, PNG o WebP.';
      _notify();
      return;
    } on Exception {
      _message = 'No pudimos abrir la cámara o la galería.';
      _notify();
      return;
    }
    if (picked == null) {
      _notify();
      return;
    }
    if (picked.bytes.length > maxBytes) {
      _message = 'La foto pesa más de 5 MB. Elegí otra.';
      _notify();
      return;
    }
    final upload = PhotoUpload._(picked.bytes, picked.contentType);
    _uploads.add(upload);
    await _run(upload);
  }

  /// Tries a failed upload again, reusing its link while it is valid.
  Future<void> retry(PhotoUpload upload) async {
    if (!_uploads.contains(upload) || upload.state != PhotoUploadState.failed) {
      return;
    }
    await _run(upload);
  }

  /// Drops a failed upload and releases its reserved slot on the server.
  Future<void> discard(PhotoUpload upload) async {
    _uploads.remove(upload);
    final grant = upload._grant;
    final credentials = _credentials();
    _notify();
    if (grant == null || credentials == null) return;
    try {
      await _api.delete(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
        photoId: grant.photoId,
      );
    } on StaffAuthFailure {
      // The pending slot expires on its own after its upload window.
    }
  }

  /// Deletes a confirmed photo; false when the deletion failed.
  Future<bool> delete(String photoId) async {
    _message = null;
    final credentials = _credentials();
    if (credentials == null) {
      _message = _noSessionMessage;
      _notify();
      return false;
    }
    try {
      await _api.delete(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
        photoId: photoId,
      );
    } on StaffAuthFailure catch (failure) {
      _message = _messageFor(failure, _Stage.delete);
      _notify();
      return false;
    }
    _photos = [
      for (final photo in _photos)
        if (photo.photoId != photoId) photo,
    ];
    _notify();
    onListingChanged?.call();
    return true;
  }

  Future<void> _run(PhotoUpload upload) async {
    upload
      ..state = PhotoUploadState.uploading
      ..progress = 0
      ..message = null;
    _notify();
    final credentials = _credentials();
    if (credentials == null) {
      _fail(upload, _noSessionMessage);
      return;
    }

    var stage = _Stage.request;
    try {
      var grant = upload._grant;
      if (grant == null || !grant.expiresAt.isAfter(_now())) {
        grant = await _api.requestUpload(
          accessToken: credentials.token,
          agencyId: credentials.agencyId,
          listingId: listingId,
          contentType: upload.contentType,
          sizeBytes: upload.bytes.length,
        );
        upload._grant = grant;
      }
      stage = _Stage.upload;
      await _api.upload(
        grant: grant,
        bytes: upload.bytes,
        onProgress: (progress) {
          upload.progress = progress;
          _notify();
        },
      );
      stage = _Stage.confirm;
      final photo = await _api.confirm(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
        photoId: grant.photoId,
      );
      _uploads.remove(upload);
      _photos = [..._photos, photo];
      _notify();
      onListingChanged?.call();
    } on StaffAuthFailure catch (failure) {
      if (stage == _Stage.confirm &&
          (failure.statusCode == 422 || failure.statusCode == 404)) {
        // The API discarded the slot; a retry needs a new link.
        upload._grant = null;
      }
      _fail(upload, _messageFor(failure, stage));
    }
  }

  void _fail(PhotoUpload upload, String message) {
    upload
      ..state = PhotoUploadState.failed
      ..message = message;
    _notify();
  }

  /// Spanish, user-facing text for a failed photo call.
  static String _messageFor(StaffAuthFailure failure, _Stage stage) {
    if (failure.isNetworkFailure) return failure.detail;
    if (stage == _Stage.upload) {
      return 'No pudimos subir la foto. Reintentá.';
    }
    return switch (failure.statusCode) {
      401 => 'Tu sesión expiró. Cerrá sesión y volvé a ingresar.',
      403 =>
        'Tu cuenta no tiene permisos sobre los inmuebles de esta '
            'inmobiliaria.',
      404 => 'El inmueble o la foto ya no existe.',
      409 when stage == _Stage.request => 'Llegaste al máximo de 10 fotos.',
      409 => 'La subida no se completó. Reintentá.',
      422 =>
        'El archivo no es una foto válida (JPG, PNG o WebP de hasta 5 MB).',
      502 || 503 || 504 =>
        'El almacenamiento de fotos no está disponible. Intentá más tarde.',
      _ => 'Ocurrió un error inesperado. Intentá de nuevo.',
    };
  }
}
