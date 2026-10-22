import 'dart:convert';

import 'package:captura_mobile/data/services/capture_draft_store.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';

/// [PendingUploadStore] kept in memory; records survive "restarts" because
/// tests share one instance between controllers.
class InMemoryPendingUploadStore implements PendingUploadStore {
  final Map<String, String> _files = {};

  String _key(String ownerId, String captureId) => '$ownerId/$captureId';

  @override
  Future<List<PendingCaptureUpload>> list(String ownerId) async => [
    for (final entry in _files.entries)
      if (entry.key.startsWith('$ownerId/'))
        PendingCaptureUpload.fromJson(
          jsonDecode(entry.value) as Map<String, Object?>,
        ),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> save(String ownerId, PendingCaptureUpload upload) async =>
      _files[_key(ownerId, upload.captureId)] = jsonEncode(upload.toJson());

  @override
  Future<void> delete(String ownerId, String captureId) async =>
      _files.remove(_key(ownerId, captureId));
}

/// [CapturePackageFiles] over an in-memory map of path to bytes.
class FakePackageFiles implements CapturePackageFiles {
  FakePackageFiles(Map<String, List<int>> files) : files = {...files};

  final Map<String, List<int>> files;
  final List<String> deleted = [];

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Stream<List<int>> open(String path) {
    final bytes = files[path];
    if (bytes == null) throw StateError('missing $path');
    // Two chunks so progress callbacks fire more than once.
    final half = bytes.length ~/ 2;
    return Stream.fromIterable([bytes.sublist(0, half), bytes.sublist(half)]);
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
    deleted.add(path);
  }
}
