import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/listing_photo.dart';
import 'staff_auth_failure.dart';

export '../models/listing_photo.dart';

/// HTTP client for the F04.2 photo routes of one listing
/// (`/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos`) and for
/// the signed upload to object storage.
///
/// The session token goes only to the API. The upload goes straight to the
/// storage with the signed link and never carries the token.
class StaffListingPhotosApi {
  StaffListingPhotosApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(seconds: 120),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  /// Bytes sent per chunk; progress is reported after each one.
  static const int uploadChunkBytes = 64 * 1024;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;
  final Duration uploadTimeout;

  Future<List<ListingPhoto>> listPhotos({
    required String accessToken,
    required String agencyId,
    required String listingId,
  }) async {
    final json = await _send(
      'GET',
      _photosPath(agencyId, listingId),
      accessToken: accessToken,
    );
    return _parse(() {
      final photos = (json as Map<String, Object?>)['photos'] as List<Object?>;
      return [
        for (final item in photos)
          ListingPhoto.fromJson(item as Map<String, Object?>),
      ];
    });
  }

  Future<PhotoUploadGrant> requestUpload({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required String contentType,
    required int sizeBytes,
  }) async {
    final json = await _send(
      'POST',
      _photosPath(agencyId, listingId),
      accessToken: accessToken,
      body: {'content_type': contentType, 'size_bytes': sizeBytes},
    );
    return _parse(
      () => PhotoUploadGrant.fromJson(json as Map<String, Object?>),
    );
  }

  /// Sends [bytes] to the signed link, reporting progress from 0 to 1.
  Future<void> upload({
    required PhotoUploadGrant grant,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.StreamedRequest('PUT', Uri.parse(grant.uploadUrl))
      ..headers.addAll(grant.headers)
      ..contentLength = bytes.length;
    final http.StreamedResponse response;
    try {
      final sending = _client.send(request);
      // The transport can fail while the body is still being written; observe
      // that failure now so it is reported by the await below, not as an
      // unhandled error in the meantime.
      unawaited(sending.then<void>((_) {}, onError: (Object _) {}));
      for (var start = 0; start < bytes.length; start += uploadChunkBytes) {
        final end = start + uploadChunkBytes < bytes.length
            ? start + uploadChunkBytes
            : bytes.length;
        request.sink.add(bytes.sublist(start, end));
        onProgress?.call(end / bytes.length);
      }
      await request.sink.close();
      response = await sending.timeout(uploadTimeout);
      await response.stream.drain<void>();
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The storage answers in XML, not the API envelope: keep only the status.
      throw failureFromResponse(statusCode: response.statusCode, body: '');
    }
    onProgress?.call(1);
  }

  Future<ListingPhoto> confirm({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required String photoId,
  }) async {
    final json = await _send(
      'POST',
      '${_photoPath(agencyId, listingId, photoId)}/confirm',
      accessToken: accessToken,
    );
    return _parse(() => ListingPhoto.fromJson(json as Map<String, Object?>));
  }

  Future<void> delete({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required String photoId,
  }) async {
    await _send(
      'DELETE',
      _photoPath(agencyId, listingId, photoId),
      accessToken: accessToken,
      expectBody: false,
    );
  }

  String _photosPath(String agencyId, String listingId) =>
      '/api/v1/staff/agencies/${Uri.encodeComponent(agencyId)}/listings/'
      '${Uri.encodeComponent(listingId)}/photos';

  String _photoPath(String agencyId, String listingId, String photoId) =>
      '${_photosPath(agencyId, listingId)}/${Uri.encodeComponent(photoId)}';

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw malformedResponseFailure();
    } on TypeError {
      throw malformedResponseFailure();
    }
  }

  Future<Object?> _send(
    String method,
    String path, {
    required String accessToken,
    Map<String, Object?>? body,
    bool expectBody = true,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }

    // FastAPI sends `application/json` without a charset; decode UTF-8.
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw failureFromResponse(statusCode: response.statusCode, body: text);
    }
    if (!expectBody) return null;
    if (text.isEmpty) throw malformedResponseFailure();
    try {
      return jsonDecode(text);
    } on FormatException {
      throw malformedResponseFailure();
    }
  }
}
