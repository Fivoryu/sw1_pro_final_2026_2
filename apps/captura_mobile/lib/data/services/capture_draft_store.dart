import 'dart:convert';
import 'dart:io';

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
    await for (final entry in dir.list()) {
      if (entry is File) total += await entry.length();
    }
    return total;
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

  void _checkId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be a plain identifier');
    }
  }
}
