import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'staff_auth_failure.dart';

/// Remote state of a listing's scene.
sealed class RemoteSceneState {
  const RemoteSceneState();
}

/// The listing has a scene; [etag] identifies its revision on the server.
class RemoteScene extends RemoteSceneState {
  const RemoteScene({required this.document, required this.etag});

  final Map<String, Object?> document;
  final String? etag;
}

/// The listing exists but nobody saved a scene for it yet.
class NoRemoteScene extends RemoteSceneState {
  const NoRemoteScene();
}

/// Outcome of a conditional scene save.
sealed class SceneSaveResult {
  const SceneSaveResult();
}

/// The server accepted the document as revision [etag].
class SceneSaved extends SceneSaveResult {
  const SceneSaved({required this.etag});

  final String? etag;
}

/// The remote scene changed since the capture started (`412 scene_conflict`);
/// nothing was written. [currentEtag] is the revision now on the server, if any.
class SceneConflict extends SceneSaveResult {
  const SceneConflict({required this.currentEtag});

  final String? currentEtag;
}

/// HTTP client for the staff scene routes
/// (`/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/scene`).
///
/// Saves are conditional: a capture made from scratch only creates the scene
/// (`If-None-Match: *`) and an update only replaces the revision it started
/// from (`If-Match`), so a scene edited elsewhere is never silently lost.
class StaffSceneApi {
  StaffSceneApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<RemoteSceneState> fetch({
    required String accessToken,
    required String agencyId,
    required String listingId,
  }) async {
    final response = await _send(
      'GET',
      _scenePath(agencyId, listingId),
      accessToken: accessToken,
    );
    final text = _text(response);
    if (response.statusCode == 404 && _code(text) == 'scene_not_defined') {
      return const NoRemoteScene();
    }
    _ensureSuccess(response, text);
    return RemoteScene(
      document: _document(text),
      etag: response.headers['etag'],
    );
  }

  /// Saves [document] over [baseEtag]; a null [baseEtag] means the capture
  /// believes no scene exists yet.
  Future<SceneSaveResult> save({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required Map<String, Object?> document,
    required String? baseEtag,
  }) async {
    final response = await _send(
      'PUT',
      _scenePath(agencyId, listingId),
      accessToken: accessToken,
      body: document,
      headers: baseEtag == null
          ? const {'If-None-Match': '*'}
          : {'If-Match': baseEtag},
    );
    final text = _text(response);
    if (response.statusCode == 412) {
      return SceneConflict(currentEtag: response.headers['etag']);
    }
    _ensureSuccess(response, text);
    _document(text);
    return SceneSaved(etag: response.headers['etag']);
  }

  String _scenePath(String agencyId, String listingId) =>
      '/api/v1/staff/agencies/${Uri.encodeComponent(agencyId)}'
      '/listings/${Uri.encodeComponent(listingId)}/scene';

  String _text(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  String? _code(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        final code = decoded['code'];
        return code is String ? code : null;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  void _ensureSuccess(http.Response response, String text) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw failureFromResponse(statusCode: response.statusCode, body: text);
    }
  }

  Map<String, Object?> _document(String text) {
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
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        if (body != null) 'Content-Type': 'application/json',
        ...headers,
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
