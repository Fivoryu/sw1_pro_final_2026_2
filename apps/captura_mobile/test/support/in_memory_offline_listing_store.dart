import 'package:captura_mobile/data/services/offline_listing_store.dart';

/// [OfflineListingStore] kept in memory; tests share one instance to simulate
/// the phone's disk across controllers.
class InMemoryOfflineListingStore implements OfflineListingStore {
  final Map<String, Map<String, List<OfflineListing>>> data = {};

  @override
  Future<List<OfflineListing>> read(String ownerId) async {
    final seen = <String>{};
    return [
      for (final bucket in (data[ownerId] ?? const {}).values)
        for (final listing in bucket)
          if (seen.add(listing.listingId)) listing,
    ];
  }

  @override
  Future<void> write(
    String ownerId,
    String bucket,
    List<OfflineListing> listings,
  ) async {
    (data[ownerId] ??= {})[bucket] = listings;
  }

  @override
  Future<void> clear() async => data.clear();
}
