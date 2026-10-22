import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'customer_auth_failure.dart';

/// A listing scene document loaded from the public API.
sealed class SceneLoadResult {
  const SceneLoadResult();
}

/// The published listing has a scene: [document] matches the v1 contract.
class SceneReady extends SceneLoadResult {
  const SceneReady(this.document);

  final Map<String, Object?> document;
}

/// The published listing exists but has no scene yet; the caller must show
/// the same honest state as the catalog instead of a fake walkthrough.
class SceneNotDefined extends SceneLoadResult {
  const SceneNotDefined();
}

/// The scene could not be read: [failure] is always safe to show.
class SceneUnavailable extends SceneLoadResult {
  const SceneUnavailable(this.failure);

  final CustomerAuthFailure failure;
}

/// HTTP client for the public scene endpoint, `GET /api/v1/listings/{id}/scene`.
///
/// The scene needs no session: like the catalog, it only exposes published
/// listings, so no credentials are sent — and none ever reach the WebView.
class SceneApi {
  SceneApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Reads the scene document of [listingId], or why it could not be read.
  Future<SceneLoadResult> getScene(String listingId) async {
    final uri = Uri.parse('$_baseUrl/api/v1/listings/$listingId/scene');
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final failure = failureFromResponse(
          statusCode: response.statusCode,
          body: text,
        );
        if (failure.code == 'scene_not_defined') return const SceneNotDefined();
        return SceneUnavailable(failure);
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) {
        return SceneUnavailable(malformedResponseFailure());
      }
      return SceneReady(decoded);
    } on FormatException {
      return SceneUnavailable(malformedResponseFailure());
    } on TypeError {
      return SceneUnavailable(malformedResponseFailure());
    } on TimeoutException {
      return SceneUnavailable(networkFailure());
    } on SocketException {
      return SceneUnavailable(networkFailure());
    } on http.ClientException {
      return SceneUnavailable(networkFailure());
    }
  }
}
