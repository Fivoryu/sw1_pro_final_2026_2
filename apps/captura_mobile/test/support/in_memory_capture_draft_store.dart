import 'dart:convert';

import 'package:captura_mobile/data/services/capture_draft_store.dart';

/// [CaptureDraftStore] kept in memory, for widget tests that cannot wait on
/// real file I/O inside the fake-async zone.
class InMemoryCaptureDraftStore implements CaptureDraftStore {
  final Map<String, String> _files = {};
  final Map<String, List<int>> _sources = {};
  var _nextSource = 1;

  String _key(String ownerId, String listingId) => '$ownerId/$listingId';

  @override
  Future<Map<String, Object?>?> read(String ownerId, String listingId) async {
    final text = _files[_key(ownerId, listingId)];
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  @override
  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> draft,
  ) async => _files[_key(ownerId, listingId)] = jsonEncode(draft);

  @override
  Future<void> delete(String ownerId, String listingId) async =>
      await Future.wait([
        Future<void>(() => _files.remove(_key(ownerId, listingId))),
        deleteTraceSources(ownerId, listingId),
      ]);

  @override
  Future<List<String>> listingIds(String ownerId) async => [
    for (final key in _files.keys)
      if (key.startsWith('$ownerId/')) key.substring(ownerId.length + 1),
  ]..sort();

  @override
  Future<int> sizeBytes(String ownerId) async => [
    for (final entry in _files.entries)
      if (entry.key.startsWith('$ownerId/')) utf8.encode(entry.value).length,
    for (final entry in _sources.entries)
      if (entry.key.startsWith('$ownerId/')) entry.value.length,
  ].fold<int>(0, (total, size) => total + size);

  @override
  Future<String> saveTraceSource(
    String ownerId,
    String listingId,
    List<int> bytes,
    String contentType,
  ) async {
    final id = 'source-${_nextSource++}.${contentType.split('/').last}';
    _sources['$ownerId/$listingId/$id'] = [...bytes];
    return id;
  }

  @override
  Future<List<int>?> readTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  ) async => _sources['$ownerId/$listingId/$sourceId'];

  @override
  Future<void> deleteTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  ) async => _sources.remove('$ownerId/$listingId/$sourceId');

  @override
  Future<void> deleteTraceSources(String ownerId, String listingId) async {
    _sources.removeWhere((key, _) => key.startsWith('$ownerId/$listingId/'));
  }
}
