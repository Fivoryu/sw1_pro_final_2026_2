import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/spatial/capture_upload.dart';
import 'staff_auth_failure.dart';

/// The server accepted the registration of a capture package.
class CaptureRegistration {
  const CaptureRegistration({
    required this.captureId,
    required this.status,
    required this.uploadUrl,
    this.expiresAt,
  });

  final String captureId;
  final RemoteCaptureStatus status;

  /// Short-lived signed URL the ZIP is PUT to.
  final String uploadUrl;
  final DateTime? expiresAt;
}

/// Server-side state of a capture package.
class CaptureStatusReport {
  const CaptureStatusReport({
    required this.captureId,
    required this.status,
    this.failureReason,
    this.warnings = const [],
  });

  final String captureId;
  final RemoteCaptureStatus status;

  /// Present when [status] is `failed`.
  final String? failureReason;
  final List<String> warnings;
}

/// The signed upload URL is no longer valid; registering again (idempotent by
/// capture id) hands out a fresh one.
class UploadUrlExpired extends StaffAuthFailure {
  const UploadUrlExpired()
    : super(
        code: 'upload_url_expired',
        detail: 'La subida venció. La retomamos desde el principio.',
      );
}

/// HTTP client for the staff capture routes
/// (`/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/captures`,
/// `docs/api/f07-capture-package.md`).
///
/// Failures reuse the staff vocabulary of [StaffAuthFailure] so callers treat
/// them like every other staff call.
class StaffCaptureApi {
  StaffCaptureApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.uploadTimeout = const Duration(minutes: 10),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Packages reach 150 MB: the PUT gets much longer than a JSON call.
  final Duration uploadTimeout;

  /// Registers the capture. Repeating it with the same [captureId] returns the
  /// same capture, so a retry never creates a second one.
  Future<CaptureRegistration> register({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required String captureId,
    required int sizeBytes,
  }) async {
    final response = await _send(
      'POST',
      _capturesPath(agencyId, listingId),
      accessToken: accessToken,
      body: {'captureId': captureId, 'sizeBytes': sizeBytes},
    );
    final json = _success(response);
    final id = json['captureId'];
    final status = RemoteCaptureStatus.fromWire(json['status']);
    final url = json['uploadUrl'];
    if (id is! String || status == null || url is! String || url.isEmpty) {
      throw malformedResponseFailure();
    }
    final expires = json['expiresAt'];
    return CaptureRegistration(
      captureId: id,
      status: status,
      uploadUrl: url,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
    );
  }

  /// PUTs the ZIP to [uploadUrl] (absolute, or relative to the API). The URL is
  /// signed, so the staff token is deliberately not sent: it must never reach
  /// an object-storage host. [onProgress] receives the bytes handed to the
  /// transport so far.
  Future<void> upload({
    required String uploadUrl,
    required Stream<List<int>> body,
    required int length,
    void Function(int sent)? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl/').resolve(uploadUrl);
    var sent = 0;
    final counted = body.map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent);
      return chunk;
    });
    final request = _StreamBodyRequest('PUT', uri, counted, length)
      ..headers['Content-Type'] = 'application/zip';
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(uploadTimeout),
      ).timeout(uploadTimeout);
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 410) {
      throw const UploadUrlExpired();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw failureFromResponse(
        statusCode: response.statusCode,
        body: _text(response),
      );
    }
  }

  /// Confirms the upload and queues the reconstruction (idempotent).
  Future<RemoteCaptureStatus> complete({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required String captureId,
  }) async {
    final response = await _send(
      'POST',
      '${_capturePath(agencyId, listingId, captureId)}/complete',
      accessToken: accessToken,
    );
    final status = RemoteCaptureStatus.fromWire(_success(response)['status']);
    if (status == null) throw malformedResponseFailure();
    return status;
  }

  Future<CaptureStatusReport> status({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required String captureId,
  }) async {
    final response = await _send(
      'GET',
      _capturePath(agencyId, listingId, captureId),
      accessToken: accessToken,
    );
    final json = _success(response);
    final status = RemoteCaptureStatus.fromWire(json['status']);
    final id = json['captureId'];
    if (status == null || id is! String) throw malformedResponseFailure();
    final reason = json['failureReason'];
    final warnings = json['warnings'];
    return CaptureStatusReport(
      captureId: id,
      status: status,
      failureReason: reason is String ? reason : null,
      warnings: warnings is List
          ? [
              for (final warning in warnings)
                if (warning is String) warning,
            ]
          : const [],
    );
  }

  String _capturesPath(String agencyId, String listingId) =>
      '/api/v1/staff/agencies/${Uri.encodeComponent(agencyId)}'
      '/listings/${Uri.encodeComponent(listingId)}/captures';

  String _capturePath(String agencyId, String listingId, String captureId) =>
      '${_capturesPath(agencyId, listingId)}/${Uri.encodeComponent(captureId)}';

  String _text(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  Map<String, Object?> _success(http.Response response) {
    final text = _text(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw failureFromResponse(statusCode: response.statusCode, body: text);
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      throw malformedResponseFailure();
    }
    throw malformedResponseFailure();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    required String accessToken,
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);

    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
  }
}

/// A request whose body is an existing stream with a known length, so a large
/// ZIP is read lazily with back-pressure instead of being buffered in memory.
class _StreamBodyRequest extends http.BaseRequest {
  _StreamBodyRequest(super.method, super.url, this._body, int length) {
    contentLength = length;
  }

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
