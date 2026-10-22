import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One capture as the fake server knows it.
class FakeCapture {
  FakeCapture(this.id, this.sizeBytes);

  final String id;
  final int sizeBytes;
  String status = 'awaiting_upload';
  String? failureReason;
  List<int>? uploaded;
}

/// In-memory staff capture endpoints (F07 capture package contract) plus the
/// signed object-storage URL the ZIP is PUT to.
class FakeCaptureBackend {
  final Map<String, FakeCapture> captures = {};
  final List<http.Request> requests = [];
  bool offline = false;

  /// Network errors on the next PUTs.
  int failPuts = 0;

  /// 403 (expired signature) on the next PUTs.
  int expirePuts = 0;

  /// `5xx` on the next `complete` calls.
  int failCompletes = 0;

  /// What `register` answers for a capture too large for the API.
  bool rejectRegistration = false;

  int registerCalls = 0;
  int putCalls = 0;
  int completeCalls = 0;

  /// Status a completed capture moves to when polled, in order.
  final List<(String, String?)> statusScript = [];

  http.Client get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    if (request.method == 'PUT' && request.url.host == 'storage.example.test') {
      return _put(request);
    }
    final register = RegExp(
      r'^/api/v1/staff/agencies/([^/]+)/listings/([^/]+)/captures$',
    );
    final single = RegExp(
      r'^/api/v1/staff/agencies/([^/]+)/listings/([^/]+)/captures/([^/]+)(/complete)?$',
    );
    if (request.method == 'POST' && register.hasMatch(path)) {
      return _register(request);
    }
    final match = single.firstMatch(path);
    if (match != null) {
      final capture = captures[match.group(3)];
      if (capture == null) {
        return _json({'detail': 'Capture not found', 'code': 'not_found'}, 404);
      }
      if (request.method == 'POST' && match.group(4) == '/complete') {
        return _complete(capture);
      }
      if (request.method == 'GET') return _status(capture);
    }
    return _json({'detail': 'unexpected', 'code': 'not_found'}, 404);
  });

  http.Response _register(http.Request request) {
    registerCalls += 1;
    if (rejectRegistration) {
      return _json({
        'detail': 'Capture package is too large',
        'code': 'validation_error',
      }, 422);
    }
    final body = jsonDecode(request.body) as Map<String, Object?>;
    final id = body['captureId']! as String;
    final existing = captures[id];
    final capture =
        existing ?? FakeCapture(id, (body['sizeBytes']! as num).toInt());
    captures[id] = capture;
    return _json({
      'captureId': id,
      'status': capture.status,
      'uploadUrl': 'https://storage.example.test/upload/$id?sig=$registerCalls',
      'expiresAt': '2026-10-21T13:00:00Z',
    }, existing == null ? 201 : 200);
  }

  http.Response _put(http.Request request) {
    putCalls += 1;
    if (failPuts > 0) {
      failPuts -= 1;
      throw http.ClientException('connection reset');
    }
    if (expirePuts > 0) {
      expirePuts -= 1;
      return http.Response('expired', 403);
    }
    final id = request.url.pathSegments.last;
    captures[id]!.uploaded = request.bodyBytes;
    return http.Response('', 200);
  }

  http.Response _complete(FakeCapture capture) {
    completeCalls += 1;
    if (failCompletes > 0) {
      failCompletes -= 1;
      return _json({'detail': 'down', 'code': 'dependency_unavailable'}, 503);
    }
    if (capture.status == 'awaiting_upload') capture.status = 'queued';
    return _json({'captureId': capture.id, 'status': capture.status}, 202);
  }

  http.Response _status(FakeCapture capture) {
    if (statusScript.isNotEmpty) {
      final (status, reason) = statusScript.removeAt(0);
      capture.status = status;
      capture.failureReason = reason;
    }
    return _json({
      'captureId': capture.id,
      'status': capture.status,
      if (capture.failureReason != null) 'failureReason': capture.failureReason,
      'warnings': <Object?>[],
    }, 200);
  }

  http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );
}
