import 'dart:convert';
import 'dart:io';

import '../../domain/spatial/capture_upload.dart';

/// On-device storage of spatial capture drafts, keyed by staff account and
/// listing. Each account only sees and cleans its own drafts.
abstract interface class CaptureDraftStore {
  Future<Map<String, Object?>?> read(String ownerId, String listingId);

  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> draft,
  );

  Future<void> delete(String ownerId, String listingId);

  Future<List<String>> listingIds(String ownerId);

  /// Bytes used by [ownerId]'s drafts, so the agent can see the space taken.
  Future<int> sizeBytes(String ownerId);

  Future<String> saveTraceSource(
    String ownerId,
    String listingId,
    List<int> bytes,
    String contentType,
  );

  Future<List<int>?> readTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  );

  Future<void> deleteTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  );

  Future<void> deleteTraceSources(String ownerId, String listingId);
}

/// [CaptureDraftStore] with one JSON file per listing under
/// `spatial_captures/<staff id>/<listing id>.json`.
///
/// A draft survives app restarts and lost connectivity until the agent
/// removes it.
class FileCaptureDraftStore implements CaptureDraftStore {
  FileCaptureDraftStore({required Future<Directory> Function() root})
    : _root = root;

  final Future<Directory> Function() _root;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  @override
  Future<Map<String, Object?>?> read(String ownerId, String listingId) async {
    final file = await _file(ownerId, listingId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Falls through: the unreadable draft is kept aside below.
    }
    await file.rename('${file.path}.corrupt');
    return null;
  }

  /// Writes through a temporary file and a rename, so an interrupted write
  /// never leaves a half-written draft in place of the previous one.
  @override
  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> draft,
  ) async {
    final file = await _file(ownerId, listingId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(draft), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String ownerId, String listingId) async {
    final file = await _file(ownerId, listingId);
    if (await file.exists()) await file.delete();
    await deleteTraceSources(ownerId, listingId);
  }

  @override
  Future<List<String>> listingIds(String ownerId) async {
    final dir = await _ownerDir(ownerId);
    if (!await dir.exists()) return const [];
    final ids = <String>[];
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && name.endsWith('.json')) {
        ids.add(name.substring(0, name.length - '.json'.length));
      }
    }
    ids.sort();
    return ids;
  }

  @override
  Future<int> sizeBytes(String ownerId) async {
    final dir = await _ownerDir(ownerId);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  @override
  Future<String> saveTraceSource(
    String ownerId,
    String listingId,
    List<int> bytes,
    String contentType,
  ) async {
    _checkId(listingId);
    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw ArgumentError.value(contentType, 'contentType'),
    };
    final sourceId =
        '${DateTime.now().microsecondsSinceEpoch}-${bytes.length}.$extension';
    final file = await _traceFile(ownerId, listingId, sourceId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return sourceId;
  }

  @override
  Future<List<int>?> readTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  ) async {
    final file = await _traceFile(ownerId, listingId, sourceId);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> deleteTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  ) async {
    final file = await _traceFile(ownerId, listingId, sourceId);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteTraceSources(String ownerId, String listingId) async {
    _checkId(listingId);
    final owner = await _ownerDir(ownerId);
    final dir = Directory('${owner.path}/trace_sources/$listingId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Directory> _ownerDir(String ownerId) async {
    _checkId(ownerId);
    final root = await _root();
    return Directory('${root.path}/spatial_captures/$ownerId');
  }

  Future<File> _file(String ownerId, String listingId) async {
    _checkId(listingId);
    final dir = await _ownerDir(ownerId);
    return File('${dir.path}/$listingId.json');
  }

  Future<File> _traceFile(
    String ownerId,
    String listingId,
    String sourceId,
  ) async {
    _checkId(listingId);
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,160}$').hasMatch(sourceId) ||
        sourceId.contains('..')) {
      throw ArgumentError.value(sourceId, 'sourceId');
    }
    final owner = await _ownerDir(ownerId);
    return File('${owner.path}/trace_sources/$listingId/$sourceId');
  }

  void _checkId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be a plain identifier');
    }
  }
}

/// On-device record of capture packages still on their way to the server
/// (F07.5), keyed by staff account and capture id. Each account only sees and
/// removes its own.
abstract interface class PendingUploadStore {
  Future<List<PendingCaptureUpload>> list(String ownerId);

  Future<void> save(String ownerId, PendingCaptureUpload upload);

  Future<void> delete(String ownerId, String captureId);
}

/// [PendingUploadStore] with one JSON file per capture under
/// `capture_uploads/<staff id>/<capture id>.json`. Records survive app
/// restarts; each write goes through a temporary file and a rename.
class FilePendingUploadStore implements PendingUploadStore {
  FilePendingUploadStore({required Future<Directory> Function() root})
    : _root = root;

  final Future<Directory> Function() _root;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  @override
  Future<List<PendingCaptureUpload>> list(String ownerId) async {
    final dir = await _ownerDir(ownerId);
    if (!await dir.exists()) return const [];
    final uploads = <PendingCaptureUpload>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entry.readAsString());
        if (decoded is Map<String, Object?>) {
          uploads.add(PendingCaptureUpload.fromJson(decoded));
          continue;
        }
      } on FormatException {
        // Falls through: the unreadable record is kept aside below.
      }
      await entry.rename('${entry.path}.corrupt');
    }
    uploads.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return uploads;
  }

  @override
  Future<void> save(String ownerId, PendingCaptureUpload upload) async {
    final file = await _file(ownerId, upload.captureId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(upload.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String ownerId, String captureId) async {
    final file = await _file(ownerId, captureId);
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _ownerDir(String ownerId) async {
    _checkId(ownerId);
    final root = await _root();
    return Directory('${root.path}/capture_uploads/$ownerId');
  }

  Future<File> _file(String ownerId, String captureId) async {
    _checkId(captureId);
    final dir = await _ownerDir(ownerId);
    return File('${dir.path}/$captureId.json');
  }

  void _checkId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be a plain identifier');
    }
  }
}

/// [CapturePackageFiles] over the real file system.
class IoCapturePackageFiles implements CapturePackageFiles {
  const IoCapturePackageFiles();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Stream<List<int>> open(String path) => File(path).openRead();

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
