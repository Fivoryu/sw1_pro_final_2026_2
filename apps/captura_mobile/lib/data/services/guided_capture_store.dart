import 'dart:convert';
import 'dart:io';

/// On-device storage of guided capture checklists (F14.2), keyed by staff
/// account and listing. Which photo belongs to which room lives only here,
/// on the agent's phone: the API does not know about rooms.
abstract interface class GuidedCaptureStore {
  Future<Map<String, Object?>?> read(String ownerId, String listingId);

  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> checklist,
  );
}

class FileGuidedCaptureStore implements GuidedCaptureStore {
  FileGuidedCaptureStore({required Future<Directory> Function() root})
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
      // Falls through: an unreadable checklist starts over.
    }
    return null;
  }

  /// Writes through a temporary file and a rename, so an interrupted write
  /// never leaves a half-written checklist.
  @override
  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> checklist,
  ) async {
    final file = await _file(ownerId, listingId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(checklist), flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _file(String ownerId, String listingId) async {
    if (!_safeId.hasMatch(ownerId) || !_safeId.hasMatch(listingId)) {
      throw ArgumentError('Unsafe identifier');
    }
    final root = await _root();
    return File('${root.path}/guided_captures/$ownerId/$listingId.json');
  }
}

/// Keeps checklists in memory; for tests and for builds without storage.
class InMemoryGuidedCaptureStore implements GuidedCaptureStore {
  final Map<String, Map<String, Object?>> entries = {};

  @override
  Future<Map<String, Object?>?> read(String ownerId, String listingId) async {
    final entry = entries['$ownerId/$listingId'];
    return entry == null
        ? null
        : jsonDecode(jsonEncode(entry)) as Map<String, Object?>;
  }

  @override
  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> checklist,
  ) async {
    entries['$ownerId/$listingId'] =
        jsonDecode(jsonEncode(checklist)) as Map<String, Object?>;
  }
}
