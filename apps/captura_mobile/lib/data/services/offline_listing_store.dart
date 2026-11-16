import 'dart:convert';
import 'dart:io';

/// What the offline mode remembers about a listing: its id and a label.
/// Nothing else about the listing is stored on purpose.
class OfflineListing {
  const OfflineListing({required this.listingId, required this.label});

  factory OfflineListing.fromJson(Map<String, Object?> json) => OfflineListing(
    listingId: json['listing_id']! as String,
    label: json['label']! as String,
  );

  final String listingId;
  final String label;

  Map<String, Object?> toJson() => {'listing_id': listingId, 'label': label};
}

/// Local copy of the listings an account already downloaded, so a recording
/// can be started without network. Entries are kept per account; [read] only
/// returns the entries of the owner it is asked for.
abstract interface class OfflineListingStore {
  /// Listings of [ownerId] across every bucket, without duplicates.
  Future<List<OfflineListing>> read(String ownerId);

  /// Replaces the [bucket] (for example one review tab) of [ownerId].
  Future<void> write(
    String ownerId,
    String bucket,
    List<OfflineListing> listings,
  );

  /// Removes the cache of every account (sign-out, discarded session).
  Future<void> clear();
}

/// File-backed store: `offline_listings/<owner id>.json`, one map of
/// bucket to listings. Each write goes through a temporary file and a rename.
class FileOfflineListingStore implements OfflineListingStore {
  FileOfflineListingStore({required Future<Directory> Function() root})
    : _root = root;

  final Future<Directory> Function() _root;

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  @override
  Future<List<OfflineListing>> read(String ownerId) async {
    final file = await _file(ownerId);
    if (!await file.exists()) return const [];
    try {
      final buckets = await _readBuckets(file);
      final seen = <String>{};
      return [
        for (final bucket in buckets.values)
          for (final listing in bucket)
            if (seen.add(listing.listingId)) listing,
      ];
    } on Object {
      // An unreadable cache is just an empty one; it is rebuilt online.
      return const [];
    }
  }

  @override
  Future<void> write(
    String ownerId,
    String bucket,
    List<OfflineListing> listings,
  ) async {
    final file = await _file(ownerId);
    await file.parent.create(recursive: true);
    Map<String, List<OfflineListing>> buckets;
    try {
      buckets = await file.exists() ? await _readBuckets(file) : {};
    } on Object {
      buckets = {};
    }
    buckets[bucket] = listings;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        for (final entry in buckets.entries)
          entry.key: [for (final item in entry.value) item.toJson()],
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Map<String, List<OfflineListing>>> _readBuckets(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return {};
    return {
      for (final entry in decoded.entries)
        entry.key: [
          for (final item in entry.value! as List<Object?>)
            OfflineListing.fromJson(item! as Map<String, Object?>),
        ],
    };
  }

  Future<Directory> _dir() async {
    final root = await _root();
    return Directory('${root.path}/offline_listings');
  }

  Future<File> _file(String ownerId) async {
    if (!_safeId.hasMatch(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId', 'unsafe identifier');
    }
    final dir = await _dir();
    return File('${dir.path}/$ownerId.json');
  }
}
