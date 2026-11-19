import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/services/ar_capture_channel.dart';
import '../../data/services/capture_draft_store.dart';
import '../../data/services/staff_auth_failure.dart';
import '../../data/services/staff_capture_api.dart';
import '../staff_session_controller.dart';
import 'capture_upload.dart';

/// What the upload is doing right now for one package.
enum UploadPhase { idle, registering, uploading, finishing, checking }

/// One package as the screen shows it.
class CaptureUploadItem {
  const CaptureUploadItem({
    required this.upload,
    this.phase = UploadPhase.idle,
    this.progress,
  });

  final PendingCaptureUpload upload;
  final UploadPhase phase;

  /// 0..1 while [phase] is [UploadPhase.uploading].
  final double? progress;
}

/// Sends the capture packages of one listing to the server and follows their
/// reconstruction (F07.5).
///
/// Every package is saved on the phone first and keeps its last completed
/// [UploadStage], so closing the app or losing the connection only pauses it:
/// the next run resumes from that stage. Registration, upload and `complete`
/// are idempotent on the server, so a retry never creates a second capture.
/// The local ZIP is deleted only after `complete` succeeded.
class CaptureUploadController extends ChangeNotifier {
  CaptureUploadController({
    required this.listingId,
    required StaffSessionController session,
    required StaffCaptureApi api,
    required PendingUploadStore store,
    required CapturePackageFiles files,
    DateTime Function()? now,
  }) : _session = session,
       _api = api,
       _store = store,
       _files = files,
       _now = now ?? DateTime.now;

  static const String noSessionMessage =
      'Tu cuenta no tiene una sesión activa. Volvé a ingresar.';
  static const String _offlineSessionMessage =
      'Modo sin conexión. El recorrido queda guardado en el teléfono y se '
      'envía cuando vuelva la red y se renueve tu sesión.';
  static const String _offlineMessage =
      'Sin conexión. El recorrido quedó guardado en el teléfono; se vuelve '
      'a intentar cuando tengas red.';
  static const String _localProblemMessage =
      'No pudimos leer el recorrido guardado en el teléfono. Reintentá.';
  static const String _missingFileMessage =
      'El archivo del recorrido ya no está en el teléfono. Volvé a capturar '
      'el ambiente.';

  final String listingId;
  final StaffSessionController _session;
  final StaffCaptureApi _api;
  final PendingUploadStore _store;
  final CapturePackageFiles _files;
  final DateTime Function() _now;

  List<PendingCaptureUpload> _uploads = [];
  Future<void>? _running;
  static final _activeListings = <String, Future<void>>{};
  String? _activeId;
  UploadPhase _phase = UploadPhase.idle;
  double? _progress;
  String? _message;
  bool _disposed = false;

  /// This listing's packages, oldest first.
  List<CaptureUploadItem> get items => [
    for (final upload in _uploads)
      if (upload.captureId == _activeId)
        CaptureUploadItem(upload: upload, phase: _phase, progress: _progress)
      else
        CaptureUploadItem(upload: upload),
  ];

  /// A problem that is not tied to one package (for example, no session).
  String? get message => _message;

  /// Whether a run is in progress.
  bool get busy => _running != null;

  /// Completes when the current run (if any) finished.
  Future<void> get idle => _running ?? Future<void>.value();

  /// The signed-in account, or the one of the stored session while the app
  /// is offline, so recordings can be queued without network.
  String? get _ownerId => _session.ownerId;
  String? get ownerId => _ownerId;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final owner = _ownerId;
    if (owner == null) return;
    final stored = await _store.list(owner);
    if (_ownerId != owner) return;
    _uploads = [
      for (final upload in stored)
        if (upload.listingId == listingId) upload,
    ];
    _notify();
  }

  /// Saves the package on the phone and starts sending it. The same
  /// capture id is never added twice.
  Future<bool> enqueue(CapturePackageInfo package) async {
    final owner = _ownerId;
    if (owner == null) {
      _message = noSessionMessage;
      _notify();
      return false;
    }
    final existing = _uploads
        .where((upload) => upload.captureId == package.captureId)
        .firstOrNull;
    if (existing != null) {
      if (existing.sizeBytes != package.sizeBytes ||
          existing.sha256 != package.sha256 ||
          (!existing.isSent && existing.zipPath != package.zipPath)) {
        throw StateError(
          'El captureId ya identifica otro archivo; se conservan ambas evidencias.',
        );
      }
      unawaited(_scheduleRetry().catchError((Object _) {}));
      return true;
    }
    final upload = PendingCaptureUpload(
      sha256: package.sha256,
      captureId: package.captureId,
      listingId: listingId,
      zipPath: package.zipPath,
      sizeBytes: package.sizeBytes,
      keyframeCount: package.keyframeCount,
      createdAt: _now(),
    );
    await _store.save(owner, upload);
    _uploads = [..._uploads, upload];
    _notify();
    unawaited(_scheduleRetry().catchError((Object _) {}));
    return true;
  }

  /// Sends whatever is pending and refreshes the server state of what was
  /// sent. Calls while a run is in progress join it instead of starting
  /// another, so nothing is uploaded twice.
  Future<void> retry() {
    final running = _running;
    if (running != null) return running;
    return _scheduleRetry();
  }

  /// Publishes the new turn synchronously so enqueue() cannot return before
  /// idle observes it. An enqueue during a run adds a turn after the listing's
  /// current tail; ordinary retry() calls continue to join existing work.
  Future<void> _scheduleRetry() {
    final owner = _ownerId;
    final key = '${owner ?? "none"}:$listingId';
    final active = _activeListings[key];
    // Reserve ownership before notifying listeners. Another controller may be
    // uploading this listing: wait, then read its persisted result and retry
    // anything still pending instead of joining with a stale in-memory queue.
    late final Future<void> operation;
    operation = Future<void>.microtask(() async {
      if (active != null) {
        try {
          await active;
        } on Object {
          // This run independently reloads the durable queue below.
        }
      }
      if (_ownerId != owner) {
        _message = noSessionMessage;
        return;
      }
      await _run();
    }).whenComplete(() {
      if (identical(_activeListings[key], operation)) {
        _activeListings.remove(key);
      }
      if (identical(_running, operation)) _running = null;
      _notify();
    });
    _activeListings[key] = operation;
    _running = operation;
    _notify();
    return operation;
  }

  Future<void> _run() async {
    _notify();
    try {
      final owner = _ownerId;
      if (owner != null) {
        // Disk is authoritative: background recovery and other screens can
        // advance stages or add captures while this controller is open.
        await load();
        if (_ownerId != owner) return;
      }
      final credentials = _credentials();
      if (owner == null || credentials == null) {
        // Offline mode has no access token on purpose: nothing is sent until
        // the session is renewed with network.
        _message = _session.isOffline
            ? _offlineSessionMessage
            : noSessionMessage;
        return;
      }
      _message = null;
      for (final upload in List.of(_uploads)) {
        if (_ownerId != owner || _credentials() == null) return;
        if (upload.isFinished) continue;
        _activeId = upload.captureId;
        if (upload.isSent) {
          await _refreshStatus(owner, credentials, upload);
        } else {
          await _send(owner, credentials, upload);
        }
      }
    } on StaffAuthFailure catch (failure) {
      _message = _describe(failure);
    } on Object {
      _message =
          'No se pudo leer o actualizar la cola de subidas. El recorrido y '
          'sus registros se conservan en el teléfono. Reintentá.';
    } finally {
      _activeId = null;
      _phase = UploadPhase.idle;
      _progress = null;
    }
  }

  Future<void> _send(
    String owner,
    ({String token, String agencyId}) credentials,
    PendingCaptureUpload start,
  ) async {
    var current = start;
    var reregistered = false;
    try {
      while (true) {
        if (_ownerId != owner || _credentials() == null) return;
        if (current.stage == UploadStage.local ||
            current.stage == UploadStage.registered) {
          final path = current.zipPath;
          if (path == null || !await _files.exists(path)) {
            current = await _save(
              owner,
              current.copyWith(permanent: true, lastError: _missingFileMessage),
            );
            return;
          }
        }
        switch (current.stage) {
          case UploadStage.local:
            _setPhase(current, UploadPhase.registering);
            final registration = await _api.register(
              accessToken: credentials.token,
              agencyId: credentials.agencyId,
              listingId: listingId,
              captureId: current.captureId,
              sizeBytes: current.sizeBytes,
              sha256: current.sha256,
            );
            if (registration.status != RemoteCaptureStatus.awaitingUpload) {
              final status = await _api.complete(
                accessToken: credentials.token,
                agencyId: credentials.agencyId,
                listingId: listingId,
                captureId: current.captureId,
              );
              current = await _save(
                owner,
                current.copyWith(
                  stage: UploadStage.completed,
                  remoteStatus: status,
                  clearUploadUrl: true,
                  clearLastError: true,
                ),
              );
              return;
            }
            current = await _save(
              owner,
              current.copyWith(
                stage: UploadStage.registered,
                uploadUrl: registration.uploadUrl,
                clearLastError: true,
              ),
            );
          case UploadStage.registered:
            _setPhase(current, UploadPhase.uploading, progress: 0);
            try {
              await _upload(current);
            } on UploadUrlExpired {
              if (reregistered) rethrow;
              // The signed URL timed out: registering again is idempotent and
              // hands out a fresh one.
              reregistered = true;
              final fresh = await _api.register(
                accessToken: credentials.token,
                agencyId: credentials.agencyId,
                listingId: listingId,
                captureId: current.captureId,
                sizeBytes: current.sizeBytes,
                sha256: current.sha256,
              );
              if (fresh.status != RemoteCaptureStatus.awaitingUpload) {
                // Registration alone is not a receipt. complete() verifies
                // uploadVerified and the capture identity before we advance.
                _setPhase(current, UploadPhase.finishing);
                final status = await _api.complete(
                  accessToken: credentials.token,
                  agencyId: credentials.agencyId,
                  listingId: listingId,
                  captureId: current.captureId,
                );
                current = await _save(
                  owner,
                  current.copyWith(
                    stage: UploadStage.completed,
                    remoteStatus: status,
                    clearUploadUrl: true,
                    clearLastError: true,
                  ),
                );
                // Retain the local ZIP, including if verification or saving fails.
                return;
              }
              final renewedUrl = fresh.uploadUrl;
              final renewedUri = renewedUrl == null
                  ? null
                  : Uri.tryParse(renewedUrl);
              if (renewedUrl == null ||
                  renewedUrl.trim().isEmpty ||
                  renewedUri == null ||
                  (renewedUri.hasScheme &&
                      ((renewedUri.scheme != 'http' &&
                              renewedUri.scheme != 'https') ||
                          renewedUri.host.isEmpty))) {
                throw malformedResponseFailure();
              }
              current = await _save(
                owner,
                current.copyWith(uploadUrl: renewedUrl),
              );
              continue;
            }
            current = await _save(
              owner,
              current.copyWith(
                stage: UploadStage.uploaded,
                clearLastError: true,
              ),
            );
          case UploadStage.uploaded:
            _setPhase(current, UploadPhase.finishing);
            RemoteCaptureStatus status;
            try {
              status = await _api.complete(
                accessToken: credentials.token,
                agencyId: credentials.agencyId,
                listingId: listingId,
                captureId: current.captureId,
              );
            } on StaffAuthFailure catch (failure) {
              if (failure.statusCode != 409 || reregistered) rethrow;
              final fresh = await _api.register(
                accessToken: credentials.token,
                agencyId: credentials.agencyId,
                listingId: listingId,
                captureId: current.captureId,
                sizeBytes: current.sizeBytes,
                sha256: current.sha256,
              );
              if (fresh.status != RemoteCaptureStatus.awaitingUpload) rethrow;
              reregistered = true;
              current = await _save(
                owner,
                current.copyWith(uploadUrl: fresh.uploadUrl),
              );
              await _upload(current);
              continue;
            }
            final path = current.zipPath;
            current = await _save(
              owner,
              current.copyWith(
                stage: UploadStage.completed,
                remoteStatus: status,
                clearZipPath: true,
                clearUploadUrl: true,
                clearLastError: true,
              ),
            );
            // Only now is the server the owner of the package.
            if (path != null) await _deleteQuietly(path);
          case UploadStage.completed:
            return;
        }
      }
    } on StaffAuthFailure catch (failure) {
      await _save(
        owner,
        current.copyWith(
          permanent: _isPermanent(failure),
          lastError: _describe(failure),
        ),
      );
    } on Object {
      // A local problem (for example, reading the ZIP): retryable, not fatal.
      await _save(owner, current.copyWith(lastError: _localProblemMessage));
    }
  }

  Future<void> _upload(PendingCaptureUpload upload) async {
    final url = upload.uploadUrl;
    final path = upload.zipPath;
    if (url == null || path == null) {
      throw const StaffAuthFailure(
        code: kInternalError,
        detail:
            'Falta la dirección de subida. La retomamos desde el principio.',
      );
    }
    var lastPercent = -1;
    await _api.upload(
      uploadUrl: url,
      body: _files.open(path),
      length: upload.sizeBytes,
      onProgress: (sent) {
        final fraction = (sent / upload.sizeBytes).clamp(0.0, 1.0);
        final percent = (fraction * 100).floor();
        if (percent == lastPercent && fraction < 1) return;
        lastPercent = percent;
        _progress = fraction;
        _notify();
      },
    );
  }

  Future<void> _refreshStatus(
    String owner,
    ({String token, String agencyId}) credentials,
    PendingCaptureUpload upload,
  ) async {
    _setPhase(upload, UploadPhase.checking);
    try {
      final report = await _api.status(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
        captureId: upload.captureId,
      );
      await _save(
        owner,
        upload.copyWith(
          remoteStatus: report.status,
          failureReason: report.failureReason,
          clearLastError: true,
        ),
      );
    } on StaffAuthFailure catch (failure) {
      // The last known state stays; only the problem is added.
      await _save(owner, upload.copyWith(lastError: _describe(failure)));
    }
  }

  /// Removes a finished or permanently failed package from the phone: its
  /// record and any ZIP still there.
  Future<void> dismiss(String captureId) async {
    final owner = _ownerId;
    if (owner == null) return;
    final matches = _uploads.where((u) => u.captureId == captureId);
    if (matches.isEmpty) return;
    final upload = matches.first;
    if (!upload.isFinished) return;
    final path = upload.zipPath;
    if (path != null) await _deleteQuietly(path);
    await _store.delete(owner, captureId);
    _uploads = [
      for (final current in _uploads)
        if (current.captureId != captureId) current,
    ];
    _notify();
  }

  Future<PendingCaptureUpload> _save(
    String owner,
    PendingCaptureUpload upload,
  ) async {
    await _store.save(owner, upload);
    _uploads = [
      for (final current in _uploads)
        if (current.captureId == upload.captureId) upload else current,
    ];
    _notify();
    return upload;
  }

  void _setPhase(
    PendingCaptureUpload upload,
    UploadPhase phase, {
    double? progress,
  }) {
    _activeId = upload.captureId;
    _phase = phase;
    _progress = progress;
    _notify();
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await _files.delete(path);
    } on Object {
      // A leftover ZIP is only wasted space; the upload already succeeded.
    }
  }

  /// A 4xx the agent cannot fix by waiting (too large, forbidden, not found)
  /// ends the retries. Auth, timeouts, throttling and 5xx stay retryable.
  bool _isPermanent(StaffAuthFailure failure) {
    final status = failure.statusCode;
    if (failure.isNetworkFailure || status == null) return false;
    if (status == 401 || status == 408 || status == 429) return false;
    return status >= 400 && status < 500;
  }

  String _describe(StaffAuthFailure failure) {
    if (failure is UploadConnectionFailure) return failure.detail;
    if (failure.isNetworkFailure) return _offlineMessage;
    if (failure.statusCode == 401) {
      return 'La sesión venció. Volvé a ingresar con la misma cuenta y '
          'reintentá la subida. El recorrido sigue guardado en el teléfono.';
    }
    return failure.detail;
  }

  ({String token, String agencyId})? _credentials() {
    final token = _session.accessToken;
    final agencyId = _session.account?.tenantId;
    if (token == null || agencyId == null) return null;
    return (token: token, agencyId: agencyId);
  }
}
