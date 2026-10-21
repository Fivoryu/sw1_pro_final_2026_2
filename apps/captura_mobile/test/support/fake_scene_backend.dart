import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory staff scene endpoint honoring the F07.5 revision preconditions.
class FakeSceneBackend {
  Map<String, Object?>? document;
  int revision = 0;
  bool offline = false;
  final List<http.Request> requests = [];

  /// Simulates an edit made elsewhere (for example in the panel editor).
  void editRemotely(Map<String, Object?> next) {
    document = next;
    revision += 1;
  }

  String get etag => '"$revision"';

  http.Client get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    if (request.method == 'GET') {
      if (document == null) {
        return _json({
          'detail': 'Scene is not defined for this listing',
          'code': 'scene_not_defined',
        }, 404);
      }
      return _json(document!, 200, etag: etag);
    }
    final ifMatch = request.headers['If-Match'];
    final ifNoneMatch = request.headers['If-None-Match'];
    final exists = document != null;
    final matches = ifMatch == null
        ? (ifNoneMatch != '*' || !exists)
        : exists && (ifMatch == '*' || ifMatch == etag);
    if (!matches) {
      return _json(
        {'detail': 'Scene revision mismatch', 'code': 'scene_conflict'},
        412,
        etag: exists ? etag : null,
      );
    }
    document = jsonDecode(request.body) as Map<String, Object?>;
    revision = exists ? revision + 1 : 1;
    return _json(document!, 200, etag: etag);
  });

  http.Response _json(Object body, int status, {String? etag}) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json', 'etag': ?etag},
      );
}
